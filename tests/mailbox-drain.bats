#!/usr/bin/env bats
# mailbox-drain — v2 non-keystroke delivery. Proves the drain lands mail as CONTEXT (additionalContext
# on prompt/session-start; decision:block on stop), advances the SHARED .seen cursor EXACTLY ONCE, and
# never touches a keystroke transport. Isolated via CC_MAILBOX_DIR + a synthetic ITERM_SESSION_ID.
#
# Harness rules (from tests/cc-notify.bats, learned from real escapes):
#   1. `|| false` on EVERY bare [[ ]] — bats does not trap a [[ ]] failure mid-body.
#   2. Assert the SPECIFIC string, never a loose glob that a degraded result also matches.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DRAIN="$REPO/hooks/mailbox-drain.sh"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  export ITERM_SESSION_ID="w0t0p0:$UUID"
  MBOX="$CC_MAILBOX_DIR/$UUID.md"
  SEEN="$CC_MAILBOX_DIR/$UUID.seen"
}

seed() { printf '%s\n' "$@" > "$MBOX"; }
add()  { printf '%s\n' "$@" >> "$MBOX"; }

# "the drain delivered NOTHING" — no longer spellable as `[ -z "$output" ]`.
#
# Arm-on-open (7f2b85d5) moved the watcher nudge OFF the "mail arrived" path and onto every boundary,
# so an unwatched session now legitimately emits `🔔 No inbox wake path armed.` even when there is
# nothing to deliver. That is the fix working — but it silently inverted four exactly-once assertions
# here from "no mail was surfaced" into "the nudge did not fire", which is a different (and now
# always-false) claim. Assert the absence of the DELIVERY instead, so these tests keep testing the
# cursor and stay indifferent to the nudge.
#
# "as CONTEXT" is the delivery marker the drain pins deliberately (hooks/mailbox-drain.sh renders it
# in every body-bearing payload and the suite above already asserts it) — never a loose glob.
delivered_nothing() { # <output> → 0 iff no mail body was surfaced
  local ctx=""
  [ -n "$1" ] && ctx="$(printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)"
  [ -z "$(printf '%s' "$ctx" | grep -F 'as CONTEXT' || true)" ]
}

