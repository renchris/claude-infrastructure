#!/bin/bash
# page-damp.sh — SEND-side damping for automated pagers (v3 D7).
#
# The gap this closes: cc-inbox-guard damps ESCALATION per (uuid, acked:lines) and lead-supervisor
# damps per (sid, state), but NOTHING damped the SEND itself — so a producer that re-derives the same
# conclusion every sweep re-sends it every sweep. Live forensics 2026-07-20: 570 near-duplicate pages
# into ONE box, ~30 s apart, for three days. Damping is what makes an automated pager a *signal*
# rather than a stream.
#
#   damp_should_send <target> <state-fingerprint>   exit 0 = SEND (new or TTL-expired) · 1 = SUPPRESS
#
# CONTRACT — the fingerprint is the page's STATE, never its timestamp. A fingerprint that embeds a
# clock, a counter, an elapsed-time phrase or a pid changes every sweep and silently disables damping
# while looking wired (the failure mode this helper exists to prevent). Feed it the state + cause
# words: "DEAD:coordination-hang", "ESCALATED:stale-telemetry". A genuine state CHANGE ⇒ new
# fingerprint ⇒ sends immediately, which is the whole point: change is signal, repetition is noise.
#
# TTL (CC_PAGE_DAMP_TTL_S, default 1800) bounds the suppression so an UNCHANGED-but-still-true
# condition re-surfaces about twice an hour rather than never — a page that stops re-asserting is
# indistinguishable from a resolved one.
#
# Marker: <dir>/<sanitized-target>.<sanitized-fingerprint> holding the epoch of the last send.
# FAIL-OPEN by construction: an unwritable/unreadable marker dir ⇒ SEND. A damping layer must never
# be the reason a page is lost — the worst case of fail-open is the noise we already had.
#
# Env: CC_PAGE_DAMP_DIR (default ~/.claude/autonomy/pages/damp) · CC_PAGE_DAMP_TTL_S (1800).
# bash 3.2-safe. No `set -e`. Sourced by bin/cc-reaper + scripts/lead-supervisor.sh.

_damp_dir() { printf '%s' "${CC_PAGE_DAMP_DIR:-$HOME/.claude/autonomy/pages/damp}"; }
_damp_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'; }   # marker-filename-safe

damp_should_send() { # <target> <state-fingerprint> → 0 send, 1 suppress
  local target="${1:-}" fp="${2:-}" dir mk last now ttl="${CC_PAGE_DAMP_TTL_S:-1800}"
  [ -n "$target" ] && [ -n "$fp" ] || return 0        # nothing to key on → fail OPEN
  case "$ttl" in ''|*[!0-9]*) ttl=1800 ;; esac
  dir="$(_damp_dir)"
  mkdir -p "$dir" 2>/dev/null || return 0             # unwritable → fail OPEN
  mk="$dir/$(_damp_key "$target").$(_damp_key "$fp")"
  now="$(date +%s 2>/dev/null || echo 0)"
  case "$now" in ''|*[!0-9]*) now=0 ;; esac
  if [ -f "$mk" ]; then
    last="$(head -n1 "$mk" 2>/dev/null | tr -dc '0-9')"
    case "$last" in ''|*[!0-9]*) last=0 ;; esac
    # Inside the TTL AND the same fingerprint ⇒ this is a repeat of a page already sent. Suppress.
    # A clock that jumped backwards (now < last) reads as "not yet expired" — harmless, self-corrects.
    [ "$(( now - last ))" -lt "$ttl" ] 2>/dev/null && return 1
  fi
  printf '%s\n' "$now" > "$mk" 2>/dev/null || true    # record-fail → still SEND (fail-open)
  return 0
}
