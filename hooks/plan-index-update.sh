#!/bin/bash
set -euo pipefail

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_result.filePath // empty')

# Fast exit: not a plan file
[ -z "$FILE" ] && exit 0
PLANS_DIR="$HOME/.claude/plans"
case "$FILE" in "$PLANS_DIR"/*.md) ;; *) exit 0 ;; esac

# Determine project (triple fallback)
PROJECT="${CLAUDE_PROJECT_DIR:-}"
[ -z "$PROJECT" ] && PROJECT=$(echo "$INPUT" | jq -r '.cwd // empty')
[ -z "$PROJECT" ] && PROJECT="$PWD"

# Skip if project is .claude directory itself
case "$PROJECT" in "$HOME/.claude"*) exit 0 ;; esac

BASENAME=$(basename "$FILE")
PROJECT_NAME=$(basename "$PROJECT")
INDEX="$HOME/.claude/plans-index.json"
NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Create index if it doesn't exist
[ ! -f "$INDEX" ] && echo '{"version":1,"plans":{}}' > "$INDEX"

# Atomic update via temp file
TEMP=$(mktemp)
jq --arg file "$BASENAME" \
   --arg project "$PROJECT" \
   --arg projectName "$PROJECT_NAME" \
   --arg now "$NOW" \
   '.plans[$file] = (
      .plans[$file] // {} |
      .project = $project |
      .projectName = $projectName |
      .lastSeen = $now |
      .firstIndexed = (.firstIndexed // $now)
    ) | .generated = $now' \
   "$INDEX" > "$TEMP" && mv "$TEMP" "$INDEX"

exit 0
