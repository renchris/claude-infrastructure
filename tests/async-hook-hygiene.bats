#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
# Async hooks have no operator-visible channel (docs/research/startup-hooks-2026-10-18/A5-silent-drops.md
# F8): scripts/async-hook-lint.sh refuses an async hook that prints systemMessage, and
# hooks/lib/async-span.sh gives each one START/END IDL rows so a harness kill is countable.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
}

settings_for() { # <command>... → a settings.json registering each as an async SessionStart hook
  local cmds; cmds="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
  jq -n --argjson c "$cmds" '{hooks:{SessionStart:[{hooks:($c|map({type:"command",command:.,async:true}))}]}}' \
    > "$BATS_TEST_TMPDIR/settings.json"
}

@test "lint: today's async hooks pass (none prints systemMessage)" {
  # shellcheck disable=SC2088  # the literal "~/" is what settings.json stores; the lint expands it
  settings_for '~/.claude/hooks/pre-session-validate.sh' '~/.claude/hooks/lead-crash-watchdog.sh' \
               '~/.claude/hooks/session-register.sh' '~/.claude/hooks/live-session-registry.sh'
  run "$REPO/scripts/async-hook-lint.sh" "$BATS_TEST_TMPDIR/settings.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 async hook script(s)"* ]]
}

@test "lint: an async hook that prints systemMessage fails, named" {
  printf '#!/bin/bash\necho %s\n' "'{\"systemMessage\":\"hi\"}'" > "$BATS_TEST_TMPDIR/loud.sh"
  settings_for "$BATS_TEST_TMPDIR/loud.sh"
  run "$REPO/scripts/async-hook-lint.sh" "$BATS_TEST_TMPDIR/settings.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"*"loud.sh"* ]]
}

@test "lint: a sync hook printing systemMessage is not its business" {
  printf '#!/bin/bash\necho %s\n' "'{\"systemMessage\":\"hi\"}'" > "$BATS_TEST_TMPDIR/loud.sh"
  jq -n --arg c "$BATS_TEST_TMPDIR/loud.sh" '{hooks:{SessionStart:[{hooks:[{type:"command",command:$c}]}]}}' \
    > "$BATS_TEST_TMPDIR/settings.json"
  run "$REPO/scripts/async-hook-lint.sh" "$BATS_TEST_TMPDIR/settings.json"
  [ "$status" -eq 0 ]
}

span_script() { # <body> → a hook script that opens a span then runs body
  printf '#!/bin/bash\n. "%s/hooks/lib/async-span.sh" && async_span_begin probe-hook "%s"\n%s\n' \
    "$REPO" "aaaa-bbbb" "$1" > "$BATS_TEST_TMPDIR/h.sh"
}

@test "span: a clean exit writes started then passed exit:0 for the same pid" {
  span_script 'exit 0'
  run bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.disposition' "$CC_IDL" | tr '\n' ' ')" = "started passed " ]
  pid="$(jq -r 'select(.disposition=="started")|.reason' "$CC_IDL")"; pid="${pid#pid:}"
  [ "$(jq -r 'select(.disposition=="passed")|.reason' "$CC_IDL")" = "exit:0_pid:$pid" ]
  [ "$(jq -r '.sid' "$CC_IDL" | sort -u)" = "aaaa-bbbb" ]
}

@test "span: a non-zero exit writes failed exit:<rc>" {
  span_script 'exit 3'
  run bash "$BATS_TEST_TMPDIR/h.sh"
  jq -e 'select(.disposition=="failed" and (.reason|startswith("exit:3_")))' "$CC_IDL" >/dev/null
}

@test "span: a TERM writes failed exit:143 (a harness kill is countable)" {
  span_script 'sleep 5 & wait $!'
  bash "$BATS_TEST_TMPDIR/h.sh" & p=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$CC_IDL" ] && break; sleep 0.2; done
  kill -TERM "$p"; wait "$p" || true
  jq -e 'select(.disposition=="failed" and (.reason|startswith("exit:143_")))' "$CC_IDL" >/dev/null
}

@test "span: CC_ASYNC_SPAN=0 writes nothing" {
  span_script 'exit 0'
  CC_ASYNC_SPAN=0 run bash "$BATS_TEST_TMPDIR/h.sh"
  [ ! -s "$CC_IDL" ]
}
