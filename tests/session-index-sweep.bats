#!/usr/bin/env bats
# session-index sweep — the 107-day wedge and the scanner it would have unleashed (audit 06 §4.1,
# §5.3).
#
# Two independent defects, both covered here:
#   (1) `session_index_trylock` had no liveness test, so ONE abandoned mkdir-lock
#       (~/.claude/session-index.lock.d, mtime 2026-04-09) made the sweep exit at line 27 on all
#       ~1,440 ticks/day for 107 days. Session search stopped indexing in April; nothing noticed.
#   (2) Unblocking that lock without fixing the scan turns a no-op into a 59 s-per-60 s-tick
#       scanner: 2× stat + 1× sqlite3 per transcript, then THREE full-file python3 parses of the
#       same file. Hence the batched change detection and the single-pass extractor.
#
# Harness laws: L1 the fixtures are real transcript JSONL and a real SQLite index built by the
# shipped init functions; L2 every assertion is failure-DISTINCT (a live owner's lock is NOT
# stolen — the mirror of "an abandoned lock IS"); L3 `[ ]` / `grep -q` only; L4 each lock rule has
# both polarities so neither "never steal" nor "always steal" can pass.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/projects/-Users-x-proj" "$HOME/.claude/logs" "$HOME/.claude/state"
  SWEEP="$REPO/hooks/session-index-sweep.sh"
  HELPERS="$REPO/hooks/lib/session-index-helpers.sh"
  # shellcheck disable=SC1090
  source "$HELPERS"
  session_index_init_db
  session_index_init_tracking
  LOCKD="$HOME/.claude/session-index.lock.d"
}

teardown() { rm -rf "$LOCKD" 2>/dev/null || true; }

SID_A=11111111-2222-3333-4444-555555555555
SID_B=66666666-7777-8888-9999-aaaaaaaaaaaa

