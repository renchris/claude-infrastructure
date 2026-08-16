#!/usr/bin/env bats
# Phase 3 — handoff-fire.sh --notify-back: the back-channel trailer.
#
# Exercised through `handoff-fire.sh --dry-run` with an explicit --launcher (which
# skips account ranking / claude-accounts / git / iTerm2 — fully side-effect-free).
# TMPDIR is pointed at the bats temp dir so the materialized prompt COPIES auto-clean.

setup() {
  # M11 pins — see fire-autonomy.bats. The "--launcher makes this fully side-effect-free"
  # note above was true of iTerm2/git/accounts but NOT of the capacity gate, which sits
  # upstream of all of them: at load 41.72/10 cores this suite went 8-of-9 RED on a
  # pristine tree. It also went GREEN once in three runs on the same tree, so the
  # failure presents as flake — a single green run is NOT evidence of health here.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  PF="$BATS_TEST_TMPDIR/prompt.md"
  printf 'ORIGINAL PROMPT BODY\nline two\n' > "$PF"
  export TMPDIR="$BATS_TEST_TMPDIR"
}

# extract the "copy: <path>)" the dry-run prints on its notify-back line
copy_of() { printf '%s\n' "$1" | sed -n 's/.*copy: \([^)]*\)).*/\1/p'; }

# extract the prompt path the composed `command:` line reads via "$(cat <path>)"
cmd_prompt_of() { printf '%s\n' "$1" | sed -n 's/.*cat \([^)]*\)).*/\1/p'; }

@test "--notify-back <uuid>: trailer copy carries the cc-notify ping recipe with that UUID" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000001" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test \
    --notify-back 1234ABCD-5678-90EF-1234-567890ABCDEF --dry-run
  [ "$status" -eq 0 ]
  copy="$(copy_of "$output")"
  [ -n "$copy" ]; [ -f "$copy" ]
  grep -q 'cc-notify 1234ABCD-5678-90EF-1234-567890ABCDEF "HANDOFF-PING' "$copy"
  grep -q 'ORIGINAL PROMPT BODY' "$copy"        # the copy preserves the original body first
}

@test "--notify-back NEVER mutates the caller's prompt file" {
  before="$(shasum "$PF" | awk '{print $1}')"
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000001" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test \
    --notify-back 1234ABCD-5678-90EF-1234-567890ABCDEF --dry-run
  [ "$status" -eq 0 ]
  after="$(shasum "$PF" | awk '{print $1}')"
  [ "$before" = "$after" ]
  copy="$(copy_of "$output")"
  [ "$copy" != "$PF" ]                          # trailer went to a distinct copy
}

@test "--notify-back (bare) defaults to the firing pane UUID from \$ITERM_SESSION_ID" {
  run env ITERM_SESSION_ID="w3t0p1:CAFEBABE-0000-0000-0000-000000000009" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --notify-back --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'originator CAFEBABE-0000-0000-0000-000000000009'
  copy="$(copy_of "$output")"
  grep -q 'cc-notify CAFEBABE-0000-0000-0000-000000000009' "$copy"
}

@test "--notify-back (bare) honors --session-id over \$ITERM_SESSION_ID" {
  run env ITERM_SESSION_ID="w3t0p1:AAAAAAAA-0000-0000-0000-000000000001" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test \
    --session-id BBBBBBBB-0000-0000-0000-000000000002 --notify-back --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'originator BBBBBBBB-0000-0000-0000-000000000002'
}

@test "--notify-back (bare) with no \$ITERM_SESSION_ID and no UUID errors (exit 1)" {
  run env -u ITERM_SESSION_ID \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --notify-back --dry-run
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'ITERM_SESSION_ID and no UUID'
}

@test "trailer documents the v2 inbox transport (no keystrokes, no hand-written mailbox files)" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000003" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --notify-back --dry-run
  [ "$status" -eq 0 ]
  copy="$(copy_of "$output")"
  grep -q 'v2 INBOX transport' "$copy"          # names the transport
  grep -q 'NO keystrokes' "$copy"               # the v1 composer-inject claim is gone for good
  ! grep -q 'r submit, not' "$copy" || false    # the \r-not-\n note is historical (v2 plan Phase 3)
  grep -q 'do NOT hand-write mailbox files' "$copy"  # the "durable fallback" invitation is gone
}

@test "--no-self-retire --no-notify-back: no trailer at all, original prompt used as-is" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000004" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --no-self-retire --no-notify-back --dry-run
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q 'notify-back:' || false
  printf '%s\n' "$output" | grep -qF "cat $PF"  # command reads the original prompt directly
}

# --- back-channel is OPT-OUT (2026-08-08) -------------------------------------------------------
# Was opt-in. Measured over 7 days: 8 of 301 real fires carried a back-channel, so a surviving
# originator routinely had no completion signal and leads hand-wrote git-poll loops with GUESSED
# commit counts. These four tests pin the new default and each of its three escapes.

