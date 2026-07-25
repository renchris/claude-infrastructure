#!/usr/bin/env bats
# settings-hook-timeouts.sh — the scripted, reversible way to set a hook entry's `timeout` or wire
# a hook under an existing event/matcher (audit 09 D-5, D-14).
#
# D-5: `waiting-recycle.sh` (795 lines, fires on EVERY Bash call, one of only two hooks that can
# emit {decision:"block"} from a non-Stop event) carried NO timeout key in any of the five config
# dirs — a hung git/transcript read had no ceiling. Same for `keychain-guard.sh`.
# D-14: PreCompact was asymmetric — dod-persist.sh was wired on matcher:auto only, so a MANUAL
# /compact never persisted the frozen DoD.
#
# The tool's --selftest RED-proves both operations end-to-end; these bats pin the CLI contract
# (dry-run vs --apply, backup, exit codes, narrowness, refusal to invent an event/matcher).
#
# Harness laws: L1 fixtures reproduce the LIVE settings shape (PostToolUse/Bash chain with one
# timeout-less entry; PreCompact auto+manual); L2 assertions key on failure-distinct values (the
# timeout that must NOT change, the object that must NOT grow); L3 `[ ]` / `grep -q` only;
# L4 each behaviour has a must-change and a must-NOT-change fixture.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/settings-hook-timeouts.sh"
  D="$BATS_TEST_TMPDIR"
  F="$D/settings.json"
  mklive "$F"
}

# the live shape: PostToolUse/Bash = log-bash(5) + waiting-recycle(NO timeout);
# PreCompact = auto{date, dod-persist(10)} + manual{date}
mklive() {
  jq -n '{hooks:{PostToolUse:[
      {matcher:"Bash",hooks:[
        {type:"command",command:"~/.claude/hooks/log-bash.sh",timeout:5},
        {type:"command",command:"~/.claude/hooks/waiting-recycle.sh"}]}],
    PreToolUse:[
      {matcher:"Bash",hooks:[
        {type:"command",command:"~/.claude/hooks/validate-bash.sh",timeout:10},
        {type:"command",command:"~/.claude/hooks/keychain-guard.sh"}]}],
    PreCompact:[
      {matcher:"auto",hooks:[
        {type:"command",command:"date >> log"},
        {type:"command",command:"~/.claude/hooks/dod-persist.sh",timeout:10}]},
      {matcher:"manual",hooks:[
        {type:"command",command:"date >> log"}]}]}}' > "$1"
}

