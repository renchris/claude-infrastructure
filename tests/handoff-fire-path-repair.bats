#!/usr/bin/env bats
# handoff-fire.sh hf_path_repair — a caller whose PATH lacks ~/.claude/bin must not lose the router.
#
# Incident 2026-09-30: after a host reboot a fire printed "pre-fire account sweep: skipped
# (claude-accounts not on PATH)", ranked accounts by the activity proxy, and routed a session onto an
# account at 100% weekly. The binary was present at ~/.claude/bin the whole time; only PATH was short.
# The function is extracted with sed, as the rest of this repo's handoff-fire suites do, so nothing
# here runs the fire path.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  # Nothing here runs the fire path, but the ratchet binds every suite that names handoff-fire.sh,
  # and pinning the seams costs a line each.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  FN="$BATS_TEST_TMPDIR/fn.sh"
  sed -n '/^hf_path_repair() {/,/^}/p' "$HF" > "$FN"
  [ -s "$FN" ] || { echo "hf_path_repair not found in $HF"; false; }
  printf '#!/bin/sh\necho real-router\n' > "$HOME/.claude/bin/claude-accounts"
  chmod +x "$HOME/.claude/bin/claude-accounts"
}

@test "RED-PROOF: a PATH without ~/.claude/bin finds claude-accounts after the repair" {
  run /bin/bash -c "PATH=/usr/bin:/bin; . '$FN'; command -v claude-accounts >/dev/null && exit 7; hf_path_repair; command -v claude-accounts"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$HOME/.claude/bin/claude-accounts" ]
}

@test "the dir is APPENDED, so a caller's own stub earlier on PATH still wins" {
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  printf '#!/bin/sh\necho stub\n' > "$BATS_TEST_TMPDIR/stub/claude-accounts"; chmod +x "$BATS_TEST_TMPDIR/stub/claude-accounts"
  run /bin/bash -c "PATH='$BATS_TEST_TMPDIR/stub':/usr/bin:/bin; . '$FN'; hf_path_repair; claude-accounts; printf '%s\n' \"\$PATH\""
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[0]}" = stub ]
  [ "${lines[1]}" = "$BATS_TEST_TMPDIR/stub:/usr/bin:/bin:$HOME/.claude/bin" ]
}

@test "already on PATH → PATH is unchanged (no duplicate entry)" {
  run /bin/bash -c "PATH=/usr/bin:'$HOME/.claude/bin':/bin; . '$FN'; hf_path_repair; printf '%s' \"\$PATH\""
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin:$HOME/.claude/bin:/bin" ]
}

@test "no ~/.claude/bin at all → PATH is unchanged and the repair exits 0" {
  rm -rf "$HOME/.claude/bin"
  run /bin/bash -c "set -eu; PATH=/usr/bin:/bin; . '$FN'; hf_path_repair; printf '%s' \"\$PATH\""
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin:/bin" ]
}

@test "the repair is CALLED at top level, not only defined" {
  grep -qx 'hf_path_repair' "$HF"
}
