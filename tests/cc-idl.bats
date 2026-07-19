#!/usr/bin/env bats
# cc-idl — tamper-evident hash-chain over the append-only autonomy IDL (axis k, P1/P9).
#   seal              extend the chain over new \n-terminated IDL lines (append-only, atomic)
#   verify            recompute from the IDL; exit 7 on any altered/deleted/reordered sealed line
#   append '<json>'   canonical write-and-seal; echoes the new head
#   head              print the witnessable "<seq>\t<hash>" anchor
#
# Harness laws honored (§3.10): L1 every fixture's chain bytes come from the REAL cc-idl, never a
# hand-written hash; L2 asserts on failure-distinct strings (TAMPER / DELETED, exit 7 vs 0); L3
# every assertion is `[ ]` / `grep -q` (both trap under errexit — a bare `[[ ]]` would not); L4
# each behaviour has BOTH a positive and a negative fixture, so the suite goes RED against the
# matching bug (a no-op verify fails the tamper tests; an always-fail verify fails the clean test).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  IDL_BIN="$REPO/bin/cc-idl"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_IDL_CHAIN="$BATS_TEST_TMPDIR/idl.chain"
  export CC_IDL_LOCK="$BATS_TEST_TMPDIR/idl.lock.d"
}

# write N JSON lines into the IDL
seed() { local n="$1" i; : > "$CC_IDL"; for i in $(seq 1 "$n"); do printf '{"ts":"2026-07-19T08:0%d:00Z","seq":%d}\n' "$((i % 10))" "$i" >> "$CC_IDL"; done; }

# ── seal ────────────────────────────────────────────────────────────────────────────────────
@test "seal over a fresh IDL is GENESIS and is LOUD about it" {
  seed 3
  run bash "$IDL_BIN" seal
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "genesis"
  echo "$output" | grep -q "sealed 3 new"
  [ -f "$CC_IDL_CHAIN" ]
  run wc -l < "$CC_IDL_CHAIN"
  [ "$(echo "$output" | tr -d ' ')" = "3" ]
}

@test "seal is idempotent — a second seal with no new lines seals 0" {
  seed 3; bash "$IDL_BIN" seal >/dev/null
  run bash "$IDL_BIN" seal
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "sealed 0 new"
}

@test "seal is incremental — new raw lines seal without recomputing the prefix" {
  seed 3; bash "$IDL_BIN" seal >/dev/null
  printf '{"seq":4}\n{"seq":5}\n' >> "$CC_IDL"
  run bash "$IDL_BIN" seal
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "sealed 2 new"
  run bash "$IDL_BIN" verify
  [ "$status" -eq 0 ]
}

@test "seal is content-deterministic — identical IDLs seal to an identical head" {
  seed 4; bash "$IDL_BIN" seal >/dev/null
  head1="$(bash "$IDL_BIN" head | cut -f2)"
  # a second, independent chain over byte-identical content
  export CC_IDL="$BATS_TEST_TMPDIR/idl2.jsonl" CC_IDL_CHAIN="$BATS_TEST_TMPDIR/idl2.chain" CC_IDL_LOCK="$BATS_TEST_TMPDIR/idl2.lock.d"
  seed 4; bash "$IDL_BIN" seal >/dev/null
  head2="$(bash "$IDL_BIN" head | cut -f2)"
  [ -n "$head1" ]
  [ "$head1" = "$head2" ]
}

# ── verify: clean vs each tamper class (positive + negative → RED against a no-op verify) ─────
@test "verify passes on an intact sealed chain" {
  seed 5; bash "$IDL_BIN" seal >/dev/null
  run bash "$IDL_BIN" verify
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "OK"
}

@test "verify DETECTS an in-place edit of a sealed line (exit 7, points at the line)" {
  seed 5; bash "$IDL_BIN" seal >/dev/null
  perl -i -pe 's/"seq":3/"seq":999/ if $.==3' "$CC_IDL"
  run bash "$IDL_BIN" verify
  [ "$status" -eq 7 ]
  echo "$output" | grep -q "TAMPER"
  echo "$output" | grep -q "line 3"
}

