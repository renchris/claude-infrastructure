#!/usr/bin/env bats
# instructions-loaded — the InstructionsLoaded observer (HOOK_SURFACE_100P § 3 row 27, W3-B).
#
# Harness laws, same as tests/file-changed.bats: L1 fixtures are the LITERAL 2.1.220/2.1.114 shape
# (transcribed from the 16 captured rows in /tmp/hs/log/{census,census114,display-run*}.tsv, so the
# suite does not depend on a /tmp tree a reboot wipes); L2 assertions key on failure-DISTINCT
# strings; L3 `[ ]` / `grep -q` only, never `[[ ]]` or `(( ))` (bats-assert-liveness); L4 the
# not-firing cases are fixtured too.
#
# 🚨 `run` NEVER ON THE RIGHT OF A PIPE. bats runs a pipeline's last element in a subshell, so
# `$status` and `$output` come back empty and every assertion on them passes vacuously. Payloads
# reach the hook by REDIRECTION from a file. This was a real defect in the sibling suite's first
# draft, green-looking and meaningless.
#
# ══ WHAT THIS SUITE IS ACTUALLY DEFENDING ══════════════════════════════════════════════════════
#
# Two things, and neither is the happy path:
#
#  1. THE FIELD-SHIFT. `load_reason` and `memory_type` are always present; `file_path` is the field
#     that identifies the row. The first draft of BOTH handlers extracted with `@tsv` + `read`, and
#     a tab is an IFS whitespace character — so `read` strips a LEADING empty field and shifts every
#     later field left. A payload missing `file_path` then logged a row naming a file called "User"
#     (this event) or "change" (the sibling). Measured, not theorised: it is why both scripts use
#     `@sh` + `eval`. The no-file_path arm below is the only thing that sees it.
#
#  2. THE MATCHER'S POPULATION. This event's matcher is the `load_reason`, not a tool name, so it
#     decides WHICH loads are observed. A handler that dropped `load_reason` from its row would make
#     every log line un-attributable to the registration that produced it, and a second registration
#     on another value would silently contaminate the first. The row must carry it.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/instructions-loaded.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  LOG="$HOME/.claude/logs/instructions-loaded.log"
  PAYLOAD="$BATS_TEST_TMPDIR/payload.json"
}

# The literal session_start payload, transcribed from /tmp/hs/log/census.tsv. Note what is ABSENT:
# there is no `prompt_id` — at session_start no prompt exists yet — so nothing may key on it.
il_payload() { # <file_path> <memory_type> <load_reason>
  jq -nc --arg f "$1" --arg m "$2" --arg r "$3" \
    '{session_id:"0748cd7b-9971-4fa6-8f2f-ec0f29fccdde",
      transcript_path:"/tmp/t.jsonl",cwd:"/private/tmp/hs/scratch",
      hook_event_name:"InstructionsLoaded",file_path:$f,memory_type:$m,load_reason:$r}' > "$PAYLOAD"
}

# ── the row carries the fields that make it interpretable ──────────────────────────────────────

@test "a real session_start payload records the file, its memory_type and its load_reason" {
  il_payload /Users/chrisren/.claude-quaternary/CLAUDE.md User session_start
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -f "$LOG" ]
  grep -q "/Users/chrisren/.claude-quaternary/CLAUDE.md" "$LOG"
  grep -q "session_start" "$LOG"
  grep -q "User" "$LOG"
}

@test "the load_reason is recorded, so a row stays attributable to the matcher that produced it" {
  # The matcher IS the load_reason. Drop it from the row and no later reader can tell which
  # registration wrote the line, which is what makes a second registration contaminate the first.
  il_payload /x/CLAUDE.md Project compact
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  grep -q "compact" "$LOG"
}

@test "all four memory_type values round-trip, including the two the probe never saw" {
  # Only User and Project were observed in the 16 measured rows; the binary documents Local and
  # Managed too. A handler that only handled the observed pair would mislabel the other two.
  for MT in User Project Local Managed; do
    il_payload "/x/$MT.md" "$MT" session_start
    run "$HOOK" < "$PAYLOAD"
    [ "$status" -eq 0 ]
  done
  grep -q "Local" "$LOG"
  grep -q "Managed" "$LOG"
  [ "$(wc -l < "$LOG")" -eq 4 ]
}

