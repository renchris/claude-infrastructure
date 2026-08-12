#!/bin/bash
# SessionStart Hook - Create global + filtered task list symlinks.
# Auto-detects active task list (UUID or named) and generates TASKS.md.

# shellcheck source=lib/task-helpers.sh
# shellcheck disable=SC1091  # ship-land's gate runs shellcheck without -x, so the sourced
# helper cannot be followed statically; TASKS_DIR/TASKS_INDEX come from it, not a misspelling.
. "$(dirname "$0")/lib/task-helpers.sh"

TASK_LIST_ID="${CLAUDE_CODE_TASK_LIST_ID:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# Both hooks source task-helpers.sh above, which resolves the index against the RUNNING
# session's config dir. Re-hardcoding it here re-introduced the account-2/3/4 mis-target
# that helper exists to prevent.
INDEX="$TASKS_INDEX"

# ── Store-wide maintenance (--sweep) — DETACHED from the session-start critical path ────────
# Everything here is O(all ~2,400 task dirs) upkeep whose freshness no session start depends
# on: the index prune, the store-wide _summary.json sweep (scaling-bottlenecks-2026-08-09 §5
# P0-2 — the staleness guard lives in task-helpers.sh summary_stale, zero forks for an
# unchanged dir), and an empty-dir GC. It used to run inline and was the hook's residual
# ~0.6s on every start of every project including /clear; the one summary a start actually
# consumes — the ACTIVE list's, for TASKS.md — is regenerated synchronously below instead.
# Dispatch: CC_TASKS_SWEEP=async (default, detached + stamp-throttled) · sync (tests, and any
# caller that needs the effects before returning) · off.
store_sweep() {
    local dir TEMP listid now mt d gcout
    # Empty-dir GC first (fewer dirs for the passes below). The store accretes one dir per
    # session (2,479 on this box, 97% empty, nothing pruning them — R4 §4) and every consumer
    # glob scales with it. `rmdir` IS the guard: it refuses a non-empty dir atomically, so the
    # age gate only has to protect a just-created empty dir (a list mkdir'd at SessionStart
    # whose first TaskCreate has not landed yet) — 7 days is generous for that window.
    now=$(date +%s)
    gcout="$(stat -f '%m %N' "$TASKS_DIR"/*/ 2>/dev/null)"
    while IFS=' ' read -r mt d; do
        [ -n "$d" ] || continue
        case "$mt" in ''|*[!0-9]*) continue ;; esac
        [ $(( now - mt )) -gt "${CC_TASKS_GC_AGE_S:-604800}" ] || continue
        rmdir "$d" 2>/dev/null || true
    done <<EOF
$gcout
EOF

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

    # Store-wide summary refresh — only where staleness is provable (summary_stale).
    for dir in "$TASKS_DIR"/*/; do
        [ -d "$dir" ] || continue
        summary_stale "$dir" || continue
        regenerate_summary "$dir"
    done
}
if [ "${1:-}" = "--sweep" ]; then
    store_sweep
    exit 0
fi

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

# ── Active task list detection ──────────────────────────────────────
# Find the most recently modified task list MAPPED TO THIS PROJECT (G-P14-7).
# Project-scoped so a foreign project's list can never surface as this project's
# active list; the current session's own list is self-indexed above.
ACTIVE_ID=$(find_active_list "$PROJECT_DIR" "$INDEX")

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
# The ACTIVE list's summary is the one artifact this start actually consumes (TASKS.md is
# generated from it), so it refreshes here, synchronously, under the same guard — every
# other dir belongs to the detached store_sweep.
if [ -n "$EFFECTIVE_ID" ] && [ -d "$TASKS_DIR/$EFFECTIVE_ID" ] && summary_stale "$TASKS_DIR/$EFFECTIVE_ID/"; then
    regenerate_summary "$TASKS_DIR/$EFFECTIVE_ID/"
fi
if [ -n "$EFFECTIVE_ID" ] && [ -f "$ACTIVE_SUMMARY" ]; then
    generate_tasks_md "$ACTIVE_SUMMARY" "$FILTERED_DIR/TASKS.md" "$PROJECT_DIR"
fi

# ── Store-wide maintenance dispatch ─────────────────────────────────
# Detached + throttled: a /clear burst must not stack sweeps, so a stamp gates re-spawn to
# once per CC_TASKS_SWEEP_MIN_S (default 600s). All three fds are detached — a background
# child holding the hook's stdout pipe would make the hook runner wait for EOF and re-create
# the very stall this split removes.
SWEEP_MODE="${CC_TASKS_SWEEP:-async}"
if [ "$SWEEP_MODE" = "sync" ]; then
    store_sweep
elif [ "$SWEEP_MODE" != "off" ]; then
    SWEEP_STAMP="$TASKS_DIR/.sweep-stamp"
    NOW_S=$(date +%s); LAST_S=$(stat -f %m "$SWEEP_STAMP" 2>/dev/null || echo 0)
    if [ $(( NOW_S - LAST_S )) -ge "${CC_TASKS_SWEEP_MIN_S:-600}" ]; then
        : > "$SWEEP_STAMP" 2>/dev/null || true
        ( "$0" --sweep </dev/null >/dev/null 2>&1 & ) 2>/dev/null
    fi
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
