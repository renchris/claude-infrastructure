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
#   · Bands are the empirically calibrated ones (re-measured 2026-07-30 for M1-rev): utility PRI=20
#     (the band the actuators now request), background/maintenance PRI=4, undemoted PRI=31, and
#     `nice` ALONE does NOT leave the 31 band — which is why nice is gone from both actuators.
#   · PRI assertions on DEMOTED procs test the exact clamp value, never a `<= N` range: Darwin
#     decays a busy undemoted proc as low as PRI 17, so a range up to 20 would make these tests
#     pass on undemoted work. A clamp PINS its value; that is what makes the equality safe.
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
  unset CC_BATS_ACTIVE CC_BATS_QOS CC_BATS_QOS_MODE CC_BATS_QOS_BAND CC_BATS_QUIET \
        CC_BATS_REAL CC_BATS_BAND CC_BATS_TASKPOLICY
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

@test "(iv) shim's bats descendants actually reach the UTILITY band (PRI==20)" {
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
  # every observed descendant must be pinned at the utility clamp value — not merely "low"
  local bad
  bad=$(printf '%s\n' "$pris" | awk '$1!=20 {n++} END {print n+0}')
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
  if [ -n "$own" ] && [ "$own" -le 20 ]; then
    skip "suite itself is in a demoted band (pri=$own); a full-priority control is unconstructible from here — see (xv)"
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
  undemoted=$(printf '%s\n' "$pris" | awk '$1>20 {n++} END {print n+0}')
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
  # NONE may never be quieted. An inert QoS that prints nothing is the exact failure mode this row
  # exists to fix (R4). M1-rev deleted the PARTIAL tier, so CC_BATS_TASKPOLICY= alone reaches NONE
  # — the reason removing the CC_BATS_NICE_BIN seam cost this suite no coverage.
  #
  # The first version of this test used PATH=/nonexistent to make QoS unavailable. That was a WRONG
  # PREMISE: it broke bats' own `#!/usr/bin/env bash` shebang (rc 127) instead of exercising the
  # NONE branch, so it proved nothing about quieting. The set-but-empty taskpolicy seam is what
  # actually reaches it.
  run env CC_BATS_QUIET=1 CC_BATS_TASKPOLICY= /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false                                   # bats itself must still run
  [[ "$output" =~ "QoS NOT applied" ]] || false                  # and the warning must survive QUIET
}

@test "(xv) census reports AMBIENT-DEMOTED (not FAIL) when run from inside a demoted band" {
  # The one-way-ratchet path. A census fired from inside a gate cannot build a full-priority
  # control; it must degrade to a named state and still produce a population verdict, never a false
  # SIGNAL-DEAD. This is the test that (v)'s skip points at.
  if [ ! -x /usr/sbin/taskpolicy ]; then skip "taskpolicy(8) absent on this host"; fi
  run /usr/sbin/taskpolicy -c utility \
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

# ── M1-rev: the band flip, and the tier that died with it ─────────────────────────────────────

@test "(xvi) M1-rev: FULL mode applies the UTILITY clamp — asserted on kernel PRI, not the exec line" {
  if [ ! -x /usr/sbin/taskpolicy ]; then skip "taskpolicy(8) absent on this host"; fi
  # A stand-in for the real bats that reports the shim's exported state AND the band the kernel
  # actually gave it. The exec line is what we intended; PRI is what happened.
  echo '#!/bin/bash' > "$TMP/fake-bats"
  echo 'echo "MODE=$CC_BATS_QOS_MODE BAND=$CC_BATS_QOS_BAND PRI=$(ps -o pri= -p $$ | tr -d " ")"' >> "$TMP/fake-bats"
  chmod +x "$TMP/fake-bats"
  run env CC_BATS_REAL="$TMP/fake-bats" /bin/bash "$SHIM"
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ MODE=FULL ]] || false
  [[ "$output" =~ BAND=utility ]] || false
  [[ "$output" =~ PRI=20 ]] || false          # 20 == BASEPRI_UTILITY, pinned
  # and the prefix must no longer carry nice(1) at all — it was measured decorative
  [[ ! "$output" =~ PRI=4 ]] || false
}

@test "(xvii) M1-rev: an invalid CC_BATS_BAND refuses the clamp but STILL RUNS bats" {
  # taskpolicy exits 64 on an unparseable clamp WITHOUT running the program, so an unvalidated band
  # would not merely fail to demote — it would stop the gate. The refusal must be loud AND harmless.
  echo '#!/bin/bash' > "$TMP/fake-bats"
  echo 'echo "MODE=$CC_BATS_QOS_MODE ran=yes"' >> "$TMP/fake-bats"
  chmod +x "$TMP/fake-bats"
  run env CC_BATS_REAL="$TMP/fake-bats" CC_BATS_BAND=definitely-not-a-clamp /bin/bash "$SHIM"
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ ran=yes ]] || false                 # the gate still ran
  [[ "$output" =~ MODE=NONE ]] || false
  [[ "$output" =~ "QoS NOT applied" ]] || false       # and said so
}

@test "(xviii) M1-rev: the nice-only PARTIAL tier is UNREACHABLE, not merely unused" {
  # The tier fell back to something measured to demote nothing. Removing it means no seam
  # combination may still produce it — otherwise the dead code is just hidden.
  echo '#!/bin/bash' > "$TMP/fake-bats"
  echo 'echo "MODE=$CC_BATS_QOS_MODE"' >> "$TMP/fake-bats"
  chmod +x "$TMP/fake-bats"
  run env CC_BATS_REAL="$TMP/fake-bats" CC_BATS_TASKPOLICY= /bin/bash "$SHIM"
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ MODE=NONE ]] || false
  [[ ! "$output" =~ PARTIAL ]] || false
  # Assert on the CODE marker, not the bare word: the header comment explaining the tier's removal
  # legitimately contains "PARTIAL", and a grep for prose would fail for the wrong reason.
  run grep -c 'QOS_MODE="PARTIAL"' "$SHIM"
  [ "$output" -eq 0 ] || false                        # no assignment can produce the tier
}

