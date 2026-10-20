#!/usr/bin/env bats
# migration 0066 — hook `if` filters (docs/research/load-root-cause-2026-10-17/DESIGN.md X18).
#
# 0066 splits pr-gate.sh and relay-verbatim.sh into one entry per `if` pattern and unregisters the
# inert ship-rail-push-allow.sh, in the shared settings.json (c10: staged for the operator). Its
# --confirm runs a live probe of `if` on the claude binary first, so these tests drive the probe
# through a STUB claude (CC_IF_PROBE_CLAUDE) that writes the hook-log rows a real run would, and
# never start a real one.
#
# Pins: the class is c10; the verify oracle fails before and passes after; the edit touches only
# the three target entries; a second run is a no-op with no second backup; somebody else's `if`
# is refused rc 3; --dry-run and --check never run the probe; and --confirm refuses, writing
# nothing, when the probe shows a filter that misses a spelling, fires on `ls`, or never ran.
#
# Hermetic: $HOME is a fixture under BATS_TEST_TMPDIR; nothing reads the operator's config.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  M="$REPO_ROOT/migrations/0066-hook-if-filters.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp/"
  # claude-accounts' pane state defaults to an absolute /tmp path that a fixtured $HOME does not move.
  export CC_PANE_DIR="$BATS_TEST_TMPDIR/claude-accounts-pane"
  mkdir -p "$HOME/.claude" "$TMPDIR" "$BATS_TEST_TMPDIR/bin"
  S="$HOME/.claude/settings.json"
  jq -n '{env: {MCP_TIMEOUT: "30000"}, hooks: {
      PreToolUse: [
        {matcher: "Bash", hooks: [
          {type: "command", command: "~/.claude/hooks/validate-bash.sh", timeout: 5},
          {type: "command", command: "~/.claude/hooks/ship-rail-push-allow.sh", timeout: 5},
          {type: "command", command: "~/.claude/hooks/pr-gate.sh"}]},
        {matcher: "Write|Edit|MultiEdit", hooks: [{type: "command", command: "~/.claude/hooks/w.sh"}]}],
      PostToolUse: [
        {matcher: "Bash", hooks: [
          {type: "command", command: "~/.claude/hooks/log-bash.sh", timeout: 5},
          {type: "command", command: "~/.claude/hooks/relay-verbatim.sh", timeout: 5}]}]}}' > "$S"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/parity-ok"
  chmod +x "$BATS_TEST_TMPDIR/bin/parity-ok"
  export CC_SETTINGS_PARITY_BIN="$BATS_TEST_TMPDIR/bin/parity-ok"
  stub_claude good
}

# stub_claude <good|skip-bash-c|ls-fires|never-runs|not-logged-in|partial|timeout>: a claude that
# "runs" each numbered command of the prompt and logs the hooks a real run would start, matching each
# `if` as a glob. not-logged-in prints the real refusal and runs nothing; partial runs only commands
# 1-5; timeout runs everything and then exits 124, as `timeout 240` reports a killed child.
stub_claude() {
  # shellcheck disable=SC2016  # the stub's own variables expand when the stub runs
  printf '%s\n' '#!/bin/bash' \
    'echo "$*" >> "'"$BATS_TEST_TMPDIR"'/claude-calls"' \
    'echo "CLAUDECODE=${CLAUDECODE:-unset} SID=${CLAUDE_CODE_SESSION_ID:-unset} CFG=${CLAUDE_CONFIG_DIR:-unset}" >> "'"$BATS_TEST_TMPDIR"'/claude-env"' \
    '[ "${1:-}" = --version ] && { echo "9.9.9 (stub)"; exit 0; }' \
    'set_file=""; prompt=""; while [ $# -gt 0 ]; do case "$1" in --settings) set_file="$2"; shift 2 ;; *) prompt="$1"; shift ;; esac; done' \
    'mode="'"$1"'"; [ "$mode" = never-runs ] && exit 0' \
    '[ "$mode" = not-logged-in ] && { echo "Not logged in · Please run /login"; exit 1; }' \
    'log="${set_file%/*}/fired.log"; n=0' \
    'rows="$(jq -r ".hooks.PreToolUse[0].hooks[] | select(.[\"if\"] != null) | [(.command | split(\" \") | last), .[\"if\"]] | @tsv" "$set_file")"' \
    'while IFS= read -r line; do' \
    '  case "$line" in [0-9]*". "*) cmd="${line#*. }" ;; *) continue ;; esac' \
    '  n=$((n + 1)); [ "$mode" = partial ] && [ "$n" -gt 5 ] && break' \
    '  printf "noif\t%s\n" "$cmd" >> "$log"' \
    '  while IFS=$'"'\\t'"' read -r label pat; do' \
    '    glob="${pat#Bash(}"; glob="${glob%)}"' \
    '    case "$mode:$cmd" in "skip-bash-c:bash -c"*) continue ;; esac' \
    '    # shellcheck disable=SC2053' \
    '    if [[ $cmd == $glob ]] || { [ "$mode" = ls-fires ] && [ "$cmd" = ls ] && [ "$label" = pr-create ]; }; then printf "%s\t%s\n" "$label" "$cmd" >> "$log"; fi' \
    '  done <<< "$rows"' \
    'done <<< "$prompt"' \
    '[ "$mode" = timeout ] && exit 124; exit 0' \
    > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  export CC_IF_PROBE_CLAUDE="$BATS_TEST_TMPDIR/bin/claude"
}

