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
  # HERMETIC HOME. seg_read() reads $HOME/.claude/logs/compressor-sentinel.jsonl; without this the
  # suite samples the operator's LIVE sentinel and its verdicts drift with whatever the box is
  # doing. Seed the fixture so the segment reading is deterministic (0.00) rather than ambient.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  SENTINEL="$HOME/.claude/logs/compressor-sentinel.jsonl"
  # The row now needs a FRESH `ts`: since F5 was closed, a row without one is a BLIND instrument and
  # aborts the ramp. That is the fix working, so the fixture carries what a live sentinel writes.
  seed_sentinel 0.00 0
  # BIN defaults under $HOME, which the hermetic HOME above just emptied — so `up`'s executable
  # check would fire (rc 2) BEFORE the breach check and mask what these tests are pinning (rc 3).
  # A stub keeps the breach path reachable; the breach tests never launch it, because they abort.
  export CC_RAMP_BIN=/bin/echo
}
# iso_ago: an ISO-8601 Zulu timestamp N seconds in the past. Both `date` spellings are tried
# because this suite runs on the operator's macOS box (BSD `-v-NS`) and in CI/cloud Linux (GNU
# `-d @epoch`) — the same divergence the subject deliberately avoids by doing its own arithmetic.
iso_ago() { # $1=seconds ago
  date -u -v-"$1"S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "@$(( $(date -u +%s) - $1 ))" +%Y-%m-%dT%H:%M:%SZ
}
# seed_sentinel: write ONE row shaped like compressor-sentinel.sh:776 emits.
seed_sentinel() { # $1=pct  $2=age_seconds
  printf '{"ts":"%s","t":42,"seg":0,"lim":1629615,"pct":%s}\n' "$(iso_ago "$2")" "$1" > "$SENTINEL"
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

# ── D3'S INSTRUMENT MUST BE ALIVE (F5, 10-adv-redteam.md) ─────────────────────────────────────────
# The old reader was `jq -r '.pct // 0' || echo 0`, so a missing/stale/unparseable sentinel log read
# 0 — the healthiest possible segment figure — and the ramp advanced a stage on an alarm that was
# not reporting. Every test below pins CC_RAMP_FLOOR_GB=0 (unconditionally inert: avail is never
# < 0) so the D6 memory arm, which breach() evaluates first, cannot decide these for the wrong
# reason — the lesson the D3-ceiling test above was rewritten for.

@test "D3 is UNVERIFIABLE when the sentinel log is ABSENT — the redteam's own falsifier" {
  # F5 verbatim: `mv` the jsonl aside and run `capacity-ramp.sh breach`. Pre-fix it read OK.
  mv "$SENTINEL" "$SENTINEL.moved"
  CC_RAMP_FLOOR_GB=0 run bash "$SCRIPT" breach
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"UNVERIFIABLE"* ]] || false
  [[ "$output" == *"could not measure is NOT healthy"* ]] || false
}

@test "D3 is UNVERIFIABLE when the last row is STALE — a dead alarm is not a quiet one" {
  # The sentinel has its own SKIP path and a launchd restart loses its baselines, so a log that
  # stopped growing is the expected shape of the failure, not an exotic one.
  seed_sentinel 0.00 600
  CC_RAMP_FLOOR_GB=0 run bash "$SCRIPT" breach
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"UNVERIFIABLE"* ]] || false
  [[ "$output" == *"600s old"* ]] || false
}

@test "POSITIVE CONTROL: a FRESH 0.00 row is a MEASUREMENT and the ramp proceeds" {
  # The load-bearing counterpart. Without it the fix could be "always abort", which reads as
  # maximal safety and is just a differently-broken instrument — the ramp could never run at all.
  seed_sentinel 0.00 0
  CC_RAMP_FLOOR_GB=0 run bash "$SCRIPT" breach
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"OK:"* ]] || false
  ! [[ "$output" == *"UNVERIFIABLE"* ]] || false
}

@test "a row with no ts is BLIND — freshness is read from the ROW, not from the file existing" {
  # A legacy or partially-written row. The file is present and non-empty, so an existence check
  # alone would pass it; only reading the row's own sample time catches this.
  printf '{"pct":0.00,"seg":0,"lim":1629615}\n' > "$SENTINEL"
  CC_RAMP_FLOOR_GB=0 run bash "$SCRIPT" breach
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"UNVERIFIABLE"* ]] || false
}

@test "a row whose pct is null is BLIND — the sentinel emitted a row it could not fill" {
  # compressor-sentinel.sh writes \"pct\":\${SEG_PCT:-null}. `// 0` laundered that null into the
  # healthiest reading; `// empty` keeps it an absence.
  printf '{"ts":"%s","pct":null}\n' "$(iso_ago 0)" > "$SENTINEL"
  CC_RAMP_FLOOR_GB=0 run bash "$SCRIPT" breach
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"UNVERIFIABLE"* ]] || false
}

