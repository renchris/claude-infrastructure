# shellcheck shell=bash
# startup-sentinel.sh — start/done markers for this repo's own SYNC SessionStart hooks (sourced; bash 3.2).
#
# WHY. Claude Code 2.1.293 renders nothing when it cancels a SessionStart hook, and a cancelled hook's
# stdout is discarded whole (docs/research/startup-hooks-2026-10-18/README.md §1 item 3, §3 D1/D20).
# Before the first prompt there is no transcript to read either, so these markers are the only signal
# that a start lost something: a `.start` with no `.done`, a `.done` with rc ≠ 0, or a `.done` that
# finished at its timeout with output owed. hooks/session-beat.sh reads them at the first prompt and
# confirms or clears each from the transcript, which is the authority (README §5 unit 3.4). A `.done`
# with rc 0 does NOT prove delivery: the harness discards output from hooks that finish inside its lag
# (gap-G3 F3) — that is why the reader never trusts it alone.
#
# Usage, right after the hook knows its session id:
#   . "<dir>/lib/startup-sentinel.sh" && ss_begin <hook> <timeout_ms> <sid> [<transcript_path>]
#   ss_owed <bytes>         # just before printing (the byte count of what the hook prints)
# ss_begin arms `trap 'ss_end $?' EXIT` and `trap 'exit 143' TERM`. A hook that owns its own EXIT trap
# passes --no-trap first and calls `ss_end "$rc"` from that trap itself.
#
# Files ("$R/<sid>/", R=${CC_STARTUP_HEALTH_DIR:-$HOME/.claude/state/startup-health}):
#   <hook>.start   empty; its MTIME is the start time (a builtin `: >` — no clock fork)
#   <hook>.done    rc=, elapsed_s= ($SECONDS: since the hook's shell started), owed=, timeout_ms=
#                  one printf, so one write(2): a reader never sees half a record
#   session.start  transcript_path=, size= — first writer per session only (noclobber)
# A SIGKILL leaves `.start` without `.done`, which still reads as a possible loss.
# Hot path is builtins only, plus one `mkdir -p` per session and, for its first writer, one `stat`.
#
# Kill switch: CC_STARTUP_SENTINEL=0.

ss_begin() {
  _SS_ON=0
  [ "${CC_STARTUP_SENTINEL:-1}" = 0 ] && return 0
  local _notrap=0
  [ "${1:-}" = --no-trap ] && { _notrap=1; shift; }
  _SS_HOOK="${1:-}"; _SS_TMO="${2:-5000}"
  local _sid="${3:-}" _tp="${4:-}" _sz=0 _opts
  case "$_SS_HOOK" in ''|*[!0-9A-Za-z_-]*) return 0 ;; esac
  case "$_sid" in ''|*[!0-9A-Za-z-]*) return 0 ;; esac
  case "$_SS_TMO" in ''|*[!0-9]*) _SS_TMO=5000 ;; esac
  _SS_DIR="${CC_STARTUP_HEALTH_DIR:-$HOME/.claude/state/startup-health}/$_sid"
  [ -d "$_SS_DIR" ] || mkdir -p "$_SS_DIR" 2>/dev/null || return 0
  : > "$_SS_DIR/$_SS_HOOK.start" 2>/dev/null || return 0
  if [ ! -e "$_SS_DIR/session.start" ]; then
    [ -n "$_tp" ] && [ -f "$_tp" ] && _sz="$(stat -f %z "$_tp" 2>/dev/null || echo 0)"
    _opts="$-"; set -C
    printf 'transcript_path=%s\nsize=%s\n' "$_tp" "$_sz" > "$_SS_DIR/session.start" 2>/dev/null || true
    case "$_opts" in *C*) ;; *) set +C ;; esac
  fi
  _SS_OWED=0; _SS_ON=1
  if [ "$_notrap" = 0 ]; then
    trap 'ss_end $?' EXIT
    trap 'exit 143' TERM
  fi
  return 0
}

ss_owed() { case "${1:-}" in ''|*[!0-9]*) ;; *) _SS_OWED="$1" ;; esac; }

ss_end() {
  local _rc="${1:-0}"
  [ "${_SS_ON:-0}" = 1 ] || return 0
  _SS_ON=0
  printf 'rc=%s\nelapsed_s=%s\nowed=%s\ntimeout_ms=%s\n' "$_rc" "$SECONDS" "${_SS_OWED:-0}" "$_SS_TMO" \
    > "$_SS_DIR/$_SS_HOOK.done" 2>/dev/null || true
  return 0
}
