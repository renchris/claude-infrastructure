#!/usr/bin/env bash
# restore-lock.sh — the one-restore-at-a-time lock for the session restore (W3 P2, 2026-10-04).
#
# WHY: a restore relaunches every pane of the fleet. Two of them at once (the launchd boot path and
# a hand-run `cc-restore`, or a retry fired while the first still runs) would each launch the same
# sessions, and the per-session fence in reso-resume-one only stops the second launch of a sid that
# already has a live holder; it cannot stop two restores from laying out two sets of windows. So a
# restore takes ONE global lock first, and claims its event so a crashed run is visible afterwards.
#
#   restore_lock_take <event-id>       rc 0 taken · 1 held by a live restore · 2 cannot · 3 event done
#   restore_lock_release [done]        rc 0 released · 1 not ours (or not held)
#   restore_refuse_under_bats [what]   rc 0 REFUSE (a bats harness is present) · 1 proceed
#
# The lock is `mkdir <state>/restore.lock`, with a holder file stamped with the pid, its lstart and
# the boot uuid (`kern.bootsessionuuid`, never kern.boottime, which moves on an NTP step). A holder is
# STALE, and its lock is reclaimed, when any of the three no longer matches: another boot, a dead
# pid, or a live pid with a different start time (pids are reused). A lock dir whose holder file is
# missing or unreadable is a taker mid-write for RESTORE_LOCK_GRACE_S (10) seconds and stale after.
# The claim is `<state>/events/<id>.inprogress`, carrying the same stamp. `release done` renames it to
# `<id>.done`; a plain release removes it. A claim left behind by a dead holder is evidence of a
# crashed restore and is overwritten by the next taker of that event.
#
# restore_refuse_under_bats exists because a test once reached the live kitty (1deb094d2): the case
# set only some of boot-resume's seams, and the unset ones resolved to the real layout script and
# the operator's real roster. Any restore code about to SIGNAL or drive a real process asks it first
# and stands down when a bats harness is present. It reads the same three variables as
# scripts/handoff-fire.sh's `_under_test` and has no bypass: a test of a signalling path stubs the
# signaller instead.
#
# /bin/bash 3.2 safe (launchd runs the restore under it). Sourced: defines functions only.
# Seams: RESTORE_STATE_DIR (default ${CC_BOOT_RESUME_STATE_DIR:-$HOME/.claude/autonomy/boot-resume}),
# RESTORE_LOCK_BOOT_UUID, RESTORE_LOCK_PS_BIN, RESTORE_LOCK_GRACE_S.

_restore_lock_state_dir() {
  printf '%s' "${RESTORE_STATE_DIR:-${CC_BOOT_RESUME_STATE_DIR:-$HOME/.claude/autonomy/boot-resume}}"
}

_restore_lock_boot_uuid() {
  if [ -n "${RESTORE_LOCK_BOOT_UUID:-}" ]; then printf '%s' "$RESTORE_LOCK_BOOT_UUID"; return 0; fi
  /usr/sbin/sysctl -n kern.bootsessionuuid 2>/dev/null | tr -d '[:space:]'
}

# LSTART under TZ=UTC LC_ALL=C, runs of spaces collapsed and trimmed — the form lr-recon-fence.sh
# stamps, so the two locks read a process the same way. Empty when the pid is gone.
_restore_lock_lstart_of() {
  TZ=UTC LC_ALL=C "${RESTORE_LOCK_PS_BIN:-/bin/ps}" -o lstart= -p "$1" 2>/dev/null \
    | tr -s ' ' | sed -e 's/^ //' -e 's/ $//'
}

_restore_lock_field() { # <compact json> <key> → the value of a "key":"v" or "key":N pair
  printf '%s' "$1" | sed -n -e "s/.*\"$2\":\"\\([^\"]*\\)\".*/\\1/p" -e "t" -e "s/.*\"$2\":\\([0-9][0-9]*\\).*/\\1/p" | head -1
}

_restore_lock_stamp() { # <event-id> <pid> → the holder json on stdout; rc 1 when it cannot be stamped
  local ls boot
  ls="$(_restore_lock_lstart_of "$2")"
  boot="$(_restore_lock_boot_uuid)"
  [ -n "$ls" ] && [ -n "$boot" ] || return 1
  printf '{"event":"%s","pid":%s,"lstart":"%s","boot":"%s","at":%s}\n' "$1" "$2" "$ls" "$boot" "$(date +%s)"
}

