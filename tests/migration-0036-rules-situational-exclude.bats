#!/usr/bin/env bats
# migration 0036 — item F4 of docs/research/token-efficiency-2026-09-23/OPPORTUNITIES.md.
#
# 0036 stages the claudeMdExcludes glob for the situational half of the split rules file in the ONE
# shared ~/.claude/settings.json every account links to since 0037 (c10: staged for the operator,
# never self-run). Rewritten 2026-09-24: the first version wrote to one account's file, which after
# 0037 is a symlink to the shared file, so it would have changed the whole fleet while claiming one.
# Pins: the class is c10 and the step line says all accounts; the verify oracle discriminates and is
# config-dir invariant; the edit keeps every sibling key and prior exclude and keeps every account
# LINKED; a second run is a no-op; and a fleet that is not converged is refused untouched.
#
# Hermetic: $HOME is a fixture under BATS_TEST_TMPDIR; the real bin/cc-settings-parity runs against
# fixture account dirs through its CC_PARITY_DIRS seam, so nothing reads the operator's config.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  M="$REPO_ROOT/migrations/0036-rules-situational-exclude.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_SETTINGS_PARITY_BIN CC_PARITY_CANONICAL CC_PARITY_ACCOUNTS_JSON
  mkdir -p "$HOME/.claude/bin"
  ln -s "$REPO_ROOT/bin/cc-settings-parity" "$HOME/.claude/bin/cc-settings-parity"
  jq -n '{env:{MCP_TIMEOUT:"30000"}, claudeMdExcludes:["/tmp/x/**"], hooks:{Stop:[]}}' > "$HOME/.claude/settings.json"
  CC_PARITY_DIRS=""
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
  G='**/.claude/rules/agent-operating-lessons-situational.md'
}

header() { sed -n "s/^# *migration-$1: *//p" "$M" | head -1; }

@test "1: 0036 is c10 and its step line names the shared file and all accounts, not one" {
  [ "$(header class)" = "c10" ]
  step="$(header step)"
  [[ "$step" == *"~/.claude/settings.json"* ]] || { echo "$step"; false; }
  [[ "$step" == *"ALL accounts"* ]] || { echo "$step"; false; }
  ! grep -v '^[[:space:]]*#' "$M" | grep -q 'CC_RULES_SPLIT_ACCOUNT_DIR' || { echo "per-account override still in code"; false; }
}

@test "2: the verify oracle fails before and passes after, from every CC_CLAUDE_DIR" {
  verify="$(header verify)"
  for d in "$HOME/.claude" "$HOME/.claude-tertiary"; do
    run env CC_CLAUDE_DIR="$d" bash -c "$verify"
    [ "$status" -ne 0 ] || { echo "oracle passed BEFORE the migration ran ($d)"; false; }
  done
  run bash "$M"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  for d in "$HOME/.claude" "$HOME/.claude-tertiary"; do
    run env CC_CLAUDE_DIR="$d" bash -c "$verify"
    [ "$status" -eq 0 ] || { echo "oracle failed AFTER ($d)"; false; }
  done
}

@test "3: glob appended to the shared file; siblings survive; every account still LINKED and sees it" {
  run bash "$M"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  f="$HOME/.claude/settings.json"
  [ ! -L "$f" ] || false
  [ "$(jq -c '.claudeMdExcludes' "$f")" = "$(jq -nc --arg g "$G" '["/tmp/x/**", $g]')" ] || false
  [ "$(jq -r '.env.MCP_TIMEOUT' "$f")" = "30000" ] || false
  jq -e '.hooks.Stop == []' "$f" >/dev/null || false
  for a in next secondary tertiary quaternary; do
    [ -L "$HOME/.claude-$a/settings.json" ] || { echo "$a was re-forked into a real file"; false; }
    jq -e --arg g "$G" '.claudeMdExcludes | any(.[]; . == $g)' "$HOME/.claude-$a/settings.json" >/dev/null || false
  done
}

@test "4: a second run is a no-op with no second backup" {
  bash "$M" >/dev/null
  run bash "$M"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"already present"* ]] || false
  [ "$(find "$HOME/.claude" -maxdepth 1 -name 'settings.json.bak-0036-*' | wc -l | tr -d ' ')" -eq 1 ] || false
  [ "$(jq --arg g "$G" '[.claudeMdExcludes[] | select(. == $g)] | length' "$HOME/.claude/settings.json")" -eq 1 ] || false
}

@test "5: a forked account is refused and NOTHING is written (all accounts or none)" {
  rm "$HOME/.claude-tertiary/settings.json"
  cp "$HOME/.claude/settings.json" "$HOME/.claude-tertiary/settings.json"
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/shared.before"
  run bash "$M"
  [ "$status" -ne 0 ] || { echo "ran over a forked fleet: $output"; false; }
  [[ "$output" == *"refusing"* ]] || { echo "$output"; false; }
  cmp -s "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/shared.before" || false
  cmp -s "$HOME/.claude-tertiary/settings.json" "$BATS_TEST_TMPDIR/shared.before" || false
  [ "$(find "$HOME/.claude" -maxdepth 1 -name 'settings.json.bak-0036-*' | wc -l | tr -d ' ')" -eq 0 ] || false
}

@test "6: a non-array claudeMdExcludes fails and changes nothing" {
  jq -n '{claudeMdExcludes:"oops"}' > "$HOME/.claude/settings.json"
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/bad.before"
  run bash "$M"
  [ "$status" -ne 0 ] || false
  cmp -s "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/bad.before" || false
}
