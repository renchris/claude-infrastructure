#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2088  # fixture strings carry literal $HOME/~ exactly as settings.json stores them
# migrations/0050 — the research block's "*" registration and the router's 10 s timeout (wave B1 of
# docs/plans/RESEARCH_PROGRAM_BUILD.md; REPORT.md §4.1, §4.2, §8 item 6). Same fixture shape as
# tests/c10-settings-migrations.bats: one shared settings.json every account dir links to.
# Hermetic: scratch HOME, the repo's own bin/cc-settings-parity via CC_SETTINGS_PARITY_BIN.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_SETTINGS_PARITY_BIN="$REPO/bin/cc-settings-parity"
  unset CC_MIGRATION_STATE
  mkdir -p "$HOME/.claude/hooks"
  printf '{"accounts":[{"name":"next","config_dir":"~/.claude-next"},{"name":"next2","config_dir":"~/.claude-secondary"},{"name":"next3","config_dir":"~/.claude-tertiary"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  jq -n '{
    hooks: {
      PreToolUse: [{matcher: "*", hooks: [{type: "command", command: "~/.claude/hooks/unit-gate.sh"}]},
                   {matcher: "Bash", hooks: [{type: "command", command: "~/.claude/hooks/validate-bash.sh", timeout: 10}]}],
      UserPromptSubmit: [{hooks: [{type: "command", command: "~/.claude/hooks/mailbox-drain.sh", timeout: 5},
                                  {type: "command", command: "~/.claude/hooks/research-precognition-nudge.sh", timeout: 5}]}]},
    permissions: {allow: ["Read"]}
  }' > "$HOME/.claude/settings.json"
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"; ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
  done
  : > "$HOME/.claude/hooks/research-block.sh"
  S="$HOME/.claude/settings.json"
}

mig() { bash "$REPO/migrations/0050-research-block-registration.sh" "$@"; }

@test "0050: --check passes on a linked fleet and writes nothing; --verify reads not-applied" {
  local before; before="$(shasum "$S")"
  run mig --check
  [ "$status" -eq 0 ]
  [ "$(shasum "$S")" = "$before" ]
  run mig --verify
  [ "$status" -eq 1 ]
}

@test "0050: appends its own '*' group, raises only the router's timeout, verifies, and is idempotent" {
  run mig --confirm settings.json
  [ "$status" -eq 0 ]
  [ "$(jq -c '.hooks.PreToolUse[-1]' "$S")" = '{"matcher":"*","hooks":[{"type":"command","command":"~/.claude/hooks/research-block.sh","timeout":5}]}' ]
  [ "$(jq -c '.hooks.PreToolUse[0]' "$S")" = '{"matcher":"*","hooks":[{"type":"command","command":"~/.claude/hooks/unit-gate.sh"}]}' ]
  [ "$(jq '.hooks.UserPromptSubmit[0].hooks[1].timeout' "$S")" = 10 ]
  [ "$(jq '.hooks.UserPromptSubmit[0].hooks[0].timeout' "$S")" = 5 ]
  [ "$(jq -c .permissions "$S")" = '{"allow":["Read"]}' ]
  for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ]; done
  run mig --verify
  [ "$status" -eq 0 ]
  run mig --confirm settings.json
  [[ "$output" == *"already applied"* ]] || false
  [ "$(jq '[.hooks.PreToolUse[] | select(.hooks[].command == "~/.claude/hooks/research-block.sh")] | length' "$S")" = 1 ]
}

@test "0050: a FORKED account ⇒ rc 3, nothing written" {
  rm "$HOME/.claude-next/settings.json"; cp "$S" "$HOME/.claude-next/settings.json"
  local before; before="$(shasum "$S")"
  run mig --confirm settings.json
  [ "$status" -eq 3 ]
  [ "$(shasum "$S")" = "$before" ]
}

@test "0050: refuses (rc 4) while the live hook file is absent" {
  rm "$HOME/.claude/hooks/research-block.sh"
  run mig --check
  [ "$status" -eq 4 ]
}

@test "0050: refuses when the router is not registered at all — the block would read every turn as unlabeled" {
  jq 'del(.hooks.UserPromptSubmit)' "$S" > "$S.tmp" && cat "$S.tmp" > "$S" && rm "$S.tmp"
  run mig --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"not registered as a UserPromptSubmit hook"* ]] || false
}

@test "0050: usage — a bare invocation outside the converger and an unnamed --confirm are refused (rc 2)" {
  run mig
  [ "$status" -eq 2 ]
  run mig --confirm
  [ "$status" -eq 2 ]
}