mk_transcript() { # <path>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'JSONL'
{"type":"user","message":{"content":"please fix the batched sweep so it stops re-parsing"}}
{"type":"assistant","message":{"content":[{"type":"text","text":"I will collapse the three parses into one pass over each changed transcript file."},{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/alpha.txt"}},{"type":"tool_use","name":"Bash","input":{"command":"echo hello"}}]}}
{"type":"user","message":{"content":"second user message with enough length to count"}}
JSONL
}

# ══ (1) staleness-aware trylock ════════════════════════════════════════════════════════════════

@test "an UNSTAMPED lock past the staleness horizon is taken over (the 107-day wedge)" {
  mkdir -p "$LOCKD"
  touch -t "$(date -v-200d +%Y%m%d%H%M)" "$LOCKD"
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_trylock && echo ACQUIRED'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q ACQUIRED
}

@test "a FRESH unstamped lock is NOT taken over (the horizon is real, not decoration)" {
  mkdir -p "$LOCKD"
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_trylock && echo ACQUIRED'"
  [ "$status" -ne 0 ]
  ! echo "$output" | grep -q ACQUIRED
}

@test "a lock whose owner is ALIVE is never stolen, however old it looks" {
  # A backfill legitimately holds this for hours and mkdir's mtime never refreshes.
  mkdir -p "$LOCKD"
  printf '%s %s' "$$" "$(ps -o lstart= -p $$ | tr -s ' ')" > "$LOCKD/owner"
  touch -t "$(date -v-200d +%Y%m%d%H%M)" "$LOCKD"
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_trylock && echo ACQUIRED'"
  [ "$status" -ne 0 ]
  ! echo "$output" | grep -q ACQUIRED
}

@test "a lock whose owner pid is DEAD is taken over immediately" {
  mkdir -p "$LOCKD"
  printf '99999999 Wed Jan  1 00:00:00 2020' > "$LOCKD/owner"
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_trylock && echo ACQUIRED'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q ACQUIRED
}

@test "a lock whose pid was RECYCLED into a different process is taken over" {
  # Same pid, different start time — `kill -0` alone would call this alive forever.
  mkdir -p "$LOCKD"
  printf '%s Wed Jan  1 00:00:00 2020' "$$" > "$LOCKD/owner"
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_trylock && echo ACQUIRED'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q ACQUIRED
}

@test "acquiring stamps an owner, and unlock removes the whole lock dir" {
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_trylock; cat \"$LOCKD/owner\"'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^[0-9]+ '
  [ ! -d "$LOCKD" ]          # the EXIT trap released it
}

# ══ (2) batched change detection ═══════════════════════════════════════════════════════════════

@test "changed-files returns a new transcript, then nothing once it is tracked" {
  local t="$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_transcript "$t"

  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_changed_files'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$SID_A"

  bash "$SWEEP"
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_changed_files'"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q "$SID_A"
}

@test "a transcript that GROWS is detected again (size+mtime, not existence)" {
  local t="$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_transcript "$t"
  bash "$SWEEP"
  echo '{"type":"user","message":{"content":"a third message appended after indexing"}}' >> "$t"
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_changed_files'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$SID_A"
}

@test "the sweep indexes a transcript end-to-end and is a no-op on the second run" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT COUNT(*) FROM sessions WHERE session_id='$SID_A';"
  [ "$output" = "1" ]
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT COUNT(*) FROM file_tracking;"
  [ "$output" = "1" ]

  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT sweep_count FROM file_tracking;"
  [ "$output" = "1" ]          # untouched file ⇒ no second upsert
}

@test "the nested {sid}/transcript.jsonl layout still indexes" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_B/transcript.jsonl"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT COUNT(*) FROM sessions WHERE session_id='$SID_B';"
  [ "$output" = "1" ]
}

@test "the per-tick cap defers the overflow instead of running unbounded, and says so" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"
  SESSION_INDEX_SWEEP_MAX_FILES=1 run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT COUNT(*) FROM sessions;"
  [ "$output" = "1" ]
  grep -q "DEFERRED 1" "$HOME/.claude/logs/session-index.log"
  # the deferred one lands on the next tick
  run bash "$SWEEP"
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT COUNT(*) FROM sessions;"
  [ "$output" = "2" ]
}

# ══ cadence knob ═══════════════════════════════════════════════════════════════════════════════

@test "the cadence knob suppresses a tick inside its window and the plist stays at 60s" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  bash "$SWEEP"                                        # writes the stamp
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"
  SESSION_INDEX_SWEEP_MIN_INTERVAL_S=3600 run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT COUNT(*) FROM sessions;"
  [ "$output" = "1" ]                                  # the second transcript was NOT indexed

  run plutil -extract StartInterval raw -o - "$REPO/launchd/com.claude.session-search-sweep.plist"
  [ "$output" = "60" ]
}

# ══ (3) one-pass extraction is field-for-field identical to the three it replaces ══════════════

@test "extract_all reproduces context, assistant text, files, commands and message count" {
  local t="$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_transcript "$t"

  local ctx enr meta all
  ctx=$(session_index_extract_context "$t" 5)
  enr=$(session_index_extract_enriched "$t")
  meta=$(session_index_extract_transcript_meta "$t")
  all=$(session_index_extract_all "$t" 5)

  local a_ctx a_at a_fc a_cr a_mc e_at e_fc e_cr
  IFS=$'\t' read -r a_ctx a_at a_fc a_cr a_mc <<< "$all"
  IFS=$'\t' read -r e_at e_fc e_cr <<< "$enr"

  [ "$a_ctx" = "$ctx" ]
  [ "$a_at"  = "$e_at" ]
  [ "$a_fc"  = "$e_fc" ]
  [ "$a_cr"  = "$e_cr" ]
  [ "$a_mc"  = "$meta" ]
  # and it is not vacuously equal — the fixture really carries all four
  echo "$a_fc" | grep -q '/tmp/alpha.txt'
  echo "$a_cr" | grep -q 'echo hello'
  [ "$a_mc" = "2" ]
}

@test "extract_all tolerates a transcript path containing a quote (env-passed, not interpolated)" {
  local t="$HOME/.claude/projects/-Users-x-proj/od'd-$SID_A.jsonl"
  mk_transcript "$t"
  run session_index_extract_all "$t" 5
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'collapse the three parses'
}