@test "up REFUSES on a blind sentinel and launches NOTHING" {
  # The abort must reach the launch loop, not merely the `breach` verb — F5's damage is a ramp that
  # ADVANCES on a dead instrument.
  rm -f "$SENTINEL"
  export CC_RAMP_FLOOR_GB=0
  run_up 1
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"ABORT"* ]] || false
  [[ "$output" == *"UNVERIFIABLE"* ]] || false
  [ ! -s "$CC_RAMP_PIDFILE" ] || { echo "pidfile non-empty — it launched on an unreadable sentinel"; return 1; }
}

@test "stat says BLIND, never 0, when the sentinel is unreadable" {
  # The display spelling matters as much as the branch: a 0 in this column is indistinguishable
  # from a calm box to every human and every grep that reads the line.
  rm -f "$SENTINEL"
  run bash "$SCRIPT" stat
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"seg=BLIND"* ]] || false
  [[ "$output" == *"segage=n/a"* ]] || false
  ! [[ "$output" == *"seg=0%"* ]] || false
}

@test "POSITIVE CONTROL for the above: a fresh row prints the reading AND its age" {
  seed_sentinel 4.50 0
  run bash "$SCRIPT" stat
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"seg=4.50%"* ]] || false
  [[ "$output" == *"segage=0s"* ]] || false
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
  # ANCHOR NOTE: breach()'s segment comparison takes its value from $pct (it was $s until the F5
  # freshness fix split "measured" from "could not measure"). A stale anchor here does not RED —
  # it `skip`s, i.e. the mutation control silently stops controlling anything. Caught exactly that
  # way on 2026-08-11; if you rename the variable again, this line moves with it.
  sed 's|awk -v s="$pct" -v m="$SEG_MAX" .BEGIN{exit !(s+0 >= m+0)}. |false |' "$SCRIPT" > "$MUT"
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

@test "MUTATION: neutering the freshness check makes a STALE sentinel read healthy again" {
  MUT="$TMP/mut-fresh.sh"
  # `%` delimiter, not `|`: the expression this replaces contains awk's own `||`, which ends the
  # s-command early and yields `sed: unknown option to s`.
  sed 's%awk -v g="$age" -v m="$SEG_MAX_AGE" .BEGIN{exit !(g+0 > m+0 || g+0 < -(m+0))}.%false%' "$SCRIPT" > "$MUT"
  bash -n "$MUT" || { echo "mutant is malformed — it would red everything and prove nothing"; return 1; }
  ! grep -q 'g+0 > m+0' "$MUT" || skip "sed anchor missed; nothing mutated"
  grep -q 'UNVERIFIABLE' "$MUT" || { echo "sed over-matched: the mutant lost the D3 blind arm entirely"; return 1; }
  seed_sentinel 0.00 600
  # CONTROL FIRST — the real script must abort here, or a status change proves nothing.
  CC_RAMP_FLOOR_GB=0 run bash "$SCRIPT" breach
  [ "$status" -eq 1 ] || { echo "control failed: the unmutated script does not abort on a stale row"; return 1; }
  CC_RAMP_FLOOR_GB=0 CC_RAMP_PIDFILE="$TMP/mut-pids.txt" run bash "$MUT" breach
  # With the age comparison dead, a 10-minute-old row is indistinguishable from a live one again.
  [ "$status" -eq 0 ] || { echo "mutation did not change behaviour — the test is not pinning freshness"; return 1; }
}

@test "MUTATION: neutering the blind branch restores F5 exactly — an ABSENT sentinel reads OK" {
  # The blind arm is its OWN site: the freshness mutant above cannot go red when this branch rots,
  # because an unreadable log never produces an age to compare in the first place.
  MUT="$TMP/mut-blind.sh"
  sed 's|if \[ -z "$r" \]; then|if false; then|' "$SCRIPT" > "$MUT"
  bash -n "$MUT" || { echo "mutant is malformed — it would red everything and prove nothing"; return 1; }
  ! grep -q 'if \[ -z "$r" \]; then' "$MUT" || skip "sed anchor missed; nothing mutated"
  rm -f "$SENTINEL"
  CC_RAMP_FLOOR_GB=0 run bash "$SCRIPT" breach
  [ "$status" -eq 1 ] || { echo "control failed: the unmutated script does not abort on an absent log"; return 1; }
  CC_RAMP_FLOOR_GB=0 CC_RAMP_PIDFILE="$TMP/mut-pids.txt" run bash "$MUT" breach
  # Empty pct falls through every comparison as 0 — the pre-fix behaviour, verbatim.
  [ "$status" -eq 0 ] || { echo "mutation did not change behaviour — the test is not pinning blindness"; return 1; }
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
