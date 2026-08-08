#!/usr/bin/env bats
# session-index-end.sh — the firstPrompt fallback that blanked the field it was meant to fill.
#
# The hook's transcript fallback filtered `select(.type == "human")`. Claude Code transcripts do
# not emit that type: measured 2026-08-08 over the newest live transcripts, 0 `human` records
# against 313 / 224 / 277 `user`. So the jq always produced "" — and the assignment was
# unconditional, sitting under a guard that tested SUMMARY while writing FIRST_PROMPT. Every
# session whose index entry had a real firstPrompt and an empty summary got the firstPrompt
# ERASED on close, silently, into the search index.
#
# The trap this suite exists to hold shut: swapping the type alone does NOT fix it. `.message
# .content` is a block array on the large majority of user records (294/313 in one live
# transcript), and the first `type=="user"` record is usually machinery — a raw first-record read
# over the 4 newest live transcripts returns `[`, `<command-name>/goal</command-name>` and
# `<local-command-caveat>` for 3 of them. That is a NON-EMPTY wrong value: it defeats any
# "only overwrite when non-empty" guard and poisons the index worse than the empty string did.
# Hence §3 below, which a naive type swap fails.
#
# Harness laws: L1 fixtures are real transcript JSONL + a real sessions-index.json in the shape
# `session_index_lookup_sessions_index` actually parses, and the hook is driven end-to-end over
# its real stdin contract into a real SQLite index built by the shipped init functions; L2 every
# assertion is failure-DISTINCT — each of the three defects (wrong type, machinery-first, guard on
# the wrong field) reds a different test, and §3 carries one fixture PER machinery form because
# each leaks a different wrong value; L3 `[ ]` / `grep -q` only, and no `! …` negation — bats
# exempts those from errexit, so they are evaluated and discarded (scripts/bats-assert-liveness.py
# is the arbiter); L4 the preserve rule is asserted in both polarities, so neither "never write"
# nor "always write" can pass.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  PROJ_DIR="$HOME/.claude/projects/-Users-x-proj"
  mkdir -p "$PROJ_DIR" "$HOME/.claude/logs" "$HOME/.claude/state"
  HOOK="$REPO/hooks/session-index-end.sh"
  HELPERS="$REPO/hooks/lib/session-index-helpers.sh"
  # shellcheck disable=SC1090
  source "$HELPERS"
  session_index_init_db
  DB="$HOME/.claude/session-index.db"
}

SID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee

# Drive the hook exactly as Claude Code does: session metadata as JSON on stdin.
run_hook() { # <transcript_path>
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"/Users/x/proj"}' "$SID" "$1" \
    | bash "$HOOK"
}

first_prompt() { sqlite3 "$DB" "SELECT first_prompt FROM sessions WHERE session_id='$SID';"; }

# A sessions-index.json entry — the rich source the hook prefers over the transcript.
mk_index() { # <summary> <firstPrompt>
  jq -n --arg sid "$SID" --arg s "$1" --arg fp "$2" \
    '{entries: [{sessionId: $sid, summary: $s, firstPrompt: $fp, gitBranch: "main",
                 created: "2026-08-01T00:00:00Z", modified: "2026-08-01T01:00:00Z",
                 messageCount: 7}]}' > "$PROJ_DIR/sessions-index.json"
}

# ══ (1) the erasure: a good firstPrompt must survive an empty summary ══════════════════════════

@test "an entry with a real firstPrompt and an EMPTY summary keeps its firstPrompt" {
  # The exact shape the old guard destroyed: `[ -z "$SUMMARY" ]` fired, and the assignment it
  # gated wrote FIRST_PROMPT.
  mk_index "" "wire the capacity alarm to the live launchd plist"
  local t="$PROJ_DIR/$SID.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":"unrelated later transcript text here"}}' > "$t"

  run_hook "$t"
  run first_prompt
  [ "$output" = "wire the capacity alarm to the live launchd plist" ]
}

@test "an entry with BOTH summary and firstPrompt keeps its firstPrompt (the other polarity)" {
  mk_index "a real summary" "the original first prompt as filed"
  local t="$PROJ_DIR/$SID.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":"unrelated later transcript text here"}}' > "$t"

  run_hook "$t"
  run first_prompt
  [ "$output" = "the original first prompt as filed" ]
}

# ══ (2) the fallback actually fires when there IS nothing to lose ══════════════════════════════

@test "with no index entry, a STRING-content user message becomes the firstPrompt" {
  local t="$PROJ_DIR/$SID.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":"rebuild the landing pipeline from scratch"}}' > "$t"

  run_hook "$t"
  run first_prompt
  echo "$output" | grep -q "rebuild the landing pipeline from scratch"
}

