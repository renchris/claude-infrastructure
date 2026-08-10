#!/usr/bin/env bats
# Tests for scripts/capacity-ramp.sh — the S6-DOD D1 ramp harness.
#
# The two properties worth pinning are the two that were LEARNED THE HARD WAY in the investigation
# that produced this script (2026-08-09):
#   1. `down` kills ONLY tracked pids. A cleanup that killed by "age < 4 minutes" could not
#      distinguish its own probes from a freshly-fired peer session, which is young by construction.
#   2. `up` refuses to launch when a D3/D6 abort condition already holds. The actuator excludes
#      claude from its cohort, so this floor is the ramp's ONLY backstop.
# Each has a mutation check asserting the test goes RED when the property is neutered.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/capacity-ramp.sh"
  TMP="$(mktemp -d)"
  export CC_RAMP_PIDFILE="$TMP/pids.txt"
  export CC_RAMP_FIFODIR="$TMP"
  export CC_RAMP_SETTLE=0
  # HERMETIC HOME. seg_pct() reads $HOME/.claude/logs/compressor-sentinel.jsonl; without this the
  # suite samples the operator's LIVE sentinel and its verdicts drift with whatever the box is
  # doing. Seed the fixture so seg_pct is deterministic (0.00) rather than ambient.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  printf '{"pct":0.00,"seg":0,"lim":1629615}\n' > "$HOME/.claude/logs/compressor-sentinel.jsonl"
  # BIN defaults under $HOME, which the hermetic HOME above just emptied — so `up`'s executable
  # check would fire (rc 2) BEFORE the breach check and mask what these tests are pinning (rc 3).
  # A stub keeps the breach path reachable; the breach tests never launch it, because they abort.
  export CC_RAMP_BIN=/bin/echo
}
teardown() {
  # Reclaim anything a rotted breach arm managed to launch. `down` kills only this script's own
  # tracked pids, so on the green path (no pidfile) it is an instant no-op.
  bash "$SCRIPT" down >/dev/null 2>&1 || true
  rm -rf "$TMP"
}

# NEVER capture `up` through bats' `run`. `run` reads the subject's output from a PIPE, and a breach
# arm that rots lets `up` LAUNCH — its `sleep 7200` fifo-holder inherits that pipe and keeps it open,
# so the test HANGS FOR TWO HOURS instead of going red. Measured 2026-08-10 while building the
# control for the ceiling test below: the mutant subject wedged the suite rather than failing it,
# which would burn the post-land runner's whole budget on a non-verdict. Capturing to a FILE gives
# the grandchildren something other than the pipe, so the parent's exit status is the verdict and a
# rotted arm reds immediately (verified: status 0, not 3, returned at once).
run_up() {
  status=0
  bash "$SCRIPT" up "$@" >"$TMP/up.out" 2>&1 || status=$?
  output="$(cat "$TMP/up.out")"
}

@test "usage: no verb exits 64 and names the stages" {
  run bash "$SCRIPT"
  [ "$status" -eq 64 ]
  [[ "$output" == *"19 -> 40 -> 80 -> 150"* ]]
}

@test "stat emits every D-criterion field on one line" {
  run bash "$SCRIPT" stat
  [ "$status" -eq 0 ]
  for f in sessions= ptys= avail= seg= panics=; do
    [[ "$output" == *"$f"* ]] || { echo "missing field: $f in: $output"; return 1; }
  done
}

@test "up REFUSES when the memory floor already breaches (the ramp's only backstop)" {
  # Floor set absurdly high => breach holds now => up must abort before launching anything.
  export CC_RAMP_FLOOR_GB=999999
  run_up 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"ABORT"* ]] || false
  [[ "$output" == *"D6 memory"* ]] || false
  [ ! -s "$CC_RAMP_PIDFILE" ] || { echo "pidfile non-empty — it launched despite the breach"; return 1; }
}

@test "up REFUSES when the segment ceiling already breaches" {
  # PIN THE SIBLING AXIS INERT. breach() evaluates D6 memory BEFORE D3 segments and returns on the
  # first hit, so leaving the memory floor at its 8GB default lets the operator's live vm_stat decide
  # which arm this test reaches. Measured 2026-08-10 at avail=7.17GB: the D6 arm won, `status` was
  # still 3 — so the exit-code assertion passed for the WRONG reason — and the output said
  # "D6 memory", never "D3 segments". That is the whole of post-land RED 3e09830ca503, and it is why
  # the bisect could name no culprit (the floor commit was not green either): the failure is ambient
  # load, not a regression. FLOOR_GB=0 is unconditionally inert (avail is never < 0), which leaves D3
  # as the only reachable arm.
  export CC_RAMP_SEG_MAX=-1 CC_RAMP_FLOOR_GB=0   # any seg_pct >= -1 => breach
  run_up 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"D3 segments"* ]]
}

@test "breach verb exits 1 and names the reason when a floor is crossed" {
  CC_RAMP_FLOOR_GB=999999 run bash "$SCRIPT" breach
  [ "$status" -eq 1 ]
  [[ "$output" == *"BREACH"* ]]
}

