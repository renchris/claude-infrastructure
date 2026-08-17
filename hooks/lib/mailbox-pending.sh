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
#   mailbox_take_n <uuid> [ack] [max]  same, but delivers AT MOST <max> lines and advances the cursor by
#                                    exactly what it printed (max=0/absent ⇒ unlimited ⇒ mailbox_take).
#   mailbox_take_from <uuid> <from> [ack]  LOCKED: print lines (from, EOF] where <from> is the CALLER'S
#                                    OWN cursor, not the shared .seen; advances the shared cursors but
#                                    never REGRESSES them. For a reader that must not be starvable by
#                                    another consumer's cursor write (bin/cc-await-ping — F-3).
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

# ── PORTABLE MTIME, and why the ORDER is the whole fix ───────────────────────────────────────────
# The idiom this file used — `stat -f %m … || stat -c %Y … || echo 0` — is macOS-first with a Linux
# fallback, and on Linux the fallback IS NEVER REACHED: GNU `stat -f` is not "BSD mtime", it is
# --file-system, so it exits 0 printing a filesystem report ("Inodes: Total: … Free: …"). The digit
# guard downstream then reads that as unparseable and yields 0 — an mtime of the epoch. Every
# freshness question in this file therefore answered "ancient" on Linux, permanently:
# `mailbox_wake_armed` said NOT ARMED over a live watcher's fresh heartbeat, and `_mbx_lock` treated
# every held lock as stale and stole it on the first poll. Measured 2026-08-16 on a Linux worker
# while building the W2 claim guard, whose entire job is that predicate.
#
# Reversing the order fixes it because the failure is asymmetric: BSD `stat` has no `-c` and exits
# non-zero on it, so the fallback fires; GNU `stat` has a `-f` that SUCCEEDS at something else, so it
# never does. Try the flag whose wrong-platform behaviour is an ERROR first. Behaviour on macOS — the
# fleet — is unchanged by construction: `-c` fails there exactly as `-f` failed here.
#
# SCOPE. 51 further call sites carry the same idiom and the same latent bug — enumerate them with
#   grep -rn 'stat -f %m' hooks/ bin/ scripts/
# (`hooks/session-continue.sh:328` and `bin/cc-idl:52` are the two with live suite reds behind them:
# wake-floor 27/28 and ttl-lock-owner-token 7). They are NOT touched here, and NOT yet in the
# backlog — the worker that found this had no reachable store. This helper exists so the four readers of
# the wake-path predicate — cc-notify, mailbox-drain, the wake floor, and the wake-arm claim guard —
# cannot disagree about it, which is the invariant that made this file the SSOT in the first place.
_mbx_mtime() { # <path> → epoch seconds, 0 when unknowable
  local m
  m="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)"
  case "$m" in ''|*[!0-9]*) m=0 ;; esac
  printf '%s' "$m"
}

