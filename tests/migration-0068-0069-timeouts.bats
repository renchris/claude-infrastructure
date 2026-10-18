#!/usr/bin/env bats
# migrations 0068 (SessionStart dispatcher 12 → 20 s) and 0069 (TeammateIdle 5 → 20 s) — Wave 6 items
# 6.1 and 6.5 of docs/research/startup-hooks-2026-10-18/README.md. c10: staged for the operator, never
# self-run. Pins: nothing is written without --confirm; the verify oracle discriminates; only the one
# timeout changes and every account stays LINKED; a second run is a no-op; a higher operator value is
# left alone; a forked fleet and an unregistered hook are refused untouched.
#
# Hermetic: $HOME is a fixture; the real bin/cc-settings-parity runs over fixture account dirs through
# its CC_PARITY_DIRS seam, so nothing reads the operator's config.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_SETTINGS_PARITY_BIN CC_PARITY_CANONICAL CC_PARITY_ACCOUNTS_JSON CC_MIGRATION_STATE
  mkdir -p "$HOME/.claude/bin"
  ln -s "$REPO_ROOT/bin/cc-settings-parity" "$HOME/.claude/bin/cc-settings-parity"
  jq -n '{env:{A:"1"}, hooks:{
    SessionStart:[{hooks:[{type:"command",command:"~/.claude/hooks/dod-persist.sh",timeout:5},
                          {type:"command",command:"~/.claude/hooks/session-start-dispatch.sh",timeout:12}]}],
    TeammateIdle:[{hooks:[{type:"command",command:"~/.claude/hooks/teammate-auto-shutdown.sh",timeout:5}]}]}}' \
    > "$HOME/.claude/settings.json"
  CC_PARITY_DIRS=""
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
  S="$HOME/.claude/settings.json"
}

m() { echo "$REPO_ROOT/migrations/$1"; }
to_of() { jq -r --arg e "$1" --arg c "$2" '.hooks[$e][].hooks[] | select(.command == $c) | .timeout' "$S"; }
# shellcheck disable=SC2088  # the literal "~/" is what settings.json stores
SSD='~/.claude/hooks/session-start-dispatch.sh'
# shellcheck disable=SC2088  # same
TAS='~/.claude/hooks/teammate-auto-shutdown.sh'

@test "both are c10 with a --confirm run line" {
  for f in 0068-ssd-timeout-20.sh 0069-teammate-idle-timeout-20.sh; do
    grep -q '^# migration-class: c10' "$(m $f)"
    grep -q "^# migration-run: bash .*$f --confirm settings.json" "$(m $f)"
  done
}

@test "no --confirm ⇒ nothing written (bare, --dry-run, --check)" {
  before="$(cat "$S")"
  run bash "$(m 0068-ssd-timeout-20.sh)"; [ "$status" -eq 2 ]
  run bash "$(m 0068-ssd-timeout-20.sh)" --dry-run; [ "$status" -eq 0 ]
  run bash "$(m 0069-teammate-idle-timeout-20.sh)" --check; [ "$status" -eq 0 ]
  [ "$(cat "$S")" = "$before" ]
}

@test "verify discriminates: false before, true after" {
  run bash "$(m 0068-ssd-timeout-20.sh)" --verify; [ "$status" -ne 0 ]
  run bash "$(m 0068-ssd-timeout-20.sh)" --confirm settings.json; [ "$status" -eq 0 ]
  run bash "$(m 0068-ssd-timeout-20.sh)" --verify; [ "$status" -eq 0 ]
}

@test "0068 changes only the dispatcher's timeout; accounts stay linked" {
  run bash "$(m 0068-ssd-timeout-20.sh)" --confirm settings.json
  [ "$status" -eq 0 ]
  [ "$(to_of SessionStart "$SSD")" = 20 ]
  # shellcheck disable=SC2088  # the literal "~/" is what settings.json stores
  [ "$(to_of SessionStart '~/.claude/hooks/dod-persist.sh')" = 5 ]
  [ "$(to_of TeammateIdle "$TAS")" = 5 ]
  [ "$(jq -r .env.A "$S")" = 1 ]
  for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ]; done
}

@test "0069 raises TeammateIdle to 20 and is idempotent" {
  run bash "$(m 0069-teammate-idle-timeout-20.sh)" --confirm settings.json; [ "$status" -eq 0 ]
  [ "$(to_of TeammateIdle "$TAS")" = 20 ]
  [ "$(to_of SessionStart "$SSD")" = 12 ]
  run bash "$(m 0069-teammate-idle-timeout-20.sh)" --confirm settings.json
  [ "$status" -eq 0 ]; [[ "$output" == *"already applied"* ]]
}

@test "a higher operator value is left alone" {
  jq '.hooks.SessionStart[0].hooks[1].timeout = 30' "$S" > "$S.t" && cat "$S.t" > "$S"
  run bash "$(m 0068-ssd-timeout-20.sh)" --confirm settings.json
  [ "$status" -eq 0 ]
  [ "$(to_of SessionStart "$SSD")" = 30 ]
}

@test "a forked fleet is refused untouched" {
  rm "$HOME/.claude-next/settings.json"; cp "$S" "$HOME/.claude-next/settings.json"
  jq '.env.B = "2"' "$HOME/.claude-next/settings.json" > "$BATS_TEST_TMPDIR/x" && cat "$BATS_TEST_TMPDIR/x" > "$HOME/.claude-next/settings.json"
  before="$(cat "$S")"
  run bash "$(m 0068-ssd-timeout-20.sh)" --confirm settings.json
  [ "$status" -eq 3 ]
  [ "$(cat "$S")" = "$before" ]
}

@test "an unregistered hook is refused (exit 4)" {
  jq 'del(.hooks.TeammateIdle)' "$S" > "$S.t" && cat "$S.t" > "$S"
  run bash "$(m 0069-teammate-idle-timeout-20.sh)" --confirm settings.json
  [ "$status" -eq 4 ]
}
