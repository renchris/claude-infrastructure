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
# ── FORWARD CHAINS (v3 D1 — succession must not strand an inbox) ──────────────────────────────────
# The mailbox is PANE-UUID-keyed, so a recycle/succession orphans the predecessor's box: live forensics
# 2026-07-20 found 631/206/155-line former-desk boxes, every line permanently unread, because producers
# kept paging a UUID whose pane was gone (research doc §2 — "root cause is addressing, not transport").
# A `<old-uuid>.forward` file holding the successor UUID makes the box a POINTER, so:
#   • SEND side  — cc-notify follows the chain BEFORE enqueue, so a stale address still lands live.
#   • DRAIN side — the successor ADOPTS the predecessor's undelivered tail exactly once (migration).
# Both are bounded (MAX_HOPS) and cycle-safe (visited set): a forward loop must degrade to "deliver to
# where I got stuck", never spin a hook. A `.forward` is also the D6 tombstone — archive preserves it.
#
#   mailbox_forward_of   <uuid>       resolve the chain HEAD (echo the terminal uuid; echoes <uuid>
#                                     itself when there is no forward). Bounded 4 hops, cycle-safe.
#   mailbox_write_forward <old> <new> atomic tmp+mv pointer write. Refuses a self-forward.
#   mailbox_migrate <old> <new>       LOCKED (both boxes): append old's UNCONSUMED (acked, EOF] lines to
#                                     new's inbox with a provenance prefix, then advance BOTH of old's
#                                     cursors to EOF. Exactly-once by construction — the cursor advance
#                                     is what makes a second call a no-op (idempotent, safe to re-run
#                                     on every SessionStart).
#
# Env: CC_MAILBOX_DIR (default ~/.claude/mailbox) · CC_MBX_LOCK_WAIT_MS (2000) · CC_MBX_LOCK_STALE_S (10)
#      · CC_MBX_FORWARD_MAX_HOPS (4).
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

# ── FORWARD CHAINS + SUCCESSION MIGRATION (v3 D1) ────────────────────────────────────────────────
_mbx_fwd_file() { printf '%s/%s.forward' "$(_mbx_dir)" "${1:-}"; }

# STRICT canonical 8-4-4-4-12 check — deliberately stricter than _mbx_valid_uuid (which is permissive
# "hex-and-dashes" by design, so the read primitives stay fail-safe on odd input). A forward pointer is
# an ADDRESS: combined with the `tr -dc` sanitiser, permissive validation turns a corrupt pointer like
# "not-a-uuid!!" into the plausible-looking "-a-" and would route real mail into a garbage box. A
# pointer is only ever written by mailbox_write_forward, so anything non-canonical IS corruption —
# refuse to write it, and ignore it on read (stopping at the last good hop).
_mbx_strict_uuid() {
  case "${1:-}" in
    [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]-[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) return 0 ;;
    *) return 1 ;;
  esac
}

# Resolve a forward chain to its HEAD. Echoes the TERMINAL uuid — which is the input uuid when there is
# no forward — so every caller can pipe through this unconditionally with no "does a forward exist?"
# branch. Bounded (CC_MBX_FORWARD_MAX_HOPS, default 4) and cycle-safe (visited set): a loop, an
# over-long chain, or a junk pointer STOPS at the last good hop and delivers there. A hook must degrade
# to a slightly-stale address, never spin.
# Exit: 0 = resolved (head echoed) · 1 = invalid input uuid (echoed back verbatim, caller decides).
mailbox_forward_of() {
  local u="${1:-}" max="${CC_MBX_FORWARD_MAX_HOPS:-4}" hops=0 visited nxt
  _mbx_valid_uuid "$u" || { printf '%s' "$u"; return 1; }
  case "$max" in ''|*[!0-9]*) max=4 ;; esac
  visited=" $u "
  while [ "$hops" -lt "$max" ]; do
    nxt="$(head -n1 "$(_mbx_fwd_file "$u")" 2>/dev/null | tr -dc '0-9A-Fa-f-')"
    [ -n "$nxt" ] || break                            # no pointer → u IS the head
    _mbx_strict_uuid "$nxt" || break                  # junk/corrupt pointer → stop at the last good hop
    case "$visited" in *" $nxt "*) break ;; esac      # CYCLE → stop (never spin)
    visited="$visited$nxt "
    u="$nxt"; hops=$(( hops + 1 ))
  done
  printf '%s' "$u"
  return 0
}

