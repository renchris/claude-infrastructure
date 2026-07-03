#!/bin/bash
# push-critical.sh — Pushover break-through for Claude Code "needs input",
# LABELED per account for a 4-account (shared-hooks) fan-out.
#
# Account label derives from CLAUDE_CONFIG_DIR (VERIFIED present in the hook env on
# CC 2.1.183), with a transcript_path fallback. cwd from CLAUDE_PROJECT_DIR (verified),
# falling back to stdin .cwd then $PWD. Because all 4 config dirs share ~/.claude/hooks
# + settings.json via symlink, this ONE file serves every account.
#
# STATUS: INERT until PUSHOVER_TOKEN and PUSHOVER_USER are exported. Put them in ~/.zshenv
# so every account's binary AND its hook children inherit them.
#
# Break-through note (corrected): priority=1 bypasses Pushover's OWN quiet hours and forces
# sound, but to pierce the iOS mute switch + Focus/DND you must enable Critical Alerts in the
# Pushover iOS app (Settings > Priority > High Priority > "Override Silent Mode" — app-side,
# NOT an API param). For repeat-until-acknowledged, use priority=2 + retry(>=30) + expire(<=10800).
#
# It is a SEPARATE Notification hook object — never folded into notify.sh, whose 2s
# cross-account debounce would drop a second account's simultaneous push.
set -u
[ -z "${PUSHOVER_TOKEN:-}" ] && exit 0
[ -z "${PUSHOVER_USER:-}" ]  && exit 0

JQ="$(command -v jq || echo /opt/homebrew/bin/jq)"
input="$(cat 2>/dev/null || true)"   # CC pipes the hook JSON on stdin; EOFs immediately

# --- account label: env first (dependency-free), transcript_path fallback ---
cfg="${CLAUDE_CONFIG_DIR:-}"
if [ -z "$cfg" ] && [ -n "$input" ] && [ -x "$JQ" ]; then
  tp="$(printf '%s' "$input" | "$JQ" -r '.transcript_path // empty' 2>/dev/null)"
  case "$tp" in "$HOME"/.claude*/projects/*) cfg="${tp%%/projects/*}" ;; esac
fi
case "$cfg" in
  "$HOME"/.claude-next)       acct="acct1" ;;
  "$HOME"/.claude-secondary)  acct="acct2" ;;
  "$HOME"/.claude-tertiary)   acct="acct3" ;;
  "$HOME"/.claude-quaternary) acct="acct4" ;;
  "$HOME"/.claude)            acct="default" ;;
  "")                         acct="acct?" ;;
  *)                          acct="${cfg##*/}" ;;
esac

# --- cwd: env first, stdin fallback, PWD last ---
cwd="${CLAUDE_PROJECT_DIR:-}"
if [ -z "$cwd" ] && [ -n "$input" ] && [ -x "$JQ" ]; then
  cwd="$(printf '%s' "$input" | "$JQ" -r '.cwd // empty' 2>/dev/null)"
fi
[ -z "$cwd" ] && cwd="${PWD:-?}"
dir="$(basename "$cwd")"

# --- message from the Notification payload ---
msg=""
[ -n "$input" ] && [ -x "$JQ" ] && msg="$(printf '%s' "$input" | "$JQ" -r '.message // empty' 2>/dev/null)"
[ -z "$msg" ] && msg="waiting for input"

# Per-account sound — hear WHICH account needs you without looking (fixes alert fatigue
# when 4 accounts share one Pushover user key). Override any with your own Pushover sounds.
case "$acct" in
  acct1) snd=pushover ;; acct2) snd=bike ;; acct3) snd=cosmic ;; acct4) snd=bugle ;; *) snd=pushover ;;
esac

curl -s --max-time 4 -X POST https://api.pushover.net/1/messages.json \
  -d "token=${PUSHOVER_TOKEN}" \
  -d "user=${PUSHOVER_USER}" \
  -d "title=Claude ${acct} — needs input" \
  -d "message=[${acct}] ${dir}: ${msg}" \
  -d "sound=${snd}" \
  -d "priority=1" >/dev/null 2>&1 || true
exit 0
