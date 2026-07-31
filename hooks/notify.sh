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
# ── ARTIFACT DIR: private by construction, never a fixed name in world-writable /tmp ─────────────
# WHY: the log and the debounce locks were fixed names directly under mode-1777 /tmp. The sticky
# bit stops another uid REPLACING a file we own — it does NOT stop them PRE-CREATING a name that
# does not exist yet. A symlink planted at /tmp/claude-notify.log makes every append below follow
# it and write into an attacker-chosen file AS US, on a hook that fires on every Stop; a planted
# lock silences one named session, and the lock filenames publish live session ids to anyone who
# can read the directory. CWE-59/377 — codex-security 2026-07-29 finding 2, whose findings.json
# records exactly this dataflow.
#
# The guarantee is the MODE OF A DIRECTORY WE MINT, not the luck of the base path — the same
# conclusion the launcher hardening reached (09a0214a): answer the property, not the path.
#   • base = $TMPDIR first: per-uid /var/folders/…/T, already 0700, and NO fork on the hot path.
#   • launchd injects no TMPDIR into agent jobs (14 of 15 sampled user agents in 09a0214a), so fall
#     back to `getconf DARWIN_USER_TEMP_DIR`, which resolves from confstr and NOT the environment
#     (verified here under `env -i`). A bare `${TMPDIR:-/tmp}` is the measured trap: it reads as
#     applied while landing straight back in 1777 /tmp exactly where it matters. The fork is paid
#     only on that fallback, never when TMPDIR is present.
#   • then a dedicated subdir minted 0700, so even the /tmp fallback leaves no pre-create primitive.
#
# Relocating (rather than only tightening the mode, as the telemetry dir had to) is safe here
# because claude-notify.log has NO consumer: the only non-doc references in-tree are this writer
# and the bats suite, which follows the seam. hooks/session-end.sh's tmp sweep reaps only
# handoff-* at maxdepth 1, so nothing was reaping these anyway and nothing is stranded by the move.
#
# Seam: CC_NOTIFY_DIR relocates the log + debounce locks (bats asserts on real artifacts without
# writing live fleet state — the same role CC_PERMPEND_DIR plays for the beacon).
if [ -z "${CC_NOTIFY_DIR:-}" ]; then
  _nty_base="${TMPDIR:-}"
  if [ -z "$_nty_base" ]; then _nty_base="$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"; fi
  if [ -z "$_nty_base" ]; then _nty_base="/tmp"; fi
  CC_NOTIFY_DIR="${_nty_base%/}/cc-notify"
fi
# Mint at CREATE time only — `[ -d ]` is a builtin, so the steady state costs no fork on a hook
# this hot. `umask 077` rather than `mkdir -m 700`: with -p, -m applies ONLY to the deepest
# component (SC2174, and confirmed on this host — the intermediate came out 0755), so a
# CC_NOTIFY_DIR pointing somewhere two levels deep would leave a world-writable parent behind.
# umask covers every component, and the dir is never briefly loose between a mkdir and a chmod.
if [ ! -d "$CC_NOTIFY_DIR" ]; then (umask 077; mkdir -p "$CC_NOTIFY_DIR") 2>/dev/null || true; fi
# A dir that is a symlink, not ours, or unwritable is refused outright — a foreign dir at this path
# IS the pre-create primitive. Refusal disables the ARTIFACTS ONLY; the alert below still fires.
NTY_DIR_OK=1
if [ -L "$CC_NOTIFY_DIR" ] || [ ! -d "$CC_NOTIFY_DIR" ] || [ ! -O "$CC_NOTIFY_DIR" ] || [ ! -w "$CC_NOTIFY_DIR" ]; then
  NTY_DIR_OK=0
