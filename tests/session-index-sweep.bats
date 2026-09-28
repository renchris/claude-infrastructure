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
# both polarities so neither "never steal" nor "always steal" can pass (the DEAD and RECYCLED
# holder reclaims are owned by session-index-lock-stale.bats cases 3 and 4).

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
  # The lock records ownership as TWO files, `pid` + `lstart` (see _session_index_lock_own) —
  # not a single `owner` line. These fixtures wrote `owner`, which the reclaim path never reads,
  # so every such case fell through to the dir-age branch and the suite tested nothing real.
  printf '%s\n' "$$" > "$LOCKD/pid"
  ps -o lstart= -p $$ > "$LOCKD/lstart"          # byte-identical to what the holder writes
  touch -t "$(date -v-200d +%Y%m%d%H%M)" "$LOCKD"
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_trylock && echo ACQUIRED'"
  [ "$status" -ne 0 ]
  ! echo "$output" | grep -q ACQUIRED
}

@test "acquiring stamps an owner, and unlock removes the whole lock dir" {
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_trylock; cat \"$LOCKD/pid\"'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^[0-9]+$'
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

# Every case above tracks at most ONE row, which is why the suite stayed green while BSD awk
# rejected `-v tracking=<multi-line table>` ("newline in string") on every real tick from the
# second tracked transcript onward: 191,067 log lines, nothing swept since 2026-09-07. The failure
# sat inside the sweep's `< <(…)`, so neither `set -e` nor any test could see it. These cases put
# /usr/bin/awk first on PATH, because that is the awk launchd runs.
SID_C=bbbbbbbb-cccc-dddd-eeee-ffffffffffff

track() { # <path> — record the file as swept at its CURRENT mtime+size, as the sweep would
  sqlite3 "$HOME/.claude/session-index.db" "INSERT INTO file_tracking
    (file_path, session_id, project_dir, last_mtime, last_size, last_swept_at)
    VALUES ('$1', 'x', 'p', $(stat -f %m "$1"), $(stat -f %z "$1"), '2026-01-01T00:00:00Z');"
}

@test "with 2+ tracked rows under BSD awk, new and grown files are detected and unchanged ones are not" {
  local d="$HOME/.claude/projects/-Users-x-proj"
  mk_transcript "$d/$SID_A.jsonl"; track "$d/$SID_A.jsonl"
  mk_transcript "$d/$SID_B.jsonl"; track "$d/$SID_B.jsonl"
  echo '{"type":"user","message":{"content":"appended after tracking"}}' >> "$d/$SID_B.jsonl"
  mk_transcript "$d/$SID_C.jsonl"
  run bash -c "PATH=/usr/bin:/bin:\$PATH HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_changed_files'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$SID_B"          # grown
  echo "$output" | grep -q "$SID_C"          # never tracked
  [[ "$output" != *"$SID_A"* ]] || false     # tracked and unchanged: proves the join ran
  ! grep -q "change detection FAILED" "$HOME/.claude/logs/session-index.log" 2>/dev/null || false
}

@test "a tracked path containing a space joins correctly among 2+ tracked rows" {
  local d="$HOME/.claude/projects/-Users-x-my proj"
  mk_transcript "$d/$SID_A.jsonl"; track "$d/$SID_A.jsonl"
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"
  track "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"
  mk_transcript "$d/$SID_C.jsonl"
  run bash -c "PATH=/usr/bin:/bin:\$PATH HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_changed_files'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "$d/$SID_C.jsonl"
  [[ "$output" != *"$SID_A"* ]] || false
  [[ "$output" != *"$SID_B"* ]]
}

@test "a failing change-detection join is LOGGED with its rc, not lost in the process substitution" {
  mkdir -p "$BATS_TEST_TMPDIR/shim"
  printf '#!/bin/sh\necho "awk: simulated failure" >&2\nexit 2\n' > "$BATS_TEST_TMPDIR/shim/awk"
  chmod +x "$BATS_TEST_TMPDIR/shim/awk"
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  run bash -c "PATH='$BATS_TEST_TMPDIR/shim':\$PATH HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_changed_files'"
  grep -q "change detection FAILED rc=2" "$HOME/.claude/logs/session-index.log"
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

  local ctx enr all
  ctx=$(session_index_extract_context "$t" 5)
  enr=$(session_index_extract_enriched "$t")
  all=$(session_index_extract_all "$t" 5)

  local a_ctx a_at a_fc a_cr a_mc e_at e_fc e_cr
  IFS=$'\t' read -r a_ctx a_at a_fc a_cr a_mc <<< "$all"
  IFS=$'\t' read -r e_at e_fc e_cr <<< "$enr"

  [ "$a_ctx" = "$ctx" ]
  [ "$a_at"  = "$e_at" ]
  [ "$a_fc"  = "$e_fc" ]
  [ "$a_cr"  = "$e_cr" ]
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

# ══ (4) retention: the index must not outlive its subject ══════════════════════════════════════
# 5,453 session rows indexed ~1,600 transcripts because CC deletes transcripts at 30 d and nothing
# deleted the rows (audit 03 §1c). L4: every delete case is paired with a keep case, and the
# fail-closed case is the one that matters most — a wrong reading of "0 transcripts" would wipe
# the whole index.

@test "a session whose transcript is gone is reported, then deleted with --retention-apply" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"
  bash "$SWEEP"
  rm -f "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"

  run bash "$SWEEP" --retention
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "before=2"
  echo "$output" | grep -q "deletable=1"
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT COUNT(*) FROM sessions;"
  [ "$output" = "2" ]                     # report-only really did not delete

  run bash "$SWEEP" --retention-apply
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "after=1"
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT session_id FROM sessions;"
  [ "$output" = "$SID_A" ]                # the surviving one is the one still on disk
}

@test "retention also clears the FTS and tracking rows, not just sessions" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"   # survivor: keeps the
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"   # on-disk set non-empty
  bash "$SWEEP"
  rm -f "$HOME/.claude/projects/-Users-x-proj/$SID_B.jsonl"
  bash "$SWEEP" --retention-apply
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT COUNT(*) FROM sessions_fts WHERE session_id='$SID_B';"
  [ "$output" = "0" ]
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT COUNT(*) FROM file_tracking WHERE session_id='$SID_B';"
  [ "$output" = "0" ]
}

