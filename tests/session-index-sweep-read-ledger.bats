#!/usr/bin/env bats
# session-index-sweep.sh — the hourly memory read-ledger block (TrueMemory #15,
# docs/research/truememory-2026-09-27.md §3.15; acceptance X1 self-path, X2 own IDL name).
#
# The block is damped by a stamp, so each cadence rule is pinned in both polarities: due runs the
# CLI, a fresh stamp does not, an expired stamp does again, and 0 disables it even with no stamp.
# The CLI is a stub (it appends to $STUB_MARK) everywhere except the last case, which runs the REAL
# CLI through a symlinked hooks dir — the only case that can fail if the block resolves the CLI from
# `dirname "$0"` instead of the dereferenced self-path.
#
# Assertions are simple commands only (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/projects/-Users-x-proj" "$HOME/.claude/logs" "$HOME/.claude/state"
  SWEEP="$REPO/hooks/session-index-sweep.sh"
  # shellcheck disable=SC1091
  source "$REPO/hooks/lib/session-index-helpers.sh"
  session_index_init_db
  session_index_init_tracking
  # Every OTHER damped block off, so each case exercises the read-ledger block alone.
  export CC_HISTORY_UNION_MINUTES=0 SESSION_INDEX_RETENTION_DAYS=0 SESSION_INDEX_FTS_PARITY_MINUTES=0
  unset CC_READ_LEDGER_MINUTES CC_READ_LEDGER_STAMP SESSION_INDEX_PROJECT_ROOTS
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export STUB_MARK="$BATS_TEST_TMPDIR/stub.runs"
  STAMP="$HOME/.claude/state/memory-read-ledger.last"
  STUB="$BATS_TEST_TMPDIR/stub-ledger"
  stub 'echo "LEDGER-VERDICT scanned=3 reads=1 topics=1 pruned=0"'
  export CC_READ_LEDGER_BIN="$STUB"
}

teardown() { rm -rf "$HOME/.claude/session-index.lock.d" 2>/dev/null || true; }

stub() { # <body line> — the stub records each run, then runs the body
  # shellcheck disable=SC2016  # $STUB_MARK must reach the stub unexpanded; the stub reads it at run time
  printf '#!/bin/bash\necho run >>"$STUB_MARK"\n%s\n' "$1" >"$STUB"
  chmod +x "$STUB"
}

runs()     { if [ -f "$STUB_MARK" ]; then grep -c . "$STUB_MARK"; else echo 0; fi; }
idl_rows() { if [ -f "$CC_IDL" ]; then jq -r 'select(.hook=="session-index-sweep:read-ledger") | "\(.disposition) \(.reason)"' "$CC_IDL"; fi; }

@test "due (no stamp): the CLI runs once, the stamp is written, and ONE fired row lands under the block's own name" {
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(runs)" -eq 1 ]
  [ -f "$STAMP" ]
  [ "$(idl_rows)" = "fired ledger-written" ]
  grep -q 'Read ledger: LEDGER-VERDICT scanned=3 reads=1 topics=1 pruned=0 rc=0' "$HOME/.claude/logs/session-index.log"
}

@test "not due (fresh stamp): the CLI does not run and no IDL row is written" {
  date -u +%Y-%m-%dT%H:%M:%SZ >"$STAMP"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(runs)" -eq 0 ]
  [ -z "$(idl_rows)" ]
}

@test "due again once the stamp is older than the window" {
  date -u +%Y-%m-%dT%H:%M:%SZ >"$STAMP"
  touch -t "$(date -v-2H +%Y%m%d%H%M)" "$STAMP"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(runs)" -eq 1 ]
}

@test "CC_READ_LEDGER_MINUTES=0 disables the block even with no stamp" {
  CC_READ_LEDGER_MINUTES=0 run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(runs)" -eq 0 ]
  [ ! -e "$STAMP" ]
  [ -z "$(idl_rows)" ]
}

@test "a CLI that fails without a verdict leaves the sweep at exit 0 and logs abstained ledger-cli-failed" {
  stub 'echo "Traceback: boom" >&2; echo garbage; exit 3'
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(runs)" -eq 1 ]
  [ "$(idl_rows)" = "abstained ledger-cli-failed" ]
  grep -q 'Read ledger: garbage rc=3' "$HOME/.claude/logs/session-index.log"
}

@test "the CLI's own abstain reason is carried into the IDL row verbatim" {
  stub 'echo "LEDGER-VERDICT abstained reason=no-transcript-roots"'
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(idl_rows)" = "abstained no-transcript-roots" ]
}

@test "a CLI that does not resolve logs abstained ledger-cli-missing and the sweep still exits 0" {
  CC_READ_LEDGER_BIN="$BATS_TEST_TMPDIR/absent" run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(idl_rows)" = "abstained ledger-cli-missing" ]
}

@test "X1: run through a symlinked hooks dir, the block finds the REAL CLI via the dereferenced self-path" {
  unset CC_READ_LEDGER_BIN
  mkdir -p "$HOME/.claude/hooks"
  ln -s "$REPO/hooks/session-index-sweep.sh" "$HOME/.claude/hooks/session-index-sweep.sh"
  ln -s "$REPO/hooks/lib" "$HOME/.claude/hooks/lib"
  [ ! -e "$HOME/.claude/bin/cc-memory-read-ledger" ]   # nothing to find beside the symlink
  local root="$BATS_TEST_TMPDIR/acct/projects"
  mkdir -p "$root/-Users-x-proj"
  printf '{"type":"assistant","timestamp":"2026-09-20T10:00:00.000Z","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"/Users/x/.claude/projects/-Users-x-store/memory/alpha.md"}}]}}\n' \
    >"$root/-Users-x-proj/11111111-1111-1111-1111-111111111111.jsonl"
  CC_READ_LEDGER_ROOTS="$root" run bash "$HOME/.claude/hooks/session-index-sweep.sh"
  [ "$status" -eq 0 ]
  [ "$(idl_rows)" = "fired ledger-written" ]
  grep -q $'\t-Users-x-store\talpha.md\tmain$' "$HOME/.claude/state/memory-read-ledger.tsv"
}
