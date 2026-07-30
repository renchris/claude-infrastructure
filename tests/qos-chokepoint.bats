#!/usr/bin/env bats
# qos-chokepoint.bats — row 13 (MACHINE_CAPACITY_V2.md §7). Proves the QoS band is applied at the
# bats INVOCATION chokepoint, and that the census can tell a covered box from an uncovered one.
#
# PROOF DISCIPLINE (from the exemplar's catches, non-negotiable):
#   · Every absence assertion has a POSITIVE CONTROL beside it (a test that the detector fires).
#   · Non-final `[[ ]]` / `(( ))` are errexit-EXEMPT and therefore DEAD as assertions — every one
#     carries `|| false` (memory bats-dead-assertions-errexit-exemptions).
#   · The runtime-priority tests read PRI from ps, not from the exec line: the exec line is what we
#     INTENDED, PRI is what the kernel DID.
#   · Bands are the empirically calibrated ones (2026-07-29): background tier PRI=4, undemoted
#     PRI=31, and `nice` ALONE does NOT leave the 31 band.
#
# RED-PROOF: see tests/README or the plan §7. The pre-change tree has no bin/cc-bats at all, so
# (i)-(vi) fail at file-not-found against a pristine `git archive` checkout — that is the RED. The
# census tests (vii)-(xi) RED against the pre-change tree too (no scripts/qos-census.sh).

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SHIM="$REPO/bin/cc-bats"
  CENSUS="$REPO/scripts/qos-census.sh"
  TMP="$BATS_TEST_TMPDIR"
  # HERMETICITY (required by the repo's test-hermeticity ratchet, and correct on its own merits):
  # qos-census.sh defaults its durable log to $HOME/.claude/logs/qos-census.jsonl, so an unfixtured
  # run would append to the OPERATOR's live census log and pollute the very AC1 accrual record this
  # suite exists to protect. Fixturing $HOME makes that structurally impossible rather than relying
  # on every test remembering --no-append.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  # HERMETICITY, second axis — the AMBIENT CC_BATS_* environment. Every seam this suite exercises is
  # read from the environment, so the suite's verdict silently depended on HOW IT WAS INVOKED. Run it
  # through `bin/cc-bats` (the obvious thing to do — CLAUDE.md tells rebuild sessions to put gate work
  # through the chokepoint) and the shim exports CC_BATS_ACTIVE=1; the shim UNDER TEST then hits its
  # own re-entrancy guard (bin/cc-bats:101), execs straight to real bats, and emits none of the
  # warnings (vi)/(vi-b) assert. Measured 2026-07-29 by the campaign coordinator: 16/16 green under
  # plain bats, 14/16 through the shim, with nothing in either output naming the harness as the
  # cause. A suite that tests a wrapper must not inherit that wrapper's own state — unset the whole
  # family so each test controls exactly the seams it sets via `run env ...` (per-invocation env is
  # unaffected by this).
  unset CC_BATS_ACTIVE CC_BATS_QOS CC_BATS_QOS_MODE CC_BATS_QUIET \
        CC_BATS_REAL CC_BATS_NICE CC_BATS_NICE_BIN CC_BATS_TASKPOLICY
  # A tiny bats corpus whose single test lives long enough to be observed by ps.
  mkdir -p "$TMP/t"
  cat > "$TMP/t/slow.bats" <<'EOF'
@test "occupies the scheduler long enough to be sampled" {
  /bin/sleep 4
}
EOF
}

# ── the shim resolves and does not recurse ────────────────────────────────────────────────────

@test "(i) shim execs the real bats and reports its version" {
  run /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ Bats ]] || false
}

@test "(ii) shim does NOT recurse when it is itself named 'bats' on PATH" {
  # The self-shadowing case: put a dir containing a `bats` -> cc-bats symlink FIRST on PATH.
  # A naive `command -v bats` implementation fork-bombs here; correct resolution skips itself.
  mkdir -p "$TMP/shimdir"
  ln -sf "$SHIM" "$TMP/shimdir/bats"
  run env PATH="$TMP/shimdir:$PATH" timeout 30 /bin/bash "$TMP/shimdir/bats" --version
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ Bats ]] || false
  # timeout(1) returns 124 on a hang — assert we did not merely get lucky on ordering.
  [ "$status" -ne 124 ] || false
}

@test "(iii) shim fails loudly (rc 127) when no real bats can be resolved" {
  run env CC_BATS_REAL=/nonexistent/bats /bin/bash "$SHIM" --version
  [ "$status" -eq 127 ] || false
  [[ "$output" =~ "cannot resolve the real bats" ]] || false
}

# ── the load-bearing runtime assertion: PRI, not the exec line ────────────────────────────────

