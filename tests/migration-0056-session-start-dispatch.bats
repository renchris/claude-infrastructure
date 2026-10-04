#!/usr/bin/env bats
# migration-0056 — SessionStart regrouping (migrations/0056-session-start-dispatch.sh, fix row 17).
# The fixture is the LIVE 18-hook SessionStart layout as of 2026-10-04, transcribed verbatim, so the
# assertions are about the document the operator will actually run this against.

SS_LIVE='[{"hooks":[{"type":"command","command":"~/.claude/hooks/session-start.sh","timeout":10},{"type":"command","command":"~/.claude/hooks/setup-plan-symlinks.sh","timeout":5},{"type":"command","command":"~/.claude/hooks/setup-task-symlinks.sh","timeout":5},{"type":"command","command":"~/.claude/hooks/pre-session-validate.sh","timeout":10},{"type":"command","command":"~/.claude/hooks/lead-crash-watchdog.sh","timeout":10},{"type":"command","command":"~/.claude/hooks/session-register.sh","timeout":5},{"type":"command","command":"~/.claude/hooks/activation-watch.sh","timeout":5},{"type":"command","command":"~/.claude/hooks/dod-persist.sh","timeout":5},{"type":"command","command":"~/.claude/hooks/desk-brief-inject.sh","timeout":5},{"type":"command","command":"~/.claude/hooks/mailbox-wake-arm.sh","timeout":14400,"asyncRewake":true,"rewakeMessage":"📬 Peer mail arrived while you were idle — delivered by the inbox watcher, not typed by you:","rewakeSummary":"📬 peer mail"},{"type":"command","command":"~/.claude/hooks/escalation-watch.sh","timeout":10},{"type":"command","command":"~/.claude/hooks/accounts-board.sh","timeout":5}]},{"hooks":[{"type":"command","command":"~/.claude/hooks/session-index-start.sh","timeout":5}]},{"hooks":[{"type":"command","command":"~/.claude/hooks/config-mirror-assert.sh","timeout":8}]},{"hooks":[{"type":"command","command":"~/.claude/hooks/frontier-status.sh","timeout":5}]},{"hooks":[{"type":"command","command":"~/.claude/hooks/live-session-registry.sh","timeout":5}]},{"hooks":[{"type":"command","command":"~/.claude/hooks/mailbox-drain.sh session-start","timeout":5},{"type":"command","command":"~/.claude/hooks/net-context-stamp.sh","timeout":5}]}]'

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_SETTINGS_PARITY_BIN="$REPO/bin/cc-settings-parity"
  unset CC_MIGRATION_STATE
  export CC_ACCOUNTS_BOARD="$BATS_TEST_TMPDIR/claude-accounts-board.txt"   # pinned: an absolute /tmp default
  mkdir -p "$HOME/.claude/hooks"
  printf '{"accounts":[{"name":"next","config_dir":"~/.claude-next"},{"name":"next2","config_dir":"~/.claude-secondary"},{"name":"next3","config_dir":"~/.claude-tertiary"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  jq -n --argjson ss "$SS_LIVE" '{hooks: {SessionStart: $ss,
      Stop: [{hooks: [{type: "command", command: "~/.claude/hooks/session-continue.sh"}]}]},
    permissions: {allow: ["Read"]}}' > "$HOME/.claude/settings.json"
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"; ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
  done
  printf '#!/bin/bash\n' > "$HOME/.claude/hooks/session-start-dispatch.sh"
  chmod +x "$HOME/.claude/hooks/session-start-dispatch.sh"
  S="$HOME/.claude/settings.json"
}

mig() { bash "$REPO/migrations/0056-session-start-dispatch.sh" "$@"; }
cmds() { jq -r '[.hooks.SessionStart[].hooks[].command] | .[]' "$S"; }

@test "0056: --check passes on a linked fleet and writes nothing; --verify reads not-applied" {
  local before; before="$(shasum "$S")"
  run mig --check
  [ "$status" -eq 0 ]
  [ "$(shasum "$S")" = "$before" ]
  run mig --verify
  [ "$status" -eq 1 ]
}

