# shellcheck shell=bash
# startup-proof.sh — "stamp only after proof of delivery" for SessionStart output (sourced; bash 3.2).
#
#   sp_request <sid> <name> <needle> <action> [<arg>...]   file a proof request; builtins + 1 mkdir
#
# WHY. A SessionStart hook that stamps "I delivered this" right after printing is wrong whenever the
# harness then discards its output: a cancelled hook's stdout is dropped whole, and so is the output
# of a hook that finished inside the harness's lag (docs/research/startup-hooks-2026-10-18 gap-G3 F3).
# The stamp then suppresses the one thing that was never seen — a failed recycle's recovery order,
# the deadline banner, the goal nudge — for good (README §2 row #21, §5 unit 5.4). So a hook prints
# and FILES this request instead of stamping; session-beat's detached prompt worker
# (hooks/lib/startup-health.sh sh_settle) looks for <needle> in the session transcript's delivered
# hook output (hook_success stdout, hook_system_message, hook_additional_context — the transcript is
# the authority) and only then performs <action>. Not found once the startup is scanned: the action
# is not done, so the hook says it again at the next start; a request with a `fallback` file is
# instead injected by the prompt front once (the UPS fallback), then proven from that turn's record.
#
# Actions (the worker runs exactly these, nothing else):
#   touch  <file>                        create <file> (a latch / once-marker)
#   write  <file> <text>                 write <text> as <file> (temp + mv)
#   jqset  <json-file> <key>             set .<key> to now (UTC) in <json-file> (temp + mv)
#   idl    <idl-file> <hook> <extra-json>  append a `fired` row on proof, a `failed` row
#                                        ("not-delivered") when the startup ends without it
# Optional last line `fallback=<file>`: text to inject as additionalContext at the next prompt when
# the needle is absent (recycle-failed-inject's order). One file per request:
#   "$R/<sid>/proof.<name>"   needle= / action= / arg1= / arg2= / arg3= / fallback=
# R=${CC_STARTUP_HEALTH_DIR:-$HOME/.claude/state/startup-health}. Kill switch: CC_STARTUP_PROOF=0 —
# the caller then stamps at print as before (sp_request returns 1).

sp_request() {
  local sid="${1:-}" name="${2:-}" needle="${3:-}" action="${4:-}" d f
  [ "${CC_STARTUP_PROOF:-1}" = 0 ] && return 1
  case "$sid" in ''|*[!0-9A-Za-z-]*) return 1 ;; esac
  case "$name" in ''|*[!0-9A-Za-z_-]*) return 1 ;; esac
  case "$action" in touch|write|jqset|idl) ;; *) return 1 ;; esac
  case "$needle" in ''|*$'\n'*) return 1 ;; esac
  shift 4
  d="${CC_STARTUP_HEALTH_DIR:-$HOME/.claude/state/startup-health}/$sid"
  [ -d "$d" ] || mkdir -p "$d" 2>/dev/null || return 1
  f="$d/proof.$name"
  # Every line is an `if`, never `[ ] && printf`: a false test as the group's LAST command would
  # make the whole write read as failed.
  {
    printf 'needle=%s\naction=%s\n' "$needle" "$action"
    if [ $# -ge 1 ]; then printf 'arg1=%s\n' "$1"; fi
    if [ $# -ge 2 ]; then printf 'arg2=%s\n' "$2"; fi
    if [ $# -ge 3 ]; then printf 'arg3=%s\n' "$3"; fi
    if [ -n "${SP_FALLBACK:-}" ]; then printf 'fallback=%s\n' "$SP_FALLBACK"; fi
  } > "$f.$$" 2>/dev/null && [ -s "$f.$$" ] && mv -f "$f.$$" "$f" 2>/dev/null && return 0
  rm -f "$f.$$" 2>/dev/null
  return 1
}
