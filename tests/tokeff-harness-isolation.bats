#!/usr/bin/env bats
# The token-efficiency eval harness files into a PER-RUN ledger, never the real operator stores
# (BACKLOG_MASTER W0 ledger-admission.1). The 09-24/25 gate minted 73 project=fx rows into the real
# backlog because run.sh set no CC_BACKLOG_FILE.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RUNSH="$REPO/docs/research/token-efficiency-2026-09-23/eval/harness/run.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy" "$HOME/.claude/mailbox"
  : > "$HOME/.claude/autonomy/backlog.jsonl"
  export CC_BACKLOG_KICK=off CC_BACKLOG_PROJECT_WARN=off CC_BACKLOG_COVERAGE_WARN=off CC_BACKLOG_PREMISE=off
  unset CC_BACKLOG_FILE CC_BACKLOG_IDL CC_BACKLOG_VALIDATED CC_DECISIONS_DIR CC_MAILBOX_DIR GATE_GUARD
  # a minimal task, arm and config dir; the "claude" is a stub that files one row the way a run would
  export GATE_TASKS="$BATS_TEST_TMPDIR/tasks"; mkdir -p "$GATE_TASKS/T99"
  printf 'do the thing\n' > "$GATE_TASKS/T99/prompt.txt"
  printf '#!/bin/bash\nmkdir -p "$1" && git -C "$1" init -q\n' > "$GATE_TASKS/T99/fixture.sh"
  chmod +x "$GATE_TASKS/T99/fixture.sh"
  CCD="$BATS_TEST_TMPDIR/ccd"; mkdir -p "$CCD"
  export CLAUDE_BIN="$BATS_TEST_TMPDIR/claude-stub"
  printf '#!/bin/bash\nbash %q add --title "stub filing from a run" --project fx >/dev/null\necho "{}"\n' \
    "$REPO/bin/cc-backlog" > "$CLAUDE_BIN"
  chmod +x "$CLAUDE_BIN"
}

mkarms() { mkdir -p "$1/arms/full/rules"; : > "$1/arms/full/CLAUDE.md"; : > "$1/arms/full/rules/x.md"; }

@test "harness: a run's filings land in \$RUN/out/backlog.jsonl and the real ledger is byte-identical" {
  export GATE_ROOT="$BATS_TEST_TMPDIR/gate"; mkarms "$GATE_ROOT"
  before="$(shasum "$HOME/.claude/autonomy/backlog.jsonl")"
  run bash "$RUNSH" full T99 1 "$CCD"
  [ "$status" -eq 0 ]
  [ "$(shasum "$HOME/.claude/autonomy/backlog.jsonl")" = "$before" ]
  grep -q 'stub filing from a run' "$GATE_ROOT/runs/T99/r1/out/backlog.jsonl"
}

@test "harness: refuses to start when a store override resolves inside the real autonomy store" {
  export GATE_ROOT="$HOME/.claude/autonomy/gate"; mkarms "$GATE_ROOT"
  run bash "$RUNSH" full T99 1 "$CCD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"refusing to start"* ]] || false
  [ ! -e "$GATE_ROOT/runs" ]
}

@test "harness: a caller's own CC_BACKLOG_FILE pointing at the real store is overridden, not inherited" {
  export GATE_ROOT="$BATS_TEST_TMPDIR/gate"; mkarms "$GATE_ROOT"
  export CC_BACKLOG_FILE="$HOME/.claude/autonomy/backlog.jsonl"
  run bash "$RUNSH" full T99 1 "$CCD"
  [ "$status" -eq 0 ]
  [ ! -s "$HOME/.claude/autonomy/backlog.jsonl" ]
}
