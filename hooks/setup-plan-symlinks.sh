#!/bin/bash
# SessionStart Hook - Create global + filtered plan symlinks and report TRUTHFUL
# plan counts. Counts docs/plans + .claude-plans (project) from disk, and the
# cross-project total from plans-index.json. Fixes G-P14-1 ("Plans: 0" lie).
# Env overrides (tests): CC_PLANS_DIR, CC_PLAN_INDEX.

PLANS_DIR="${CC_PLANS_DIR:-$HOME/.claude/plans}"
INDEX="${CC_PLAN_INDEX:-$HOME/.claude/plans-index.json}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# 1. Remove legacy global symlink
[ -L ".claude-global-plans" ] && rm ".claude-global-plans" 2>/dev/null || true

# 2. Filtered project-specific directory
FILTERED_DIR=".claude-plans"
mkdir -p "$FILTERED_DIR" 2>/dev/null || true

# 3. Global plans directory symlink
ALL_LINK="$FILTERED_DIR/_all"
if [ -d "$PLANS_DIR" ]; then
    # Guard: if _all is a real directory (not symlink), remove it
    [ -d "$ALL_LINK" ] && [ ! -L "$ALL_LINK" ] && rm -rf "$ALL_LINK"
    # Atomic symlink create/replace (-n prevents following existing symlink on macOS)
    ln -sfn "$PLANS_DIR" "$ALL_LINK"
fi

# Clean stale symlinks (exclude _all directory symlink)
find "$FILTERED_DIR" -maxdepth 1 -type l ! -name '_all' ! -exec test -e {} \; -delete 2>/dev/null || true

# Populate from index: symlink this project's GLOBAL (~/.claude/plans) plans into
# the filtered dir. docs/plans + .claude-plans plans already live in the project.
if [ -f "$INDEX" ]; then
    jq -r --arg proj "$PROJECT_DIR" \
      '.plans | to_entries[]
       | select(.value.project == $proj and (.value.namespace // "global") == "global")
       | (.value.path // empty)' \
      "$INDEX" 2>/dev/null | while IFS= read -r src; do
        [ -n "$src" ] || continue
        dst="$FILTERED_DIR/$(basename "$src")"
        [ -f "$src" ] && [ ! -e "$dst" ] && ln -s "$src" "$dst" 2>/dev/null || true
    done
fi

# ── Truthful counts (real disk + index reads) ───────────────────────────────────
# Project plans = docs/plans + .claude-plans (deduped by basename; a .claude-plans
# symlink may mirror a global plan). Open = status not in {complete, superseded};
# status-less/unknown counts as OPEN (never hide potential work — anti-FM1).
project_files() {
    {
        find "$PROJECT_DIR/docs/plans" -maxdepth 1 \( -type f -o -type l \) -name '*.md' 2>/dev/null
        find "$FILTERED_DIR"           -maxdepth 1 \( -type f -o -type l \) -name '*.md' 2>/dev/null
    } | awk '{ n=split($0,a,"/"); b=a[n]; if(!(b in seen)){seen[b]=1; print} }'
}

# Status is read in ONE awk pass over every plan's frontmatter. The old shape was a
# plan_status() call per file — ~3 forks each, ~750 forks on a 250-plan project, which
# was this hook's entire 0.5s SessionStart cost. The grammar matches the plan_status
# copies in find-plan.sh / validate-plan-structure.sh: first line must be `---`; the
# first `status:` line (case-insensitive) before the closing `---` wins; strip
# space/tab/quote/backtick, lowercase; `completed`/`done`→complete; only complete|superseded
# CLOSE a plan — everything else (open, in-progress, junk, no frontmatter, and a
# 0-byte file awk never visits) stays OPEN, exactly as before (anti-FM1).
PROJ_LIST="$(project_files)"
PROJ_TOTAL=0; PROJ_OPEN=0; PROJ_CLOSED=0
if [ -n "$PROJ_LIST" ]; then
    PROJ_TOTAL=$(printf '%s\n' "$PROJ_LIST" | grep -c .)
    # xargs may split a huge list into several awk runs; each prints its own closed
    # count, so the trailing awk sums whatever arrives (0 runs ⇒ 0).
    # shellcheck disable=SC2016  # the awk program is intentionally single-quoted (the $0/sub/gsub are awk's, and the one shell-visible token is the '\'' escape)
    PROJ_CLOSED=$(printf '%s\n' "$PROJ_LIST" | tr '\n' '\0' | xargs -0 awk '
        function flush() { if (infile && (st=="complete" || st=="superseded")) closed++; infile=0 }
        FNR==1 { flush(); infile=1; st="unknown"; fm=($0=="---")?1:0; if (!fm) nextfile; next }
        fm && $0=="---" { fm=0; nextfile }
        fm && st=="unknown" && tolower($0) ~ /^status:/ {
            v=$0; sub(/^[^:]*:/, "", v)
            gsub(/[[:space:]"]|'\''|`/, "", v); v=tolower(v)
            if (v=="completed" || v=="done") v="complete"
            if (v=="complete" || v=="superseded") st=v
            nextfile
        }
        END { flush(); print closed+0 }
    ' 2>/dev/null | awk '{s+=$1} END {print s+0}')
    case "$PROJ_CLOSED" in ''|*[!0-9]*) PROJ_CLOSED=0 ;; esac
    PROJ_OPEN=$((PROJ_TOTAL - PROJ_CLOSED))
fi

# All-projects total from the index (kept fresh by `plan-index-update.sh reconcile`).
ALL_TOTAL=0
[ -f "$INDEX" ] && ALL_TOTAL=$(jq -r '.plans | length' "$INDEX" 2>/dev/null || echo 0)
case "$ALL_TOTAL" in ''|*[!0-9]*) ALL_TOTAL=0 ;; esac

PROJECT_NAME=$(basename "$PROJECT_DIR")

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Plans: ${PROJ_OPEN}/${PROJ_TOTAL} open for ${PROJECT_NAME} · ${ALL_TOTAL} all. .claude-plans/ = project plans, .claude-plans/_all/ = global plan sink. Run 'find-plan.sh --list-open' for the cross-project open list.\"}}"

exit 0
