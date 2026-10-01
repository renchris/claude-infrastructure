#!/usr/bin/env bats
# migrations/0049 — moves three spent raw-ff DEPLOY scripts out of the live ~/.claude root into the
# converger's backup store (backlog 5cb75cf245f1). Hermetic: $HOME is fixtured, so the live root and
# the state dir the migration touches are both inside the test dir.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO_ROOT/migrations/0049-retire-spent-deploy-scripts.sh"
  export CC_MIGRATION_STATE="$HOME/.claude/autonomy/migrations"
  printf 'one\n'   > "$HOME/.claude/DEPLOY-crash-diagnostics.sh"
  printf 'two\n'   > "$HOME/.claude/DEPLOY-DESK-RECYCLE-FIX.sh"
  printf 'three\n' > "$HOME/.claude/DEPLOY-NOW.sh.pre-ssot.bak"
  mkdir -p "$HOME/.claude/scripts"; : > "$HOME/.claude/scripts/deploy-now.sh"
  ln -s "$HOME/.claude/scripts/deploy-now.sh" "$HOME/.claude/DEPLOY-NOW.sh"
}

verify() { # the migration's own declared oracle, read from its header — never a copy of it
  local v
  v="$(sed -n 's/^# migration-verify: //p' "$MIG")"
  [ -n "$v" ]
  bash -c "$v"
}

@test "the oracle reads RED before the migration runs" {
  run verify
  [ "$status" -ne 0 ]
}

@test "moves all three, bytes intact, into superseded/ — and the oracle reads green" {
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/DEPLOY-crash-diagnostics.sh" ]
  [ ! -e "$HOME/.claude/DEPLOY-DESK-RECYCLE-FIX.sh" ]
  [ ! -e "$HOME/.claude/DEPLOY-NOW.sh.pre-ssot.bak" ]
  [ "$(cat "$CC_MIGRATION_STATE"/superseded/DEPLOY-crash-diagnostics.sh.*)" = one ]
  [ "$(cat "$CC_MIGRATION_STATE"/superseded/DEPLOY-DESK-RECYCLE-FIX.sh.*)" = two ]
  [ "$(cat "$CC_MIGRATION_STATE"/superseded/DEPLOY-NOW.sh.pre-ssot.bak.*)" = three ]
  run verify
  [ "$status" -eq 0 ]
}

@test "the live DEPLOY-NOW.sh symlink is never touched" {
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude/DEPLOY-NOW.sh" ]
}

@test "idempotent: a second run moves nothing and still exits 0" {
  bash "$MIG"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 file(s) moved"* ]] || false
  [ "$(find "$CC_MIGRATION_STATE/superseded" -type f | wc -l | tr -d ' ')" -eq 3 ]
}

@test "a SYMLINK at one of the names is refused loudly, not moved" {
  rm "$HOME/.claude/DEPLOY-DESK-RECYCLE-FIX.sh"
  ln -s /dev/null "$HOME/.claude/DEPLOY-DESK-RECYCLE-FIX.sh"
  run bash "$MIG"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a regular file"* ]] || false
  [ -L "$HOME/.claude/DEPLOY-DESK-RECYCLE-FIX.sh" ]
}
