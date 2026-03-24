#!/bin/bash
# SessionStart Hook - MCP Status Logger
# Logs MCP server status and provides additionalContext to warn Claude
# about potential initialization delays (per GitHub issue #723)

set -euo pipefail

LOG_DIR=~/.claude/logs
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sessions.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session started in $(pwd)" >> "$LOG_FILE"

# === DAILY BACKUP PRUNING (background, non-blocking) ===
PRUNE_SCRIPT="$HOME/.claude/scripts/prune-backups.sh"
LAST_PRUNE_FILE="$HOME/.claude/.last-backup-prune"
TODAY=$(date +%Y-%m-%d)
if [ -x "$PRUNE_SCRIPT" ]; then
  if [ ! -f "$LAST_PRUNE_FILE" ] || [ "$(cat "$LAST_PRUNE_FILE" 2>/dev/null)" != "$TODAY" ]; then
    echo "$TODAY" > "$LAST_PRUNE_FILE"
    "$PRUNE_SCRIPT" &  # Background, non-blocking
  fi
fi

# Check MCP server status with exponential backoff
MAX_ATTEMPTS=3
ATTEMPT=0
DELAY=1
CONNECTED_COUNT=0

if command -v claude &> /dev/null; then
  while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if MCP_OUTPUT=$(claude mcp list 2>&1); then
      CONNECTED_COUNT=$(echo "$MCP_OUTPUT" | grep -c "Connected" || true)
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] MCP Status (attempt $((ATTEMPT+1))):" >> "$LOG_FILE"
      echo "$MCP_OUTPUT" >> "$LOG_FILE"

      if [ "$CONNECTED_COUNT" -gt 0 ]; then
        break
      fi
    fi

    ATTEMPT=$((ATTEMPT + 1))
    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
      sleep $DELAY
      DELAY=$((DELAY * 2))
    fi
  done
fi

# Check agent-browser installation
AGENT_BROWSER_STATUS="not installed"
if command -v agent-browser &> /dev/null; then
  AGENT_BROWSER_STATUS="installed"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] agent-browser: $AGENT_BROWSER_STATUS" >> "$LOG_FILE"
fi

# Output additionalContext for Claude (JSON format)
# This warns Claude about potential MCP initialization delays
if [ "$CONNECTED_COUNT" -gt 0 ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "MCP: $CONNECTED_COUNT server(s). agent-browser: $AGENT_BROWSER_STATUS. If BrowserMCP tools fail with 'No such tool available', use agent-browser skill instead."
  }
}
EOF
else
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "WARNING: MCP not responding. agent-browser: $AGENT_BROWSER_STATUS. Use agent-browser skill for browser automation."
  }
}
EOF
fi

exit 0
