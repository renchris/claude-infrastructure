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
# Seam: CC_NOTIFY_DIR relocates the log + debounce locks (default /tmp, unchanged in production).
# Exists so the bats suite can assert on real artifacts without writing live fleet state — the same
# role CC_PERMPEND_DIR plays for the beacon.
CC_NOTIFY_DIR="${CC_NOTIFY_DIR:-/tmp}"
LOG_FILE="${CC_NOTIFY_DIR}/claude-notify.log"

# ── IDENTITY: read the harness payload so an alert NAMES the session it came from ────────────────
# WHY: EVENT_TYPE="$1" used to be this hook's ENTIRE input — it read no stdin and no payload — so
# every desktop alert said "Claude needs your approval" and named nothing. At ~30 concurrent
# sessions that is untriageable: the operator still has to hunt panes, which is the compensating
# control the whole legibility push exists to retire
# (docs/research/step3-to-step4-pathway-2026-07-31.md §2b, §3 Stage A.1).
#
# Fail-open in every direction: no stdin, no jq, or a malformed payload ⇒ the ORIGINAL anonymous
# strings still fire. A notification that names nothing beats a notification that never comes.
# `[ -t 0 ]` guards the read: hooks always get JSON on stdin (the beacon does this on the far
# hotter PostToolUse path, and push-critical.sh records that CC "EOFs immediately"), but a human
# running this from a terminal would otherwise block on `cat` until the 5 s hook timeout.
INPUT=""
[ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"
# Seam: CC_NOTIFY_JQ (testability — lets the suite exercise the genuinely-no-jq branch).
JQ="${CC_NOTIFY_JQ:-$(command -v jq 2>/dev/null || echo /opt/homebrew/bin/jq)}"

SID=""; PAY_CWD=""; TOOL=""; DETAIL=""
if [ -n "$INPUT" ] && [ -x "$JQ" ]; then
  # ONE jq fork for all four fields (this hook also runs on every Stop).
  #
  # The separator is US (\x1f), NOT a tab, and that is load-bearing. Tab is an IFS *whitespace*
  # character, so bash collapses runs of it and drops empty fields: a payload with no tool_name —
  # which is EVERY Notification event, i.e. the live `permission_prompt` path — would shift the
  # message left into TOOL and leave DETAIL empty, rendering the command nowhere. \x1f is
  # non-whitespace, so empty fields are preserved positionally. Newlines/tabs inside a value are
  # flattened first, so a multi-line command cannot truncate the single-line `read`.
  # The `?` suffixes keep a non-object tool_input from erroring the whole expression.
  _F="$(printf '%s' "$INPUT" | "$JQ" -r '
        [ (.session_id // ""), (.cwd // ""), (.tool_name // ""),
          ( .tool_input.command? // .tool_input.file_path? // .tool_input.description?
            // .message? // "" ) ]
        | map(tostring | gsub("[\n\r\t]"; " ")) | join("\u001f")' 2>/dev/null || true)"
  IFS=$'\x1f' read -r SID PAY_CWD TOOL DETAIL <<<"$_F" || true
fi

# cwd: env first (dependency-free, verified present in the hook env), stdin fallback, PWD last.
CWD="${CLAUDE_PROJECT_DIR:-}"; [ -z "$CWD" ] && CWD="$PAY_CWD"; [ -z "$CWD" ] && CWD="${PWD:-}"
DIR="${CWD##*/}"
SID8="${SID%%-*}"                                  # first uuid group — enough to name a pane

# The session id becomes a FILENAME component below; reject anything that is not a safe basename.
case "$SID" in ''|*[!A-Za-z0-9._-]*) SID_SAFE="" ;; *) SID_SAFE="$SID" ;; esac

# DETAIL is MODEL-AUTHORED text (the blocked command) interpolated into an AppleScript string
# literal, so it is scrubbed to a notification-safe subset — backslash FIRST (AppleScript's escape
# char, and @tsv leaves literals), then the quote that would terminate the literal, then control
# chars. Pure bash, no forks. See memory json-quoting-is-not-shell-quoting: generated source must
# be escaped for the language that will PARSE it, not the one that wrote it.
#
# The single quote is substituted VIA A VARIABLE, not written inline: inside double quotes bash
# leaves `\'` as backslash-quote, which re-introduces the escape char this function just stripped —
# and `\'` is a hard SYNTAX ERROR in AppleScript (verified: osascript -2741 "Expected \" but found
# unknown token"). That would have silently dropped every alert whose command contains a quote —
# `git commit -m "…"`, the common case — i.e. reproduced the exact drop this change removes.
nty_scrub() {
  local s="$1" sq="'"
  s="${s//\\/ }"
  s="${s//\"/$sq}"
  s="${s//[[:cntrl:]]/ }"
  if (( ${#s} > 140 )); then s="${s:0:140}…"; fi
  printf '%s' "$s"
}
DETAIL="$(nty_scrub "$DETAIL")"
DIR="$(nty_scrub "$DIR")"
TOOL="$(nty_scrub "$TOOL")"

# ── Debounce: prevent duplicate notifications within 2 seconds — keyed PER SESSION ───────────────
# WHY per session: the key used to be per ACCOUNT, so two sessions blocking within the 2 s window
# collapsed into ONE notification and the second block simply vanished. At this fleet's concurrency
# that is a routine drop, BY CONSTRUCTION, of exactly the events we most need to see
# (§3 Stage A.2). No session id (fail-open payload) ⇒ fall back to the old account-wide key.
_ACCT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _ACCT="${_ACCT##*/}"
DEBOUNCE_FILE="${CC_NOTIFY_DIR}/claude-notify-${_ACCT}-${SID_SAFE:-nosid}-${EVENT_TYPE}.lock"
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

# ── Overlay the identity onto the anonymous fallback above ───────────────────────────────────────
# The case block stays the FALLBACK: with no payload (no stdin / no jq / malformed) the MESSAGE
# reads exactly as it always did — "Claude needs your approval". The title still gains the
# directory, because cwd falls back to $PWD, which for a hook IS the session's directory; only a
# payload can supply the session id and the command. With a payload it is triage-ready at a glance:
#   title     Permission · claude-infrastructure
#   subtitle  1a5cf368 · Bash
#   message   git push --force origin main
SUBTITLE=""
if [[ -n "$DIR" || -n "$SID8" ]]; then
    case "$EVENT_TYPE" in
        permission)  TITLE="Permission" ;;
        question)    TITLE="Question" ;;
        elicitation) TITLE="MCP input" ;;
        plan)        TITLE="Plan ready" ;;
        complete)    TITLE="Task complete" ;;
    esac
    if [[ -n "$DIR" ]];    then TITLE="${TITLE} · ${DIR}"; fi
    SUBTITLE="$SID8"
    if [[ -n "$TOOL" ]];   then SUBTITLE="${SUBTITLE:+${SUBTITLE} · }${TOOL}"; fi
    if [[ -n "$DETAIL" ]]; then MESSAGE="$DETAIL"; fi
