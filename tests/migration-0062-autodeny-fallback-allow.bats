#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2088  # fixture strings carry literal permission-rule text (with ~) exactly as settings.json stores them
# Migration 0062 — adds the five classifier-fallback allow rules (cc-notify path spellings, wrap-ledger.sh)
# to the ONE shared settings.json (docs/research/autodeny-prompts-2026-10-11/, candidate C5).
#
# Pinned: --dry-run/--check write nothing; --confirm appends exactly the five rules after the untouched
# existing list and changes no other byte of meaning (ask, deny, every other key), keeps every account a
# symlink and reads back through --verify; a second run is a no-op; a partly-applied file gains only the
# missing rules, never a duplicate; a FORKED account is refused rc 3 with nothing written; usage errors
# are rc 2.
#
# Hermetic: scratch HOME, the repo's own bin/cc-settings-parity via CC_SETTINGS_PARITY_BIN. Nothing here
# runs cc-notify or wrap-ledger.sh; the rules only name them.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_SETTINGS_PARITY_BIN="$REPO/bin/cc-settings-parity"
  mkdir -p "$HOME/.claude"
  printf '{"accounts":[{"name":"next","config_dir":"~/.claude-next"},{"name":"next2","config_dir":"~/.claude-secondary"},{"name":"next3","config_dir":"~/.claude-tertiary"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  jq -n '{
    autoMode: {soft_deny: ["Git Push to Default Branch: x"]},
    hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "~/.claude/hooks/validate-bash.sh"}]}]},
    permissions: {allow: ["Bash(cc-notify:*)", "Bash(git add:*)"],
                  ask: ["Bash(git push:*)"], deny: ["Bash(git push --force:*)"], defaultMode: "auto"}
  }' > "$HOME/.claude/settings.json"
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"; ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
  done
  F="$HOME/.claude/settings.json"
  NEW="$(jq -cn --arg abs "Bash($HOME/.claude/bin/cc-notify:*)" '["Bash(~/.claude/bin/cc-notify:*)", $abs,
    "Bash(~/Development/claude-infrastructure/bin/cc-notify:*)", "Bash(bash ~/.claude/scripts/wrap-ledger.sh:*)",
    "Bash(~/.claude/scripts/wrap-ledger.sh:*)"]')"
}

mig() { bash "$REPO/migrations/0062-autodeny-fallback-allow.sh" "$@"; }
all_linked() { for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ] || return 1; done; }

@test "0062: --dry-run and --check write nothing; --verify reads NOT live (rc 1) before apply" {
  local before; before="$(shasum "$F")"
  for m in --dry-run --check; do
    run mig "$m"
    [ "$status" -eq 0 ] || { echo "$m: $output"; false; }
    [[ "$output" == *"nothing written"* ]] || false
  done
  [ "$(shasum "$F")" = "$before" ]
  [ ! -d "$HOME/.claude/backups" ]
  run mig --verify
  [ "$status" -eq 1 ]
}

@test "0062: --confirm appends exactly the five rules, changes nothing else, keeps links, verifies, idempotent" {
  local orig; orig="$(cat "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$F" ]
  [ ! -L "$F" ]
  all_linked
  jq -e --argjson n "$NEW" '.permissions.allow == ["Bash(cc-notify:*)","Bash(git add:*)"] + $n' "$F" >/dev/null
  jq -en --argjson a "$orig" --slurpfile b "$F" '($a | del(.permissions.allow)) == ($b[0] | del(.permissions.allow))' >/dev/null
  jq -e '.permissions.ask == ["Bash(git push:*)"] and .permissions.deny == ["Bash(git push --force:*)"]' "$F" >/dev/null
  # the backup holds the pre-edit file
  local b; b="$(ls -d "$HOME"/.claude/backups/autodeny-fallback-allow-0062-*)"
  jq -en --argjson a "$orig" --slurpfile b "$b/settings.json" '$a == $b[0]' >/dev/null
  run mig --verify
  [ "$status" -eq 0 ]
  local after; after="$(shasum "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]] || false
  [ "$(shasum "$F")" = "$after" ]
}

@test "0062: a partly-applied file gains only the missing rules, never a duplicate" {
  jq '.permissions.allow += ["Bash(~/.claude/scripts/wrap-ledger.sh:*)"]' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
  run mig --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *'"Bash(~/.claude/scripts/wrap-ledger.sh:*)"'* ]] || false
  run mig --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq -e '[.permissions.allow[] | select(. == "Bash(~/.claude/scripts/wrap-ledger.sh:*)")] | length == 1' "$F" >/dev/null
  jq -e --argjson n "$NEW" '($n - .permissions.allow) == [] and (.permissions.allow | length) == 7' "$F" >/dev/null
  all_linked
}

@test "0062: a FORKED account ⇒ rc 3, nothing written anywhere" {
  rm "$HOME/.claude-next/settings.json"; cp "$F" "$HOME/.claude-next/settings.json"
  local b1 b2; b1="$(shasum "$F")"; b2="$(shasum "$HOME/.claude-next/settings.json")"
  run mig --confirm settings.json
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(shasum "$F")" = "$b1" ]
  [ "$(shasum "$HOME/.claude-next/settings.json")" = "$b2" ]
}

@test "0062: usage — bare outside the converger, an unnamed --confirm, a stray trailing arg ⇒ rc 2, nothing written" {
  local before; before="$(shasum "$F")"
  run mig
  [ "$status" -eq 2 ]
  run mig --confirm
  [ "$status" -eq 2 ]
  run mig --confirm settings.json --probe
  [ "$status" -eq 2 ]
  run mig --bogus
  [ "$status" -eq 2 ]
  [ "$(shasum "$F")" = "$before" ]
}
