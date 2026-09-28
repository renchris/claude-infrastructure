#!/usr/bin/env bats
# session_index_init_db — the probe that dropped sessions_fts (TrueMemory study §3.2 P0b, gap 5).
#
# The column probes read `PRAGMA table_info` with no busy timeout and treated ANY failure as
# "column missing". Under contention one returned nothing ("database is locked"), the migration
# heredoc ran without -bail, its ALTER failed on the duplicate column, and the
# `DROP TABLE IF EXISTS sessions_fts` after it still succeeded. The SCHEMA pass then re-created
# the table EMPTY: 40 of 9,422 rows searchable on the live index. Errexit callers died before the
# "Migrated" log line, so nothing recorded it.
#
# The sqlite3 shim fails exactly the reads a test names and passes everything else to the real
# binary, so each case differs from a healthy run by one failed read.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  HELPERS="$REPO/hooks/lib/session-index-helpers.sh"
  DB="$HOME/.claude/session-index.db"
  LOG="$HOME/.claude/logs/session-index.log"
  REAL_SQLITE="$(command -v sqlite3)"
  SHIM="$BATS_TEST_TMPDIR/shim"
  mkdir -p "$SHIM"
  export SHIM_CALLS="$BATS_TEST_TMPDIR/sqlite-calls" SHIM_FAIL="" SHIM_STATE="$BATS_TEST_TMPDIR"
  # SHIM_FAIL=<substring>: the FIRST call whose argv contains it fails like a locked DB (rc 5).
  cat > "$SHIM/sqlite3" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "\$SHIM_CALLS"
if [ -n "\$SHIM_FAIL" ] && [ ! -f "\$SHIM_STATE/failed-once" ]; then
  case "\$*" in *"\$SHIM_FAIL"*)
    touch "\$SHIM_STATE/failed-once"
    echo "Error: database is locked" >&2
    exit 5 ;;
  esac
fi
exec "$REAL_SQLITE" "\$@"
EOF
  chmod +x "$SHIM/sqlite3"
}

# A fully-migrated index with three searchable sessions, built by the shipped init, then stamped
# back to user_version 0 — the state of every index built before the version gate existed.
build_full_db() {
  bash -c "source '$HELPERS'; session_index_init_db"
  "$REAL_SQLITE" "$DB" <<'SQL'
INSERT INTO sessions (session_id, project_path, project_name, summary, created_at, modified_at, indexed_at)
VALUES ('s1','/p','p','alpha summary','t','t','t'),
       ('s2','/p','p','beta summary','t','t','t'),
       ('s3','/p','p','gamma summary','t','t','t');
INSERT INTO sessions_fts (session_id, summary, first_prompt, tags, keywords, project_name, context_text, assistant_text, files_changed, commands_run, search_aliases)
  SELECT session_id, summary, first_prompt, tags, keywords, project_name, context_text, assistant_text, files_changed, commands_run, search_aliases FROM sessions;
PRAGMA user_version = 0;
SQL
  rm -f "$SHIM_CALLS"
}

init_db_via_shim() { # [extra shell prefix, e.g. "set -euo pipefail;"]
  run bash -c "$1 PATH='$SHIM':\$PATH; source '$HELPERS'; session_index_init_db; echo INIT_OK"
}

fts_count() { "$REAL_SQLITE" "$DB" "SELECT COUNT(*) FROM sessions_fts;"; }

@test "a FAILED column probe skips every migration: sessions_fts survives and the failure is logged" {
  build_full_db
  [ "$(fts_count)" = "3" ]
  SHIM_FAIL=table_info init_db_via_shim
  [ "$(fts_count)" = "3" ]
  grep -q "init_db probe failed" "$LOG"
  ! grep -q "Migrated" "$LOG" || false
}

@test "a FAILED user_version read also skips every migration, never runs them" {
  build_full_db
  SHIM_FAIL=user_version init_db_via_shim
  [ "$(fts_count)" = "3" ]
  grep -q "init_db user_version read failed" "$LOG"
  ! grep -q "Migrated" "$LOG" || false
}

@test "under set -euo pipefail a failed probe returns 0 and leaves the index intact" {
  build_full_db
  SHIM_FAIL=table_info init_db_via_shim "set -euo pipefail;"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q INIT_OK
  [ "$(fts_count)" = "3" ]
}

@test "a genuinely missing column is migrated and sessions_fts is repopulated, logged once before the DDL" {
  "$REAL_SQLITE" "$DB" <<'SQL'
CREATE TABLE sessions (
    session_id TEXT PRIMARY KEY, project_path TEXT NOT NULL, project_name TEXT NOT NULL,
    summary TEXT NOT NULL DEFAULT '', first_prompt TEXT NOT NULL DEFAULT '',
    git_branch TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, modified_at TEXT NOT NULL,
    message_count INTEGER NOT NULL DEFAULT 0, tags TEXT NOT NULL DEFAULT '',
    keywords TEXT NOT NULL DEFAULT '', source TEXT NOT NULL DEFAULT 'unknown',
    indexed_at TEXT NOT NULL, tagged_at TEXT DEFAULT NULL);
CREATE VIRTUAL TABLE sessions_fts USING fts5(session_id, summary, first_prompt, tags, keywords, project_name);
INSERT INTO sessions (session_id, project_path, project_name, summary, created_at, modified_at, indexed_at)
VALUES ('s1','/p','p','alpha summary','t','t','t'), ('s2','/p','p','beta summary','t','t','t');
INSERT INTO sessions_fts (session_id, summary, first_prompt, tags, keywords, project_name)
  SELECT session_id, summary, first_prompt, tags, keywords, project_name FROM sessions;
SQL
  init_db_via_shim "set -euo pipefail;"
  [ "$status" -eq 0 ]
  for c in context_text assistant_text files_changed commands_run search_aliases; do
    "$REAL_SQLITE" "$DB" "SELECT name FROM pragma_table_info('sessions');" | grep -qx "$c"
  done
  [ "$(fts_count)" = "2" ]
  [ "$("$REAL_SQLITE" "$DB" "SELECT COUNT(*) FROM sessions_fts WHERE sessions_fts MATCH 'alpha';")" = "1" ]
  "$REAL_SQLITE" "$DB" "SELECT search_aliases FROM sessions_fts LIMIT 1;" >/dev/null   # new FTS shape
  [ "$(grep -c "Migrated" "$LOG")" = "1" ]
}

@test "once stamped, a second init_db runs no column probe at all (the hot-path gate)" {
  bash -c "source '$HELPERS'; session_index_init_db"      # fresh DB: schema pass + stamp
  rm -f "$SHIM_CALLS"
  init_db_via_shim
  [ "$status" -eq 0 ]
  ! grep -q "table_info" "$SHIM_CALLS" || false
  [ "$(wc -l < "$SHIM_CALLS" | tr -d ' ')" = "1" ]         # the one user_version read
}