@test "down with no pidfile is a clean no-op — it never guesses at a target" {
  rm -f "$CC_RAMP_PIDFILE"
  run bash "$SCRIPT" down
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing this script spawned"* ]]
}

@test "down kills ONLY tracked pids — an untracked sibling survives" {
  # sibling = a process this script did NOT spawn. It must be alive afterwards.
  sleep 60 & SIBLING=$!
  sleep 60 & TRACKED=$!
  echo "$TRACKED" > "$CC_RAMP_PIDFILE"
  run bash "$SCRIPT" down
  [ "$status" -eq 0 ]
  sleep 1
  kill -0 "$SIBLING" 2>/dev/null || { echo "REGRESSION: down killed an untracked sibling"; kill $SIBLING 2>/dev/null; return 1; }
  ! kill -0 "$TRACKED" 2>/dev/null || { echo "down failed to kill its own tracked pid"; return 1; }
  kill "$SIBLING" 2>/dev/null || true
}

# ── MUTATION CHECKS ────────────────────────────────────────────────────────────────────────────
# Each neuters ONE property in a COPY and asserts the guarding test would go RED. One mutant per
# site; each is syntax-checked first, because a malformed mutant reddens everything, which reads as
# maximal coverage while proving nothing.

@test "MUTATION: neutering the floor check makes the refusal test pass wrongly" {
  MUT="$TMP/mut-floor.sh"
  sed 's|awk -v a="$a" -v f="$FLOOR_GB" .BEGIN{exit !(a+0 < f+0)}. |false |' "$SCRIPT" > "$MUT"
  bash -n "$MUT" || { echo "mutant is malformed — it would red everything and prove nothing"; return 1; }
  grep -q 'D6 memory' "$MUT" || skip "sed anchor missed; nothing mutated"
  CC_RAMP_FLOOR_GB=999999 CC_RAMP_PIDFILE="$TMP/mut-pids.txt" run bash "$MUT" breach
  # With the floor comparison dead, an impossible floor no longer breaches => exit 0, not 1.
  [ "$status" -eq 0 ] || { echo "mutation did not change behaviour — the test is not pinning the floor"; return 1; }
}

@test "MUTATION: neutering the segment check makes the ceiling refusal test pass wrongly" {
  # The D3 arm is its OWN site and needs its own mutant. The floor mutant above cannot go red when
  # this comparison rots, and until the ceiling test pinned the memory floor inert it was reaching
  # the D6 arm on any loaded box — i.e. the one arm nothing else covers had a guard that could not
  # reliably reach it.
  MUT="$TMP/mut-seg.sh"
  sed 's|awk -v s="$s" -v m="$SEG_MAX" .BEGIN{exit !(s+0 >= m+0)}. |false |' "$SCRIPT" > "$MUT"
  bash -n "$MUT" || { echo "mutant is malformed — it would red everything and prove nothing"; return 1; }
  grep -q 'D3 segments' "$MUT" || { echo "sed over-matched: the mutant lost the D3 arm entirely"; return 1; }
  ! grep -q 'exit !(s+0 >= m+0)' "$MUT" || skip "sed anchor missed; nothing mutated"
  # Control FIRST: the real script must breach under this env, or a status change proves nothing.
  CC_RAMP_SEG_MAX=-1 CC_RAMP_FLOOR_GB=0 run bash "$SCRIPT" breach
  [ "$status" -eq 1 ] || { echo "control failed: the unmutated script does not breach here"; return 1; }
  CC_RAMP_SEG_MAX=-1 CC_RAMP_FLOOR_GB=0 CC_RAMP_PIDFILE="$TMP/mut-pids.txt" run bash "$MUT" breach
  # With the segment comparison dead, an impossible ceiling no longer breaches => exit 0, not 1.
  [ "$status" -eq 0 ] || { echo "mutation did not change behaviour — the test is not pinning the ceiling"; return 1; }
}

@test "MUTATION: replacing tracked-pid kill with a pattern kill would hit the sibling" {
  # Assert the CONTRACT rather than running a pattern-kill: the script must never select targets
  # by age or by pgrep -f. Those are the two predicates that cannot distinguish ours from theirs.
  # Strip comments FIRST. The header deliberately NAMES `pgrep -f` and age-based selection in order
  # to explain why they are forbidden, so a naive grep matches the documentation of the anti-pattern
  # rather than the anti-pattern — this test failed exactly that way on first run.
  CODE="$TMP/code-only.sh"
  sed 's/[[:space:]]*#.*$//' "$SCRIPT" > "$CODE"
  ! grep -qE 'pgrep -f|etime' "$CODE" || {
    echo "REGRESSION: capacity-ramp selects targets by pattern/age — identity must be tracked pids"
    return 1; }
  # positive control: the forbidden pattern IS detectable once present in code
  printf '\npgrep -f claude\n' >> "$CODE"
  grep -qE 'pgrep -f' "$CODE" || { echo "control failed: the guard cannot see the pattern at all"; return 1; }
  grep -q 'while read -r p' "$SCRIPT" || { echo "down no longer iterates the pidfile"; return 1; }
}
