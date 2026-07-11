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

# Resolve the nearest project-local binary by walking up from the file's dir.
# Calling node_modules/.bin/eslint directly skips `npx`'s per-invocation
# resolution overhead — this hook fires on every code edit, so that adds up.
resolve_local_bin() {
  local dir="$1" bin="$2"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -x "$dir/node_modules/.bin/$bin" ]; then
      printf '%s' "$dir/node_modules/.bin/$bin"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

case "$EXT" in
  ts|tsx|js|jsx)
    # Direct project-local binary first; fall back to npx (identical --fix behavior).
    if ESLINT_BIN="$(resolve_local_bin "$(dirname "$FILE")" eslint)"; then
      "$ESLINT_BIN" --fix "$FILE" 2>/dev/null || true
    elif command -v npx &>/dev/null; then
      npx eslint --fix "$FILE" 2>/dev/null || true
    fi
    # OPT-IN for max speed: append ` &` to the eslint line above to run it
    # non-blocking (removes ~7s/edit of turn latency). Caveat: a same-tick
    # commit/read could race the async format; the commit-time eslint gate
    # is the correctness backstop. Left blocking by default (no race).
    ;;
  py)
    # Use ruff if available
    if command -v ruff &>/dev/null; then
      ruff format "$FILE" 2>/dev/null || true
    fi
    ;;
esac

exit 0
