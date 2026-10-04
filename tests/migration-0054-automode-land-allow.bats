#!/usr/bin/env bats
# shellcheck disable=SC2016  # fixture strings carry literal permission-rule text exactly as settings.json stores them
# Migration 0054 — adds the three land-line allow rules to the ONE shared settings.json.
#
# Pinned: --dry-run/--check write nothing; --confirm adds exactly the three rules and changes no
# other byte of meaning (every other key, every pre-existing allow entry, the git-push ask and the
# force-push deny), keeps every account a symlink and reads back through --verify; a second run is
# a no-op; a FORKED account is refused rc 3 with nothing written; usage errors are rc 2; and the
# --probe exit maps PASS 0 / FAIL 1 (with the restore line) / BLIND 3.
#
# Hermetic: scratch HOME, the repo's own bin/cc-settings-parity via CC_SETTINGS_PARITY_BIN. The
# behavioral probe needs real headless sessions, so --probe runs a STUB probe placed where the
# migration resolves it (its sibling scripts/ dir) in a scratch copy of the migration.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_SETTINGS_PARITY_BIN="$REPO/bin/cc-settings-parity"
  # hermeticity: the rule strings name scripts/ship-land.sh; nothing here runs it, but pin the converge anyway
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$BATS_TEST_TMPDIR/absent-repo"
  mkdir -p "$HOME/.claude"
  printf '{"accounts":[{"name":"next","config_dir":"~/.claude-next"},{"name":"next2","config_dir":"~/.claude-secondary"},{"name":"next3","config_dir":"~/.claude-tertiary"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  jq -n '{
    autoMode: {soft_deny: ["Git Push to Default Branch: x"]},
    hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "~/.claude/hooks/validate-bash.sh"}]}]},
    permissions: {allow: ["Bash(git add:*)", "Bash(scripts/ship-land.sh:*)"],
                  ask: ["Bash(git push:*)"], deny: ["Bash(git push --force:*)"], defaultMode: "auto"}
  }' > "$HOME/.claude/settings.json"
  for a in next secondary tertiary quaternary; do
    mkdir -p "$HOME/.claude-$a"; ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
  done
  F="$HOME/.claude/settings.json"
}

mig() { bash "$REPO/migrations/0054-automode-land-allow.sh" "$@"; }
all_linked() { for a in next secondary tertiary quaternary; do [ -L "$HOME/.claude-$a/settings.json" ] || return 1; done; }
NEW='["Bash(git commit -m:*)","Bash(bash scripts/ship-land.sh:*)","Bash(fnm exec --using=22 bash scripts/ship-land.sh:*)"]'

@test "0054: --dry-run and --check write nothing; --verify reads NOT live (rc 1) before apply" {
  local before; before="$(shasum "$F")"
  for m in --dry-run --check; do
    run mig "$m"
    [ "$status" -eq 0 ] || { echo "$m: $output"; false; }
  done
  [ "$(shasum "$F")" = "$before" ]
  run mig --verify
  [ "$status" -eq 1 ]
}

@test "0054: --confirm adds exactly the three rules, changes nothing else, keeps links, verifies, idempotent" {
  local orig; orig="$(cat "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$F" ]
  [ ! -L "$F" ]
  all_linked
  # the allow list is the old list with the three rules appended, in order, once
  jq -e --argjson n "$NEW" '.permissions.allow == ["Bash(git add:*)","Bash(scripts/ship-land.sh:*)"] + $n' "$F" >/dev/null
  # every other key is unchanged — the git-push ask and the force-push deny above all
  jq -en --argjson a "$orig" --slurpfile b "$F" '($a | del(.permissions.allow)) == ($b[0] | del(.permissions.allow))' >/dev/null
  jq -e '.permissions.ask == ["Bash(git push:*)"] and .permissions.deny == ["Bash(git push --force:*)"]' "$F" >/dev/null
  run mig --verify
  [ "$status" -eq 0 ]
  local after; after="$(shasum "$F")"
  run mig --confirm settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]] || false
  [ "$(shasum "$F")" = "$after" ]
}

@test "0054: a FORKED account ⇒ rc 3, nothing written anywhere" {
  rm "$HOME/.claude-next/settings.json"; cp "$F" "$HOME/.claude-next/settings.json"
  local b1 b2; b1="$(shasum "$F")"; b2="$(shasum "$HOME/.claude-next/settings.json")"
  run mig --confirm settings.json
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(shasum "$F")" = "$b1" ]
  [ "$(shasum "$HOME/.claude-next/settings.json")" = "$b2" ]
}

@test "0054: usage — bare outside the converger, an unnamed --confirm, a stray trailing arg ⇒ rc 2, nothing written" {
  local before; before="$(shasum "$F")"
  run mig
  [ "$status" -eq 2 ]
  run mig --confirm
  [ "$status" -eq 2 ]
  run mig --confirm settings.json --force
  [ "$status" -eq 2 ]
  [ "$(shasum "$F")" = "$before" ]
}

@test "0054: --probe maps the probe's PASS/FAIL/BLIND to rc 0/1/3, and a FAIL prints the restore line" {
  local t="$BATS_TEST_TMPDIR/tree" rc want
  mkdir -p "$t/migrations" "$t/scripts"
  cp "$REPO/migrations/0054-automode-land-allow.sh" "$t/migrations/"
  printf '#!/bin/bash\necho "stub probe rc=$STUB_PROBE_RC"\nexit "$STUB_PROBE_RC"\n' > "$t/scripts/automode-land-probe.sh"
  for pair in 0:0 1:1 3:3; do
    rc=${pair%%:*} want=${pair##*:}
    jq '.permissions.allow -= '"$NEW" "$F" > "$F.tmp" && mv "$F.tmp" "$F"   # un-apply between rounds
    STUB_PROBE_RC=$rc run bash "$t/migrations/0054-automode-land-allow.sh" --confirm settings.json --probe
    [ "$status" -eq "$want" ] || { echo "probe rc $rc ⇒ got $status: $output"; false; }
    [[ "$output" == *"stub probe rc=$rc"* ]] || false
    if [ "$rc" = 1 ]; then [[ "$output" == *"Restore: cp -p $HOME/.claude/backups/automode-land-allow-0054-"* ]] || false; fi
  done
}