fi

# Log for debugging — carries the identity too, so the log is itself triageable after the fact.
echo "$(date): Playing ${SOUND} for ${EVENT_TYPE} [${SID8:-nosid}${DIR:+ ${DIR}}]" >> "$LOG_FILE"

# Play sound async (background with disown so script can exit immediately)
if [[ "$SOUND" == /* ]]; then
    afplay "${SOUND}" 2>> "$LOG_FILE" &
else
    afplay "${SOUNDS_DIR}/${SOUND}" 2>> "$LOG_FILE" &
fi
disown 2>/dev/null || true

# Show desktop notification for high-priority events only
if [[ "$EVENT_TYPE" == "permission" || "$EVENT_TYPE" == "question" || "$EVENT_TYPE" == "elicitation" || "$EVENT_TYPE" == "plan" ]]; then
    # `subtitle` is omitted rather than passed empty — AppleScript renders an empty subtitle as a
    # blank line, which would cost the very legibility this change buys. TITLE/SUBTITLE/MESSAGE
    # have all been through nty_scrub, so no field can terminate the string literal.
    _NTY_AS="display notification \"${MESSAGE}\" with title \"${TITLE}\""
    if [[ -n "$SUBTITLE" ]]; then _NTY_AS="${_NTY_AS} subtitle \"${SUBTITLE}\""; fi
    _NTY_AS="${_NTY_AS} sound name \"${SOUND%.aiff}\""
    nty_osa osascript -e "$_NTY_AS" 2>/dev/null || true
fi

exit 0