# ── M1-rev: the census classifier must reject a DECAYED undemoted PRI ──────────────────────────

# _marker_script <name> — write a uniquely-named sleeper whose ARGS will carry <name> (the census
# greps the full args line) and print its path. The caller starts it in ITS OWN shell, never via
# `$(...)`: a background job started inside a command substitution belongs to that subshell, so the
# pid it reports is not the caller's child and the proc is not reliably observable afterwards.
# No `exec` in the script — the wrapper must survive, because it is the proc carrying <name>.
# CONCURRENCY NOTE: the fleet demonstrably runs this suite in parallel with itself (observed
# 2026-07-30 — a sibling session running `bats tests/qos-chokepoint.bats tests/capacity-alarm.bats`
# while this suite ran), so two live markers can share one name and both land in the census
# population. The assertions below are written to be COLLISION-SAFE rather than relying on a unique
# name: a neighbour's marker is always in the same band as ours, so it can only add to the tier we
# already assert `>= 1` on, and (xix)'s reject-side clamp set is `actual + 1`, a value no marker can
# occupy. A $$-suffixed name was tried and abandoned — it did not survive the census's pattern seam
# inside bats, and an unverified mechanism guarding a negligible risk is worse than none.
#
# THE PATH SHAPE IS LOAD-BEARING, NOT COSMETIC (fixed 2026-07-31). The marker must live at
# `<dir>/libexec/bats-core/bats-exec-*` because the SHIPPED census is strict by default and admits a
# row only when argv field 5 or 6 matches that libexec shape (§9.7's POSITIONAL discriminator,
# `qos-census.sh:256`). A marker at a plain `$TMP/<name>` path is invisible to it: measured on this
# box, the same live proc reads `procs_total:0` under the shipped default and `procs_total:1` under
# `QOS_CENSUS_STRICT=off`. That is why (xix)/(xx) failed on trunk — they were written against the
# M1-rev clamp classifier (`2514226e`, 01:51) while the discriminator that narrows the population had
# landed 45 min EARLIER from a parallel session (`bfe4da1e`, 01:06); the merge was textually clean and
# semantically broken, so the tests asserted on a population the shipped tool cannot see. Keep this
# shape, or fix the tests against `QOS_CENSUS_STRICT=off` — never assert a non-shipped configuration.
_marker_script() {
  local name="$1"
  local d="$TMP/$name/libexec/bats-core"
  mkdir -p "$d"
  echo '#!/bin/bash' > "$d/bats-exec-test"
  echo '/bin/sleep 6' >> "$d/bats-exec-test"
  chmod +x "$d/bats-exec-test"
  printf '%s' "$d/bats-exec-test"
}

@test "(xix) M1-rev: the CLAMP FILTER decides, not the ceiling — admit and reject, same proc" {
  # THE MEASURED HAZARD (2026-07-30): Darwin decays a busy UNDEMOTED proc's PRI as low as 17, so a
  # bare `pri <= 20` ceiling counts undemoted work as demoted — over-reported coverage, a false PASS.
  # The fix is to require a CLAMP-PINNED value, and this proves the filter is what rejects.
  #
  # The marker is PINNED to the background clamp rather than inheriting this suite's band. Two
  # reasons, both learned the hard way here: (1) an inherited band is not deterministic — the suite
  # runs demoted through the shim in some contexts and undemoted in others, so a test keyed on the
  # marker's OWN measured PRI is flaky by construction; (2) `background` is reachable from ANY band
  # because a clamp only ever lowers, so PRI 4 is guaranteed. That also makes the test collision-safe
  # against a concurrent run of this same suite: every zzqosmark marker anywhere is PRI 4.
  #
  # The ceiling is raised to 99 so the RANGE always admits. The only thing that can then reject is
  # the clamp SET — which is exactly the mechanism under test.
  local mk; mk=$(_marker_script zzqosmark)
  /usr/sbin/taskpolicy -c background /bin/bash "$mk" >/dev/null 2>&1 &
  local pid=$!
  /bin/sleep 1
  local actual; actual=$(ps -o pri= -p "$pid" 2>/dev/null | tr -d ' ')
  [ "$actual" = "4" ] || false                           # deterministic by construction
  run env QOS_CENSUS_PATTERN=zzqosmark QOS_CENSUS_NO_CONTROL=1 QOS_DEMOTED_PRI_MAX=99 \
      QOS_CLAMP_PRIS="4" /bin/bash "$CENSUS" --json --no-append
  local admitted="$output"
  run env QOS_CENSUS_PATTERN=zzqosmark QOS_CENSUS_NO_CONTROL=1 QOS_DEMOTED_PRI_MAX=99 \
      QOS_CLAMP_PRIS="20" /bin/bash "$CENSUS" --json --no-append
  local rejected="$output"
  run env QOS_CENSUS_PATTERN=zzqosmark QOS_CENSUS_NO_CONTROL=1 \
      /bin/bash "$CENSUS" --json --no-append
  local defaults="$output"
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  # NON-VACUITY: an empty population would make both sides trivially 0.
  [ "$(printf '%s' "$admitted" | jq -r '.procs_total')" -ge 1 ] || false
  [ "$(printf '%s' "$admitted" | jq -r '.procs_demoted')" -ge 1 ] || false   # 4 in set  ⇒ admit
  [ "$(printf '%s' "$rejected" | jq -r '.procs_demoted')" -eq 0 ] || false   # 4 not in {20} ⇒ reject
  # And the SHIPPED default is the two clamp constants — which is what excludes the decay range
  # (17..19, 21..30) that a bare ceiling of 20 would have swallowed.
  [ "$(printf '%s' "$defaults" | jq -r '.clamp_pris')" = "4 20" ] || false
}

