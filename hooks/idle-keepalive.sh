#!/bin/bash
# idle-keepalive.sh — the idle-scoped prompt-cache keepalive for MAIN sessions, in SHADOW mode.
#
# Plan: docs/plans/USAGE_LEVERS.md § W3. It logs the moment it WOULD wake an idle session; it never
# wakes one. The switch-on decision is due after about 7 days of logs (bin/cc-idle-cache-readout).
#
# ── WHY A NEW TIMER, NOT A TWEAK TO THE EXISTING WAKE PATHS (reproduced in round 2, decision 3) ───
# A main session's cache lives 1 h, and the 3300 s wake that used to beat it no longer fires:
#   · hooks/session-continue.sh (wake_floor) stands its 3300 s floor DOWN whenever
#     mailbox-wake-arm.sh is registered on Stop with asyncRewake — which it is, on every account;
#   · that mechanical watcher runs `cc-await-ping --timeout 14340` and exits SILENTLY on timeout;
#   · and a keepalive bolted onto mailbox-wake-arm.sh does nothing, because its claim guard exits
#     when a watcher is already armed — and the watcher survives across turns (one ran 3h17m).
# So the keepalive must be its own hook, timed from the GAP START, not from whenever a watcher
# happened to be armed, and it must not care whether a watcher is armed. This file is that hook.
#
# ── WHAT IT DOES ─────────────────────────────────────────────────────────────────────────────────
# Registered on Stop with asyncRewake (migrations/0077), so the harness runs it in the background
# and does not reap it at the turn's end. At launch — the gap start — it notes the transcript size,
# then sleeps until gap start + CC_KEEPALIVE_WAKE_S (3300). If anything was appended to the
# transcript meanwhile, the gap is over and it exits (idle-scoped: one timer per gap, and a new
# Stop launches the next one). If the session is still idle, it writes a kind=wake row through
# hooks/lib/idle_gap.py — context size, and whether a mailbox watcher is armed right then — and
# exits 0. CC_KEEPALIVE_MAX_WAKES (1) bounds the wakes per gap ("about one wake per gap").
#
# SHADOW IS STRUCTURAL, NOT A FLAG. asyncRewake wakes the model only on exit 2, and the EXIT trap
# below forces 0 on every path; there is no wake branch to switch on. The kind=gap rows (gap
# length, the rebuild the next request actually paid) come from the SYNCHRONOUS Stop hook
# hooks/cache-expiry-tracker.sh, which is already registered, so the ledger runs before 0077 does.
#
# Kill switch: CC_IDLE_KEEPALIVE=off. Seams (tests): CC_IDLE_KEEPALIVE_HARNESS_ARGV /
# CC_IDLE_KEEPALIVE_HARNESS_FD1 (as mailbox-wake-arm.sh's), CC_IDLE_KEEPALIVE_SETTLE_S,
# CC_IDLE_KEEPALIVE_POLL_S, CC_KEEPALIVE_WAKE_S, CC_KEEPALIVE_MAX_WAKES. bash 3.2-safe.
set -uo pipefail
trap 'exit 0' EXIT

[ "${CC_IDLE_KEEPALIVE:-shadow}" = shadow ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

_stdin="$(cat 2>/dev/null || true)"

# ── HEADLESS GUARD — the same three oracles as hooks/mailbox-wake-arm.sh (read its header) ───────
# asyncRewake is dispatched SYNCHRONOUSLY in a non-interactive session, so a 55-minute timer would
# block a `claude -p` for 55 minutes. A one-shot has no idle gap to keep warm anyway.
if [ "${CC_IDLE_KEEPALIVE_HARNESS_ARGV+x}" = x ]; then
  _harness="$CC_IDLE_KEEPALIVE_HARNESS_ARGV"; _harness_pid=""
else
  _harness=""; _harness_pid=""; _anc="$PPID"; _hops=0
  while [ -n "$_anc" ] && [ "$_anc" != 1 ] && [ "$_hops" -lt 6 ]; do
    _cmdline="$(ps -o command= -p "$_anc" 2>/dev/null || true)"
    case "$_cmdline" in *claude*|*node*) _harness="$_cmdline"; _harness_pid="$_anc"; break ;; esac
    _anc="$(ps -o ppid= -p "$_anc" 2>/dev/null | tr -d ' ' || true)"
    _hops=$(( _hops + 1 ))
  done
