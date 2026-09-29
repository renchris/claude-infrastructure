#!/usr/bin/env bats
# tests/rig/stub-claude.py — the rig's fake Claude Code must match the real CLI where a recovery
# script probes it. Real `claude --version` prints and exits 0 with no session, no transcript and no
# registry row; the stub started a fresh session instead, whose registry row overwrote a relaunched
# pane's and hid the sid from the rig daemon (FLEET_V2 W5 N=30, clean-idle stuck IN-FLIGHT).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  STUB="$REPO/tests/rig/stub-claude.py"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/cfg"
  export CLAUDE_CONFIG_DIR="$HOME/cfg" CC_PANE_ID=77
}

@test "stub --version prints the pinned version and writes no session, transcript or registry row" {
  run python3 "$STUB" --version </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^2\.1\.[0-9]+\ \(Claude\ Code\)$ ]] || { echo "$output"; false; }
  [ "$(find "$HOME" -type f | wc -l | tr -d ' ')" = 0 ] || { find "$HOME" -type f; false; }
}
