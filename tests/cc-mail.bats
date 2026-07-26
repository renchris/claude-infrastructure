#!/usr/bin/env bats
# cc-mail — the OPERATOR read surface for cross-session mail.
#
# WHY THIS SUITE EXISTS: cc-mail is the only human-facing view of the mailbox substrate, so its
# FILTERS are load-bearing — a filter that silently drops a real message is worse than no reader at
# all (the operator would believe they had seen everything). Every test below pins a filter against
# a fixture mailbox and asserts BOTH directions: the thing that must appear, and the thing that must
# not. The noise suppression in particular is asserted reversible (--all), because a default that
# hides real mail with no way back is how a reader becomes a liar.
#
# Isolation: CC_MAILBOX_DIR + CC_REGISTRY_DIR redirect the two stores; $HOME is fixtured per the
# hermeticity ratchet so nothing here can read or write the operator's live layer.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CM="$REPO/bin/cc-mail"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"; mkdir -p "$CC_MAILBOX_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"
  export COLUMNS=400

  NOW="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  OLD="$(date -v-5H '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || date -d '5 hours ago' '+%Y-%m-%dT%H:%M:%S%z')"
  PANE="AAAAAAAA-1111-2222-3333-444444444444"

  cat > "$CC_MAILBOX_DIR/$PANE.md" <<EOF
$NOW [wt-peer-1] REAL-SIGNAL alpha the land is green
$NOW [wt-peer-2] HANDOFF-HUSK-PANE: self-close of fake:BBBB-2222 typed /exit successfully
$NOW [claude] ⚠️ REAPER SURFACE — session x is finished-operator
$OLD [wt-peer-3] REAL-SIGNAL bravo from five hours ago
not a mailbox line at all
EOF

  cat > "$CC_REGISTRY_DIR/$PANE.json" <<EOF
{"paneUUID":"$PANE","name":"wt-friendly-name","cwd":"/tmp/x","account":"claude-next"}
EOF
}

@test "default: shows real signal from inside the window" {
  run bash "$CM" --since 2h
  [ "$status" -eq 0 ]
  [[ "$output" == *"REAL-SIGNAL alpha"* ]] || false
}

@test "default: SUPPRESSES husk-pane fixture spam" {
  run bash "$CM" --since 2h
  [[ "$output" != *"HANDOFF-HUSK-PANE"* ]] || false
}

@test "default: suppresses routine reaper surfaces too" {
  run bash "$CM" --since 2h
  [[ "$output" != *"REAPER SURFACE"* ]] || false
}

@test "--all makes the suppression REVERSIBLE (a hidden message is always reachable)" {
  run bash "$CM" --since 2h --all
  [[ "$output" == *"HANDOFF-HUSK-PANE"* ]] || false
  [[ "$output" == *"REAPER SURFACE"* ]] || false
}

@test "the default run TELLS the operator that noise was suppressed (never silent)" {
  run bash "$CM" --since 2h
  [[ "$output" == *"noise suppressed"* ]] || false
}

@test "--since bounds the window: a 5h-old message is out of a 2h window" {
  run bash "$CM" --since 2h
  [[ "$output" != *"REAL-SIGNAL bravo"* ]] || false
}

@test "--since widens correctly: 12h reaches the 5h-old message" {
  run bash "$CM" --since 12h
  [[ "$output" == *"REAL-SIGNAL bravo"* ]] || false
}

@test "pane UUID is resolved to its friendly registry name" {
  run bash "$CM" --since 2h
  [[ "$output" == *"wt-friendly-name"* ]] || false
}

@test "--from filters by sender" {
  run bash "$CM" --since 12h --from wt-peer-3
  [[ "$output" == *"bravo"* ]] || false
  [[ "$output" != *"alpha"* ]] || false
}

@test "--grep filters by body text" {
  run bash "$CM" --since 12h --grep alpha
  [[ "$output" == *"alpha"* ]] || false
  [[ "$output" != *"bravo"* ]] || false
}

@test "--pane filters by recipient, matching the friendly name too" {
  run bash "$CM" --since 2h --pane wt-friendly-name
  [[ "$output" == *"REAL-SIGNAL alpha"* ]] || false
  run bash "$CM" --since 2h --pane NO-SUCH-PANE
  [[ "$output" != *"REAL-SIGNAL alpha"* ]] || false
}

@test "--count reports volume and emits NO message bodies" {
  run bash "$CM" --since 12h --count
  [ "$status" -eq 0 ]
  [[ "$output" == *"signal"* ]] || false
  [[ "$output" != *"REAL-SIGNAL alpha"* ]] || false
}

@test "a malformed line is skipped, never fatal" {
  run bash "$CM" --since 12h
  [ "$status" -eq 0 ]
  [[ "$output" != *"not a mailbox line at all"* ]] || false
}

@test "an absent mailbox dir exits 3 with a reason, never a silent empty success" {
  CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/nope" run bash "$CM"
  [ "$status" -eq 3 ]
  [[ "$output" == *"no mailbox dir"* ]] || false
}

@test "an unknown option exits 2 (fail-closed parser, never ignored)" {
  run bash "$CM" --bogus-option
  [ "$status" -eq 2 ]
}

@test "--help prints usage and exits 0" {
  run bash "$CM" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"cc-mail"* ]] || false
}

@test "an empty RESULT says so plainly instead of printing nothing" {
  run bash "$CM" --since 12h --grep zzz-matches-nothing-zzz
  [ "$status" -eq 0 ]
  [[ "$output" == *"no signal mail"* ]] || false
}

@test "an empty result still reports the noise it suppressed (so 'nothing' is never ambiguous)" {
  # Distinguishing 'no mail arrived' from 'mail arrived but I hid it' is the whole point of a
  # reader the operator trusts: a bare 'nothing' would read as silence on a busy channel.
  run bash "$CM" --since 2h --grep zzz-matches-nothing-zzz
  [[ "$output" == *"no signal mail"* ]] || false
}

@test "hermeticity: a run does not create or write the operator's live mailbox" {
  run bash "$CM" --since 12h
  [ ! -e "$HOME/.claude/mailbox" ] || false
}