@test "default fire: back-channel trailer added with NO flag, addressed to the firing pane" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000005" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'originator AAAAAAAA-0000-0000-0000-000000000005'
  copy="$(cmd_prompt_of "$output")"
  [ -n "$copy" ]; [ -f "$copy" ]
  [ "$copy" != "$PF" ]                                        # a distinct copy, never the caller's file
  grep -q 'cc-notify AAAAAAAA-0000-0000-0000-000000000005 "HANDOFF-PING' "$copy"
  grep -q 'SELF-RETIRE' "$copy"                               # both trailers coexist
  grep -q 'ORIGINAL PROMPT BODY' "$copy"                      # original body preserved first
}

@test "--no-notify-back opts out but KEEPS self-retire" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-00000000000A" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --no-notify-back --dry-run
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q 'notify-back:' || false
  copy="$(cmd_prompt_of "$output")"
  [ -n "$copy" ]; [ -f "$copy" ]
  ! grep -q 'HANDOFF-PING' "$copy" || false                   # no back-channel
  grep -q 'SELF-RETIRE' "$copy"                               # self-retire is a separate opt-out
}

# THE REGRESSION THIS DEFAULT COULD HAVE CAUSED. A headless fire (launchd/cron) has no firing pane,
# so the defaulted BACK_SID cannot resolve. Before this test the same code path exit-1'd — which
# would have broken every scheduled fire on the box the moment the default landed.
@test "defaulted back-channel with no firing pane DEGRADES (exit 0), does not error" {
  run env -u ITERM_SESSION_ID \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'back-channel: SKIPPED'
  ! printf '%s\n' "$output" | grep -q 'notify-back:' || false
}

@test "EXPLICIT --notify-back with no firing pane still hard-errors (degrade is default-only)" {
  run env -u ITERM_SESSION_ID \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --notify-back --dry-run
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'ITERM_SESSION_ID and no UUID'
  ! printf '%s\n' "$output" | grep -q 'back-channel: SKIPPED' || false
}

# THE ADDRESS MUST BE ONE cc-notify CAN RESOLVE, not merely one payload-lint accepts. Measured
# 2026-08-08: `cc-notify 776` → verdict=unresolvable, `cc-notify wt-cc-005655-99631-776` →
# verdict=delivered. A bare kitty pane id passed F3 for a few hours and would have sent every fired
# peer's announce into nothing — silently, which is the exact W5 root the back-channel exists to
# prevent. cc-notify resolves --role → friendly NAME (cc-registry) → raw pane UUID.
@test "a NON-uuid pane id is addressed by its REGISTRY NAME, not the bare id" {
  mkdir -p "$BATS_TEST_TMPDIR/reg"
  printf '{"paneUUID":"776","name":"wt-probe-776","cwd":"/tmp"}\n' > "$BATS_TEST_TMPDIR/reg/776.json"
  run env ITERM_SESSION_ID="w0t0p0:776" CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'originator wt-probe-776'
  copy="$(cmd_prompt_of "$output")"
  grep -q 'cc-notify wt-probe-776 "HANDOFF-PING' "$copy"
  ! grep -qE 'cc-notify 776( |")' "$copy" || false      # never the bare id — it does not resolve
}

@test "a NON-uuid pane id with NO registry row STANDS DOWN (never emits a dead address)" {
  mkdir -p "$BATS_TEST_TMPDIR/emptyreg"
  run env ITERM_SESSION_ID="w0t0p0:999" CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/emptyreg" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --dry-run
  [ "$status" -eq 0 ]                                    # degrades, never fails the fire
  printf '%s\n' "$output" | grep -q 'back-channel: SKIPPED'
  ! printf '%s\n' "$output" | grep -q 'notify-back:' || false
}

@test "--recycle: self-retire AND back-channel auto-excluded (the recycled pane IS the continuation)" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-000000000006" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --recycle --dry-run
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q 'handoff-prompt-nb' || false # no trailer copy made — original used as-is
  ! printf '%s\n' "$output" | grep -q 'notify-back:' || false # no originator distinct from this pane
}

