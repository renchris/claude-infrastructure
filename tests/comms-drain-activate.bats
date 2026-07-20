#!/usr/bin/env bats
# 07-comms-drain-activate.sh — the C10 operator script that wires the 2-way-comms mailbox-drain hooks
# into the LIVE per-account settings.json. These tests run ONLY against temp settings.json fixtures
# (CC_CONFIG_DIRS / CC_LIVE_DIR seams) — never the live ~/.claude* files, which are the operator's step.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/docs/activation/pending-activation/07-comms-drain-activate.sh"
  A="$BATS_TEST_TMPDIR/cfg-a"
  B="$BATS_TEST_TMPDIR/cfg-b"
  LIVE="$BATS_TEST_TMPDIR/live"
  mkdir -p "$A" "$B" "$LIVE"
  # A realistic-shaped settings.json: both hook keys already carry an unrelated group.
  fixture "$A"
  fixture "$B"
}

fixture() {
  cat > "$1/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/session-start.sh", "timeout": 10 } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "~/.claude/hooks/memory-nudge.sh", "timeout": 5 } ] }
    ]
  }
}
JSON
}

# Run the activation script against the fixture dirs only.
act() { CC_CONFIG_DIRS="$A $B" CC_LIVE_DIR="$LIVE" CC_REPO="$REPO" run bash "$S" "$@"; }

drain_count() { # $1=file $2=hook key
  jq "[.hooks.$2[]?.hooks[]?.command? // empty] | map(select(contains(\"mailbox-drain\"))) | length" "$1"
}

@test "dry run (no CONFIRM) changes nothing and says so" {
  before="$(cat "$A/settings.json")"
  act
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'dry run'
  [ "$before" = "$(cat "$A/settings.json")" ]
  [ ! -f "$A/settings.json.pre-comms-drain.bak" ]
}

@test "CONFIRM=1 wires every fixture dir: result parses and carries BOTH drain entries" {
  CONFIRM=1 act
  [ "$status" -eq 0 ]
  for d in "$A" "$B"; do
    jq empty "$d/settings.json"
    [ "$(drain_count "$d/settings.json" SessionStart)" -eq 1 ]
    [ "$(drain_count "$d/settings.json" UserPromptSubmit)" -eq 1 ]
    jq -e '[.hooks.SessionStart[]?.hooks[]?.command?] | any(contains("mailbox-drain.sh session-start"))' "$d/settings.json"
    jq -e '[.hooks.UserPromptSubmit[]?.hooks[]?.command?] | any(contains("mailbox-drain.sh prompt"))' "$d/settings.json"
  done
}

@test "the wired entries are copied VERBATIM from settings.example.json" {
  CONFIRM=1 act
  T="$REPO/settings-templates/settings.example.json"
  want="$(jq -cS 'first(.hooks.SessionStart[]?.hooks[]? | select(.command? // "" | contains("mailbox-drain.sh session-start")))' "$T")"
  got="$(jq -cS 'first(.hooks.SessionStart[]?.hooks[]? | select(.command? // "" | contains("mailbox-drain.sh session-start")))' "$A/settings.json")"
  [ "$want" = "$got" ]
}

@test "append never overwrites the pre-existing sibling groups" {
  CONFIRM=1 act
  jq -e '[.hooks.SessionStart[]?.hooks[]?.command?] | any(contains("session-start.sh"))' "$A/settings.json"
  jq -e '[.hooks.UserPromptSubmit[]?.hooks[]?.command?] | any(contains("memory-nudge.sh"))' "$A/settings.json"
}

@test "a backup is written before the edit and restores the pre-wired state" {
  CONFIRM=1 act
  [ -f "$A/settings.json.pre-comms-drain.bak" ]
  [ "$(drain_count "$A/settings.json.pre-comms-drain.bak" SessionStart)" -eq 0 ]
}