@test "(xx) M1-rev: a known UTILITY proc lands in the pri20 tier and the tiers partition the set" {
  if [ ! -x /usr/sbin/taskpolicy ]; then skip "taskpolicy(8) absent on this host"; fi
  local mk; mk=$(_marker_script zzutilmark)
  /usr/sbin/taskpolicy -c utility /bin/bash "$mk" >/dev/null 2>&1 &
  local pid=$!
  /bin/sleep 1
  run env QOS_CENSUS_PATTERN=zzutilmark QOS_CENSUS_NO_CONTROL=1 \
      /bin/bash "$CENSUS" --json --no-append
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  local d p4 p20
  d=$(printf '%s' "$output" | jq -r '.procs_demoted')
  p4=$(printf '%s' "$output" | jq -r '.procs_pri4')
  p20=$(printf '%s' "$output" | jq -r '.procs_pri20')
  [ "$p20" -ge 1 ] || false                     # the utility proc is counted, in the RIGHT tier
  [ "$p4" -eq 0 ] || false                      # and not in the background tier
  [ "$((p4 + p20))" -eq "$d" ] || false         # the two tiers partition the demoted set
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

# ── the activation SEED: the non-guessing answer, and every way it can be wrong ────────────────
# Added 2026-07-29 alongside the seed mechanism (bin/cc-bats:58-97). The seed exists because the
# resolver's last branch — the Cellar sweep — picks a version with `sort -V`, and picking a version
# by sort order is a GUESS. Shadow mode is where that matters: once /opt/homebrew/bin/bats IS this
# shim, the seed is the only non-guessing answer left, so the seed's FAILURE modes are load-bearing
# and each one is pinned below.
#
# EXISTENCE EVIDENCE FIRST. Five of these tests assert the seed was IGNORED. That claim is
# unfalsifiable on its own — "the stale seed was ignored" and "the seed file is never read at all"
# produce byte-identical output — so (xvii) proves the seed IS consulted, using a stand-in bats that
# names itself in its own --version. Every ignore-test then asserts real `Bats` AND the absence of
# that marker (memory absence-alarm-needs-existence-evidence).
#
# TWO INVOCATION CONVENTIONS, both deliberate:
#   · `timeout` comes BEFORE `env`, unlike (ii). The shadow-mode tests narrow PATH to the shim dir,
#     and `env PATH=<narrow> timeout ...` resolves timeout(1) against the NARROWED path — measured
#     while writing these tests: `env: timeout: No such file or directory`, rc 127, a resolution test
#     that never reached the resolver.
#   · Every invocation either sets CC_BATS_SEED or passes `env -u CC_BATS_SEED`. setup() unsets the
#     CC_BATS_* family but NOT CC_BATS_SEED, so an ambient seed in the invoking shell would otherwise
#     silently decide the verdict — the same how-was-it-invoked dependency setup()'s own comment
#     records for CC_BATS_ACTIVE.

# Seed helpers live ABOVE their callers, not in the helper section at the foot of the file where
# _descendant_pris sits: shellcheck -S info raises SC2218 (error) on a call to a function defined
# later, and this file is shellcheck-clean today. Bats sources the whole file before running any
# test, so either position WORKS — only the lint distinguishes them.

# _cellar_bats — the highest-versioned real bats under a Cellar, discovered at RUNTIME.
# Never a hardcoded version: this box measured 1.13.0 on 2026-07-29 and any `brew upgrade` moves it.
# That staleness is precisely what the seed exists to survive, so a test that hardcoded the version
# would rot in the same way the thing under test is designed not to.
_cellar_bats() {
  find /opt/homebrew/Cellar/bats-core /usr/local/Cellar/bats-core /opt/homebrew/opt/bats-core \
       -maxdepth 3 -name bats -type f -perm -u+x 2>/dev/null | sort -V | tail -1
}

# _seed <seed-file> <target-path> — write the one-line seed file, creating its parent.
_seed() {
  mkdir -p "$(dirname "$1")"
  printf '%s\n' "$2" > "$1"
}

# _fake_bats <path> <marker> — a stand-in "real bats" that NAMES ITSELF in its --version output.
# This marker is what makes the seed tests two-sided: its presence proves the seed answered, its
# absence next to a real `Bats` proves the shim fell through to its own search. Absolute shebang, so
# the PATH-narrowing tests cannot turn a resolution result into a shebang failure.
_fake_bats() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/bash\necho "Bats 9.99.0 %s"\n' "$2" > "$1"
  chmod +x "$1"
}

@test "(xvi) a VALID seed is honoured: the seeded Cellar binary runs" {
  # The seed's happy path, against the REAL binary rather than a stand-in, so this test also proves
  # the seeded path is executable-as-bats and not merely string-matched.
  local cellar
  cellar=$(_cellar_bats)
  if [ -z "$cellar" ]; then skip "no Cellar bats on this host to seed from"; fi
  _seed "$TMP/seed" "$cellar"
  run timeout 20 env CC_BATS_SEED="$TMP/seed" /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false
  [ "$status" -ne 124 ] || false
  [[ "$output" =~ Bats ]] || false
}

@test "(xvii) POSITIVE CONTROL for (xviii)-(xxii): a valid seed is CONSULTED, and answers" {
  # The control the five ignore-tests below stand on. A marked stand-in makes "the seed answered"
  # observable; without it every ignore-test passes just as well against a shim that never opens the
  # seed file at all.
  _fake_bats "$TMP/fake/bats" "CC-SEED-MARKER"
  _seed "$TMP/seed" "$TMP/fake/bats"
  run timeout 20 env CC_BATS_SEED="$TMP/seed" /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ CC-SEED-MARKER ]] || false
}

@test "(xviii) a STALE seed (target gone) degrades to the search — never fatal" {
  # `brew upgrade bats-core` moves the Cellar out from under the recording. That must cost nothing:
  # a seed is a shortcut, and a broken shortcut may not break every gate run on the machine.
  _fake_bats "$TMP/fake/bats" "CC-SEED-MARKER"          # exists, but is NOT what we seed
  _seed "$TMP/seed" "$TMP/definitely/not/here/bats"
  run timeout 20 env CC_BATS_SEED="$TMP/seed" /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false
  [ "$status" -ne 124 ] || false
  [[ "$output" =~ Bats ]] || false                      # a real bats answered
  [[ ! "$output" =~ CC-SEED-MARKER ]] || false          # and it was NOT the seed
}

