#!/usr/bin/env bats
# cc-settings-parity runs through python3, never as a #! exec by path (REPORT §3 Phase 1,
# docs/research/kalloc-longterm-2026-10-21/REPORT.md): on macOS 15.8.1 each by-path #! exec keeps
# ~1.1 KiB of kernel memory, and the migrations' verify lines ran it 781 times in the census hour.
#
# RED-proof: the behavioural case points the migration at a parity copy whose #! names no real
# interpreter. By path that exec fails and 0041 REFUSES; through python3 it runs and 0041 proceeds.
#
# Hermetic: $HOME is a fixture; the real bin/cc-settings-parity runs over fixture account dirs.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  unset CC_PARITY_CANONICAL CC_PARITY_ACCOUNTS_JSON CC_MIGRATION_STATE
  mkdir -p "$HOME/.claude/bin"
  jq -n '{hooks:{Stop:[]}}' > "$HOME/.claude/settings.json"
  CC_PARITY_DIRS=""
  for a in next secondary; do
    mkdir -p "$HOME/.claude-$a"
    ln -s "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"
    CC_PARITY_DIRS="${CC_PARITY_DIRS:+$CC_PARITY_DIRS:}$HOME/.claude-$a"
  done
  export CC_PARITY_DIRS
  # The real engine, re-headed so that only an explicit python3 can run it.
  P="$BATS_TEST_TMPDIR/cc-settings-parity"
  { printf '#!/nonexistent/python3\n'; tail -n +2 "$REPO/bin/cc-settings-parity"; } > "$P"
  chmod +x "$P"
  export CC_SETTINGS_PARITY_BIN="$P"
}

@test "a migration runs cc-settings-parity through python3, not by path" {
  run "$P" check
  [ "$status" -eq 126 ] || [ "$status" -eq 127 ]          # the by-path exec really is dead
  run bash "$REPO/migrations/0041-bash-output-max-chars.sh" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"DRY RUN"* ]]
  [[ "$output" != *"REFUSED"* ]]
}

@test "a stub parity (a bash script) still runs by its own #! line" {
  printf '#!/bin/bash\nexit 0\n' > "$P"
  run bash "$REPO/migrations/0041-bash-output-max-chars.sh" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"DRY RUN"* ]]
}

@test "no migration, verify line or c10-batch call runs cc-settings-parity by path" {
  cd "$REPO"
  run git grep -nE '"\$parity" check|^# migration-verify: "\$HOME/\.claude/bin/cc-settings-parity"' -- migrations
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  run grep -n 'parity_ok()' scripts/c10-batch.sh
  [[ "$output" == *'/usr/bin/env python3 "$1/.claude/bin/cc-settings-parity" check'* ]]
}
