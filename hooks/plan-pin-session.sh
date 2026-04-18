#!/bin/bash
# ~/.claude/hooks/plan-pin-session.sh — PostToolUse hook on ExitPlanMode.
# Pins the session's plan file path to ~/.claude/sessions/<session-id>.plan
# so `current-session-plan.sh` L1 resolves in O(1).
#
# Mechanism: when ExitPlanMode succeeds, the harness writes the plan to
# a new ~/.claude/plans/<adjective-word-noun>.md file. We content-hash
# tool_input.plan vs all plan files and pick the exact match. Fallback:
# the file modified within the last 3 seconds (handles harness writes
# with trailing-whitespace normalization that would break SHA match).
#
# Non-blocking: always exits 0 on error paths. Never blocks the agent.

set -uo pipefail

command -v jq >/dev/null || exit 0

INPUT=$(cat 2>/dev/null || echo '{}')

TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL" == "ExitPlanMode" ]] || exit 0

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
PLAN_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.plan // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && exit 0
[ -z "$PLAN_CONTENT" ] && exit 0

PINS_DIR="$HOME/.claude/sessions"
mkdir -p "$PINS_DIR" 2>/dev/null || true
SIDECAR="$PINS_DIR/$SESSION_ID.plan"

# Strategy 1: SHA256 match against existing plan files.
TARGET_SHA=$(printf '%s' "$PLAN_CONTENT" | shasum -a 256 | awk '{print $1}')
for f in "$HOME"/.claude/plans/*.md; do
  [ -f "$f" ] || continue
  H=$(shasum -a 256 "$f" 2>/dev/null | awk '{print $1}')
  if [[ "$H" == "$TARGET_SHA" ]]; then
    printf '%s\n' "$f" > "$SIDECAR"
    exit 0
  fi
done

# Strategy 2: plan file modified within the last 3 seconds (handles harness
# normalization that breaks exact SHA match — trailing newline etc.).
RECENT=$(find "$HOME/.claude/plans" -maxdepth 1 -name '*.md' -type f \
  -newermt '3 seconds ago' 2>/dev/null | head -1)
if [ -n "$RECENT" ] && [ -f "$RECENT" ]; then
  printf '%s\n' "$RECENT" > "$SIDECAR"
fi

exit 0
