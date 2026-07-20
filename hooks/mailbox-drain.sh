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
# boundaries, so a delivery here is immediately ack'd (mailbox_take …1) — the guard need never chase it.
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

# LOCKED atomic take on a RELIABLE boundary → advance both cursors (ack_now=1). Body on stdout; rc 1 =
# nothing new; rc 2 = delivered-but-cursor-write-failed (still surface the body — better a dup next turn
# than a drop; the re-deliver is bounded and the guard sees the un-advanced .acked).
body="$(mailbox_take "$own_uuid" 1)"; rc=$?
[ -n "$body" ] || exit 0        # rc 1: nothing pending

n="$(printf '%s\n' "$body" | grep -c '')"; plural=$([ "$n" = 1 ] && echo message || echo messages)
warn=""; [ "$rc" = 2 ] && warn=' (⚠ cursor write failed — you may see this again; that is a dup, not a loss)'
ctx="$(printf '📬 INBOX — %s new %s from other Claude sessions (delivered as CONTEXT via the non-keystroke inbox channel, never typed into your input line)%s:\n%s\n(Already marked delivered. Triage/act as appropriate; reply to a peer with cc-notify <uuid> "…". This is a message TO you, not something you typed.)' \
  "$n" "$plural" "$warn" "$body")"
jq -nc --arg e "$EVENT" --arg c "$ctx" '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}'
exit 0
