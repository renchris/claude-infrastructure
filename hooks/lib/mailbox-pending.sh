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

# ── SESSION-KEYED ADDRESSING (v2 M1) + PULL-ADOPTION (v2 M4) ─────────────────────────────────────
# docs/plans/CROSS_SESSION_COMMS_V2.md §1.3-§1.4, §4.
#
# THE FRAME ERROR THIS REPLACES. The inbox was named after the container the reader currently
# occupies (its iTerm2 pane), and continuity across container changes was restored by a pointer the
# DYING container wrote (`.forward`). Both halves fail structurally:
#
#   (a) the address expires while the reader still LIVES — a `--resume` of the SAME session into a
#       NEW pane opens a fresh empty inbox while the real mail sits in <old-pane>.md (live incident
#       2026-07-29: the coordinator had to re-send by hand), and
#   (b) the repair is owed by the dead party — `.forward` has exactly TWO production writers
#       (handoff-fire.sh cooperative close, desk-register) so a crash / 529 / SIGKILL / plain resume
#       writes nothing. MEASURED COVERAGE: 3 of 91 dead-pane boxes = 3.3%.
#
# The durable identity was available at the exact point the fragile one was chosen: the harness hands
# every hook `session_id` on stdin, and mailbox-drain.sh discarded that stdin (`cat >/dev/null`) and
# then keyed on $ITERM_SESSION_ID. Twelve other hooks in this repo parse session_id from that same
# stdin. Pane-keying was never forced by a missing session id.
#
# THE INVERSION: address the SESSION; treat the pane as an ALIAS resolved at delivery; and have
# succession PULL from a provably-dead predecessor instead of relying on a push.
#
# WHY THE ALIAS LIVES ON THE BOUNDARY PATH: mailbox-drain.sh is the ONE place in the system that sees
# both identities at once, for every session, at every boundary. Writing the mapping there needs no
# daemon, no registry, and no cooperation from any dying party, and it SELF-HEALS — every boundary
# re-asserts it. That is `rearm-belongs-on-the-open-path` generalised from arming to addressing.
#
# The trail is APPEND-ONLY (never rewritten — append-only-store-safety-rules) and deduped against the
# last entry, so it stays small while preserving the pane's occupancy HISTORY. That history is what
# makes M4 possible without a `.forward`: a successor can see who held its pane before it.
#
#   mailbox_alias_write <pane> <session>   append pane→session iff it differs from the current tip
#   mailbox_alias_of    <pane>             current occupant session (echoes <pane> when unaliased, so
#                                          callers pipe unconditionally — same idiom as forward_of)
#   mailbox_alias_trail <pane>             every session ever on <pane>, NEWEST FIRST (M4 input)
#   mailbox_session_is_current <session>   is <session> the tip of ANY pane's trail? (liveness proxy)
#   mailbox_adoptable_predecessors <pane> <self>   sessions on <pane> that are provably NOT current
#
# Kill switches: CC_MBX_SESSION_KEY=0 (addressing reverts to pane-keyed) · CC_MBX_PULL_ADOPT=0
# (no pull-adoption). Both default ON. Env: CC_MBX_ALIAS_MAX_PRED (3) bounds the adoption fan-out.
_mbx_dir() { printf '%s' "${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"; }
_mbx_alias_dir() { printf '%s/.alias' "$(_mbx_dir)"; }
_mbx_alias_file() { printf '%s/%s' "$(_mbx_alias_dir)" "${1:-}"; }
# A mailbox KEY is a safe filename component, not necessarily a UUID. This used to be a hex-and-dashes
# check, which silently made every NAME-keyed box invisible to the whole library: `mailbox_lines`
# returned 0, so `mailbox_unacked_count` returned 0, so cc-inbox-guard's fail-loud backstop saw nothing
# to alarm about. And name-keyed boxes are REAL — a role file legitimately holds "a uuid, a session id,
# or a pane name" (desk-register; cc-announce says the same), and `cc-notify --role` uses that value
# VERBATIM as the mailbox key. Mail addressed that way could therefore go undelivered forever with the
# guard structurally unable to see it. Widened to any safe component: non-empty, no path separator, no
# leading dot (which would collide with the .lock/.tmp namespace), and no `.`/`..` traversal. Every
# previously-valid key still passes; only the blind spot closes. Address-shaped values (`.forward`
# pointers) stay on the STRICT canonical-UUID check below — that one is deliberately narrow.
_mbx_valid_uuid() {
  case "${1:-}" in
    ''|.|..) return 1 ;;
    .*) return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}
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

