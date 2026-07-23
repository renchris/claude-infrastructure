#!/bin/bash
# mailbox-drain.sh — v2 non-keystroke delivery on the RELIABLE boundaries: drain this session's inbox
# and surface it as additionalContext (never keystrokes, never the live input line).
#
#   mailbox-drain.sh session-start   (SessionStart hook)  → additionalContext
#   mailbox-drain.sh prompt          (UserPromptSubmit)   → additionalContext
#
# The Stop channel is DELIBERATELY not here (critique fix B): in-loop mail delivery is folded into
# session-continue.sh — the ONE hook already blocking the in-loop desk — so there is no competing Stop
# blocker, no 4-hook yield-guards, no wall-clock TTL. Idle/mid-turn mail is caught by the target's armed
# cc-await-ping watcher (seeded from .seen so it never misses a pending line); the cc-inbox-guard is the
# fail-loud backstop. SessionStart + UserPromptSubmit are the harness's two RELIABLE additionalContext
# boundaries, so a delivery here advances ONLY the .seen (emitted) cursor (mailbox_take …0) — never the
# .acked (consumed) cursor. .acked is promoted one cycle later at the next Stop fold (session-continue.sh
# → mailbox_promote_acked), the moment a turn PROVABLY carried the mail. Dup-biased BY DESIGN: a death
# after drain but before that Stop re-surfaces the mail next boundary (a visible dup) — acking at drain
# would instead have marked it consumed and SILENTLY LOST it on a mid-turn death the guard can't see.
#
# The inbox is ~/.claude/mailbox/<own-pane-uuid>.md; delivery is exactly-once via the split cursor
# (.seen emitted / .acked consumed) under a lock — see hooks/lib/mailbox-pending.sh.
#
# FAIL-SAFE: missing uuid / jq / lib → exit 0 (deliver nothing; the guard backstops). Every path exits 0.
# Env seams (tests): CC_MAILBOX_DIR · ITERM_SESSION_ID.

MODE="${1:-}"

_scd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_lib="$_scd/lib/mailbox-pending.sh"
[ -f "$_lib" ] || _lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh"
[ -f "$_lib" ] || _lib="$HOME/.claude/hooks/lib/mailbox-pending.sh"
# shellcheck source=lib/mailbox-pending.sh
# shellcheck disable=SC1091
. "$_lib" 2>/dev/null || exit 0

command -v jq >/dev/null 2>&1 || exit 0
cat >/dev/null 2>&1 || true    # consume the hook JSON on stdin so the writer never SIGPIPEs

own_uuid="${ITERM_SESSION_ID:-}"; own_uuid="${own_uuid##*:}"
case "$own_uuid" in ''|*[!0-9A-Fa-f-]*) exit 0 ;; esac

case "$MODE" in
  session-start) EVENT=SessionStart ;;
  prompt)        EVENT=UserPromptSubmit ;;
  *)             exit 0 ;;   # Stop / unknown are not handled here (see fix B)
esac

# LOCKED atomic take on a RELIABLE boundary → advance ONLY .seen (ack_now=0); .acked is promoted at the
# next Stop fold (session-continue.sh → mailbox_promote_acked) once a turn provably consumed the mail.
# Body on stdout; rc 1 = nothing new; rc 2 = delivered-but-.seen-write-failed (still surface the body —
# better a dup next turn than a drop; the re-deliver is bounded and the guard sees the un-advanced .acked).
body="$(mailbox_take "$own_uuid" 0)"; rc=$?

# ── ADOPTION (v3 D1) — SessionStart only: inherit what a predecessor pane never consumed ──────────
# A pane that self-closed with a successor left `<old>.forward` → us. Its inbox may still hold lines
# nobody ever read (live forensics: 631/206/155 stranded in former-desk boxes). Take them ONCE, here,
# where we already hold a boundary that can surface them.
#
# ORDER: own take FIRST (adoption is best-effort; a bug in it must never cost us our OWN mail), then
# migrate, then a SECOND take to surface what just landed AT THIS SAME BOUNDARY. Deferring adopted
# mail to the next boundary would reproduce the exact latency the SLO exists to kill — and the second
# take is free (rc 1 when nothing migrated).
#
# BOUNDED: only *.forward files naming us, one pass, no chain-walking (a chain's intermediate hops are
# resolved by the SENDER; here we adopt only what points directly at us — a multi-hop predecessor is
# adopted by ITS successor, transitively, as each one starts). Every path exits 0.
if [ "$MODE" = "session-start" ] && command -v mailbox_migrate >/dev/null 2>&1; then
  _mdir="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
  _adopted=0
  for _f in "$_mdir"/*.forward; do
    [ -f "$_f" ] || continue                                   # unmatched glob
    _tgt="$(head -n1 "$_f" 2>/dev/null | tr -dc '0-9A-Fa-f-')"
    [ "$_tgt" = "$own_uuid" ] || continue                      # not pointing at us
    _pred="$(basename "$_f" .forward)"
    [ "$_pred" = "$own_uuid" ] && continue                     # paranoia: never adopt from ourselves
    _n="$(mailbox_migrate "$_pred" "$own_uuid" 2>/dev/null || true)"
    case "$_n" in ''|*[!0-9]*) _n=0 ;; esac
    _adopted=$(( _adopted + _n ))
  done
  if [ "$_adopted" -gt 0 ]; then
    _more="$(mailbox_take "$own_uuid" 0)"                      # surface the adopted lines NOW
    [ -n "$_more" ] && body="$([ -n "$body" ] && printf '%s\n' "$body"; printf '%s' "$_more")"
  fi
fi

[ -n "$body" ] || exit 0        # rc 1: nothing pending

n="$(printf '%s\n' "$body" | grep -c '')"; plural=$([ "$n" = 1 ] && echo message || echo messages)
warn=""; [ "$rc" = 2 ] && warn=' (⚠ cursor write failed — you may see this again; that is a dup, not a loss)'

# ── WAKE NUDGE (v3 D4) — the fleet-wide finding: 0 armed watchers across 16 live sessions, and the
# desk sat on 57 unacked pages for 2 h. The harness floor is that NOTHING external can wake an idle
# session — only the model can arm its own watcher. So the one moment we can fix that is HERE, when we
# have the model's attention and can see (by the absence of a fresh `.watching` heartbeat) that it has
# no wake path. One line, only when actually unwatched — a nudge on every drain would be noise.
nudge=""
_wf="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}/$own_uuid.watching"
_fresh_s="${CC_WATCH_FRESH_S:-90}"
_watched=0
if [ -f "$_wf" ]; then
  _mt="$(stat -f %m "$_wf" 2>/dev/null || stat -c %Y "$_wf" 2>/dev/null || echo 0)"
  _now="$(date +%s 2>/dev/null || echo 0)"
  case "$_mt" in ''|*[!0-9]*) _mt=0 ;; esac
  [ "$(( _now - _mt ))" -le "$_fresh_s" ] 2>/dev/null && _watched=1
fi
[ "$_watched" = 1 ] || nudge='
(no watcher armed — arm cc-await-ping via Bash run_in_background before idling, or mail waits for your next boundary)'

ctx="$(printf '📬 INBOX — %s new %s from other Claude sessions (delivered as CONTEXT via the non-keystroke inbox channel, never typed into your input line)%s:\n%s\n(Already marked delivered. Triage/act as appropriate; reply to a peer with cc-notify <uuid> "…". This is a message TO you, not something you typed.)%s' \
  "$n" "$plural" "$warn" "$body" "$nudge")"
jq -nc --arg e "$EVENT" --arg c "$ctx" '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}'
exit 0
