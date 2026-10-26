#!/usr/bin/env bats
# shellcheck disable=SC2016  # fixture strings carry literal permission-rule text exactly as settings.json stores them
# Migration 0084 — adds the cc-lr / lr-handoff / handoff-fire / session-continue clear allow rules to
# the ONE shared settings.json.
#
# Pinned: --dry-run writes nothing and lists only the missing rules; --confirm adds exactly those,
# skips a rule already present, changes no other key and no pre-existing allow entry, keeps an
# account symlink a symlink, and satisfies its own migration-verify header; a second run is a no-op;
# the launchd-only lr-* internals are never allowed; usage errors are rc 2 with nothing written.
#
# Hermetic: scratch HOME with a stub ~/.claude/bin/cc-lr; nothing here runs cc-lr.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  # hermeticity: the rule strings name handoff-fire.sh; nothing here runs it, but pin its gates and seams anyway
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/absent-sweep.json" CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-" CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/telemetry"
  mkdir -p "$HOME/.claude/bin" "$HOME/.claude-next"
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.claude/bin/cc-lr"; chmod +x "$HOME/.claude/bin/cc-lr"
  jq -n '{
    autoMode: {soft_deny: ["x"]},
    permissions: {allow: ["Bash(git add:*)", "Bash(~/.claude/bin/cc-lr switch:*)", "Bash(cc-lr:*)"],
                  ask: ["Bash(git stash clear:*)"], deny: ["Bash(git push --force:*)"], defaultMode: "auto"}
  }' > "$HOME/.claude/settings.json"
  ln -s "$HOME/.claude/settings.json" "$HOME/.claude-next/settings.json"
  F="$HOME/.claude/settings.json"
}

mig() { /bin/bash "$REPO/migrations/0084-cc-lr-move-allow.sh" "$@"; }
verify_header() { bash -c "$(sed -n 's/^# migration-verify: //p' "$REPO/migrations/0084-cc-lr-move-allow.sh")"; }
new_rules() {
  jq -nc --arg h "$HOME" '[
    "Bash(~/.claude/bin/cc-lr:*)",
    "Bash(\($h)/.claude/bin/cc-lr:*)",
    "Bash(~/.claude/scripts/limit-recover/lr-handoff.sh:*)",
    "Bash(\($h)/.claude/scripts/limit-recover/lr-handoff.sh:*)",
    "Bash(\($h)/.claude/scripts/handoff-fire.sh:*)",
    "Bash(~/.claude/hooks/session-continue.sh clear:*)"]'
}

@test "0084: --dry-run writes nothing, lists the six missing rules, skips the present one; verify reads NOT live" {
  local before; before="$(shasum "$F")"
  run mig --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(shasum "$F")" = "$before" ]
  [ "$(grep -c '^  + ' <<<"$output")" -eq 6 ]
  [[ "$output" != *"+ Bash(cc-lr:*)"* ]] || false
  run verify_header
  [ "$status" -ne 0 ]
}

@test "0084: --confirm appends exactly the missing rules, changes nothing else, keeps links, verifies, idempotent" {
  local orig; orig="$(cat "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -L "$HOME/.claude-next/settings.json" ]
  jq -e --argjson n "$(new_rules)" \
    '.permissions.allow == ["Bash(git add:*)", "Bash(~/.claude/bin/cc-lr switch:*)", "Bash(cc-lr:*)"] + $n' "$F" >/dev/null
  jq -en --argjson a "$orig" --slurpfile b "$F" '($a | del(.permissions.allow)) == ($b[0] | del(.permissions.allow))' >/dev/null
  run verify_header
  [ "$status" -eq 0 ]
  local after; after="$(shasum "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]] || false
  [ "$(shasum "$F")" = "$after" ]
}

@test "0084: never allows the launchd-only lr-* internals or kitty @" {
  run mig --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run jq -r '.permissions.allow[]' "$F"
  [[ "$output" != *lr-fire-resume* && "$output" != *lr-move-worker* && "$output" != *lr-move-batch* ]] || false
  [[ "$output" != *lr-fleet* && "$output" != *"kitty @"* ]] || false
}

@test "0084: usage — bare outside the converger, an unnamed --confirm, an unknown arg ⇒ rc 2, nothing written" {
  local before; before="$(shasum "$F")"
  run mig
  [ "$status" -eq 2 ]
  run mig --confirm
  [ "$status" -eq 2 ]
  run mig --force
  [ "$status" -eq 2 ]
  [ "$(shasum "$F")" = "$before" ]
}

@test "0084: cc-lr absent from the live layer ⇒ rc 1, nothing written" {
  rm "$HOME/.claude/bin/cc-lr"
  local before; before="$(shasum "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 1 ]
  [[ "$output" == *"not on the live layer"* ]] || false
  [ "$(shasum "$F")" = "$before" ]
}
