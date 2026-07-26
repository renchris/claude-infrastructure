#!/bin/bash
# Claude Code Audio Notification Script
# Usage: notify.sh <event_type>

set -euo pipefail

# Bound the OS-notification fork (machine-wide iTerm2/AppleEvent wedge, 2026-07-26). This one
# targets NotificationCenter rather than iTerm2, so it is not the root cause — but it is an
# AppleEvent fork inside an automated path, and an unbounded one turns a best-effort page into a
# stalled hook. Every call site here is already best-effort (`|| true`), so a cut costs at most
# one missed notification and never a wrong verdict. timeout(1) is resolved by ABSOLUTE PATH as
# well as PATH — hooks and launchd jobs run without Homebrew on PATH, where coreutils installs it.
# No timeout(1) ⇒ run unbounded rather than lose notifications entirely.
# Seams: NTY_OSA_TIMEOUT_S · NTY_OSA_TIMEOUT_BIN (set-but-EMPTY disables verbatim).
NTY_OSA_TIMEOUT_S="${NTY_OSA_TIMEOUT_S:-5}"
if [ -n "${NTY_OSA_TIMEOUT_BIN+set}" ]; then
  NTY_OSA_TB="${NTY_OSA_TIMEOUT_BIN}"
else
  NTY_OSA_TB=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { NTY_OSA_TB="$_c"; break; }
  done
fi
nty_osa() {
  if [ -z "$NTY_OSA_TB" ] || [ ! -x "$NTY_OSA_TB" ]; then "$@"; return $?; fi
  "$NTY_OSA_TB" -k 3 "$NTY_OSA_TIMEOUT_S" "$@"
}


EVENT_TYPE="${1:-complete}"
SOUNDS_DIR="/System/Library/Sounds"
SCREENREADER_SOUNDS="/System/Library/PrivateFrameworks/ScreenReader.framework/Versions/A/Resources/Sounds"
LOG_FILE="/tmp/claude-notify.log"

# Debounce: prevent duplicate notifications within 2 seconds
_ACCT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _ACCT="${_ACCT##*/}"
DEBOUNCE_FILE="/tmp/claude-notify-${_ACCT}-${EVENT_TYPE}.lock"
if [[ -f "$DEBOUNCE_FILE" ]]; then
    LAST_NOTIFY=$(stat -f %m "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    if (( NOW - LAST_NOTIFY < 2 )); then
        exit 0
    fi
fi
touch "$DEBOUNCE_FILE"

case "$EVENT_TYPE" in
    permission)
        SOUND="Funk.aiff"
        TITLE="Permission Required"
        MESSAGE="Claude needs your approval"
        ;;
    question)
        SOUND="Blow.aiff"
        TITLE="Question from Claude"
        MESSAGE="Claude has a question for you"
        ;;
    elicitation)
        SOUND="${SCREENREADER_SOUNDS}/BubbleAppear.aiff"
        TITLE="MCP Input Needed"
        MESSAGE="MCP tool requires your input"
        ;;
    complete)
        SOUND="Purr.aiff"
        TITLE="Task Complete"
        MESSAGE="Claude finished responding"
        ;;
    auth)
        SOUND="Pop.aiff"
        TITLE="Authentication"
        MESSAGE="Authentication successful"
        ;;
    plan)
        SOUND="Glass.aiff"
        TITLE="Plan Ready"
        MESSAGE="Review and approve the plan"
        ;;
    *)
        SOUND="Pop.aiff"
        TITLE="Claude Code"
        MESSAGE="Notification"
        ;;
esac

# Log for debugging
echo "$(date): Playing ${SOUND} for ${EVENT_TYPE}" >> "$LOG_FILE"

# Play sound async (background with disown so script can exit immediately)
if [[ "$SOUND" == /* ]]; then
    afplay "${SOUND}" 2>> "$LOG_FILE" &
else
    afplay "${SOUNDS_DIR}/${SOUND}" 2>> "$LOG_FILE" &
fi
disown 2>/dev/null || true

# Show desktop notification for high-priority events only
if [[ "$EVENT_TYPE" == "permission" || "$EVENT_TYPE" == "question" || "$EVENT_TYPE" == "elicitation" || "$EVENT_TYPE" == "plan" ]]; then
    nty_osa osascript -e "display notification \"${MESSAGE}\" with title \"${TITLE}\" sound name \"${SOUND%.aiff}\"" 2>/dev/null || true
fi

exit 0