header() { sed -n "s/^# *migration-$1: *//p" "$M" | head -1; }
ifs() { jq -c --arg ev "$1" --arg re "$2" '[.hooks[$ev][]?.hooks[]? | select(.command | test($re)) | .["if"]] | sort' "$S"; }
# Everything but the three targets, so a test can assert the edit touched nothing else.
rest() { jq -c '.hooks.PreToolUse |= map(.hooks |= map(select(.command | test("pr-gate|ship-rail") | not)))
                | .hooks.PostToolUse |= map(.hooks |= map(select(.command | test("relay-verbatim") | not)))' "$S"; }

@test "1: 0066 is c10, names its operator step, and its verify oracle fails before and passes after" {
  [ "$(header class)" = "c10" ]
  [ -n "$(header step)" ]
  run env CC_MIGRATION_REPO="$REPO_ROOT" bash -c "$(header verify)"
  [ "$status" -ne 0 ]
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run env CC_MIGRATION_REPO="$REPO_ROOT" bash -c "$(header verify)"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "2: --confirm splits pr-gate and relay-verbatim per if, drops ship-rail, touches nothing else" {
  before="$(rest)"
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"probe PASSED"* ]] || false
  [ "$(ifs PreToolUse 'pr-gate')" = '["Bash(*gh pr create*)","Bash(*gh pr edit*)"]' ]
  [ "$(ifs PostToolUse 'relay-verbatim')" = '["Bash(*cc-do --list*)","Bash(*claude-accounts*--readout*)","Bash(*operator-readout.sh --render*)"]' ]
  [ "$(ifs PreToolUse 'ship-rail')" = '[]' ]
  [ "$(rest)" = "$before" ]
  # The split copies keep the entry's own fields (relay-verbatim's timeout).
  [ "$(jq '[.hooks.PostToolUse[0].hooks[] | select(.command | test("relay")) | .timeout] | unique' -c "$S")" = '[5]' ]
}

@test "3: a second run is a no-op with no second backup" {
  bash "$M" --confirm settings.json >/dev/null
  sum="$(shasum "$S")"
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]] || false
  [ "$(shasum "$S")" = "$sum" ]
  [ "$(find "$HOME/.claude/backups" -name settings.json | wc -l | tr -d ' ')" = 1 ]
}

@test "4: --dry-run and --check write nothing and never start the probe" {
  sum="$(shasum "$S")"
  run bash "$M" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]] || false
  run bash "$M" --check
  [ "$status" -eq 0 ]
  [ "$(shasum "$S")" = "$sum" ]
  [ ! -e "$BATS_TEST_TMPDIR/claude-calls" ]
}

@test "5: somebody else's if on pr-gate is refused rc 3 and named by --conflict" {
  jq '.hooks.PreToolUse[0].hooks[2]["if"] = "Bash(gh pr *)"' "$S" > "$S.n" && mv "$S.n" "$S"
  sum="$(shasum "$S")"
  run bash "$M" --confirm settings.json
  [ "$status" -eq 3 ]
  [[ "$output" == *"Bash(gh pr *)"* ]] || false
  [ "$(shasum "$S")" = "$sum" ]
  run bash "$M" --conflict
  [ "$status" -eq 0 ]
}

