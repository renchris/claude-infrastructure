#!/usr/bin/env bats
# session-index sweep — the sessions_fts identity fingerprint and the hourly parity alarm
# (docs/research/truememory-2026-09-27.md P1, §5.13).
#
# sessions_fts was DROPped and re-created, not DELETEd, by a racing migration probe. SQLite has no
# DDL triggers, so the sweep detects it from the table's IDENTITY (sqlite_master rowid of
# sessions_fts : rootpage of sessions_fts_data) and from a damped row-count parity check.
#
# Harness laws, as in session-index-sweep.bats: a real SQLite index built by the shipped init
# functions under a temp HOME; every alarm case is paired with its quiet case, so neither "always
# log" nor "never log" can pass. The one stub is a PATH-shimmed sqlite3 that fails ONLY the
# identity read, because a genuinely locked DB would also fail the sweep's own init before the
# code under test ever ran.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/projects/-Users-x-proj" "$HOME/.claude/logs" "$HOME/.claude/state"
  # Pin the per-root list so the verdict never reads the real account roots of this machine.
  export SESSION_INDEX_PROJECT_ROOTS="$HOME/.claude/projects $HOME/.claude-secondary/projects"
  SWEEP="$REPO/hooks/session-index-sweep.sh"
  HELPERS="$REPO/hooks/lib/session-index-helpers.sh"
  # shellcheck disable=SC1090
  source "$HELPERS"
  session_index_init_db
  session_index_init_tracking
  DB="$HOME/.claude/session-index.db"
  LOG="$HOME/.claude/logs/session-index.log"
  IDF="$HOME/.claude/state/session-index-fts-identity"
  STAMP="$HOME/.claude/state/session-index-fts-parity.last"
}

teardown() { rm -rf "$HOME/.claude/session-index.lock.d" 2>/dev/null || true; }

SID_A=11111111-2222-3333-4444-555555555555
SID_B=66666666-7777-8888-9999-aaaaaaaaaaaa

mk_transcript() { # <path>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'JSONL'
{"type":"user","message":{"content":"please index this transcript for the identity check"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"Indexed, and the fts row sits beside the sessions row."}]}}
JSONL
}

log_count() { grep -c -- "$1" "$LOG" 2>/dev/null || true; }
backdate_stamp() { touch -t "$(date -v-2H +%Y%m%d%H%M)" "$STAMP"; }

# ══ identity fingerprint ═══════════════════════════════════════════════════════════════════════

@test "first tick records the identity and logs no CHANGED line" {
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ -f "$IDF" ]
  grep -Eq '^[0-9]+:[0-9]+$' "$IDF"
  [ "$(log_count 'FTS-IDENTITY CHANGED')" = "0" ]
}

@test "an unchanged table over two ticks logs no CHANGED line and keeps the same identity" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  bash "$SWEEP"
  local id1; id1="$(cat "$IDF")"
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"   # real writes in between
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(cat "$IDF")" = "$id1" ]
  [ "$(log_count 'FTS-IDENTITY CHANGED')" = "0" ]
}

@test "DROP of sessions_fts between ticks (re-created by the next init) logs FTS-IDENTITY CHANGED" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  bash "$SWEEP"
  local id1; id1="$(cat "$IDF")"
  # The incident shape: the table goes, and the sweep's own idempotent init re-creates it empty.
  sqlite3 "$DB" "DROP TABLE sessions_fts;"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(log_count 'FTS-IDENTITY CHANGED')" = "1" ]
  grep -q "FTS-IDENTITY CHANGED old=$id1 new=$(cat "$IDF") (DROP+CREATE unless a VACUUM ran)" "$LOG"
  [ "$(cat "$IDF")" != "$id1" ]
  # ...and it is reported once, not on every later tick
  bash "$SWEEP"
  [ "$(log_count 'FTS-IDENTITY CHANGED')" = "1" ]
}

