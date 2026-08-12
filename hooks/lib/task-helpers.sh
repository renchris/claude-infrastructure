#!/bin/bash
# Shared functions for task list hooks.
# Source: . "$(dirname "$0")/lib/task-helpers.sh"
# Env overrides (tests): CC_TASKS_DIR, CC_TASKS_INDEX.

# Resolve the store the way Claude Code does — relative to the RUNNING session's config dir — with
# account 1's as the fallback. These were hardcoded to $HOME/.claude/tasks, which for accounts
# 2/3/4 named a directory Claude Code never wrote to (it wrote to $CLAUDE_CONFIG_DIR/tasks), so the
# index, the _current symlink and the desk's cross-project rollup all pointed at empty boards for
# three of four accounts, silently and with no error anywhere. The mirror now symlinks tasks/ so
# both spellings land in the same place — deriving it anyway keeps these hooks correct if that ever
# stops being true, rather than correct only by coincidence.
CC_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TASKS_DIR="${CC_TASKS_DIR:-$CC_CONFIG_DIR/tasks}"
TASKS_INDEX="${CC_TASKS_INDEX:-$CC_CONFIG_DIR/tasks-index.json}"
[ -d "$TASKS_DIR" ]   || TASKS_DIR="$HOME/.claude/tasks"
[ -f "$TASKS_INDEX" ] || TASKS_INDEX="$HOME/.claude/tasks-index.json"

# Find the active task list for a project (G-P14-7). When a project is known,
# ONLY lists the tasks-index maps to THAT project are eligible — a globally
# most-recent FOREIGN list can never surface. Unmapped (UUID/foreign) lists and a
# missing index ⇒ no match (never a global fallback). With no project (legacy /
# non-project context), falls back to global-most-recent.
#   Args: $1 = project dir (default $CLAUDE_PROJECT_DIR), $2 = index (default $TASKS_INDEX)
# Prints the task list ID (directory basename), or empty string if none found.
# PERFORMANCE (DESK_ROUTER_AND_STARTUP_V1 W0). This function used to fork one `jq` per
# task-list DIRECTORY, each re-reading the WHOLE index, plus `basename` + `ls -t` + `head`
# + `stat` per directory — ~2,400 dirs × a 136 KB index ≈ 21 s to select ~25 entries. It is
# on the SessionStart critical path via setup-task-symlinks.sh, whose own `timeout: 5` then
# killed the hook mid-flight and DISCARDED the work (`_current`, `.active-list-id` and
# TASKS.md are all written after this call), every session start, every project, every
# config dir, including every /clear. Rewritten to ONE index read plus pure-bash mtime
# comparison: measured 21.2 s -> 0.09 s on the live store, identical answer.
#
# Two invariants the rewrite deliberately preserves, because the tests pin them:
#   * The DIRECTORY GLOB stays the iteration order, and the index is only a membership
#     test. Reordering to the index's key order would change which list wins an mtime tie
#     (jq object order is insertion order, not the glob's collation).
#   * `-nt` is strictly-newer, exactly like the previous `-gt` on stat mtimes, so the
#     earliest candidate in glob order still wins a tie.
# The membership set is a |-delimited string, not `declare -A`: the shebang is /bin/bash,
# which on macOS is 3.2.57 with no associative arrays (same reason as session-end.sh:161).
find_active_list() {
    local proj="${1:-${CLAUDE_PROJECT_DIR:-}}"
    local index="${2:-$TASKS_INDEX}"
    local best="" best_file="" dir listid tj mapped_set=""

    if [ -n "$proj" ]; then
        # Unmapped lists and a missing index ⇒ no match (never a global fallback).
        [ -f "$index" ] || { echo ""; return 0; }
        local mapped
        mapped=$(jq -r --arg p "$proj" \
                   '.taskLists | to_entries[] | select(.value.project == $p) | .key' \
                   "$index" 2>/dev/null)
        [ -n "$mapped" ] || { echo ""; return 0; }
        while IFS= read -r listid; do
            [ -n "$listid" ] && mapped_set="${mapped_set}|${listid}|"
        done <<EOF
$mapped
EOF
    fi

    for dir in "$TASKS_DIR"/*/; do
        [ ! -d "$dir" ] && continue
        listid="${dir%/}"; listid="${listid##*/}"
        if [ -n "$proj" ]; then
            case "$mapped_set" in
                *"|$listid|"*) : ;;
                *) continue ;;
            esac
        fi
        # Task files are 1.json, 2.json, … — `-nt` is a shell builtin, so the whole
        # newest-file scan costs zero forks.
        for tj in "$dir"[0-9]*.json; do
            [ -e "$tj" ] || continue
            if [ -z "$best_file" ] || [ "$tj" -nt "$best_file" ]; then
                best_file="$tj"
                best="$listid"
            fi
        done
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

# summary_stale <dir> → 0 when the dir's _summary.json must be regenerated, 1 when it is
# current. The freshness guard from scaling-bottlenecks-2026-08-09 §5 P0-2, factored here so
# the store-wide sweep and the targeted active-list regen in setup-task-symlinks.sh read ONE
# definition: regenerate when (a) a task json is newer than the summary (covers in-place
# TaskUpdate rewrites), (b) tasks exist with no summary, or (c) the dir emptied AFTER its
# summary was written (deletion moves dir mtime; the regen writes the summary into the dir,
# so post-regen the two are equal and it skips). Pure bash, zero forks for an unchanged dir.
# CC_TASKS_SUMMARY_FORCE=1 bypasses the guard (also the test suite's mutation control).
summary_stale() {
    local dir="${1%/}/" summary tj has_task=0
    summary="${dir}_summary.json"
    [ "${CC_TASKS_SUMMARY_FORCE:-0}" = "1" ] && return 0
    for tj in "$dir"*.json; do
        [ -e "$tj" ] || continue
        case "$tj" in */_summary.json) continue ;; esac
        has_task=1
        if [ ! -f "$summary" ] || [ "$tj" -nt "$summary" ]; then return 0; fi
    done
    if [ "$has_task" -eq 0 ]; then
        [ -f "$summary" ] || return 1
        [ "$dir" -nt "$summary" ] && return 0
    fi
    return 1
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
