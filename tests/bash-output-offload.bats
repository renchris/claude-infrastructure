#!/usr/bin/env bats
# hooks/bash-output-offload.sh (token-efficiency rank 12, wave 2) and its registration, migration 0039.
# Pins: a large non-read Bash result becomes head + pointer + the failure lines from the hidden middle
# + tail, with the full text saved at the named path; deliberate reads, small results, background
# launches and CC_BASH_OFFLOAD=0 pass through untouched; garbage input fails open. Migration 0039 is
# c10, appends exactly one "^Bash$" entry to the shared settings.json, keeps every account linked,
# is idempotent, and refuses a forked fleet with nothing written.
#
# Hermetic: $HOME is a fixture; the real bin/cc-settings-parity runs over fixture account dirs.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO_ROOT/hooks/bash-output-offload.sh"
  M="$REPO_ROOT/migrations/0039-bash-output-offload.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BASH_OFFLOAD_DIR="$BATS_TEST_TMPDIR/offload"
  unset CC_BASH_OFFLOAD CC_BASH_OFFLOAD_CHARS
}

payload() { # $1 = command, $2 = stdout
  jq -nc --arg c "$1" --arg o "$2" '{tool_name:"Bash",tool_input:{command:$c},tool_response:{stdout:$o,stderr:"",interrupted:false,isImage:false,noOutputExpected:false}}'
}
big() { python3 -c 'print("\n".join(["ok %d - case"%i for i in range(1,500)]+["not ok 500 - parse empty field"]+["ok %d - case"%i for i in range(501,900)]+["899 passed, 1 failed"]))'; }

@test "a large non-read result is replaced: head, pointer with path, the hidden failure line, tail" {
  out="$(payload ./test.sh "$(big)" | bash "$HOOK")"
  s="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout')"
  [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" = PostToolUse ]
  [[ "$s" == "ok 1 - case"* ]] || false
  [[ "$s" == *"lines 41-840 are not shown"* ]] || false
  [[ "$s" == *"500: not ok 500 - parse empty field"* ]] || false
  [[ "$s" == *"899 passed, 1 failed" ]] || false
  path="$(printf '%s' "$s" | sed -n 's/.*Full output: \([^ ]*\) .*/\1/p' | head -1)"
  [ -f "$path" ] || { echo "no saved file: $path"; false; }
  [ "$(cat "$path")" = "$(big)" ] || false
  # the rest of the tool_response object is carried through unchanged
  [ "$(printf '%s' "$out" | jq -c '.hookSpecificOutput.updatedToolOutput | del(.stdout)')" = '{"stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false}' ]
  [ "${#s}" -lt 5000 ] || false
}

@test "deliberate reads, small results, background launches and CC_BASH_OFFLOAD=0 pass through" {
  for c in "cat big.log" "sed -n 1,900p big.log" "git show HEAD" "git -C x diff" "grep -n ok big.log" "./x | tail -900"; do
    [ -z "$(payload "$c" "$(big)" | bash "$HOOK")" ] || { echo "read touched: $c"; false; }
  done
  [ -z "$(payload ./test.sh "small" | bash "$HOOK")" ] || false
  [ -z "$(jq -nc --arg o "$(big)" '{tool_name:"Bash",tool_input:{command:"./t.sh"},tool_response:{stdout:$o,backgroundTaskId:"b1"}}' | bash "$HOOK")" ] || false
  [ -z "$(payload ./test.sh "$(big)" | CC_BASH_OFFLOAD=0 bash "$HOOK")" ] || false
  [ ! -d "$CC_BASH_OFFLOAD_DIR" ] || [ -z "$(ls "$CC_BASH_OFFLOAD_DIR")" ] || false
}

@test "fail-open: garbage and a non-Bash payload exit 0 with no output" {
  run bash -c 'printf "not json" | bash "$0"' "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ] || false
  run bash -c 'jq -nc "{tool_name:\"Read\",tool_response:{stdout:\"x\"}}" | bash "$0"' "$HOOK"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ] || false
}

fleet() { # shared settings.json, four linked accounts, live hook present
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/hooks"
  ln -s "$REPO_ROOT/bin/cc-settings-parity" "$HOME/.claude/bin/cc-settings-parity"
  : > "$HOME/.claude/hooks/bash-output-offload.sh"
  jq -n '{env:{A:"1"},hooks:{PostToolUse:[{matcher:"Bash",hooks:[{type:"command",command:"~/.claude/hooks/log-bash.sh"}]}]}}' > "$HOME/.claude/settings.json"
  CC_PARITY_DIRS=""
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"; ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
}
header() { sed -n "s/^# *migration-$1: *//p" "$M" | head -1; }

@test "0039: c10, verify fails before and passes after, one entry appended, accounts stay linked, idempotent" {
  fleet
  [ "$(header class)" = c10 ]
  run bash -c "$(header verify)"; [ "$status" -ne 0 ] || false
  run bash "$M"; [ "$status" -eq 2 ] || false            # no consent flag, nothing written
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bash -c "$(header verify)"; [ "$status" -eq 0 ] || false
  [ "$(jq -c '.hooks.PostToolUse[1]' "$HOME/.claude/settings.json")" = '{"matcher":"^Bash$","hooks":[{"type":"command","command":"~/.claude/hooks/bash-output-offload.sh","timeout":10}]}' ]
  [ "$(jq -c '.hooks.PostToolUse[0].matcher, .env' "$HOME/.claude/settings.json" | tr -d '\n')" = '"Bash"{"A":"1"}' ]
  for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ] || false; done
  run bash "$M" --confirm settings.json
  [[ "$output" == *"already applied"* ]] || false
  [ "$(jq '[.hooks.PostToolUse[] | select(.matcher=="^Bash$")] | length' "$HOME/.claude/settings.json")" -eq 1 ]
}

@test "0039: a forked account is refused with nothing written" {
  fleet
  rm "$HOME/.claude-tertiary/settings.json"; cp "$HOME/.claude/settings.json" "$HOME/.claude-tertiary/settings.json"
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/before"
  run bash "$M" --confirm settings.json
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *REFUSED* ]] || { echo "$output"; false; }
  cmp -s "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/before" || false
}
