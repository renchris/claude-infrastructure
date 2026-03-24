#!/bin/bash
# SessionStart Hook - Create global + filtered plan symlinks

PLANS_DIR="$HOME/.claude/plans"
INDEX="$HOME/.claude/plans-index.json"
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

# Populate from index
if [ -f "$INDEX" ]; then
    jq -r --arg proj "$PROJECT_DIR" \
      '.plans | to_entries[] | select(.value.project == $proj) | .key' \
      "$INDEX" 2>/dev/null | while IFS= read -r fname; do
        src="$PLANS_DIR/$fname"
        dst="$FILTERED_DIR/$fname"
        [ -f "$src" ] && [ ! -e "$dst" ] && ln -s "$src" "$dst" 2>/dev/null || true
    done
fi

# Report to session
TOTAL=$(find "$PLANS_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
FILTERED=$(find "$FILTERED_DIR" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
PROJECT_NAME=$(basename "$PROJECT_DIR")

echo "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Plans: ${FILTERED} for ${PROJECT_NAME} (${TOTAL} total). .claude-plans/ = project plans, .claude-plans/_all/ = all global plans.\"}}"

exit 0
