#!/usr/bin/env bats
# wrap-ledger.sh § backlog-fold cache — `cc-backlog list` served from an exact (mtime,size) cache,
# filled by ONE detached filler per store state, with a bounded wait (fix/stop-hook-latency,
# 2026-09-24). The uncached behaviour every other wrap-ledger suite pins is untouched: they stub
# CC_BACKLOG_BIN, and auto mode never caches a stubbed binary. These cases force the cache ON
# (WRAP_BACKLOG_CACHE=on) against a counting stub, so every claim is about calls actually made.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LEDGER="$REPO/scripts/wrap-ledger.sh"
  # a private $HOME: every default this ledger falls back to (~/.claude stores, the backlog path,
  # the detach lib's second tier) must resolve inside the fixture, never on the operator's box
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || return 1
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt; git add base.txt; git commit -q -m base
  git push -q -u origin main
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"
  export WRAP_TRUNK="origin/main"
  unset WRAP_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/no-live-layer"
  export WRAP_LIVE_ROOT="$BATS_TEST_TMPDIR/no-live-root"
  export CC_MIGRATIONS_STATE="$BATS_TEST_TMPDIR/migrations"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  unset WRAP_LIVE_BUDGET_COMMITS WRAP_LIVE_BUDGET_MIN
  export CC_DECIDE_BIN="$BATS_TEST_TMPDIR/absent-cc-decide"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export WRAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/projects"
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/teams"
  mkdir -p "$CC_WF_TEAM_ROOTS"
  # the memo would serve run 2 from run 1 and hide every backlog read — keep it out of the picture
  export WRAP_CACHE=off
  SID="sess-11111111-2222-3333-4444-555555555555"
  export WRAP_SESSION_ID="$SID"

  # the cache under test: a private dir, a fixture store, a counting stub
  export WRAP_BACKLOG_CACHE=on
  export WRAP_BACKLOG_CACHE_DIR="$BATS_TEST_TMPDIR/blc"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  printf '{"id":"B-77","event":"add"}\n' > "$CC_BACKLOG_FILE"
  export STUB_CALLS="$BATS_TEST_TMPDIR/calls.log"; : > "$STUB_CALLS"
  export STUB_ALL="$BATS_TEST_TMPDIR/all.json" STUB_BLOCKED="$BATS_TEST_TMPDIR/blocked.json"
  printf '[{"id":"A-1","status":"open","filedBy":"%s"}]\n' "$SID" > "$STUB_ALL"
  printf '[{"id":"B-77","status":"blocked","needs":"load the plist","session":"%s"}]\n' "$SID" > "$STUB_BLOCKED"
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/cc-backlog-stub"
  cat > "$CC_BACKLOG_BIN" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_CALLS"
[ -n "${STUB_SLEEP:-}" ] && sleep "$STUB_SLEEP"
[ -n "${STUB_FAIL:-}" ] && exit 1
case "$*" in *--all*) cat "$STUB_ALL" ;; *) cat "$STUB_BLOCKED" ;; esac
STUB
  chmod +x "$CC_BACKLOG_BIN"

  # the ✅-eligible state, so both backlog reads (YOURS and FILED) actually run
  printf -- '- [x] item one\n' > "$BATS_TEST_TMPDIR/dod-ok.md"
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/dod-ok.md"
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"
}

field() { printf '%s' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }
calls() { grep -c -e "$1" "$STUB_CALLS" | tr -d ' '; }
# rc 0 = a FINISHED entry for list args $1 exists. An entry's name ends in its args (`…_--json`); a
# filler's temp file ends `…_--json.XXXXXX` and its lock `…_--json.fill`, so neither can match.
has_entry() {
  local e
  for e in "$WRAP_BACKLOG_CACHE_DIR"/wl-*; do
    [ -f "$e" ] || continue
    case "$e" in *"$1"*_--json) return 0 ;; esac
  done
  return 1
}
# wait (bounded) until the detached filler has put an entry for $1 in place
await_entry() {
  local i=0
  while [ "$i" -lt 150 ]; do has_entry "$1" && return 0; sleep 0.2; i=$((i + 1)); done
  return 1
}

@test "a hit serves both folds without re-running cc-backlog, and the ledger is the same" {
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" YOURS)" = "1" ]
  [ "$(field "$output" FILED_MINE)" = "1" ]
  first="$output"
  [ "$(calls '--blocked')" = "1" ]
  [ "$(calls '--all')" = "1" ]
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(calls '--blocked')" = "1" ]
  [ "$(calls '--all')" = "1" ]
  [ "$(field "$output" YOURS)" = "1" ]
  [ "$(field "$output" FILED_MINE)" = "1" ]
  [ "$(field "$output" RUNG)" = "$(field "$first" RUNG)" ]
}

