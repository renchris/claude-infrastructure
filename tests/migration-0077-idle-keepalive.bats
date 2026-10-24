#!/usr/bin/env bats
# migration 0077 (register the log-only keepalive timer hooks/idle-keepalive.sh on Stop) —
# docs/plans/USAGE_LEVERS.md § W3. c10: staged for the operator, never self-run. Pins: nothing is
# written without --confirm; it REFUSES while the live hook is absent; the verify oracle
# discriminates; apply appends exactly one asyncRewake group and leaves every other Stop entry
# alone; every account stays LINKED; a second run is a no-op; a forked account is refused.
#
# Hermetic: $HOME is a fixture; the real bin/cc-settings-parity runs over fixture account dirs
# through its CC_PARITY_DIRS seam; the "live hook" is a copy of the repo's file under $HOME.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_SETTINGS_PARITY_BIN CC_PARITY_CANONICAL CC_PARITY_ACCOUNTS_JSON CC_MIGRATION_STATE CC_MIGRATION_REPO
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/telemetry"
  export CC_PERMPEND_DIR="$BATS_TEST_TMPDIR/permpend"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude/hooks/lib"
  ln -s "$REPO_ROOT/bin/cc-settings-parity" "$HOME/.claude/bin/cc-settings-parity"
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"/bin/bash ~/.claude/hooks/mailbox-wake-arm.sh",timeout:14400,asyncRewake:true}]},
                       {hooks:[{type:"command",command:"/bin/bash ~/.claude/hooks/cc-permission-beacon.sh clear"}]}],
                  UserPromptSubmit:[{hooks:[{type:"command",command:"x"}]}]}}' > "$HOME/.claude/settings.json"
  CC_PARITY_DIRS=""
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
  cp "$REPO_ROOT/hooks/idle-keepalive.sh" "$HOME/.claude/hooks/idle-keepalive.sh"
  cp "$REPO_ROOT/hooks/lib/idle_gap.py" "$HOME/.claude/hooks/lib/idle_gap.py"
  S="$HOME/.claude/settings.json"
  M="$REPO_ROOT/migrations/0077-idle-keepalive-timer-registration.sh"
}

@test "c10 with a --confirm run line" {
  grep -q '^# migration-class: c10' "$M"
  grep -q '^# migration-run: bash .*0077-idle-keepalive-timer-registration.sh --confirm settings.json' "$M"
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

@test "REFUSES while the live hook is absent, and writes nothing" {
  rm "$HOME/.claude/hooks/idle-keepalive.sh"
  before="$(cat "$S")"
  run /bin/bash "$M" --confirm settings.json
  [ "$status" -eq 4 ]
  [[ "$output" == *"REFUSED"* ]] || false
  [ "$(cat "$S")" = "$before" ]
}

@test "verify discriminates; apply appends one asyncRewake Stop group and keeps every account linked" {
  before_rest="$(jq -S 'del(.hooks.Stop)' "$S")"; before_stop="$(jq -c '.hooks.Stop' "$S")"
  run /bin/bash "$M" --verify; [ "$status" -ne 0 ]
  run /bin/bash "$M" --confirm settings.json; [ "$status" -eq 0 ]
  run /bin/bash "$M" --verify; [ "$status" -eq 0 ]
  [ "$(jq -S 'del(.hooks.Stop)' "$S")" = "$before_rest" ]
  [ "$(jq -c '.hooks.Stop[:-1]' "$S")" = "$before_stop" ]
  [ "$(jq -c '.hooks.Stop[-1]' "$S")" = '{"hooks":[{"type":"command","command":"/bin/bash ~/.claude/hooks/idle-keepalive.sh","timeout":14400,"asyncRewake":true}]}' ]
  for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ]; done
  compgen -G "$HOME/.claude/backups/idle-keepalive-0077-*" >/dev/null
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