# ── portable mkdir lock (macOS-safe; flock is Linux-only) ─────────────────────────────────────────
# OWNER TOKEN (a15/D4). The 2 s give-up and the mtime-TTL self-break below are DELIBERATE — this
# channel picks a benign duplicate over a hung hook, and that contract is unchanged here. What was
# not deliberate is the release: `_mbx_unlock` was an unconditional `rm -rf`, so a holder whose lock
# had been TTL-stolen from it went on to delete the THIEF's lock and admit a third writer. Two
# concurrent cursor writers is the bounded dup the design accepts; THREE, one of which believes it
# holds a mutex nobody else can see, is not — it is unbounded by construction.
#
# So: stamp an owner token on acquire and verify it on release. That closes the chain without
# touching the dup-over-hang policy. It also lets the reap convict faster than the TTL when the
# holder is provably dead, while still never stealing from a live one before its TTL.
_mbx_lock() { # <uuid> → 0 acquired, 1 gave up (caller proceeds lock-free: dup-risk, never a hang)
  local u="$1" ld waited=0 step=50 max="${CC_MBX_LOCK_WAIT_MS:-2000}" stale="${CC_MBX_LOCK_STALE_S:-10}"
  mkdir -p "$(_mbx_dir)" 2>/dev/null || return 1
  ld="$(_mbx_dir)/.$u.lock"
  while ! mkdir "$ld" 2>/dev/null; do
    local mt now age htok=""
    # A provably-dead holder is reclaimed at once — no need to serve out its TTL. Read with the
    # `read` builtin, never `$(cat …)`: this is a hot hook path and a fork per poll is real cost.
    [ -f "$ld/owner" ] && { read -r htok < "$ld/owner" 2>/dev/null || htok=""; }
    case "$htok" in
      ''|*[!0-9]*) ;;                                        # no/odd token → fall through to TTL
      *) kill -0 "$htok" 2>/dev/null || { rm -rf "$ld" 2>/dev/null; continue; } ;;
    esac
    mt="$(_mbx_mtime "$ld")"
    now="$(date +%s 2>/dev/null || echo 0)"; age=$(( now - $(_mbx_int "$mt") ))
    [ "$age" -ge "$stale" ] 2>/dev/null && { rm -rf "$ld" 2>/dev/null; continue; }   # holder died → break
    [ "$waited" -ge "$max" ] && return 1
    sleep 0.05 2>/dev/null || sleep 1; waited=$(( waited + step ))
  done
  printf '%s\n' "$$" > "$ld/owner" 2>/dev/null || true
  return 0
}
# Release ONLY what we still own: if our lock was TTL-stolen and a peer now holds its own dir, the
# token is theirs and deleting it would admit a third writer. Fork-free read, as above.
_mbx_unlock() {
  local ld tok=""
  ld="$(_mbx_dir)/.${1:-}.lock"
  [ -f "$ld/owner" ] && { read -r tok < "$ld/owner" 2>/dev/null || tok=""; }
  # An UNTOKENED dir is ours by construction: the only writer that leaves no token is a pre-fix
  # holder, and on this path that can only be a dir we just created. Deleting it keeps release
  # total (never leaking a lock) while a FOREIGN token is always preserved.
  if [ -z "$tok" ] || [ "$tok" = "$$" ]; then
    rm -rf "$ld" 2>/dev/null || true
  fi
  return 0
}

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
  mt="$(_mbx_mtime "$wf")"
  now="$(date +%s 2>/dev/null || echo 0)"
  case "$mt" in ''|*[!0-9]*) mt=0 ;; esac
  [ "$(( now - mt ))" -le "${CC_WATCH_FRESH_S:-90}" ] 2>/dev/null || return 1
  wpid="$(sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p' "$wf" 2>/dev/null | head -n1)"
  [ -n "$wpid" ] || return 0
  kill -0 "$wpid" 2>/dev/null
}

# ── WHO is arming it, and IN WHICH MODE — the two questions E2 needs and the predicate above cannot
#    answer (docs/research/goal-safe-2way-comms-2026-08-13.md §8 E2) ───────────────────────────────
# `mailbox_wake_armed` answers "is a wake path live?", which is the only question its three callers
# ever had. E2 asks a different one: a watcher armed BEFORE a `/goal` arrived defers that goal for
# its whole term (CC skips goal evaluation at any Stop holding a non-terminal background Bash), and
# the ONLY thing that can end it is a `kill` naming the pid — so the surface that reports the
# condition has to be able to NAME the culprit. Both live here rather than in the drain for the
# reason the predicate above was hoisted here: two readers of one marker must not disagree about it.
mailbox_wake_pid() { # <uuid> → prints the LIVE watcher's pid; rc 1 = no live watcher, or a legacy
                     #           marker that records no pid (armed, but not nameable — say nothing)
  local u="${1:-}" wf wpid
  mailbox_wake_armed "$u" || return 1
  wf="$(_mbx_dir)/$u.watching"
  wpid="$(sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p' "$wf" 2>/dev/null | head -n1)"
  [ -n "$wpid" ] || return 1
  printf '%s\n' "$wpid"
}

