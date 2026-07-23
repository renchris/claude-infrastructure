#!/usr/bin/env bats
# handoff-teardown-marker.bats — the teardown-marker contract v1 + never-engaged telemetry.
#
# WHY: a self-close/--recycle types /exit, which INTERRUPTS the in-flight turn and kills the pane
# mid-Bash — to the crash watchdog that death is indistinguishable from a real CC crash (false
# CRASHes), and a fire that never engaged logged NO telemetry at all. handoff-fire.sh now drops a
# deterministic teardown marker immediately before the first /exit, and records engaged=0 on a
# failed engagement.
#
# These assert the WRITER side of the contract by driving the REAL functions — extracted VERBATIM
# from scripts/handoff-fire.sh and sourced — so a fixture is the function's LITERAL emission, never
# a hand-written approximation that could pass while the live shape drifts.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  HOME="$BATS_TEST_TMPDIR/home"; export HOME          # sandbox every $HOME write (fresh per test)
  TD="$HOME/.claude/watchdog/teardown"
  HJ="$HOME/.claude/logs/handoffs.jsonl"
  # The bats process itself runs inside a CC session that likely EXPORTS SESSION_ID — clear the slate
  # so the "unset" cases are real and the "set" cases come only from the per-call prefix.
  unset SESSION_ID FIRING_SID WANT_SELF_RETIRE SPAWNED_PANE CHOSEN 2>/dev/null || true
  # Extract the two functions VERBATIM so we assert on their literal emission.
  FUNCS="$BATS_TEST_TMPDIR/funcs.sh"
  {
    sed -n '/^write_teardown_marker() {/,/^}/p' "$HF"
    sed -n '/^  emit_handoff_telemetry() {/,/^  }$/p' "$HF"
  } > "$FUNCS"
  # shellcheck disable=SC1090
  source "$FUNCS"
}

json_ok() { # $1 = file → assert it parses as one JSON object (skip if no python3)
  command -v python3 >/dev/null || skip "python3 not available"
  run python3 -c "import json,sys; json.loads(open(sys.argv[1]).read().strip())" "$1"
  [ "$status" -eq 0 ]
}

# ---- teardown marker: key selection + field shape --------------------------------------------

@test "marker: SESSION_ID set → sid-keyed file, key_kind=sid, mode preserved" {
  SESSION_ID="cc-sid-123" write_teardown_marker "pane-AAA" terminal
  [ -f "$TD/cc-sid-123.json" ]                        # keyed by the CC session id, not the pane
  run cat "$TD/cc-sid-123.json"
  [[ "$output" == *'"key_kind":"sid"'* ]]
  [[ "$output" == *'"pane":"pane-AAA"'* ]]
  [[ "$output" == *'"sid":"cc-sid-123"'* ]]
  [[ "$output" == *'"mode":"terminal"'* ]]
  [[ "$output" == *'"ts":"'* ]]
  json_ok "$TD/cc-sid-123.json"
}

@test "marker: SESSION_ID unset → pane-keyed fallback, key_kind=pane, sid empty" {
  unset SESSION_ID || true
  write_teardown_marker "pane-BBB" recycle
  [ -f "$TD/pane-BBB.json" ]                          # keyed by the pane uuid
  [ ! -e "$TD/.json" ]                               # empty-key file never created
  run cat "$TD/pane-BBB.json"
  [[ "$output" == *'"key_kind":"pane"'* ]]
  [[ "$output" == *'"pane":"pane-BBB"'* ]]
  [[ "$output" == *'"sid":""'* ]]
  [[ "$output" == *'"mode":"recycle"'* ]]
  json_ok "$TD/pane-BBB.json"
}

@test "marker: successor mode is recorded verbatim" {
  SESSION_ID="cc-sid-9" write_teardown_marker "pane-CCC" successor
  run cat "$TD/cc-sid-9.json"
  [[ "$output" == *'"mode":"successor"'* ]]
}

@test "marker: empty pane AND empty SESSION_ID → guard writes nothing, returns 0" {
  unset SESSION_ID || true
  run write_teardown_marker "" ""
  [ "$status" -eq 0 ]                                 # never blocks the close
  [ ! -e "$TD" ] || [ -z "$(ls -A "$TD" 2>/dev/null)" ]   # no garbage marker
}

# ---- never-engaged telemetry ------------------------------------------------------------------

@test "telemetry: emit 0 appends an engaged=0 line to handoffs.jsonl (failed engagement)" {
  FIRING_SID="cc-sid-x" SESSION_ID="cc-sid-x" SPAWNED_PANE="pane-DDD" CHOSEN="next2" \
    emit_handoff_telemetry 0
  [ -f "$HJ" ]
  run cat "$HJ"
  [[ "$output" == *'"engaged":0'* ]]
  [[ "$output" == *'"firing_sid":"cc-sid-x"'* ]]
  [[ "$output" == *'"target_pane":"pane-DDD"'* ]]
  [[ "$output" == *'"account":"next2"'* ]]
  [[ "$output" == *'"class":"handoff"'* ]]
  json_ok "$HJ"
}

@test "telemetry: firing_rss_kb is keyed by SESSION_ID, not the pane FIRING_SID" {
  # The pidfile lives at the SESSION-ID key; FIRING_SID is a DIFFERENT (pane) value that must NOT
  # match. Pre-fix the lookup used $FIRING_SID → miss → firing_rss_kb:0; post-fix it finds the pid.
  mkdir -p "$HOME/.claude/watchdog"
  printf '%s\n' "$$" > "$HOME/.claude/watchdog/cc-sid-rss.pid"
  FIRING_SID="pane-NOMATCH" SESSION_ID="cc-sid-rss" SPAWNED_PANE="pane-EEE" CHOSEN="next" \
    emit_handoff_telemetry 1
  run cat "$HJ"
  [[ "$output" == *'"engaged":1'* ]]
  [[ "$output" != *'"firing_rss_kb":0}'* ]]          # rss found ⇒ lookup used SESSION_ID
}