@test "(xix) a seed pointing at a NON-EXECUTABLE file is ignored" {
  printf 'this is not a binary\n' > "$TMP/plain"
  chmod -x "$TMP/plain"
  [ ! -x "$TMP/plain" ] || false                        # the fixture must really be non-executable
  _seed "$TMP/seed" "$TMP/plain"
  run timeout 20 env CC_BATS_SEED="$TMP/seed" /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ Bats ]] || false
  [[ ! "$output" =~ CC-SEED-MARKER ]] || false
}

@test "(xx) a seed pointing at a DIRECTORY is ignored" {
  # A directory passes `-x` (the traverse bit), so `-x` ALONE would accept it and exec a directory.
  # bin/cc-bats:92 pairs `-x` with `! -d` for exactly this; the test pins the pairing.
  mkdir -p "$TMP/adir"
  [ -x "$TMP/adir" ] || false                           # the trap is real: a dir IS -x
  _seed "$TMP/seed" "$TMP/adir"
  run timeout 20 env CC_BATS_SEED="$TMP/seed" /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ Bats ]] || false
}

@test "(xxi) FORK-BOMB GUARD: a seed pointing at cc-bats ITSELF is rejected, not followed" {
  # The catastrophic case. A seed recorded during shadow-mode activation can name the path that IS
  # the shim, and following it is an unbounded exec loop with no output and no natural end. A HANG
  # is the failure here, so the bound is asserted explicitly: timeout(1) reports 124 and 124 must
  # never appear.
  _seed "$TMP/seed" "$SHIM"
  run timeout 20 env CC_BATS_SEED="$TMP/seed" /bin/bash "$SHIM" --version
  [ "$status" -ne 124 ] || false                        # did not loop
  [ "$status" -eq 0 ] || false                          # and still ran the real thing
  [[ "$output" =~ Bats ]] || false
}

@test "(xxii) FORK-BOMB GUARD holds through a SYMLINK to cc-bats (indirect self)" {
  # Sharper than (xxi), and the honest description of HOW it survives: the first hop does NOT reject
  # this seed — `$TMP/linkdir/bats` physicalises to itself, not to our own path, so the shim EXECS
  # it. The guard bites on the SECOND hop, where that same path is now `self`, and resolution falls
  # through to the search. So the property is CONVERGENCE (one extra exec), not rejection — worth
  # pinning separately, because a change that made the seed re-read on every hop would turn this
  # exact shape into the loop (xxi) guards against.
  mkdir -p "$TMP/linkdir"
  ln -sf "$SHIM" "$TMP/linkdir/bats"
  _seed "$TMP/seed" "$TMP/linkdir/bats"
  run timeout 20 env CC_BATS_SEED="$TMP/seed" /bin/bash "$SHIM" --version
  [ "$status" -ne 124 ] || false
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ Bats ]] || false
}

# ── the seam itself: unset / set-empty are DIFFERENT, and the difference must be observable ────

@test "(xxiii) POSITIVE CONTROL for (xxiv): with CC_BATS_SEED UNSET, the DEFAULT location is read" {
  # The default is $HOME/.claude/state/cc-bats-real — deliberately $HOME/.claude and NOT
  # $CLAUDE_CONFIG_DIR (bin/cc-bats:66-70): the seed is a MACHINE fact, and this box runs sessions
  # across four config dirs, so a per-config-dir seed would be invisible to the other three.
  # setup()'s fixtured $HOME is what makes asserting this safe — the real ~/.claude is never touched.
  _fake_bats "$TMP/fake/bats" "CC-SEED-MARKER"
  _seed "$HOME/.claude/state/cc-bats-real" "$TMP/fake/bats"
  run timeout 20 env -u CC_BATS_SEED /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ CC-SEED-MARKER ]] || false            # the default path IS consulted
}

@test "(xxiv) CC_BATS_SEED set-but-EMPTY is honoured verbatim: it DISABLES the lookup" {
  # `${VAR:-default}` cannot tell unset from set-empty, so it would silently re-enable the default
  # path here — the same asymmetry (vi) pins for CC_BATS_TASKPOLICY, and the one bin/cc-bats:71-73
  # records as caught in review. Two-sided against (xxiii): IDENTICAL fixture, only the seam differs,
  # so the marker's disappearance can only be the seam.
  _fake_bats "$TMP/fake/bats" "CC-SEED-MARKER"
  _seed "$HOME/.claude/state/cc-bats-real" "$TMP/fake/bats"
  run timeout 20 env CC_BATS_SEED= /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ Bats ]] || false                      # a real bats still answered
  [[ ! "$output" =~ CC-SEED-MARKER ]] || false          # the default seed was NOT consulted
}

# ── SHADOW MODE simulated: every PATH candidate is the shim, so does anything still resolve? ───

@test "(xxv) SHADOW MODE, no seed: every PATH candidate is the shim and it still resolves" {
  # The case that decides whether shadow mode is safe at all. Invoked THROUGH the `bats` symlink and
  # with PATH narrowed to the shim dir, so branch 2's every candidate is us and the walk must
  # exhaust without ever accepting itself.
  #
  # COVERAGE LIMIT, stated rather than implied: on an UNACTIVATED box /opt/homebrew/bin/bats is still
  # Homebrew's own binary, so branch 3 answers here and branch 4 (the Cellar sweep) is NOT what makes
  # this pass. Branch 4 is reachable only once shadow mode has really repointed that Homebrew-owned
  # absolute path — a machine-wide, operator-owned mutation, and the three branch-3 paths are
  # hardcoded absolutes with no seam, so no test can fixture it. What IS proven, and is the
  # decision-relevant part: with the whole PATH shadowed the shim resolves a real bats, exits 0, and
  # does not loop.
  #
  # /usr/bin and /bin stay on PATH on purpose: real bats is `#!/usr/bin/env bash`, so dropping them
  # would fail the shebang and prove nothing about resolution — the wrong-premise trap (vi-b) records.
  mkdir -p "$TMP/shadowdir"
  ln -sf "$SHIM" "$TMP/shadowdir/bats"
  run timeout 20 env -u CC_BATS_SEED PATH="$TMP/shadowdir:/usr/bin:/bin" \
      /bin/bash "$TMP/shadowdir/bats" --version
  [ "$status" -ne 124 ] || false                        # a hang IS the failure mode here
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ Bats ]] || false
}

