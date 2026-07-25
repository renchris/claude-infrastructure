#!/usr/bin/env bats
# subagent-stop.sh — D-12 v1. The ONE contract this hook has is FAIL-OPEN: whatever arrives on
# stdin, it exits 0 and it never dies mid-way. Its payload schema is UNDOCUMENTED, so every field
# read is a guess with a fallback, and every case below is also a schema-shape fixture.
#
# HERMETIC: all four sinks (IDL, schema log, report index, state dir) are redirected into
# BATS_TEST_TMPDIR via the env seams; nothing touches the live ~/.claude.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO_ROOT/hooks/subagent-stop.sh"
  export SUBAGENT_STOP_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export SUBAGENT_STOP_LOG="$BATS_TEST_TMPDIR/subagent-stop.log"
  export SUBAGENT_STOP_REPORTS="$BATS_TEST_TMPDIR/subagent-reports.log"
  export SUBAGENT_STOP_STATE="$BATS_TEST_TMPDIR/state"
}

fire() { printf '%s' "$1" | "$HOOK"; }

# ── the fail-open contract ──────────────────────────────────────────────────────────────────────

@test "snake_case payload: exit 0" {
  run fire '{"session_id":"s1","agent_name":"tm-gates","transcript_path":"/tmp/x.jsonl"}'
  [ "$status" -eq 0 ]
}

@test "camelCase payload: exit 0" {
  run fire '{"sessionId":"s2","agentName":"deep-research","transcriptPath":"/tmp/y.jsonl"}'
  [ "$status" -eq 0 ]
}

@test "nested-object payload: exit 0" {
  run fire '{"session":{"id":"s3"},"agent":{"name":"explore"},"finalMessage":"done"}'
  [ "$status" -eq 0 ]
}

@test "empty object (no fields at all): exit 0" {
  run fire '{}'
  [ "$status" -eq 0 ]
}

@test "malformed JSON: exit 0" {
  run fire 'not json{{{'
  [ "$status" -eq 0 ]
}

@test "empty stdin: exit 0" {
  run fire ''
  [ "$status" -eq 0 ]
}

@test "hostile field values (quotes, backslashes, newlines) : exit 0" {
  run fire '{"session_id":"a\"b\\c","agent_name":"x\ny","final_message":"he said \"hi\"\nthen left"}'
  [ "$status" -eq 0 ]
}

@test "unknown-schema payload with none of the expected spellings: exit 0" {
  run fire '{"weird":{"deeply":{"nested":1}},"totally_new_field":"v"}'
  [ "$status" -eq 0 ]
}

# ── the telemetry it exists to produce ──────────────────────────────────────────────────────────

@test "every invocation appends exactly one IDL line" {
  fire '{"session_id":"s1"}'
  fire '{}'
  fire 'garbage'
  [ "$(wc -l < "$SUBAGENT_STOP_IDL")" -eq 3 ]
}

@test "the IDL line carries actor=subagent-stop and kind=subagent_end" {
  fire '{"session_id":"s1","agent_name":"tm-gates"}'
  run jq -r '[.actor,.kind,.sid,.agent] | @tsv' "$SUBAGENT_STOP_IDL"
  [ "$status" -eq 0 ]
  [[ "$output" == "subagent-stop"$'\t'"subagent_end"$'\t'"s1"$'\t'"tm-gates" ]]
}

@test "the IDL line also carries .hook + .disposition (idl-abstain-alarm's schema)" {
  fire '{"session_id":"s1"}'
  run jq -r 'select(.hook != null and .disposition != null) | .disposition' "$SUBAGENT_STOP_IDL"
  [ -n "$output" ]
}

@test "every IDL line is valid JSON even for hostile input" {
  fire '{"session_id":"a\"b\\c","agent_name":"x\ny"}'
  fire 'garbage'
  run jq -e -s 'length == 2' "$SUBAGENT_STOP_IDL"
  [ "$status" -eq 0 ]
}

@test "malformed payload abstains (never claims to have observed a subagent)" {
  fire 'garbage'
  run jq -r '.disposition + ":" + .reason' "$SUBAGENT_STOP_IDL"
  [ "$output" = "abstained:unparseable-payload" ]
}

@test "a payload with a transcript path writes a report POINTER, not the body" {
  fire '{"session_id":"s1","agent_name":"tm-gates","transcript_path":"/tmp/nope.jsonl"}'
  [ -f "$SUBAGENT_STOP_REPORTS" ]
  run jq -r '.transcript' "$SUBAGENT_STOP_REPORTS"
  [ "$output" = "/tmp/nope.jsonl" ]
}

@test "a final message is indexed by length + a capped head, never copied whole" {
  long="$(printf 'x%.0s' $(seq 1 5000))"
  fire "{\"session_id\":\"s1\",\"final_message\":\"$long\"}"
  run jq -r '[(.final_chars|tostring),(.final_head|length|tostring)] | @tsv' "$SUBAGENT_STOP_REPORTS"
  [[ "$output" == "5000"$'\t'"200" ]]
}

@test "a payload with no report at all writes NO pointer line" {
  fire '{"session_id":"s1"}'
  [ ! -f "$SUBAGENT_STOP_REPORTS" ]
  run jq -r '.disposition + ":" + .reason' "$SUBAGENT_STOP_IDL"
  [ "$output" = "passed:no-report-in-payload" ]
}

@test "schema discovery logs the leaf key paths once per shape" {
  fire '{"session_id":"s1","agent_name":"a"}'
  fire '{"session_id":"s2","agent_name":"b"}'
  [ "$(grep -c 'subagent-stop schema:' "$SUBAGENT_STOP_LOG")" -eq 1 ]
  run cat "$SUBAGENT_STOP_LOG"
  [[ "$output" == *"keys=[agent_name,session_id]"* ]]
}

@test "a NEW payload shape is logged even on the same day" {
  fire '{"session_id":"s1"}'
  fire '{"sessionId":"s2","agent":{"name":"x"}}'
  [ "$(grep -c 'subagent-stop schema:' "$SUBAGENT_STOP_LOG")" -eq 2 ]
}

@test "the hook never writes outside its four declared sinks" {
  fire '{"session_id":"s1","agent_name":"a","transcript_path":"/tmp/x.jsonl"}'
  run bash -c "ls -A '$BATS_TEST_TMPDIR' | sort | tr '\n' ' '"
  [ "$output" = "idl.jsonl state subagent-reports.log subagent-stop.log " ]
}
