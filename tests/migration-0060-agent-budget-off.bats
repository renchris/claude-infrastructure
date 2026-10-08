#!/usr/bin/env bats
# Migration 0060 — adds env.CLAUDE_CODE_RIPPLING_TULIP=0 (decision D6) to the ONE shared settings.json.
#
# Pinned: --dry-run/--check write nothing; --confirm adds exactly that key and changes no other byte
# of meaning, keeps every account a symlink and reads back through --verify; a second run is a no-op;
# a FORKED account and a DIFFERENT value (a budget set on purpose) are each refused rc 3 with nothing
# written (the second also reads as --conflict); usage errors are rc 2.
#
# Hermetic: scratch HOME, the repo's own bin/cc-settings-parity via CC_SETTINGS_PARITY_BIN.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0060-agent-budget-off.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_SETTINGS_PARITY_BIN="$REPO/bin/cc-settings-parity"
  unset CC_MIGRATION_STATE
  mkdir -p "$HOME/.claude"
  printf '{"accounts":[{"name":"next","config_dir":"~/.claude-next"},{"name":"next2","config_dir":"~/.claude-secondary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  jq -n '{
    env: {MCP_TIMEOUT: "30000", CLAUDE_CODE_CERT_STORE: "bundled"},
    permissions: {allow: ["Bash(git add:*)"], defaultMode: "auto"}
  }' > "$HOME/.claude/settings.json"
  for a in next secondary; do
    mkdir -p "$HOME/.claude-$a"; ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
  done
  F="$HOME/.claude/settings.json"
}

mig() { bash "$MIG" "$@"; }

@test "0060: the c10 headers the converger and the batch read are all present" {
  for h in 'migration-class: c10' 'migration-step: ' 'migration-run: ' 'migration-verify: ' 'migration-conflict: '; do
    grep -q "^# $h" "$MIG" || { echo "missing header: $h"; false; }
  done
}

@test "0060: --dry-run and --check write nothing; --verify and --conflict read rc 1 before apply" {
  local before; before="$(shasum "$F")"
  for m in --dry-run --check; do
    run mig "$m"
    [ "$status" -eq 0 ] || { echo "$m: $output"; false; }
  done
  [ "$(shasum "$F")" = "$before" ]
  run mig --verify;   [ "$status" -eq 1 ]
  run mig --conflict; [ "$status" -eq 1 ]
}

@test "0060: --confirm adds exactly the one env key, keeps links, verifies, and a re-run is a no-op" {
  local orig; orig="$(cat "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -L "$HOME/.claude-next/settings.json" ]
  [ -L "$HOME/.claude-secondary/settings.json" ]
  jq -e '.env == {MCP_TIMEOUT: "30000", CLAUDE_CODE_CERT_STORE: "bundled", CLAUDE_CODE_RIPPLING_TULIP: "0"}' "$F" >/dev/null
  jq -en --argjson a "$orig" --slurpfile b "$F" '($a | del(.env)) == ($b[0] | del(.env))' >/dev/null
  run mig --verify;   [ "$status" -eq 0 ]
  run mig --conflict; [ "$status" -eq 1 ]
  local after; after="$(shasum "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ]; [[ "$output" == *"already applied"* ]] || false
  [ "$(shasum "$F")" = "$after" ]
}

@test "0060: a hand-typed JSON number 0 reads as applied, not as a conflict" {
  jq '.env.CLAUDE_CODE_RIPPLING_TULIP = 0' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
  run mig --verify;   [ "$status" -eq 0 ]
  run mig --conflict; [ "$status" -eq 1 ]
}

@test "0060: a FORKED account ⇒ rc 3, nothing written anywhere" {
  rm "$HOME/.claude-next/settings.json"; cp "$F" "$HOME/.claude-next/settings.json"
  local b1; b1="$(shasum "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(shasum "$F")" = "$b1" ]
}

@test "0060: a budget already set on purpose is refused rc 3, never overwritten, and reads as --conflict" {
  jq '.env.CLAUDE_CODE_RIPPLING_TULIP = "200000"' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
  local before; before="$(shasum "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(shasum "$F")" = "$before" ]
  run mig --conflict; [ "$status" -eq 0 ]
  run mig --verify;   [ "$status" -eq 1 ]
}

@test "0060: usage — bare outside the converger, an unnamed --confirm, a stray trailing arg ⇒ rc 2" {
  local before; before="$(shasum "$F")"
  run mig;                                  [ "$status" -eq 2 ]
  run mig --confirm;                        [ "$status" -eq 2 ]
  run mig --confirm settings.json --probe;  [ "$status" -eq 2 ]
  run mig --bogus;                          [ "$status" -eq 2 ]
  [ "$(shasum "$F")" = "$before" ]
}