@test "prompt drain: pending mail → additionalContext (never keystrokes), cursor advances to EOF" {
  seed "2026-07-20T10:00:00+0000 [reaper] page one" "2026-07-20T10:01:00+0000 [supervisor] page two"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  ev="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
  [ "$ev" = "UserPromptSubmit" ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'page one'
  printf '%s' "$ctx" | grep -q 'page two'
  # delivered as CONTEXT — the payload says so, and there is no keystroke transport involved.
  printf '%s' "$ctx" | grep -q 'as CONTEXT'
  [ "$(cat "$SEEN")" -eq 2 ]
}

@test "exactly-once: a second identical drain delivers NOTHING (cursor already at EOF)" {
  seed "a msg" "b msg"
  echo '{}' | "$DRAIN" prompt >/dev/null
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  delivered_nothing "$output"
  [ "$(cat "$SEEN")" -eq 2 ]     # the named claim: the cursor stayed at EOF, it did not re-deliver
}

@test "session-start drain emits SessionStart additionalContext" {
  seed "resume-time message"
  run bash -c 'echo "{}" | "$0" session-start' "$DRAIN"
  [ "$status" -eq 0 ]
  ev="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
  [ "$ev" = "SessionStart" ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'resume-time message'
}

@test "Stop is NOT handled by the drain (fix B: in-loop delivery folds into session-continue)" {
  seed "mid-turn page"
  run bash -c 'echo "{}" | "$0" stop' "$DRAIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]               # no decision:block here — the standalone Stop blocker is gone
  [ ! -f "$SEEN" ]               # and it did NOT consume the mail (session-continue / watcher will)
}

@test "ack-on-consume: a reliable drain advances ONLY .seen; .acked waits for the Stop fold (no mid-turn loss)" {
  seed "page one" "page two"
  echo '{}' | "$DRAIN" prompt >/dev/null
  [ "$(cat "$SEEN")" -eq 2 ]                          # emitted cursor advanced at the boundary
  [ ! -f "$CC_MAILBOX_DIR/$UUID.acked" ]              # consumed cursor NOT advanced at drain (deferred)
  source "$REPO/hooks/lib/mailbox-pending.sh"
  # the cc-inbox-guard keys on unacked (lines-acked): still 2 right after the drain — the model has not
  # yet provably taken a turn carrying this mail, so a mid-turn death here re-surfaces it (dup, not loss).
  [ "$(CC_MAILBOX_DIR="$CC_MAILBOX_DIR" mailbox_unacked_count "$UUID")" -eq 2 ]
  # the next Stop fold promotes .acked=.seen → unacked drops to 0 (no false alarm on already-consumed mail)
  CC_MAILBOX_DIR="$CC_MAILBOX_DIR" mailbox_promote_acked "$UUID"
  [ "$(cat "$CC_MAILBOX_DIR/$UUID.acked")" -eq 2 ]
  [ "$(CC_MAILBOX_DIR="$CC_MAILBOX_DIR" mailbox_unacked_count "$UUID")" -eq 0 ]
}

@test "append-during-drain: a line added AFTER the count is read stays pending (no loss, no dup)" {
  seed "first" "second"
  # first drain sees 2 → delivers both, cursor=2
  echo '{}' | "$DRAIN" prompt >/dev/null
  [ "$(cat "$SEEN")" -eq 2 ]
  add "third"
  # next drain delivers ONLY the third
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'third'
  printf '%s' "$ctx" | grep -qv 'first' || true
  run bash -c 'printf "%s" "$1" | grep -c "second"' _ "$ctx"
  [ "$output" -eq 0 ]
  [ "$(cat "$SEEN")" -eq 3 ]
}

@test "cursor is byte-consistent with handoff-disposition (--ack writes the SAME value the drain does)" {
  seed "one" "two" "three"
  echo '{}' | "$DRAIN" prompt >/dev/null
  drain_cursor="$(cat "$SEEN")"
  # handoff-disposition --ack computes the cursor the same way (grep -c '') and writes it to .seen
  rm -f "$SEEN"
  CC_MAILBOX_DIR="$CC_MAILBOX_DIR" "$REPO/scripts/handoff-disposition.sh" --session "$UUID" --ack >/dev/null 2>&1 || true
  ack_cursor="$(cat "$SEEN")"
  [ "$drain_cursor" -eq "$ack_cursor" ]
}

@test "rotated mailbox (cursor ahead of EOF) re-delivers rather than swallowing" {
  printf 'only line after rotate\n' > "$MBOX"
  echo "9" > "$SEEN"    # stale cursor beyond EOF (file was truncated + regrown)
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'only line after rotate'
  [ "$(cat "$SEEN")" -eq 1 ]
}

@test "no pane uuid → clean no-op (never errors)" {
  unset ITERM_SESSION_ID
  seed "unreachable"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the drain NEVER invokes a keystroke transport (no it2 on PATH is needed)" {
  seed "context-only delivery"
  # Run with an empty PATH-ish env for it2: if the drain shelled out to it2 it would fail; it must not.
  IT2_BIN=/nonexistent/it2 run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'context-only delivery'
}

# ── v3: succession ADOPTION (D1) + the unwatched wake NUDGE (D4) ──────────────────────────────────

@test "SessionStart ADOPTS a predecessor's unconsumed mail and surfaces it in the SAME boundary" {
  local PRED="BBBBBBBB-1111-2222-3333-444444444444"
  printf 'own line\n'                    > "$CC_MAILBOX_DIR/$UUID.md"
  printf 'inherited 1\ninherited 2\n'    > "$CC_MAILBOX_DIR/$PRED.md"
  printf '%s\n' "$UUID"                  > "$CC_MAILBOX_DIR/$PRED.forward"
  run bash -c "echo '{}' | ITERM_SESSION_ID='w0t0p0:$UUID' '$DRAIN' session-start"
  [ "$status" -eq 0 ]
  local ctx; ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'own line'
  printf '%s' "$ctx" | grep -q '\[forwarded:BBBBBBBB\] inherited 1'
  printf '%s' "$ctx" | grep -q '\[forwarded:BBBBBBBB\] inherited 2'
  printf '%s' "$ctx" | grep -q '3 new messages'      # own + both adopted, ONE delivery
}

@test "adoption is exactly-once — a second SessionStart inherits nothing further" {
  local PRED="BBBBBBBB-1111-2222-3333-444444444444"
  printf 'inherited\n'   > "$CC_MAILBOX_DIR/$PRED.md"
  printf '%s\n' "$UUID"  > "$CC_MAILBOX_DIR/$PRED.forward"
  bash -c "echo '{}' | ITERM_SESSION_ID='w0t0p0:$UUID' '$DRAIN' session-start" >/dev/null
  run bash -c "echo '{}' | ITERM_SESSION_ID='w0t0p0:$UUID' '$DRAIN' session-start"
  [ "$status" -eq 0 ]
  delivered_nothing "$output"                        # nothing left to deliver
  [ "$(grep -c '' "$CC_MAILBOX_DIR/$UUID.md")" -eq 1 ]   # NOT duplicated into our box
}

@test "a .forward pointing at SOMEONE ELSE is not adopted (we take only what names us)" {
  local PRED="BBBBBBBB-1111-2222-3333-444444444444" OTHER="CCCCCCCC-1111-2222-3333-444444444444"
  printf 'not for us\n'   > "$CC_MAILBOX_DIR/$PRED.md"
  printf '%s\n' "$OTHER"  > "$CC_MAILBOX_DIR/$PRED.forward"
  run bash -c "echo '{}' | ITERM_SESSION_ID='w0t0p0:$UUID' '$DRAIN' session-start"
  [ "$status" -eq 0 ]
  delivered_nothing "$output"
  [ "$(grep -c '' "$CC_MAILBOX_DIR/$PRED.md")" -eq 1 ]   # left untouched for its real successor
}

@test "adoption does NOT run on the prompt boundary (one-shot, at session start)" {
  local PRED="BBBBBBBB-1111-2222-3333-444444444444"
  printf 'inherited\n'   > "$CC_MAILBOX_DIR/$PRED.md"
  printf '%s\n' "$UUID"  > "$CC_MAILBOX_DIR/$PRED.forward"
  run bash -c "echo '{}' | ITERM_SESSION_ID='w0t0p0:$UUID' '$DRAIN' prompt"
  [ "$status" -eq 0 ]
  delivered_nothing "$output"
  [ "$(mailbox_acked "$PRED")" -eq 0 ] 2>/dev/null || [ -z "$(cat "$CC_MAILBOX_DIR/$PRED.acked" 2>/dev/null)" ]
}

@test "D4: an UNWATCHED session draining mail gets the arm-a-watcher nudge, exactly once" {
  printf 'a page\n' > "$CC_MAILBOX_DIR/$UUID.md"
  run bash -c "echo '{}' | ITERM_SESSION_ID='w0t0p0:$UUID' '$DRAIN' prompt"
  local ctx; ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'no watcher armed'
  printf '%s' "$ctx" | grep -q 'cc-await-ping'
  [ "$(printf '%s' "$ctx" | grep -c 'no watcher armed')" -eq 1 ]
}

@test "D4: a WATCHED session (fresh .watching heartbeat) gets NO nudge" {
  printf 'a page\n' > "$CC_MAILBOX_DIR/$UUID.md"
  touch "$CC_MAILBOX_DIR/$UUID.watching"
  run bash -c "echo '{}' | ITERM_SESSION_ID='w0t0p0:$UUID' '$DRAIN' prompt"
  local ctx; ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'a page'
  ! printf '%s' "$ctx" | grep -q 'no watcher armed' || false
}

@test "D4: a STALE .watching heartbeat counts as unwatched (a dead watcher is not a wake path)" {
  printf 'a page\n' > "$CC_MAILBOX_DIR/$UUID.md"
  # BACKDATE the heartbeat rather than shrinking the threshold to 0: at CC_WATCH_FRESH_S=0 a
  # just-touched file is still "0s old ≤ 0" and reads as FRESH, so that test would pass for the wrong
  # reason (and pass even if staleness were never checked). A real past mtime is the actual predicate.
  touch "$CC_MAILBOX_DIR/$UUID.watching"
  touch -t 202001010000 "$CC_MAILBOX_DIR/$UUID.watching"
  run bash -c "echo '{}' | ITERM_SESSION_ID='w0t0p0:$UUID' '$DRAIN' prompt"
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'no watcher armed'
}

# ── OPERATOR-VISIBLE systemMessage (2026-07-26) ──────────────────────────────────────────────────
# additionalContext is MODEL-ONLY, so before this the operator saw NOTHING of a 751-msg/12h channel.
# These pin the human-facing line: it must exist, name real senders, and never let fixture noise
# crowd out a real peer report — while additionalContext keeps carrying the full bodies unchanged.

@test "operator line: a peer message emits systemMessage ALONGSIDE additionalContext" {
  seed "2026-07-26T10:00:00+0000 [wt-keystone] Phase 1 landed 1bc02f6f"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  [ "$msg" != "null" ] || false                       # the whole point: the human can see it
  printf '%s' "$msg" | grep -q '1 peer message'
  printf '%s' "$msg" | grep -q 'wt-keystone'
  # …and the model still gets the FULL body, unchanged
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'Phase 1 landed 1bc02f6f'
}

@test "operator line: fixture noise is COUNTED but never NAMED (cannot crowd out a real peer)" {
  seed "2026-07-26T10:00:00+0000 [wt-a] HANDOFF-HUSK-PANE: self-close of fake:BBBB-2222 failed" \
       "2026-07-26T10:00:01+0000 [wt-b] HANDOFF-HUSK-PANE: self-close of fake:CCCC-3333 failed" \
       "2026-07-26T10:00:02+0000 [real-peer] ROOT CAUSE REPRODUCED — the actual finding"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  printf '%s' "$msg" | grep -q '1 peer message'       # only the real one counts as signal
  printf '%s' "$msg" | grep -q 'real-peer'
  printf '%s' "$msg" | grep -q '2 fixture/lifecycle suppressed'
  printf '%s' "$msg" | grep -qv 'wt-a' || true
  [[ "$msg" != *"HANDOFF-HUSK-PANE"* ]] || false      # never reprint fixture bodies at the operator
}

@test "operator line: an all-noise drain says so plainly instead of claiming peer traffic" {
  seed "2026-07-26T10:00:00+0000 [claude] ⚠️ REAPER SURFACE — session x is finished-operator" \
       "2026-07-26T10:00:01+0000 [claude] [desk-sweep] NEW: 1 page(s)"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  printf '%s' "$msg" | grep -q 'no peer traffic'
  printf '%s' "$msg" | grep -q 'cc-mail --all'        # the escape hatch is named, so nothing is lost
}

@test "operator line: senders are deduped and capped — a burst cannot emit a wall of names" {
  seed "2026-07-26T10:00:00+0000 [p1] a" "2026-07-26T10:00:01+0000 [p1] b" \
       "2026-07-26T10:00:02+0000 [p2] c" "2026-07-26T10:00:03+0000 [p3] d" \
       "2026-07-26T10:00:04+0000 [p4] e" "2026-07-26T10:00:05+0000 [p5] f"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  printf '%s' "$msg" | grep -q '6 peer message'       # count is honest…
  [ "$(printf '%s' "$msg" | tr ',' '\n' | grep -c 'p[0-9]')" -le 3 ]   # …names are capped at 3
  [[ "$msg" != *"p5"* ]] || false                     # the cap actually bites
}

@test "operator line: the message is ONE line — it must never bury the operator's own turn" {
  seed "2026-07-26T10:00:00+0000 [peer] a body with
an embedded newline that must not leak into the operator line"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  # `jq -r` prints the literal "null" for a MISSING key, and "null" is ALSO one line — so a
  # line-count assertion alone would pass against a hook that emits no systemMessage at all. Pin
  # presence first, or this test cannot fail (the dead-assertion class this repo runs a ratchet for).
  [ "$msg" != "null" ] || false
  printf '%s' "$msg" | grep -q '📬'
  [ "$(printf '%s' "$msg" | grep -c '')" -eq 1 ]
}

# ── ARM-ON-OPEN (2026-07-26) — the nudge must reach a session whose inbox is EMPTY ───────────────
# The wake nudge used to sit BELOW `[ -n "$body" ] || exit 0`, so it could only fire once mail was
# already pending — i.e. only after a wake had already been missed. The boundary that matters is the
# one where the box is EMPTY and the session is about to idle. Same defect as a WebSocket client that
# subscribes once after its first connect rather than from its on-open handler.
@test "arm-on-open: EMPTY inbox + no watcher ⇒ still nudged, with the exact arm command" {
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [ "$ctx" != "null" ] || false
  printf '%s' "$ctx" | grep -q "cc-await-ping --timeout" || false
  printf '%s' "$ctx" | grep -q 'run_in_background=true' || false
  # NO id (2026-07-31). This asserted `cc-await-ping $UUID` while session-continue.sh asserted its own
  # separately-derived key — two suites each green on a DIFFERENT id for one mechanism, which is how
  # the disagreement survived. An arm command with no id cannot disagree with anything.
  # `! A || false` is the repo's canonical form for "fail if A matches" — what the liveness
  # fixer emits for `A && false`, pinned in both directions by bats-assert-liveness.bats:261-283.
  # It is also correct in FINAL position, where the bare `A && false` returns A's own non-zero
  # status on a MISS and fails the case that should pass.
  ! printf '%s' "$ctx" | grep -qE 'cc-await-ping +[0-9A-Fa-f-]{8}' || false
  true
}

@test "arm-on-open: EMPTY inbox + ARMED watcher ⇒ silent (nothing to say)" {
  printf 'pid=%s\n' "$$" > "$CC_MAILBOX_DIR/$UUID.watching"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || false
}

@test "arm-on-open: EMPTY inbox + a watcher whose pid is DEAD ⇒ nudged (freshness alone is not a wake path)" {
  printf 'pid=999999\n' > "$CC_MAILBOX_DIR/$UUID.watching"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [ "$ctx" != "null" ] || false
  printf '%s' "$ctx" | grep -q 'No inbox wake path armed' || false
}

@test "arm-on-open: the empty-inbox nudge is model-only — no systemMessage per turn" {
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  msg="$(printf '%s' "$output" | jq -r '.systemMessage // "ABSENT"')"
  [ "$msg" = "ABSENT" ] || false   # a per-turn human line would bury the operator's own output
}

@test "RED-PROOF: the pre-fix drain from origin/main emits NOTHING on an empty unwatched inbox" {
  local old="$BATS_TEST_TMPDIR/pre"; mkdir -p "$old"
  git -C "$REPO" archive origin/main hooks | tar -x -C "$old" || skip "origin/main unavailable"
  # An `if` block, NOT `A && skip || false`: the liveness fixer's mechanical `|| false` is correct for
  # `A && <assertion>` but INVERTS `A && skip` — a non-matching grep (the normal case, i.e. the control
  # genuinely IS pre-fix) falls through to `false` and fails the test. skip is control flow, not an
  # assertion, so it needs a branch rather than a short-circuit.
  if grep -q 'HOISTED ABOVE THE EMPTY-INBOX EXIT' "$old/hooks/mailbox-drain.sh"; then
    skip "control is not pre-fix"
  fi
  run bash -c 'echo "{}" | "$0" prompt' "$old/hooks/mailbox-drain.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || false        # RED: the arm nudge was unreachable with an empty box
}
