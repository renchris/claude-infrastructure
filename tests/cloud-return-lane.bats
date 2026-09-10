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