@test "IDEMPOTENT: a second run skips every dir and adds nothing twice" {
  CONFIRM=1 act
  after_first="$(cat "$A/settings.json")"
  CONFIRM=1 act
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'already wired'
  printf '%s' "$output" | grep -q 'wired:   0'
  [ "$after_first" = "$(cat "$A/settings.json")" ]
  [ "$(drain_count "$A/settings.json" SessionStart)" -eq 1 ]
  [ "$(drain_count "$A/settings.json" UserPromptSubmit)" -eq 1 ]
}

@test "malformed settings.json → RESTORE + nonzero, the file is byte-identical" {
  printf '{ "hooks": { "SessionStart": [ ' > "$B/settings.json"   # truncated JSON
  before="$(cat "$B/settings.json")"
  CONFIRM=1 act
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'RESTORED'
  [ "$before" = "$(cat "$B/settings.json")" ]
  ! grep -q 'mailbox-drain' "$B/settings.json"
}

@test "a settings.json with no .hooks at all is wired cleanly (not corrupted)" {
  echo '{"model":"opus"}' > "$B/settings.json"
  CC_CONFIG_DIRS="$B" CC_LIVE_DIR="$LIVE" CC_REPO="$REPO" CONFIRM=1 run bash "$S"
  [ "$status" -eq 0 ]
  jq -e '.model == "opus"' "$B/settings.json"
  [ "$(drain_count "$B/settings.json" SessionStart)" -eq 1 ]
  [ "$(drain_count "$B/settings.json" UserPromptSubmit)" -eq 1 ]
}

@test "--rollback restores every backup and drops the drain lines" {
  CONFIRM=1 act
  act --rollback
  [ "$status" -eq 0 ]
  for d in "$A" "$B"; do
    ! grep -q 'mailbox-drain' "$d/settings.json"
    [ ! -f "$d/settings.json.pre-comms-drain.bak" ]
    jq -e '[.hooks.SessionStart[]?.hooks[]?.command?] | any(contains("session-start.sh"))' "$d/settings.json"
  done
}

@test "step 0 creates the per-file symlinks the wired path depends on" {
  CONFIRM=1 act
  for rel in hooks/mailbox-drain.sh hooks/lib/mailbox-pending.sh bin/cc-inbox-guard; do
    [ -L "$LIVE/$rel" ]
    [ "$(readlink "$LIVE/$rel")" = "$REPO/$rel" ]
    [ -e "$LIVE/$rel" ]
  done
}

@test "a dir-symlinked hooks/ is detected and left alone" {
  ln -s "$REPO/hooks" "$LIVE/hooks"
  CONFIRM=1 act
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'dir-symlink'
  [ -L "$LIVE/hooks" ]
}

@test "a dir with no settings.json is not created or wired" {
  empty="$BATS_TEST_TMPDIR/no-settings"
  mkdir -p "$empty"
  CC_CONFIG_DIRS="$A $empty" CC_LIVE_DIR="$LIVE" CC_REPO="$REPO" CONFIRM=1 run bash "$S"
  [ "$status" -eq 0 ]
  [ ! -e "$empty/settings.json" ]
}

@test "a template PREDATING the 2-way-comms commit → nonzero + names the ff-sync fix" {
  fake="$BATS_TEST_TMPDIR/oldrepo"
  mkdir -p "$fake/settings-templates"
  echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"~/.claude/hooks/session-start.sh"}]}]}}' \
    > "$fake/settings-templates/settings.example.json"
  CC_CONFIG_DIRS="$A" CC_LIVE_DIR="$LIVE" CC_REPO="$fake" CONFIRM=1 run bash "$S"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'no mailbox-drain entry'
  printf '%s' "$output" | grep -q 'merge --ff-only origin/main'
  ! grep -q 'mailbox-drain' "$A/settings.json"
}

@test "the live ~/.claude* settings are NEVER touched by this suite" {
  # Guard the guard: the script must refuse to run with no template rather than fall back to defaults.
  CC_CONFIG_DIRS="$A" CC_LIVE_DIR="$LIVE" CC_REPO="$BATS_TEST_TMPDIR/nope" CONFIRM=1 run bash "$S"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'template not found'
  ! grep -q 'mailbox-drain' "$A/settings.json"
}
