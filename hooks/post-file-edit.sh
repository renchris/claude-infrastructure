#!/bin/bash
# PostToolUse hook for automatic formatting after file edits
# Per 2.1.11: exit 0 = success, errors are non-blocking

set -euo pipefail

INPUT=$(cat)

# Try tool_input first (Edit/Write), then tool_result (for successful writes)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_result.filePath // empty')

# Exit cleanly if no file path
[ -z "$FILE" ] && exit 0

# Exit if file doesn't exist (was deleted or Write failed)
[ ! -f "$FILE" ] && exit 0

EXT="${FILE##*.}"

case "$EXT" in
  ts|tsx|js|jsx)
    # Use npx eslint if available (pnpm/npm)
    if command -v npx &>/dev/null; then
      npx eslint --fix "$FILE" 2>/dev/null || true
    fi
    ;;
  py)
    # Use ruff if available
    if command -v ruff &>/dev/null; then
      ruff format "$FILE" 2>/dev/null || true
    fi
    ;;
esac

exit 0