# Point <old>'s box at <new> (atomic tmp+mv, like every other cursor write here). A SELF-forward is
# refused: it would make mailbox_forward_of a silent no-op and hide a real succession bug behind a
# pointer that looks wired.
mailbox_write_forward() { # <old> <new>
  local old="${1:-}" new="${2:-}" dir tmp
  # never persist a non-canonical address (explicit if, not `A && B || C` — same reason as migrate's)
  if ! _mbx_strict_uuid "$old" || ! _mbx_strict_uuid "$new"; then return 1; fi
  [ "$old" = "$new" ] && return 1
  dir="$(_mbx_dir)"; mkdir -p "$dir" 2>/dev/null || return 1
  tmp="$dir/.$old.forward.$$.tmp"
  printf '%s\n' "$new" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  mv -f "$tmp" "$(_mbx_fwd_file "$old")" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; return 1; }
  return 0
}

# Adopt <old>'s UNCONSUMED tail into <new>: append old's (acked, EOF] lines to new's inbox with a
# provenance prefix, then advance old's cursors past what actually landed. Echoes the migrated count.
#
# Why (acked, EOF] and not (seen, EOF] — `.seen` is EAGER (emitted); `.acked` is PROVEN-consumed, and
# it is the cursor the fail-loud guard keys on. Migrating from `acked` can therefore re-deliver a line
# the dying session was shown but never provably took. That direction is deliberate: a dup is visible
# and harmless, a drop is invisible and permanent (same reasoning as the F11 past-EOF re-deliver).
#
# EXACTLY-ONCE is the cursor advance, so this is safe to re-run on every SessionStart: a second call
# reads acked == EOF, finds nothing unconsumed, and no-ops.
# Exit: 0 = migrated ≥1 · 1 = nothing to migrate (incl. bad/equal uuids, missing box) · 2 = PARTIAL —
# some lines landed, then a write failed; old's cursors were advanced by exactly what landed, so the
# next call resumes at the right line (no loss, no dup).
mailbox_migrate() { # <old> <new>
  local old="${1:-}" new="${2:-}" f_old f_new a cur body lo hi ts pfx ln migrated=0 rc=0 cursor
  if ! _mbx_valid_uuid "$old" || ! _mbx_valid_uuid "$new"; then echo 0; return 1; fi
  [ "$old" = "$new" ] && { echo 0; return 1; }
  f_old="$(mailbox_file "$old")"; f_new="$(mailbox_file "$new")"
  [ -f "$f_old" ] || { echo 0; return 1; }
  mkdir -p "$(_mbx_dir)" 2>/dev/null || { echo 0; return 1; }

  # DEADLOCK-FREE two-box locking: acquire in a FIXED lexicographic order, so two migrations running in
  # opposite directions can never hold-and-wait on each other. _mbx_lock already gives up after ~2 s and
  # degrades lock-free rather than hanging, so this is belt-and-braces — but a hook is exactly where a
  # stall is unacceptable, and an ordered acquire costs nothing.
  if [[ "$old" < "$new" ]]; then lo="$old"; hi="$new"; else lo="$new"; hi="$old"; fi
  _mbx_lock "$lo" || true
  _mbx_lock "$hi" || true

  a="$(mailbox_acked "$old")"; cur="$(mailbox_lines "$old")"
  if [ "$cur" -le "$a" ]; then _mbx_unlock "$hi"; _mbx_unlock "$lo"; echo 0; return 1; fi
  body="$(tail -n +"$((a + 1))" "$f_old" 2>/dev/null | head -n "$(( cur - a ))")"
  if [ -z "$body" ]; then _mbx_unlock "$hi"; _mbx_unlock "$lo"; echo 0; return 1; fi

  # APPEND FIRST, ADVANCE SECOND — that ordering IS the no-loss guarantee. Advancing the cursor first
  # would silently destroy mail on a full/read-only disk. Line-at-a-time (not one bulk append) so a
  # partial failure is COUNTABLE: we advance by exactly what landed and the retry resumes cleanly.
  # One prefixed line per source line keeps the 1-message-1-line cursor contract intact, and keeps the
  # original "<ISO> [<from>] <msg>" visible after the provenance stamp.
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)"
  pfx="$ts [forwarded:$(printf '%s' "$old" | cut -c1-8)] "
  while IFS= read -r ln; do
    printf '%s%s\n' "$pfx" "$ln" >> "$f_new" 2>/dev/null || { rc=2; break; }
    migrated=$(( migrated + 1 ))
  done <<MBXEOF
$body
MBXEOF

  if [ "$migrated" -gt 0 ]; then
    cursor=$(( a + migrated ))
    _mbx_write_int "$(_mbx_dir)/$old.seen"  "$cursor" || rc=2
    _mbx_write_int "$(_mbx_dir)/$old.acked" "$cursor" || rc=2
  fi
  _mbx_unlock "$hi"; _mbx_unlock "$lo"
  echo "$migrated"
  [ "$migrated" -gt 0 ] || return 1
  return "$rc"
}
