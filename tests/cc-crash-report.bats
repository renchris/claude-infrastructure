#!/usr/bin/env bats
# cc-crash-report — reads the de-conflated claude-crashes.jsonl ledger and (--backfill)
# reclassifies recent watchdog-detected deaths. Safety-critical: --backfill must NEVER
# invoke a watchdog hook lacking --classify (an old copy would spawn a daemon per call).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  BIN="$REPO/bin/cc-crash-report"
  export CC_LOG_DIR="$BATS_TEST_TMPDIR/logs"
  mkdir -p "$CC_LOG_DIR"
  LEDGER="$CC_LOG_DIR/claude-crashes.jsonl"
}

@test "empty ledger → friendly no-data message, exit 0" {
  run bash "$BIN"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "No crash ledger yet"
}

@test "ledger summary counts CRASH vs RECYCLE and cause" {
  printf '%s\n' \
    '{"ts":"t1","sid":"aaaa","class":"CRASH","cause":"jetsam-oom","transcript_kb":8000}' \
    '{"ts":"t2","sid":"bbbb","class":"RECYCLE","cause":"deliberate-self-close","transcript_kb":5000}' \
    '{"ts":"t3","sid":"cccc","class":"CRASH","cause":"abrupt-unknown","transcript_kb":300}' \
    > "$LEDGER"
  run bash "$BIN"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "2 CRASH"
  echo "$output" | grep -q "1 RECYCLE"
  echo "$output" | grep -q "jetsam-oom"
}

@test "--crashes lists only CRASH rows" {
  printf '%s\n' \
    '{"class":"CRASH","cause":"jetsam-oom"}' \
    '{"class":"RECYCLE","cause":"deliberate-self-close"}' \
    > "$LEDGER"
  run bash "$BIN" --crashes
  echo "$output" | grep -q '"class":"CRASH"'
  ! echo "$output" | grep -q '"class":"RECYCLE"'
}

@test "--backfill REFUSES a watchdog hook without --classify (daemon-spawn guard)" {
  # a stale hook that lacks --classify support
  local stale="$BATS_TEST_TMPDIR/stale-hook.sh"
  printf '#!/bin/bash\necho stale\n' > "$stale"; chmod +x "$stale"
  printf '[watchdog %s] LEAD CRASH detected pid=1\n' "00000000-0000-0000-0000-000000000000" > "$CC_LOG_DIR/lead-crash-watchdog.log"
  CC_WATCHDOG_HOOK="$stale" run bash "$BIN" --backfill 5
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "no --classify support"
}
