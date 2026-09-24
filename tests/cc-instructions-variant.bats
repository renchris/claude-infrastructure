#!/usr/bin/env bats
# cc-instructions-variant — the operator's switch for the instructions A/B arm.
#
# Pins the contract the A/B depends on: `set` registers the arm, re-points the account's CLAUDE.md
# through the real mirror and reads the link back; `reset` restores the shared file; every switch is
# logged so a census can split sessions by arm; a missing variant or unknown account changes nothing.
# Hermetic: scratch HOME with its own accounts.json and the repo's mirror lib linked in.

setup() {
  unset CC_BATS_ACTIVE
  export HOME="$BATS_TEST_TMPDIR/home"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLI="$REPO/bin/cc-instructions-variant"
  mkdir -p "$HOME/.claude/lib" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"
  ln -s "$REPO/lib/config-mirror.zsh" "$HOME/.claude/lib/config-mirror.zsh"
  printf 'full rules\n' > "$HOME/.claude/CLAUDE.md"
  printf 'slim rules\n' > "$HOME/.claude/CLAUDE.slim.md"
  printf '{"accounts":[{"name":"next3","config_dir":"~/.claude-tertiary"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  ln -s "$HOME/.claude/CLAUDE.md" "$HOME/.claude-tertiary/CLAUDE.md"
  ln -s "$HOME/.claude/CLAUDE.md" "$HOME/.claude-quaternary/CLAUDE.md"
  mkdir -p "$HOME/.claude/rules"
  ln -s "$HOME/.claude/rules" "$HOME/.claude-tertiary/rules"
  ln -s "$HOME/.claude/rules" "$HOME/.claude-quaternary/rules"
}

@test "set: registers the arm, re-points CLAUDE.md and rules/, logs the switch" {
  run "$CLI" set next3 slim
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.claude-tertiary/CLAUDE.md")" = "$HOME/.claude/CLAUDE.slim.md" ]
  [ "$(readlink "$HOME/.claude-tertiary/rules")" = "$HOME/.claude/rules.slim" ]
  grep -qx '.claude-tertiary slim' "$HOME/.claude/instruction-variants"
  grep -q '"account":".claude-tertiary","variant":"slim","action":"set"' "$HOME/.claude/autonomy/instruction-variants.jsonl"
  [ "$(readlink "$HOME/.claude-quaternary/CLAUDE.md")" = "$HOME/.claude/CLAUDE.md" ]
  [ "$(readlink "$HOME/.claude-quaternary/rules")" = "$HOME/.claude/rules" ]
}

@test "reset: back to the shared file, line removed, switch logged" {
  "$CLI" set next3 slim
  run "$CLI" reset next3
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.claude-tertiary/CLAUDE.md")" = "$HOME/.claude/CLAUDE.md" ]
  [ "$(readlink "$HOME/.claude-tertiary/rules")" = "$HOME/.claude/rules" ]
  run grep -q 'claude-tertiary' "$HOME/.claude/instruction-variants"
  [ "$status" -ne 0 ]
  grep -q '"action":"reset"' "$HOME/.claude/autonomy/instruction-variants.jsonl"
}

@test "set with an undeployed variant refuses and changes nothing" {
  run "$CLI" set next3 nosuch
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/.claude/instruction-variants" ]
  [ "$(readlink "$HOME/.claude-tertiary/CLAUDE.md")" = "$HOME/.claude/CLAUDE.md" ]
}

@test "an unknown account is a usage error" {
  run "$CLI" set nextX slim
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/.claude/instruction-variants" ]
}

@test "status shows each account's arm and the deployed variants" {
  "$CLI" set next3 slim
  run "$CLI" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '^\.claude-tertiary +slim '
  echo "$output" | grep -Eq '^\.claude-quaternary +shared '
  echo "$output" | grep -q 'variants available: slim'
}

@test "status: a variant derived from the current CLAUDE.md is in sync; an edit to CLAUDE.md makes it STALE" {
  local h; h="$(shasum -a 256 "$HOME/.claude/CLAUDE.md" | cut -c1-16)"
  printf '<!-- instructions-variant: slim · derived-from CLAUDE.global.md sha256:%s -->\nslim rules\n' "$h" \
    > "$HOME/.claude/CLAUDE.slim.md"
  run "$CLI" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CLAUDE.slim.md: in sync with CLAUDE.md ($h)"
  printf 'full rules, edited\n' > "$HOME/.claude/CLAUDE.md"
  run "$CLI" status
  echo "$output" | grep -q "CLAUDE.slim.md: STALE, derived from $h"
}