# ── READ RECEIPT — delivery, surfacing and consumption are THREE events ───────────────────────────
# Only the third means "they know", and every sender-side report we had described the first. That gap
# has a measured cost: 2026-07-26 14:10 the desk told two panes their land-lock blocker was stale and
# to retry; cc-notify said "delivered to inbox (live session)" for both; neither ever read the line
# (~4 h idle, 4 unread each) and the desk reported them to the operator as unblocked. Nothing had
# lied — "delivered" was true. It was just answering a different question than the one being asked.
#
# The proof already existed in the cursors; nothing exposed it per-message. Given the line a message
# landed on, this turns those cursors into the verdict, so a claim can cite the cursor and not the send:
#   unread   — .seen has not reached the line: nothing has surfaced it
#   surfaced — .seen passed it (a drain emitted it) but .acked has not: shown, not provably consumed
#   read     — .acked passed it: a turn provably carried it. THE ONLY ONE THAT MEANS "they were told".
# Keyed on .acked (never the eager .seen) for the same reason cc-inbox-guard is: seen is a promise,
# acked is evidence. Fail-safe like every read here — a bad uuid or line reports the WEAKEST verdict
# (unread), so a malformed query can never manufacture a false "read".
mailbox_receipt() { # <uuid> <line> → echoes unread|surfaced|read; exit 0 iff read
  local u="${1:-}" n
  n="$(_mbx_int "${2:-0}")"
  if ! _mbx_valid_uuid "$u" || [ "$n" -le 0 ]; then echo unread; return 1; fi
  if [ "$(mailbox_acked "$u")" -ge "$n" ]; then echo read; return 0; fi
  if [ "$(mailbox_seen  "$u")" -ge "$n" ]; then echo surfaced; return 1; fi
  echo unread; return 1
}

# ── WAKE-PATH PREDICATE — the ONE definition (v3 D4 / wake-floor) ─────────────────────────────────
# "Is <uuid> reachable RIGHT NOW by a write to its inbox?" i.e. does it have a live cc-await-ping
# whose exit will ride the harness task-completion notification back into the model.
#
# WHY IT LIVES HERE: this predicate had TWO independent copies — bin/cc-notify's wake_path_armed
# (:511-520) and hooks/mailbox-drain.sh's inline block (:100-111) — and mailbox-drain's own comment
# already stated the invariant those copies exist to satisfy: "the two consumers of this marker must
# not disagree about whether a wake path exists." Two copies cannot enforce that; one definition can.
# The wake FLOOR (hooks/session-continue.sh) would have been a third copy, which is what forced the
# extraction. Both original copies read the identical CC_WATCH_FRESH_S:-90 seam, so hoisting them is
# behaviour-preserving by construction, not a re-derivation.
#
# TWO conditions, both required:
#   freshness — the heartbeat is re-stamped every poll, so a stale one means the watcher is gone.
#   pid alive — a SIGKILLed watcher skips cc-await-ping's EXIT cleanup and leaves the marker behind.
#               A marker naming a DEAD pid is NOT a wake path; treating it as one is exactly the
#               false promise cc-notify's verdict must never make.
# No pid recorded ⇒ legacy marker ⇒ freshness is all there is to go on (never fail a legacy arm).
mailbox_wake_armed() { # <uuid> → 0 = a live watcher will wake this session, 1 = it will not
  local u="${1:-}" wf mt now wpid
  wf="$(_mbx_dir)/$u.watching"; [ -f "$wf" ] || return 1
  mt="$(stat -f %m "$wf" 2>/dev/null || stat -c %Y "$wf" 2>/dev/null || echo 0)"
  now="$(date +%s 2>/dev/null || echo 0)"
  case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
  [ "$(( now - mt ))" -le "${CC_WATCH_FRESH_S:-90}" ] 2>/dev/null || return 1
  wpid="$(sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p' "$wf" 2>/dev/null | head -n1)"
  [ -n "$wpid" ] || return 0
  kill -0 "$wpid" 2>/dev/null
}

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

# ── M1: PANE→SESSION ALIAS TRAIL ─────────────────────────────────────────────────────────────────
# Append-only occupancy history for one pane. Deduped against the tip so a session taking 500
# boundaries writes ONE line, not 500 — the file stays O(sessions-on-this-pane), not O(turns).
# Fail-safe like every primitive here: a bad key or an unwritable dir is a silent no-op, never an
# error that could cost a hook.
mailbox_alias_write() { # <pane> <session>
  local pane="${1:-}" sess="${2:-}" f tip dir
  _mbx_valid_uuid "$pane" || return 1
  _mbx_valid_uuid "$sess" || return 1
  [ "$pane" = "$sess" ] && return 1          # a self-alias carries no information
  dir="$(_mbx_alias_dir)"; mkdir -p "$dir" 2>/dev/null || return 1
  f="$(_mbx_alias_file "$pane")"
  tip="$(tail -n1 "$f" 2>/dev/null | awk '{print $2}')"
  [ "$tip" = "$sess" ] && return 0           # already the current occupant → dedup
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null)" "$sess" >> "$f" 2>/dev/null || return 1
  return 0
}

