#!/usr/bin/env bats
# migrations/0014 — register hooks/subagent-stop.sh as a SubagentStop hook (backlog 7ea31ffa1a08).
#
# THE ARM THAT CREDITS THIS CHANGE is "PRE-FIX CONTROL": the migration file does not exist on
# origin/main, so that test RED-s there. Everything else asserts behaviour of a file that is only
# introduced by this diff.
#
# The interesting risk here is NOT "does it write" — it is the two ways a registration migration
# reads green while doing nothing: skipping every dir because the array it tests for is absent
# everywhere (which is why the discriminator is the Stop array, not SubagentStop), and registering a
# path that does not execute. Both get their own arm.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/migrations/0014-subagent-stop-registration.sh"

  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_CLAUDE_DIR="$HOME/.claude"
  mkdir -p "$HOME/.claude/hooks"
  # the subject must be executable or the migration must refuse — see the refusal arm
  printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/hooks/subagent-stop.sh"
  chmod +x "$HOME/.claude/hooks/subagent-stop.sh"

  # shellcheck disable=SC2088  # the UNEXPANDED tilde is the subject under test — CC expands it at
  # hook-run time, and expanding it here would assert this machine's $HOME instead of the contract
  HOOK_CMD='~/.claude/hooks/subagent-stop.sh'
}

# fleet_config <dir> — a settings.json shaped like a real one: a populated Stop array, no
# SubagentStop array (the measured live state in all five dirs on 2026-08-17).
fleet_config() {
  mkdir -p "$1"
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/session-continue.sh",timeout:5}]}]}}' \
    > "$1/settings.json"
}

registered() { # <settings.json>
  jq -e --arg c "$HOOK_CMD" \
    '[.hooks.SubagentStop[]?.hooks[]?.command] | any(. == $c)' "$1" >/dev/null 2>&1
}

@test "PRE-FIX CONTROL: the migration exists and declares its class and verify" {
  [ -f "$SUT" ]
  grep -q '^# migration-class: c10' "$SUT"
  grep -q '^# migration-verify:' "$SUT"
  grep -q '^# migration-subject:' "$SUT"
}

@test "creates the SubagentStop array where none existed — the whole live state today" {
  fleet_config "$HOME/.claude"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  registered "$HOME/.claude/settings.json"
}

@test "the declared migration-verify command actually passes after the run" {
  # A migration whose own verify does not clear is reported unverifiable forever.
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run jq -e '[.hooks.SubagentStop[]?.hooks[]?.command] | any(. == "~/.claude/hooks/subagent-stop.sh")' \
    "$CC_CLAUDE_DIR/settings.json"
  [ "$status" -eq 0 ]
}

@test "writes EVERY fleet config dir, not just the primary" {
  for d in .claude .claude-next .claude-secondary .claude-tertiary .claude-quaternary; do
    fleet_config "$HOME/$d"
  done
  run bash "$SUT"
  [ "$status" -eq 0 ]
  for d in .claude .claude-next .claude-secondary .claude-tertiary .claude-quaternary; do
    registered "$HOME/$d/settings.json"
  done
}

@test "ANTI-VACUOUS ARM: it does not skip every dir for lack of a SubagentStop array" {
  # If the fleet-config discriminator were "has a SubagentStop array" it would be false in all five
  # dirs, every one would be skipped, and the migration would still exit 0 — green by doing nothing.
  fleet_config "$HOME/.claude"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'skipped (not a fleet config)' || false
  registered "$HOME/.claude/settings.json"
}

@test "the stored command is the LITERAL tilde, not this machine's expanded \$HOME" {
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run jq -r '.hooks.SubagentStop[0].hooks[0].command' "$HOME/.claude/settings.json"
  # shellcheck disable=SC2088  # asserting the LITERAL tilde reached settings.json unexpanded
  [ "$output" = '~/.claude/hooks/subagent-stop.sh' ]
  ! printf '%s' "$output" | grep -q "$HOME"
}

@test "timeout matches the template's declared 10, not a fresh guess" {
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run jq -r '.hooks.SubagentStop[0].hooks[0].timeout' "$HOME/.claude/settings.json"
  [ "$output" = "10" ]
}

@test "idempotent: a second run registers nothing further and says so" {
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'already registered'
  run jq -r '[.hooks.SubagentStop[]?.hooks[]?.command] | length' "$HOME/.claude/settings.json"
  [ "$output" = "1" ]
}

@test "APPENDS beside a sibling it did not write — never clobbers the array" {
  mkdir -p "$HOME/.claude"
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"x",timeout:5}]}],
                 SubagentStop:[{hooks:[{type:"command",command:"~/.claude/hooks/other.sh",timeout:3}]}]}}' \
    > "$HOME/.claude/settings.json"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  registered "$HOME/.claude/settings.json"
  run jq -r '[.hooks.SubagentStop[]?.hooks[]?.command] | any(. == "~/.claude/hooks/other.sh")' \
    "$HOME/.claude/settings.json"
  [ "$output" = "true" ]
}

@test "REFUSES when the subject is not executable — a registered no-op reads GREEN" {
  chmod -x "$HOME/.claude/hooks/subagent-stop.sh"
  fleet_config "$HOME/.claude"
  run bash "$SUT"
  [ "$status" -ne 0 ]
  ! registered "$HOME/.claude/settings.json"
}

@test "a config with no Stop array is left alone — not a fleet config" {
  mkdir -p "$HOME/.claude"
  jq -n '{permissions:{deny:[]}}' > "$HOME/.claude/settings.json"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'not a fleet config'
  ! registered "$HOME/.claude/settings.json"
}

@test "a backup of the pre-edit file exists and the result is valid JSON" {
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run bash -c "ls '$HOME/.claude/'settings.json.bak-0014-* 2>/dev/null | wc -l"
  [ "${output// /}" -ge 1 ]
  run jq -e . "$HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
}
