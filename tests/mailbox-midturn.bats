#!/usr/bin/env bats
# v3 D5 (mid-turn PostToolUse drain) + D11 (human-visible systemMessage) + the bounded take primitive.
#
# What these pin — the two things v2 could not do:
#   D5  a session inside an hours-long autonomous turn passes NEITHER reliable boundary (SessionStart is
#       once, UserPromptSubmit needs a human), so mail sat for hours WHILE THE SESSION WORKED (R-2; live:
#       the desk on 57 unacked pages for 2 h). PostToolUse is the boundary such a turn actually has.
#       Its whole risk is that it fires on EVERY tool call — so the damping IS the feature, and the cap
#       must be cursor-exact or a bounded drain silently eats the remainder.
#   D11 additionalContext reaches the MODEL only. Every drain must ALSO emit the top-level systemMessage
#       the TUI renders, or a working conversation stays invisible to the human (U-1/U-4).
#
# Harness rules (v1 suite, learned from real escapes):
#   1. `|| false` on EVERY bare [[ ]] — bats does not trap a bare [[ ]] failure mid-body.
#   2. Assert the SPECIFIC value, never a loose glob a degraded result also matches.
# Isolation: CC_MAILBOX_DIR only — never the live ~/.claude/mailbox.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DRAIN="$REPO/hooks/mailbox-drain.sh"
  # Fixture $HOME before anything else. The subject reads it for the wake-armed check and builds the
  # re-arm advisory from it, so an unfixtured run reads the OPERATOR's live state — the empty-inbox
  # nudge assertion would then pass or fail depending on whether a real session happened to have a
  # watcher armed. The lib still resolves from $REPO (mailbox-drain.sh:52 tries its own dir first),
  # so this isolates without detaching the test from the real subject.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  export ITERM_SESSION_ID="w0t0p0:$UUID"
  MBOX="$CC_MAILBOX_DIR/$UUID.md"
  SEEN="$CC_MAILBOX_DIR/$UUID.seen"
  export CC_POSTTOOL_DRAIN_MIN_S=0        # tests drive the rate limit explicitly, never by wall clock
}

seed() { printf '%s\n' "$@" > "$MBOX"; }
lib()  { . "$REPO/hooks/lib/mailbox-pending.sh"; }

# ── D5: the mid-turn boundary exists at all ───────────────────────────────────────────────────────

