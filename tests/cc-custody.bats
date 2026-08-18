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

@test "MALFORMED: return with a flag where the token should be is an ERROR, never a silent rc-0 non-discharge" {
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-9 --slug wave9
  run "$BIN" return --cwd "$WT_A"
  [ "$status" -ne 0 ]
  [ "$("$BIN" count --open --cwd "$WT_A")" = 1 ]
}

# ── AGE / THE STALE CLASS (item 3b464e94b3ff) ───────────────────────────────────────────────────
# Rows had no age disposition, so a debt from a peer that can never return (reaped, crashed, died
# before its detach) convicted every later same-cwd session as 🔧 until a human ran `abandon`.
# What is pinned here is the rule the fix chose: age is DERIVED and VISIBLE, the stale set is
# SEPARATELY ADDRESSABLE, and NOTHING EXPIRES — `count --open` still counts a stale row, because a
# consumer contract that silently shrank would be the same silent-loss failure one layer down.

_backdate() { # <marker> <iso-ts> — fixture surgery: backdate the open row carrying this marker
  local f
  # `find`, not `ls` (SC2012), and `sort | head` rather than relying on ls's ordering: the store
  # holds one fixture file per test, but "whichever one ls printed first" is not a contract.
  f="$(find "$CC_CUSTODY_DIR" -maxdepth 1 -name '*.jsonl' -type f | sort | awk 'NR==1')"
  jq -c --arg m "$1" --arg ts "$2" 'if .marker == $m then .ts = $ts else . end' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
}

@test "stale class: an open row past the TTL counts as --stale, a fresh one as --fresh" {
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-STALE --slug waveStale
  "$BIN" open --cwd "$WT_A" --target 43 --marker M-FRESH --slug waveFresh
  _backdate M-STALE "2020-01-01T00:00:00Z"
  [ "$("$BIN" count --open --cwd "$WT_A" --stale)" = 1 ]
  [ "$("$BIN" count --open --cwd "$WT_A" --fresh)" = 1 ]
  # NOTHING EXPIRES: the bare consumer contract still sees both.
  [ "$("$BIN" count --open --cwd "$WT_A")" = 2 ]
}

@test "TTL default is 24h and CC_CUSTODY_TTL_HOURS is the seam that moves it" {
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-25H --slug wave25h
  _backdate M-25H "$(date -u -v-25H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '25 hours ago' +%Y-%m-%dT%H:%M:%SZ)"
  [ "$("$BIN" count --open --cwd "$WT_A" --stale)" = 1 ]
  [ "$(CC_CUSTODY_TTL_HOURS=48 "$BIN" count --open --cwd "$WT_A" --stale)" = 0 ]
}

@test "age is VISIBLE: list --open renders it and marks STALE; --json carries ageHours + stale" {
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-VIS --slug waveVis
  _backdate M-VIS "2020-01-01T00:00:00Z"
  run "$BIN" list --open --cwd "$WT_A"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'STALE'
  run "$BIN" list --open --cwd "$WT_A" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.[0].stale')" = true ]
  [ "$(printf '%s' "$output" | jq -r '.[0].ageHours > 0')" = true ]
}

@test "abandon --stale --why discharges the stale set ONLY; the fresh debt survives" {
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-BULK1 --slug waveBulk1
  "$BIN" open --cwd "$WT_A" --target 43 --marker M-BULK2 --slug waveBulk2
  _backdate M-BULK1 "2020-01-01T00:00:00Z"
  run "$BIN" abandon --stale --cwd "$WT_A"
  [ "$status" -ne 0 ]                       # a bulk discharge without a reason is still refused
  run "$BIN" abandon --stale --why "peer reaped before its detach" --cwd "$WT_A"
  [ "$status" -eq 0 ]
  [ "$output" = 1 ]
  [ "$("$BIN" count --open --cwd "$WT_A")" = 1 ]
  [ "$("$BIN" list --open --cwd "$WT_A" --json | jq -r '.[0].marker')" = M-BULK2 ]
  grep -q 'peer reaped before its detach' "$CC_CUSTODY_DIR"/*.jsonl
}

@test "an UNPARSEABLE ts is never stale — an unknown age keeps the debt, never bulk-discharges it" {
  "$BIN" open --cwd "$WT_A" --target 42 --marker M-BADTS --slug waveBadTs
  _backdate M-BADTS "not-a-timestamp"
  [ "$("$BIN" count --open --cwd "$WT_A" --stale)" = 0 ]
  [ "$("$BIN" list --open --cwd "$WT_A" --json | jq -r '.[0].ageHours')" = null ]
  run "$BIN" abandon --stale --why "sweep" --cwd "$WT_A"
  [ "$status" -eq 0 ]
  [ "$output" = 0 ]
  [ "$("$BIN" count --open --cwd "$WT_A")" = 1 ]
}
