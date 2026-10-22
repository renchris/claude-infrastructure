#!/usr/bin/env bats
# migration 0075 (remove the blanket `Bash(git push:*)` ask; validate-bash's PUSH arm decides) —
# docs/research/permission-prompt-reduction-2026-10-20/REPORT.md. c10: staged for the operator,
# never self-run. Pins: nothing is written without --confirm; it REFUSES while the live hook lacks
# the push check; the verify oracle discriminates; only that one ask entry changes (the force-push
# denies and the other asks stay); every account stays LINKED; a second run is a no-op.
#
# Hermetic: $HOME is a fixture; the real bin/cc-settings-parity runs over fixture account dirs through
# its CC_PARITY_DIRS seam, and the "live hook" is a fixture file through CC_0075_LIVE_HOOK.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_SETTINGS_PARITY_BIN CC_PARITY_CANONICAL CC_PARITY_ACCOUNTS_JSON CC_MIGRATION_STATE CC_MIGRATION_REPO
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/telemetry"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/hooks"
  ln -s "$REPO_ROOT/bin/cc-settings-parity" "$HOME/.claude/bin/cc-settings-parity"
  jq -n '{env:{A:"1"}, permissions:{
    allow:["Bash(git add:*)"],
    ask:["Bash(fly deploy:*)","Bash(git push:*)","Bash(git stash clear:*)"],
    deny:["Bash(git push --force:*)","Bash(git push -f:*)"]}}' > "$HOME/.claude/settings.json"
  CC_PARITY_DIRS=""
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
  export CC_0075_LIVE_HOOK="$HOME/.claude/hooks/validate-bash.sh"
  cp "$REPO_ROOT/hooks/validate-bash.sh" "$CC_0075_LIVE_HOOK"      # the hook WITH the push arm
  S="$HOME/.claude/settings.json"
  M="$REPO_ROOT/migrations/0075-git-push-ask-to-hook.sh"
}

@test "c10 with a --confirm run line, and the shipped hook carries the arm it gates on" {
  grep -q '^# migration-class: c10' "$M"
  grep -q '^# migration-run: bash .*0075-git-push-ask-to-hook.sh --confirm settings.json' "$M"
  grep -q '_go_push_owned' "$REPO_ROOT/hooks/validate-bash.sh"
}

@test "no --confirm ⇒ nothing written (bare, wrong target, --dry-run, --check)" {
  before="$(cat "$S")"
  run /bin/bash "$M"; [ "$status" -eq 2 ]
  run /bin/bash "$M" --confirm other.json; [ "$status" -eq 2 ]
  run /bin/bash "$M" --dry-run; [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]] || false
  run /bin/bash "$M" --check; [ "$status" -eq 0 ]
  [ "$(cat "$S")" = "$before" ]
}

@test "REFUSES while the live hook lacks the push check, and writes nothing" {
  printf '#!/bin/bash\n# a pre-0075 hook\n' > "$CC_0075_LIVE_HOOK"
  before="$(cat "$S")"
  run /bin/bash "$M" --confirm settings.json
  [ "$status" -eq 4 ]
  [[ "$output" == *"REFUSED"* ]] || false
  [ "$(cat "$S")" = "$before" ]
}

@test "verify discriminates; apply removes exactly the one entry and keeps every account linked" {
  run /bin/bash "$M" --verify; [ "$status" -ne 0 ]
  run /bin/bash "$M" --confirm settings.json; [ "$status" -eq 0 ]
  run /bin/bash "$M" --verify; [ "$status" -eq 0 ]
  [ "$(jq -c '.permissions.ask' "$S")" = '["Bash(fly deploy:*)","Bash(git stash clear:*)"]' ]
  [ "$(jq -c '.permissions.deny' "$S")" = '["Bash(git push --force:*)","Bash(git push -f:*)"]' ]
  [ "$(jq -c '.permissions.allow, .env' "$S" | tr -d '\n')" = '["Bash(git add:*)"]{"A":"1"}' ]
  for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ]; done
  compgen -G "$HOME/.claude/backups/git-push-ask-0075-*" >/dev/null
}

@test "a second run is a no-op" {
  /bin/bash "$M" --confirm settings.json
  after="$(cat "$S")"
  run /bin/bash "$M" --confirm settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]] || false
  [ "$(cat "$S")" = "$after" ]
}

@test "a forked account is refused untouched" {
  rm "$HOME/.claude-next/settings.json"; cp "$S" "$HOME/.claude-next/settings.json"
  jq '.env.B = "2"' "$HOME/.claude-next/settings.json" > "$BATS_TEST_TMPDIR/x" && mv "$BATS_TEST_TMPDIR/x" "$HOME/.claude-next/settings.json"
  before="$(cat "$S")"
  run /bin/bash "$M" --confirm settings.json
  [ "$status" -eq 3 ]
  [ "$(cat "$S")" = "$before" ]
}
