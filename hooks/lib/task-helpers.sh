#!/bin/bash
# Shared functions for task list hooks.
# Source: . "$(dirname "$0")/lib/task-helpers.sh"
# Env overrides (tests): CC_TASKS_DIR, CC_TASKS_INDEX.

TASKS_DIR="${CC_TASKS_DIR:-$HOME/.claude/tasks}"
TASKS_INDEX="${CC_TASKS_INDEX:-$HOME/.claude/tasks-index.json}"

# Find the active task list for a project (G-P14-7). When a project is known,
# ONLY lists the tasks-index maps to THAT project are eligible — a globally
# most-recent FOREIGN list can never surface. Unmapped (UUID/foreign) lists and a
# missing index ⇒ no match (never a global fallback). With no project (legacy /
# non-project context), falls back to global-most-recent.
#   Args: $1 = project dir (default $CLAUDE_PROJECT_DIR), $2 = index (default $TASKS_INDEX)
# Prints the task list ID (directory basename), or empty string if none found.
find_active_list() {
    local proj="${1:-${CLAUDE_PROJECT_DIR:-}}"
    local index="${2:-$TASKS_INDEX}"
    local best="" best_time=0
    for dir in "$TASKS_DIR"/*/; do
        [ ! -d "$dir" ] && continue
        local listid
        listid=$(basename "$dir")
        # Project scoping: skip lists not mapped to this project.
        if [ -n "$proj" ]; then
            local mapped=""
            [ -f "$index" ] && mapped=$(jq -r --arg k "$listid" '.taskLists[$k].project // ""' "$index" 2>/dev/null)
            [ "$mapped" = "$proj" ] || continue
        fi
        # Any numeric .json files? (task files are 1.json, 2.json, etc.)
        local latest
        # SC2012: filenames are controlled (numeric N.json) → ls -t is the simplest
        # portable mtime sort; find has no BSD-portable -printf mtime ordering.
        # shellcheck disable=SC2012
        latest=$(ls -t "$dir"/[0-9]*.json 2>/dev/null | head -1)
        [ -z "$latest" ] && continue
        local mtime
        mtime=$(stat -f %m "$latest" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$best_time" ]; then
            best_time=$mtime
            best=$listid
        fi
    done
    echo "$best"
}

# Roll up EVERY project's open task lists (pending + in_progress > 0), one line
# each: "<projectName> | <N> open | <listid> | <projectPath>". Unmapped lists are
# labelled (unmapped) — never silently dropped. This is the desk's cross-project
# "what task work is open everywhere?" verb.
#   Args: $1 = index (default $TASKS_INDEX)
all_open_rollup() {
    local index="${1:-$TASKS_INDEX}" dir listid open proj pn
    for dir in "$TASKS_DIR"/*/; do
        [ ! -d "$dir" ] && continue
        listid=$(basename "$dir")
        open=$(cat "$dir"/[0-9]*.json 2>/dev/null \
                 | jq -s '[.[] | select(.status=="pending" or .status=="in_progress")] | length' 2>/dev/null)
        case "$open" in ''|*[!0-9]*) open=0 ;; esac
        [ "$open" -gt 0 ] || continue
        proj=""; pn=""
        if [ -f "$index" ]; then
            proj=$(jq -r --arg k "$listid" '.taskLists[$k].project // ""' "$index" 2>/dev/null)
            pn=$(jq -r --arg k "$listid" '.taskLists[$k].projectName // ""' "$index" 2>/dev/null)
        fi
        [ -n "$pn" ]   || pn="(unmapped)"
        [ -n "$proj" ] || proj="(unmapped)"
        printf '%-24s | %3d open | %s | %s\n' "$pn" "$open" "$listid" "$proj"
    done
}

