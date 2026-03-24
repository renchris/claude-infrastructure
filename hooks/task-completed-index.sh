#!/bin/bash
set -euo pipefail
# TaskCompleted Hook - Regenerate summary and TASKS.md for the active task list.
# Works with UUID-based task lists (auto-detected), not just named ones.

# shellcheck source=lib/task-helpers.sh
. "$(dirname "$0")/lib/task-helpers.sh"

TASK_LIST_ID="${CLAUDE_CODE_TASK_LIST_ID:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
INDEX="$HOME/.claude/tasks-index.json"
FILTERED_DIR=".claude-tasks"

# Determine the active task list — prefer .active-list-id, fall back to detection
ACTIVE_ID=""
if [ -f "$FILTERED_DIR/.active-list-id" ]; then
    ACTIVE_ID=$(cat "$FILTERED_DIR/.active-list-id" 2>/dev/null)
fi
# Validate the stored ID still has tasks
if [ -n "$ACTIVE_ID" ] && [ ! -d "$TASKS_DIR/$ACTIVE_ID" ]; then
    ACTIVE_ID=""
fi
# Fall back to auto-detection
if [ -z "$ACTIVE_ID" ]; then
    ACTIVE_ID=$(find_active_list)
fi
# Final fall back to named list
EFFECTIVE_ID="${ACTIVE_ID:-$TASK_LIST_ID}"
[ -z "$EFFECTIVE_ID" ] && exit 0

TASK_DIR="$TASKS_DIR/$EFFECTIVE_ID"
[ ! -d "$TASK_DIR" ] && exit 0

# Cleanup temp files on any exit
TEMP=""
cleanup() { [ -n "$TEMP" ] && rm -f "$TEMP"; }
trap cleanup EXIT

# Update index if it exists
if [ -n "$TASK_LIST_ID" ] && [ -f "$INDEX" ]; then
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    TASK_COUNT=$(find "$TASK_DIR" -maxdepth 1 -name '*.json' ! -name '_summary.json' 2>/dev/null | wc -l | tr -d ' ')
    case "$TASK_COUNT" in ''|*[!0-9]*) TASK_COUNT=0 ;; esac

    TEMP=$(mktemp)
    if jq --arg listid "$TASK_LIST_ID" \
       --arg now "$NOW" \
       --argjson taskCount "$TASK_COUNT" \
       'if .taskLists[$listid] then
          .taskLists[$listid].lastSeen = $now |
          .taskLists[$listid].taskCount = $taskCount |
          .generated = $now
        else . end' \
       "$INDEX" > "$TEMP" 2>/dev/null; then
        mv "$TEMP" "$INDEX"
        TEMP=""
    fi
fi

# Regenerate _summary.json
regenerate_summary "$TASK_DIR"

# Update _current symlink (in case it drifted)
if [ -n "$EFFECTIVE_ID" ]; then
    ln -sfn "$TASK_DIR" "$FILTERED_DIR/_current" 2>/dev/null || true
    echo "$EFFECTIVE_ID" > "$FILTERED_DIR/.active-list-id" 2>/dev/null || true
fi

# Regenerate TASKS.md
SUMMARY="$TASK_DIR/_summary.json"
if [ -f "$SUMMARY" ]; then
    generate_tasks_md "$SUMMARY" "$FILTERED_DIR/TASKS.md" "$PROJECT_DIR"
fi

exit 0
