#!/bin/bash
# boot-resume-launch.sh — the TTY-coupled resume seam for boot-resume.sh (T-P16-2).
#
# boot-resume.sh runs headless from launchd and CANNOT host an interactive `claude --resume` (which
# reso-resume-one drives via `expect ... interact` and needs a real pane/tty). So the actual resume
# is delegated here: open a FRESH iTerm2 window and run reso-resume-one inside it, where the resumed
# Claude UI can live. Isolating this GUI-coupled step keeps the orchestrator (detect/decide/dedup/
# page) fully unit-testable — boot-resume.sh calls this via the CC_RESUME_LAUNCH_BIN seam.
#
#   Usage: boot-resume-launch.sh <account-alias> <cwd> <session-id> [branch]
#     account-alias: next|next2|next3|next4|fable.. (already MAPPED by boot-resume.sh)
#   --dry-run (or CC_LAUNCH_DRYRUN=1): print the reso-resume-one command + the osascript, run nothing.
#
# Env: CC_RESUME_ONE_BIN (default ~/.reso/bin/reso-resume-one) · CC_OSASCRIPT_BIN (default osascript).
# Never reuses the current pane (resume-sessions off-by-one rule); always a new window. Fail-loud.
set -uo pipefail

DRYRUN="${CC_LAUNCH_DRYRUN:-0}"
case "${1:-}" in
  -h|--help) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
  --dry-run) DRYRUN=1; shift ;;
esac

acct="${1:-}"; cwd="${2:-}"; sid="${3:-}"; branch="${4:-}"
if [ -z "$acct" ] || [ -z "$sid" ]; then
  echo "boot-resume-launch: usage: <account-alias> <cwd> <session-id> [branch]" >&2
  exit 2
fi

RESUME_ONE="${CC_RESUME_ONE_BIN:-$HOME/.reso/bin/reso-resume-one}"
OSASCRIPT="${CC_OSASCRIPT_BIN:-osascript}"

# shell-quote a single argument (wrap in single quotes, escaping embedded single quotes) so a cwd
# with spaces survives the osascript `write text` shell.
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

CMD="$(shq "$RESUME_ONE") $(shq "$acct") $(shq "$cwd") $(shq "$sid")"
[ -n "$branch" ] && CMD="$CMD $(shq "$branch")"

# osascript escaping: the command runs inside an AppleScript double-quoted string → escape " and \.
osa_cmd="$(printf '%s' "$CMD" | sed 's/\\/\\\\/g; s/"/\\"/g')"
read -r -d '' OSA <<OSA_EOF || true
tell application "iTerm2"
  activate
  set w to (create window with default profile)
  tell current session of w
    write text "$osa_cmd"
  end tell
end tell
OSA_EOF

if [ "$DRYRUN" = "1" ]; then
  printf 'CMD: %s\n' "$CMD"
  printf '%s\n' "$OSA"
  exit 0
fi

if [ ! -x "$RESUME_ONE" ]; then
  echo "boot-resume-launch: reso-resume-one not executable at $RESUME_ONE" >&2
  exit 3
fi
command -v "${OSASCRIPT%% *}" >/dev/null 2>&1 || { echo "boot-resume-launch: osascript unavailable" >&2; exit 3; }

# ensure iTerm2 is up (post-login it may not be running yet), then drive it.
open -a iTerm 2>/dev/null || true
printf '%s' "$OSA" | "$OSASCRIPT" - >/dev/null 2>&1 || { echo "boot-resume-launch: osascript failed for $sid" >&2; exit 4; }
exit 0
