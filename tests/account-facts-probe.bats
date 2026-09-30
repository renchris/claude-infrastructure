#!/usr/bin/env bats
# scripts/account-facts-probe.sh — the recorders settle master-account-facts rows
# (BACKLOG_MASTER W0 ledger-retraction.9).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PROBE="$REPO/scripts/account-facts-probe.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_AUTH_TIMESERIES="$BATS_TEST_TMPDIR/auth.jsonl" CC_RELOGIN_LOG="$BATS_TEST_TMPDIR/relogin.log"
  export CC_PROBE_NOW=1790000000     # 2026-09-21T12:53:20Z
}

ts_line() { printf '{"ts":"%s","acct":"%s","state":"%s","n_live":%s}\n' "$1" "$2" "$3" "$4"; }

@test "herd: no OK->non-OK transition at >= N live in the window exits 0" {
  { ts_line 2026-09-01T00:00:00Z next OK 5; ts_line 2026-09-10T00:00:00Z next EMPTY 0
    ts_line 2026-09-20T00:00:00Z next2 OK 1; } > "$CC_AUTH_TIMESERIES"
  run bash "$PROBE" herd --min-live 6 --days 14
  [ "$status" -eq 0 ]
}

@test "herd: a transition that logs out >= N live sessions exits 1" {
  { ts_line 2026-09-01T00:00:00Z next OK 1; ts_line 2026-09-15T00:00:00Z next OK 9
    ts_line 2026-09-15T00:05:00Z next EMPTY 0; } > "$CC_AUTH_TIMESERIES"
  run bash "$PROBE" herd --min-live 5 --days 14
  [ "$status" -eq 1 ]
  [[ "$output" == *"herd: 1"* ]]
}

@test "herd: a recorder shorter than the window, or absent, is exit 2 — never a verdict" {
  ts_line 2026-09-20T00:00:00Z next OK 1 > "$CC_AUTH_TIMESERIES"
  run bash "$PROBE" herd --min-live 5 --days 14
  [ "$status" -eq 2 ]
  rm -f "$CC_AUTH_TIMESERIES"
  run bash "$PROBE" herd --min-live 5 --days 14
  [ "$status" -eq 2 ]
}

@test "relogin-proven: a linked row closes through cc-premise once cc-relogin logs PROVEN for its account" {
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl" CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off CC_BACKLOG_PROJECT_WARN=off CC_BACKLOG_COVERAGE_WARN=off CC_BACKLOG_PREMISE=off
  export CC_PREMISE_READINGS_REQUIRED=1
  printf '2026-09-20T10:00:00Z RESULT next attempt=1 exit=1 error\n' > "$CC_RELOGIN_LOG"
  cd "$BATS_TEST_TMPDIR"
  id="$(bash "$REPO/bin/cc-backlog" add --title "does a headless refresh move next's login cliff" --project acctfacts \
        --falsifier "bash $PROBE relogin-proven next --since 2026-09-20T00:00:00Z")"
  run python3 "$REPO/bin/cc-premise" sweep --record --close-falsified 5 --json
  [ "$(printf '%s' "$output" | jq -r '.closed_falsified')" = 0 ]
  printf '2026-09-21T09:00:00Z RESULT next attempt=1 exit=0 PROVEN — deadline moved\n' >> "$CC_RELOGIN_LOG"
  run python3 "$REPO/bin/cc-premise" sweep --record --close-falsified 5 --json
  [ "$(printf '%s' "$output" | jq -r '.closed_falsified')" = 1 ]
  [ "$(bash "$REPO/bin/cc-backlog" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.status')" = done ]
}