@test "FAIL-CLOSED: an unreadable projects dir deletes NOTHING (not 'the index is all stale')" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  bash "$SWEEP"
  rm -rf "$HOME/.claude/projects"
  run bash "$SWEEP" --retention-apply
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "deletable=0"
  run sqlite3 "$HOME/.claude/session-index.db" "SELECT COUNT(*) FROM sessions;"
  [ "$output" = "1" ]
}

@test "the weekly pass is self-damped: it runs once, then not again inside the window" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  bash "$SWEEP"
  local st="$HOME/.claude/state/session-index-retention.last"
  [ -f "$st" ]
  # Damping is keyed on the stamp's MTIME, so that is what the assertions read (two runs
  # inside the same second write an identical ISO string — content proves nothing here).
  local m1 m2
  m1=$(stat -f %m "$st")
  touch -t "$(date -v-9d +%Y%m%d%H%M)" "$st"     # pretend the last pass was 9 days ago
  bash "$SWEEP"
  m2=$(stat -f %m "$st")
  [ "$m2" -ge "$m1" ]                            # due ⇒ the stamp was refreshed to now
  [ -z "$(find "$st" -maxdepth 0 -mtime +6 2>/dev/null)" ]

  # ...and now that it is fresh, a further tick must NOT re-run it
  touch -t "$(date -v-9d +%Y%m%d%H%M)" "$st"
  bash "$SWEEP"                                  # this one IS due → refreshes
  local m3; m3=$(stat -f %m "$st")
  bash "$SWEEP"                                  # this one is NOT due → must not touch it
  [ "$(stat -f %m "$st")" = "$m3" ]
}

@test "SESSION_INDEX_RETENTION_DAYS=0 disables the weekly pass entirely" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  SESSION_INDEX_RETENTION_DAYS=0 run bash "$SWEEP"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.claude/state/session-index-retention.last" ]
}

# ══ (3) Dynamic Workflow result files ═════════════════════════════════════════════════════════════
# A workflow's result lives only in `<project>/<sid>/workflows/wf_*.json`; the TrueMemory study's
# miss #106 had its answer there and nowhere the index read (docs/research/truememory-2026-09-27.md
# §3.18). Each file becomes its OWN row keyed on its stem; the parent session's row is never touched.
WF_ID=wf_abc12345-678

mk_workflow() { # <path> — result words (zanzibarquux) appear ONLY in `result`; script/logs carry
                # their own (scriptonlyword / logonlyword), which must never be indexed
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'JSON'
{"runId":"wf_abc12345-678","timestamp":"2026-09-20T10:00:00Z","taskId":"t1",
 "workflowName":"docs-audit","summary":"Audit the docs tree for stale plans","status":"completed",
 "phases":[{"title":"Ground truth","detail":"map the code"}],
 "result":[{"finding":"the zanzibarquux ledger is orphaned","files":["docs/a.md"]},"second note"],
 "logs":["logonlyword appeared in a log"],
 "script":"export const meta = { name: 'scriptonlyword' }",
 "scriptPath":"/tmp/x.js","durationMs":10,"totalTokens":5}
JSON
}