# rc 0 when the holder in <lockdir> is STALE (reclaimable), 1 when it is live or too young to judge.
_restore_lock_stale() {
  local dir="$1" raw pid ls boot age grace
  raw="$(cat "$dir/holder" 2>/dev/null)"
  pid="$(_restore_lock_field "$raw" pid)"
  ls="$(_restore_lock_field "$raw" lstart)"
  boot="$(_restore_lock_field "$raw" boot)"
  if [ -z "$pid" ] || [ -z "$ls" ] || [ -z "$boot" ]; then
    grace="${RESTORE_LOCK_GRACE_S:-10}"
    case "$grace" in ''|*[!0-9]*) grace=10 ;; esac
    age=$(( $(date +%s) - $(stat -f %m "$dir" 2>/dev/null || date +%s) ))
    [ "$age" -gt "$grace" ]
    return
  fi
  [ "$boot" != "$(_restore_lock_boot_uuid)" ] && return 0
  kill -0 "$pid" 2>/dev/null || return 0
  [ "$ls" != "$(_restore_lock_lstart_of "$pid")" ]
}

restore_lock_take() {
  local id="${1:-}" pid="$$" state lock ev stamp tomb raw try=0
  case "$id" in ''|*/*|.*) return 2 ;; esac
  case "$id" in *[!A-Za-z0-9._:-]*) return 2 ;; esac
  state="$(_restore_lock_state_dir)"; lock="$state/restore.lock"; ev="$state/events"
  mkdir -p "$ev" 2>/dev/null || return 2
  [ -e "$ev/$id.done" ] && return 3
  stamp="$(_restore_lock_stamp "$id" "$pid")" || return 2
  while [ "$try" -lt 3 ]; do
    try=$((try + 1))
    if mkdir "$lock" 2>/dev/null; then
      if printf '%s\n' "$stamp" > "$lock/holder.tmp.$$" 2>/dev/null && mv -f "$lock/holder.tmp.$$" "$lock/holder" 2>/dev/null \
         && printf '%s\n' "$stamp" > "$ev/$id.inprogress.tmp.$$" 2>/dev/null \
         && mv -f "$ev/$id.inprogress.tmp.$$" "$ev/$id.inprogress" 2>/dev/null; then
        _RESTORE_LOCK_EVENT="$id"
        return 0
      fi
      rm -rf "$lock" "$ev/$id.inprogress.tmp.$$" 2>/dev/null
      return 2
    fi
    [ -d "$lock" ] || return 2
    _restore_lock_stale "$lock" || return 1
    # Steal by rename, then make sure the tomb holds the holder we judged stale; a different one means
    # a racing taker got there first, and its lock goes back.
    raw="$(cat "$lock/holder" 2>/dev/null)"
    tomb="$lock.stale.$$.$RANDOM"
    mv "$lock" "$tomb" 2>/dev/null || continue
    if [ "$(cat "$tomb/holder" 2>/dev/null)" != "$raw" ]; then
      [ -e "$lock" ] || mv "$tomb" "$lock" 2>/dev/null
      return 1
    fi
    rm -rf "$tomb"
  done
  return 1
}

restore_lock_release() {
  local mode="${1:-}" state lock ev raw id
  state="$(_restore_lock_state_dir)"; lock="$state/restore.lock"; ev="$state/events"
  [ -d "$lock" ] || return 1
  raw="$(cat "$lock/holder" 2>/dev/null)"
  [ "$(_restore_lock_field "$raw" pid)" = "$$" ] || return 1
  [ "$(_restore_lock_field "$raw" lstart)" = "$(_restore_lock_lstart_of "$$")" ] || return 1
  id="${_RESTORE_LOCK_EVENT:-$(_restore_lock_field "$raw" event)}"
  if [ -n "$id" ] && [ -f "$ev/$id.inprogress" ]; then
    if [ "$mode" = "done" ]; then
      mv -f "$ev/$id.inprogress" "$ev/$id.done" 2>/dev/null
    else
      rm -f "$ev/$id.inprogress" 2>/dev/null
    fi
  fi
  rm -rf "$lock"
  _RESTORE_LOCK_EVENT=""
  return 0
}

restore_refuse_under_bats() {
  if [ -n "${BATS_TEST_FILENAME:-}${BATS_TEST_TMPDIR:-}${BATS_VERSION:-}" ]; then
    printf 'restore-lock: REFUSED under a bats harness: %s\n' "${1:-a signal to a live process}" >&2
    return 0
  fi
  return 1
}