@test "(iv) shim's bats descendants actually reach the BACKGROUND band (PRI<=10)" {
  if [ ! -x /usr/sbin/taskpolicy ]; then skip "taskpolicy(8) absent on this host"; fi
  /bin/bash "$SHIM" "$TMP/t/slow.bats" >/dev/null 2>&1 &
  local shim_pid=$!
  /bin/sleep 2
  # Collect PRI of every descendant of our own shim invocation — never a global bats grep, which
  # would pick up a sibling session's run and prove nothing about THIS shim.
  local pris
  pris=$(_descendant_pris "$shim_pid")
  kill "$shim_pid" 2>/dev/null || true
  wait "$shim_pid" 2>/dev/null || true
  [ -n "$pris" ] || false                                  # we must have observed something
  # every observed descendant must be in the background band
  local bad
  bad=$(printf '%s\n' "$pris" | awk '$1>10 {n++} END {print n+0}')
  [ "$bad" -eq 0 ] || false
}

@test "(v) POSITIVE CONTROL for (iv): the SAME probe reports PRI=31 with QoS switched off" {
  # Without this, (iv) could pass because _descendant_pris silently returns only demoted pids,
  # or because the host demotes everything. This proves the probe can SEE an undemoted proc.
  #
  # MEASURED CONSTRAINT: the background band is a ONE-WAY RATCHET. A child of a demoted parent
  # inherits pri=4, `taskpolicy -B -p` does not lift it, and there is no default/none clamp. So if
  # THIS SUITE is itself running demoted, an undemoted control is unconstructible and the test must
  # say that rather than fail — a bound that cannot be met from here can only convict falsely
  # (memory exoneration-bound-must-fit-what-it-bounds). Run the suite at normal priority to
  # exercise this control; test (xv) covers the demoted-caller path explicitly.
  local own
  own=$(ps -p $$ -o pri= 2>/dev/null | tr -d ' ')
  if [ -n "$own" ] && [ "$own" -le 10 ]; then
    skip "suite itself is in the background band (pri=$own); a full-priority control is unconstructible from here — see (xv)"
  fi
  CC_BATS_QOS=off /bin/bash "$SHIM" "$TMP/t/slow.bats" >/dev/null 2>&1 &
  local shim_pid=$!
  /bin/sleep 2
  local pris
  pris=$(_descendant_pris "$shim_pid")
  kill "$shim_pid" 2>/dev/null || true
  wait "$shim_pid" 2>/dev/null || true
  [ -n "$pris" ] || false
  local undemoted
  undemoted=$(printf '%s\n' "$pris" | awk '$1>10 {n++} END {print n+0}')
  [ "$undemoted" -gt 0 ] || false                          # the detector CAN see full priority
}

@test "(vi) CC_BATS_TASKPOLICY set-but-EMPTY is honoured verbatim and WARNS loudly" {
  # `${VAR:-}` cannot tell unset from set-empty; a seam that cannot turn a thing off is not a seam.
  run env CC_BATS_TASKPOLICY= /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false
  # The warning must name the measured fact (nice alone does not leave PRI 31), not a soft notice.
  [[ "$output" =~ "does NOT move PRI off 31" ]] || false
}

@test "(vi-b) CC_BATS_QUIET must NOT be able to silence the fully-inert case" {
  # PARTIAL may be quieted; NONE may never be. An inert QoS that prints nothing is the exact
  # failure mode this row exists to fix (R4).
  #
  # The first version of this test used PATH=/nonexistent to make QoS unavailable. That was a WRONG
  # PREMISE: it broke bats' own `#!/usr/bin/env bash` shebang (rc 127) instead of exercising the
  # NONE branch, so it proved nothing about quieting. Reaching NONE needs BOTH resolvers empty,
  # which is what the two set-but-empty seams are for.
  run env CC_BATS_QUIET=1 CC_BATS_TASKPOLICY= CC_BATS_NICE_BIN= /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false                                   # bats itself must still run
  [[ "$output" =~ "QoS NOT applied" ]] || false                  # and the warning must survive QUIET
}

