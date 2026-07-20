#!/bin/bash
# mailbox-pending.sh — inbox-cursor primitives for the v2 non-keystroke comms channel.
#
# TWO cursors, one truth (critique fix A — split delivery from ack so the fail-loud guard can SEE a loss
# the delivery cursor would hide):
#   <uuid>.seen   EMITTED  — the drain/fold has SURFACED lines up to here (don't re-deliver / re-block).
#                            Shared with handoff-disposition.sh (mailbox_pending) + its --ack.
#   <uuid>.acked  CONSUMED — the model PROVABLY took a turn carrying these (reliable channels advance it
#                            immediately; the Stop-fold lags one cycle). cc-inbox-guard alarms on
#                            acked < EOF — NEVER on the eager `seen` — so a dropped/undrained line is loud.
#   acked ≤ seen ≤ lines is the invariant (both clamped on read).
#
# The inbox <uuid>.md is append-only (cc-notify), one message per line "<ISO> [<from>] <message>".
# Line count is grep -c '' EVERYWHERE (matches handoff-disposition; wc -l diverges on a non-newline-
# terminated final line — a torn concurrent append — so never mix the two: critique F1).
#
# Atomicity (critique F1 — the desk is a HOT target: reaper/supervisor/any peer append at any instant):
# every cursor read-modify-write runs under a portable mkdir lock (macOS has no flock). mailbox_take
# snapshots the window AND advances under ONE lock hold, so a concurrent append is never marked seen
# without being delivered. The lock self-breaks if stale (holder died) and gives up after ~2s degrading
# to lock-free (risking a benign DUP, never a hang — a hook must never block).
#
# Functions (fail-safe: bad uuid / missing dir → "nothing", never an error):
#   mailbox_lines  <uuid>            current line count (grep -c '')
#   mailbox_seen   <uuid>            emitted cursor, clamped [0, lines]  (past-EOF ⇒ 0: re-deliver, F11)
#   mailbox_acked  <uuid>            consumed cursor, clamped [0, seen]
#   mailbox_pending_count  <uuid>    lines - seen   (undrained — the drain/fold signal)
#   mailbox_unacked_count  <uuid>    lines - acked  (unconsumed — the GUARD signal)
#   mailbox_has_pending    <uuid>    exit 0 iff pending_count > 0
#   mailbox_take <uuid> [ack_now]    LOCKED: print lines (seen, EOF] to stdout; advance seen=EOF; if
#                                    ack_now=1 also acked=EOF. Return 0 = delivered+committed · 1 = nothing
#                                    new (no body) · 2 = body printed but the cursor WRITE FAILED — the
#                                    caller must escalate + still deliver, never silently drop (F9).
#   mailbox_promote_acked  <uuid>    LOCKED: acked=seen (the Stop-fold lag: last cycle's emitted is now consumed)
#
# Env: CC_MAILBOX_DIR (default ~/.claude/mailbox) · CC_MBX_LOCK_WAIT_MS (2000) · CC_MBX_LOCK_STALE_S (10).
# bash 3.2-safe. No `set -e`.

_mbx_dir() { printf '%s' "${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"; }
_mbx_valid_uuid() { case "${1:-}" in ''|*[!0-9A-Fa-f-]*) return 1 ;; *) return 0 ;; esac; }
mailbox_file() { printf '%s/%s.md' "$(_mbx_dir)" "${1:-}"; }
_mbx_int() { case "${1:-}" in ''|*[!0-9]*) echo 0 ;; *) echo "$1" ;; esac; }

# ── portable mkdir lock (macOS-safe; flock is Linux-only) ─────────────────────────────────────────
_mbx_lock() { # <uuid> → 0 acquired, 1 gave up (caller proceeds lock-free: dup-risk, never a hang)
  local u="$1" ld waited=0 step=50 max="${CC_MBX_LOCK_WAIT_MS:-2000}" stale="${CC_MBX_LOCK_STALE_S:-10}"
  mkdir -p "$(_mbx_dir)" 2>/dev/null || return 1
  ld="$(_mbx_dir)/.$u.lock"
  while ! mkdir "$ld" 2>/dev/null; do
    local mt now age; mt="$(stat -f %m "$ld" 2>/dev/null || stat -c %Y "$ld" 2>/dev/null || echo 0)"
    now="$(date +%s 2>/dev/null || echo 0)"; age=$(( now - $(_mbx_int "$mt") ))
    [ "$age" -ge "$stale" ] 2>/dev/null && { rm -rf "$ld" 2>/dev/null; continue; }   # holder died → break
    [ "$waited" -ge "$max" ] && return 1
    sleep 0.05 2>/dev/null || sleep 1; waited=$(( waited + step ))
  done
  return 0
}
_mbx_unlock() { rm -rf "$(_mbx_dir)/.${1:-}.lock" 2>/dev/null || true; }

