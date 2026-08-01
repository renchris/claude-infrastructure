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

# Bound every call that reaches the iTerm2 / AppleEvent surface (machine-wide API wedge,
# 2026-07-26: a bare `it2 session list --json` returned rc 124 with zero output while blocked forks
# piled up). This runs at BOOT to drive iTerm2; unbounded, a wedged API strands the whole resume with no
# operator feedback. The existing rc-4 'osascript failed' path already reports a cut.
# timeout(1) is resolved by ABSOLUTE PATH as well as PATH — launchd jobs and hooks run with a
# minimal PATH excluding Homebrew, exactly where coreutils installs it, so a PATH-only lookup would
# leave the AUTOMATED callers unbounded while interactive shells stayed safe. No timeout(1) ⇒ run
# unbounded rather than break the call. Seams: CC_OSA_TIMEOUT_S · CC_OSA_TIMEOUT_BIN
# (set-but-EMPTY disables verbatim; `${VAR:-}` cannot tell unset from set-empty).
BRL_TIMEOUT_S="${CC_OSA_TIMEOUT_S:-20}"
if [ -n "${CC_OSA_TIMEOUT_BIN+set}" ]; then
  BRL_TIMEOUT_BIN="$CC_OSA_TIMEOUT_BIN"
else
  BRL_TIMEOUT_BIN=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { BRL_TIMEOUT_BIN="$_c"; break; }
  done
fi
brl_bounded() {
  if [ -z "$BRL_TIMEOUT_BIN" ] || [ ! -x "$BRL_TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$BRL_TIMEOUT_BIN" -k 3 "$BRL_TIMEOUT_S" "$@"
}


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
tell application id "com.googlecode.iterm2"
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
printf '%s' "$OSA" | brl_bounded "$OSASCRIPT" - >/dev/null 2>&1 || { echo "boot-resume-launch: osascript failed for $sid" >&2; exit 4; }
exit 0
