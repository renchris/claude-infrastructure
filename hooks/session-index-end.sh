#!/bin/bash
# SessionEnd hook — indexes the just-completed session.
# Reads session metadata from stdin JSON, looks up rich data from sessions-index.json.
# Performance target: <200ms.
set -euo pipefail

# Read stdin (hook provides JSON with session_id, transcript_path, cwd)
INPUT=$(cat)

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)

# Fast exit if no session ID
[ -z "$SESSION_ID" ] && exit 0

# Resolve helpers — follow symlink to repo
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPERS="$SCRIPT_DIR/lib/session-index-helpers.sh"
if [ ! -f "$HELPERS" ]; then
    # Fallback: try the repo location directly
    HELPERS="$HOME/.claude/hooks/lib/session-index-helpers.sh"
fi
[ -f "$HELPERS" ] || exit 0
source "$HELPERS"

# Init DB (idempotent)
session_index_init_db

# Non-blocking lock — skip if backfill/tagger is running (hook must be <200ms)
if ! session_index_trylock; then
    session_index_log "Skipped indexing $SESSION_ID (lock held by another process)"
    exit 0
fi

# Derive project directory from transcript path or cwd
PROJECT_DIR=""
if [ -n "$TRANSCRIPT_PATH" ]; then
    PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")
elif [ -n "$CWD" ]; then
    # Encode cwd to project dir name: /Users/chrisren/Dev/foo → -Users-chrisren-Dev-foo
    encoded=$(echo "$CWD" | sed 's|/|-|g')
    PROJECT_DIR="$CLAUDE_PROJECTS_DIR/$encoded"
fi

# Derive project path from cwd or directory name
PROJECT_PATH="${CWD:-}"
if [ -z "$PROJECT_PATH" ] && [ -n "$PROJECT_DIR" ]; then
    dir_name=$(basename "$PROJECT_DIR")
    PROJECT_PATH=$(echo "$dir_name" | sed 's/^-/\//' | sed 's/-/\//g')
fi
PROJECT_NAME=$(session_index_project_name "${PROJECT_PATH:-unknown}")

# Try sessions-index.json first (richest source)
SUMMARY="" FIRST_PROMPT="" GIT_BRANCH="" CREATED_AT="" MODIFIED_AT="" MSG_COUNT=0
if [ -n "$PROJECT_DIR" ]; then
    ENTRY=$(session_index_lookup_sessions_index "$PROJECT_DIR" "$SESSION_ID" 2>/dev/null || echo "")
    if [ -n "$ENTRY" ]; then
        IFS=$'\t' read -r SUMMARY FIRST_PROMPT GIT_BRANCH CREATED_AT MODIFIED_AT MSG_COUNT <<< "$ENTRY"
    fi
fi

# Fallback: extract from transcript first lines
if [ -z "$SUMMARY" ] && [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    # First user message from transcript JSONL
    FIRST_PROMPT=$(head -50 "$TRANSCRIPT_PATH" 2>/dev/null | \
        jq -r 'select(.type == "human") | .message.content // empty' 2>/dev/null | \
        head -1 | cut -c1-500)
fi

# Defaults
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
[ -z "$CREATED_AT" ] && CREATED_AT="$NOW"
[ -z "$MODIFIED_AT" ] && MODIFIED_AT="$NOW"
[ -z "$MSG_COUNT" ] || [ "$MSG_COUNT" = "null" ] && MSG_COUNT=0

# Extract context text from transcript (first 5 user messages)
CONTEXT_TEXT=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    CONTEXT_TEXT=$(session_index_extract_context "$TRANSCRIPT_PATH" 5)
fi

# Extract enriched data (assistant text, file paths, commands)
ASSISTANT_TEXT="" FILES_CHANGED="" COMMANDS_RUN=""
if [ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ]; then
    ENRICHED=$(session_index_extract_enriched "$TRANSCRIPT_PATH")
    IFS=$'\t' read -r ASSISTANT_TEXT FILES_CHANGED COMMANDS_RUN <<< "$ENRICHED"
fi

# Extract keywords
KEYWORDS=$(session_index_extract_keywords "$SUMMARY $FIRST_PROMPT $CONTEXT_TEXT")

# Upsert
session_index_upsert_with_fts \
    "$SESSION_ID" \
    "$PROJECT_PATH" \
    "$PROJECT_NAME" \
    "$SUMMARY" \
    "$FIRST_PROMPT" \
    "$GIT_BRANCH" \
    "$CREATED_AT" \
    "$MODIFIED_AT" \
    "$MSG_COUNT" \
    "" \
    "$KEYWORDS" \
    "sessions-index" \
    "$CONTEXT_TEXT" \
    "$ASSISTANT_TEXT" \
    "$FILES_CHANGED" \
    "$COMMANDS_RUN" \
    ""

session_index_log "Indexed session $SESSION_ID ($PROJECT_NAME, ${MSG_COUNT} msgs)"
exit 0
