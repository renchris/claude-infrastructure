#!/usr/bin/env bats
# migration 0073 (Stop close gates completion-assert / session-continue / boundary-handoff 5 → 10 s) —
# Wave 6 item 6.8 of docs/research/startup-hooks-2026-10-18/README.md. c10: staged for the operator,
# never self-run. Pins: nothing is written without --confirm; the verify oracle discriminates; only
# the three timeouts change, whatever interpreter spelling each command carries; every account stays
# LINKED; a second run is a no-op; a higher operator value is left alone; a forked fleet and a missing
# gate are refused untouched.
#
# Hermetic: $HOME is a fixture; the real bin/cc-settings-parity runs over fixture account dirs through
# its CC_PARITY_DIRS seam, so nothing reads the operator's config.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_SETTINGS_PARITY_BIN CC_PARITY_CANONICAL CC_PARITY_ACCOUNTS_JSON CC_MIGRATION_STATE CC_MIGRATION_REPO
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/telemetry"
  mkdir -p "$HOME/.claude/bin"
  ln -s "$REPO_ROOT/bin/cc-settings-parity" "$HOME/.claude/bin/cc-settings-parity"
  # Three spellings on purpose: env-bash, bare, /bin/bash — cmd_bare must see one hook each.
  jq -n '{env:{A:"1"}, hooks:{
    Stop:[{hooks:[{type:"command",command:"/usr/bin/env bash ~/.claude/hooks/completion-assert.sh",timeout:5},
                  {type:"command",command:"~/.claude/hooks/session-continue.sh",timeout:5},
                  {type:"command",command:"/bin/bash ~/.claude/hooks/boundary-handoff.sh",timeout:5},
                  {type:"command",command:"/bin/bash ~/.claude/hooks/operator-readout.sh",timeout:5}]}],
    SessionStart:[{hooks:[{type:"command",command:"~/.claude/hooks/session-continue.sh",timeout:5}]}]}}' \
    > "$HOME/.claude/settings.json"
  CC_PARITY_DIRS=""
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
  S="$HOME/.claude/settings.json"
  M="$REPO_ROOT/migrations/0073-stop-gate-timeouts-10.sh"
}

to_of() { jq -r --arg e "$1" --arg c "$2" '.hooks[$e][].hooks[] | select(.command | endswith($c)) | .timeout' "$S"; }

@test "c10 with a --confirm run line" {
  grep -q '^# migration-class: c10' "$M"
  grep -q '^# migration-run: bash .*0073-stop-gate-timeouts-10.sh --confirm settings.json' "$M"
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

@test "verify discriminates: false before, true after" {
  run /bin/bash "$M" --verify; [ "$status" -ne 0 ]
  run /bin/bash "$M" --confirm settings.json; [ "$status" -eq 0 ]
  run /bin/bash "$M" --verify; [ "$status" -eq 0 ]
}

@test "raises exactly the three gates across spellings; the rest is byte-equal; accounts stay linked" {
  run /bin/bash "$M" --confirm settings.json
  [ "$status" -eq 0 ]
  [ "$(to_of Stop completion-assert.sh)" = 10 ]
  [ "$(to_of Stop session-continue.sh)" = 10 ]
  [ "$(to_of Stop boundary-handoff.sh)" = 10 ]
  [ "$(to_of Stop operator-readout.sh)" = 5 ]
  [ "$(to_of SessionStart session-continue.sh)" = 5 ]
  [ "$(jq -r .env.A "$S")" = 1 ]
  bk="$(ls -d "$HOME"/.claude/backups/stop-gate-timeouts-0073-*)"
  [ "$(jq -S 'del(.hooks.Stop[0].hooks[0,1,2].timeout)' "$bk/settings.json")" = "$(jq -S 'del(.hooks.Stop[0].hooks[0,1,2].timeout)' "$S")" ]
  for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ]; done
}

@test "a second run is a no-op" {
  run /bin/bash "$M" --confirm settings.json; [ "$status" -eq 0 ]
  after="$(cat "$S")"
  run /bin/bash "$M" --confirm settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]] || false
  [ "$(cat "$S")" = "$after" ]
}

@test "a higher operator value is left alone, the others still raised" {
  jq '.hooks.Stop[0].hooks[1].timeout = 30' "$S" > "$S.t" && cat "$S.t" > "$S"
  run /bin/bash "$M" --confirm settings.json
  [ "$status" -eq 0 ]
  [ "$(to_of Stop session-continue.sh)" = 30 ]
  [ "$(to_of Stop completion-assert.sh)" = 10 ]
}

@test "a forked fleet is refused untouched" {
  rm "$HOME/.claude-next/settings.json"; cp "$S" "$HOME/.claude-next/settings.json"
  jq '.env.B = "2"' "$HOME/.claude-next/settings.json" > "$BATS_TEST_TMPDIR/x" && cat "$BATS_TEST_TMPDIR/x" > "$HOME/.claude-next/settings.json"
  before="$(cat "$S")"
  run /bin/bash "$M" --confirm settings.json
  [ "$status" -eq 3 ]
  [ "$(cat "$S")" = "$before" ]
}

@test "a gate missing from Stop is refused untouched (exit 4) and named" {
  jq 'del(.hooks.Stop[0].hooks[2])' "$S" > "$S.t" && cat "$S.t" > "$S"
  before="$(cat "$S")"
  run /bin/bash "$M" --confirm settings.json
  [ "$status" -eq 4 ]
  [[ "$output" == *"boundary-handoff.sh"* ]] || false
  [ "$(cat "$S")" = "$before" ]
}