@test "6: a partial if set (create only, edit missing) is refused rc 3" {
  jq '.hooks.PreToolUse[0].hooks[2]["if"] = "Bash(*gh pr create*)"' "$S" > "$S.n" && mv "$S.n" "$S"
  run bash "$M" --confirm settings.json
  [ "$status" -eq 3 ]
  [[ "$output" == *"partial"* ]] || false
}

@test "7: with ship-rail already unregistered, the filters still apply" {
  jq '.hooks.PreToolUse[0].hooks |= map(select(.command | test("ship-rail") | not))' "$S" > "$S.n" && mv "$S.n" "$S"
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(ifs PreToolUse 'pr-gate')" = '["Bash(*gh pr create*)","Bash(*gh pr edit*)"]' ]
}

@test "8: FAIL (rc 1) — a probe that ran but misses bash -c or fires on ls makes --confirm refuse and write nothing" {
  sum="$(shasum "$S")"
  for mode in skip-bash-c ls-fires; do
    stub_claude "$mode"
    run bash "$M" --confirm settings.json
    [ "$status" -eq 1 ] || { echo "$mode: rc $status"; echo "$output"; false; }
    [[ "$output" == *"probe did not pass"* ]] || { echo "$mode"; echo "$output"; false; }
    [[ "$output" != *"BLIND"* ]] || { echo "$mode"; echo "$output"; false; }
    [ "$(shasum "$S")" = "$sum" ]
  done
  [ ! -d "$HOME/.claude/backups" ]
}

@test "8b: BLIND (rc 3) — empty log, not logged in, rc 124 and a partial run prove nothing; --confirm writes nothing" {
  sum="$(shasum "$S")"
  for mode in never-runs not-logged-in timeout partial; do
    stub_claude "$mode"
    run bash "$M" --confirm settings.json
    [ "$status" -eq 3 ] || { echo "$mode: rc $status"; echo "$output"; false; }
    [[ "$output" == *"probe BLIND"* ]] || { echo "$mode"; echo "$output"; false; }
    [[ "$output" == *"REFUSED — BLIND, nothing written"* ]] || { echo "$mode"; echo "$output"; false; }
    [ "$(shasum "$S")" = "$sum" ]
  done
  [ ! -d "$HOME/.claude/backups" ]
}

@test "8c: each BLIND cause is named, and --probe alone passes rc 3 through" {
  stub_claude never-runs;    run bash "$M" --probe; [ "$status" -eq 3 ]; [[ "$output" == *"empty fired.log"* ]] || false
  stub_claude not-logged-in; run bash "$M" --probe; [ "$status" -eq 3 ]; [[ "$output" == *"not logged in"* ]] || false
  stub_claude timeout;       run bash "$M" --probe; [ "$status" -eq 3 ]; [[ "$output" == *"rc 124"* ]] || false
  stub_claude partial;       run bash "$M" --probe; [ "$status" -eq 3 ]; [[ "$output" == *"cmd 6 never ran"* ]] || false
}

@test "8d: the probe child runs without the caller's session vars and on the caller's CLAUDE_CONFIG_DIR" {
  run env CLAUDECODE=1 CLAUDE_CODE_SESSION_ID=parent-sid CLAUDE_CONFIG_DIR="$HOME/.claude-acct" bash "$M" --probe
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q "CLAUDECODE=unset SID=unset CFG=$HOME/.claude-acct" "$BATS_TEST_TMPDIR/claude-env"
}

@test "8e: 0066 is held out of the c10 batch as manual" {
  [[ "$(header batch-hold)" == "manual — "* ]] || false
}

@test "9: --probe alone prints the matrix and passes on a correct binary" {
  run bash "$M" --probe
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"cmd 3"*"pr-edit"*"bash -c"* ]] || false
  [[ "$output" == *"probe PASSED"* ]] || false
}

@test "10: a forked account settings.json is refused rc 3" {
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/bin/parity-bad"
  chmod +x "$BATS_TEST_TMPDIR/bin/parity-bad"
  CC_SETTINGS_PARITY_BIN="$BATS_TEST_TMPDIR/bin/parity-bad" run bash "$M" --confirm settings.json
  [ "$status" -eq 3 ]
}
