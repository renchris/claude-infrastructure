#!/usr/bin/env bats
# 8370af320af5 — the report counts LIVE sessions' inboxes as dead-pane boxes.
#
# A mailbox box key is written in one of TWO identity spaces. cc-notify addresses panes, so many boxes
# are keyed by a pane id; the session registry also carries a `session_id`, and boxes exist under that
# too. comms-strand-report.sh adjudicated every box against ONE list — `it2 session list --json`, which
# returns pane ids only — so every session-uuid-keyed box was unmatched and counted dead.
#
# Measured on the live store 2026-08-17, before the fix: 544 boxes, 10 live, 534 dead,
# dead_never_surfaced 14873. Cross-checking the registry, EIGHT currently-live sessions had a
# session_id-keyed box and all eight were in the dead pile — including the session running the check.
# Under kitty the two spaces are not even the same shape (pane ids read `102`, `131`), so the match
# could not have succeeded by luck.
#
# The second defect is the one that let it stand: the positive control asked whether THIS PANE's id was
# in the pane list. It is, so the control passed — while being blind to the only axis that fails. A
# control has to be independent of the thing it is certifying, so this file pins the registry axis too:
# an unreadable registry now refuses to report, because with it unread every uuid-keyed box is
# fabricated-dead and the fabrication IS the headline number.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_MAILBOX_DIR="$HOME/.claude/mailbox"
  mkdir -p "$CC_MAILBOX_DIR" "$HOME/.claude/bin"
  RPT="$REPO/scripts/comms-strand-report.sh"
  SID="9f1c2d3e-4a5b-6c7d-8e9f-0a1b2c3d4e5f"   # a live session's session_id
  DEADSID="11112222-3333-4444-5555-666677778888"
  export CC_PANE_ID=131                         # pin the control's own-pane leg; never inherit the real one
  export CC_STRAND_FIXTURE_RE='^(ZZZZZZZZ)-'    # do not let the default fixture filter eat our uuids
}

_stub_it2() { # <json>
  { echo '#!/bin/bash'; printf 'cat <<"J"\n%s\nJ\n' "$1"; } > "$HOME/.claude/bin/it2"
  chmod +x "$HOME/.claude/bin/it2"
}
_stub_sessions() { # <json>   (empty string ⇒ an unreadable registry)
  if [ -z "$1" ]; then
    { echo '#!/bin/bash'; echo 'exit 1'; } > "$HOME/.claude/bin/cc-sessions"
  else
    { echo '#!/bin/bash'; printf 'cat <<"J"\n%s\nJ\n' "$1"; } > "$HOME/.claude/bin/cc-sessions"
  fi
  chmod +x "$HOME/.claude/bin/cc-sessions"
}
PANES='[{"id":"131"},{"id":"102"}]'
REG() { printf '[{"paneUUID":"131","name":"recycle-11-131","session_id":"%s"}]' "$SID"; }

@test "a LIVE session's session_id-keyed box is NOT counted dead (the measured defect)" {
  printf '2026-08-17T10:00:00-0700 [peer] hello\n' > "$CC_MAILBOX_DIR/$SID.md"
  _stub_it2 "$PANES"; _stub_sessions "$(REG)"
  run /bin/bash "$RPT" --json
  [ "$status" -ne 3 ]
  [ "$(printf '%s' "$output" | jq -r '.live_boxes')" -eq 1 ]
  [ "$(printf '%s' "$output" | jq -r '.dead_boxes')" -eq 0 ]
}

@test "REMOVE HALF: a session_id the registry does NOT list still counts dead (not a blanket live)" {
  printf '2026-08-17T10:00:00-0700 [peer] stranded\n' > "$CC_MAILBOX_DIR/$DEADSID.md"
  _stub_it2 "$PANES"; _stub_sessions "$(REG)"
  run /bin/bash "$RPT" --json
  [ "$status" -ne 3 ]
  [ "$(printf '%s' "$output" | jq -r '.dead_boxes')" -eq 1 ]
  [ "$(printf '%s' "$output" | jq -r '.live_boxes')" -eq 0 ]
}

@test "REGRESSION: the pane-id axis still resolves — a pane-keyed box stays live" {
  printf '2026-08-17T10:00:00-0700 [peer] hello\n' > "$CC_MAILBOX_DIR/131.md"
  _stub_it2 "$PANES"; _stub_sessions "$(REG)"
  run /bin/bash "$RPT" --json
  [ "$(printf '%s' "$output" | jq -r '.live_boxes')" -eq 1 ]
}

@test "CONTROL ON THE BLIND AXIS: an unreadable session registry REFUSES to report numbers" {
  # without it, every uuid-keyed box is fabricated-dead — the same class of fabrication the pane-list
  # refusal already exists to prevent, one identity space over.
  printf '2026-08-17T10:00:00-0700 [peer] hello\n' > "$CC_MAILBOX_DIR/$SID.md"
  _stub_it2 "$PANES"; _stub_sessions ''
  run /bin/bash "$RPT" --json
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q '"verdict":"unknown"' || false
}

@test "CONTROL ON THE BLIND AXIS: a registry that does not know THIS pane refuses too" {
  # a readable registry describing some other machine is not an oracle for this one.
  printf '2026-08-17T10:00:00-0700 [peer] hello\n' > "$CC_MAILBOX_DIR/$SID.md"
  _stub_it2 "$PANES"
  _stub_sessions '[{"paneUUID":"999","name":"elsewhere","session_id":"aaaabbbb-cccc-dddd-eeee-ffff00001111"}]'
  run /bin/bash "$RPT" --json
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q '"verdict":"unknown"' || false
}

@test "ALARM POLARITY: with both oracles healthy the report still reports (the stricter control did not become an always-refuse)" {
  printf '2026-08-17T10:00:00-0700 [peer] hello\n' > "$CC_MAILBOX_DIR/$SID.md"
  _stub_it2 "$PANES"; _stub_sessions "$(REG)"
  run /bin/bash "$RPT" --json
  [ "$status" -ne 3 ]
  printf '%s' "$output" | grep -q '"verdict":"ok"' || false
}
