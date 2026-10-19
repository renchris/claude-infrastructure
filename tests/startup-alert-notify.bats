#!/usr/bin/env bats
# hooks/startup-alert-notify.sh + migrations/0071-filechanged-startup-alerts.sh — startup-hooks Wave 6
# item 6.2 (docs/research/startup-hooks-2026-10-18/probes/probeA-RESULT.md). c10: staged for the
# operator, never self-run.
# Hook pins: it speaks only for <alerts>/<its own session id> on add/change, prints valid JSON whatever
# the alert file holds, and is silent on everything else. Migration pins: nothing is written without
# --confirm; verify discriminates; only the two groups are added, with an ABSOLUTE matcher, beside the
# existing FileChanged pair; a second run is a no-op; a forked fleet is refused untouched.
#
# Hermetic: $HOME is a fixture; the real bin/cc-settings-parity runs over fixture account dirs through
# its CC_PARITY_DIRS seam, so nothing reads the operator's config.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_SETTINGS_PARITY_BIN CC_PARITY_CANONICAL CC_PARITY_ACCOUNTS_JSON CC_MIGRATION_STATE CC_STARTUP_ALERT_DIR
  mkdir -p "$HOME/.claude/bin"
  ln -s "$REPO_ROOT/bin/cc-settings-parity" "$HOME/.claude/bin/cc-settings-parity"
  jq -n '{env:{A:"1"}, hooks:{
    FileChanged:[{matcher:"/x/.claude/file-watch-paths",hooks:[{type:"command",command:"~/.claude/hooks/file-changed.sh",timeout:5}]},
                 {matcher:"*",hooks:[{type:"command",command:"~/.claude/hooks/file-changed.sh",timeout:5}]}],
    Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/x.sh"}]}]}}' > "$HOME/.claude/settings.json"
  CC_PARITY_DIRS=""
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
  S="$HOME/.claude/settings.json"
  MIG="$REPO_ROOT/migrations/0071-filechanged-startup-alerts.sh"
  HOOK="$REPO_ROOT/hooks/startup-alert-notify.sh"
  AL="$HOME/.claude/state/startup-health/alerts"
  SID="0478b034-66e1-436b-af35-050b4b60045a"
  mkdir -p "$AL"
}

payload() { # <file_path> [event] [session_id]
  printf '{"session_id":"%s","transcript_path":"/t.jsonl","cwd":"/w","hook_event_name":"FileChanged","file_path":"%s","event":"%s"}' \
    "${3:-$SID}" "$1" "${2:-change}"
}
fire() { run bash -c 'printf "%s" "$1" | bash "$2"' _ "$1" "$HOOK"; }

@test "hook: own alert → toast with the file's lines + BEL/OSC 99, valid JSON" {
  printf 'session-start-dispatch cancelled at 9 s\nrecovery packet not injected\n' > "$AL/$SID"
  fire "$(payload "$AL/$SID" add)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = "⚠ startup: session-start-dispatch cancelled at 9 s · recovery packet not injected" ]
  [ "$(printf '%s' "$output" | jq -r .terminalSequence)" = "$(printf '\a\033]99;;Claude Code startup fault 0478b034\033\\')" ]
}

@test "hook: quotes, backslashes and control bytes still give valid JSON" {
  printf 'say "hi" \\ back\ttab\033[31mred\n' > "$AL/$SID"
  fire "$(payload "$AL/$SID")"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = '⚠ startup: say "hi" \ back tab [31mred' ]
}

@test "hook: silent for another session's alert, an unlink, a same-named file elsewhere, junk stdin" {
  echo x > "$AL/other-sid"; echo x > "$AL/$SID"; mkdir -p "$HOME/elsewhere"; echo x > "$HOME/elsewhere/$SID"
  fire "$(payload "$AL/other-sid")";            [ "$status" -eq 0 ]; [ -z "$output" ]
  fire "$(payload "$AL/$SID" unlink)";          [ "$status" -eq 0 ]; [ -z "$output" ]
  fire "$(payload "$HOME/elsewhere/$SID")";     [ "$status" -eq 0 ]; [ -z "$output" ]
  fire 'not json';                              [ "$status" -eq 0 ]; [ -z "$output" ]
  fire '';                                      [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "migration: c10 with a --confirm run line; no --confirm ⇒ nothing written" {
  grep -q '^# migration-class: c10' "$MIG"
  grep -q '^# migration-run: bash .*0071-filechanged-startup-alerts.sh --confirm settings.json' "$MIG"
  before="$(cat "$S")"
  run bash "$MIG"; [ "$status" -eq 2 ]
  run bash "$MIG" --dry-run; [ "$status" -eq 0 ]
  run bash "$MIG" --check; [ "$status" -eq 0 ]
  [ "$(cat "$S")" = "$before" ]
}

@test "migration: verify false before, true after; adds only the two groups; links survive; idempotent" {
  rmdir "$AL"
  before="$(jq -S . "$S")"
  run bash "$MIG" --verify; [ "$status" -ne 0 ]
  run bash "$MIG" --confirm settings.json; [ "$status" -eq 0 ]
  run bash "$MIG" --verify; [ "$status" -eq 0 ]
  [ -d "$AL" ]
  [ "$(jq '.hooks.FileChanged | length' "$S")" = 4 ]
  [ "$(jq -S '.hooks.FileChanged |= .[0:2]' "$S")" = "$before" ]
  [ "$(jq -r '.hooks.FileChanged[2].matcher' "$S")" = "$AL" ]
  [ "$(jq -r '.hooks.FileChanged[2].hooks[0].command' "$S")" = true ]
  [ "$(jq -r '.hooks.FileChanged[3] | has("matcher")' "$S")" = false ]
  # shellcheck disable=SC2088  # the literal "~/" is what settings.json stores
  [ "$(jq -r '.hooks.FileChanged[3].hooks[0].command' "$S")" = '/bin/bash ~/.claude/hooks/startup-alert-notify.sh' ]
  for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ]; done
  after="$(cat "$S")"
  run bash "$MIG" --confirm settings.json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'already applied'
  [ "$(cat "$S")" = "$after" ]
}

@test "migration: a forked fleet is refused untouched" {
  rm "$HOME/.claude-next/settings.json"; jq '.env.B = "2"' "$S" > "$HOME/.claude-next/settings.json"
  before="$(cat "$S")"
  run bash "$MIG" --confirm settings.json
  [ "$status" -eq 3 ]
  [ "$(cat "$S")" = "$before" ]
}
