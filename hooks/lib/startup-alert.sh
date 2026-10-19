# shellcheck shell=bash
# startup-alert.sh — the rolling startup alert file for an idle pane (sourced; bash 3.2).
#
#   sa_alert <sid> <line>   add <line> to "$R/alerts/<sid>" unless it is already there
#
# WHY. A start that loses output in a pane nobody types into never reaches the prompt front
# (hooks/session-beat.sh), so its loss is silent until the next prompt (README D20). A FileChanged
# hook watching "$R/alerts" (README #13a, a c10 settings registration that is the operator's) can
# push these lines to that idle pane within ~1 s. ONE file per session holding EVERY pending line,
# rewritten whole (temp + mv): the harness drops a second toast inside 5 s, so two faults must read
# as one file with two lines, not two events (README §5 unit 3.6, gap-G2). Harmless before #13a:
# nothing reads the file except `cc-startup-health`, and the prompt front empties it once the
# session's startup is resolved.
#
# Writers: the 3.1 sentinel on a non-zero exit (TERM included) and the dispatcher's
# ssd_alert_hook (its TERM trap and late collector). Runs on a dying hook's exit path, so builtins
# plus one `mkdir` (first alert only) and one `mv`; a short mkdir lock keeps two concurrent writers
# from dropping each other's line, and a writer that cannot get it writes anyway.
# R=${CC_STARTUP_HEALTH_DIR:-$HOME/.claude/state/startup-health}. Kill switch: CC_STARTUP_ALERT=0.

sa_alert() {
  local sid="${1:-}" line="${2:-}" dir f tmp l body="" i=0 locked=0
  [ "${CC_STARTUP_ALERT:-1}" = 0 ] && return 0
  case "$sid" in ''|*[!0-9A-Za-z-]*) return 0 ;; esac
  [ -n "$line" ] || return 0
  dir="${CC_STARTUP_HEALTH_DIR:-$HOME/.claude/state/startup-health}/alerts"
  [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 0
  f="$dir/$sid"; tmp="$dir/.$sid.$$"
  while [ "$i" -lt 20 ]; do
    if mkdir "$f.lock" 2>/dev/null; then locked=1; break; fi
    i=$(( i + 1 )); sleep 0.02 2>/dev/null
  done
  if [ -f "$f" ]; then
    while IFS= read -r l; do
      [ "$l" = "$line" ] && { [ "$locked" = 1 ] && rmdir "$f.lock" 2>/dev/null; return 0; }
      body="$body$l"$'\n'
    done < "$f"
  fi
  printf '%s%s\n' "$body" "$line" > "$tmp" 2>/dev/null && mv -f "$tmp" "$f" 2>/dev/null
  [ "$locked" = 1 ] && rmdir "$f.lock" 2>/dev/null
  return 0
}
