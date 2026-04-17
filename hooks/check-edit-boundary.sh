#!/bin/bash
# PreToolUse hook: enforce freeze/focus edit boundaries
# Matcher: Write|Edit|MultiEdit
#
# Modes: freeze (deny INSIDE) | focus (deny OUTSIDE)
# State: ~/.claude/edit-boundary.json
# CLI: $0 set <freeze|focus> <dir> [dir2...] | clear | show
# Hook: reads JSON from stdin per PreToolUse protocol (no args).

set -uo pipefail

STATE_FILE="$HOME/.claude/edit-boundary.json"

# ── CLI management mode (called with arguments) ──────────────────────
if [ $# -gt 0 ]; then
  case "$1" in
    set)
      MODE="${2:-}"
      shift 2 2>/dev/null || true
      if [ "$MODE" != "freeze" ] && [ "$MODE" != "focus" ]; then
        echo "Usage: $0 set <freeze|focus> <dir> [dir2 ...]" >&2
        exit 1
      fi
      if [ $# -eq 0 ]; then
        echo "Error: at least one directory path required" >&2
        exit 1
      fi
      # Resolve each path to absolute with trailing slash
      PATHS_JSON="["
      FIRST=true
      for DIR in "$@"; do
        RESOLVED=$(cd "$DIR" 2>/dev/null && pwd -P) || {
          echo "Error: directory not found: $DIR" >&2
          exit 1
        }
        RESOLVED="${RESOLVED%/}/"
        $FIRST && FIRST=false || PATHS_JSON+=","
        PATHS_JSON+="\"$RESOLVED\""
      done
      PATHS_JSON+="]"
      mkdir -p "$(dirname "$STATE_FILE")"
      printf '{"mode":"%s","paths":%s}\n' "$MODE" "$PATHS_JSON" > "$STATE_FILE"
      echo "Edit boundary set: mode=$MODE paths=$PATHS_JSON"
      ;;
    clear)
      rm -f "$STATE_FILE"
      echo "Edit boundary cleared."
      ;;
    show)
      if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
      else
        echo "No edit boundary active."
      fi
      ;;
    *)
      echo "Usage: $0 {set|clear|show}" >&2
      exit 1
      ;;
  esac
  exit 0
fi

# ── Hook mode (PreToolUse, reads JSON from stdin) ─────────────────────

# No state file = no boundary active, allow everything
[ ! -f "$STATE_FILE" ] && exit 0

# Require jq — fail-open if unavailable
if ! command -v jq &>/dev/null; then
  exit 0
fi

INPUT=$(cat)
STATE=$(cat "$STATE_FILE")

MODE=$(printf '%s' "$STATE" | jq -r '.mode // empty')
[ -z "$MODE" ] && exit 0

# Extract file_path from tool input
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')
[ -z "$FILE_PATH" ] && exit 0

# Resolve to absolute path
case "$FILE_PATH" in
  /*) ;;
  *)  FILE_PATH="$(pwd)/$FILE_PATH" ;;
esac

# Normalize: collapse double slashes, resolve parent dir symlinks
FILE_DIR=$(dirname "$FILE_PATH")
FILE_BASE=$(basename "$FILE_PATH")
FILE_DIR=$(cd "$FILE_DIR" 2>/dev/null && pwd -P || printf '%s' "$FILE_DIR")
FILE_PATH="$FILE_DIR/$FILE_BASE"

# Read boundary paths into array
BOUNDARY_PATHS=()
while IFS= read -r p; do
  [ -n "$p" ] && BOUNDARY_PATHS+=("$p")
done < <(printf '%s' "$STATE" | jq -r '.paths[]')

# Check if file is inside ANY boundary path (prefix match with trailing /)
inside_boundary() {
  for BP in "${BOUNDARY_PATHS[@]}"; do
    case "$1" in
      "${BP}"*) return 0 ;;
    esac
  done
  return 1
}

# Format boundary list for messages
BOUNDARY_LIST=$(printf '%s' "$STATE" | jq -r '.paths | join(", ")')

# ── Decision ──────────────────────────────────────────────────────────
DENY=false
if [ "$MODE" = "freeze" ]; then
  # Freeze: deny edits INSIDE boundary paths
  if inside_boundary "$FILE_PATH"; then
    DENY=true
    REASON="[edit-boundary] Blocked: $FILE_PATH is inside frozen directory ($BOUNDARY_LIST). Edits inside frozen directories are not allowed."
  fi
elif [ "$MODE" = "focus" ]; then
  # Focus: deny edits OUTSIDE boundary paths
  if ! inside_boundary "$FILE_PATH"; then
    DENY=true
    REASON="[edit-boundary] Blocked: $FILE_PATH is outside the focus boundary ($BOUNDARY_LIST). Only edits inside the focus directories are allowed."
  fi
fi

if [ "$DENY" = true ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$REASON"
  }
}
EOF
fi

exit 0