@test "0056: 18 registrations become 10 — nine folded, one dispatcher, async on five, the rest untouched" {
  run mig --confirm settings.json
  [ "$status" -eq 0 ]
  [ "$(cmds | wc -l | tr -d ' ')" -eq 10 ]
  for c in session-start setup-plan-symlinks setup-task-symlinks activation-watch escalation-watch \
           accounts-board session-index-start config-mirror-assert frontier-status; do
    # shellcheck disable=SC2088  # the literal "~/" is what settings.json stores
    ! cmds | grep -qx "~/.claude/hooks/$c.sh" || { echo "$c still registered"; false; }
  done
  [ "$(jq -c '.hooks.SessionStart[-1]' "$S")" = '{"hooks":[{"type":"command","command":"~/.claude/hooks/session-start-dispatch.sh","timeout":12}]}' ]
  for c in pre-session-validate lead-crash-watchdog session-register live-session-registry net-context-stamp; do
    # shellcheck disable=SC2088  # the literal "~/" is what settings.json stores
    [ "$(jq --arg c "~/.claude/hooks/$c.sh" '[.hooks.SessionStart[].hooks[] | select(.command == $c) | .async] == [true]' "$S")" = true ]
  done
  # the four kept hooks are byte-identical entries, mailbox-wake-arm's asyncRewake included
  [ "$(jq -c '[.hooks.SessionStart[].hooks[] | select(.command | test("dod-persist|desk-brief|mailbox-"))]' "$S")" = \
    "$(jq -nc --argjson ss "$SS_LIVE" '[$ss[].hooks[] | select(.command | test("dod-persist|desk-brief|mailbox-"))]')" ]
  [ "$(jq -r '[.hooks.SessionStart[].hooks[] | select(.command | test("dod-persist|desk-brief|mailbox-drain")) | has("async")] | any' "$S")" = false ]
  # emptied groups are dropped; nothing outside SessionStart moved; every account still links
  [ "$(jq '[.hooks.SessionStart[] | select((.hooks | length) == 0)] | length' "$S")" -eq 0 ]
  [ "$(jq -c '.hooks.Stop, .permissions' "$S")" = "$(printf '%s\n%s' '[{"hooks":[{"type":"command","command":"~/.claude/hooks/session-continue.sh"}]}]' '{"allow":["Read"]}')" ]
  for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ] || false; done
  run mig --verify
  [ "$status" -eq 0 ]
}

@test "0056: idempotent — a second run is 'already applied' and leaves one dispatcher" {
  mig --confirm settings.json >/dev/null
  local after; after="$(shasum "$S")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]] || false
  [ "$(shasum "$S")" = "$after" ]
  [ "$(cmds | grep -c session-start-dispatch)" -eq 1 ]
}

@test "0056: a forked account is refused (rc 3) and nothing is written" {
  rm "$HOME/.claude-tertiary/settings.json"; cp "$S" "$HOME/.claude-tertiary/settings.json"
  jq '.x = 1' "$HOME/.claude-tertiary/settings.json" > "$BATS_TEST_TMPDIR/t" && mv "$BATS_TEST_TMPDIR/t" "$HOME/.claude-tertiary/settings.json"
  local before; before="$(shasum "$S")"
  run mig --confirm settings.json
  [ "$status" -eq 3 ]
  [ "$(shasum "$S")" = "$before" ]
}

@test "0056: refused (rc 4) while the live dispatcher is absent — the nine are never dropped without it" {
  rm "$HOME/.claude/hooks/session-start-dispatch.sh"
  local before; before="$(shasum "$S")"
  run mig --confirm settings.json
  [ "$status" -eq 4 ]
  [ "$(shasum "$S")" = "$before" ]
}

@test "0056: a bare run outside the converger, or an unnamed --confirm, is a usage error (rc 2)" {
  run mig
  [ "$status" -eq 2 ]
  run mig --confirm
  [ "$status" -eq 2 ]
}
