#!/usr/bin/env bats
# cc-settings-parity + migration 0037 — every Claude account runs ONE settings.json.
#
# Operator ruling 2026-09-23: accounts are interchangeable, so any per-account settings difference is
# a defect. Pinned here: `check` says PARITY only when every account's settings.json is a symlink to
# the shared file, and otherwise names the account and the differing keys — a real-file copy is
# FORKED even when identical, because identical copies are how every fork started; `converge
# --dry-run` prints the per-account diff and writes nothing; `converge` backs up, folds the ruled
# differences into the shared file, links every account, and is a no-op the second time; it refuses,
# writing nothing, on an account-only key or hook command nobody has ruled on; the SessionStart hook
# carries the divergence line for its own account and is silent once linked.
#
# Hermetic: scratch HOME with its own accounts.json, shared settings and four account dirs.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TOOL="$REPO/bin/cc-settings-parity"
  MIG="$REPO/migrations/0037-settings-parity.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  printf '{"accounts":[{"name":"next","config_dir":"~/.claude-next"},{"name":"next2","config_dir":"~/.claude-secondary"},{"name":"next3","config_dir":"~/.claude-tertiary"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "effortLevel": "medium",
  "tui": "default",
  "cleanupPeriodDays": 365,
  "attribution": {"commit": "", "pr": ""},
  "permissions": {"allow": ["Bash(ls:*)"], "deny": ["Bash(rm -rf /:*)"]},
  "autoMode": {"soft_deny": ["A", "B"]},
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "~/.claude/hooks/guard.sh", "timeout": 10}]}],
    "PostToolUseFailure": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "~/.claude/hooks/log-bash.sh", "timeout": 5}]}]
  }
}
JSON
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
  done
}

# Replace one account's link with a real file holding $2 (JSON).
fork() { rm -f "$HOME/.claude-$1/settings.json"; printf '%s\n' "$2" > "$HOME/.claude-$1/settings.json"; }
# A realistic divergent account: behind on hooks and soft_deny, its own effort/tui, account-only keys.
fork_realistic() {
  fork next '{
    "effortLevel": "low", "tui": "fullscreen",
    "attribution": {"commit": "", "pr": "", "sessionUrl": false},
    "enableAllProjectMcpServers": true,
    "modelSettings": {"claude-fable-5-1": {"effortLevel": "xhigh"}},
    "permissions": {"allow": ["Bash(ls:*)", "Bash(kitten @ ls:*)"], "deny": ["Bash(rm -rf /:*)"]},
    "autoMode": {"soft_deny": ["A"]},
    "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "~/.claude/hooks/guard.sh", "timeout": 30}]}]}
  }'
}
sums() { for f in "$HOME"/.claude/settings.json "$HOME"/.claude-*/settings.json; do [ -L "$f" ] && printf 'L ' ; shasum "$f"; done; }
linked() { [ -L "$HOME/.claude-$1/settings.json" ] && [ "$(readlink "$HOME/.claude-$1/settings.json")" = "$HOME/.claude/settings.json" ]; }

@test "check: every account linked ⇒ PARITY, exit 0" {
  run "$TOOL" check
  [ "$status" -eq 0 ]
  [ "$output" = "PARITY — 4 account(s) share ~/.claude/settings.json" ]
}

@test "check: an identical real-file copy is still FORKED (exit 1) — copies are how forks start" {
  fork tertiary "$(cat "$HOME/.claude/settings.json")"
  run "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"DIVERGED .claude-tertiary: a FORKED real file, not a symlink to the shared file; identical today, will drift"* ]] || false
  [[ "$output" != *".claude-next"* ]]
}

@test "check: a divergent fork names the account and each differing key" {
  fork_realistic
  run "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"DIVERGED .claude-next: a FORKED real file"* ]] || false
  [[ "$output" == *"effortLevel"* ]] || false
  [[ "$output" == *"hooks.PostToolUseFailure"* ]] || false
  [[ "$output" == *"autoMode.soft_deny"* ]] || false
  [[ "$output" == *"0037-settings-parity.sh --dry-run"* ]]
}

@test "check: a link to some OTHER file and a missing settings.json are both divergence" {
  printf '{"tui":"default"}\n' > "$HOME/elsewhere.json"
  rm "$HOME/.claude-secondary/settings.json"; ln -s "$HOME/elsewhere.json" "$HOME/.claude-secondary/settings.json"
  rm "$HOME/.claude-quaternary/settings.json"
  run "$TOOL" check
  [ "$status" -eq 1 ]
  [[ "$output" == *".claude-secondary: a symlink to ~/elsewhere.json, not the shared file"* ]] || false
  [[ "$output" == *".claude-quaternary: NO settings.json"* ]]
}

@test "check --account-dir --brief: silent when linked, one line when forked" {
  run "$TOOL" check --account-dir "$HOME/.claude-next" --brief
  [ "$status" -eq 0 ]; [ -z "$output" ]
  fork_realistic
  run "$TOOL" check --account-dir "$HOME/.claude-next" --brief
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "⚠ settings.json DIVERGES from the shared ~/.claude/settings.json — .claude-next: "* ]]
}

