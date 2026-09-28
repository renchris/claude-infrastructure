#!/usr/bin/env bats
# cc-memory-read-ledger — the read ledger the rotor's protection reads (TrueMemory #15,
# docs/research/truememory-2026-09-27.md §3.15).
#
# Every fixture is a real transcript JSONL shape (assistant record, tool_use content item) under a
# fixture account root, and every exclusion is pinned beside a read that IS counted in the same run,
# so "count nothing" cannot pass a test that asserts an exclusion. Time is pinned through
# CC_READ_LEDGER_NOW = 2026-09-28T00:00:00Z, so the 365-day horizon is hand-countable:
# 2025-09-27 is 366 days back (pruned), 2025-09-29 is 364 (kept).
#
# Assertions are simple commands only (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLI="$REPO/bin/cc-memory-read-ledger"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  ROOT_A="$BATS_TEST_TMPDIR/acct-a/projects"
  ROOT_B="$BATS_TEST_TMPDIR/acct-b/projects"
  mkdir -p "$ROOT_A/-Users-x-proj" "$ROOT_B/-Users-x-proj"
  export CC_READ_LEDGER_ROOTS="$ROOT_A $ROOT_B"
  STATE="$HOME/.claude/state"
  export CC_READ_LEDGER_STATE_DIR="$STATE"
  export CC_READ_LEDGER_NOW=1790553600   # 2026-09-28T00:00:00Z
  unset CC_READ_LEDGER_RG CC_READ_LEDGER_BULK CC_READ_LEDGER_RETAIN_DAYS SESSION_INDEX_PROJECT_ROOTS
  MEM="/Users/x/.claude/projects/-Users-x-store/memory"
  S1=11111111-1111-1111-1111-111111111111
  S2=22222222-2222-2222-2222-222222222222
  S3=33333333-3333-3333-3333-333333333333
}

# tool <transcript> <tool> <file_path> <timestamp> — append one assistant tool_use record
tool() {
  mkdir -p "$(dirname "$1")"
  printf '{"type":"assistant","timestamp":"%s","message":{"content":[{"type":"tool_use","id":"t","name":"%s","input":{"file_path":"%s"}}]}}\n' \
    "$4" "$2" "$3" >>"$1"
}

main_t() { printf '%s/-Users-x-proj/%s.jsonl' "$1" "$2"; }       # <root> <sid>
sub_t()  { printf '%s/-Users-x-proj/%s/subagents/agent-%s.jsonl' "$1" "$2" "$3"; }  # <root> <sid> <id>

ledger_rows() { grep -v '^#' "$STATE/memory-read-ledger.tsv" || true; }

@test "a non-author Read of a topic file is recorded with its store, topic and last read ts" {
  tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/alpha.md" 2026-09-20T10:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/alpha.md" 2026-09-20T11:30:00.000Z
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$output" = "LEDGER-VERDICT scanned=1 reads=1 topics=1 pruned=0" ]
  [ "$(ledger_rows)" = "$(printf '2026-09-20T11:30:00Z\t%s\t-Users-x-store\talpha.md\tmain' "$S1")" ]
}

@test "the AUTHOR is excluded — including an author that wrote through a subagent — beside a counted read" {
  tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/alpha.md" 2026-09-20T10:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S1")" Edit "$MEM/alpha.md" 2026-09-20T10:01:00.000Z
  tool "$(main_t "$ROOT_A" "$S2")" Read "$MEM/beta.md" 2026-09-20T10:00:00.000Z
  tool "$(sub_t "$ROOT_A" "$S2" a1)" Write "$MEM/beta.md" 2026-09-20T09:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S3")" Read "$MEM/alpha.md" 2026-09-21T10:00:00.000Z
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$(ledger_rows)" = "$(printf '2026-09-21T10:00:00Z\t%s\t-Users-x-store\talpha.md\tmain' "$S3")" ]
}

@test "a BULK reader (>10 distinct topics in one transcript) is excluded, beside a counted read" {
  local i
  for i in 01 02 03 04 05 06 07 08 09 10 11; do
    tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/t$i.md" 2026-09-20T10:00:00.000Z
  done
  tool "$(main_t "$ROOT_A" "$S2")" Read "$MEM/t01.md" 2026-09-20T12:00:00.000Z
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$(ledger_rows)" = "$(printf '2026-09-20T12:00:00Z\t%s\t-Users-x-store\tt01.md\tmain' "$S2")" ]
}

@test "exactly 10 distinct topics is NOT bulk (the threshold is 'more than 10')" {
  local i
  for i in 01 02 03 04 05 06 07 08 09 10; do
    tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/t$i.md" 2026-09-20T10:00:00.000Z
  done
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$(ledger_rows | grep -c .)" -eq 10 ]
}

