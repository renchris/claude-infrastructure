#!/bin/bash
# TeammateIdle hook — auto-shutdown idle teammates to prevent orphans
# Fires when a teammate is about to go idle after finishing its turn.
#
# Uses JSON {"continue": false} on stdout with exit 0 to STOP the teammate.
# Previous approach (exit code 2) was WRONG — it blocks idle and tells the
# teammate to continue working, creating an infinite retry loop.
#
# Designed from 15-agent research (Mar 19 2026), fixed Apr 4 2026:
#   - TeammateIdle is purpose-built for this (Claude Code v2.1.32+)
#   - Prevents orphans at source (no more 15+ idle panes)
#   - {"continue": false} cleanly stops the teammate process

set -uo pipefail

INPUT=$(cat)
TEAMMATE_NAME=$(echo "$INPUT" | jq -r '.teammate_name // "unknown"' 2>/dev/null)
TEAM_NAME=$(echo "$INPUT" | jq -r '.team_name // "unknown"' 2>/dev/null)

# Log the shutdown
LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR" 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Auto-shutdown idle teammate: $TEAMMATE_NAME (team: $TEAM_NAME)" \
  >> "$LOG_DIR/teammate-lifecycle.log"

# Auto-cleanup worktree if exists (convention: /tmp/worktree-<teammate_name>)
WORKTREE="/tmp/worktree-${TEAMMATE_NAME}"
if [ -d "$WORKTREE" ]; then
  git worktree remove "$WORKTREE" --force 2>/dev/null && \
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaned worktree: $WORKTREE" \
      >> "$LOG_DIR/teammate-lifecycle.log"
fi

# Stop the teammate — JSON on stdout with exit 0
echo '{"continue": false, "stopReason": "Idle teammate auto-shutdown"}'

# CRITICAL: {"continue": false} does NOT terminate the claude process.
# It only stops the current turn. The process stays alive, goes idle again,
# and the hook fires repeatedly (confirmed: 3-4x per teammate in logs).
#
# Fix: Schedule a delayed kill of the parent claude process.
# The 3-second delay allows Claude Code to process the JSON response
# before the process is terminated. The iTerm2 "Claude-Teammate" profile
# has "Prompt Before Closing 2": 0, so the pane auto-closes on exit.
(sleep 3 && kill -TERM $PPID 2>/dev/null) &

exit 0