# THE WRITER CONTRACT, stated here because this is the reader (B3, `cc-await-ping --idle-scoped`,
# §4 C1-C7). An idle-scoped watcher is SANCTIONED under a live goal: it terminates on any new turn
# of its own session, so its deferral spans exactly the idle window. It must therefore be
# distinguishable from the plain 14400 s park, which is not. The declaration is a `mode=idle-scoped`
# line stamped by the watcher itself into EITHER of the two files it already re-writes every poll:
#   ~/.claude/mailbox/<key>.watching        the marker (one owner slot, handed over at exit)
#   ~/.claude/mailbox/.watchers/<key>.<pid> its own per-pid claim (never handed over)
# Either suffices; the claim is the sturdier of the two, because `_unbeat`'s hand-over rewrites the
# marker on behalf of a sibling whose mode it does not know. Absence ⇒ NOT idle-scoped, which is the
# fail direction E2 needs: an unstamped watcher is reported as goal-blocking (a false alarm at worst,
# and today every watcher in the fleet genuinely is one), where the inverse would silently swallow
# the report this exists to make.
mailbox_wake_idle_scoped() { # <uuid> → 0 iff the LIVE watcher declares idle-scoped mode
  local u="${1:-}" wpid
  wpid="$(mailbox_wake_pid "$u")" || return 1
  grep -q '^mode=idle-scoped$' "$(_mbx_dir)/$u.watching" 2>/dev/null && return 0
  grep -q '^mode=idle-scoped$' "$(_mbx_dir)/.watchers/$u.$wpid" 2>/dev/null && return 0
  return 1
}

# LOCKED atomic take: snapshot the window (seen, EOF], print it, advance seen=EOF (never regress), and —
# for a reliable channel — acked=EOF too. Emitting is the CALLER's job (it wraps the body in JSON); the
# guard's acked cursor is what makes a post-print emit-failure loud, so advancing seen inside the lock is
# safe (F1 atomicity) without needing emit-before-advance for the reliable path. Returns 1 if the seen
# write FAILED (F9): the caller must escalate, not re-loop on the same mail.
mailbox_take() { # <uuid> [ack_now]  (ack_now=1 ⇒ reliable channel: advance acked too)
  mailbox_take_n "${1:-}" "${2:-0}" 0
}

# BOUNDED take (v3 D5). Identical to mailbox_take except it delivers at most <max> lines and advances the
# cursor by EXACTLY what it printed — never by the window it could have taken.
#
# Why a cap needs its own primitive rather than a caller-side `head`: mailbox_take advances seen=EOF, so a
# caller that printed only the first N lines of a larger window would mark the unshown remainder DELIVERED
# and silently lose it — the precise failure class this whole substrate exists to make impossible. The cap
# lives INSIDE the lock, beside the cursor write, so "shown" and "advanced" cannot diverge.
#
# The cap matters because D5 drains between tool calls: a 600-line box must not be dumped into a tool
# result. Whatever is left over is not lost — it is still (seen, EOF] and the very next boundary takes it.
mailbox_take_n() { # <uuid> [ack_now] [max]  (max 0/absent ⇒ unlimited)
  local u="${1:-}" ack_now="${2:-0}" max="${3:-0}" f prev cur want body rc=0
  _mbx_valid_uuid "$u" || return 1
  case "$max" in ''|*[!0-9]*) max=0 ;; esac
  f="$(mailbox_file "$u")"
  _mbx_lock "$u" || true                       # gave up ⇒ proceed lock-free (dup-risk, never a hang)
  prev="$(mailbox_seen "$u")"; cur="$(mailbox_lines "$u")"
  if [ "$cur" -le "$prev" ]; then _mbx_unlock "$u"; return 1; fi   # nothing new
  want=$(( cur - prev ))
  if [ "$max" -gt 0 ] && [ "$want" -gt "$max" ]; then want="$max"; cur=$(( prev + want )); fi
  body="$(tail -n +"$((prev + 1))" "$f" 2>/dev/null | head -n "$want")"
  printf '%s' "$body"
  if ! _mbx_write_int "$(_mbx_dir)/$u.seen" "$cur"; then rc=2; fi   # F9: body printed, cursor write FAILED
  [ "$ack_now" = 1 ] && [ "$rc" = 0 ] && _mbx_write_int "$(_mbx_dir)/$u.acked" "$cur"
  _mbx_unlock "$u"
  return "$rc"
}

