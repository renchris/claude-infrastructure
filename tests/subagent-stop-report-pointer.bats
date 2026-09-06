#!/usr/bin/env bats
# subagent-stop-report-pointer — the SubagentStop consumer must index a subagent's report using the
# schema the harness ACTUALLY sends, and must stay non-blocking.
#
# WHAT THIS EXISTS TO PIN. hooks/subagent-stop.sh v1 was written before the payload was measured and
# says so in its own header ("the payload SCHEMA IS NOT DOCUMENTED"). HOOK_SURFACE_100P W1 measured
# it (/tmp/hs/log/sub3.tsv, 2.1.220), and two of v1's guesses were wrong in a way that made the hook
# QUIETER THAN IT LOOKED rather than broken:
#   · the report body is `last_assistant_message`, which v1's fallback chain does not contain — so
#     every pointer line it had ever written recorded final_chars:0. A harvest index existed and
#     pointed at nothing. This is the same shape as the sibling defect in tests/log-bash-exit-code:
#     a hook that logs a real-looking record whose payload-derived field is always the default.
#   · `agent_id` was not read at all — the only field joining this record to the SubagentStart that
#     opened the agent, and the one that tells two concurrent agents of the same type apart.
# The CONTROL at the bottom replays the REAL pre-fix script out of git against the REAL payload and
# requires it to give the wrong answer.
#
# NON-BLOCKING is pinned here, not merely intended. SubagentStop is Stop-family: `decision:"block"`
# or `hookSpecificOutput.additionalContext` on stdout extends the turn and increments the harness's
# consecutive-block counter (capped at 8). So stdout must be EMPTY on every path, and the exit
# always 0 — asserted across the real payload, malformed input, empty input, and no jq.
#
# Hermetic: HOME is redirected into BATS_TEST_TMPDIR and all four of the subject's env seams point
# into it, so nothing here reads or writes the operator's live ~/.claude.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/subagent-stop.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export SUBAGENT_STOP_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export SUBAGENT_STOP_LOG="$BATS_TEST_TMPDIR/schema.log"
  export SUBAGENT_STOP_REPORTS="$BATS_TEST_TMPDIR/reports.log"
  export SUBAGENT_STOP_STATE="$BATS_TEST_TMPDIR/state"
}

# Captured verbatim from a 2.1.220 run (/tmp/hs/log/sub3.tsv). Do not "tidy" this — a suite proving
# a script works on a payload nobody sends proves nothing about production.
real_payload() {   # $1 = agent_id (default the measured one)  $2 = the report body
  local aid="${1:-a98cd5803b06f1084}" body="${2:-ping}"
  cat <<JSON
{"session_id":"68f0f48f-2776-4c7f-9f75-93623105d8f7",
 "transcript_path":"/tmp/hs/68f0f48f.jsonl","cwd":"/private/tmp/hs/scratch",
 "prompt_id":"9df61632","permission_mode":"auto","agent_id":"${aid}",
 "agent_type":"general-purpose","effort":{"level":"low"},"hook_event_name":"SubagentStop",
 "stop_hook_active":false,
 "agent_transcript_path":"/tmp/hs/subagents/agent-${aid}.jsonl",
 "last_assistant_message":"${body}","background_tasks":[],"session_crons":[]}
JSON
}

pointer() { tail -1 "$SUBAGENT_STOP_REPORTS"; }

# ---- the measured schema ------------------------------------------------------------------------
@test "the report body is indexed — final_chars is the real length, not 0" {
  real_payload a1 "the wave found three stranded branches" | bash "$HOOK"
  pointer | jq -e '.final_chars == 38' >/dev/null || false
  pointer | jq -e '.final_head | test("three stranded")' >/dev/null || false
}

@test "agent_id is carried — it is what joins this record to its SubagentStart" {
  real_payload a98cd5803b06f1084 | bash "$HOOK"
  pointer | jq -e '.agent_id == "a98cd5803b06f1084"' >/dev/null || false
  grep -q '"agent_id":"a98cd5803b06f1084"' "$SUBAGENT_STOP_IDL" || false
}

@test "two concurrent agents of the SAME type stay distinguishable" {
  real_payload aaa1 | bash "$HOOK"
  real_payload bbb2 | bash "$HOOK"
  # agent_type alone cannot separate these; agent_id is the whole reason the records are usable.
  [ "$(jq -r '.agent' "$SUBAGENT_STOP_REPORTS" | sort -u | wc -l | tr -d ' ')" -eq 1 ] || false
  [ "$(jq -r '.agent_id' "$SUBAGENT_STOP_REPORTS" | sort -u | wc -l | tr -d ' ')" -eq 2 ] || false
}

@test "the agent transcript path is preferred over the SESSION transcript path" {
  real_payload a1 | bash "$HOOK"
  # .transcript_path is also present in the payload and is the parent session's — indexing that one
  # would point every subagent report at the same file.
  pointer | jq -e '.transcript | test("subagents/agent-a1")' >/dev/null || false
}

@test "it is a POINTER, not a copy — a long report is not inlined" {
  local long; long="$(printf 'x%.0s' $(seq 1 5000))"
  real_payload a1 "$long" | bash "$HOOK"
  pointer | jq -e '.final_chars == 5000' >/dev/null || false
  [ "$(wc -c < "$SUBAGENT_STOP_REPORTS" | tr -d ' ')" -lt 600 ] || false
}