@test "a subagent Read is recorded as kind=subagent, from a second account root" {
  tool "$(sub_t "$ROOT_B" "$S1" a7)" Read "$MEM/gamma.md" 2026-09-22T08:00:00.000Z
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$(ledger_rows)" = "$(printf '2026-09-22T08:00:00Z\t%s\t-Users-x-store\tgamma.md\tsubagent' "$S1")" ]
}

@test "MEMORY.md, archive/ files and non-memory paths are never reads" {
  tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/MEMORY.md" 2026-09-20T10:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/archive/MEMORY_ARCHIVE_2026-H2-COLD.md" 2026-09-20T10:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S1")" Read "/Users/x/Development/repo/docs/notes.md" 2026-09-20T10:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/delta.md" 2026-09-20T10:00:00.000Z
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$(ledger_rows)" = "$(printf '2026-09-20T10:00:00Z\t%s\t-Users-x-store\tdelta.md\tmain' "$S1")" ]
}

@test "a row 366 days old and a garbage-ts row are pruned; a 364-day row is kept" {
  mkdir -p "$STATE"
  {
    printf '#ts\tsid\tstore\ttopic\tkind\n'
    printf '2025-09-27T00:00:00Z\told-1\t-Users-x-store\told.md\tmain\n'
    printf 'not-a-date\told-2\t-Users-x-store\told.md\tmain\n'
    printf '2025-09-29T00:00:00Z\told-3\t-Users-x-store\tkept.md\tmain\n'
  } >"$STATE/memory-read-ledger.tsv"
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$output" = "LEDGER-VERDICT scanned=0 reads=0 topics=1 pruned=2" ]
  [ "$(ledger_rows)" = "$(printf '2025-09-29T00:00:00Z\told-3\t-Users-x-store\tkept.md\tmain')" ]
}

@test "the summary TSV is exact: per topic, last non-author read and row count, sorted" {
  tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/alpha.md" 2026-09-20T10:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S2")" Read "$MEM/alpha.md" 2026-09-25T10:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S2")" Read "$MEM/beta.md" 2026-09-24T10:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S3")" Edit "$MEM/beta.md" 2026-09-26T10:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S3")" Read "$MEM/beta.md" 2026-09-26T11:00:00.000Z
  run "$CLI"
  [ "$status" -eq 0 ]
  [ "$output" = "LEDGER-VERDICT scanned=3 reads=3 topics=2 pruned=0" ]
  want="$(printf '#store\ttopic\tlast_read\treads\n-Users-x-store\talpha.md\t2026-09-25T10:00:00Z\t2\n-Users-x-store\tbeta.md\t2026-09-24T10:00:00Z\t1')"
  [ "$(cat "$STATE/memory-read-summary.tsv")" = "$want" ]
}

@test "incremental: an unchanged run re-scans nothing and keeps every row; a changed session is REPLACED" {
  tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/alpha.md" 2026-09-20T10:00:00.000Z
  tool "$(main_t "$ROOT_A" "$S2")" Read "$MEM/beta.md" 2026-09-20T10:00:00.000Z
  touch -t 202609200000 "$(main_t "$ROOT_A" "$S1")" "$(main_t "$ROOT_A" "$S2")"
  run "$CLI"
  [ "$output" = "LEDGER-VERDICT scanned=2 reads=2 topics=2 pruned=0" ]
  run "$CLI"
  [ "$output" = "LEDGER-VERDICT scanned=0 reads=0 topics=2 pruned=0" ]
  # S2 later edits what it read: it becomes the author, and its earlier row must go.
  tool "$(main_t "$ROOT_A" "$S2")" Edit "$MEM/beta.md" 2026-09-28T10:00:00.000Z
  touch -t 203001010000 "$(main_t "$ROOT_A" "$S2")"   # changed after the pinned NOW, whatever the wall clock
  run "$CLI"
  [ "$output" = "LEDGER-VERDICT scanned=1 reads=0 topics=1 pruned=0" ]
  [ "$(ledger_rows)" = "$(printf '2026-09-20T10:00:00Z\t%s\t-Users-x-store\talpha.md\tmain' "$S1")" ]
}

@test "the grep fallback (no rg) records the same row" {
  tool "$(main_t "$ROOT_A" "$S1")" Read "$MEM/alpha.md" 2026-09-20T10:00:00.000Z
  CC_READ_LEDGER_RG=none run "$CLI"
  [ "$status" -eq 0 ]
  [ "$output" = "LEDGER-VERDICT scanned=1 reads=1 topics=1 pruned=0" ]
  [ "$(ledger_rows)" = "$(printf '2026-09-20T10:00:00Z\t%s\t-Users-x-store\talpha.md\tmain' "$S1")" ]
}

@test "no readable root abstains with a parseable reason and writes nothing" {
  CC_READ_LEDGER_ROOTS="$BATS_TEST_TMPDIR/nowhere" run "$CLI"
  [ "$status" -eq 0 ]
  [ "$output" = "LEDGER-VERDICT abstained reason=no-transcript-roots" ]
  [ ! -e "$STATE/memory-read-ledger.tsv" ]
}