@test "converge --dry-run: prints the per-account diff and writes NOTHING" {
  fork_realistic
  before="$(sums)"
  run bash "$MIG" --dry-run
  [ "$status" -eq 0 ]
  [ "$(sums)" = "$before" ]
  [[ "$output" == *"DRY-RUN (nothing written)"* ]] || false
  [[ "$output" == *"~/.claude-next/settings.json (real file -> symlink to the shared file):"* ]] || false
  [[ "$output" == *'~ effortLevel: "low" -> "high"'* ]] || false
  [[ "$output" == *'~ tui: "fullscreen" -> "default"'* ]] || false
  [[ "$output" == *"- enableAllProjectMcpServers (was true)"* ]] || false
  [[ "$output" == *"+ hooks.PostToolUseFailure:"* ]] || false
  [[ "$output" == *"+ [Bash] ~/.claude/hooks/log-bash.sh (timeout 5)"* ]] || false
  [[ "$output" == *"1 account file(s) would become symlinks"* ]] || false
  [ ! -d "$HOME/.claude/backups" ]
}

@test "converge: backs up, folds rulings into the shared file, links every account, reads back PARITY" {
  fork_realistic
  cp "$HOME/.claude-next/settings.json" "$BATS_TEST_TMPDIR/next.orig"
  cp "$HOME/.claude/settings.json" "$BATS_TEST_TMPDIR/shared.orig"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PARITY — 4 account(s) share ~/.claude/settings.json"* ]] || false
  for a in next secondary tertiary quaternary; do linked "$a"; done
  S="$HOME/.claude/settings.json"
  [ "$(jq -r .effortLevel "$S")" = high ]                        # overlay: SSOT effort
  [ "$(jq -r .attribution.sessionUrl "$S")" = false ]            # promoted
  [ "$(jq -r .tui "$S")" = default ]                             # shared wins until ruled
  [ "$(jq -r 'has("enableAllProjectMcpServers")' "$S")" = false ] # dropped
  [ "$(jq -r 'has("modelSettings")' "$S")" = false ]              # dropped
  jq -e '.permissions.allow | index("Bash(kitten @ ls:*)")' "$S" >/dev/null   # allow is a UNION
  [ "$(jq -r '.autoMode.soft_deny|length' "$S")" -eq 2 ]          # shared superset kept
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].timeout' "$S")" -eq 10 ] # shared hook entry wins
  [ "$(jq -r '.cleanupPeriodDays' "$S")" -eq 365 ]
  b="$(ls -d "$HOME"/.claude/backups/settings-parity-0037-*)"
  cmp -s "$b/claude-next.settings.json" "$BATS_TEST_TMPDIR/next.orig"
  cmp -s "$b/shared.settings.json" "$BATS_TEST_TMPDIR/shared.orig"
  run "$TOOL" check
  [ "$status" -eq 0 ]
}

@test "converge: a second run is a no-op" {
  fork_realistic
  bash "$MIG" >/dev/null
  before="$(sums)"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already converged"* ]] || false
  [ "$(sums)" = "$before" ]
}

@test "converge REFUSES, writing nothing, on an account-only key no ruling covers" {
  fork quaternary '{"tui":"default","someNewKnob":true}'
  before="$(sums)"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSING"* ]] || false
  [[ "$output" == *".claude-quaternary: key 'someNewKnob' exists only in this account"* ]] || false
  [ "$(sums)" = "$before" ]
  [ ! -d "$HOME/.claude/backups" ]
}

@test "converge REFUSES, writing nothing, on a hook command the shared file never runs" {
  fork secondary '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/.claude/hooks/only-here.sh"}]}]}}'
  before="$(sums)"
  run bash "$MIG" --dry-run
  [ "$status" -eq 1 ]
  [[ "$output" == *".claude-secondary: hook Stop -> '~/.claude/hooks/only-here.sh' exists only in this account"* ]] || false
  [ "$(sums)" = "$before" ]
}

@test "converge: a hook differing only by timeout is not a new hook — shared wins, no refusal" {
  fork tertiary '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"~/.claude/hooks/guard.sh","timeout":99}]}]}}'
  run bash "$MIG"
  [ "$status" -eq 0 ]
  linked tertiary
}

@test "migration: an unknown argument is a usage error and writes nothing" {
  fork_realistic
  before="$(sums)"
  run bash "$MIG" --force
  [ "$status" -eq 2 ]
  [ "$(sums)" = "$before" ]
}

@test "SessionStart hook: carries the divergence line for its own account, silent once linked" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not installed"
  mkdir -p "$HOME/.claude/lib" "$HOME/.claude/bin"
  printf '_cc_sync_account() { :; }\n' > "$HOME/.claude/lib/config-mirror.zsh"
  ln -s "$TOOL" "$HOME/.claude/bin/cc-settings-parity"
  export CLAUDE_CONFIG_DIR="$HOME/.claude-next"
  run bash "$REPO/hooks/config-mirror-assert.sh"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  fork_realistic
  run bash "$REPO/hooks/config-mirror-assert.sh"
  [ "$status" -eq 0 ]
  c="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$c" == *"settings.json DIVERGES from the shared ~/.claude/settings.json — .claude-next:"* ]]
}