@test "D5: post-tool drain emits PostToolUse additionalContext (the mid-turn boundary R-2 lacked)" {
  seed "2026-07-25T10:00:00+0000 [reaper] mid-turn page"
  run bash -c 'echo "{}" | "$0" post-tool' "$DRAIN"
  [ "$status" -eq 0 ]
  ev="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
  [ "$ev" = "PostToolUse" ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'mid-turn page'
  [ "$(cat "$SEEN")" -eq 1 ]
}

@test "D5: no pending mail → post-tool exits 0 silently (the every-tool-call common path)" {
  run bash -c 'echo "{}" | "$0" post-tool' "$DRAIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "D5: post-tool advances .seen only — .acked stays put for the guard/Stop-fold (ack_now=0)" {
  seed "one" "two"
  echo '{}' | "$DRAIN" post-tool >/dev/null
  [ "$(cat "$SEEN")" -eq 2 ]
  [ ! -f "$CC_MAILBOX_DIR/$UUID.acked" ]
}

# ── D5 damping: the cap must be CURSOR-EXACT (the drop-shaped failure this whole substrate forbids) ──

@test "D5 cap: only N lines delivered AND the cursor advances by exactly N (remainder deferred, not lost)" {
  seed l1 l2 l3 l4 l5
  CC_POSTTOOL_DRAIN_MAX_LINES=2 bash -c 'echo "{}" | "$0" post-tool' "$DRAIN" > "$BATS_TEST_TMPDIR/o1"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' < "$BATS_TEST_TMPDIR/o1")"
  printf '%s' "$ctx" | grep -q 'l1'
  printf '%s' "$ctx" | grep -q 'l2'
  # the SPECIFIC failure: l3 must NOT have been shown…
  run bash -c "printf '%s' \"\$1\" | grep -q 'l3'" _ "$ctx"
  [ "$status" -ne 0 ]
  # …and must NOT have been marked delivered.
  [ "$(cat "$SEEN")" -eq 2 ]
}

@test "D5 cap: the deferred remainder is NAMED, so a partial drain never reads as 'that was all'" {
  seed l1 l2 l3 l4 l5
  CC_POSTTOOL_DRAIN_MAX_LINES=2 bash -c 'echo "{}" | "$0" post-tool' "$DRAIN" > "$BATS_TEST_TMPDIR/o2"
  jq -r '.hookSpecificOutput.additionalContext' < "$BATS_TEST_TMPDIR/o2" | grep -q '+3 more pending'
}

@test "D5 cap: the NEXT boundary delivers exactly the remainder (deferral is bounded, not a drop)" {
  seed l1 l2 l3 l4 l5
  CC_POSTTOOL_DRAIN_MAX_LINES=2 bash -c 'echo "{}" | "$0" post-tool' "$DRAIN" >/dev/null
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'l3'
  printf '%s' "$ctx" | grep -q 'l5'
  [ "$(cat "$SEEN")" -eq 5 ]
}

@test "D5 rate limit: a second post-tool inside the floor delivers NOTHING and consumes NO cursor" {
  seed a1
  CC_POSTTOOL_DRAIN_MIN_S=3600 bash -c 'echo "{}" | "$0" post-tool' "$DRAIN" >/dev/null   # first: drains
  printf '%s\n' "a2" >> "$MBOX"
  run bash -c 'CC_POSTTOOL_DRAIN_MIN_S=3600; export CC_POSTTOOL_DRAIN_MIN_S; echo "{}" | "$0" post-tool' "$DRAIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$SEEN")" -eq 1 ]          # a2 is still pending — throttled, never marked delivered
}

@test "D5 rate limit: the marker is stamped only on a REAL drain, so an idle burst never holds the floor" {
  # 100 pending-free tool calls under a long floor, THEN mail arrives: it must still drain immediately.
  CC_POSTTOOL_DRAIN_MIN_S=3600 bash -c 'echo "{}" | "$0" post-tool' "$DRAIN" >/dev/null
  [ ! -f "$CC_MAILBOX_DIR/$UUID.posttool" ] || false
  seed "arrives after the idle burst"
  run bash -c 'CC_POSTTOOL_DRAIN_MIN_S=3600; export CC_POSTTOOL_DRAIN_MIN_S; echo "{}" | "$0" post-tool' "$DRAIN"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'arrives after the idle burst'
}

@test "D5: the reliable boundaries are NOT capped (a resume must surface the whole backlog)" {
  seed l1 l2 l3 l4 l5 l6 l7 l8 l9 l10 l11 l12 l13 l14 l15 l16 l17 l18 l19 l20 l21 l22
  CC_POSTTOOL_DRAIN_MAX_LINES=2 bash -c 'echo "{}" | "$0" session-start' "$DRAIN" > "$BATS_TEST_TMPDIR/o3"
  jq -r '.hookSpecificOutput.additionalContext' < "$BATS_TEST_TMPDIR/o3" | grep -q 'l22'
  [ "$(cat "$SEEN")" -eq 22 ]
}

# ── D11: the human sees it ────────────────────────────────────────────────────────────────────────

# NOTE ON EXPECTED WORDING (merge 2026-07-31). D11 shipped ahead of this commit, on trunk, in a
# STRONGER form than the version authored here: the digest suppresses fixture/lifecycle senders and
# points at `cc-mail` rather than `cc-thread --me`. These three tests assert the PROPERTY D11 exists
# for — a delivery is visible to the human, senders are deduped, silence when there is nothing to
# say — against the wording that actually won. Do not "restore" the older strings: they describe an
# implementation that no longer exists.

