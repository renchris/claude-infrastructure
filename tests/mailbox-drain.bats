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
  # ── HERMETIC $HOME (2026-08-07) ──────────────────────────────────────────────────────────────
  # Un-grandfathers this suite from rule 1 of scripts/test-hermeticity-lint.sh; that ratchet's
  # DOWNWARD half requires the allowlist line to be deleted in this same commit, or the lint reds.
  #
  # Three seams in the subject default under $HOME, and CC_MAILBOX_DIR masks only the first two:
  #   hooks/lib/mailbox-pending.sh:101  _mbx_dir()   → $HOME/.claude/mailbox
  #   hooks/mailbox-drain.sh:107        _mdir        → $HOME/.claude/mailbox
  #   hooks/mailbox-drain.sh:224        _armcmd      → $HOME/.claude/bin/cc-await-ping  ← UNMASKED
  # plus scripts/handoff-disposition.sh:52-54 (MAILBOX_DIR/SESSIONS_BIN/TASKS_DIR), which the
  # cursor-parity test below executes.
  #
  # Stated honestly: today the leak is LATENT, not verdict-bearing — the suite was measured 27/27
  # green under BOTH the live and the fixtured $HOME, so this closes a seam rather than a red. That
  # is the point of a pin (the lint's own rule-5 note: "converts 'latent' into 'cannot'"). The one
  # UNMASKED seam is what makes it more than paperwork: the arm command this suite pins is built
  # from live $HOME, so without the fixture the string under assertion is the operator's, and any
  # future test that forgets CC_MAILBOX_DIR reads and MUTATES the operator's real mailbox.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/bin"
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

# ── GOAL-AWARE NAG (2026-08-10) — never instruct the arm that disables a LIVE /goal ──────────────
# CC skips /goal evaluation at any Stop where a non-terminal background Bash exists
# (docs/research/goal-in-handoff-2026-08-08.md § RESOLVED). The cc-await-ping arm this nag used to
# hand every unwatched session is exactly such a task — so with a goal live, the nudge must WARN
# AGAINST arming, and must not carry a pasteable arm command at all.
#
# ── C7 FLIP (2026-08-16, goal-safe-2way-comms §4) ────────────────────────────────────────────────
# "No arm command at all" was the 08-10 contract and it is now the wrong one: it left the goal-armed
# session with no idle mode, i.e. in the SPIN pole (90 unmet evaluations over an unchanged world).
# The nudge must still refuse the PARKED form and must now name the IDLE-SCOPED one — with the sid,
# because an arm that cannot name its session is refused at the tool. The pair of assertions below
# is the discrimination: the denied spelling absent, the admitted spelling present.

@test "goal-aware: LIVE /goal ⇒ the nudge refuses the PARKED arm and teaches the idle-scoped one" {
  T="$BATS_TEST_TMPDIR/goal-t.jsonl"
  printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"finish the rollout"}}\n' > "$T"
  run bash -c 'printf "{\"transcript_path\":\"%s\",\"session_id\":\"abc-123-def\"}" "$1" | "$0" prompt' "$DRAIN" "$T"
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [ "$ctx" != "null" ] || false
  printf '%s' "$ctx" | grep -q 'do NOT park the ordinary 4-hour watcher' || false
  # the DENIED spelling must never appear — the chokepoint refuses it, so instructing it would hand
  # the model a command its own guard rejects
  ! printf '%s' "$ctx" | grep -q 'cc-await-ping --timeout' || false
  # …and the ADMITTED one must, carrying THIS session's id (without it the tool refuses, exit 6)
  printf '%s' "$ctx" | grep -q 'cc-await-ping --idle-scoped --sid abc-123-def' || false
}

@test "goal-aware: no session_id ⇒ the nudge says so rather than emitting a form the tool refuses" {
  T="$BATS_TEST_TMPDIR/goal-t.jsonl"
  printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"finish the rollout"}}\n' > "$T"
  run bash -c 'printf "{\"transcript_path\":\"%s\"}" "$1" | "$0" prompt' "$DRAIN" "$T"
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q -- "--sid <this session's id>" || false
}

