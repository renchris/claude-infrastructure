#!/usr/bin/env bats
# session_index_history_gapfill — index the sessions that exist only in the prompt history.
#
# WHY IT EXISTS. The union built by bin/cc-history-union has exactly one consumer worth having:
# something that turns a prompt record into a searchable index row. That used to be phases 2-3 of
# session-index-backfill.sh, which on the path launchd invokes has exited 1 at line 13 on every
# scheduled run (a `source` of $SCRIPT_DIR/lib/progress-ui.sh that resolves under ~/.claude/bin/
# and does not exist) — which is why the index carried zero rows with source='history'.
#
# Harness laws: L1 the DB is built by the shipped session_index_init_db and the history is real
# JSONL in the real record shape; L2 every case names the ONE mutation of the subject it dies
# under; L3 `[ ]` / `grep -q` only; L4 the insert and the DON'T-TOUCH directions are both asserted,
# so neither "never insert" nor "overwrite everything" can pass.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export SESSION_INDEX_DB="$HOME/.claude/session-index.db"
  export CLAUDE_HISTORY="$HOME/hist.jsonl"
  # shellcheck disable=SC1090
  source "$REPO/hooks/lib/session-index-helpers.sh"
  session_index_init_db

  # s-new: two prompts, deliberately written LATEST-FIRST so a subject that takes the last record
  # it sees rather than the earliest one is caught by the first_prompt case.
  cat > "$CLAUDE_HISTORY" <<'JSONL'
{"display":"SECOND prompt of the new session","pastedContents":{},"project":"/w/proj-new","sessionId":"s-new","timestamp":2000}
{"display":"FIRST prompt uniquefrobnicator","pastedContents":{},"project":"/w/proj-new","sessionId":"s-new","timestamp":1000}
{"display":"prompt of an already indexed session","pastedContents":{},"project":"/w/proj-old","sessionId":"s-old","timestamp":3000}
JSONL
}

_have() { sqlite3 "$SESSION_INDEX_DB" "SELECT COUNT(*) FROM sessions WHERE session_id='$1';"; }

# Mutant: skip the INSERT entirely (the pre-fix state — nothing consumes the history). Dies here.
@test "a session present only in history is inserted, tagged source=history" {
  run session_index_history_gapfill
  [ "$status" -eq 0 ]
  grep -q 'verdict=ok' <<< "$output"
  grep -q 'inserted=2' <<< "$output"
  [ "$(_have s-new)" -eq 1 ]
  run sqlite3 "$SESSION_INDEX_DB" "SELECT source FROM sessions WHERE session_id='s-new';"
  [ "$output" = "history" ]
}

# Mutant: insert into `sessions` but not into `sessions_fts`. Dies here — and this is the whole
# point of the feature, because sessions_fts has NO triggers on this schema, so a row that is not
# explicitly synced exists but can never be found by claude-search.
@test "the inserted row is FTS-searchable, not merely present in the table" {
  run session_index_history_gapfill
  [ "$status" -eq 0 ]
  run sqlite3 "$SESSION_INDEX_DB" \
    "SELECT session_id FROM sessions_fts WHERE sessions_fts MATCH 'uniquefrobnicator';"
  [ "$output" = "s-new" ]
}

# Mutant: take the last record seen for a session. Dies here — first_prompt must be the EARLIEST.
@test "first_prompt is the session's earliest prompt, not the last record read" {
  run session_index_history_gapfill
  [ "$status" -eq 0 ]
  run sqlite3 "$SESSION_INDEX_DB" "SELECT first_prompt FROM sessions WHERE session_id='s-new';"
  grep -q 'FIRST prompt' <<< "$output"
}

# Mutant: upsert unconditionally instead of inserting only missing ids. Dies here — a history row
# is the poorest source there is and must never overwrite a transcript-derived one.
@test "an already-indexed session is left untouched" {
  session_index_upsert_with_fts "s-old" "/real/path" "realname" "a real summary" \
    "a real first prompt" "" "2026-01-01T00:00:00Z" "2026-01-01T00:00:00Z" 42 "" "" "transcript"
  run session_index_history_gapfill
  [ "$status" -eq 0 ]
  grep -q 'already_indexed=1' <<< "$output"
  run sqlite3 "$SESSION_INDEX_DB" \
    "SELECT source||'|'||summary||'|'||project_name||'|'||message_count FROM sessions WHERE session_id='s-old';"
  [ "$output" = "transcript|a real summary|realname|42" ]
}

# Mutant: drop the "already in the table" filter. Dies here — a second pass must be a no-op, since
# the sweep runs this on a cadence forever.
@test "re-running inserts nothing and creates no duplicate" {
  run session_index_history_gapfill; [ "$status" -eq 0 ]
  run session_index_history_gapfill
  [ "$status" -eq 0 ]
  grep -q 'inserted=0' <<< "$output"
  run sqlite3 "$SESSION_INDEX_DB" "SELECT COUNT(*) FROM sessions;"
  [ "$output" -eq 2 ]
  run sqlite3 "$SESSION_INDEX_DB" "SELECT COUNT(*) FROM sessions_fts WHERE session_id='s-new';"
  [ "$output" -eq 1 ]
}

# Mutant: index records with no session id (or crash on them). Dies here — there is no key to
# index a session-less record on, and a malformed line must not abort the pass.
@test "records with no sessionId, no project, or unparseable JSON are skipped, not fatal" {
  cat >> "$CLAUDE_HISTORY" <<'JSONL'
{"display":"legacy record with no session id","pastedContents":{},"project":"/w/legacy","timestamp":4000}
{"display":"record with no project","pastedContents":{},"sessionId":"s-noproj","timestamp":5000}
{ this is not json
JSONL
  run session_index_history_gapfill
  [ "$status" -eq 0 ]
  grep -q 'unparseable=1' <<< "$output"
  grep -q 'inserted=2' <<< "$output"
  [ "$(_have s-noproj)" -eq 0 ]
}

# Mutant: treat a missing history file as fatal, or as an empty success. Dies here — the verdict
# must SAY which, because the sweep logs this line and a silent 0 would read as "nothing to do".
@test "a missing history file is a named verdict, not a crash and not a silent zero" {
  rm -f "$CLAUDE_HISTORY"
  run session_index_history_gapfill
  [ "$status" -eq 0 ]
  grep -q 'verdict=no-history' <<< "$output"
}
