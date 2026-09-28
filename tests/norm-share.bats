#!/usr/bin/env bats
# norm-share — scripts/norm-share.py, the nightly output metric for the transcript normaliser
# (docs/research/truememory-2026-09-27.md §3.14 gap item 3; nightly step 7c).
#
# Each case builds a fixture session-index DB holding only the sessions columns the script reads,
# with indexed_at in the live format (UTC `YYYY-MM-DDTHH:MM:SSZ`), and asserts the rendered lines.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  unset SESSION_INDEX_DB
  NS="$REPO/scripts/norm-share.py"
  DB="$BATS_TEST_TMPDIR/index.db"
}

# fixture <clean> <dirty> [<old-dirty>] — rows indexed a minute ago, plus dirty rows from 2020.
fixture() {
  python3 - "$DB" "$1" "$2" "${3:-0}" <<'EOF'
import sqlite3, sys
from datetime import datetime, timedelta, timezone
db, clean, dirty, old = sys.argv[1], *map(int, sys.argv[2:])
now = (datetime.now(timezone.utc) - timedelta(minutes=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
c = sqlite3.connect(db)
c.execute("CREATE TABLE sessions (session_id TEXT PRIMARY KEY, context_text TEXT NOT NULL DEFAULT '', indexed_at TEXT NOT NULL)")
rows = [("Refactor the widget parser.", now)] * clean
rows += [("Fix it. Stop hook feedback: the gate is red.", now)] * dirty
rows += [("<teammate-message teammate_id=\"x\">brief</teammate-message>", "2020-01-01T00:00:00Z")] * old
rows += [("", now)]  # empty context_text is never counted
c.executemany("INSERT INTO sessions VALUES (?, ?, ?)", [(str(i), t, s) for i, (t, s) in enumerate(rows)])
c.commit()
EOF
}

@test "all clean rows: ok" {
  fixture 10 0
  run python3 "$NS" --db "$DB"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "NORM-SHARE contaminated=0 total=10 pct=0" ]
  [ "${lines[1]}" = "verdict=ok" ]
}

@test "3 of 10 contaminated: regressed, exit 1" {
  fixture 7 3
  run python3 "$NS" --db "$DB"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "NORM-SHARE contaminated=3 total=10 pct=30" ]
  [ "${lines[1]}" = "verdict=regressed" ]
}

@test "1 of 12 contaminated: ok (pct rounds up to 9, still under 10)" {
  fixture 11 1
  run python3 "$NS" --db "$DB"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "NORM-SHARE contaminated=1 total=12 pct=9" ]
  [ "${lines[1]}" = "verdict=ok" ]
}

@test "4 rows: abstains too-few-rows, exit 0" {
  fixture 2 2
  run python3 "$NS" --db "$DB"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "NORM-SHARE contaminated=2 total=4 pct=50" ]
  [ "${lines[1]}" = "verdict=abstain reason=too-few-rows" ]
}

@test "rows indexed before the window are excluded" {
  fixture 10 0 5
  run python3 "$NS" --db "$DB"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "NORM-SHARE contaminated=0 total=10 pct=0" ]
  # control: a window wide enough to reach 2020 counts them, so the fixture discriminates
  run python3 "$NS" --db "$DB" --hours 100000
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "NORM-SHARE contaminated=5 total=15 pct=34" ]
}

@test "missing DB: abstains no-db, exit 0; the default path follows HOME" {
  run python3 "$NS" --db "$BATS_TEST_TMPDIR/absent.db"
  [ "$status" -eq 0 ]
  [ "$output" = "verdict=abstain reason=no-db" ]
  run python3 "$NS"
  [ "$status" -eq 0 ]
  [ "$output" = "verdict=abstain reason=no-db" ]
}

@test "a DB without the sessions table: abstains unreadable, exit 0" {
  python3 -c 'import sqlite3, sys; sqlite3.connect(sys.argv[1]).execute("CREATE TABLE other (x)")' "$DB"
  run python3 "$NS" --db "$DB"
  [ "$status" -eq 0 ]
  [ "$output" = "verdict=abstain reason=unreadable (OperationalError)" ]
}

@test "the DB is never written" {
  fixture 7 3
  before="$(shasum "$DB")"
  run python3 "$NS" --db "$DB"
  [ "$(shasum "$DB")" = "$before" ]
}

@test "a garbage --hours is refused with rc 2" {
  fixture 10 0
  run python3 "$NS" --db "$DB" --hours soon
  [ "$status" -eq 2 ]
  [[ "$output" == *"not a number of hours: 'soon'"* ]] || false
}