@test "goal-aware DISCRIMINATOR: a MET goal restores the ordinary arm nudge (last record wins)" {
  T="$BATS_TEST_TMPDIR/goal-t.jsonl"
  { printf '{"type":"attachment","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"finish"}}\n'
    printf '{"type":"attachment","attachment":{"type":"goal_status","met":true,"condition":"finish","iterations":1}}\n'
  } > "$T"
  run bash -c 'printf "{\"transcript_path\":\"%s\"}" "$1" | "$0" prompt' "$DRAIN" "$T"
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'run_in_background=true' || false
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

# ── W2 CUSTODY — THE PING-RECEIPT DISCHARGER (custody v1.1, item d29b73103189) ────────────────────
# WHAT IS PINNED: a received `HANDOFF-PING <slug>: …` discharges the originator's OPEN custody row
# for that slug, scoped to the originator's OWN cwd; both slug-LESS ping shapes discharge nothing;
# the kill switch and the cheap gate leave the store untouched; and both channels (model context +
# operator systemMessage) report the discharge.
#
# HERMETICITY: CC_CUSTODY_DIR is pinned explicitly rather than relying on the fixtured $HOME above.
# cc-custody's store defaults under $HOME, so the fixture alone would do — but this suite's own
# header records why that is not the standard to hold: the seam that bites is the UNMASKED one, and
# a store that a test can WRITE to is exactly the class of seam worth pinning by name.
custody_setup() {
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  CUSTODY="$REPO/bin/cc-custody"
  ORIG_CWD="$BATS_TEST_TMPDIR/originator"; mkdir -p "$ORIG_CWD"
  OTHER_CWD="$BATS_TEST_TMPDIR/other"; mkdir -p "$OTHER_CWD"
}
# Drive the drain with a stdin payload naming the originator's cwd — the field handoff-fire keyed
# `cc-custody open` on, and the one the discharger reads.
drain_at() { # $1 = cwd → runs `prompt` mode with that cwd in the payload
  bash -c 'printf "{\"cwd\":\"%s\"}" "$1" | "$0" prompt' "$DRAIN" "$1"
}

@test "custody: a HANDOFF-PING carrying a slug DISCHARGES the originator's open row for that cwd" {
  custody_setup
  "$CUSTODY" open --cwd "$ORIG_CWD" --target 77 --marker M-PING-1 --slug wave5 --notify-back "$UUID"
  [ "$("$CUSTODY" count --open --cwd "$ORIG_CWD")" = 1 ]
  seed "2026-08-13T10:00:00+0000 [peer] HANDOFF-PING wave5: landed 9da394a9c, self-closing"
  run drain_at "$ORIG_CWD"
  [ "$status" -eq 0 ]
  [ "$("$CUSTODY" count --open --cwd "$ORIG_CWD")" = 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'custody: 1 dispatched session(s) DISCHARGED' || false
  printf '%s' "$ctx" | grep -q 'wave5' || false
  # the OPERATOR half — a ledger state change must not be model-only (the v3 D11 rule this suite
  # already enforces for delivery itself).
  msg="$(printf '%s' "$output" | jq -r '.systemMessage')"
  printf '%s' "$msg" | grep -q 'custody −1' || false
}

@test "custody CONTROL: the SAME slug open under a DIFFERENT cwd is NOT discharged (scoping)" {
  custody_setup
  "$CUSTODY" open --cwd "$OTHER_CWD" --target 78 --marker M-PING-2 --slug wave5
  seed "2026-08-13T10:00:00+0000 [peer] HANDOFF-PING wave5: done"
  run drain_at "$ORIG_CWD"
  [ "$status" -eq 0 ]
  # a slug is a prompt-file basename, so two originators can collide on one; discharging store-wide
  # would silently drop THIS cwd's custody, which is the failure direction the store designs against.
  [ "$("$CUSTODY" count --open --cwd "$OTHER_CWD")" = 1 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  ! printf '%s' "$ctx" | grep -q 'DISCHARGED' || false
}

@test "custody: the two slug-LESS ping shapes discharge NOTHING (no join key exists to discharge on)" {
  custody_setup
  "$CUSTODY" open --cwd "$ORIG_CWD" --target 79 --marker M-PING-3 --slug wave7
  # `HANDOFF-PING:` (cc-await-ping's bare shape) and sc_announce_before_retire's `(auto, …)` — both
  # belong to the self-close path, which discharges by MARKER, so neither needs a key here.
  seed "2026-08-13T10:00:00+0000 [peer] HANDOFF-PING: landed 9da394a9c, self-closing" \
       "2026-08-13T10:01:00+0000 [peer] HANDOFF-PING (auto, unannounced retire): peer 79 is retiring NOW."
  run drain_at "$ORIG_CWD"
  [ "$status" -eq 0 ]
  [ "$("$CUSTODY" count --open --cwd "$ORIG_CWD")" = 1 ]
}

@test "custody: a slug with NO open row leaves the store untouched and says nothing (rc 0, quiet)" {
  custody_setup
  "$CUSTODY" open --cwd "$ORIG_CWD" --target 80 --marker M-PING-4 --slug wave8
  seed "2026-08-13T10:00:00+0000 [peer] HANDOFF-PING wave-that-was-never-fired: done"
  run drain_at "$ORIG_CWD"
  [ "$status" -eq 0 ]
  [ "$("$CUSTODY" count --open --cwd "$ORIG_CWD")" = 1 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'as CONTEXT' || false     # the mail itself still delivered
  ! printf '%s' "$ctx" | grep -q 'DISCHARGED' || false
}

@test "custody KILL SWITCH: CC_DRAIN_CUSTODY_RETURN=0 delivers the mail and discharges nothing" {
  custody_setup
  "$CUSTODY" open --cwd "$ORIG_CWD" --target 81 --marker M-PING-5 --slug wave9
  seed "2026-08-13T10:00:00+0000 [peer] HANDOFF-PING wave9: done"
  CC_DRAIN_CUSTODY_RETURN=0 run drain_at "$ORIG_CWD"
  [ "$status" -eq 0 ]
  [ "$("$CUSTODY" count --open --cwd "$ORIG_CWD")" = 1 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'as CONTEXT' || false
}

@test "custody: ordinary peer mail (no HANDOFF-PING) never reaches the discharger" {
  custody_setup
  "$CUSTODY" open --cwd "$ORIG_CWD" --target 82 --marker M-PING-6 --slug wave10
  seed "2026-08-13T10:00:00+0000 [supervisor] wave10 is looking good"
  run drain_at "$ORIG_CWD"
  [ "$status" -eq 0 ]
  [ "$("$CUSTODY" count --open --cwd "$ORIG_CWD")" = 1 ]
}

@test "custody: dup-biased re-delivery cannot double-count — a second ping is an rc-0 no-op" {
  custody_setup
  "$CUSTODY" open --cwd "$ORIG_CWD" --target 83 --marker M-PING-7 --slug wave11
  seed "2026-08-13T10:00:00+0000 [peer] HANDOFF-PING wave11: done"
  run drain_at "$ORIG_CWD"
  [ "$("$CUSTODY" count --open --cwd "$ORIG_CWD")" = 0 ]
  add "2026-08-13T10:05:00+0000 [peer] HANDOFF-PING wave11: done (re-surfaced dup)"
  run drain_at "$ORIG_CWD"
  [ "$status" -eq 0 ]
  [ "$("$CUSTODY" count --open --cwd "$ORIG_CWD")" = 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  ! printf '%s' "$ctx" | grep -q 'DISCHARGED' || false   # already discharged ⇒ nothing to report
}

@test "RED-PROOF: the pre-v1.1 drain from origin/main leaves an open custody row OPEN on a ping" {
  custody_setup
  local old="$BATS_TEST_TMPDIR/pre-custody"; mkdir -p "$old"
  git -C "$REPO" archive origin/main hooks | tar -x -C "$old" || skip "origin/main unavailable"
  if grep -q 'cc-custody' "$old/hooks/mailbox-drain.sh"; then
    skip "control is not pre-v1.1"
  fi
  "$CUSTODY" open --cwd "$ORIG_CWD" --target 84 --marker M-PING-8 --slug wave12
  seed "2026-08-13T10:00:00+0000 [peer] HANDOFF-PING wave12: landed, self-closing"
  run bash -c 'printf "{\"cwd\":\"%s\"}" "$1" | "$0" prompt' "$old/hooks/mailbox-drain.sh" "$ORIG_CWD"
  [ "$status" -eq 0 ]
  # RED: the peer reported, the originator read the report, and the debt stayed on the books —
  # 🔧 forever, because self-close was the only discharge path custody v1 had.
  [ "$("$CUSTODY" count --open --cwd "$ORIG_CWD")" = 1 ]
}

@test "custody: the cloud ping shape (a slug carrying '/') discharges — the charset admits it" {
  custody_setup
  # scripts/cloud-return.sh wakes the originator with `HANDOFF-PING cloud/<id>: …` and records that
  # same namespaced token as the custody key, so the slug charset has to admit `/` or the whole
  # off-box return path is undischargeable from the drain.
  "$CUSTODY" open --cwd "$ORIG_CWD" --target 90 --marker M-PING-9 --slug cloud/session_test
  seed "2026-08-13T10:00:00+0000 [cloud] HANDOFF-PING cloud/session_test: LANDED+VERIFIED on main"
  run drain_at "$ORIG_CWD"
  [ "$status" -eq 0 ]
  [ "$("$CUSTODY" count --open --cwd "$ORIG_CWD")" = 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'cloud/session_test' || false
}