@test "all five load_reason values the binary declares round-trip" {
  # Read off the binary's own matcherMetadata literal:
  #   values:["session_start","nested_traversal","path_glob_match","include","compact"]
  # NOT the three the plan's § 3 note claims (at_mention / skill_load / slash_command), which do
  # not appear in that metadata at all. If a future binary renames one, this arm still passes —
  # it pins the handler's transparency, not the binary's list. The list itself is pinned in § 2.
  for LR in session_start nested_traversal path_glob_match include compact; do
    il_payload "/x/$LR.md" User "$LR"
    run "$HOOK" < "$PAYLOAD"
    [ "$status" -eq 0 ]
  done
  grep -q "path_glob_match" "$LOG"
  grep -q "nested_traversal" "$LOG"
  [ "$(wc -l < "$LOG")" -eq 5 ]
}

@test "the optional trigger_file_path and parent_file_path are recorded when present" {
  # These arrive only on the load_reasons the W1 probe never exercised (path_glob_match / include),
  # so nothing measured carries them — they come from the binary's own field list. Recording them
  # is what makes a later path_glob_match registration interpretable without a code change.
  jq -nc '{session_id:"s",hook_event_name:"InstructionsLoaded",
           file_path:"/x/rule.md",memory_type:"Project",load_reason:"path_glob_match",
           trigger_file_path:"/repo/src/app.ts",parent_file_path:"/repo/CLAUDE.md"}' > "$PAYLOAD"
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  grep -q "/repo/src/app.ts" "$LOG"
  grep -q "/repo/CLAUDE.md" "$LOG"
}

@test "an absent optional becomes a placeholder, never an empty column" {
  # An empty TSV column shifts every later field left on read. The placeholder is what keeps a
  # session_start row (no trigger, no parent) readable by the same parser as a path_glob_match row.
  il_payload /x/plain.md User session_start
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  # 7 fields: ts, sid, load_reason, memory_type, file_path, trigger, parent
  [ "$(awk -F'\t' '{print NF}' "$LOG")" -eq 7 ]
}

@test "each invocation appends exactly one row" {
  il_payload /x/one.md User session_start
  run "$HOOK" < "$PAYLOAD"
  il_payload /x/two.md Project session_start
  run "$HOOK" < "$PAYLOAD"
  [ "$(wc -l < "$LOG")" -eq 2 ]
}

@test "a path containing a space and a quote survives extraction intact" {
  # `@sh` + `eval` is the extraction route; this is the arm that proves the quoting is real rather
  # than an accident of well-behaved fixtures.
  il_payload "/x/we ird's dir/CLAUDE.md" User session_start
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  grep -q "we ird's dir/CLAUDE.md" "$LOG"
  [ "$(wc -l < "$LOG")" -eq 1 ]
}

# ── the field-shift regression, and fail-open ──────────────────────────────────────────────────

@test "a payload with no file_path writes NO row — it must not log memory_type as the filename" {
  # THE REGRESSION ARM. With `@tsv` + `read` this wrote a row whose file_path column read "User".
  jq -nc '{session_id:"s",hook_event_name:"InstructionsLoaded",
           memory_type:"User",load_reason:"session_start"}' > "$PAYLOAD"
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ]
}

@test "malformed JSON on stdin exits 0 and writes no row" {
  echo 'not json {{{' > "$PAYLOAD"
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ]
}

@test "empty stdin exits 0" {
  printf '' > "$PAYLOAD"
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
}

@test "no stdin at all exits 0" {
  run "$HOOK" < /dev/null
  [ "$status" -eq 0 ]
}

@test "an unexpected argument does not make a fail-open hook fail closed" {
  # This event is observability-only per the binary ("does not support blocking"), so there is no
  # argument that may ever produce a nonzero exit.
  il_payload /x/arg.md User session_start
  run "$HOOK" --unexpected < "$PAYLOAD"
  [ "$status" -eq 0 ]
}

@test "an unwritable log directory does not fail the hook" {
  mkdir -p "$HOME/.claude"
  : > "$HOME/.claude/logs"        # a FILE where the log dir must go — mkdir -p will fail
  il_payload /x/unwritable.md User session_start
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
}

@test "the observer never writes to stdout — this event cannot block and must return nothing" {
  il_payload /x/silent.md User session_start
  run "$HOOK" < "$PAYLOAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
