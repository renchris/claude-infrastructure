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

# ── FLEET_V2 W6d rig additions (D1.11, D4.13) ─────────────────────────────────────────────────────

@test "reset_in_s moves the stub's limit reset from 3 h out to the knob" {
  export LR_RIG="$BATS_TEST_TMPDIR/rig" LR_RIG_SPECS="$BATS_TEST_TMPDIR/specs"
  mkdir -p "$LR_RIG_SPECS" "$BATS_TEST_TMPDIR/work"
  sid=11111111-0000-4000-8000-000000000001
  printf '{"knobs":{"reset_in_s":60}}\n' > "$LR_RIG_SPECS/$sid.json"
  run python3 "$STUB" --rig-write-dead "$sid" --rig-cwd "$BATS_TEST_TMPDIR/work" </dev/null
  [ "$status" -eq 0 ]
  tx="$(find "$HOME/.claude-next/projects" -name "$sid.jsonl")"
  at="$(tail -1 "$tx" | python3 -c 'import json,sys; print(json.load(sys.stdin)["quotaLimits"]["resetsAt"])')"
  d=$(( at - $(date +%s) ))
  [ "$d" -ge 50 ] && [ "$d" -le 70 ] || { echo "reset in ${d}s"; false; }
}

@test "fake --place answers stay only when RIG_PLACE_STAY=1 and the source is uncovered" {
  export LR_RECON_ROOT="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_RECON_ROOT" "$HOME/.claude" "$BATS_TEST_TMPDIR/facts"
  printf '{"accounts":[{"name":"next","config_dir":"%s/a"},{"name":"next2","config_dir":"%s/b"}]}\n' "$HOME" "$HOME" > "$HOME/.claude/accounts.json"
  printf '{"sid":"s1","src":"next","w":1}\n' > "$BATS_TEST_TMPDIR/m.jsonl"
  FAKE="$REPO/tests/rig/fake-claude-accounts.py"
  run python3 "$FAKE" --place --movers "$BATS_TEST_TMPDIR/m.jsonl" --facts "$BATS_TEST_TMPDIR/facts"
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["s1"]["acct"])')" = next2 ]
  RIG_PLACE_STAY=1 run python3 "$FAKE" --place --movers "$BATS_TEST_TMPDIR/m.jsonl" --facts "$BATS_TEST_TMPDIR/facts"
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; r=json.load(sys.stdin)["s1"]; print(r["acct"], r["reason"])')" = "next stay" ]
  printf '{"acct":"next","scope":"5h","resets_at":%d}\n' $(( $(date +%s) + 3600 )) > "$BATS_TEST_TMPDIR/facts/next.5h.json"
  RIG_PLACE_STAY=1 run python3 "$FAKE" --place --movers "$BATS_TEST_TMPDIR/m.jsonl" --facts "$BATS_TEST_TMPDIR/facts"
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["s1"]["acct"])')" = next2 ]
}