@test "verify DETECTS a deleted sealed line as truncation (exit 7)" {
  seed 5; bash "$IDL_BIN" seal >/dev/null
  perl -i -ne 'print unless $.==3' "$CC_IDL"
  run bash "$IDL_BIN" verify
  [ "$status" -eq 7 ]
  echo "$output" | grep -q "DELETED/TRUNCATED"
}

@test "verify DETECTS a reordering of two sealed lines (exit 7)" {
  seed 3; bash "$IDL_BIN" seal >/dev/null
  printf '{"ts":"2026-07-19T08:01:00Z","seq":1}\n{"ts":"2026-07-19T08:03:00Z","seq":3}\n{"ts":"2026-07-19T08:02:00Z","seq":2}\n' > "$CC_IDL"
  run bash "$IDL_BIN" verify
  [ "$status" -eq 7 ]
  echo "$output" | grep -q "TAMPER"
}

@test "ANTI-LAUNDER: a re-seal after tampering CANNOT hide it (verify still exit 7)" {
  # The load-bearing property: seal copies the sealed prefix verbatim and only appends new lines,
  # so an attacker who edits a past line and re-runs seal still fails verify at that line.
  seed 5; bash "$IDL_BIN" seal >/dev/null
  perl -i -pe 's/"seq":2/"seq":88/ if $.==2' "$CC_IDL"
  run bash "$IDL_BIN" seal        # attacker attempts to launder the edit
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "sealed 0 new"
  run bash "$IDL_BIN" verify
  [ "$status" -eq 7 ]
  echo "$output" | grep -q "line 2"
}

@test "verify refuses when nothing has been sealed yet (exit 2)" {
  seed 3   # sealed nothing
  run bash "$IDL_BIN" verify
  [ "$status" -eq 2 ]
}

@test "verify reports an unsealed tail without failing (concurrent appends are not tamper)" {
  seed 3; bash "$IDL_BIN" seal >/dev/null
  printf '{"seq":4}\n{"seq":5}\n' >> "$CC_IDL"
  run bash "$IDL_BIN" verify
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "2 unsealed tail"
}

@test "a mid-write trailing partial line (no newline) is left unsealed, never corrupts the chain" {
  printf '{"seq":1}\n{"seq":2}\n{"seq":3}' > "$CC_IDL"   # line 3 has NO trailing newline
  run bash "$IDL_BIN" seal
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "sealed 2 new"                 # only the 2 complete lines sealed
  run bash "$IDL_BIN" verify
  [ "$status" -eq 0 ]
}

# ── append ──────────────────────────────────────────────────────────────────────────────────
@test "append writes the record to the IDL, seals it, and echoes a 64-hex head" {
  seed 2; bash "$IDL_BIN" seal >/dev/null
  run bash "$IDL_BIN" append '{"seq":3,"note":"canonical"}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^[0-9a-f]{64}$'
  run grep -c '"note":"canonical"' "$CC_IDL"
  [ "$output" = "1" ]
  run bash "$IDL_BIN" verify
  [ "$status" -eq 0 ]
}

@test "append rejects a non-JSON argument (exit 2) and does not grow the IDL" {
  seed 2; bash "$IDL_BIN" seal >/dev/null
  before="$(wc -l < "$CC_IDL")"
  run bash "$IDL_BIN" append 'not json at all'
  [ "$status" -eq 2 ]
  after="$(wc -l < "$CC_IDL")"
  [ "$before" = "$after" ]
}

# ── head + usage ──────────────────────────────────────────────────────────────────────────────
@test "head prints the current <seq>\\t<hash> anchor" {
  seed 4; bash "$IDL_BIN" seal >/dev/null
  run bash "$IDL_BIN" head
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^4	[0-9a-f]{64}$'
}

@test "an unknown verb exits 2 with usage" {
  run bash "$IDL_BIN" frobnicate
  [ "$status" -eq 2 ]
}
