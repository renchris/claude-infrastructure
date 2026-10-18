#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
# research-precognition-nudge.sh is a human-intent nudge: silent on a harness-injected
# <task-notification> (60 of 90 firings were machine prompts — docs/research/startup-hooks-2026-10-18/
# A9-beyond-startup.md), still firing on a typed research prompt. Hermetic: the router is off.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/research-precognition-nudge.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_RESEARCH_ROUTER=off
}
run_p() { run bash -c 'jq -nc --arg p "$1" "{prompt:\$p}" | bash "$0"' "$H" "$1"; }

@test "a <task-notification> quoting research intent is SILENT" {
  run_p $'<task-notification>\nagent said: research the options and fan out subagents</task-notification>'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "leading whitespace before the envelope is still a machine prompt" {
  run_p $'  \n<task-notification>research the options</task-notification>'
  [ -z "$output" ]
}

@test "a typed research prompt still gets the nudge" {
  run_p 'please research the options for the cache'
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESEARCH-INTENT PRE-COGNITION"* ]]
}
