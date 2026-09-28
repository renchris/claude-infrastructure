#!/usr/bin/env bats
# harvest-skill-end.sh — SessionEnd hook: logs a skill-harvest candidate row for
# substantive sessions so /harvest-skill has a backlog to synthesize from.
#
# The defect this pins: the hook read its three columns by joining them in SQL with
# '|' and splitting them back with `cut -d'|'`. `commands_run` is RAW SHELL TEXT and
# routinely contains pipes — one probed row carried 127 — so `-f2` was a fragment of
# the first command and `-f3` the next fragment, never the file list. Every candidate
# record the hook ever wrote carries the corruption (_candidates.jsonl line 1 stores a
# ` head -30 && echo …` fragment where the path list belongs). Same class as
# docs/research/TSV_FIELD_COLLAPSE_2026-07-25.md, at a call site that sweep never
# reached, and invisible because the artifact is only read by a human much later.
#
# RED-proof coverage: the load-bearing fixture's commands_run CONTAINS pipes, so it
# fails against the join+cut implementation and passes against per-column extraction;
# a pipe-FREE control proves the fix is general and not a special case for pipes; the
# gates and every fail-open path are asserted to write nothing rather than to crash.
#
# Assertions are simple commands only. bash exempts `[[ ]]` from errexit, so a
# non-final `[[ ]]` in a bats body evaluates and DISCARDS its result — the test would
# pass vacuously (scripts/bats-assert-liveness.py).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/harvest-skill-end.sh"
  # Fixture $HOME: the hook stages candidates under $HOME/.claude/skills-pending, and
  # an unfixtured suite would append to the operator's real harvest backlog.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export SESSION_INDEX_DB="$BATS_TEST_TMPDIR/idx.db"
  STAGE="$HOME/.claude/skills-pending/_candidates.jsonl"
  # The hook's IDL row goes here, never to the operator's live store; no stub re-read waits.
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export HARVEST_STUB_RETRIES=0
}

has()   { printf '%s' "$1" | grep -qF -- "$2"; }

# mkrow <sid> <message_count> <commands_run> <files_changed> [source]
# source defaults to the SessionEnd writer's value; `session-start` is session-index-start's stub.
mkrow() {
  sqlite3 "$SESSION_INDEX_DB" \
    "CREATE TABLE IF NOT EXISTS sessions (session_id TEXT, message_count INT, commands_run TEXT, files_changed TEXT, source TEXT);"
  sqlite3 "$SESSION_INDEX_DB" \
    "INSERT INTO sessions (session_id, message_count, commands_run, files_changed, source) VALUES ('$1', $2, '$3', '$4', '${5:-sessions-index}');"
}

# mktranscript <path> <n-user+assistant-records> — plus non-message records and a truncated
# last line, which the count must skip rather than fail on.
mktranscript() {
  local i
  : > "$1"
  printf '{"type":"ai-title","aiTitle":"t"}\n' >> "$1"
  for ((i = 0; i < $2; i++)); do
    if [ $((i % 2)) -eq 0 ]; then
      printf '{"message":{"content":[{"type":"text","text":"\\"type\\":\\"user\\""}]},"type":"user"}\n' >> "$1"
    else
      printf '{"message":{"content":[]},"type":"assistant"}\n' >> "$1"
    fi
  done
  printf '{"type":"attachment"}\n{"type":"user","mess' >> "$1"
}

# IDL rows the hook wrote, and one field of the last.
idl_n()    { [ -f "$CC_IDL" ] && wc -l <"$CC_IDL" | tr -d ' ' || echo 0; }
idl_last() { tail -1 "$CC_IDL" | jq -r ".$1"; }

fire() { printf '{"session_id":"%s"}' "$1" | bash "$HOOK"; }

# The staged record's field $1, or empty when nothing was staged.
field() { jq -r ".$1 // empty" <"$STAGE"; }

