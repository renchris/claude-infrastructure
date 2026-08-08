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
}

has()   { printf '%s' "$1" | grep -qF -- "$2"; }

# mkrow <sid> <message_count> <commands_run> <files_changed>
mkrow() {
  sqlite3 "$SESSION_INDEX_DB" \
    "CREATE TABLE IF NOT EXISTS sessions (session_id TEXT, message_count INT, commands_run TEXT, files_changed TEXT);"
  sqlite3 "$SESSION_INDEX_DB" \
    "INSERT INTO sessions (session_id, message_count, commands_run, files_changed) VALUES ('$1', $2, '$3', '$4');"
}

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
  # sqlite3 -json returns the two-byte string '[]' for no rows, not the empty string,
  # so a bare -z test would fall through into jq and stage a null record.
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