# Regenerate _summary.json for a task list directory.
regenerate_summary() {
    local dir="$1"
    [ ! -d "$dir" ] && return 1
    local listid
    listid=$(basename "$dir")
    local hwm
    hwm=$(cat "$dir/.highwatermark" 2>/dev/null || echo "0")
    case "$hwm" in ''|*[!0-9]*) hwm=0 ;; esac
    local json_files
    json_files=$(find "$dir" -maxdepth 1 -name '*.json' ! -name '_summary.json' 2>/dev/null)
    if [ -z "$json_files" ]; then
        jq -n --arg listid "$listid" --argjson hwm "$hwm" \
          '{taskListId: $listid, highwatermark: $hwm, totalOnDisk: 0,
            pending: 0, in_progress: 0, completed: 0, plans: [], tasks: []}' \
          > "$dir/_summary.json" 2>/dev/null || true
        return 0
    fi
    local temp
    temp=$(mktemp)
    if find "$dir" -maxdepth 1 -name '*.json' ! -name '_summary.json' -exec cat {} + 2>/dev/null \
      | jq -s --arg listid "$listid" --argjson hwm "$hwm" \
        '{taskListId: $listid, highwatermark: $hwm, totalOnDisk: length,
          pending: [.[] | select(.status == "pending")] | length,
          in_progress: [.[] | select(.status == "in_progress")] | length,
          completed: [.[] | select(.status == "completed")] | length,
          plans: ([.[].description | [scan("\\[Plan: ([^]]+)\\]") | .[0]] | .[]] | unique),
          tasks: (sort_by(.id | tonumber))}' \
        > "$temp" 2>/dev/null && [ -s "$temp" ]; then
        mv "$temp" "$dir/_summary.json"
    else
        rm -f "$temp"
    fi
}

# Generate TASKS.md from a _summary.json file.
# Args: $1 = summary json path, $2 = output TASKS.md path, $3 = project dir (for absolute path)
generate_tasks_md() {
    local summary="$1"
    local output="$2"
    local project_dir="${3:-.}"
    [ ! -f "$summary" ] && return 1
    local total
    total=$(jq -r '.totalOnDisk' "$summary" 2>/dev/null)
    if [ "$total" = "0" ] || [ -z "$total" ]; then
        rm -f "$output" 2>/dev/null
        return 0
    fi
    local pending in_progress completed list_id now abs_path
    pending=$(jq -r '.pending' "$summary")
    in_progress=$(jq -r '.in_progress' "$summary")
    completed=$(jq -r '.completed' "$summary")
    list_id=$(jq -r '.taskListId' "$summary")
    now=$(date -u +"%Y-%m-%d %H:%M UTC")
    abs_path=$(cd "$project_dir" 2>/dev/null && pwd)/.claude-tasks/TASKS.md

    {
        echo "<!-- Auto-generated by Claude Code hooks — DO NOT EDIT -->"
        echo "<!-- Regenerated: session start · task create/update · task complete -->"
        echo "<!-- To resume in a new session: Read .claude-tasks/TASKS.md -->"
        echo "<!-- Absolute path: ${abs_path} -->"
        echo ""
        echo "# Active Tasks"
        echo ""
        echo "**${pending} pending** · ${in_progress} in-progress · ${completed} done | ${now}"
        echo ""

        if [ "$pending" -gt 0 ]; then
            echo "## Pending"
            echo ""
            jq -r '.tasks[] | select(.status == "pending") |
                "- [ ] **\(.id). \(.subject)**\n  \(.description | gsub("\n"; "\n  "))\n"' "$summary"
        fi

        if [ "$in_progress" -gt 0 ]; then
            echo "## In Progress"
            echo ""
            jq -r '.tasks[] | select(.status == "in_progress") |
                "- [~] **\(.id). \(.subject)**\n  \(.description | gsub("\n"; "\n  "))\n"' "$summary"
        fi

        if [ "$completed" -gt 0 ]; then
            echo "## Completed"
            echo ""
            jq -r '.tasks[] | select(.status == "completed") |
                "- [x] **\(.id). \(.subject)**"' "$summary"
            echo ""
        fi

        echo "---"
        echo "*Source: \`~/.claude/tasks/${list_id}/\` · JSON: \`.claude-tasks/_current/_summary.json\`*"
    } > "$output"
}

# ── CLI entrypoint — runs ONLY when executed directly, never when sourced. ───────
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    case "${1:-}" in
        --all-open) all_open_rollup "${2:-$TASKS_INDEX}" ;;
        --active)   find_active_list "${2:-${CLAUDE_PROJECT_DIR:-}}" "${3:-$TASKS_INDEX}" ;;
        *) echo "usage: task-helpers.sh --all-open [index] | --active [project] [index]" >&2; exit 2 ;;
    esac
fi
