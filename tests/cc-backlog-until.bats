#!/usr/bin/env bats
# cc-backlog `block --until "<probe>"` — reboot-resume R2 (docs/research/reboot-resume-2026-10-21/
# REPORT.md item 2; contract in docs/plans/REBOOT_RESUME_PERFECTION_2026-10-21.md).
#
# An ARMING probe: exit 0 means the block's precondition has arrived, and the restore classifier
# wakes the row's session (kind `unblocked`). It is a field of its own, `until`, because the only
# existing probe field, `falsifier`, CLOSES the row on exit 0 — the row would vanish at the moment it
# became actionable (docs/lessons/arming-and-mootness-cannot-share-one-falsifier.md).
#
# Pinned: the field survives the fold's whitelist into `list --json`; it is absent (not "") when not
# given; it never lands in `falsifier`; a re-block without it drops it; other verbs refuse it.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  P=/repo/until-suite
  PROBE='sw_vers -productVersion | grep -q "^15\.8\.1"'
}

row_json() { bash "$CB" list --all --json | jq -c --arg i "$1" 'map(select(.id==$i)) | first // empty'; }
new_row() { bash "$CB" add --title "wait for the OS update $RANDOM" --project "$P" --why-not-now "not-yet-true: macOS 15.8.1 not installed" 2>/dev/null | tail -1; }

@test "block --until stores field 'until', carried by list --json beside the session" {
  id="$(new_row)"; [[ "$id" =~ ^[0-9a-f]{12}$ ]] || { echo "add gave: $id"; false; }
  run bash "$CB" block "$id" --needs "not-yet-true: macOS 15.8.1 installed" --class not-yet-true \
      --session s-owner-1 --until "$PROBE"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(row_json "$id" | jq -r '.status')" = blocked ] || false
  [ "$(row_json "$id" | jq -r '.until')" = "$PROBE" ] || { row_json "$id"; false; }
  [ "$(row_json "$id" | jq -r '.session')" = s-owner-1 ] || false
  # the raw record carries it too, under its own key
  grep -F '"until":' "$CC_BACKLOG_FILE" | grep -q '"event":"block"' || false
}

@test "--until NEVER lands in falsifier: an arming probe must not close the row" {
  id="$(new_row)"
  bash "$CB" block "$id" --needs "not-yet-true: macOS 15.8.1 installed" --class not-yet-true --until "true" >/dev/null 2>&1
  [ "$(row_json "$id" | jq -r 'has("falsifier")')" = false ] || { row_json "$id"; false; }
  ! grep -q '"falsifier"' "$CC_BACKLOG_FILE" || false
  [ "$(row_json "$id" | jq -r '.status')" = blocked ] || false   # a passing probe did not close it
}

@test "no --until: the key is ABSENT from list --json (old rows keep working)" {
  id="$(new_row)"
  bash "$CB" block "$id" --needs "not-yet-true: macOS 15.8.1 installed" --class not-yet-true >/dev/null 2>&1
  [ "$(row_json "$id" | jq -r 'has("until")')" = false ] || { row_json "$id"; false; }
}

@test "a re-block without --until drops the old probe (it belongs to the CURRENT block)" {
  id="$(new_row)"
  bash "$CB" block "$id" --needs "not-yet-true: macOS 15.8.1 installed" --class not-yet-true --until "$PROBE" >/dev/null 2>&1
  [ "$(row_json "$id" | jq -r 'has("until")')" = true ] || false
  bash "$CB" block "$id" --needs "not-yet-true: macOS 16 installed" --class not-yet-true --force >/dev/null 2>&1
  [ "$(row_json "$id" | jq -r 'has("until")')" = false ] || { row_json "$id"; false; }
}

@test "block --until on a row with NO session stamps the blocking session; a row that names one keeps it" {
  id="$(new_row)"
  CLAUDE_CODE_SESSION_ID=s-blocker-9 bash "$CB" block "$id" --needs "not-yet-true: macOS 15.8.1 installed" \
    --class not-yet-true --until "$PROBE" >/dev/null 2>&1
  [ "$(bash "$CB" list --blocked --json | jq -r --arg i "$id" 'map(select(.id==$i)) | first | .session')" = s-blocker-9 ] || { row_json "$id"; false; }
  [ "$(bash "$CB" list --blocked --json | jq -r --arg i "$id" 'map(select(.id==$i)) | first | .until')" = "$PROBE" ] || false
  # re-blocked by ANOTHER session: the row already names its owner, so the owner stays
  CLAUDE_CODE_SESSION_ID=s-other-2 bash "$CB" block "$id" --needs "not-yet-true: macOS 15.8.1 installed" \
    --class not-yet-true --until "$PROBE" --force >/dev/null 2>&1
  [ "$(row_json "$id" | jq -r '.session')" = s-blocker-9 ] || { row_json "$id"; false; }
  # without --until nothing is stamped (the ambient id is not attribution on its own)
  id2="$(new_row)"
  CLAUDE_CODE_SESSION_ID=s-blocker-9 bash "$CB" block "$id2" --needs "not-yet-true: macOS 16 installed" --class not-yet-true >/dev/null 2>&1
  [ "$(row_json "$id2" | jq -r 'has("session")')" = false ] || { row_json "$id2"; false; }
}

@test "--until on any verb but block is refused, never silently ignored" {
  id="$(new_row)"
  run bash "$CB" claim "$id" --until "true"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"--until applies only to block"* ]] || false
}