fi
# Per-sink guard as well as per-dir. CC_NOTIFY_DIR is an operator-settable seam that can point
# anywhere, so the symlink refusal must be LOCAL to the sink rather than inherited from an
# assumption about its parent. Safe iff: the dir passed, the path is not a symlink, and it is
# either absent or a regular file we own. All builtins — no fork.
nty_sink_ok() {
  if [ "$NTY_DIR_OK" != 1 ]; then return 1; fi
  if [ -L "$1" ]; then return 1; fi
  if [ ! -e "$1" ]; then return 0; fi
  if [ -f "$1" ] && [ -O "$1" ]; then return 0; fi
  return 1
}
LOG_FILE="${CC_NOTIFY_DIR}/claude-notify.log"
# Resolved once: every append below goes to the real log or to /dev/null, never to a planted path.
if nty_sink_ok "$LOG_FILE"; then NTY_LOG="$LOG_FILE"; else NTY_LOG="/dev/null"; fi

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
  # Cut to 400 BEFORE the three global substitutions. They are O(n) each over the whole payload,
  # and this runs on the PermissionRequest path where the hook is blocking the operator's prompt:
  # measured 1 MB→1.5 s, 2 MB→5.4 s, 5 MB→30 s, i.e. straight through the 5 s hook budget on a
  # large tool_input. 400 is comfortably above the 140-char cap below, so the visible result is
  # byte-identical — only the work disappears.
  local s="${1:0:400}" sq="'"
  s="${s//\\/ }"
  s="${s//\"/$sq}"
  s="${s//[[:cntrl:]]/ }"
  if (( ${#s} > 140 )); then s="${s:0:140}…"; fi
  printf '%s' "$s"
}
DETAIL="$(nty_scrub "$DETAIL")"
# SID8 reaches the AppleScript literal too. Line 83 already treats SID as untrusted for the
# FILENAME sink; leaving the same value raw for the script sink is an inconsistency, and a quote
# in it is a -2740 syntax error, i.e. the alert renders NOTHING.
SID8="$(nty_scrub "$SID8")"
DIR="$(nty_scrub "$DIR")"
TOOL="$(nty_scrub "$TOOL")"

# ── Debounce: prevent duplicate notifications within 2 seconds — keyed PER SESSION ───────────────
# WHY per session: the key used to be per ACCOUNT, so two sessions blocking within the 2 s window
# collapsed into ONE notification and the second block simply vanished. At this fleet's concurrency
# that is a routine drop, BY CONSTRUCTION, of exactly the events we most need to see
# (§3 Stage A.2). No session id (fail-open payload) ⇒ fall back to the old account-wide key.
_ACCT="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; _ACCT="${_ACCT##*/}"
DEBOUNCE_FILE="${CC_NOTIFY_DIR}/claude-notify-${_ACCT}-${SID_SAFE:-nosid}-${EVENT_TYPE}.lock"
# The same sink guard runs on the lock, and `-f` alone would not have been it: `[[ -f ]]` FOLLOWS a
# symlink to a regular file, so the planted-lock mute would have read as a legitimate fresh lock.
# An unsafe lock path means NO debounce rather than a trusted one — fail toward notifying.
if nty_sink_ok "$DEBOUNCE_FILE" && [[ -f "$DEBOUNCE_FILE" ]]; then
    LAST_NOTIFY=$(stat -f %m "$DEBOUNCE_FILE" 2>/dev/null || echo 0)
    NOW=$(date +%s)
    # A lock stamped in the FUTURE is treated as stale, never as fresh. `NOW - LAST_NOTIFY` goes
    # NEGATIVE there, which satisfies `< 2` forever, and the `touch` below is never reached — so the
    # suppression is self-perpetuating rather than a 2 s window. Two real triggers: any backward
    # clock step (NTP correction, lid or VM resume) blackholes a session's alerts until wall-clock
    # catches up; and /tmp is world-writable with these filenames publishing live session ids, so a
    # local user can pre-create one and silence a specific session. Fail toward NOTIFYING.
    if (( LAST_NOTIFY <= NOW && NOW - LAST_NOTIFY < 2 )); then
        exit 0
    fi
fi
# same rule: the lock is best-effort, the alert is not — and we never `touch` a path the guard
# rejected, since that is precisely how a planted symlink would get its target's mtime bumped.
if nty_sink_ok "$DEBOUNCE_FILE"; then touch "$DEBOUNCE_FILE" 2>/dev/null || true; fi

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
# `|| true`: this is a DIAGNOSTIC, and it was the only side-effecting line here without one — so
# under `set -e` an unwritable log file (disk full, or a foreign-owned file at this fixed
# world-writable path after the tmp cleaner reaps it) aborted the hook and the alert was never
# rendered at all. A missing log line must never cost the notification it is describing.
{ echo "$(date): Playing ${SOUND} for ${EVENT_TYPE} [${SID8:-nosid}${DIR:+ ${DIR}}]" >> "$NTY_LOG"; } 2>/dev/null || true

# Play sound async (background with disown so script can exit immediately)
# afplay's stderr is the OTHER append at this path — a redirect the eye skips, and it CREATES the
# file just as readily as the log line above, so it needs the resolved sink too.
if [[ "$SOUND" == /* ]]; then
    afplay "${SOUND}" 2>> "$NTY_LOG" &
else
    afplay "${SOUNDS_DIR}/${SOUND}" 2>> "$NTY_LOG" &
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