@test "(xxvi) SHADOW MODE with a valid seed: the seed answers, and short-circuits the search" {
  # Same shadow shape as (xxv), plus the seed. The marker proves the seed — branch 1.5, ahead of the
  # PATH walk — is what answered, which is the whole reason it is tried first: in shadow mode the
  # PATH answer is the shim, so a resolver that consulted PATH first would have to walk past itself
  # to find anything.
  mkdir -p "$TMP/shadowdir"
  ln -sf "$SHIM" "$TMP/shadowdir/bats"
  _fake_bats "$TMP/fake/bats" "CC-SEED-MARKER"
  _seed "$TMP/seed" "$TMP/fake/bats"
  run timeout 20 env CC_BATS_SEED="$TMP/seed" PATH="$TMP/shadowdir:/usr/bin:/bin" \
      /bin/bash "$TMP/shadowdir/bats" --version
  [ "$status" -ne 124 ] || false
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ CC-SEED-MARKER ]] || false
}

@test "(xxvii) CC_BATS_REAL still OUTRANKS the seed" {
  # Precedence, proven by DISCRIMINATION rather than by both paths happening to work: two distinct
  # stand-ins, so the winner is named in the output. (iii) already pins that the pin is honoured even
  # when broken; this pins that it wins when a perfectly good seed is also present.
  _fake_bats "$TMP/fake/pin"  "CC-PIN-MARKER"
  _fake_bats "$TMP/fake/bats" "CC-SEED-MARKER"
  _seed "$TMP/seed" "$TMP/fake/bats"
  run timeout 20 env CC_BATS_REAL="$TMP/fake/pin" CC_BATS_SEED="$TMP/seed" \
      /bin/bash "$SHIM" --version
  [ "$status" -eq 0 ] || false
  [[ "$output" =~ CC-PIN-MARKER ]] || false             # the env pin ran
  [[ ! "$output" =~ CC-SEED-MARKER ]] || false          # the seed did not
}

# (seed helpers _cellar_bats / _seed / _fake_bats are defined above (xvi), ahead of their callers —
#  see the SC2218 note there.)

# ── DENOMINATOR PURITY: "argv contains bats" is not "this process IS bats" ─────────────────────
# Added 2026-07-30 with the strict-matching fix (scripts/qos-census.sh § DENOMINATOR PURITY). The
# first census counted ANY process whose argv contained the pattern. Measured live, that denominator
# was 157 rows of which only 114 were real bats: 6 `timeout` wrappers, 17 `<shell> -c` lines and 19
# claude sessions made up the rest — and EVERY pri=31 row in the population was one of those three
# classes. The `timeout 800 bats …` wrapper is the worst of them: it legitimately sits at pri=31
# while every bats child it spawned is at pri=4 (reproduced on 3 live wrappers), so it MANUFACTURES
# exactly the uncovered signal this tool exists to detect. Contaminated census: 73.2%. Clean: 100%.
# Same failure class as memory `detector-matching-its-own-skill-description` — text in an argv is
# never evidence that the process IS the thing.
#
# HOW THESE TESTS ARE DETERMINISTIC ON A SHARED BOX. The census reads the LIVE process table, and
# this machine runs other sessions' gates continuously (loadavg 47.1 while these were written, 73
# real bats procs in flight), so any absolute count against the default `bats` pattern is
# non-deterministic by construction. Each test below therefore spawns REAL processes carrying a
# token unique to that test and points QOS_CENSUS_PATTERN at it, which narrows the population to
# exactly this test's own processes. The probe path ALSO carries `bats-core/bats-exec-test`, because
# strict mode's positive discriminator is bats' own libexec path — without that half a probe would
# be excluded for the WRONG REASON and every exclusion test would pass vacuously against a census
# that had simply seen nothing.
#
# Every exclusion below is paired with a positive control measuring the SAME LIVE PROCESS under
# QOS_CENSUS_STRICT=off. That pairing is the point of the row: the bug being fixed was itself an
# unpoliced denominator, and "excluded" is indistinguishable from "saw nothing" without it.
#
# Helpers precede their callers (SC2218, as above). Probes are self-limiting (`timeout`/`sleep`
# bounded) AND swept with `pkill -f <token>` before any assertion runs, so a failing assertion can
# never strand a process on a box other sessions are using.

# _json_field <key> <json-line> — the numeric value of one census JSON field ("" when absent).
_json_field() {
  printf '%s' "$2" | sed -n "s/.*\"$1\":\([0-9.]*\).*/\1/p"
}

# _qos_probe_bin <token> — a sleep-shaped stand-in at a path that satisfies BOTH filters.
# The path carries the unique token (so QOS_CENSUS_PATTERN selects only this test's processes) and
# `bats-core/bats-exec-test` (so strict mode's positive discriminator accepts it). Only then is an
# exclusion attributable to the exclusion rule under test.
_qos_probe_bin() {
  local d="$TMP/$1/libexec/bats-core"
  mkdir -p "$d"
  ln -sf /bin/sleep "$d/bats-exec-test"
  printf '%s' "$d/bats-exec-test"
}