# ── W2 CUSTODY — the SELF-RETIRE restriction lifted (custody v1.1, item d29b73103189) ────────────
# handoff-fire's `cc-custody open` used to also require WANT_SELF_RETIRE=1. The reason (review #5)
# was sound at the time: a --no-self-retire peer writes no fired-peer stamp ⇒ carries no marker ⇒
# can never reach the self-close discharge, so its row would be deterministically stale, and "not
# recorded" beat "recorded unretirably". hooks/mailbox-drain.sh now discharges on the HANDOFF-PING
# itself, keyed on the SLUG — so what these two cases pin is the JOIN that makes the lift safe:
# every fire that arms a back-channel hands its peer a ping recipe carrying that same slug,
# self-retiring or not. Without that, the lift would just re-create the stale rows review #5 refused.
@test "custody join: a --no-self-retire fire STILL carries a slug-bearing HANDOFF-PING recipe" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-0000000000C1" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --no-self-retire \
    --notify-back 1234ABCD-5678-90EF-1234-567890ABCDEF --dry-run
  [ "$status" -eq 0 ]
  copy="$(copy_of "$output")"
  [ -n "$copy" ]; [ -f "$copy" ]
  # the slug is `basename` of the prompt file sans extension — the exact token cc-custody `open`
  # records as --slug, and the exact token the drain greps out of the received ping.
  grep -q 'cc-notify 1234ABCD-5678-90EF-1234-567890ABCDEF "HANDOFF-PING prompt:' "$copy"
  ! grep -q 'SELF-RETIRE' "$copy" || false      # the peer genuinely will not self-close
}

@test "custody join CONTROL: --no-notify-back arms no ping, and is the case that opens no row" {
  run env ITERM_SESSION_ID="w1t0p0:AAAAAAAA-0000-0000-0000-0000000000C2" \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --no-self-retire --no-notify-back --dry-run
  [ "$status" -eq 0 ]
  copy="$(cmd_prompt_of "$output")"
  [ -n "$copy" ]; [ -f "$copy" ]
  # NB_ARMED_TARGET is empty here, which is exactly the guard the custody `open` still tests: no
  # back-channel ⇒ no return was ever owed ⇒ no debt to record. A one-way fire is not a lost wave.
  ! grep -q 'HANDOFF-PING' "$copy" || false
}

@test "custody open: the guard tests only 'was a return owed', never self-retire (with RED control)" {
  # A source pin, deliberately: the call site sits inside the engagement-confirmed branch, which
  # cannot be reached without a real iTerm2 spawn (tests/handoff-fire-failed-cleanup.bats states the
  # same constraint and extracts functions for the same reason). The BEHAVIOURAL half of this change
  # is the join pinned above; this half pins that the guard actually stopped excluding those fires.
  guard="$(grep -n 'NB_ARMED_TARGET:-' "$HF" | grep 'SPAWNED_PANE' | head -1)"
  [ -n "$guard" ] || { echo "custody open guard not found in $HF"; false; }
  ! printf '%s' "$guard" | grep -q 'WANT_SELF_RETIRE' \
    || { echo "still gated on self-retire: $guard"; false; }
  # RED control: the same line pre-fix DOES gate on it, so this assertion is falsifiable rather
  # than merely satisfied by a grep that matches nothing.
  #
  # 🚨 A LITERAL SHA, NEVER origin/main. This control replayed `origin/main:scripts/handoff-fire.sh`,
  # and that ref ADVANCES past this very fix the moment it lands — after which the control compares
  # the fix to itself, the marker grep stops matching, and the `skip` below turned that into a
  # PERMANENTLY VACUOUS pass. It is also why this commit could never land: moving-ref-control-lint
  # refuses a control the land itself changes, so every re-land attempt hit the same gate, pinned a
  # new refs/land/failed/<ts>-…-31568-1 and minted another blocked re-land row — ~11 of them on
  # 2026-08-16 alone. 764f96963 is 0c48b3cb0^, the immutable parent of this fix; it cannot move.
  #
  # THE MARKER'S POLARITY IS INVERTED HERE, deliberately, because this fix is a REMOVAL. The lint's
  # stock advice is "an identifier the FIX introduced must be ABSENT from the replay"; the symmetric
  # proof for a deletion is that the identifier the fix DELETED is PRESENT in the replay. Derived
  # from the measured diff of 764f96963..0c48b3cb0 on that line, never from prose: the guard read
  # `… && [ "${WANT_SELF_RETIRE:-0}" = 1 ]` before and drops that clause after.
  #
  # AND IT FAILS RATHER THAN SKIPS. Against a moving ref a skip was arguably defensible — the
  # artifact could legitimately drift. Against a literal sha the artifact is immutable, so a missing
  # marker can only mean the control itself is broken, and skipping would hide exactly the breakage
  # this block exists to expose (memory: control-calibrated-to-implementation-decays).
  old="$(git -C "$REPO" show 764f96963:scripts/handoff-fire.sh 2>/dev/null \
         | grep 'NB_ARMED_TARGET:-' | grep 'SPAWNED_PANE' | head -1)"
  [ -n "$old" ] || { echo "control unrecoverable: 764f96963:scripts/handoff-fire.sh has no NB_ARMED_TARGET/SPAWNED_PANE guard line"; false; }
  printf '%s' "$old" | grep -q 'WANT_SELF_RETIRE' \
    || { echo "control is not pre-v1.1 — 764f96963 must still gate on WANT_SELF_RETIRE: $old"; false; }
}
