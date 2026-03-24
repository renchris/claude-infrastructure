#!/bin/bash
# TeammateIdle hook — auto-shutdown idle teammates to prevent orphans
# Fires when a teammate is about to go idle after finishing its turn.
# Exit code 2 = block idle, teammate receives stderr as feedback → triggers shutdown.
#
# Designed from 15-agent research (Mar 19 2026):
#   - TeammateIdle is purpose-built for this (Claude Code v2.1.32+)
#   - Prevents orphans at source (no more 15+ idle panes)
#   - No timeout tracking needed — immediate shutdown on first idle

set -uo pipefail

INPUT=$(cat)
TEAMMATE_NAME=$(echo "$INPUT" | jq -r '.teammate_name // "unknown"' 2>/dev/null)
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // "unknown"' 2>/dev/null)

# Log the shutdown
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto-shutdown idle teammate: $TEAMMATE_NAME (team: $TEAM_NAME)" \
  >> "$LOG_DIR/teammate-lifecycle.log"

# Block idle with exit code 2 — triggers teammate shutdown
# stderr message is sent back to the teammate as feedback
echo "You are idle. Shutting down automatically per TeammateIdle hook. If you need to continue working, use TaskUpdate to mark your task in-progress before going idle." >&2
exit 2