@test "the pointer line stays single-line and parseable when the report has a quote and a newline" {
  printf '%s' '{"session_id":"s","agent_id":"a1","agent_type":"general-purpose","agent_transcript_path":"/tmp/a.jsonl","last_assistant_message":"he said \"done\"\nthen left"}' | bash "$HOOK"
  [ "$(wc -l < "$SUBAGENT_STOP_REPORTS" | tr -d ' ')" -eq 1 ] || false
  jq -e -s 'length == 1' "$SUBAGENT_STOP_REPORTS" >/dev/null || false
}

@test "v1's guessed spellings still work — a rename degrades, it does not blank" {
  printf '%s' '{"session_id":"s","agent_name":"legacy","transcript":"/tmp/l.jsonl","final_message":"legacy body"}' | bash "$HOOK"
  pointer | jq -e '.agent == "legacy" and .final_head == "legacy body"' >/dev/null || false
}

# ---- non-blocking ------------------------------------------------------------------------------
@test "stdout is EMPTY and exit is 0 on every input shape — Stop-family, never a gate" {
  local shape
  for shape in '{"session_id":"s","agent_id":"a","agent_transcript_path":"/tmp/a.jsonl","last_assistant_message":"hi"}' \
               'not json at all' '{}' ''; do
    run bash -c "printf '%s' '$shape' | bash '$HOOK'"
    [ "$status" -eq 0 ] || false
    [ -z "$output" ] || false
  done
}

has_directive() { printf '%s' "${1:-}" | grep -qE '"decision"|additionalContext'; }

@test "it never emits a block directive on any path" {
  # POSITIVE CONTROL first: the detector can see these strings when they ARE present. Without it,
  # "no directive found" is indistinguishable from a grep that can never match.
  has_directive '{"decision":"block"}' || false
  has_directive '{"hookSpecificOutput":{"additionalContext":"x"}}' || false
  real_payload a1 > "$BATS_TEST_TMPDIR/p9.json"
  run bash -c "bash '$HOOK' < '$BATS_TEST_TMPDIR/p9.json'"
  [ "$status" -eq 0 ] || false
  ! has_directive "$output" || false
}

@test "with no jq on PATH it abstains quietly rather than dying" {
  run bash -c "printf '%s' '$(real_payload a1 | tr -d '\n')' | PATH=/usr/bin:/bin bash '$HOOK'"
  [ "$status" -eq 0 ] || false
}

@test "a payload with neither a transcript nor a report is LOGGED as passed, never silent" {
  printf '%s' '{"session_id":"s","agent_type":"general-purpose"}' | bash "$HOOK"
  grep -q '"disposition":"passed","reason":"no-report-in-payload"' "$SUBAGENT_STOP_IDL" || false
  [ ! -f "$SUBAGENT_STOP_REPORTS" ] || false
}

# ---- the control that must be able to FAIL -------------------------------------------------------
@test "CONTROL pre_fix_is_red: the shipped pre-fix script indexes an EMPTY report" {
  # Replays the REAL artifact out of git — not a hand-written imitation of it — against the REAL
  # payload. It must give the wrong answer: final_chars 0 and no agent_id at all. If this ever goes
  # green, the payload shape moved and every assertion above has stopped testing the defect.
  # 🚨 A LITERAL sha, never HEAD. HEAD is a MOVING ref: the moment the fix lands it becomes the
  # FIXED file, and this control then compares the fix to itself — passing vacuously forever. 8c591f8
  # is the commit that added the v1 hook, it is an ancestor of origin/main, and no commit touched
  # this file between it and the fix, so it IS the pre-fix artifact rather than a stand-in for one.
  local pre="$BATS_TEST_TMPDIR/pre-fix.sh"
  git -C "$REPO" show 8c591f8722d031514570b24931ee537b99bde8a0:hooks/subagent-stop.sh > "$pre" 2>/dev/null \
    || skip "pre-fix blob unreachable"
  [ -s "$pre" ] || false
  # The pin ALONE re-goes-vacuous if the sha is ever re-pointed, so assert MARKERS the fix
  # introduced are ABSENT from the replay. Both are measured against the two artifacts' real diff
  # (0 occurrences pre, 4 post), not read off the post-fix file's own explanatory prose.
  ! grep -q 'AGENT_ID' "$pre" || false
  ! grep -q 'last_assistant_message' "$pre" || false
  grep -q 'AGENT_ID' "$HOOK" || false
  grep -q 'last_assistant_message' "$HOOK" || false
  real_payload a98cd5803b06f1084 'a real report body' > "$BATS_TEST_TMPDIR/p12.json"
  SUBAGENT_STOP_REPORTS="$BATS_TEST_TMPDIR/pre-reports.log" \
  SUBAGENT_STOP_IDL="$BATS_TEST_TMPDIR/pre-idl.jsonl" \
  SUBAGENT_STOP_LOG="$BATS_TEST_TMPDIR/pre-schema.log" \
  SUBAGENT_STOP_STATE="$BATS_TEST_TMPDIR/pre-state" \
    bash "$pre" < "$BATS_TEST_TMPDIR/p12.json"
  local line; line="$(tail -1 "$BATS_TEST_TMPDIR/pre-reports.log")"
  printf '%s' "$line" | jq -e '.final_chars == 0' >/dev/null || false      # the report was lost
  printf '%s' "$line" | jq -e 'has("agent_id") | not' >/dev/null || false  # the id was never read
  # …and the CURRENT subject gets both right on the identical payload.
  real_payload a98cd5803b06f1084 'a real report body' | bash "$HOOK"
  pointer | jq -e '.final_chars == 18 and .agent_id == "a98cd5803b06f1084"' >/dev/null || false
}
