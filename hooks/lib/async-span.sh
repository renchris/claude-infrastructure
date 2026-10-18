# shellcheck shell=bash
# async-span.sh — START/END IDL rows for an ASYNC hook (sourced; bash 3.2; no forks on the write path).
#
# WHY. An async hook has no operator-visible channel: its stderr is never rendered and never sent to
# the model (53 records in 48 h, 0 shown — docs/research/startup-hooks-2026-10-18/A5-silent-drops.md
# F8), and a harness kill at its timeout leaves no record of any kind. One `started` row at entry and
# one `passed`/`failed exit:<rc>` row at exit make both visible in the IDL: a `started` row with no
# end row for the same pid is a kill (or a SIGKILL'd errexit), countable per hook.
#
# Usage, near the top of the hook, AFTER any `set -e` and BEFORE any early exit:
#   . "<dir>/lib/async-span.sh" && async_span_begin <hook-name> [<sid>]
# It arms `trap … EXIT` and `trap 'exit 143' TERM`, so a hook that already owns an EXIT trap must not
# use it. Fail-open: a missing idl-log.sh or an unwritable IDL makes it a no-op.
#
# Kill switch: CC_ASYNC_SPAN=0.

async_span_begin() {
  [ "${CC_ASYNC_SPAN:-1}" = 0 ] && return 0
  local _lib="${BASH_SOURCE[0]%/*}/idl-log.sh"
  [ -r "$_lib" ] || return 0
  # shellcheck source=idl-log.sh disable=SC1091  # runtime-resolved beside this file
  . "$_lib" || return 0
  _ASPAN_SID="${2:-?}"
  case "$_ASPAN_SID" in ''|*[!0-9A-Za-z-]*) _ASPAN_SID='?' ;; esac
  idl_init "${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}" "$1" _ASPAN_SID
  log_idl_fixed started "pid:$$"
  # shellcheck disable=SC2154  # _aspan_rc is assigned inside the trap string itself
  trap '_aspan_rc=$?; if [ "$_aspan_rc" -eq 0 ]; then log_idl_fixed passed "exit:0_pid:$$"; else log_idl_fixed failed "exit:${_aspan_rc}_pid:$$"; fi' EXIT
  trap 'exit 143' TERM
}