wf_path() { printf '%s' "$HOME/.claude/projects/-Users-x-proj/$SID_A/workflows/$WF_ID.json"; }
db() { sqlite3 "$HOME/.claude/session-index.db" "$1"; }

@test "a workflow result file is indexed as its OWN row, findable by a word only in its result" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_workflow "$(wf_path)"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run db "SELECT session_id FROM sessions_fts WHERE sessions_fts MATCH 'zanzibarquux';"
  [ "$output" = "$WF_ID" ]
  run db "SELECT source || '|' || project_path || '|' || first_prompt FROM sessions WHERE session_id='$WF_ID';"
  [ "$output" = "workflow-sweep|/Users/x/proj|workflow docs-audit: Audit the docs tree for stale plans" ]
  run db "SELECT COUNT(*) FROM sessions_fts WHERE sessions_fts MATCH 'ground';"   # a phase title
  [ "$output" = "1" ]
}

@test "a workflow's script body and logs are never indexed" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_workflow "$(wf_path)"
  bash "$SWEEP"
  run db "SELECT COUNT(*) FROM sessions WHERE session_id='$WF_ID';"
  [ "$output" = "1" ]                          # the row exists, so the zeros below mean something
  run db "SELECT COUNT(*) FROM sessions_fts WHERE sessions_fts MATCH 'scriptonlyword';"
  [ "$output" = "0" ]
  run db "SELECT COUNT(*) FROM sessions_fts WHERE sessions_fts MATCH 'logonlyword';"
  [ "$output" = "0" ]
}

@test "indexing a workflow file leaves the parent session's row and FTS row byte-identical" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  bash "$SWEEP"
  local q="SELECT session_id,project_path,project_name,summary,first_prompt,context_text,assistant_text,files_changed,commands_run,message_count,keywords,source FROM sessions WHERE session_id='$SID_A';"
  local qf="SELECT session_id,first_prompt,context_text FROM sessions_fts WHERE session_id='$SID_A';"
  local before beforef
  before=$(db "$q"); beforef=$(db "$qf")
  [ -n "$before" ]
  mk_workflow "$(wf_path)"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run db "SELECT COUNT(*) FROM sessions WHERE session_id='$WF_ID';"
  [ "$output" = "1" ]
  [ "$(db "$q")" = "$before" ]
  [ "$(db "$qf")" = "$beforef" ]
}

@test "an unchanged workflow file is not re-extracted on the next sweep, a changed one is" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_workflow "$(wf_path)"
  bash "$SWEEP"
  local p; p=$(wf_path)
  run db "SELECT session_id || '|' || sweep_count FROM file_tracking WHERE file_path='$p';"
  [ "$output" = "$WF_ID|1" ]
  bash "$SWEEP"
  run db "SELECT sweep_count FROM file_tracking WHERE file_path='$p';"
  [ "$output" = "1" ]                          # untouched file ⇒ no second extraction
  printf ' ' >> "$p"                           # size moves ⇒ detected again
  bash "$SWEEP"
  run db "SELECT sweep_count FROM file_tracking WHERE file_path='$p';"
  [ "$output" = "2" ]
}

@test "a malformed workflow file is tracked and skipped; the sweep and the transcript survive it" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mkdir -p "$(dirname "$(wf_path)")"
  printf '{"runId": "wf_abc12345-678", "result": [trunc' > "$(wf_path)"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run db "SELECT COUNT(*) FROM sessions WHERE session_id='$WF_ID';"
  [ "$output" = "0" ]
  run db "SELECT COUNT(*) FROM sessions WHERE session_id='$SID_A';"
  [ "$output" = "1" ]
  local p; p=$(wf_path)
  run db "SELECT COUNT(*) FROM file_tracking WHERE file_path='$p';"
  [ "$output" = "1" ]                          # tracked, so it is not re-parsed every tick
}

@test "retention keeps a workflow row while its file exists and drops it once the file is gone" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_workflow "$(wf_path)"
  bash "$SWEEP"                                  # the first tick also runs the weekly pass
  run db "SELECT COUNT(*) FROM sessions WHERE session_id='$WF_ID';"
  [ "$output" = "1" ]
  rm -f "$(wf_path)"
  run bash "$SWEEP" --retention-apply
  [ "$status" -eq 0 ]
  run db "SELECT COUNT(*) FROM sessions WHERE session_id='$WF_ID';"
  [ "$output" = "0" ]
  run db "SELECT COUNT(*) FROM sessions WHERE session_id='$SID_A';"
  [ "$output" = "1" ]
}