# Current occupant of <pane>. Echoes <pane> itself when there is no alias, so every caller can pipe
# through this with no "does an alias exist?" branch (the mailbox_forward_of idiom).
mailbox_alias_of() { # <pane>
  local pane="${1:-}" sess
  _mbx_valid_uuid "$pane" || { printf '%s' "$pane"; return 1; }
  sess="$(tail -n1 "$(_mbx_alias_file "$pane")" 2>/dev/null | awk '{print $2}')"
  if [ -n "$sess" ] && _mbx_valid_uuid "$sess"; then printf '%s' "$sess"; return 0; fi
  printf '%s' "$pane"; return 0
}

# Every session ever seen on <pane>, NEWEST FIRST. The M4 input.
mailbox_alias_trail() { # <pane>
  local pane="${1:-}"
  _mbx_valid_uuid "$pane" || return 1
  awk '{print $2}' "$(_mbx_alias_file "$pane")" 2>/dev/null | awk 'NF' | awk '!seen[$0]++' | sed '1!G;h;$!d'
}

# Is <session> the CURRENT occupant of any pane? This is the liveness PROXY that makes M4 safe
# without a daemon and without row 4's (currently inert) beat oracle: a pane holds one session at a
# time, so a session that is the tip of some pane's trail is being addressed as live RIGHT NOW.
# Used only to REFUSE adoption — never to assert death. Deliberately conservative in that direction.
mailbox_session_is_current() { # <session> → 0 = tip of some pane's trail, 1 = tip of none
  local sess="${1:-}" f tip
  _mbx_valid_uuid "$sess" || return 1
  for f in "$(_mbx_alias_dir)"/*; do
    [ -f "$f" ] || continue
    tip="$(tail -n1 "$f" 2>/dev/null | awk '{print $2}')"
    [ "$tip" = "$sess" ] && return 0
  done
  return 1
}

# ── M4: PULL-ADOPTION — who may I take mail from? ────────────────────────────────────────────────
# A predecessor is adoptable iff it held MY pane before me AND it is not the current occupant of any
# pane. The second clause is what stops us stealing from a session that RESUMED ELSEWHERE and is
# still alive — the exact case pane-keying could not distinguish. Bounded to the N most recent
# (CC_MBX_ALIAS_MAX_PRED, default 3): a hook must never do unbounded work (R3).
#
# ORDER MATTERS: the trail is newest-first, so the bound keeps the MOST RECENT predecessors — the
# ones whose mail is most likely to still matter — rather than an arbitrary N.
mailbox_adoptable_predecessors() { # <pane> <self-session>
  local pane="${1:-}" self="${2:-}" max="${CC_MBX_ALIAS_MAX_PRED:-3}" n=0 q
  _mbx_valid_uuid "$pane" || return 1
  case "$max" in ''|*[!0-9]*) max=3 ;; esac
  while IFS= read -r q; do
    [ -n "$q" ] || continue
    [ "$q" = "$self" ] && continue                  # never adopt from ourselves
    [ "$q" = "$pane" ] && continue                  # degenerate alias
    mailbox_session_is_current "$q" && continue      # ALIVE somewhere → refuse (the load-bearing guard)
    printf '%s\n' "$q"
    n=$(( n + 1 ))
    [ "$n" -ge "$max" ] && break
  done <<MBXPRED
$(mailbox_alias_trail "$pane")
MBXPRED
  return 0
}

# ── M1: the one resolver every SENDER uses ───────────────────────────────────────────────────────
# Given whatever a caller holds — a session id, a pane uuid, a role-derived name — return the box key
# mail should land in. Resolution order, each step degrading to the next (never a hard failure):
#   0. kill switch CC_MBX_SESSION_KEY=0            → today's behaviour, verbatim
#   1. the key already names a box that exists       → use it (idempotent for session-keyed callers)
#   2. pane→session via the alias trail              → the session box
#   3. the key itself                                → pane-keyed, exactly as before
# The FORWARD chain is still applied by the caller on top of this, so legacy pane boxes that DID get
# a cooperative `.forward` keep working. M1 removes the NEED for the pointer; it does not break it.
mailbox_resolve_key() { # <pane-or-session> → box key
  local k="${1:-}" sess
  _mbx_valid_uuid "$k" || { printf '%s' "$k"; return 1; }
  if [ "${CC_MBX_SESSION_KEY:-1}" = 0 ]; then printf '%s' "$k"; return 0; fi
  # An existing box for this exact key wins: a session-keyed sender must stay idempotent, and a pane
  # that has never taken a boundary still has its own box.
  if [ -f "$(mailbox_file "$k")" ] && ! [ -f "$(_mbx_alias_file "$k")" ]; then printf '%s' "$k"; return 0; fi
  sess="$(mailbox_alias_of "$k")"
  printf '%s' "$sess"
  return 0
}
