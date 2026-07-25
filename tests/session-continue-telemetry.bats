#!/usr/bin/env bats
# session-continue-telemetry — the auto-continue actuator must leave a trail (audit 09 D-11).
#
# `session-continue.sh` can emit {decision:"block"} up to CLAUDE_CONTINUE_MAX (8) times — it is
# the cross-turn auto-continue actuator — and it wrote NO IDL record and NO log, while all three
# of its Stop siblings (completion-assert, boundary-handoff, anti-deference-nudge) do. A runaway
# continuation or a wrongly-SUPPRESSED one was forensically invisible.
#
# Contract pinned here: every STATE CHANGE is recorded (armed · cleared{cli,kill-switch,
# sid-mismatch,cap} · fired) and the disarmed steady state is deliberately NOT — it fires on
# every Stop of every session and the sentinel's absence is itself the record.
#
# Harness laws: L1 records come from the REAL hook via its real CLI + real Stop payload; L2
# assertions key on the failure-distinct disposition/reason strings; L3 `[ ]` / `grep -q` only;
# L4 both a must-log and a must-NOT-log fixture, so an always-log bug goes RED too.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-continue.sh"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox";   mkdir -p "$CC_MAILBOX_DIR"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CONTINUE_LOG="$BATS_TEST_TMPDIR/session-continue.log"
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
}

arm()  { ( cd "$CWD" && CLAUDE_CODE_SESSION_ID="${2:-sidA}" bash "$HOOK" set "${1:-do the thing}" >/dev/null ); }
sc()   { ( cd "$CWD" && CLAUDE_CODE_SESSION_ID="${2:-sidA}" bash "$HOOK" "$1" >/dev/null ); }
actuate() { printf '{"cwd":"%s","session_id":"%s","transcript_path":"%s"}' "$CWD" "${1:-sidA}" "${2:-}" | bash "$HOOK" >/dev/null 2>&1; }

# last IDL record's <field>
idl_last() { jq -r "$1" "$CONTINUE_IDL" | tail -1; }
idl_count() { grep -c . "$CONTINUE_IDL" 2>/dev/null || printf '0'; }

mkuser_tx() { # transcript whose LAST user message is $1
  local path="$BATS_TEST_TMPDIR/tx-${BATS_TEST_NUMBER}.jsonl"
  jq -nc --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}' > "$path"
  printf '%s' "$path"
}

@test "CLI set writes an 'armed' IDL record + a log line" {
  arm "finish the gate"
  [ -f "$CONTINUE_IDL" ]
  [ "$(idl_last '.disposition')" = "armed" ]
  [ "$(idl_last '.reason')" = "cli-set" ]
  [ "$(idl_last '.hook')" = "session-continue" ]
  [ "$(idl_last '.sid')" = "sidA" ]
  [ "$(idl_last '.step')" = "finish the gate" ]
  grep -q 'armed' "$CONTINUE_LOG"
}

@test "CLI clear writes a 'cleared/cli-clear' record" {
  arm "x"; sc clear
  [ "$(idl_last '.disposition')" = "cleared" ]
  [ "$(idl_last '.reason')" = "cli-clear" ]
}

@test "a block writes a 'fired/continue' record carrying the counter" {
  arm "keep going"
  actuate sidA
  [ "$(idl_last '.disposition')" = "fired" ]
  [ "$(idl_last '.reason')" = "continue" ]
  [ "$(idl_last '.count')" = "1" ]
  [ "$(idl_last '.step')" = "keep going" ]
}

@test "the disarmed steady state writes NOTHING (no per-Stop IDL spam)" {
  actuate sidA
  [ "$(idl_count)" -eq 0 ]
  [ ! -s "$CONTINUE_LOG" ]
}

@test "the kill switch records why the sentinel was cleared" {
  arm "keep going"
  tx="$(mkuser_tx 'do the thing and stop')"
  actuate sidA "$tx"
  [ "$(idl_last '.disposition')" = "cleared" ]
  [ "$(idl_last '.reason')" = "kill-switch" ]
}

@test "a cross-succession sentinel records the sid mismatch" {
  arm "keep going" sidA
  actuate sidB
  [ "$(idl_last '.disposition')" = "cleared" ]
  [ "$(idl_last '.reason')" = "sid-mismatch" ]
  [ "$(idl_last '.stored_sid')" = "sidA" ]
  [ "$(idl_last '.session_sid')" = "sidB" ]
}

@test "hitting the cap records 'cap-reached' with the counter" {
  arm "grind"
  CLAUDE_CONTINUE_MAX=2 actuate sidA
  CLAUDE_CONTINUE_MAX=2 actuate sidA
  CLAUDE_CONTINUE_MAX=2 actuate sidA
  [ "$(idl_last '.disposition')" = "cleared" ]
  [ "$(idl_last '.reason')" = "cap-reached" ]
  [ "$(idl_last '.max')" = "2" ]
}

@test "every emitted IDL line is valid JSON even when the step carries quotes and newlines" {
  arm 'fix the "broken" gate
then land it'
  actuate sidA
  run jq -e . "$CONTINUE_IDL"
  [ "$status" -eq 0 ]
  [ "$(idl_count)" -eq 2 ]
}

@test "telemetry never changes the stop decision (block still emitted on stdout)" {
  arm "keep going"
  run bash -c "printf '{\"cwd\":\"$CWD\",\"session_id\":\"sidA\"}' | bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"decision":"block"'
}
