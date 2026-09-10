#!/usr/bin/env bats
# session_index_retention — the transcript test must not delete the history gap-fill.
#
# WHY IT EXISTS. `session_index_history_gapfill` indexes exactly the sessions that have NO
# transcript this box can still read, and retention's victim predicate is "indexed but absent from
# the on-disk transcript universe". Those two are the same set BY CONSTRUCTION: measured on the
# live index 2026-09-10, 2,900 of 2,902 source='history' rows and 358 of 358 source='history-legacy'
# rows were victims. Retention is weekly and the gap-fill hourly, so the unexempted predicate is a
# churn loop with a weekly window of up to 60 min in which ~3,000 sessions are unsearchable.
#
# Harness laws: L1 the DB is the shipped session_index_init_db and the transcript universe is real
# files under a real SESSION_INDEX_PROJECT_ROOTS; L2 every case names the ONE mutation of the
# subject it dies under; L3 `[ ]` / `grep -q` only; L4 the RETAIN and the STILL-DELETE directions
# are both asserted, so neither "delete everything" nor "blanket amnesty" can pass.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs" "$BATS_TEST_TMPDIR/projects/proj"
  export SESSION_INDEX_DB="$HOME/.claude/session-index.db"
  export SESSION_INDEX_LOG="$HOME/.claude/logs/session-index.log"
  export CLAUDE_HISTORY="$HOME/hist.jsonl"
  export SESSION_INDEX_PROJECT_ROOTS="$BATS_TEST_TMPDIR/projects"
  # shellcheck disable=SC1090
  source "$REPO/hooks/lib/session-index-helpers.sh"
  session_index_init_db
  # The sweep calls this before EVERY retention pass (hooks/session-index-sweep.sh:43,76), and
  # retention's delete batch is one transaction over five tables including file_tracking — so a
  # fixture that skips it makes every DELETE abort and the whole suite reads as "nothing is ever
  # deleted", which is the opposite of what these cases are asserting.
  session_index_init_tracking

  # The on-disk universe is NON-EMPTY, so the 0-transcripts refusal above the block under test
  # cannot be what makes a case pass — that refusal returns "before before 0" and would retain
  # every row for a reason that has nothing to do with this fix.
  : > "$BATS_TEST_TMPDIR/projects/proj/s-live.jsonl"

  cat > "$CLAUDE_HISTORY" <<'JSONL'
{"display":"a prompt from the gap-filled session","pastedContents":{},"project":"/w/proj","sessionId":"s-hist","timestamp":1000}
{"display":"a prompt from the live session","pastedContents":{},"project":"/w/proj","sessionId":"s-live","timestamp":2000}
JSONL

  _row() { # <sid> <source>
    session_index_upsert_with_fts "$1" "/w/proj" "proj" "" "p" "" \
      "2026-01-01T00:00:00Z" "2026-01-01T00:00:00Z" 1 "" "" "$2"
  }
  _have() { sqlite3 "$SESSION_INDEX_DB" "SELECT COUNT(*) FROM sessions WHERE session_id='$1';"; }
}

# Mutant: drop the exemption block entirely (the pre-fix subject). Dies here.
@test "a source=history row with no transcript but a live prompt record is RETAINED" {
  _row s-hist history
  _row s-live transcript
  run session_index_retention --apply
  [ "$status" -eq 0 ]
  [ "$(_have s-hist)" -eq 1 ]
}

# Mutant: exempt only source='history'. Dies here — phase 3 of the backfill writes synthetic
# `legacy-<sha16>` ids that can never match a transcript either.
@test "a source=history-legacy row is RETAINED even though its id matches no prompt record" {
  _row legacy-deadbeefdeadbeef history-legacy
  _row s-live transcript
  run session_index_retention --apply
  [ "$status" -eq 0 ]
  [ "$(_have legacy-deadbeefdeadbeef)" -eq 1 ]
}

# Mutant: retain every source='history' row unconditionally. Dies here — the exemption has to be
# BOUNDED, or the index grows forever and "self-cleaning" is a claim nothing enforces.
@test "a source=history row whose prompt record has aged out of the history IS deleted" {
  _row s-gone history
  _row s-live transcript
  run session_index_retention --apply
  [ "$status" -eq 0 ]
  [ "$(_have s-gone)" -eq 0 ]
}

# Mutant: subtract the exempt set from every row rather than from the history-derived ones — i.e.
# turn the exemption into a blanket amnesty. Dies here; retention must still do its actual job.
@test "a transcript-derived row whose transcript is gone is STILL deleted" {
  _row s-hist history
  _row s-dead transcript
  _row s-live transcript
  run session_index_retention --apply
  [ "$status" -eq 0 ]
  [ "$(_have s-dead)" -eq 0 ]
  [ "$(_have s-live)" -eq 1 ]
}

# Mutant: fail OPEN when the evidence cannot be read (treat an empty set as "nothing is evidenced").
# Dies here — an unreadable history would otherwise reproduce the exact bug this file exists to
# close, and silently, which is the worse of the two directions.
@test "an unreadable history retains every history-derived row and says so by name" {
  _row s-hist history
  _row legacy-deadbeefdeadbeef history-legacy
  _row s-live transcript
  rm -f "$CLAUDE_HISTORY"
  run session_index_retention --apply
  [ "$status" -eq 0 ]
  [ "$(_have s-hist)" -eq 1 ]
  [ "$(_have legacy-deadbeefdeadbeef)" -eq 1 ]
  run cat "$SESSION_INDEX_LOG"
  grep -q 'history evidence UNREADABLE' <<< "$output"
}

# Mutant: keep the old "removed N session(s) with no transcript on disk" wording. Dies here — that
# line was an alarm that fired weekly at roughly the same N no matter what, because the N it
# reported was dominated by rows that never had a transcript to lose.
@test "the applied log line reports the retained count, not just a removal count" {
  _row s-hist history
  _row s-dead transcript
  _row s-live transcript
  run session_index_retention --apply
  [ "$status" -eq 0 ]
  run cat "$SESSION_INDEX_LOG"
  grep -q 'retained 1 history-derived row' <<< "$output"
  grep -q 'whose evidence is gone' <<< "$output"
}

# Mutant: compute the exemption but never report it in the dry-run count. Dies here — the sweep's
# `--retention` mode is the operator's read of what a real pass would do.
@test "the dry-run count excludes the exempted rows" {
  _row s-hist history
  _row s-dead transcript
  _row s-live transcript
  run session_index_retention
  [ "$status" -eq 0 ]
  [ "$output" = "3 3 1" ]
  [ "$(_have s-hist)" -eq 1 ]
}
