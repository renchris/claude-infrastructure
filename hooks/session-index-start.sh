#!/bin/bash
# SessionStart hook — injects recent session context.
# Performance target: <100ms.
set -euo pipefail

# Read stdin
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

# Resolve helpers
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/lib/session-index-helpers.sh"
if [ ! -f "$HELPERS" ]; then
    HELPERS="$HOME/.claude/hooks/lib/session-index-helpers.sh"
fi

# Fast exit if no DB or helpers
[ -f "$HELPERS" ] || exit 0
source "$HELPERS"
[ -f "$SESSION_INDEX_DB" ] || exit 0

# Generate context via Python (fast, <50ms with warm Python)
CONTEXT=$(python3 "$HOME/.claude/bin/session-search.py" --context-inject "${CWD:-$HOME}" 2>/dev/null || echo "")

if [ -n "$CONTEXT" ]; then
    # Escape for JSON
    ESCAPED=$(echo "$CONTEXT" | jq -Rs .)
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": $ESCAPED
  }
}
EOF
fi

# ─── Layer 1: Crash-safe stub row ────────────────────────
# Create a minimal index row so this session is discoverable even if
# SessionEnd never fires (terminal kill, crash, etc.).
# Runs in a subshell backgrounded to stay under 100ms total.
(
    SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
    [ -z "$SESSION_ID" ] && exit 0

    session_index_init_db

    # Derive project info from CWD (same pattern as session-index-end.sh)
    PROJECT_PATH="${CWD:-}"
    if [ -z "$PROJECT_PATH" ]; then
        PROJECT_PATH="unknown"
    fi
    PROJECT_NAME=$(session_index_project_name "$PROJECT_PATH")

    NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # UPSERT stub — lower priority source so SessionEnd always wins
    session_index_upsert_with_fts \
        "$SESSION_ID" \
        "$PROJECT_PATH" \
        "$PROJECT_NAME" \
        "" \
        "" \
        "" \
        "$NOW" \
        "$NOW" \
        0 \
        "" \
        "" \
        "session-start" \
        "" \
        "" \
        "" \
        "" \
        ""

    session_index_log "Stub indexed for $SESSION_ID ($PROJECT_NAME)"
) &

exit 0