_mbx_read_int_file() { local f="$1" v=0; [ -f "$f" ] && v="$(head -n1 "$f" 2>/dev/null | tr -dc '0-9')"; _mbx_int "$v"; }
# atomic write; echoes nothing, returns 1 on failure (F9 — the caller must be able to SEE a write fail).
_mbx_write_int() {
  local f="$1" n="$2" dir tmp; dir="$(dirname "$f")"
  mkdir -p "$dir" 2>/dev/null || return 1
  tmp="$dir/.$(basename "$f").$$.tmp"
  printf '%s\n' "$n" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$f" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

mailbox_lines() {
  local u="${1:-}" f n
  _mbx_valid_uuid "$u" || { echo 0; return; }
  f="$(mailbox_file "$u")"; [ -f "$f" ] || { echo 0; return; }
  n="$(grep -c '' "$f" 2>/dev/null)"; _mbx_int "$n"
}

mailbox_seen() { # emitted cursor, clamped [0, lines]; a cursor PAST EOF (rotate/GC/recycle) ⇒ 0 (re-deliver, F11)
  local u="${1:-}" p lines
  _mbx_valid_uuid "$u" || { echo 0; return; }
  p="$(_mbx_read_int_file "$(_mbx_dir)/$u.seen")"; lines="$(mailbox_lines "$u")"
  [ "$p" -gt "$lines" ] 2>/dev/null && p=0
  echo "$p"
}

mailbox_acked() { # consumed cursor, clamped [0, seen]
  local u="${1:-}" a seen
  _mbx_valid_uuid "$u" || { echo 0; return; }
  a="$(_mbx_read_int_file "$(_mbx_dir)/$u.acked")"; seen="$(mailbox_seen "$u")"
  [ "$a" -gt "$seen" ] 2>/dev/null && a="$seen"
  echo "$a"
}

mailbox_pending_count() { local d=$(( $(mailbox_lines "${1:-}") - $(mailbox_seen "${1:-}") )); [ "$d" -lt 0 ] && d=0; echo "$d"; }
mailbox_unacked_count() { local d=$(( $(mailbox_lines "${1:-}") - $(mailbox_acked "${1:-}") )); [ "$d" -lt 0 ] && d=0; echo "$d"; }
mailbox_has_pending()   { [ "$(mailbox_pending_count "${1:-}")" -gt 0 ]; }

# LOCKED atomic take: snapshot the window (seen, EOF], print it, advance seen=EOF (never regress), and —
# for a reliable channel — acked=EOF too. Emitting is the CALLER's job (it wraps the body in JSON); the
# guard's acked cursor is what makes a post-print emit-failure loud, so advancing seen inside the lock is
# safe (F1 atomicity) without needing emit-before-advance for the reliable path. Returns 1 if the seen
# write FAILED (F9): the caller must escalate, not re-loop on the same mail.
mailbox_take() { # <uuid> [ack_now]  (ack_now=1 ⇒ reliable channel: advance acked too)
  local u="${1:-}" ack_now="${2:-0}" f prev cur body rc=0
  _mbx_valid_uuid "$u" || return 1
  f="$(mailbox_file "$u")"
  _mbx_lock "$u" || true                       # gave up ⇒ proceed lock-free (dup-risk, never a hang)
  prev="$(mailbox_seen "$u")"; cur="$(mailbox_lines "$u")"
  if [ "$cur" -le "$prev" ]; then _mbx_unlock "$u"; return 1; fi   # nothing new
  body="$(tail -n +"$((prev + 1))" "$f" 2>/dev/null | head -n "$(( cur - prev ))")"
  printf '%s' "$body"
  if ! _mbx_write_int "$(_mbx_dir)/$u.seen" "$cur"; then rc=2; fi   # F9: body printed, cursor write FAILED
  [ "$ack_now" = 1 ] && [ "$rc" = 0 ] && _mbx_write_int "$(_mbx_dir)/$u.acked" "$cur"
  _mbx_unlock "$u"
  return "$rc"
}

mailbox_promote_acked() { # <uuid> — the Stop-fold lag: everything emitted last cycle is now consumed (a turn ran)
  local u="${1:-}" seen
  _mbx_valid_uuid "$u" || return 0
  _mbx_lock "$u" || true
  seen="$(mailbox_seen "$u")"
  _mbx_write_int "$(_mbx_dir)/$u.acked" "$seen" || true
  _mbx_unlock "$u"
}
