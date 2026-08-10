#!/usr/bin/env bats
# bin/cc-custody — dispatched-work custody ledger (CLOSE_INTEGRITY W2, generator G1).
#
# WHAT IS PINNED: the open-set derivation (latest verdict per key wins; marker is the primary key,
# slug+target the fallback), per-cwd isolation under the SAME cwd normalisation the fired-peer
# store uses, discharge by marker AND by slug, the best-effort unmatched return (rc 0, loud), and
# the abandon --why requirement. The consumer contract is `count --open --cwd` printing a bare
# integer — wrap-ledger's CUSTODY_OPEN term reads exactly that.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BIN="$REPO_ROOT/bin/cc-custody"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  WT_A="$BATS_TEST_TMPDIR/wt-a"; mkdir -p "$WT_A"
  WT_B="$BATS_TEST_TMPDIR/wt-b"; mkdir -p "$WT_B"
}

@test "open then count --open = 1; count in an unrelated cwd = 0; count with no --cwd sees it" {
  run "$BIN" open --cwd "$WT_A" --target 42 --marker M-1 --slug wave1 --notify-back 85
  [ "$status" -eq 0 ]
  [ "$("$BIN" count --open --cwd "$WT_A")" = 1 ]
  [ "$("$BIN" count --open --cwd "$WT_B")" = 0 ]
  [ "$("$BIN" count --open)" = 1 ]
}

@test "return by MARKER discharges the debt" {
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-2 --slug wave2
  run "$BIN" return M-2
  [ "$status" -eq 0 ]
  [ "$("$BIN" count --open --cwd "$WT_A")" = 0 ]
}

@test "return by SLUG discharges a marker-less open (the fallback key)" {
  "$BIN" open --cwd "$WT_A" --target 42 --slug wave3
  run "$BIN" return wave3
  [ "$status" -eq 0 ]
  [ "$("$BIN" count --open --cwd "$WT_A")" = 0 ]
}

@test "abandon needs --why; with it, the debt is discharged and the why is recorded" {
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-4 --slug wave4
  run "$BIN" abandon M-4
  [ "$status" -ne 0 ]
  run "$BIN" abandon M-4 --why "wave superseded by rebuild"
  [ "$status" -eq 0 ]
  [ "$("$BIN" count --open --cwd "$WT_A")" = 0 ]
  grep -q 'wave superseded by rebuild' "$CC_CUSTODY_DIR"/*.jsonl
}

@test "latest verdict per key wins: open → return → RE-open makes it open again" {
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-5 --slug wave5
  "$BIN" return M-5
  sleep 1   # ts is second-granular; the re-open must sort strictly later
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-5 --slug wave5
  [ "$("$BIN" count --open --cwd "$WT_A")" = 1 ]
}

@test "unmatched return: rc 0, loud on stderr, discharges nothing" {
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-6 --slug wave6
  run "$BIN" return NO-SUCH-TOKEN
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'no OPEN row matches'
  [ "$("$BIN" count --open --cwd "$WT_A")" = 1 ]
}

@test "list --open --json is a JSON array carrying the open row's slug and target" {
  "$BIN" open --cwd "$WT_A" --target 77 --marker M-7 --slug wave7
  run "$BIN" list --open --cwd "$WT_A" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].slug')" = wave7 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].targetPane')" = 77 ]
}

@test "cwd normalisation: a symlinked spelling of the same worktree counts as ONE store" {
  ln -s "$WT_A" "$BATS_TEST_TMPDIR/wt-link"
  "$BIN" open --cwd "$BATS_TEST_TMPDIR/wt-link" --target 42 --marker M-8 --slug wave8
  [ "$("$BIN" count --open --cwd "$WT_A")" = 1 ]
}

@test "empty store: count is a bare 0, rc 0 (a real zero, not an error)" {
  run "$BIN" count --open --cwd "$WT_B"
  [ "$status" -eq 0 ]
  [ "$output" = 0 ]
}
