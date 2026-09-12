#!/usr/bin/env bats
# cloud-return-lane.bats — the cloud lane's own tick (scripts/cloud-return-lane.sh).
#
# The subject is a SUPERVISOR: it runs two siblings in order under their own bounds and journals
# what ran. Both siblings are stubbed beside a COPY of the lane, because the lane resolves them from
# its own directory — the same property tests/autonomy-sweep.bats leans on.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  command -v jq >/dev/null 2>&1 || skip "jq required"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR/logs"
  export CC_CLOUD_STATE="$BATS_TEST_TMPDIR/cloud"; mkdir -p "$CC_CLOUD_STATE"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"; : >"$CC_IDL"
  export CALLS="$BATS_TEST_TMPDIR/calls"; : >"$CALLS"
  D="$BATS_TEST_TMPDIR/scripts"; mkdir -p "$D"
  cp "$REPO/scripts/cloud-return-lane.sh" "$D/cloud-return-lane.sh"; chmod +x "$D/cloud-return-lane.sh"
  LANE="$D/cloud-return-lane.sh"
  cat >"$D/cloud-return.sh" <<'EOF'
#!/bin/bash
echo "return bound=${CC_RETURN_BOUND_S:-UNSET} $*" >>"$CALLS"
[ "${RETURN_SLEEP:-0}" = 0 ] || sleep "$RETURN_SLEEP"
exit "${RETURN_RC:-0}"
EOF
  cat >"$D/cloud-retire-terminal.sh" <<'EOF'
#!/bin/bash
echo "retire repo=${CLOUD_RETIRE_REPO:-UNSET} $*" >>"$CALLS"
echo "  retired s-1 (gone) — branch claude/x"
echo "cloud-retire-terminal: examined=3 gone=1 landed=1 superseded=1 conflict=0 young-held=0 kept=0 retired=3 failed=0 dry_run=0"
exit "${RETIRE_RC:-0}"
EOF
  cat >"$D/cloud-answer.py" <<'EOF'
