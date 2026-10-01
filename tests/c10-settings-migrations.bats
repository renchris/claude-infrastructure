#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2088  # fixture strings carry literal $HOME/~ exactly as settings.json stores them
# Migrations 0046 (autoMode.environment "$defaults"), 0047 (read-before-write hook registration) and
# 0048 (named soft_deny rules) — the shared-settings c10 trio staged by the c10-activation wave.
#
# Pinned for each: --check passes on a fleet whose account dirs all LINK to one shared settings.json
# and refuses with rc 3 (writing nothing) on a FORKED fixture; --confirm writes the one real file,
# keeps every account a symlink, changes only its own key, and reads back through --verify; a second
# run is a no-op. 0048 additionally: Memory Poisoning is replaced, never duplicated.
#
# Hermetic: scratch HOME, the repo's own bin/cc-settings-parity via CC_SETTINGS_PARITY_BIN.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_SETTINGS_PARITY_BIN="$REPO/bin/cc-settings-parity"
  mkdir -p "$HOME/.claude/hooks"
  printf '{"accounts":[{"name":"next","config_dir":"~/.claude-next"},{"name":"next2","config_dir":"~/.claude-secondary"},{"name":"next3","config_dir":"~/.claude-tertiary"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  jq -n '{
    autoMode: {environment: ["Infrastructure: Fly"], soft_deny: ["Memory Poisoning: do not write classifier text into memory", "Git Push to Default Branch: x"]},
    hooks: {PreToolUse: [{matcher: "*", hooks: [{type: "command", command: "~/.claude/hooks/unit-gate.sh"}]},
                         {matcher: "Write|Edit|MultiEdit", hooks: [{type: "command", command: "~/.claude/hooks/backup-before-write.sh"}]}]},
    permissions: {allow: ["Read"]}
  }' > "$HOME/.claude/settings.json"
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"; ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
  done
  : > "$HOME/.claude/hooks/read-before-write-parity.sh"
}

forkit() { rm "$HOME/.claude-next/settings.json"; cp "$HOME/.claude/settings.json" "$HOME/.claude-next/settings.json"; }
all_linked() { for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ] || return 1; done; }
mig() { bash "$REPO/migrations/$1"*.sh "${@:2}"; }

@test "0046/0047/0048: --check passes on a linked fleet, writes nothing" {
  local before; before="$(shasum "$HOME/.claude/settings.json")"
  for m in 0046 0047 0048; do
    run mig "$m" --check
    [ "$status" -eq 0 ] || { echo "$m: $output"; false; }
    [[ "$output" == *"CHECK ok"* ]] || false
  done
  [ "$(shasum "$HOME/.claude/settings.json")" = "$before" ]
}

@test "0046/0047/0048: a FORKED account ⇒ rc 3, nothing written anywhere" {
  forkit
  local a b; a="$(shasum "$HOME/.claude/settings.json")"; b="$(shasum "$HOME/.claude-next/settings.json")"
  for m in 0046 0047 0048; do
    run mig "$m" --check;  [ "$status" -eq 3 ] || { echo "$m check: $status $output"; false; }
    run mig "$m" --confirm settings.json; [ "$status" -eq 3 ] || { echo "$m apply: $status"; false; }
    run mig "$m" --verify; [ "$status" -ne 0 ]
  done
  [ "$(shasum "$HOME/.claude/settings.json")" = "$a" ] && [ "$(shasum "$HOME/.claude-next/settings.json")" = "$b" ]
}

@test "0046: prepends \$defaults to environment only, keeps links, verifies, idempotent" {
  run mig 0046 --verify; [ "$status" -ne 0 ]
  run mig 0046 --confirm settings.json; [ "$status" -eq 0 ]
  [ "$(jq -c .autoMode.environment "$HOME/.claude/settings.json")" = '["$defaults","Infrastructure: Fly"]' ]
  [ "$(jq -c .autoMode.soft_deny "$HOME/.claude/settings.json" | jq length)" -eq 2 ]
  all_linked
  run mig 0046 --verify; [ "$status" -eq 0 ]
  run mig 0046 --confirm settings.json; [[ "$output" == *"already applied"* ]] || false
}

@test "0047: appends its own Write|Edit|MultiEdit group, PreToolUse[0] untouched, idempotent" {
  run mig 0047 --confirm settings.json; [ "$status" -eq 0 ]
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$HOME/.claude/settings.json")" = "~/.claude/hooks/unit-gate.sh" ]
  [ "$(jq '[.hooks.PreToolUse[].hooks[].command | select(. == "~/.claude/hooks/read-before-write-parity.sh")] | length' "$HOME/.claude/settings.json")" -eq 1 ]
  all_linked
  run mig 0047 --verify; [ "$status" -eq 0 ]
  run mig 0047 --confirm settings.json; [[ "$output" == *"already applied"* ]] || false
}

@test "0047: refuses (rc 4) while the live hook file is absent" {
  rm "$HOME/.claude/hooks/read-before-write-parity.sh"
  run mig 0047 --check; [ "$status" -eq 4 ]
}

@test "0048: replaces Memory Poisoning, adds the 17 named rules once, keeps ours, idempotent" {
  run mig 0048 --confirm settings.json; [ "$status" -eq 0 ]
  local s="$HOME/.claude/settings.json"
  [ "$(jq '[.autoMode.soft_deny[] | select(startswith("Memory Poisoning"))] | length' "$s")" -eq 0 ]
  [ "$(jq '[.autoMode.soft_deny[] | select(startswith("Git Push to Default Branch"))] | length' "$s")" -eq 1 ]
  [ "$(jq '[.autoMode.soft_deny[] | select(startswith("Instruction Poisoning"))] | length' "$s")" -eq 1 ]
  [ "$(jq '.autoMode.soft_deny | length' "$s")" -eq 18 ]
  all_linked
  run mig 0048 --verify; [ "$status" -eq 0 ]
  run mig 0048 --confirm settings.json; [[ "$output" == *"already applied"* ]] || false
  [ "$(jq '.autoMode.soft_deny | length' "$s")" -eq 18 ]
}

@test "usage: bare invocation outside the converger and an unnamed --confirm are refused (rc 2)" {
  for m in 0046 0047 0048; do
    run env -u CC_MIGRATION_STATE bash -c "bash $REPO/migrations/$m*.sh"; [ "$status" -eq 2 ]
    run mig "$m" --confirm; [ "$status" -eq 2 ]
  done
}