# ── the field collapse ────────────────────────────────────────────────────────

@test "commands_run containing pipes no longer collapses files_changed" {
  # This is the discriminating fixture: the delimiter the old implementation split on
  # appears INSIDE the first column's value, three times.
  cmds="git log --oneline | head -30 && ls | wc -l | cat"
  files="/repo/one.md /repo/two.md"
  mkrow s-pipes 40 "$cmds" "$files"
  run fire s-pipes
  [ "$status" -eq 0 ]
  [ -f "$STAGE" ]
  [ "$(field files_changed)" = "$files" ]
  # And the pipe-bearing column itself must survive intact, not be truncated at its
  # first pipe — the other half of the same defect.
  [ "$(field commands_run)" = "$cmds" ]
}

@test "the staged files_changed is a path list, never a shell fragment" {
  mkrow s-shape 40 "grep -rn x . | sort -u && echo done" "/a/x.md /a/y.md"
  run fire s-shape
  [ "$status" -eq 0 ]
  out="$(field files_changed)"
  # The exact signature of the corruption in the live artifact: a leading space and a
  # shell operator where a path belongs.
  case "$out" in /*) ;; *) return 1 ;; esac
  case "$out" in *" && "*) return 1 ;; esac
}

@test "control: a pipe-FREE row is extracted correctly too" {
  # Proves the fix is per-column extraction and not a pipe-specific patch. This case
  # passes under the OLD implementation as well — that is what makes it a control.
  mkrow s-nopipe 40 "git status" "/only/one.md"
  run fire s-nopipe
  [ "$status" -eq 0 ]
  [ "$(field files_changed)" = "/only/one.md" ]
  [ "$(field commands_run)" = "git status" ]
}

@test "message_count survives as a number, not a string" {
  mkrow s-num 40 "ls | wc -l" "/a.md"
  run fire s-num
  [ "$status" -eq 0 ]
  [ "$(jq -r '.message_count' <"$STAGE")" = "40" ]
  [ "$(jq -r '.message_count | type' <"$STAGE")" = "number" ]
}

# ── the gates still gate ──────────────────────────────────────────────────────

@test "a thin session is not staged" {
  mkrow s-thin 11 "ls | wc -l" "/a.md"
  run fire s-thin
  [ "$status" -eq 0 ]
  [ ! -f "$STAGE" ]
}

@test "a session with no commands is not staged" {
  mkrow s-nocmd 40 "" "/a.md"
  run fire s-nocmd
  [ "$status" -eq 0 ]
  [ ! -f "$STAGE" ]
}

# ── fail-open paths write nothing and never crash ─────────────────────────────

@test "an absent index DB exits clean and stages nothing" {
  run fire s-nodb
  [ "$status" -eq 0 ]
  [ ! -f "$STAGE" ]
}

@test "a session id with no row exits clean — the empty-JSON-array path" {
  # Older sqlite3 builds print the two-byte string '[]' for no rows under -json; 3.43 prints
  # nothing. Either must stage nothing rather than fall through into jq with a null record.
  mkrow s-present 40 "ls | wc -l" "/a.md"
  run fire s-absent
  [ "$status" -eq 0 ]
  [ ! -f "$STAGE" ]
}

@test "a malformed session id is refused before it reaches SQL" {
  mkrow s-ok 40 "ls | wc -l" "/a.md"
  run bash -c "printf '{\"session_id\":\"a/../b; DROP TABLE sessions\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -f "$STAGE" ]
  # the table is still there
  [ "$(sqlite3 "$SESSION_INDEX_DB" 'SELECT COUNT(*) FROM sessions;')" = "1" ]
}

@test "missing session_id and malformed stdin exit 0 silently" {
  run bash -c "printf '{}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "printf 'not json' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ ! -f "$STAGE" ]
}

# ── the artifact stays machine-readable ───────────────────────────────────────

@test "each staged record is one valid JSON line with the expected keys" {
  mkrow s-j1 40 "a | b" "/one.md"
  fire s-j1
  mkrow s-j2 40 "c | d" "/two.md"
  fire s-j2
  [ "$(wc -l <"$STAGE" | tr -d ' ')" = "2" ]
  run jq -e -s 'length == 2 and all(has("ts") and has("session_id") and has("commands_run") and has("files_changed") and has("status"))' "$STAGE"
  [ "$status" -eq 0 ]
}

# ── every exit path writes exactly one IDL row (truememory §3.3) ──────────────
# Before this, the hook's only output was the candidate file, so "every session is thin" and
# "the gate can never open" were the same silence. Each case: one row, the right disposition,
# the right reason, and nothing on stdout (a SessionEnd hook that prints JSON would be a change).

# expect_row <disposition> <reason> — exactly one row, and it says this.
expect_row() {
  [ "$(idl_n)" = "1" ]
  [ "$(idl_last hook)" = "harvest-skill-end" ]
  [ "$(idl_last disposition)" = "$1" ]
  [ "$(idl_last reason)" = "$2" ]
}

@test "row: empty stdin → abstained no-stdin" {
  run bash -c "printf '' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  expect_row abstained no-stdin
}

@test "row: no session id, and non-JSON stdin → abstained no-session-id" {
  run bash -c "printf '{}' | bash '$HOOK'"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  expect_row abstained no-session-id
  rm -f "$CC_IDL"
  run bash -c "printf 'not json' | bash '$HOOK'"
  expect_row abstained no-session-id
}

@test "row: malformed session id → abstained bad-session-id, and the id is not recorded" {
  run bash -c "printf '{\"session_id\":\"a/../b; x\"}' | bash '$HOOK'"
  expect_row abstained bad-session-id
  [ "$(idl_last sid)" = "?" ]
}

@test "row: absent DB → index-db-missing; unreadable DB → index-unreadable; no row → no-index-row" {
  run fire s-nodb
  expect_row abstained index-db-missing
  rm -f "$CC_IDL"; printf 'not a database' > "$SESSION_INDEX_DB"
  run fire s-bad
  expect_row abstained index-unreadable
  rm -f "$CC_IDL" "$SESSION_INDEX_DB"; mkrow s-present 40 "ls" "/a.md"
  run fire s-absent
  expect_row abstained no-index-row
}

@test "row: a stub row (session-index-end not yet written) → index-row-stub, not no-cmds" {
  mktranscript "$BATS_TEST_TMPDIR/t.jsonl" 20
  mkrow s-stub 0 "" "" session-start
  run bash -c "printf '{\"session_id\":\"s-stub\",\"transcript_path\":\"%s\"}' '$BATS_TEST_TMPDIR/t.jsonl' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  expect_row abstained index-row-stub
  [ ! -f "$STAGE" ]
}

@test "row: msgs=0 on the row with no transcript → stale-telemetry (BLIND), never below-gate" {
  mkrow s-stale 0 "ls | wc -l" "/a.md"
  run fire s-stale
  expect_row abstained stale-telemetry
  [ "$(idl_last transcript)" = "no-transcript-path" ]
  rm -f "$CC_IDL"
  run bash -c "printf '{\"session_id\":\"s-stale\",\"transcript_path\":\"/nonexistent/t.jsonl\"}' | bash '$HOOK'"
  expect_row abstained stale-telemetry
  [ "$(idl_last transcript)" = "transcript-missing" ]
}

@test "row: thin session → below-gate; no commands → no-cmds; staged → fired staged" {
  mkrow s-thin 11 "ls" "/a.md"
  run fire s-thin
  expect_row abstained below-gate
  [ "$(idl_last msgs)" = "11" ]
  rm -f "$CC_IDL"; mkrow s-nocmd 40 "" "/a.md"
  run fire s-nocmd
  expect_row abstained no-cmds
  rm -f "$CC_IDL"; mkrow s-go 40 "ls" "/a.md"
  run fire s-go
  [ -z "$output" ]
  expect_row fired staged
  [ -f "$STAGE" ]
}

@test "the transcript count opens the gate the row's message_count=0 kept shut" {
  # The live defect: the row reads 0 in 11,666 of 11,670 SessionEnd lines. 14 user+assistant
  # records in the transcript (the nested `"type":"user"` text and the cut last line must not count).
  mktranscript "$BATS_TEST_TMPDIR/t.jsonl" 14
  mkrow s-tx 0 "git status" "/a.md"
  run bash -c "printf '{\"session_id\":\"s-tx\",\"transcript_path\":\"%s\"}' '$BATS_TEST_TMPDIR/t.jsonl' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  expect_row fired staged
  [ "$(idl_last msgs)" = "14" ]
  [ "$(idl_last msgs_src)" = "transcript" ]
  [ "$(jq -r '.message_count' <"$STAGE")" = "14" ]
}

@test "the transcript count outranks the row: 4 real messages stay below the gate" {
  mktranscript "$BATS_TEST_TMPDIR/t.jsonl" 4
  mkrow s-few 40 "git status" "/a.md"
  run bash -c "printf '{\"session_id\":\"s-few\",\"transcript_path\":\"%s\"}' '$BATS_TEST_TMPDIR/t.jsonl' | bash '$HOOK'"
  expect_row abstained below-gate
  [ "$(idl_last msgs)" = "4" ]
  [ ! -f "$STAGE" ]
}

@test "run through a symlink in a temp dir, the hook still finds its lib and logs (X1)" {
  mkdir -p "$BATS_TEST_TMPDIR/live/hooks"
  ln -s "$HOOK" "$BATS_TEST_TMPDIR/live/hooks/harvest-skill-end.sh"
  mkrow s-link 11 "ls" "/a.md"
  run bash -c "printf '{\"session_id\":\"s-link\"}' | bash '$BATS_TEST_TMPDIR/live/hooks/harvest-skill-end.sh'"
  [ "$status" -eq 0 ]
  expect_row abstained below-gate
}

@test "every BLIND reason this hook emits pages INERT in the alarm; the DORMANT ones do not (X3)" {
  local alarm="$REPO/scripts/idl-abstain-alarm.sh" r i now ts
  now=1752900000
  ts="$(date -u -r "$now" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$now" +%Y-%m-%dT%H:%M:%SZ)"
  for r in no-stdin no-session-id bad-session-id index-db-missing index-unreadable no-index-row index-row-stub stale-telemetry; do
    : > "$CC_IDL"
    for ((i = 0; i < 10; i++)); do
      printf '{"ts":"%s","hook":"harvest-skill-end","disposition":"abstained","reason":"%s"}\n' "$ts" "$r" >> "$CC_IDL"
    done
    run env CC_ABSTAIN_NOW="$now" CC_ABSTAIN_LOG="$BATS_TEST_TMPDIR/a.log" CC_ABSTAIN_CENSUS=0 CC_EXPECTED_FIRES=off "$alarm" --run
    [ "$status" -ne 0 ] || { echo "blind reason $r did not page"; return 1; }
  done
  for r in below-gate no-cmds; do
    : > "$CC_IDL"
    for ((i = 0; i < 10; i++)); do
      printf '{"ts":"%s","hook":"harvest-skill-end","disposition":"abstained","reason":"%s"}\n' "$ts" "$r" >> "$CC_IDL"
    done
    run env CC_ABSTAIN_NOW="$now" CC_ABSTAIN_LOG="$BATS_TEST_TMPDIR/a.log" CC_ABSTAIN_CENSUS=0 CC_EXPECTED_FIRES=off "$alarm" --run
    [ "$status" -eq 0 ] || { echo "dormant reason $r paged"; return 1; }
  done
}
