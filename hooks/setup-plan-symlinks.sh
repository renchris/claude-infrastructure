#!/bin/bash
# SessionStart Hook - Create global + filtered plan symlinks and report TRUTHFUL
# plan counts. Counts docs/plans + .claude-plans (project) from disk, and the
# cross-project total from plans-index.json. Fixes G-P14-1 ("Plans: 0" lie).
# Env overrides (tests): CC_PLANS_DIR, CC_PLAN_INDEX.

PLANS_DIR="${CC_PLANS_DIR:-$HOME/.claude/plans}"
INDEX="${CC_PLAN_INDEX:-$HOME/.claude/plans-index.json}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# plan_status <file> → open|in-progress|complete|superseded|unknown (from YAML
# frontmatter `status:`). Missing/unparseable ⇒ unknown. Kept in sync with the
# copies in find-plan.sh and validate-plan-structure.sh (no shared lib per
# single-owner file boundary).
plan_status() {
  local f="$1" first val
  IFS= read -r first < "$f" 2>/dev/null || true
  [ "$first" = "---" ] || { printf 'unknown\n'; return 0; }
  val=$(sed -n '2,/^---$/{ /^[Ss][Tt][Aa][Tt][Uu][Ss]:/p; }' "$f" 2>/dev/null | head -1)
  [ -n "$val" ] || { printf 'unknown\n'; return 0; }
  val=${val#*:}
  val=$(printf '%s' "$val" | tr -d ' \t"'\''`' | tr '[:upper:]' '[:lower:]')
  case "$val" in in_progress) val=in-progress ;; completed) val=complete ;; esac
  case "$val" in
    open|in-progress|complete|superseded) printf '%s\n' "$val" ;;
    *) printf 'unknown\n' ;;
  esac
  return 0
}

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

PROJ_TOTAL=0; PROJ_OPEN=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    PROJ_TOTAL=$((PROJ_TOTAL + 1))
    case "$(plan_status "$f")" in
        complete|superseded) ;;
        *) PROJ_OPEN=$((PROJ_OPEN + 1)) ;;
    esac
done < <(project_files)

# All-projects total from the index (kept fresh by `plan-index-update.sh reconcile`).
ALL_TOTAL=0
[ -f "$INDEX" ] && ALL_TOTAL=$(jq -r '.plans | length' "$INDEX" 2>/dev/null || echo 0)
case "$ALL_TOTAL" in ''|*[!0-9]*) ALL_TOTAL=0 ;; esac

PROJECT_NAME=$(basename "$PROJECT_DIR")

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Plans: ${PROJ_OPEN}/${PROJ_TOTAL} open for ${PROJECT_NAME} · ${ALL_TOTAL} all. .claude-plans/ = project plans, .claude-plans/_all/ = global plan sink. Run 'find-plan.sh --list-open' for the cross-project open list.\"}}"

exit 0
