#!/bin/bash
# SessionStart Hook - Create global + filtered task list symlinks.
# Auto-detects active task list (UUID or named) and generates TASKS.md.

# shellcheck source=lib/task-helpers.sh
. "$(dirname "$0")/lib/task-helpers.sh"

TASK_LIST_ID="${CLAUDE_CODE_TASK_LIST_ID:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
INDEX="$HOME/.claude/tasks-index.json"

# Filtered project-specific directory
FILTERED_DIR=".claude-tasks"
mkdir -p "$FILTERED_DIR" 2>/dev/null || true

# Global tasks directory symlink
ALL_LINK="$FILTERED_DIR/_all"
if [ -d "$TASKS_DIR" ]; then
    [ -d "$ALL_LINK" ] && [ ! -L "$ALL_LINK" ] && rm -rf "$ALL_LINK"
    ln -sfn "$TASKS_DIR" "$ALL_LINK"
fi

# Self-index: register named task list → project mapping
if [ -n "$TASK_LIST_ID" ]; then
    mkdir -p "$TASKS_DIR/$TASK_LIST_ID" 2>/dev/null || true
    PROJECT_NAME=$(basename "$PROJECT_DIR")
    NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    TASK_COUNT=$(find "$TASKS_DIR/$TASK_LIST_ID" -maxdepth 1 -name '*.json' ! -name '_summary.json' 2>/dev/null | wc -l | tr -d ' ')
    case "$TASK_COUNT" in ''|*[!0-9]*) TASK_COUNT=0 ;; esac

    # Atomic index creation
    if [ ! -f "$INDEX" ]; then
        INIT_TEMP=$(mktemp)
        echo '{"version":1,"taskLists":{}}' > "$INIT_TEMP"
        mv -n "$INIT_TEMP" "$INDEX" 2>/dev/null || rm -f "$INIT_TEMP"
    fi

    TEMP=$(mktemp)
    if jq --arg listid "$TASK_LIST_ID" \
       --arg project "$PROJECT_DIR" \
       --arg projectName "$PROJECT_NAME" \
       --arg now "$NOW" \
       --argjson taskCount "$TASK_COUNT" \
       '.taskLists[$listid] = (
          .taskLists[$listid] // {} |
          .project = $project |
          .projectName = $projectName |
          .lastSeen = $now |
          .taskCount = $taskCount |
          .firstIndexed = (.firstIndexed // $now)
        ) | .generated = $now' \
       "$INDEX" > "$TEMP" 2>/dev/null; then
        mv "$TEMP" "$INDEX"
    else
        rm -f "$TEMP"
    fi
fi

# Prune stale index entries (directories that no longer exist)
if [ -f "$INDEX" ]; then
    jq -r '.taskLists | keys[]' "$INDEX" 2>/dev/null | while IFS= read -r listid; do
        if [ ! -d "$TASKS_DIR/$listid" ]; then
            TEMP=$(mktemp)
            if jq --arg k "$listid" 'del(.taskLists[$k])' "$INDEX" > "$TEMP" 2>/dev/null && [ -s "$TEMP" ]; then
                mv "$TEMP" "$INDEX"
            else
                rm -f "$TEMP"
            fi
        fi
    done
fi

# Clean stale symlinks (exclude _all and _current)
find "$FILTERED_DIR" -maxdepth 1 -type l ! -name '_all' ! -name '_current' \
  ! -exec test -e {} \; -delete 2>/dev/null || true

# Populate project-specific symlinks from index
if [ -f "$INDEX" ]; then
    jq -r --arg proj "$PROJECT_DIR" \
      '.taskLists | to_entries[] | select(.value.project == $proj) | .key' \
      "$INDEX" 2>/dev/null | while IFS= read -r listid; do
        src="$TASKS_DIR/$listid"
        dst="$FILTERED_DIR/$listid"
        [ -d "$src" ] && [ ! -e "$dst" ] && ln -s "$src" "$dst" 2>/dev/null || true
    done
fi

# Generate _summary.json for ALL task list directories
for dir in "$TASKS_DIR"/*/; do
    [ ! -d "$dir" ] && continue
    regenerate_summary "$dir"
done

# ── Active task list detection ──────────────────────────────────────
# Find the most recently modified task list with actual tasks.
# This handles Claude Code creating UUID directories instead of using
# CLAUDE_CODE_TASK_LIST_ID.
ACTIVE_ID=$(find_active_list)

# Update _current symlink to point to the active list (UUID or named)
CURRENT_LINK="$FILTERED_DIR/_current"
if [ -n "$ACTIVE_ID" ]; then
    ln -sfn "$TASKS_DIR/$ACTIVE_ID" "$CURRENT_LINK"
    echo "$ACTIVE_ID" > "$FILTERED_DIR/.active-list-id"
    # Also create a named symlink for the UUID list
    [ ! -e "$FILTERED_DIR/$ACTIVE_ID" ] && ln -s "$TASKS_DIR/$ACTIVE_ID" "$FILTERED_DIR/$ACTIVE_ID" 2>/dev/null || true
elif [ -n "$TASK_LIST_ID" ]; then
    ln -sfn "$TASKS_DIR/$TASK_LIST_ID" "$CURRENT_LINK"
    echo "$TASK_LIST_ID" > "$FILTERED_DIR/.active-list-id"
elif [ -L "$CURRENT_LINK" ]; then
    rm "$CURRENT_LINK" 2>/dev/null || true
fi

# ── Generate TASKS.md ───────────────────────────────────────────────
EFFECTIVE_ID="${ACTIVE_ID:-$TASK_LIST_ID}"
ACTIVE_SUMMARY="$TASKS_DIR/${EFFECTIVE_ID}/_summary.json"
if [ -n "$EFFECTIVE_ID" ] && [ -f "$ACTIVE_SUMMARY" ]; then
    generate_tasks_md "$ACTIVE_SUMMARY" "$FILTERED_DIR/TASKS.md" "$PROJECT_DIR"
fi

# Report to session
TOTAL=$(find "$TASKS_DIR" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
FILTERED=$(find "$FILTERED_DIR" -maxdepth 1 -mindepth 1 \( -type l -o -type d \) \
  ! -name '_all' ! -name '_current' ! -name '.' 2>/dev/null | wc -l | tr -d ' ')
PROJECT_NAME=$(basename "$PROJECT_DIR")
ACTIVE_TASKS=$(jq -r '.totalOnDisk // 0' "$ACTIVE_SUMMARY" 2>/dev/null || echo "0")

CONTEXT="Tasks: ${ACTIVE_TASKS} active"
[ -n "$ACTIVE_ID" ] && [ "$ACTIVE_ID" != "$TASK_LIST_ID" ] && CONTEXT="$CONTEXT (auto-detected ${ACTIVE_ID:0:8}…)"
CONTEXT="$CONTEXT. ${FILTERED} list(s) for ${PROJECT_NAME} (${TOTAL} total)."
[ -f "$FILTERED_DIR/TASKS.md" ] && CONTEXT="$CONTEXT TASKS.md ready."
CONTEXT="$CONTEXT .claude-tasks/_current/ = active."

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"$CONTEXT\"}}"
exit 0