@test "an append to the store invalidates the entry: the next read folds again" {
  run bash "$LEDGER" --machine
  [ "$(calls '--blocked')" = "1" ]
  printf '{"id":"B-78","event":"add"}\n' >> "$CC_BACKLOG_FILE"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(calls '--blocked')" = "2" ]
  [ "$(calls '--all')" = "2" ]
}

@test "auto mode never caches a stubbed binary (every other suite's uncached contract)" {
  export WRAP_BACKLOG_CACHE=auto
  run bash "$LEDGER" --machine
  run bash "$LEDGER" --machine
  [ "$(calls '--blocked')" = "2" ]
  [ -z "$(ls -A "$WRAP_BACKLOG_CACHE_DIR" 2>/dev/null)" ]
}

@test "WRAP_BACKLOG_CACHE=off is uncached even when forced elsewhere" {
  export WRAP_BACKLOG_CACHE=off
  run bash "$LEDGER" --machine
  run bash "$LEDGER" --machine
  [ "$(calls '--all')" = "2" ]
}

@test "a failing fold caches nothing and reads as error, as the uncached call did" {
  export STUB_FAIL=1
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" YOURS_SRC)" = "error" ]
  [ "$(field "$output" FILED_SRC)" = "error" ]
  run has_entry '--blocked'
  [ "$status" -ne 0 ]
  run has_entry '--all'
  [ "$status" -ne 0 ]
}

@test "a fold slower than the wait fails open in time, then the detached fill serves the next run" {
  export STUB_SLEEP=6 WRAP_BACKLOG_WAIT_S=1
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  # the wait expired before the fold finished: fail-open, exactly like a timed-out bounded call
  [ "$(field "$output" YOURS_SRC)" = "error" ]
  [ "$(field "$output" FILED_SRC)" = "error" ]
  # …and the filler outlived the run and filled both entries anyway
  await_entry '--blocked'
  await_entry '--all'
  n="$(calls 'list')"
  run bash "$LEDGER" --machine
  [ "$(field "$output" YOURS)" = "1" ]
  [ "$(field "$output" FILED_MINE)" = "1" ]
  [ "$(field "$output" FILED_SRC)" != "error" ]
  [ "$(calls 'list')" = "$n" ]
}

@test "single flight: two concurrent ledgers start one fold per list between them" {
  export STUB_SLEEP=2 WRAP_BACKLOG_WAIT_S=60
  bash "$LEDGER" --machine > "$BATS_TEST_TMPDIR/a.out" 2>/dev/null &
  bash "$LEDGER" --machine > "$BATS_TEST_TMPDIR/b.out" 2>/dev/null &
  wait
  [ "$(calls '--blocked')" = "1" ]
  [ "$(calls '--all')" = "1" ]
  [ "$(field "$(cat "$BATS_TEST_TMPDIR/a.out")" YOURS)" = "1" ]
  [ "$(field "$(cat "$BATS_TEST_TMPDIR/b.out")" YOURS)" = "1" ]
}

@test "one-pass FILED read: an error in the UNCONVICTED count zeroes only that count, never FILED" {
  # whyNotNow is a NUMBER on the second row: `startswith` raises on it. Pre-merge that failed only
  # the third jq (u=0) and left f and c standing; the merged pass must keep that isolation.
  printf '[{"id":"A-1","status":"open","filedBy":"%s"},{"id":"A-2","status":"open","filedBy":"%s","whyNotNow":5,"ts":"2026-09-20T00:00:00Z"}]\n' \
    "$SID" "$SID" > "$STUB_ALL"
  for mode in on off; do
    WRAP_BACKLOG_CACHE="$mode" run bash "$LEDGER" --machine
    [ "$status" -eq 0 ]
    [ "$(field "$output" FILED_MINE)" = "1" ]
    [ "$(field "$output" FILED_SRC)" != "error" ]
    [ "$(field "$output" UNCONVICTED_ROWS)" = "0" ]
  done
}

@test "a cache that cannot be written falls back to the plain bounded call, with the right answer" {
  : > "$BATS_TEST_TMPDIR/not-a-dir"
  export WRAP_BACKLOG_CACHE_DIR="$BATS_TEST_TMPDIR/not-a-dir"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" YOURS)" = "1" ]
  [ "$(field "$output" FILED_MINE)" = "1" ]
  run bash "$LEDGER" --machine
  [ "$(field "$output" YOURS)" = "1" ]
  [ "$(calls '--blocked')" = "2" ]
}

@test "two spellings of one binary share one entry (hooks reach it via hooks/../scripts/../bin)" {
  run bash "$LEDGER" --machine
  [ "$(calls '--blocked')" = "1" ]
  mkdir -p "$BATS_TEST_TMPDIR/sub"
  CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/sub/../cc-backlog-stub" run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" YOURS)" = "1" ]
  [ "$(calls '--blocked')" = "1" ]
  [ "$(calls '--all')" = "1" ]
}
