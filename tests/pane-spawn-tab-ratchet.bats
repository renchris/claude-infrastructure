#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats: every @test body is its own subshell.
#
# scripts/checks/pane-spawn-tab-ratchet.sh — tab rows in the pane-spawn log must be 0 (lr-wake
# incident 2026-10-18, REPORT §4 Wave D: "A pane-spawns ratchet: bg-tab rows equal 0. It would have
# read 22 overnight").
#
# The fixture is the REAL night: the 22 bg-tab rows ~/.claude/logs/pane-spawns.jsonl recorded
# between 01:00Z and 15:00Z on 2026-10-18 (fields cut to ts/surface/caller/pane/detail), one
# bg-tab row from the evening before, three os-window rows from the same window, two tab rows from
# the exempt recorded-layout restorers, and one torn line.
#
# RED on origin/main: the script does not exist.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  R="$REPO/scripts/checks/pane-spawn-tab-ratchet.sh"
  FIX="$REPO/tests/fixtures/pane-spawn-tab-ratchet/pane-spawns-2026-10-18.jsonl"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  unset CC_SPAWN_LOG_FILE
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

@test "the 2026-10-18 night reads RED with exactly 22 tab rows, each named" {
  run "$R" --log "$FIX" --since 2026-10-18T01:00:00Z
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == "pane-spawn-tab-ratchet: verdict=RED tab_rows=22 since=2026-10-18T01:00:00Z unparsed=1 "* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c $'\tbg-tab\tpane:')" -eq 22 ]
  printf '%s\n' "$output" | grep -qF $'2026-10-18T03:04:18Z\tbg-tab\tpane:376\thandoff-fire.sh'
}

@test "--all counts the evening-before row too; the exempt restorers never count" {
  run "$R" --log "$FIX" --all
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == *"tab_rows=23 "* ]] || { echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -q 'cc-resume-layout\|restore-tree-live-verify' || false
}

@test "a log with only split/os-window rows and exempt tab rows reads ok, exit 0" {
  grep -v '"bg-tab"' "$FIX" > "$BATS_TEST_TMPDIR/clean.jsonl"
  run "$R" --log "$BATS_TEST_TMPDIR/clean.jsonl" --all
  [ "$status" -eq 0 ]
  [[ "$output" == "pane-spawn-tab-ratchet: verdict=ok tab_rows=0 "* ]] || { echo "$output"; false; }
}

@test "--since after the night excludes it (the ratchet counts a window, not history)" {
  run "$R" --log "$FIX" --since 2026-10-18T15:00:00Z
  [ "$status" -eq 0 ]
}

@test "an unreadable log is NO VERDICT (exit 2), never ok" {
  run "$R" --log "$BATS_TEST_TMPDIR/absent.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" == *"verdict=no-verdict reason=log-unreadable"* ]]
}

@test "the default log is ~/.claude/logs/pane-spawns.jsonl" {
  mkdir -p "$HOME/.claude/logs"; cp "$FIX" "$HOME/.claude/logs/pane-spawns.jsonl"
  run "$R" --all
  [ "$status" -eq 1 ]
  [[ "${lines[0]}" == *"log=$HOME/.claude/logs/pane-spawns.jsonl" ]]
}
