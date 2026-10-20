#!/usr/bin/env bats
# migration 0072 — retire the async SessionStart registration of pre-session-validate.sh (Wave 6 item
# 6.6a of docs/research/startup-hooks-2026-10-18/README.md). c10: staged for the operator, never
# self-run, and held out of scripts/c10-batch.sh (applied alone). Pins: nothing is written without
# --confirm; both spellings are matched through cmd_bare; only that hook goes (its group keeps the rest);
# every account stays LINKED; a second run changes nothing; a forked fleet is refused untouched.
#
# Hermetic: $HOME is a fixture; the real bin/cc-settings-parity runs over fixture account dirs through
# its CC_PARITY_DIRS seam, so nothing reads the operator's config.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_SETTINGS_PARITY_BIN CC_PARITY_CANONICAL CC_PARITY_ACCOUNTS_JSON CC_MIGRATION_STATE
  mkdir -p "$HOME/.claude/bin"
  ln -s "$REPO_ROOT/bin/cc-settings-parity" "$HOME/.claude/bin/cc-settings-parity"
  S="$HOME/.claude/settings.json"
  # shellcheck disable=SC2088  # the literal "~/" is what settings.json stores
  fixture '~/.claude/hooks/pre-session-validate.sh'
  CC_PARITY_DIRS=""
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$S" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
  M="$REPO_ROOT/migrations/0072-retire-pre-session-validate.sh"
}

fixture() { # <spelling of the pre-session-validate command>
  jq -n --arg p "$1" '{env:{A:"1"}, hooks:{
    SessionStart:[{hooks:[{type:"command",command:"~/.claude/hooks/session-start-dispatch.sh",timeout:20},
                          {type:"command",command:$p,timeout:10,async:true},
                          {type:"command",command:"~/.claude/hooks/lead-crash-watchdog.sh",timeout:10,async:true}]},
                  {matcher:"startup",hooks:[{type:"command",command:"~/.claude/hooks/dod-persist.sh",timeout:5}]}],
    Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/pre-session-validate.sh",timeout:5}]}]}}' \
    > "$S"
}
psv_count() { jq '[.hooks.SessionStart[].hooks[] | select(.command | test("pre-session-validate"))] | length' "$S"; }

@test "c10 with a --confirm run line, held out of the batch as manual" {
  grep -q '^# migration-class: c10' "$M"
  grep -q '^# migration-run: bash .*0072-retire-pre-session-validate.sh --confirm settings.json' "$M"
  grep -q '^# migration-batch-hold: manual' "$M"
}

@test "no --confirm ⇒ nothing written (bare, --dry-run, --check)" {
  before="$(cat "$S")"
  run bash "$M"; [ "$status" -eq 2 ]
  run bash "$M" --dry-run; [ "$status" -eq 0 ]; [[ "$output" == *"DRY RUN"* ]] || false
  run bash "$M" --check; [ "$status" -eq 0 ]; [[ "$output" == *"CHECK ok"* ]] || false
  [ "$(cat "$S")" = "$before" ]
}

@test "verify discriminates: false before, true after" {
  run bash "$M" --verify; [ "$status" -ne 0 ]
  run bash "$M" --confirm settings.json; [ "$status" -eq 0 ]
  run bash "$M" --verify; [ "$status" -eq 0 ]
}

@test "verify on a missing settings.json is not applied" {
  rm "$S"
  run bash "$M" --verify; [ "$status" -ne 0 ]
}

@test "bare spelling: only that hook goes; its group, other groups, other events and env stay; links survive" {
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ]
  [ "$(psv_count)" -eq 0 ]
  # shellcheck disable=SC2088  # the literal "~/" is what settings.json stores
  [ "$(jq -r '.hooks.SessionStart[0].hooks | map(.command) | join(",")' "$S")" = \
    "~/.claude/hooks/session-start-dispatch.sh,~/.claude/hooks/lead-crash-watchdog.sh" ]
  [ "$(jq -r '.hooks.SessionStart[1].matcher' "$S")" = startup ]
  # shellcheck disable=SC2088  # the literal "~/" is what settings.json stores
  [ "$(jq -r '.hooks.Stop[0].hooks[0].command' "$S")" = "~/.claude/hooks/pre-session-validate.sh" ]
  [ "$(jq -r .env.A "$S")" = 1 ]
  [ ! -L "$S" ]
  for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ]; done
  ls "$HOME"/.claude/backups/retire-pre-session-validate-0072-*/settings.json >/dev/null
}

@test "interpreter spelling (/bin/bash ~/…, post-0070) is matched through cmd_bare" {
  fixture '/bin/bash ~/.claude/hooks/pre-session-validate.sh'
  run bash "$M" --verify; [ "$status" -ne 0 ]
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ]
  [ "$(psv_count)" -eq 0 ]
  [ "$(jq '.hooks.SessionStart[0].hooks | length' "$S")" -eq 2 ]
}

@test "a group holding only the retired hook is dropped; others are untouched" {
  jq '.hooks.SessionStart += [{hooks:[{type:"command",command:"/bin/bash ~/.claude/hooks/pre-session-validate.sh"}]}]' "$S" > "$S.t" && cat "$S.t" > "$S"
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.SessionStart | length' "$S")" -eq 2 ]
  [ "$(psv_count)" -eq 0 ]
}

@test "a second run changes nothing" {
  run bash "$M" --confirm settings.json; [ "$status" -eq 0 ]
  after="$(cat "$S")"
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ]; [[ "$output" == *"already applied"* ]] || false
  [ "$(cat "$S")" = "$after" ]
}

@test "a forked fleet is refused untouched" {
  rm "$HOME/.claude-next/settings.json"; cp "$S" "$HOME/.claude-next/settings.json"
  jq '.env.B = "2"' "$HOME/.claude-next/settings.json" > "$BATS_TEST_TMPDIR/x" && cat "$BATS_TEST_TMPDIR/x" > "$HOME/.claude-next/settings.json"
  before="$(cat "$S")"
  run bash "$M" --confirm settings.json
  [ "$status" -eq 3 ]
  [ "$(cat "$S")" = "$before" ]
}
