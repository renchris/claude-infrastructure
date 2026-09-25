#!/usr/bin/env bats
# migration 0040 — token-efficiency rank 25 (wave 3): the unused claude.ai Claude Docs connector off.
#
# 0040 stages {"serverName":"claude.ai Claude Docs"} in deniedMcpServers and "anthropic-skills:docs":
# "off" in skillOverrides, in the ONE shared ~/.claude/settings.json every account links to since
# 0037 (c10: staged for the operator, never self-run). Pins: c10 with an all-accounts step line and a
# --confirm run line; nothing is written without --confirm; the verify oracle discriminates and is
# config-dir invariant; only the two keys change, prior deny entries and skill overrides survive, and
# every account stays LINKED; a second run is a no-op; a forked fleet is refused untouched; and the
# deny names exactly this one connector, never another claude.ai one.
#
# Hermetic: $HOME is a fixture under BATS_TEST_TMPDIR; the real bin/cc-settings-parity runs against
# fixture account dirs through its CC_PARITY_DIRS seam, so nothing reads the operator's config.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  M="$REPO_ROOT/migrations/0040-claude-docs-connector-off.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_SETTINGS_PARITY_BIN CC_PARITY_CANONICAL CC_PARITY_ACCOUNTS_JSON CC_MIGRATION_STATE
  mkdir -p "$HOME/.claude/bin"
  ln -s "$REPO_ROOT/bin/cc-settings-parity" "$HOME/.claude/bin/cc-settings-parity"
  jq -n '{env:{MCP_TIMEOUT:"30000"}, deniedMcpServers:[{serverName:"old-server"}], skillOverrides:{"x:y":"off"}, hooks:{Stop:[]}}' \
    > "$HOME/.claude/settings.json"
  CC_PARITY_DIRS=""
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
}

header() { sed -n "s/^# *migration-$1: *//p" "$M" | head -1; }
nbak() { find "$HOME/.claude/backups" -maxdepth 1 -name 'claude-docs-off-0040-*' 2>/dev/null | wc -l | tr -d ' '; }

@test "1: c10, the step names the shared file and ALL accounts, the run line carries --confirm" {
  [ "$(header class)" = "c10" ]
  step="$(header step)"
  [[ "$step" == *"~/.claude/settings.json"* ]] || { echo "$step"; false; }
  [[ "$step" == *"ALL accounts"* ]] || { echo "$step"; false; }
  [[ "$(header run)" == *"--confirm settings.json" ]] || false
}

@test "2: no argument and --dry-run write nothing" {
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/before"
  run bash "$M"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  run bash "$M" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"DRY RUN"* ]] || false
  cmp -s "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/before" || false
  [ "$(nbak)" -eq 0 ] || false
}

@test "3: the verify oracle fails before and passes after, from every CC_CLAUDE_DIR" {
  verify="$(header verify)"
  for d in "$HOME/.claude" "$HOME/.claude-tertiary"; do
    run env CC_CLAUDE_DIR="$d" bash -c "$verify"
    [ "$status" -ne 0 ] || { echo "oracle passed BEFORE the migration ran ($d)"; false; }
  done
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  for d in "$HOME/.claude" "$HOME/.claude-tertiary"; do
    run env CC_CLAUDE_DIR="$d" bash -c "$verify"
    [ "$status" -eq 0 ] || { echo "oracle failed AFTER ($d)"; false; }
  done
}

@test "4: only the two keys change; prior entries survive; every account still LINKED and sees it" {
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  f="$HOME/.claude/settings.json"
  [ ! -L "$f" ] || false
  [ "$(jq -c '.deniedMcpServers' "$f")" = '[{"serverName":"old-server"},{"serverName":"claude.ai Claude Docs"}]' ] || { jq -c . "$f"; false; }
  [ "$(jq -c '.skillOverrides' "$f")" = '{"x:y":"off","anthropic-skills:docs":"off"}' ] || { jq -c . "$f"; false; }
  [ "$(jq -r '.env.MCP_TIMEOUT' "$f")" = "30000" ] || false
  jq -e '.hooks.Stop == []' "$f" >/dev/null || false
  for a in next secondary tertiary quaternary; do
    [ -L "$HOME/.claude-$a/settings.json" ] || { echo "$a was re-forked into a real file"; false; }
    jq -e 'any(.deniedMcpServers[]; .serverName == "claude.ai Claude Docs")' "$HOME/.claude-$a/settings.json" >/dev/null || false
  done
}

@test "5: the deny names exactly the Claude Docs connector and no other claude.ai connector" {
  bash "$M" --confirm settings.json >/dev/null
  run jq -r '.deniedMcpServers[].serverName' "$HOME/.claude/settings.json"
  [ "$output" = "$(printf 'old-server\nclaude.ai Claude Docs')" ] || { echo "$output"; false; }
  ! grep -Eq 'disableClaudeAiConnectors|ENABLE_CLAUDEAI_MCP_SERVERS' "$HOME/.claude/settings.json" || false
}

@test "6: a second run is a no-op with no second backup" {
  bash "$M" --confirm settings.json >/dev/null
  run bash "$M" --confirm settings.json
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"already applied"* ]] || { echo "$output"; false; }
  [ "$(nbak)" -eq 1 ] || false
  [ "$(jq '[.deniedMcpServers[] | select(.serverName == "claude.ai Claude Docs")] | length' "$HOME/.claude/settings.json")" -eq 1 ] || false
}

@test "7: a forked account is refused and NOTHING is written (all accounts or none)" {
  rm "$HOME/.claude-tertiary/settings.json"
  cp "$HOME/.claude/settings.json" "$HOME/.claude-tertiary/settings.json"
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/shared.before"
  run bash "$M" --confirm settings.json
  [ "$status" -ne 0 ] || { echo "ran over a forked fleet: $output"; false; }
  [[ "$output" == *"REFUSED"* ]] || { echo "$output"; false; }
  cmp -s "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/shared.before" || false
  [ "$(nbak)" -eq 0 ] || false
}

@test "8: a non-array deniedMcpServers fails and changes nothing" {
  jq -n '{deniedMcpServers:"oops"}' > "$HOME/.claude/settings.json"
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/bad.before"
  run bash "$M" --confirm settings.json
  [ "$status" -ne 0 ] || false
  cmp -s "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/bad.before" || false
}
