#!/bin/bash
# mailbox-drain.sh — v2 non-keystroke delivery: drain this session's inbox at a SAFE boundary and
# surface it as CONTEXT, never as keystrokes on the live input line.
#
#   mailbox-drain.sh session-start   (SessionStart hook)  → additionalContext
#   mailbox-drain.sh prompt          (UserPromptSubmit)   → additionalContext
#   mailbox-drain.sh stop            (Stop hook)          → decision:block reason (wakes to triage)
#
# The inbox is ~/.claude/mailbox/<own-pane-uuid>.md (append-only, one message per line, written by
# cc-notify). A single line-count cursor <uuid>.seen tracks delivered-vs-pending — SHARED with
# handoff-disposition.sh, so a drain here is exactly what its --ack does. Each message is delivered
# EXACTLY ONCE across all three channels (advance the cursor on delivery); a line appended mid-drain
# stays pending for the next boundary (never lost, never duplicated).
#
# WHY three channels (all non-keystroke):
#   SessionStart      — a resumed/started session picks up mail that landed while it was gone.
#   UserPromptSubmit  — an interactive turn carries pending mail as context alongside the user's prompt.
#   Stop              — an ACTIVE session (or one looping via session-continue, which never re-fires
#                       UserPromptSubmit) is woken to triage at end-of-turn. Stop additionalContext is
#                       empirically INERT on this CC version (boundary-handoff.sh), so Stop uses
#                       decision:block — the same wake session-continue/completion-assert rely on.
# The idle-with-no-turn case is covered by the target's own armed cc-await-ping watcher (which polls
# this same mailbox) + the cc-inbox-guard fail-loud backstop. There is NO keystroke path anywhere here.
#
# FAIL-SAFE: a hook must never cost a session. Missing uuid / jq / mailbox → exit 0 (deliver nothing).
# Every path exits 0 EXCEPT the Stop-block (the intended block). No `set -e` (a Stop hook exiting
# non-2 by accident could false-allow; exiting 2 could false-block — we control exits explicitly).
#
# Env seams (tests): CC_MAILBOX_DIR · CC_DRAIN_BREADCRUMB_TTL · ITERM_SESSION_ID.

MODE="${1:-}"

# ── shared cursor lib (resolve next to this script; repo + symlinked ~/.claude/hooks install) ──
_scd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
_lib="$_scd/lib/mailbox-pending.sh"
[ -f "$_lib" ] || _lib="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh"
[ -f "$_lib" ] || _lib="$HOME/.claude/hooks/lib/mailbox-pending.sh"
# shellcheck source=lib/mailbox-pending.sh
# shellcheck disable=SC1091
. "$_lib" 2>/dev/null || exit 0     # no lib → cannot drain safely → fail-open (guard backstops loss)

command -v jq >/dev/null 2>&1 || exit 0    # jq builds the escaped JSON output; absent → fail-open

# consume stdin (hook JSON) so the writer never SIGPIPEs; we key off $ITERM_SESSION_ID for the pane.
cat >/dev/null 2>&1 || true

own_uuid="${ITERM_SESSION_ID:-}"; own_uuid="${own_uuid##*:}"
case "$own_uuid" in ''|*[!0-9A-Fa-f-]*) exit 0 ;; esac   # not an addressable pane → nothing to drain

MBOX="$(mailbox_file "$own_uuid")"

# ── read the pending window defensively (append-during-drain stays pending) ──
prev="$(mailbox_seen "$own_uuid")"       # clamped to [0, lines]
cur="$(mailbox_lines "$own_uuid")"
pending=$(( cur - prev ))
[ "$pending" -gt 0 ] 2>/dev/null || exit 0    # nothing new → no delivery, no block

# the new line(s) only — cap at `pending` so a line appended after we read `cur` is excluded (it stays
# pending for the next pass), then advance the cursor to `cur` (NOT the post-append EOF).
body="$(tail -n +"$((prev + 1))" "$MBOX" 2>/dev/null | head -n "$pending")"
[ -n "$body" ] || exit 0

human_n="$pending"; plural=$([ "$human_n" = 1 ] && echo message || echo messages)

case "$MODE" in
  session-start|prompt)
    event=$([ "$MODE" = session-start ] && echo SessionStart || echo UserPromptSubmit)
    ctx="$(printf '📬 INBOX — %s new %s from other Claude sessions (delivered as CONTEXT via the non-keystroke inbox channel, never typed into your input line):\n%s\n(Already marked delivered. Triage/act as appropriate; reply to a peer with cc-notify <uuid> "…". This is a message TO you, not something you typed.)' \
      "$human_n" "$plural" "$body")"
    mailbox_advance_seen "$own_uuid" "$cur"
    jq -nc --arg e "$event" --arg c "$ctx" \
      '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}'
    exit 0
    ;;
  stop)
    # Mark the breadcrumb BEFORE advancing the cursor so the other Stop-blockers (which yield on
    # "pending OR recently-drained") make the SAME decision regardless of hook execution order.
    mailbox_mark_draining "$own_uuid"
    mailbox_advance_seen "$own_uuid" "$cur"
    reason="$(printf '📬 INBOX — %s new %s from other Claude sessions arrived while you worked (delivered as CONTEXT, never typed into your input):\n%s\n\nTriage them now, then continue: act on anything actionable, reply to a peer with cc-notify <uuid> "…". These are messages TO you (a reaper/supervisor page, a back-channel ping, a peer). Already marked delivered — do not re-drain.' \
      "$human_n" "$plural" "$body")"
    jq -nc --arg r "$reason" '{decision:"block", reason:$r}'
    exit 0
    ;;
  *)
    # Unknown mode: do nothing but DON'T advance the cursor (we delivered nothing). Fail-open.
    exit 0
    ;;
esac
