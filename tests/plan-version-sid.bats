#!/usr/bin/env bats
# plan-version-sid — the plan-history MANIFEST must carry the REAL session id (audit 09 D-9).
#
# `hooks/plan-version-commit.sh:42` read `${CLAUDE_SESSION_ID:-unknown}`. CLAUDE_SESSION_ID is
# NOT a hook environment variable — the only env var CC exports that this repo relies on is
# CLAUDE_PROJECT_DIR — so every MANIFEST.jsonl record was stamped `"session":"unknown"` and the
# version log could not be joined to a session. Session identity must come from the stdin JSON
# (the hooks/completion-assert.sh:54 pattern).
#
# Harness laws: L1 the fixture is the literal PostToolUse payload shape; L2 the assertion keys
# on the failure-distinct value ("unknown" vs the real sid); L3 `[ ]` / `grep -q` only;
# L4 a positive (sid present) AND a negative (sid absent → "unknown") fixture, so an
# always-"unknown" bug and an always-hardcoded-sid bug both go RED.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/plan-version-commit.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/plans"
  PLAN="$HOME/.claude/plans/DEMO_PLAN.md"
  printf '# demo plan\n\n- a\n' > "$PLAN"
  MANIFEST="$HOME/.claude/plan-versions/MANIFEST.jsonl"
}

payload() { # <file> <session_id-json>
  jq -nc --arg f "$1" --argjson s "$2" \
    '{session_id:$s,hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{file_path:$f}}'
}

@test "MANIFEST record carries the stdin session_id, not 'unknown'" {
  payload "$PLAN" '"sid-plan-111"' | bash "$HOOK"
  [ -f "$MANIFEST" ]
  run jq -r '.session' "$MANIFEST"
  [ "$output" = "sid-plan-111" ]
}

@test "a stale CLAUDE_SESSION_ID env var never overrides the stdin session_id" {
  CLAUDE_SESSION_ID="stale-env-sid" bash -c "printf '%s' '$(payload "$PLAN" '"sid-plan-222"')' | bash '$HOOK'"
  run jq -r '.session' "$MANIFEST"
  [ "$output" = "sid-plan-222" ]
}

@test "falls back to 'unknown' when the payload carries no session_id" {
  jq -nc --arg f "$PLAN" '{hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{file_path:$f}}' \
    | bash "$HOOK"
  run jq -r '.session' "$MANIFEST"
  [ "$output" = "unknown" ]
}

@test "a non-plan file is still skipped (no MANIFEST record)" {
  other="$BATS_TEST_TMPDIR/notes.md"
  printf 'not a plan\n' > "$other"
  payload "$other" '"sid-plan-333"' | bash "$HOOK"
  [ ! -f "$MANIFEST" ]
}