fi
[ -n "$_harness" ] || exit 0
case "$_harness" in
  *--input-format*stream-json*) : ;;
  *)
    case " $_harness " in *" -p "*|*" --print "*) exit 0 ;; esac
    [ "${CLAUDE_CODE_ENTRYPOINT:-}" != sdk-cli ] || exit 0
    if [ "${CC_IDLE_KEEPALIVE_HARNESS_FD1+x}" = x ]; then
      _fd1="$CC_IDLE_KEEPALIVE_HARNESS_FD1"
    elif [ -n "$_harness_pid" ]; then
      _fd1="$(lsof -w -a -p "$_harness_pid" -d 1 -Fn 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
    else
      _fd1=""
    fi
    case "$_fd1" in /dev/tty*|/dev/pts/*) : ;; *) exit 0 ;; esac
    ;;
esac

_row="$(printf '%s' "$_stdin" | jq -r '[(.session_id // ""), (.transcript_path // "")] | join("\t")' 2>/dev/null)" || exit 0
_sid="${_row%%$'\t'*}"; _tp="${_row#*$'\t'}"
case "$_sid" in ''|*[!0-9A-Za-z-]*) exit 0 ;; esac
[ -f "$_tp" ] || exit 0

_lib="${BASH_SOURCE[0]%/*}/lib"
[ -f "$_lib/idle_gap.py" ] || exit 0

_num() { case "$1" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }
_wake_s="$(_num "${CC_KEEPALIVE_WAKE_S:-}" 3300)"
_max="$(_num "${CC_KEEPALIVE_MAX_WAKES:-}" 1)"
_settle="$(_num "${CC_IDLE_KEEPALIVE_SETTLE_S:-}" 20)"
_poll="$(_num "${CC_IDLE_KEEPALIVE_POLL_S:-}" 60)"
# Strictly under the registered hook timeout (0077 registers 14400), as mailbox-wake-arm.sh does.
_bound=14340

_launch="$(date +%s)"
# The Stop's own hooks append records for a moment after it fires; let them land before the
# snapshot, or the first poll would read them as a new turn and end every gap at once.
sleep "$_settle"
_size() { stat -f %z "$1" 2>/dev/null || stat -c %s "$1" 2>/dev/null || echo x; }
_size0="$(_size "$_tp")"

# Is a mailbox watcher armed right now? Recorded, never obeyed: coexistence is the point.
_watcher() {
  local _m="$_lib/mailbox-pending.sh" _k _pane
  [ -f "$_m" ] || { printf 'unknown'; return; }
  # shellcheck source=lib/mailbox-pending.sh
  # shellcheck disable=SC1091
  . "$_m" 2>/dev/null || { printf 'unknown'; return; }
  command -v mailbox_wake_armed >/dev/null 2>&1 || { printf 'unknown'; return; }
  _pane="${CC_PANE_ID:-${ITERM_SESSION_ID:-}}"; _pane="${_pane##*:}"
  for _k in $(mailbox_keyset "${_pane:-$_sid}" 2>/dev/null || printf '%s\n' "${_pane:-$_sid}"); do
    mailbox_wake_armed "$_k" && { printf 'true'; return; }
  done
  printf 'false'
}

_n=0
_due=$(( _launch + _wake_s ))
while [ "$_n" -lt "$_max" ]; do
  while :; do
    _now="$(date +%s)"
    [ "$_now" -lt "$_due" ] || break
    [ $(( _now - _launch )) -lt "$_bound" ] || exit 0
    _left=$(( _due - _now )); [ "$_left" -le "$_poll" ] || _left="$_poll"
    sleep "$_left"
    [ "$(_size "$_tp")" = "$_size0" ] || exit 0      # the gap ended: a new turn wrote the transcript
  done
  _n=$(( _n + 1 ))
  /usr/bin/env python3 -I "$_lib/idle_gap.py" would-wake "$_sid" "$_launch" "$(_watcher)" "$_n" \
    >/dev/null 2>&1 || true
  _due=$(( _due + _wake_s ))
done
exit 0