@test "with no index entry, an ARRAY-content user message becomes the firstPrompt" {
  # The majority shape on real transcripts — 294 of 313 user records in one live file.
  local t="$PROJ_DIR/$SID.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":[{"type":"text","text":"audit the session index for silently wrong data"}]}}' > "$t"

  run_hook "$t"
  run first_prompt
  echo "$output" | grep -q "audit the session index for silently wrong data"
}

@test "an index entry with an EMPTY firstPrompt is filled from the transcript" {
  mk_index "some summary" ""
  local t="$PROJ_DIR/$SID.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":"the transcript is the only source left"}}' > "$t"

  run_hook "$t"
  run first_prompt
  echo "$output" | grep -q "the transcript is the only source left"
}

# ══ (3) the naive-swap trap: machinery is not the human's first prompt ═════════════════════════

# One fixture per machinery form, because each leaks a DIFFERENT wrong value and a single
# combined fixture only ever convicts on whichever form happens to sit first. Measured against the
# naive swap: a block-array record renders through `jq -r` as pretty-printed JSON whose first line
# is the bare `[`, while a string record leaks its markup verbatim. A test that asserted "the
# output contains no `tool_result`" over an array-first fixture therefore passes vacuously — the
# stored value is `[`, which contains none of the words being denied. Exact equality per fixture is
# both stronger and genuinely failure-distinct: each test names the one form it holds shut.

@test "a tool_result block array before the human message does not become the firstPrompt" {
  local t="$PROJ_DIR/$SID.jsonl"
  {
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"ok"}]}}'
    printf '%s\n' '{"type":"user","message":{"content":"drive the backlog item to a landed state"}}'
  } > "$t"

  run_hook "$t"
  run first_prompt
  # The naive swap stores "[" here — the first line of jq's pretty-printed array.
  [ "$output" = "drive the backlog item to a landed state" ]
}

@test "a slash-command expansion before the human message does not become the firstPrompt" {
  local t="$PROJ_DIR/$SID.jsonl"
  {
    printf '%s\n' '{"type":"user","message":{"content":"<command-name>/goal</command-name>"}}'
    printf '%s\n' '{"type":"user","message":{"content":"drive the backlog item to a landed state"}}'
  } > "$t"

  run_hook "$t"
  run first_prompt
  # The naive swap stores "<command-name>/goal</command-name>" here, verbatim.
  [ "$output" = "drive the backlog item to a landed state" ]
}

@test "a local-command caveat before the human message does not become the firstPrompt" {
  local t="$PROJ_DIR/$SID.jsonl"
  {
    printf '%s\n' '{"type":"user","message":{"content":"<local-command-caveat>Caveat: the messages below were generated while running local commands.</local-command-caveat>"}}'
    printf '%s\n' '{"type":"user","message":{"content":"drive the backlog item to a landed state"}}'
  } > "$t"

  run_hook "$t"
  run first_prompt
  [ "$output" = "drive the backlog item to a landed state" ]
}

# ══ (4) the fallback may only ever ADD a value ═════════════════════════════════════════════════

@test "a transcript with NO substantive user text never blanks an existing firstPrompt" {
  # An all-machinery transcript extracts to "". The old code wrote that "" over good data; the
  # `-n` test is what makes the fallback additive.
  mk_index "" "the value that must not be erased"
  local t="$PROJ_DIR/$SID.jsonl"
  {
    printf '%s\n' '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"tu_1","content":"ok"}]}}'
    printf '%s\n' '{"type":"user","message":{"content":"<command-name>/wrap</command-name>"}}'
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}'
  } > "$t"

  run_hook "$t"
  run first_prompt
  [ "$output" = "the value that must not be erased" ]
}

@test "a MISSING transcript never blanks an existing firstPrompt" {
  mk_index "" "survives a transcript that is not on disk"

  run_hook "$PROJ_DIR/does-not-exist.jsonl"
  run first_prompt
  [ "$output" = "survives a transcript that is not on disk" ]
}

# ══ (5) the hook still completes ═══════════════════════════════════════════════════════════════

@test "the hook exits 0 and indexes the row in every branch above" {
  # `set -euo pipefail` + a trailing `[ test ] && assign` is the idiom the fallback uses; this
  # asserts the fallback's no-write path does not take the hook's exit code with it.
  mk_index "" "a filed prompt"
  local t="$PROJ_DIR/$SID.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":"<command-name>/wrap</command-name>"}}' > "$t"

  run run_hook "$t"
  [ "$status" -eq 0 ]
  run sqlite3 "$DB" "SELECT COUNT(*) FROM sessions WHERE session_id='$SID';"
  [ "$output" = "1" ]
}
