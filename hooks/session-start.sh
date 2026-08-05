#!/bin/bash
# SessionStart Hook - MCP Status Logger
# Logs MCP server status and provides additionalContext to warn Claude
# about potential initialization delays (per GitHub issue #723)

set -euo pipefail

LOG_DIR=~/.claude/logs
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/sessions.log"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Session started in $(pwd)" >> "$LOG_FILE"

# === EFFORT ENV-VAR TRIPWIRE (2026-06-11) ===
# CLAUDE_CODE_EFFORT_LEVEL in the process env outranks /effort EVERY turn and
# cannot be cleared from inside a session (Bash-tool `unset` runs in a child
# shell) — the harness contract is: effort defaults ride the launchers'
# `--effort` flag + settings.json effortLevel, NEVER this env var. If it shows
# up here it leaked from a stale shell, a settings.json env block, or a new
# rogue export. The warning is folded into the final hookSpecificOutput JSON
# (this hook's stdout must stay a single JSON object — a bare echo would break
# the parse and demote the whole output to plain context).
EFFORT_WARN=""
if [ -n "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]; then
  # sanitize value for safe JSON interpolation (levels are [a-z0-9]; anything else is suspicious anyway)
  _EFFORT_VAL=$(printf '%s' "$CLAUDE_CODE_EFFORT_LEVEL" | tr -cd '[:alnum:]_-' | cut -c1-32)
  EFFORT_WARN="WARNING: CLAUDE_CODE_EFFORT_LEVEL=${_EFFORT_VAL} is set in this session's environment — /effort is LOCKED to it all session (re-read every turn; cannot be unset from inside). The harness contract (zshrc effort block 2026-06-11) injects --effort at launch instead; find and remove the export (stale pre-fix terminal tab, settings.json env block, or rogue wrapper/launchd export). "
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: CLAUDE_CODE_EFFORT_LEVEL=${_EFFORT_VAL} present at SessionStart in $(pwd)" >> "$LOG_FILE"
fi

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

# === DAILY PLAN-HISTORY PRUNING (background, non-blocking) ===
# Same daily-marker shape as the backup prune above — that wiring is the reference
# (audit 03 §1c calls backups/ "the reference-quality wiring"; plan-history had none).
# Bounds MANIFEST.jsonl to keep-10-per-plan + 90 d and `git gc`s the plan-history repo.
PLAN_PRUNE_SCRIPT="$HOME/.claude/scripts/prune-plan-history.sh"
LAST_PLAN_PRUNE_FILE="$HOME/.claude/.last-plan-history-prune"
if [ -x "$PLAN_PRUNE_SCRIPT" ]; then
  if [ ! -f "$LAST_PLAN_PRUNE_FILE" ] || [ "$(cat "$LAST_PLAN_PRUNE_FILE" 2>/dev/null)" != "$TODAY" ]; then
    echo "$TODAY" > "$LAST_PLAN_PRUNE_FILE"
    "$PLAN_PRUNE_SCRIPT" >/dev/null 2>&1 &  # Background, non-blocking
  fi
fi

# Check MCP server status with exponential backoff
MAX_ATTEMPTS=3
ATTEMPT=0
DELAY=1
CONNECTED_COUNT=0

if command -v claude &> /dev/null; then
  while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    # The pane identity is deliberately NOT inherited by this child. `claude mcp list` emits a
    # SessionEnd hook event of its own — reason "other", a fresh session_id, and NO matching
    # SessionStart — so every pane-keyed SessionEnd consumer reads it as THIS pane's session
    # ending, one second into that session's life. That is how every session start came to delete
    # its own cc-registry row (2026-08-05; hooks/session-deregister.sh header carries the
    # measurement). That consumer now proves tenancy before acting, but the phantom event is the
    # source and it fires for every consumer, including ones not written yet: blanking both vars
    # makes it PANELESS, so a pane-keyed hook no-ops at its own pane gate instead of acting on a
    # live pane's state. `claude mcp list` reads neither var for anything of its own. `env -u`
    # (not a `VAR= ` prefix) so they are genuinely ABSENT, which is what the consumers' `${VAR:-}`
    # gates read — and it costs one fork on a path that is already spawning a whole CLI.
    if MCP_OUTPUT=$(env -u CC_PANE_ID -u ITERM_SESSION_ID claude mcp list 2>&1); then
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
    "additionalContext": "${EFFORT_WARN}MCP: $CONNECTED_COUNT server(s). agent-browser: $AGENT_BROWSER_STATUS. If BrowserMCP tools fail with 'No such tool available', use agent-browser skill instead."
  }
}
EOF
else
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "${EFFORT_WARN}WARNING: MCP not responding. agent-browser: $AGENT_BROWSER_STATUS. Use agent-browser skill for browser automation."
  }
}
EOF
fi

exit 0
