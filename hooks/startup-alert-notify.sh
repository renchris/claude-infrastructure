#!/bin/bash
# startup-alert-notify.sh — FileChanged notifier: a startup fault written to
# ~/.claude/state/startup-health/alerts/<session_id> reaches THAT session's pane within about a
# second, idle or not, as a toast plus a terminal bell / kitty desktop notification. 0 model tokens.
#
# Registered by migrations/0071-filechanged-startup-alerts.sh as a matcher-less FileChanged group,
# beside a group whose ABSOLUTE matcher is the alerts dir: that matcher arms the watch at setup,
# before any SessionStart hook runs, and never dispatches (it is regex-tested against the basename).
# Every live session watches the same dir, so every session runs this hook on every alert; each one
# acts only when the file's name is its own session id. Design and probe:
# docs/research/startup-hooks-2026-10-18/gap-G2.md, probes/probeA-RESULT.md.
#
# Builtins only (no jq, sed or $( ) subshell): it runs once per alert in every session.
# Measured on 2.1.293 (probe A): the toast lasts 5 s and a second `env-hook` toast that arrives
# while one is current OR queued is dropped, and startup notices can hold the toast back ~8 s. The
# terminalSequence is written on every run, so the bell is the part that always arrives. That is
# why writers keep ONE rolling file per session holding every pending line, and why this prints
# the whole file, not the newest line.
#
# Fails open: anything unexpected exits 0 with nothing on stdout.
set -u

ALERTS="${CC_STARTUP_ALERT_DIR:-$HOME/.claude/state/startup-health/alerts}"
MAXLINES=6
MAXCHARS=400

in=""
IFS= read -r -d '' in || :

v=""
field() { # <key> → $v: the string value of "key":"…" (values here are ids and paths, never escaped)
  local k="\"$1\":\""
  v=""
  case "$in" in *"$k"*) v="${in#*"$k"}"; v="${v%%\"*}" ;; esac
}

field hook_event_name; [ "$v" = "FileChanged" ] || exit 0
field event; case "$v" in add|change) ;; *) exit 0 ;; esac
field session_id; sid="$v"
case "$sid" in ''|*/*|.*) exit 0 ;; esac
field file_path; fp="$v"
# Exactly <alerts>/<own sid>: another session's alert, or a same-named file in any other watched
# dir, is not ours. /private covers a dir under /tmp or /var, which the harness reports resolved.
case "$fp" in
  "$ALERTS/$sid"|"/private$ALERTS/$sid") ;;
  *) exit 0 ;;
esac
[ -f "$fp" ] || exit 0

msg="" n=0
while [ "$n" -lt "$MAXLINES" ] && IFS= read -r line; do
  [ -n "$line" ] || continue
  msg="${msg:+$msg · }$line"
  n=$((n + 1))
done < "$fp"
[ -n "$msg" ] || msg="a startup hook failed (details: ~/.claude/state/startup-health)"
msg="${msg//[[:cntrl:]]/ }"
[ "${#msg}" -le "$MAXCHARS" ] || msg="${msg:0:$MAXCHARS}…"
msg="${msg//\\/\\\\}"
msg="${msg//\"/\\\"}"

# BEL marks the tab; OSC 99 posts a kitty desktop notification. Both are on the harness allowlist.
printf '{"systemMessage":"⚠ startup: %s","terminalSequence":"\\u0007\\u001b]99;;Claude Code startup fault %s\\u001b\\\\"}\n' \
  "$msg" "${sid:0:8}"
exit 0
