#!/bin/bash
# UserPromptSubmit Hook — Cache Expiry Warning
# Checks if >5 minutes elapsed since last interaction. If so, the prompt
# cache has expired and the full context will be reprocessed at 10x cost.
# Injects a warning into additionalContext suggesting /clear or /compact.

set -euo pipefail

LAST_FILE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.last-interaction"
CACHE_TTL=300  # 5 minutes in seconds

# No tracking file = first message in session, skip
if [[ ! -f "$LAST_FILE" ]]; then
  exit 0
fi

LAST_EPOCH=$(cat "$LAST_FILE" 2>/dev/null || echo 0)
NOW_EPOCH=$(date +%s)
ELAPSED=$((NOW_EPOCH - LAST_EPOCH))

if [[ $ELAPSED -gt $CACHE_TTL ]]; then
  MINUTES=$((ELAPSED / 60))
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "CACHE EXPIRED: ${MINUTES}m idle — prompt cache TTL is 5m. Full context will be reprocessed at uncached rate. Consider /clear (fresh session) or /compact (compress history) to reduce token cost."
  }
}
EOF
fi

exit 0