@test "a change seen on a minute tick survives into the next hourly verdict (sticky)" {
  bash "$SWEEP"                                   # verdict 1: identity=ok, stamp fresh
  grep -q 'SWEEP-VERDICT .* identity=ok$' "$LOG"
  sqlite3 "$DB" "DROP TABLE sessions_fts;"
  bash "$SWEEP"                                   # detects the change; inside the damp window
  [ "$(log_count 'SWEEP-VERDICT')" = "1" ]
  bash "$SWEEP"                                   # a quiet tick: this tick's own read is ok
  backdate_stamp
  bash "$SWEEP"                                   # verdict 2 must still say changed
  [ "$(log_count 'SWEEP-VERDICT')" = "2" ]
  tail -n 5 "$LOG" | grep -q 'SWEEP-VERDICT .* identity=changed$'
}

@test "the sweep's own retention VACUUM re-baselines the identity instead of alarming" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"
  bash "$SWEEP"
  rm -f "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"
  run bash "$SWEEP" --retention-apply
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "after=1"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(log_count 'FTS-IDENTITY CHANGED')" = "0" ]
}

@test "an identity read that FAILS logs FTS-IDENTITY UNKNOWN, is not read as unchanged, and exits 0" {
  bash "$SWEEP"
  local id1; id1="$(cat "$IDF")"
  local real; real="$(command -v sqlite3)"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # Fails only the identity query, the way a lock or a mid-flight DROP would; every other
  # statement reaches the real sqlite3.
  cat > "$BATS_TEST_TMPDIR/bin/sqlite3" <<SH
#!/bin/bash
case "\$*" in *sessions_fts_data*) echo "Error: database is locked" >&2; exit 5 ;; esac
exec "$real" "\$@"
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/sqlite3"
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash "$SWEEP"
  [ "$status" -eq 0 ]
  grep -q 'FTS-IDENTITY UNKNOWN rc=5' "$LOG"
  [ "$(log_count 'FTS-IDENTITY CHANGED')" = "0" ]
  [ "$(cat "$IDF")" = "$id1" ]                   # the last good identity is kept, not blanked
  # the sweep's normal work still happened
  run sqlite3 "$DB" "SELECT COUNT(*) FROM sessions WHERE session_id='$SID_A';"
  [ "$output" = "1" ]
}

# ══ parity alarm + verdict ═════════════════════════════════════════════════════════════════════

@test "fts rows deleted behind the index's back ⇒ FTS-PARITY DRIFT once, not again inside the window" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  SESSION_INDEX_FTS_PARITY_TOLERANCE=0 bash "$SWEEP"
  [ "$(log_count 'FTS-PARITY DRIFT')" = "0" ]      # in parity: quiet
  sqlite3 "$DB" "DELETE FROM sessions_fts;"
  backdate_stamp
  SESSION_INDEX_FTS_PARITY_TOLERANCE=0 run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ "$(log_count 'FTS-PARITY DRIFT')" = "1" ]
  grep -q 'FTS-PARITY DRIFT fts=0 sessions=1' "$LOG"
  SESSION_INDEX_FTS_PARITY_TOLERANCE=0 run bash "$SWEEP"  # still drifted, but damped
  [ "$status" -eq 0 ]
  [ "$(log_count 'FTS-PARITY DRIFT')" = "1" ]
  # alarm-only: nothing rebuilt the fts rows
  run sqlite3 "$DB" "SELECT COUNT(*) FROM sessions_fts;"
  [ "$output" = "0" ]
}

@test "a drift within the tolerance stays quiet" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  SESSION_INDEX_FTS_PARITY_TOLERANCE=1 bash "$SWEEP"
  sqlite3 "$DB" "DELETE FROM sessions_fts;"
  backdate_stamp
  SESSION_INDEX_FTS_PARITY_TOLERANCE=1 bash "$SWEEP"
  [ "$(log_count 'FTS-PARITY DRIFT')" = "0" ]
}

@test "the verdict line carries every field, with per-root counts and an absent root named" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  grep -Eq 'SWEEP-VERDICT roots=\.claude:1,\.claude-secondary:absent fts_rows=1 sessions=1 newest_swept_age_s=[0-9]+ identity=ok$' "$LOG"
}

@test "SESSION_INDEX_FTS_PARITY_MINUTES=0 disables the damped pass but not the identity check" {
  SESSION_INDEX_FTS_PARITY_MINUTES=0 run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ ! -f "$STAMP" ]
  [ "$(log_count 'SWEEP-VERDICT')" = "0" ]
  [ -f "$IDF" ]
}