@test "change detection reaches wf files at depth 4 but not depth-4 subagent transcripts" {
  mk_workflow "$(wf_path)"
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A/subagents/agent-deadbeef.jsonl"
  run bash -c "HOME='$HOME' bash -c 'source \"$HELPERS\"; session_index_changed_files'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "/workflows/$WF_ID.json"
  [[ "$output" != *agent-deadbeef* ]] || false
}

# ══ (5) every account root ════════════════════════════════════════════════════════════════════════
# Each account keeps its own projects root; the sweep read only $CLAUDE_PROJECTS_DIR, so ~70 of ~205
# transcripts from one day and 320 of 376 workflow files (the #106 gold among them) were never
# indexed. The sweep, retention and the parity count now share session_index_project_roots.

@test "one sweep indexes a transcript in root A and a workflow file in root B" {
  local a="$BATS_TEST_TMPDIR/rootA" b="$BATS_TEST_TMPDIR/rootB"
  mk_transcript "$a/-Users-x-proj/$SID_A.jsonl"
  mk_workflow "$b/-Users-x-proj/$SID_B/workflows/$WF_ID.json"
  # shellcheck disable=SC2030,SC2031  # test-local on purpose: each @test is its own subshell
  export SESSION_INDEX_PROJECT_ROOTS="$a $b"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run db "SELECT session_id FROM sessions ORDER BY session_id;"
  [ "$output" = "$SID_A
$WF_ID" ]
  run db "SELECT session_id FROM sessions_fts WHERE sessions_fts MATCH 'zanzibarquux';"
  [ "$output" = "$WF_ID" ]
  run db "SELECT project_dir FROM file_tracking WHERE session_id='$WF_ID';"
  [ "$output" = "$b/-Users-x-proj/" ]
}

@test "a symlinked root that resolves to a listed root is swept once" {
  local a="$BATS_TEST_TMPDIR/rootA" alias="$BATS_TEST_TMPDIR/rootA-alias"
  mk_transcript "$a/-Users-x-proj/$SID_A.jsonl"
  ln -s "$a" "$alias"
  # shellcheck disable=SC2030,SC2031  # test-local on purpose: each @test is its own subshell
  export SESSION_INDEX_PROJECT_ROOTS="$a $alias"
  run bash -c "source \"$HELPERS\"; session_index_project_roots"
  [ "$output" = "$a" ]
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run db "SELECT COUNT(*) FROM sessions WHERE session_id='$SID_A';"
  [ "$output" = "1" ]
  run db "SELECT file_path || '|' || sweep_count FROM file_tracking;"
  [ "$output" = "$a/-Users-x-proj/$SID_A.jsonl|1" ]
}

@test "with no root list, the default reaches the other accounts' roots" {
  mk_transcript "$HOME/.claude/projects/-Users-x-proj/$SID_A.jsonl"
  mk_transcript "$HOME/.claude-tertiary/projects/-Users-x-proj/$SID_B.jsonl"
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run db "SELECT COUNT(*) FROM sessions WHERE session_id IN ('$SID_A','$SID_B');"
  [ "$output" = "2" ]
}

@test "a caller-set CLAUDE_PROJECTS_DIR alone is the only root scanned" {
  local p="$BATS_TEST_TMPDIR/fixture-projects"
  mk_transcript "$p/-Users-x-proj/$SID_A.jsonl"
  mk_transcript "$HOME/.claude-secondary/projects/-Users-x-proj/$SID_B.jsonl"   # a default root
  export CLAUDE_PROJECTS_DIR="$p"
  run bash -c "source \"$HELPERS\"; session_index_project_roots --with-absent"
  [ "$output" = "$p" ]
  run bash "$SWEEP"
  [ "$status" -eq 0 ]
  run db "SELECT session_id FROM sessions;"
  [ "$output" = "$SID_A" ]
}

@test "retention keeps a row whose transcript is in another root, drops it once gone" {
  local a="$BATS_TEST_TMPDIR/rootA" b="$BATS_TEST_TMPDIR/rootB"
  mk_transcript "$a/-Users-x-proj/$SID_A.jsonl"
  mk_transcript "$b/-Users-x-proj/$SID_B.jsonl"
  # shellcheck disable=SC2030,SC2031  # test-local on purpose: each @test is its own subshell
  export SESSION_INDEX_PROJECT_ROOTS="$a $b"
  bash "$SWEEP"
  run bash "$SWEEP" --retention-apply
  [ "$status" -eq 0 ]
  run db "SELECT COUNT(*) FROM sessions;"
  [ "$output" = "2" ]                          # B's row survives: its evidence is in root B
  rm -f "$b/-Users-x-proj/$SID_B.jsonl"
  run bash "$SWEEP" --retention-apply
  [ "$status" -eq 0 ]
  run db "SELECT session_id FROM sessions;"
  [ "$output" = "$SID_A" ]
}
