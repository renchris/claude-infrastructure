#!/bin/bash
# SessionEnd hook — saves session ID for instant resume.
# Writes to:
#   1. ~/.claude/.last-session              (global, any-project quick resume)
#   2. ~/.claude/projects/<hash>/.last-session-id  (per-project resume)
# Performance target: <10ms (two atomic writes, no subprocesses beyond jq).
set -euo pipefail

INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
REASON=$(echo "$INPUT" | jq -r '.reason // empty' 2>/dev/null)

# Nothing to save if no session ID
[ -z "$SESSION_ID" ] && exit 0

# Skip saving on "clear" — the session is being wiped, not ended
[ "$REASON" = "clear" ] && exit 0

# 1. Global last-session file
GLOBAL_FILE="$HOME/.claude/.last-session"
printf '%s\n' "$SESSION_ID" > "$GLOBAL_FILE"

# 2. Per-project last-session-id
PROJECT_DIR=""
if [ -n "$TRANSCRIPT_PATH" ]; then
  PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")
elif [ -n "$CWD" ]; then
  encoded=$(echo "$CWD" | sed 's|/|-|g')
  PROJECT_DIR="$HOME/.claude/projects/$encoded"
fi

if [ -n "$PROJECT_DIR" ] && [ -d "$PROJECT_DIR" ]; then
  printf '%s\n' "$SESSION_ID" > "$PROJECT_DIR/.last-session-id"
fi

exit 0