@test "D11: every drain emits a top-level systemMessage naming count + sender (U-1: success was silent)" {
  seed "2026-07-25T10:00:00+0000 [cc-reaper] a page"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  sm="$(printf '%s' "$output" | jq -r '.systemMessage')"
  printf '%s' "$sm" | grep -q '1 peer message(s)'
  printf '%s' "$sm" | grep -q 'cc-reaper'
  printf '%s' "$sm" | grep -q 'cc-mail'
}

@test "D11: systemMessage carries NO message body (a TUI notice, not a transcript)" {
  seed "2026-07-25T10:00:00+0000 [peer] SECRETPAYLOAD do the thing"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  sm="$(printf '%s' "$output" | jq -r '.systemMessage')"
  run bash -c "printf '%s' \"\$1\" | grep -q 'SECRETPAYLOAD'" _ "$sm"
  [ "$status" -ne 0 ]
}

@test "D11: multiple senders are deduped and listed (whose conversation the human is watching)" {
  seed "2026-07-25T10:00:00+0000 [alpha] one" \
       "2026-07-25T10:00:01+0000 [beta] two"  \
       "2026-07-25T10:00:02+0000 [alpha] three"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  sm="$(printf '%s' "$output" | jq -r '.systemMessage')"
  printf '%s' "$sm" | grep -q '3 peer message(s)'
  [ "$(printf '%s' "$sm" | grep -o 'alpha' | grep -c '')" -eq 1 ]
  printf '%s' "$sm" | grep -q 'beta'
}

@test "D11: the mid-turn channel is human-visible too (D5 without D11 = invisible mail)" {
  seed "2026-07-25T10:00:00+0000 [supervisor] mid-turn"
  run bash -c 'echo "{}" | "$0" post-tool' "$DRAIN"
  printf '%s' "$output" | jq -e '.systemMessage' >/dev/null
  printf '%s' "$output" | jq -r '.systemMessage' | grep -q 'supervisor'
}

@test "D11: no mail ⇒ no systemMessage (the notice fires on delivery, never as ambient noise)" {
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  # NOT `[ -z "$output" ]`: an empty inbox is still a boundary, and since the 2026-07-26 nudge hoist
  # this path legitimately emits additionalContext ("no wake path armed") — the one moment arming is
  # still cheap. The property under test is narrower and survives that: no HUMAN-facing notice fires
  # when there was no delivery. Assert exactly that, so the nudge and the digest stay independent.
  [ -z "$(printf '%s' "$output" | jq -r 'select(has("systemMessage")) | .systemMessage')" ]
}

# ── the bounded primitive itself ──────────────────────────────────────────────────────────────────

@test "mailbox_take_n: max=0 is unlimited — mailbox_take's behaviour is bit-identical (no regression)" {
  seed a b c
  run bash -c ". '$REPO/hooks/lib/mailbox-pending.sh'; mailbox_take_n '$UUID' 0 0"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '')" -eq 3 ]
  [ "$(cat "$SEEN")" -eq 3 ]
}

@test "mailbox_take_n: ack_now=1 still advances BOTH cursors under a cap (reliable-channel contract)" {
  seed a b c d
  lib
  mailbox_take_n "$UUID" 1 2 >/dev/null
  [ "$(cat "$SEEN")" -eq 2 ]
  [ "$(cat "$CC_MAILBOX_DIR/$UUID.acked")" -eq 2 ]
}

@test "mailbox_take_n: a non-numeric max degrades to unlimited, never to zero (fail-open, not silent-drop)" {
  seed a b c
  run bash -c ". '$REPO/hooks/lib/mailbox-pending.sh'; mailbox_take_n '$UUID' 0 'twenty'"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '')" -eq 3 ]
}