# _qos_probe_rows <token> — live ps rows carrying <token>. The bracket trick on the token's first
# character keeps this function's OWN grep out of the snapshot, the same way the census does it.
_qos_probe_rows() {
  # shellcheck disable=SC2009  # ps|grep is REQUIRED for the same reason it is in the census: the
  # subject is the FULL args line, which `ps -o comm=` truncates at 16 chars and pgrep never sees at
  # all. A probe wait that read a different surface from the thing under test would not be a wait.
  ps -eo pid,nice,pri,args 2>/dev/null | grep -E "[${1%"${1#?}"}]${1#?}"
}

# _qos_wait_rows <token> <n> — bounded (<=20s) wait until >=n live rows carry <token>.
# A fixed sleep is a coin flip at loadavg 47; the bound turns a slow spawn into a named failure
# instead of an intermittent one.
_qos_wait_rows() {
  local tok="$1" want="$2" i=0 n=0
  while [ "$i" -lt 20 ]; do
    n=$(_qos_probe_rows "$tok" | grep -c . || true)
    if [ "$n" -ge "$want" ]; then return 0; fi
    /bin/sleep 1
    i=$((i + 1))
  done
  return 1
}

# _qos_wait_runs <token> <n> — bounded (<=30s) wait until >=n DISTINCT bats-run-* ids appear among
# the token's rows. Not the same wait as _qos_wait_rows: runs_in_flight is what lifts the census off
# NO-BURST, and bats stamps its run tmpdir only on bats-exec-file's argv, which appears later than
# the first process of a run.
_qos_wait_runs() {
  local tok="$1" want="$2" i=0 n=0
  while [ "$i" -lt 30 ]; do
    n=$(_qos_probe_rows "$tok" | grep -oE 'bats-run-[A-Za-z0-9]+' | sort -u | grep -c . || true)
    if [ "$n" -ge "$want" ]; then return 0; fi
    /bin/sleep 1
    i=$((i + 1))
  done
  return 1
}

@test "(xxviii) a timeout(1) WRAPPER is EXCLUDED from the census population (strict)" {
  # The contaminant that made the tool lie. timeout(1) FORKS (measured: it does not exec), so this
  # is two live rows — the wrapper and its child — at a path both filters accept. Strict must keep
  # the child and drop the wrapper, so the honest population size is 1, not 2.
  local tok="qoscensus$$w$RANDOM$RANDOM"
  local probe
  probe=$(_qos_probe_bin "$tok")
  timeout 30 "$probe" 25 >/dev/null 2>&1 &
  local wpid=$!
  local spawned=0
  if _qos_wait_rows "$tok" 2; then spawned=1; fi
  run timeout 40 env QOS_CENSUS_PATTERN="$tok" QOS_CENSUS_NO_CONTROL=1 \
      QOS_CENSUS_LOG="$TMP/census-xxviii.jsonl" /bin/bash "$CENSUS" --json --no-append
  local st="$status" out="$output"
  kill "$wpid" 2>/dev/null || true
  pkill -f "$tok" >/dev/null 2>&1 || true
  wait "$wpid" 2>/dev/null || true
  [ "$spawned" -eq 1 ] || false                          # the fixture really was in flight
  [ "$st" -ne 124 ] || false                             # a hang is a failure, not a slow pass
  [ "$st" -ne 127 ] || false                             # 127 = never executed; not "excluded"
  [ ! -f "$TMP/census-xxviii.jsonl" ] || false           # --no-append held; no durable write
  local total
  total=$(_json_field procs_total "$out")
  [ -n "$total" ] || false
  [ "$total" -eq 1 ] || false                            # the child, and ONLY the child
}

@test "(xxix) POSITIVE CONTROL for (xxviii): the SAME wrapper IS counted with STRICT=off" {
  # Two censuses over ONE live process pair, so the difference can only be the strict filter. Without
  # this, (xxviii)'s "1" is indistinguishable from a census that never saw the wrapper at all — the
  # absence-without-existence-evidence failure this repo keeps re-learning.
  local tok="qoscensus$$c$RANDOM$RANDOM"
  local probe
  probe=$(_qos_probe_bin "$tok")
  timeout 30 "$probe" 25 >/dev/null 2>&1 &
  local wpid=$!
  local spawned=0
  if _qos_wait_rows "$tok" 2; then spawned=1; fi
  run timeout 40 env QOS_CENSUS_PATTERN="$tok" QOS_CENSUS_NO_CONTROL=1 \
      QOS_CENSUS_LOG="$TMP/census-xxix-s.jsonl" /bin/bash "$CENSUS" --json --no-append
  local s_st="$status" s_out="$output"
  run timeout 40 env QOS_CENSUS_STRICT=off QOS_CENSUS_PATTERN="$tok" QOS_CENSUS_NO_CONTROL=1 \
      QOS_CENSUS_LOG="$TMP/census-xxix-p.jsonl" /bin/bash "$CENSUS" --json --no-append
  local p_st="$status" p_out="$output"
  kill "$wpid" 2>/dev/null || true
  pkill -f "$tok" >/dev/null 2>&1 || true
  wait "$wpid" 2>/dev/null || true
  [ "$spawned" -eq 1 ] || false
  [ "$s_st" -ne 124 ] || false
  [ "$p_st" -ne 124 ] || false
  [ "$s_st" -ne 127 ] || false
  [ "$p_st" -ne 127 ] || false
  local s_total p_total
  s_total=$(_json_field procs_total "$s_out")
  p_total=$(_json_field procs_total "$p_out")
  [ -n "$s_total" ] || false
  [ -n "$p_total" ] || false
  [ "$p_total" -eq 2 ] || false                          # permissive sees wrapper AND child
  [ "$s_total" -eq 1 ] || false                          # strict sees only the child
  [ "$p_total" -gt "$s_total" ] || false                 # the delta IS the wrapper
}

@test "(xxx) a '<shell> -c' command line is EXCLUDED from the census population (strict)" {
  # 17 of the 157 contaminated rows were shell -c lines, all at pri=31. A shell whose ARGUMENT
  # mentions a bats path is not a bats process; counting it charges the actuator for a proc it was
  # never asked to demote.
  local tok="qoscensus$$s$RANDOM$RANDOM"
  local probe
  probe=$(_qos_probe_bin "$tok")
  # Two statements, so bash cannot exec-optimise itself away and the `bash -c` row really persists.
  /bin/bash -c "/bin/sleep 25; : $probe" >/dev/null 2>&1 &
  local bpid=$!
  local spawned=0
  if _qos_wait_rows "$tok" 1; then spawned=1; fi
  run timeout 40 env QOS_CENSUS_PATTERN="$tok" QOS_CENSUS_NO_CONTROL=1 \
      QOS_CENSUS_LOG="$TMP/census-xxx.jsonl" /bin/bash "$CENSUS" --json --no-append
  local st="$status" out="$output"
  kill "$bpid" 2>/dev/null || true
  pkill -f "$tok" >/dev/null 2>&1 || true
  wait "$bpid" 2>/dev/null || true
  [ "$spawned" -eq 1 ] || false
  [ "$st" -ne 124 ] || false
  [ "$st" -ne 127 ] || false
  local total
  total=$(_json_field procs_total "$out")
  [ -n "$total" ] || false
  [ "$total" -eq 0 ] || false
}

@test "(xxxi) POSITIVE CONTROL for (xxx): the SAME shell line IS counted with STRICT=off" {
  # (xxx) asserts a ZERO — the most vacuity-prone shape there is. This measures the same live line
  # under both settings so the zero is provably an exclusion and not an empty snapshot.
  local tok="qoscensus$$t$RANDOM$RANDOM"
  local probe
  probe=$(_qos_probe_bin "$tok")
  /bin/bash -c "/bin/sleep 25; : $probe" >/dev/null 2>&1 &
  local bpid=$!
  local spawned=0
  if _qos_wait_rows "$tok" 1; then spawned=1; fi
  run timeout 40 env QOS_CENSUS_PATTERN="$tok" QOS_CENSUS_NO_CONTROL=1 \
      QOS_CENSUS_LOG="$TMP/census-xxxi-s.jsonl" /bin/bash "$CENSUS" --json --no-append
  local s_st="$status" s_out="$output"
  run timeout 40 env QOS_CENSUS_STRICT=off QOS_CENSUS_PATTERN="$tok" QOS_CENSUS_NO_CONTROL=1 \
      QOS_CENSUS_LOG="$TMP/census-xxxi-p.jsonl" /bin/bash "$CENSUS" --json --no-append
  local p_st="$status" p_out="$output"
  kill "$bpid" 2>/dev/null || true
  pkill -f "$tok" >/dev/null 2>&1 || true
  wait "$bpid" 2>/dev/null || true
  [ "$spawned" -eq 1 ] || false
  [ "$s_st" -ne 124 ] || false
  [ "$p_st" -ne 124 ] || false
  [ "$s_st" -ne 127 ] || false
  [ "$p_st" -ne 127 ] || false
  local s_total p_total
  s_total=$(_json_field procs_total "$s_out")
  p_total=$(_json_field procs_total "$p_out")
  [ -n "$s_total" ] || false
  [ -n "$p_total" ] || false
  [ "$p_total" -ge 1 ] || false                          # the shell line IS visible to the census
  [ "$s_total" -eq 0 ] || false                          # and strict is what removes it
  [ "$p_total" -gt "$s_total" ] || false
}

@test "(xxxii) the census still COUNTS a genuine bats run" {
  # The other half of a purity fix, and the one a narrowing change breaks silently: a filter tight
  # enough to drop the wrapper must not also drop the population it exists to measure. A census that
  # counts nothing reports 100% coverage forever (the NO-BURST/signal-death shape row 13 was built
  # around), so "excluded the junk" is only half a verdict.
  local real
  real=$(_cellar_bats)
  if [ -z "$real" ]; then skip "no real bats binary on this host to run"; fi
  local tok="qoscensus$$r$RANDOM$RANDOM"
  mkdir -p "$TMP/$tok"
  # Corpus under BATS_TEST_TMPDIR: the token lands in every bats child's argv via the file path, and
  # the path contains no 'claude' substring the census would (correctly) exclude.
  cat > "$TMP/$tok/slow.bats" <<'EOF'
@test "occupies the scheduler long enough to be sampled" {
  /bin/sleep 12
}
EOF
  "$real" "$TMP/$tok/slow.bats" >/dev/null 2>&1 &
  local rpid=$!
  local spawned=0
  if _qos_wait_rows "$tok" 2; then spawned=1; fi
  run timeout 40 env QOS_CENSUS_PATTERN="$tok" QOS_CENSUS_NO_CONTROL=1 \
      QOS_CENSUS_LOG="$TMP/census-xxxii-s.jsonl" /bin/bash "$CENSUS" --json --no-append
  local s_st="$status" s_out="$output"
  run timeout 40 env QOS_CENSUS_STRICT=off QOS_CENSUS_PATTERN="$tok" QOS_CENSUS_NO_CONTROL=1 \
      QOS_CENSUS_LOG="$TMP/census-xxxii-p.jsonl" /bin/bash "$CENSUS" --json --no-append
  local p_st="$status" p_out="$output"
  kill "$rpid" 2>/dev/null || true
  pkill -f "$tok" >/dev/null 2>&1 || true
  wait "$rpid" 2>/dev/null || true
  [ "$spawned" -eq 1 ] || false
  [ "$s_st" -ne 124 ] || false
  [ "$s_st" -ne 127 ] || false
  local s_total p_total
  s_total=$(_json_field procs_total "$s_out")
  p_total=$(_json_field procs_total "$p_out")
  [ -n "$s_total" ] || false
  [ "$s_total" -ge 1 ] || false                          # the real population survives the filter
  # Strict is a SUBSET of permissive by construction; a strict count above it would mean the filter
  # invented rows. Asserted relatively, never as a total, because the box is shared.
  [ "$p_st" -ne 124 ] || false
  [ -n "$p_total" ] || false
  [ "$p_total" -ge "$s_total" ] || false
}

@test "(xxxiii) the verdict can still go FAIL when genuinely undemoted runs are present" {
  # The fix must not have bought its 100% by making failure unreachable. Two REAL bats runs spawned
  # WITHOUT the demotion path put a full-priority population in front of a strict census; coverage
  # must fall below threshold and the verdict must be FAIL (rc 1), not PASS and not NO-BURST.
  #
  # SAME ONE-WAY-RATCHET CONSTRAINT AS (v): a clamp only ever LOWERS and is immutable once spawned,
  # so a child of a demoted suite inherits that clamp and an ABSOLUTELY-undemoted (pri=31) population
  # is UNCONSTRUCTIBLE from here.
  #
  # This used to skip on `own <= 10`, and that constant went stale the moment M1-rev (`2514226e`)
  # moved the fleet band from background(4) to utility(20): the shim on PATH demotes this very suite
  # to pri=20, `20 <= 10` is false, so the test did NOT skip, its children inherited pri=20, the
  # census correctly counted them as DEMOTED, coverage never dropped and line 922 failed on trunk —
  # while (v)'s sibling guard at :113 was updated to `<= 20` and kept working. Two guards over one
  # constraint disagreeing was the tell.
  #
  # Repairing the constant alone would make this test SKIP on every ordinary PATH-invoked run — the
  # shim always demotes — retiring the one property it exists to prove. So the population is now made
  # undemoted RELATIVE TO THE CONFIGURED BAND instead of absolutely: the children inherit whatever
  # clamp this suite holds, and the census is pointed at the OTHER clamp constant, so they classify as
  # full-priority. Real bats processes, the real classifier, the real verdict arithmetic — only the
  # policy's clamp set is varied, which is the same documented seam (xix) uses to prove admit/reject
  # on one proc. From a genuinely undemoted caller the default set is used and this is the original,
  # absolute form.
  local own clamps
  own=$(ps -p $$ -o pri= 2>/dev/null | tr -d ' ')
  case "$own" in
    4)  clamps="20" ;;      # suite (and children) in background ⇒ measure against utility
    20) clamps="4"  ;;      # suite (and children) in utility    ⇒ measure against background
    *)  clamps="4 20" ;;    # genuinely undemoted (or unreadable) ⇒ shipped default, absolute form
  esac
  local real
  real=$(_cellar_bats)
  if [ -z "$real" ]; then skip "no real bats binary on this host to run"; fi
  local tok="qoscensus$$f$RANDOM$RANDOM"
  mkdir -p "$TMP/$tok"
  cat > "$TMP/$tok/slow.bats" <<'EOF'