@test "selftest passes and runs all 15 checks (a zero-check suite must not 'pass')" {
  run "$S" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok   ')" -eq 15 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

# ── --set-timeout ─────────────────────────────────────────────────────────────────────────────
@test "dry-run reports the timeout and changes nothing" {
  run "$S" --event PostToolUse --set-timeout waiting-recycle --timeout 30 "$F"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'SET '
  [ "$(jq '.hooks.PostToolUse[0].hooks[1] | has("timeout")' "$F")" = "false" ]
  [ ! -f "$F.timeouts.bak" ]
}

@test "--apply sets the timeout, backs up, and leaves siblings alone" {
  run "$S" --event PostToolUse --set-timeout waiting-recycle --timeout 30 --apply "$F"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.PostToolUse[0].hooks[1].timeout' "$F")" = "30" ]
  [ "$(jq '.hooks.PostToolUse[0].hooks[0].timeout' "$F")" = "5" ]
  [ -f "$F.timeouts.bak" ]
  [ "$(jq '.hooks.PostToolUse[0].hooks[1] | has("timeout")' "$F.timeouts.bak")" = "false" ]
}

@test "--set-timeout is scoped to the named event only (a cross-event hit is exit 3, not a write)" {
  # keychain-guard lives under PreToolUse; asking for it under PostToolUse must NOT reach across
  run "$S" --event PostToolUse --set-timeout keychain-guard --timeout 10 --apply "$F"
  [ "$status" -eq 3 ]
  [ "$(jq '.hooks.PreToolUse[0].hooks[1] | has("timeout")' "$F")" = "false" ]
  [ ! -f "$F.timeouts.bak" ]
  # and under its OWN event it works
  run "$S" --event PreToolUse --set-timeout keychain-guard --timeout 10 --apply "$F"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.PreToolUse[0].hooks[1].timeout' "$F")" = "10" ]
  [ "$(jq '.hooks.PostToolUse[0].hooks[1] | has("timeout")' "$F")" = "false" ]
}

@test "--set-timeout is idempotent" {
  "$S" --event PostToolUse --set-timeout waiting-recycle --timeout 30 --apply "$F" >/dev/null
  run "$S" --event PostToolUse --set-timeout waiting-recycle --timeout 30 --apply "$F"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'clean'
}

@test "an unmatched substring is exit 3, never a silent no-op" {
  run "$S" --event PostToolUse --set-timeout nosuchhook --timeout 9 "$F"
  [ "$status" -eq 3 ]
}

# ── --ensure ──────────────────────────────────────────────────────────────────────────────────
@test "--ensure wires dod-persist onto PreCompact matcher:manual" {
  run "$S" --event PreCompact --matcher manual --ensure '~/.claude/hooks/dod-persist.sh' --timeout 10 --apply "$F"
  [ "$status" -eq 0 ]
  [ "$(jq '.hooks.PreCompact[1].hooks | length' "$F")" -eq 2 ]
  [ "$(jq -r '.hooks.PreCompact[1].hooks[1].command' "$F")" = "~/.claude/hooks/dod-persist.sh" ]
  [ "$(jq '.hooks.PreCompact[1].hooks[1].timeout' "$F")" = "10" ]
  [ "$(jq '.hooks.PreCompact[0].hooks | length' "$F")" -eq 2 ]
}

@test "--ensure is idempotent and spelling-insensitive (never double-wires a hook)" {
  "$S" --event PreCompact --matcher manual --ensure '~/.claude/hooks/dod-persist.sh' --timeout 10 --apply "$F" >/dev/null
  run "$S" --event PreCompact --matcher auto --ensure '/some/other/path/dod-persist.sh' --timeout 10 --apply "$F"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'clean'
  [ "$(jq '.hooks.PreCompact[0].hooks | length' "$F")" -eq 2 ]
}

@test "a matcher that does not exist is exit 3 — never a newly invented object" {
  run "$S" --event PreCompact --matcher typo --ensure '~/x.sh' --timeout 5 --apply "$F"
  [ "$status" -eq 3 ]
  [ "$(jq '.hooks.PreCompact | length' "$F")" -eq 2 ]
}

@test "an event that does not exist is exit 3 — never a newly invented event" {
  run "$S" --event SubagentStop --matcher-null --ensure '~/x.sh' --timeout 5 --apply "$F"
  [ "$status" -eq 3 ]
  [ "$(jq '.hooks | has("SubagentStop")' "$F")" = "false" ]
}

# ── argument + safety contract ────────────────────────────────────────────────────────────────
@test "unknown arg → exit 2" {
  run "$S" --bogus "$F"
  [ "$status" -eq 2 ]
}

@test "no operation selected → exit 2" {
  run "$S" --event Stop --timeout 5 "$F"
  [ "$status" -eq 2 ]
}

@test "a non-integer timeout → exit 2" {
  run "$S" --event PostToolUse --set-timeout waiting-recycle --timeout abc "$F"
  [ "$status" -eq 2 ]
}

@test "--ensure without a matcher → exit 2" {
  run "$S" --event PreCompact --ensure '~/x.sh' --timeout 5 "$F"
  [ "$status" -eq 2 ]
}

@test "invalid JSON input is refused, not rewritten" {
  printf '{not json' > "$D/bad.json"
  run "$S" --event PostToolUse --set-timeout waiting-recycle --timeout 30 --apply "$D/bad.json"
  [ "$status" -eq 3 ]
  grep -q 'not json' "$D/bad.json"
  [ ! -f "$D/bad.json.timeouts.bak" ]
}

@test "the applied result is always valid JSON that still has .hooks" {
  "$S" --event PostToolUse --set-timeout waiting-recycle --timeout 30 --apply "$F" >/dev/null
  run jq -e '.hooks.PostToolUse' "$F"
  [ "$status" -eq 0 ]
}