@test "(xv) census reports AMBIENT-DEMOTED (not FAIL) when run from inside the background band" {
  # The one-way-ratchet path. A census fired from inside a gate cannot build a full-priority
  # control; it must degrade to a named state and still produce a population verdict, never a false
  # SIGNAL-DEAD. This is the test that (v)'s skip points at.
  if [ ! -x /usr/sbin/taskpolicy ]; then skip "taskpolicy(8) absent on this host"; fi
  run /usr/bin/nice -n 19 /usr/sbin/taskpolicy -c background \
      /bin/bash "$CENSUS" --json --no-append
  [ "$status" -ne 4 ] || false                                   # must NOT be SIGNAL-DEAD
  [[ "$output" =~ \"control\":\"AMBIENT-DEMOTED\" ]] || false
}

# ── the census must be a three-state verdict, never a boolean ─────────────────────────────────

@test "(vii) census reports NO-BURST (rc 3), not a pass, when nothing is in flight" {
  # The signal-death case: a quiet box has nothing to demote and naive arithmetic reads 100%.
  run env QOS_CENSUS_PATTERN=zzz-no-such-process QOS_CENSUS_NO_CONTROL=1 \
      /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 3 ] || false
  [[ "$output" =~ \"verdict\":\"NO-BURST\" ]] || false
}

@test "(viii) census emits a two-sided positive control result" {
  run /bin/bash "$CENSUS" --json --no-append
  # The control must ALWAYS be reported explicitly — a census that hides whether its own detector
  # was verified is the absence-without-existence-evidence failure (R6).
  [[ "$output" =~ \"control\": ]] || false
  if [ -x /usr/sbin/taskpolicy ]; then
    # OK when this suite runs at normal priority; AMBIENT-DEMOTED when it inherited the background
    # band (one-way ratchet — see (xv)). Both are honest; FAIL/NO-TASKPOLICY here are not.
    [[ "$output" =~ \"control\":\"OK\" ]] || [[ "$output" =~ \"control\":\"AMBIENT-DEMOTED\" ]] || false
  fi
}

@test "(ix) census exits SIGNAL-DEAD (rc 4) when its own classifier cannot separate the bands" {
  # Force the demoted band to be unreachable: a threshold of -1 means NOTHING classifies as
  # demoted, so the known-demoted control must fail and the run must refuse to report coverage.
  run env QOS_DEMOTED_PRI_MAX=-1 /bin/bash "$CENSUS" --json --no-append
  [ "$status" -eq 4 ] || false
  [[ "$output" =~ \"verdict\":\"SIGNAL-DEAD\" ]] || false
}

@test "(x) census never writes to the log when --no-append is given" {
  # NON-VACUITY GUARD. Caught by the RED-proof: against the pristine tree the census does not
  # exist, so `[ ! -f "$log" ]` passed trivially — the test would have gone green with the
  # artifact absent or broken. Assert the census actually RAN before believing its restraint.
  [ -f "$CENSUS" ] || false
  local log="$TMP/census.jsonl"
  run env QOS_CENSUS_LOG="$log" QOS_CENSUS_NO_CONTROL=1 /bin/bash "$CENSUS" --quiet --no-append
  [ "$status" -ne 127 ] || false          # 127 = never executed; that is not "did not append"
  [ ! -f "$log" ] || false
}

@test "(xi) census DOES append a durable timestamped row by default (AC1 accrual)" {
  # AC1 accrues from disk over time — a coverage number narrated at close time proves nothing,
  # because the property is only true during a burst (row 12's reconciler thesis).
  local log="$TMP/census.jsonl"
  run env QOS_CENSUS_LOG="$log" QOS_CENSUS_NO_CONTROL=1 /bin/bash "$CENSUS" --quiet
  [ -f "$log" ] || false
  run grep -c '"ts":' "$log"
  [ "$output" -ge 1 ] || false
}

@test "(xii) census rejects unknown args rather than silently ignoring them" {
  run /bin/bash "$CENSUS" --definitely-not-a-flag
  [ "$status" -eq 2 ] || false
}

# ── R1 guard: admission control must stay deleted ─────────────────────────────────────────────

@test "(xiii) neither new artifact polls load or sleeps on it (R1)" {
  # A shedder that WAITS amplifies. gate_admit cost ~2h sleeping/run and 5 gates self-starved.
  # This is the chokepoint version of row 1's own lint at postland-verify.sh:1154.
  #
  # NON-VACUITY GUARD. Caught by the RED-proof: `grep` on a NONEXISTENT file also returns
  # non-zero, so this asserted "clean" against a tree containing neither artifact. An absence
  # assertion whose subject may not exist is not an assertion (memory
  # absence-alarm-needs-existence-evidence).
  [ -f "$SHIM" ] || false
  [ -f "$CENSUS" ] || false
  run grep -nE 'loadavg|load average|gate_admit' "$SHIM"
  [ "$status" -ne 0 ] || false
  # the census may READ loadavg for the record, but must never sleep in a wait loop on it
  run grep -nE 'while.*load|until.*load' "$CENSUS"
  [ "$status" -ne 0 ] || false
}

@test "(xiv) POSITIVE CONTROL for (xiii): the guard's grep is live" {
  # A check whose own grep is broken reports clean forever. Prove the pattern matches when present.
  printf 'gate_admit() { :; }\n' > "$TMP/bait.sh"
  run grep -nE 'loadavg|load average|gate_admit' "$TMP/bait.sh"
  [ "$status" -eq 0 ] || false
}

# ── helper ────────────────────────────────────────────────────────────────────────────────────

# _descendant_pris <root-pid> — PRI of every live descendant, one per line.
# Walks the tree explicitly rather than grepping for "bats" globally: a global match would collect
# a CONCURRENT session's gate run and the test would assert nothing about this shim.
_descendant_pris() {
  local root="$1" frontier next pid
  frontier="$root"
  while [ -n "$frontier" ]; do
    next=""
    for pid in $frontier; do
      ps -p "$pid" -o pri= 2>/dev/null | tr -d ' ' | grep -E '^[0-9]+$' || true
      local kids
      kids=$(pgrep -P "$pid" 2>/dev/null | tr '\n' ' ')
      next="$next $kids"
    done
    frontier=$(printf '%s' "$next" | tr -s ' ' | sed 's/^ //;s/ $//')
  done
}
