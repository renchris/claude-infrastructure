#!/bin/bash
# PostToolUse Hook (TaskCreate|TaskUpdate) - Detect active task list,
# regenerate summary, and update TASKS.md.

# shellcheck source=lib/task-helpers.sh
. "$(dirname "$0")/lib/task-helpers.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
FILTERED_DIR=".claude-tasks"

# Find the active task list (most recently modified — Claude just wrote to it)
ACTIVE_ID=$(find_active_list)
[ -z "$ACTIVE_ID" ] && exit 0

TASK_DIR="$TASKS_DIR/$ACTIVE_ID"
[ ! -d "$TASK_DIR" ] && exit 0

# Regenerate _summary.json for the active list
regenerate_summary "$TASK_DIR"

# Update _current symlink and tracker
mkdir -p "$FILTERED_DIR" 2>/dev/null || true
ln -sfn "$TASK_DIR" "$FILTERED_DIR/_current" 2>/dev/null || true
echo "$ACTIVE_ID" > "$FILTERED_DIR/.active-list-id" 2>/dev/null || true

# Also create a named symlink for discoverability
[ ! -e "$FILTERED_DIR/$ACTIVE_ID" ] && ln -s "$TASK_DIR" "$FILTERED_DIR/$ACTIVE_ID" 2>/dev/null || true

# Regenerate TASKS.md
SUMMARY="$TASK_DIR/_summary.json"
if [ -f "$SUMMARY" ]; then
    generate_tasks_md "$SUMMARY" "$FILTERED_DIR/TASKS.md" "$PROJECT_DIR"
fi

exit 0
