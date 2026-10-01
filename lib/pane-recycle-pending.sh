# shellcheck shell=bash
# pane-recycle-pending.sh — is a recycle in flight for this pane? Sourced; bash 3.2 / zsh portable.
#
# WHY THIS EXISTS (docs/research/husk-panes-2026-09-30.md, root cause 2 / fix F-a). A pane whose
# claude exited on purpose now closes FROM INSIDE (bin/cc-pane-runner, and opt-in bin/cc-close-attrib)
# instead of waiting on a kitty remote-control close that may never land. A RECYCLE also ends in a
# clean claude exit — handoff-fire types /exit and then types the relaunch at the shell — so the shell
# must survive exactly then. handoff-fire marks that window with its per-pane recycle lock
# (scripts/handoff-fire.sh hf_recycle_lock_dir / _hf_lock_holder_alive), taken BEFORE it types /exit
# and released by its watcher after the relaunch is typed. This file reads that marker; it never
# writes, takes or breaks it. ONE copy, so the two closers cannot disagree about what "pending" means.
#
# THE KEY IS AMBIGUOUS FROM THIS SIDE. The recycler hashes "${CC_TERM_KITTY_TO:-iterm2}:<pane>", and
# the value it had is not knowable here: it may have run with no CC_TERM_KITTY_TO ("iterm2:<id>"), or
# with the socket spelled either with or without kitty's `unix:` scheme. Every candidate is checked,
# and any one of them pending is enough.
#
# FAILS SAFE, which here means KEEP THE SHELL. Closing a pane mid-recycle strands the relaunch with no
# prompt to land in, and that is unrecoverable; keeping a shell that should have closed costs one husk.
# So: no pane id, no shasum, a lock dir whose holder is missing or unparseable (the recycler mkdirs
# the dir and writes the holder a moment later), or a holder pid that exists but whose start time
# cannot be read — all read as PENDING. Only a holder that is provably dead (pid gone, or pid reused:
# lstart differs) is not. That is deliberately STRICTER than handoff-fire's own reading, which treats
# an unparseable holder as not-alive so a broken lock cannot wedge the recycler forever; a closer that
# reads it as pending only leaves a husk.

cc_pane_recycle_pending() { # $1=pane id → rc 0 = a recycle may be pending (keep the shell), 1 = provably none
  local _id="${1:-}" _locks _lo _key _sum _dir _raw _pid _hl _cur
  [ -n "$_id" ] || return 0
  command -v shasum >/dev/null 2>&1 || return 0
  _locks="${LR_LOCKS_DIR:-${HOME:-}/.reso/limit-recover/locks}"
  _lo="${KITTY_LISTEN_ON:-}"
  for _key in iterm2 "${CC_TERM_KITTY_TO:-}" "$_lo" "${_lo#unix:}"; do
    [ -n "$_key" ] || continue
    _sum="$(printf '%s' "$_key:$_id" | shasum -a 1 2>/dev/null | cut -c1-40)"
    [ -n "$_sum" ] || return 0
    _dir="$_locks/pane-$_sum.recycle"
    [ -d "$_dir" ] || continue
    [ -f "$_dir/holder" ] || return 0
    _raw="$(tr -d '\r\n' < "$_dir/holder" 2>/dev/null)"
    _pid="$(printf '%s' "$_raw" | sed -n 's/.*"pid":\([0-9][0-9]*\)[,}].*/\1/p')"
    _hl="$(printf '%s' "$_raw" | sed -n 's/.*"lstart":"\([^"]*\)".*/\1/p' | tr -s ' ')"
    case "$_pid" in ''|*[!0-9]*|0) return 0 ;; esac
    [ -n "$_hl" ] || return 0
    _cur="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$_pid" 2>/dev/null | tr -s ' ' | sed 's/^ *//; s/ *$//')"
    if [ -z "$_cur" ]; then
      # No start time: either the pid is gone (dead holder) or ps itself failed. Only the first is
      # proof of death, so ask the kernel directly before believing it.
      kill -0 "$_pid" 2>/dev/null && return 0
      continue
    fi
    [ "$_cur" = "$_hl" ] && return 0
  done
  return 1
}