#!/usr/bin/env python3
import os, sys
open(os.environ["CALLS"], "a").write("answer %s\n" % " ".join(sys.argv[1:]))
sys.stdout.write("COLLECT     session_01AAAA  item=i1\n")
sys.stdout.write("cloud-answer: read 4 active session(s) - COLLECT 1, CLEAR 3\n")
sys.exit(int(os.environ.get("ANSWER_RC", "0")))
EOF
  chmod +x "$D"/*.sh "$D/cloud-answer.py"
  export CC_LANE_REPO="$BATS_TEST_TMPDIR/repo"
}

row() { jq -c "select(.disposition==\"$1\")" "$CC_IDL" | tail -1; }

@test "one tick runs RETURN then RETIRE, in that order, and journals both with rc + elapsed" {
  run bash "$LANE"
  [ "$status" -eq 0 ]
  # order is load-bearing: a branch the return pass just landed is `landed` by the retire pass
  [ "$(sed -n 1p "$CALLS" | cut -d' ' -f1)" = return ]
  [ "$(sed -n 2p "$CALLS" | cut -d' ' -f1)" = retire ]
  r="$(row cloud-return)"; [ -n "$r" ]
  [ "$(printf '%s' "$r" | jq -r '.tool')" = cloud-return-lane ]
  [ "$(printf '%s' "$r" | jq -r '.cloud_return_rc')" = "0" ]
  printf '%s' "$r" | jq -e '.elapsed_s | type == "number"' >/dev/null
  printf '%s' "$r" | jq -e '.bound_s == 5400' >/dev/null
  t="$(row cloud-retire)"; [ -n "$t" ]
  [ "$(printf '%s' "$t" | jq -r '.cloud_retire_rc')" = "0" ]
  # the retire pass's one-line census is KEPT — the sweep used to send it to /dev/null
  printf '%s' "$t" | jq -e '.summary | test("examined=3 gone=1 landed=1 superseded=1")' >/dev/null
}

@test "the child is TOLD the bound it will be killed at, and the retire pass gets the repo + --max" {
  CC_LANE_RETURN_BOUND_S=77 CC_LANE_RETIRE_MAX=9 run bash "$LANE"
  [ "$status" -eq 0 ]
  grep -q '^return bound=77 --sweep --limit 25$' "$CALLS"
  grep -q "^retire repo=$CC_LANE_REPO --max 9$" "$CALLS"
  [ "$(row cloud-return | jq -r '.bound_s')" = "77" ]
}

@test "SINGLE-FLIGHT: a live holder makes the second tick exit 4 with no rows; a dead holder is reaped" {
  mkdir -p "$CC_CLOUD_STATE/.lane.lock"
  # a LIVE holder: this test's own shell
  printf '%s\n' "$$" >"$CC_CLOUD_STATE/.lane.lock/pid"; date +%s >"$CC_CLOUD_STATE/.lane.lock/at"
  run bash "$LANE"
  [ "$status" -eq 4 ]
  # nothing RAN, but the tick still journals: rc 4 with null fields, naming the holder
  [ ! -s "$CALLS" ]
  r="$(row cloud-return)"; [ -n "$r" ]
  [ "$(printf '%s' "$r" | jq -r '.cloud_return_rc')" = "4" ]
  printf '%s' "$r" | jq -e ".holder_pid == $$ and .elapsed_s == null" >/dev/null
  # a DEAD holder (a pid nothing runs under): reaped, and the tick runs
  printf '%s\n' 2147483000 >"$CC_CLOUD_STATE/.lane.lock/pid"
  run bash "$LANE"
  [ "$status" -eq 0 ]
  grep -q '^return ' "$CALLS"
  # and the lock is released on exit
  [ ! -d "$CC_CLOUD_STATE/.lane.lock" ]
}

@test "a return pass SIGKILLed by its bound (137) leaves no stranded return lock behind, and the row says CUT" {
  mkdir -p "$CC_CLOUD_STATE/.return.lock"
  RETURN_RC=137 run bash "$LANE"
  [ "$status" -eq 0 ]
  [ ! -d "$CC_CLOUD_STATE/.return.lock" ]
  r="$(row cloud-return)"
  [ "$(printf '%s' "$r" | jq -r '.cloud_return_rc')" = "137" ]
  printf '%s' "$r" | jq -e '.note | test("cut by the lane bound")' >/dev/null
  # the retire pass still ran — a cut return is not a reason to leave the terminal strata unsettled
  grep -q '^retire ' "$CALLS"
}

@test "the lane's OWN bound is real: a return pass that overruns it is cut, not waited for" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "no timeout(1)"
  RETURN_SLEEP=20 CC_LANE_RETURN_BOUND_S=1 run bash "$LANE"
  [ "$status" -eq 0 ]
  rc="$(row cloud-return | jq -r '.cloud_return_rc')"
  case "$rc" in 124|137|143) ;; *) echo "expected a bound rc, got $rc"; false ;; esac
}

@test "an absent sibling is journalled as skipped with null fields — never as a 0 that ran instantly" {
  rm -f "$D/cloud-return.sh" "$D/cloud-retire-terminal.sh"
  run bash "$LANE"
  [ "$status" -eq 0 ]
  r="$(row cloud-return)"
  [ "$(printf '%s' "$r" | jq -r '.cloud_return_rc')" = skipped ]
  printf '%s' "$r" | jq -e '.elapsed_s == null and .load1 == null' >/dev/null
  [ "$(row cloud-retire | jq -r '.cloud_retire_rc')" = skipped ]
}

@test "the retire census is TYPED, so a pile that drained by LANDING is separable from one that was DISCARDED" {
  run bash "$LANE"
  [ "$status" -eq 0 ]
  t="$(row cloud-retire)"
  # the pass's own words are KEPT — the typed fields are added beside them, never instead of them
  printf '%s' "$t" | jq -e '.summary | test("examined=3")' >/dev/null
  # …and now they can be summed. This is the whole point: `landed` and the discard strata move
  # `pending_total` identically, so only a typed field can tell the two drains apart.
  [ "$(printf '%s' "$t" | jq -r '.census.examined')"   = 3 ]
  [ "$(printf '%s' "$t" | jq -r '.census.landed')"     = 1 ]
  [ "$(printf '%s' "$t" | jq -r '.census.superseded')" = 1 ]
  [ "$(printf '%s' "$t" | jq -r '.census.gone')"       = 1 ]
  [ "$(printf '%s' "$t" | jq -r '.census.conflict')"   = 0 ]
  # the hyphenated stratum survives the split
  [ "$(printf '%s' "$t" | jq -r '.census["young-held"]')" = 0 ]
  # numbers, not strings — a reader must be able to add them without coercing
  printf '%s' "$t" | jq -e '.census | to_entries | all(.value | type == "number")' >/dev/null
  # the discard rate is now one expression over the row
  [ "$(printf '%s' "$t" | jq -r '.census | .superseded + .conflict')" = 1 ]
  # and load1 rides the retire row too, so its elapsed is stratifiable (the §3h retrofit, not
  # repeated). Asserted as the INVARIANT, not as a value: load1() reads `sysctl vm.loadavg`, which
  # exists on the box this runs on and not on every box this suite runs on, so a `type=="number"`
  # here would be a test of the platform. What must hold is that the retire row now carries the
  # field at all and obeys the same ran/not-ran rule as the return row beside it.
  printf '%s' "$t" | jq -e 'has("load1")' >/dev/null
  printf '%s' "$t" | jq -e '.load1 == null or (.load1 | type == "number")' >/dev/null
  [ "$(printf '%s' "$t" | jq -r '.load1 | type')" = "$(row cloud-return | jq -r '.load1 | type')" ]
}

@test "a retire pass that printed NO census journals null — never a zeroed census that reads as settled-nothing" {
  # a pass CUT by its bound is the real shape of this: it dies mid-walk with nothing on stdout.
  cat >"$D/cloud-retire-terminal.sh" <<'EOF'
#!/bin/bash
echo "retire repo=${CLOUD_RETIRE_REPO:-UNSET} $*" >>"$CALLS"
exit 143
EOF
  chmod +x "$D/cloud-retire-terminal.sh"
  run bash "$LANE"
  [ "$status" -eq 0 ]
  t="$(row cloud-retire)"
  [ "$(printf '%s' "$t" | jq -r '.cloud_retire_rc')" = 143 ]
  printf '%s' "$t" | jq -e '.census == null' >/dev/null
  # the trap it must not fall into: a census of zeros is indistinguishable from a completed pass
  # that found nothing terminal, and one of those is a verdict while the other is a machine event.
  printf '%s' "$t" | jq -e '.census.examined == null' >/dev/null
}

@test "a stratum the parser was never told about still lands — the census is a CLASS, not an enumeration" {
  cat >"$D/cloud-retire-terminal.sh" <<'EOF'
#!/bin/bash
echo "retire repo=${CLOUD_RETIRE_REPO:-UNSET} $*" >>"$CALLS"
echo "cloud-retire-terminal: examined=5 gone=0 landed=2 superseded=0 conflict=0 young-held=0 kept=3 retired=2 failed=0 dry_run=0 abandoned=1"
exit 0
EOF
  chmod +x "$D/cloud-retire-terminal.sh"
  run bash "$LANE"
  [ "$status" -eq 0 ]
  t="$(row cloud-retire)"
  # `abandoned` exists in no list in this file; enumerating the strata is what cost the cc-reaper
  # whitelist twice, so the parser matches the SHAPE `key=<int>` instead.
  [ "$(printf '%s' "$t" | jq -r '.census.abandoned')" = 1 ]
  [ "$(printf '%s' "$t" | jq -r '.census.landed')"    = 2 ]
  # and a non-numeric token in the same line is not coerced into the object
  printf '%s' "$t" | jq -e '.census | has("cloud-retire-terminal:") | not' >/dev/null
}

@test "an absent retire sibling journals a null census and a null load1, not an empty object" {
  rm -f "$D/cloud-retire-terminal.sh"
  run bash "$LANE"
  [ "$status" -eq 0 ]
  t="$(row cloud-retire)"
  [ "$(printf '%s' "$t" | jq -r '.cloud_retire_rc')" = skipped ]
  printf '%s' "$t" | jq -e '.census == null and .load1 == null and .elapsed_s == null' >/dev/null
}

@test "--status reads the lock without taking it" {
  run bash "$LANE" --status
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'lane lock FREE'
  [ ! -d "$CC_CLOUD_STATE/.lane.lock" ]
  [ ! -s "$CALLS" ]
}

@test "the ANSWER pass runs third and journals its tally, so a routed question has a record" {
  run bash "$LANE"
  [ "$status" -eq 0 ]
  [ "$(sed -n 3p "$CALLS" | cut -d' ' -f1)" = answer ]
  a="$(row cloud-answer)"; [ -n "$a" ]
  [ "$(printf '%s' "$a" | jq -r '.tool')" = cloud-return-lane ]
  [ "$(printf '%s' "$a" | jq -r '.cloud_answer_rc')" = "0" ]
  printf '%s' "$a" | jq -e '.bound_s == 300' >/dev/null
  printf '%s' "$a" | jq -e '.tally | test("read 4 active session")' >/dev/null
}

@test "PLACEMENT: a return pass KILLED at its bound does not starve the answer pass" {
  # This is the whole reason the answer pass is a separate pass rather than a step under the
  # return sweep. On this box every tick since 09-04 ended `return pass rc=137 — cut by the lane
  # bound`: one land legitimately costs 700-3,900 s inside 5,400 s. Anything sequenced INSIDE that
  # pass is unreachable by construction, so the property that has to hold is exactly this one —
  # the killed child ends a command, not the script, and the passes below it still run.
  # The kill is simulated by rc, exactly as case 4 does: 137 is the signature this lane records
  # on every real cut, and asserting on it deterministically beats racing a real timeout.
  RETURN_RC=137 run bash "$LANE"
  [ "$status" -eq 0 ]
  [ "$(row cloud-return | jq -r '.cloud_return_rc')" = "137" ]
  printf '%s' "$(row cloud-return)" | jq -e '.note | test("cut by the lane bound")' >/dev/null
  grep -q '^answer' "$CALLS"
  [ "$(row cloud-answer | jq -r '.cloud_answer_rc')" = "0" ]
}

@test "CC_LANE_ANSWER=0 disables the answer pass, journalled skipped with null fields" {
  CC_LANE_ANSWER=0 run bash "$LANE"
  [ "$status" -eq 0 ]
  if grep -q '^answer' "$CALLS"; then echo "answer ran while disabled"; return 1; fi
  a="$(row cloud-answer)"
  [ "$(printf '%s' "$a" | jq -r '.cloud_answer_rc')" = "skipped" ]
  printf '%s' "$a" | jq -e '.elapsed_s == null' >/dev/null
}

# ── the fire-lane observation (§0), added 2026-09-12 by DRAIN_CIRCUIT W11 ────────────────────────
# The lane RETURNS what the fire lane produced; nothing observed whether the fire lane is still
# producing. These cases pin the three properties that make the added read worth having: it runs
# FIRST (so nothing below can starve it), it journals a TYPED reading, and it journals `null` —
# never a zero — whenever the instrument did not actually answer.

# a stub standing in for scripts/cloud-lane-liveness.sh, resolved from the lane's own directory
liveness() { # $1 rc  $2 stdout
  cat >"$D/cloud-lane-liveness.sh" <<EOF
#!/bin/bash
echo "fire \$*" >>"\$CALLS"
printf '%s' '$2'
exit $1
EOF
  chmod +x "$D/cloud-lane-liveness.sh"
}

@test "the fire-lane read runs FIRST and journals the instrument's TYPED reading" {
  liveness 0 '{"verdict":"LIVE","why":"last fire 3.04 h ago","open_gap_h":3.04,"stalls_in_window":3}'
  run bash "$LANE"
  [ "$status" -eq 0 ] || false
  # FIRST is the property: nothing below it can starve a read it does not depend on.
  [ "$(sed -n 1p "$CALLS" | cut -d' ' -f1)" = fire ] || false
  [ "$(sed -n 2p "$CALLS" | cut -d' ' -f1)" = return ] || false
  g="$(row cloud-fire-gap)"; [ -n "$g" ] || false
  [ "$(printf '%s' "$g" | jq -r '.tool')" = cloud-return-lane ] || false
  [ "$(printf '%s' "$g" | jq -r '.gap.verdict')" = "LIVE" ] || false
  # NB precedence: `A and .elapsed_s | type != "string"` pipes the whole conjunction into `type`
  # and is vacuously true. Parenthesise, or the second half asserts nothing.
  printf '%s' "$g" | jq -e '.gap.open_gap_h == 3.04 and (.elapsed_s | type) == "number"' >/dev/null || false
}

@test "a STALLED verdict is a READING, not a lane failure — it is journalled and the tick goes on" {
  liveness 1 '{"verdict":"STALLED","why":"silent for 35.78 h","open_gap_h":35.78}'
  run bash "$LANE"
  [ "$status" -eq 0 ] || false
  [ "$(row cloud-fire-gap | jq -r '.gap.verdict')" = "STALLED" ] || false
  [ "$(row cloud-fire-gap | jq -r '.fire_read_rc')" = "1" ] || false
  # the passes below still ran — an observation must never become a gate on the lane's own work
  [ "$(row cloud-return | jq -r '.cloud_return_rc')" = "0" ] || false
}

@test "an UNKNOWN reading is journalled AS UNKNOWN — the sensor's own nulls survive the journal" {
  liveness 3 '{"verdict":"UNKNOWN","why":"cannot look","open_gap_h":null,"rate_per_day":null}'
  run bash "$LANE"
  [ "$status" -eq 0 ] || false
  [ "$(row cloud-fire-gap | jq -r '.gap.verdict')" = "UNKNOWN" ] || false
  printf '%s' "$(row cloud-fire-gap)" | jq -e '.gap.open_gap_h == null' >/dev/null || false
}

@test "an ABSENT instrument journals a null gap and a skipped rc — never a zeroed reading" {
  rm -f "$D/cloud-lane-liveness.sh"
  run bash "$LANE"
  [ "$status" -eq 0 ] || false
  g="$(row cloud-fire-gap)"; [ -n "$g" ] || false
  [ "$(printf '%s' "$g" | jq -r '.fire_read_rc')" = "skipped" ] || false
  printf '%s' "$g" | jq -e '.gap == null and .elapsed_s == null' >/dev/null || false
}

@test "a CUT or garbled read journals null — one malformed value would abort every slurp" {
  liveness 124 '{"verdict":"LIV'      # half a line, exactly what a kill mid-write leaves
  run bash "$LANE"
  [ "$status" -eq 0 ] || false
  g="$(row cloud-fire-gap)"; [ -n "$g" ] || false
  printf '%s' "$g" | jq -e '.gap == null' >/dev/null || false
  [ "$(printf '%s' "$g" | jq -r '.fire_read_rc')" = "124" ] || false
  # the journal itself must still be wholly parseable — the property the guard exists for
  jq -e . "$CC_IDL" >/dev/null || false
}