@test "occupies the scheduler long enough to be sampled" {
  /bin/sleep 14
}
EOF
  # CC_BATS_QOS=off is belt-and-braces: $real is a Cellar binary, never the shim, but if that ever
  # changed the seam keeps the population undemoted rather than turning this into a silent PASS.
  CC_BATS_QOS=off "$real" "$TMP/$tok/slow.bats" >/dev/null 2>&1 &
  local r1=$!
  CC_BATS_QOS=off "$real" "$TMP/$tok/slow.bats" >/dev/null 2>&1 &
  local r2=$!
  # Wait for three distinct bats-run ids: the two spawned runs' own tmpdirs plus this suite's, which
  # the corpus path sits inside. The verdict needs >=2 and the two spawned runs alone supply that.
  local burst=0
  if _qos_wait_runs "$tok" 3; then burst=1; fi
  run timeout 40 env QOS_CENSUS_PATTERN="$tok" QOS_CENSUS_NO_CONTROL=1 \
      QOS_CLAMP_PRIS="$clamps" \
      QOS_CENSUS_LOG="$TMP/census-xxxiii.jsonl" /bin/bash "$CENSUS" --json --no-append
  local st="$status" out="$output"
  kill "$r1" "$r2" 2>/dev/null || true
  pkill -f "$tok" >/dev/null 2>&1 || true
  wait "$r1" 2>/dev/null || true
  wait "$r2" 2>/dev/null || true
  [ "$burst" -eq 1 ] || false                            # a real burst was in flight
  [ "$st" -ne 124 ] || false
  [ "$st" -ne 127 ] || false
  local total runs
  total=$(_json_field procs_total "$out")
  runs=$(_json_field runs_in_flight "$out")
  [ -n "$total" ] || false
  [ "$total" -ge 1 ] || false                            # non-vacuity: something was counted
  [ -n "$runs" ] || false
  [ "$runs" -ge 2 ] || false                             # and it cleared the NO-BURST gate
  # The construction really did place the whole population OUTSIDE the demoted set. Without this a
  # coverage drop could come from some unrelated row and the test would pass for the wrong reason.
  [ "$(_json_field procs_demoted "$out")" -eq 0 ] || false
  local below
  below=$(awk -v c="$(_json_field coverage_proc_pct "$out")" -v t=95 'BEGIN{print (c+0 < t+0) ? 1 : 0}')
  [ "$below" = "1" ] || false                            # coverage really did drop
  [[ "$out" =~ \"verdict\":\"FAIL\" ]] || false
  [ "$st" -eq 1 ] || false
}

@test "(xxxiv) a PATH entry holding a glob metacharacter is NOT pathname-expanded by the resolver" {
  # Unquoted `$PATH` in a `for` list is word-split AND pathname-expanded, so an entry containing a
  # glob metacharacter is replaced by whatever it happens to MATCH and the resolver execs a binary
  # PATH never named. This is the identity walk (§9.6), so a wrong pick here is not cosmetic.
  #
  # Measured 2026-07-31 against the pristine pre-fix artifact recovered with `git show HEAD:bin/cc-bats`
  # — never a retyped approximation: it printed the fake's marker, the fixed shim printed `Bats 1.13.0`.
  local c="$TMP/globctl"
  mkdir -p "$c/dX"
  printf '#!/bin/bash\necho GLOB_EXPANDED_REACHED_FAKE\n' > "$c/dX/bats"
  chmod +x "$c/dX/bats"

  # POSITIVE CONTROL, and it is load-bearing: without it this test passes just as well when the
  # fixture is inert (dX never created, the fake not executable, the marker misspelled) — an absence
  # assertion over a subject that was never there proves nothing. Prove the bait is live and reachable
  # BEFORE asserting the resolver refused it.
  run "$c/dX/bats"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *GLOB_EXPANDED_REACHED_FAKE* ]] || false
  # ...and that the glob really does match it, so the pre-fix expansion had somewhere to land.
  local matched; matched=$(compgen -G "$c/d*" | head -1)
  [ "$matched" = "$c/dX" ] || false

  run env PATH="$c/d*:/usr/bin:/bin" CC_BATS_QOS=off "$SHIM" --version
  [ "$status" -eq 0 ] || false
  [[ "$output" != *GLOB_EXPANDED_REACHED_FAKE* ]] || false   # the entry stayed literal
  [[ "$output" == *Bats* ]] || false                         # and a REAL bats is what ran
}