# ── READER-PRIVATE TAKE (F-3, 2026-08-09) ────────────────────────────────────────────────────────
# Identical to mailbox_take_n except the window starts at the CALLER'S OWN cursor instead of the
# shared `.seen`, and the shared cursors are advanced but NEVER regressed — this reader is an
# ADDITIONAL consumer, not the owner of `.seen`.
#
# WHY IT HAS TO EXIST. `mailbox_take_n` opens its window at `.seen`, so a reader whose trigger is
# "is there a line I have not delivered?" cannot use it once ANOTHER consumer has advanced `.seen`
# past that line: the take returns rc 1 and prints nothing, while the line is demonstrably in the
# box. That is the measured cursor race — hooks/mailbox-drain.sh advances `.seen` on delivery
# (its :13, ack_now=0) and bin/cc-await-ping polled that same cursor, so whichever consumer ran
# first starved the other. Post-mortem 2026-08-09: `886.seen=3`, `886.acked=3`, mailbox 3 lines, a
# perfect ping (landed + announced + self-closed) delivered by the drain, and the lead's ARMED
# watcher polling an empty delta forever — alive, armed, permanently silent.
#
# The fix is not to pick a different shared cursor (`.acked` was equally at EOF in that
# post-mortem, and would merely re-couple the watcher to the Stop-fold's timing). It is to stop
# sharing the TRIGGER at all: a reader passes the cursor it last delivered from, and no other
# consumer's bookkeeping can move it. DUP-BIASED, matching the drain's own declared bias (:15) —
# if the drain already surfaced the line, this re-delivers it and the reader wakes anyway, because
# a duplicate wake is cheap and a lost wake is a multi-hour hang.
#
# Exit: 0 = printed + cursors reconciled · 1 = nothing new FOR THIS READER · 2 = body printed but a
# cursor write FAILED (same F9 escalation contract as mailbox_take_n).
mailbox_take_from() { # <uuid> <from> [ack_now]
  local u="${1:-}" from="${2:-0}" ack_now="${3:-0}" f cur seen acked body rc=0
  _mbx_valid_uuid "$u" || return 1
  from="$(_mbx_int "$from")"
  f="$(mailbox_file "$u")"
  _mbx_lock "$u" || true                       # gave up ⇒ proceed lock-free (dup-risk, never a hang)
  cur="$(mailbox_lines "$u")"
  # A cursor PAST EOF means the box rotated/was GC'd under us — re-deliver rather than go silent,
  # exactly as mailbox_seen's own past-EOF clamp does (F11).
  [ "$from" -gt "$cur" ] 2>/dev/null && from=0
  if [ "$cur" -le "$from" ]; then _mbx_unlock "$u"; return 1; fi
  body="$(tail -n +"$((from + 1))" "$f" 2>/dev/null)"
  printf '%s' "$body"
  # ADVANCE-NEVER-REGRESS. Another consumer may already be ahead of us; writing our own `cur` over a
  # larger `.seen` would un-deliver ITS mail and re-create this very race in the other direction.
  seen="$(mailbox_seen "$u")"
  if [ "$seen" -lt "$cur" ]; then
    _mbx_write_int "$(_mbx_dir)/$u.seen" "$cur" || rc=2
  fi
  if [ "$ack_now" = 1 ] && [ "$rc" = 0 ]; then
    acked="$(mailbox_acked "$u")"
    if [ "$acked" -lt "$cur" ]; then
      _mbx_write_int "$(_mbx_dir)/$u.acked" "$cur" || rc=2
    fi
  fi
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
#
# PERFORMANCE (2026-08-16): this used to `tail | awk` PER FILE — two forks × every alias file. At
# 1,300 files that is ~2,600 forks, measured at 5.0 s for a single MISS, and a miss is the common
# case. `mailbox_adoptable_predecessors` calls it once per trail candidate, so a reused pane paid
# 5 s+ and `mailbox-drain.sh session-start` was REAPED at its `timeout: 5` with its work discarded
# — silently dropping peer mail on 47.9% of session starts. One awk pass over the same files is
# 0.04 s median (n=5, 1,296 tips / 1,300 files), i.e. ~100×.
#
# The set is memoised for the life of the process. That is the CORRECT lifetime, not a shortcut: a
# hook is short-lived, and the one write that could invalidate the set mid-run is our own session's
# alias append — which cannot change any answer, because every caller already skips `q = self`.
# A consistent snapshot is additionally SAFER than re-reading: it cannot half-see a concurrent
# append and flip a liveness verdict between two candidates in the same scan.
_MBX_TIPSET=
_MBX_TIPSET_LOADED=
_mbx_tipset_load() {
  [ -n "$_MBX_TIPSET_LOADED" ] && return 0
  _MBX_TIPSET_LOADED=1
  local d; d="$(_mbx_alias_dir)"
  [ -d "$d" ] || return 0
  # Newline-delimited, with leading+trailing newlines so a `case` glob can anchor whole tokens.
  # find|xargs rather than a glob: an empty .alias would make a bare `awk dir/*` read STDIN and hang.
  # shellcheck disable=SC2016  # $2 and FILENAME belong to AWK, not the shell — the single quotes are
  # what keeps them unexpanded. "Fixing" this to double quotes would substitute the shell's empty $2
  # and silently make the program read an empty field for every alias file.
  _MBX_TIPSET="
$(find "$d" -maxdepth 1 -type f -print0 2>/dev/null \
    | xargs -0 awk '{ last[FILENAME] = $2 } END { for (f in last) if (last[f] != "") print last[f] }' 2>/dev/null)
"
}
# Test seam: drop the memo so a suite can mutate .alias and re-read within one process.
mailbox_tipset_reset() { _MBX_TIPSET=; _MBX_TIPSET_LOADED=; }

mailbox_session_is_current() { # <session> → 0 = tip of some pane's trail, 1 = tip of none
  local sess="${1:-}"
  _mbx_valid_uuid "$sess" || return 1
  _mbx_tipset_load
  case "$_MBX_TIPSET" in
    *"
$sess
"*) return 0 ;;
  esac
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

# ── THE READER MUST COVER THE WRITER'S KEY SPACE, NOT ITS OWN (2026-07-31) ───────────────────────
# One LOGICAL inbox is physically spread over more than one key, and the two ends of the channel pick
# different ones:
#   WRITER  cc-notify addresses a target by whatever the ecosystem hands it — a role file, a registry
#           row, a raw uuid — and every one of those is PANE-keyed (measured: cc-roles/desk and every
#           cc-registry/*.json hold pane uuids). It resolves no alias, so the line lands in <pane>.md.
#   READER  mailbox-drain.sh reads <session>.md (its :64-68) and harvests the pane box with
#           mailbox_migrate at each boundary.
# That merge makes the split invisible to a session that takes TURNS — and fatal to one that is
# WAITING. A watcher parked on the session key sees nothing until a boundary runs, and the boundary is
# the very thing the watcher exists to cause: it reports armed and is deaf. (Measured for this fix: on
# one cc-notify write, a session-keyed cc-await-ping timed out at rc 2 while a pane-keyed watcher on
# the SAME write woke in one poll.) Naming "the key the drain reads" — as the 2026-07-29 box-key
# agreement did — makes both sides agree on a key nothing writes to; agreement is not the invariant,
# COVERAGE is.
#
# mailbox_keyset is that cover: the key itself plus its alias target, one per line, deduped. At most
# two entries and no directory scan, so it is cheap enough to recompute every poll — which it must be,
# because a pane that has not yet taken a boundary has no alias and its session key joins the set only
# later. Callers that also WRITE a per-key marker (cc-await-ping's .watching heartbeat) must write one
# for every key, so a reader asking about EITHER key gets the same answer.
mailbox_keyset() { # <pane-or-session> → every physical key of this logical inbox, one per line
  local k="${1:-}" sess f
  _mbx_valid_uuid "$k" || return 1
  printf '%s\n' "$k"
  [ "${CC_MBX_SESSION_KEY:-1}" = 0 ] && return 0
  sess="$(mailbox_alias_of "$k")"
  if [ -n "$sess" ] && [ "$sess" != "$k" ]; then printf '%s\n' "$sess"; return 0; fi

  # REVERSE EDGE (session → its pane). The trail maps pane→session, so a caller holding a SESSION id
  # has no forward edge to the pane box cc-notify actually writes — coverage would hold for the no-arg
  # arm and quietly fail for any other. It is not hypothetical during a rollout: every pane already
  # running carries the OLD session-keyed advisory in its context and may arm from it.
  # TIP, never containment: a pane whose trail merely MENTIONS this session has since been re-occupied,
  # and adopting its box would consume the current occupant's mail. So grep only shortlists (one fork
  # over the whole dir) and the tail adjudicates each candidate — normally exactly one.
  local shortlist
  shortlist="$(grep -lF " $k" "$(_mbx_alias_dir)"/* 2>/dev/null)"
  [ -n "$shortlist" ] || return 0
  printf '%s\n' "$shortlist" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$(tail -n1 "$f" 2>/dev/null | awk '{print $2}')" = "$k" ] && printf '%s\n' "${f##*/}"
  done
  return 0
}
