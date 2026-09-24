#!/usr/bin/env bats
# migration 0036 — item F4 of docs/research/token-efficiency-2026-09-23/OPPORTUNITIES.md.
#
# 0036 stages ONE account's claudeMdExcludes glob for the situational half of the split rules file
# (c10: staged for the operator, never self-run). Pins: the class is c10; the verify oracle
# discriminates and reads the target account, not the per-config-dir loop's CC_CLAUDE_DIR; the edit
# keeps every sibling key and every prior exclude; a second run is a no-op with no second backup;
# and only the target account is touched.
#
# Hermetic: $HOME is a fixture under BATS_TEST_TMPDIR; nothing reads the operator's config.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  M="$REPO_ROOT/migrations/0036-rules-situational-exclude.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_RULES_SPLIT_ACCOUNT_DIR
  mkdir -p "$HOME/.claude" "$HOME/.claude-tertiary"
  jq -n '{env:{MCP_TIMEOUT:"30000"}, claudeMdExcludes:["/tmp/x/**"], hooks:{Stop:[]}}' > "$HOME/.claude-tertiary/settings.json"
  jq -n '{hooks:{Stop:[]}}' > "$HOME/.claude/settings.json"
  G='**/.claude/rules/agent-operating-lessons-situational.md'
}

header() { sed -n "s/^# *migration-$1: *//p" "$M" | head -1; }

@test "1: 0036 is c10 and names its operator step" {
  [ "$(header class)" = "c10" ]
  [ -n "$(header step)" ]
}

@test "2: the verify oracle fails before and passes after, whatever CC_CLAUDE_DIR says" {
  verify="$(header verify)"
  run env CC_CLAUDE_DIR="$HOME/.claude" bash -c "$verify"
  [ "$status" -ne 0 ] || { echo "oracle passed BEFORE the migration ran"; false; }
  run bash "$M"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run env CC_CLAUDE_DIR="$HOME/.claude" bash -c "$verify"
  [ "$status" -eq 0 ] || false
}

@test "3: the glob is appended; prior excludes and sibling keys survive; other accounts untouched" {
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/other.before"
  run bash "$M"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  f="$HOME/.claude-tertiary/settings.json"
  [ "$(jq -c '.claudeMdExcludes' "$f")" = "$(jq -nc --arg g "$G" '["/tmp/x/**", $g]')" ] || false
  [ "$(jq -r '.env.MCP_TIMEOUT' "$f")" = "30000" ] || false
  jq -e '.hooks.Stop == []' "$f" >/dev/null || false
  cmp -s "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/other.before" || false
}

@test "4: a second run is a no-op with no second backup" {
  bash "$M" >/dev/null
  run bash "$M"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"already present"* ]] || false
  [ "$(find "$HOME/.claude-tertiary" -name 'settings.json.bak-0036-*' | wc -l | tr -d ' ')" -eq 1 ] || false
  [ "$(jq --arg g "$G" '[.claudeMdExcludes[] | select(. == $g)] | length' "$HOME/.claude-tertiary/settings.json")" -eq 1 ] || false
}

@test "5: CC_RULES_SPLIT_ACCOUNT_DIR re-aims it at another account" {
  mkdir -p "$HOME/.claude-next"; jq -n '{}' > "$HOME/.claude-next/settings.json"
  run env CC_RULES_SPLIT_ACCOUNT_DIR="$HOME/.claude-next" bash "$M"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e --arg g "$G" '.claudeMdExcludes == [$g]' "$HOME/.claude-next/settings.json" >/dev/null || false
  run jq -e --arg g "$G" '.claudeMdExcludes | any(.[]; . == $g)' "$HOME/.claude-tertiary/settings.json"
  [ "$status" -ne 0 ] || false
}

@test "6: a non-array claudeMdExcludes or a missing settings.json fails and changes nothing" {
  jq -n '{claudeMdExcludes:"oops"}' > "$HOME/.claude-tertiary/settings.json"
  cp "$HOME/.claude-tertiary/settings.json" "$BATS_TEST_TMPDIR/bad.before"
  run bash "$M"
  [ "$status" -ne 0 ] || false
  cmp -s "$HOME/.claude-tertiary/settings.json" "$BATS_TEST_TMPDIR/bad.before" || false
  run env CC_RULES_SPLIT_ACCOUNT_DIR="$HOME/nope" bash "$M"
  [ "$status" -ne 0 ] || false
  [ ! -e "$HOME/nope/settings.json" ] || false
}
