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
