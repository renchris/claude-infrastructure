#!/usr/bin/env bats
# post-compact — the compaction ledger written by hooks/post-compact.sh, and the proof that a
# ~21.8 KB `compact_summary` never reaches the log (HOOK_SURFACE_100P § 3 row 15, W3-D).
#
# Harness laws followed here:
#   L1  the golden fixture reproduces the LITERAL 2.1.220 `PostCompact` payload from
#       /tmp/hs/log/session.tsv (§ 3a rows 14,15) field-for-field, with the 21,834-character
#       `compact_summary` REGENERATED to that exact length rather than transcribed. Two reasons,
#       both deliberate: a 21 KB verbatim conversation summary in a test file is the same
#       copy-the-body defect the subject exists to prevent, and the property under test is the
#       LENGTH and the digest, which a synthesised body of the measured length exercises exactly.
#       The measured lengths themselves — 21,834 on 2.1.220 and 5,989 on 2.1.114 — are pinned below
#       as literals, so the fixture cannot drift away from what was actually captured.
#   L2  every assertion keys on a failure-DISTINCT value. `trigger` is asserted at BOTH schema
#       values from the same handler, and the digest is asserted to differ between two summaries of
#       IDENTICAL length whose first 160 characters are also identical — the one shape that a
#       head-only or constant digest cannot survive.
#   L3  assertions are `[ ]` / `grep` / `jq -e` — never `[[ ]]`, `(( ))` or a non-last `&&` element
#       (bash 3.2 discards those under bats' errexit; tests/bats-assert-liveness.bats).
#   L4  both arms of every fail-open door are fixtured.
#
# WHAT THIS SUITE DOES NOT CLAIM. It cannot show that `trigger:"auto"` is ever EMITTED — both
# captures read `manual`, and CONTEXT_ECONOMY_V2's corpus pass reports 39/39 manual and 0 auto. The
# `auto` arm below fixtures the SCHEMA value, so a handler that hardcodes `"manual"` (which every
# observation to date would let pass) goes red. Whether the harness emits it is a question for the
# log this handler writes, which is the point of writing it.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/post-compact.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export POST_COMPACT_LOG="$HOME/.claude/logs/post-compact.jsonl"
  export POST_COMPACT_MAX_BYTES=1048576
  export POST_COMPACT_HEAD_CHARS=160
  LOG="$POST_COMPACT_LOG"
  OUT="$BATS_TEST_TMPDIR/stdout.txt"
  ERR="$BATS_TEST_TMPDIR/stderr.txt"
  PAY="$BATS_TEST_TMPDIR/payload.json"
}

# the two measured `compact_summary` lengths, pinned as literals (session.tsv / session114.tsv)
MEASURED_220_CHARS=21834
MEASURED_114_CHARS=5989

# a body of exactly <n> characters that begins with the real capture's opening text
summary_of() { # <n>
  local head='<analysis>
Let me work through this conversation carefully.

**Message 1 (system/user task brief):** This is a dispatched-peer session brief from a "desk" orchestrator. '
  local body
  body="$head$(printf 'x%.0s' $(seq 1 "$1"))"
  printf '%s' "${body:0:$1}"
}

# The captured 2.1.220 shape. `prompt_id` is present here and ABSENT in the 114 capture, so it is
# fixtured on one arm only and nothing keys on it.
golden_payload() { # [trigger] [chars]
  jq -cn --arg s "$(summary_of "${2:-$MEASURED_220_CHARS}")" --arg t "${1:-manual}" \
    '{session_id:"22222222-3333-4444-8555-666666666666",
      transcript_path:"/Users/x/.claude/projects/-Users-x-Development-wt-ptuf2/22222222.jsonl",
      cwd:"/Users/x/Development/wt-ptuf2",
      prompt_id:"614d69bd-a4f0-4098-a02d-f43c715dba06",
      hook_event_name:"PostCompact", trigger:$t, compact_summary:$s}'
}

compact_rows() { if [ -f "$LOG" ]; then grep -c '"hook":"post-compact","sid"' "$LOG" || true; else echo 0; fi; }

feed() {      printf '%s' "$1" > "$PAY"; run_pay; }
feed_from() { "$@"            > "$PAY"; run_pay; }
run_pay() {
  : > "$OUT"; : > "$ERR"
  run bash -c 'bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
}

# ── the golden payload ──────────────────────────────────────────────────────────────────────────
@test "a real 220 PostCompact payload writes exactly ONE row and nothing on stdout" {
  feed_from golden_payload
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(compact_rows)" -eq 1 ]
  [ "$(wc -l < "$LOG")" -eq 1 ]
}

@test "the row carries trigger, the session and the measured summary length" {
  golden_payload > "$PAY"; bash "$HOOK" < "$PAY"
  run jq -e --argjson n "$MEASURED_220_CHARS" \
    '.trigger == "manual" and .summary_chars == $n
     and .sid == "22222222-3333-4444-8555-666666666666"' "$LOG"
  [ "$status" -eq 0 ]
}

# ── THE CONSTRAINT: a 21.8 KB summary must never reach the log ──────────────────────────────────
# The whole justification for a digest is that the body is large and is not ours to copy. A handler
# that stored `compact_summary` whole would write a >21 KB line here and would carry the sentinel
# planted deep inside it.
@test "the 21,834-character summary is DIGESTED — the row stays small and drops the body" {
  # the sentinel sits 9,000 characters in — past the head and far from either end, so only a
  # handler that copied the BODY could carry it into the log
  BODY="$(summary_of 9000)SENTINEL-DEEP-IN-THE-SUMMARY$(summary_of 12806)"
  jq -cn --arg s "$BODY" \
    '{hook_event_name:"PostCompact",session_id:"s",trigger:"manual",compact_summary:$s}' > "$PAY"
  run_pay
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(jq -r '.summary_chars' "$LOG")" -eq "$MEASURED_220_CHARS" ]
  run grep -c 'SENTINEL-DEEP-IN-THE-SUMMARY' "$LOG"
  [ "$status" -ne 0 ]
  [ "$(wc -c < "$LOG")" -lt 1000 ]
  [ "$(printf '%s' "$(jq -r '.summary_head' "$LOG")" | wc -c)" -le 200 ]
}

@test "summary_chars is the FULL length even though the body is not kept" {
  jq -cn --arg s "$(summary_of "$MEASURED_114_CHARS")" \
    '{hook_event_name:"PostCompact",session_id:"s",trigger:"manual",compact_summary:$s}' > "$PAY"
  run_pay
  [ "$status" -eq 0 ]
  [ "$(jq -r '.summary_chars' "$LOG")" -eq "$MEASURED_114_CHARS" ]
}

# ── THE CONTROLS THAT CAN FAIL ──────────────────────────────────────────────────────────────────
# The digest is what makes two compactions distinguishable once the body is gone. These two
# summaries have the SAME length and the SAME first 160 characters, so a digest computed over the
# head, or a constant, or the length, cannot tell them apart — and must go red.
@test "the digest is over the WHOLE summary — same length and same head, different sha" {
  jq -cn --arg s "$(summary_of 4000)AAAA" '{hook_event_name:"PostCompact",session_id:"s",trigger:"manual",compact_summary:$s}' > "$PAY"
  run_pay
  A="$(jq -r '.summary_sha' "$LOG")"
  : > "$LOG"
  jq -cn --arg s "$(summary_of 4000)BBBB" '{hook_event_name:"PostCompact",session_id:"s",trigger:"manual",compact_summary:$s}' > "$PAY"
  run_pay
  B="$(jq -r '.summary_sha' "$LOG")"
  [ "$A" != "-" ]
  [ "$B" != "-" ]
  [ "$A" != "$B" ]
}

# and the digest is the REAL sha256 of the field, computed here by a different route
@test "the recorded sha matches an independently computed sha256 of the summary" {
  S="$(summary_of 2000)"
  EXPECT="$(printf '%s' "$S" | shasum -a 256 | cut -c1-16)"
  jq -cn --arg s "$S" '{hook_event_name:"PostCompact",session_id:"s",trigger:"auto",compact_summary:$s}' > "$PAY"
  run_pay
  [ "$(jq -r '.summary_sha' "$LOG")" = "$EXPECT" ]
}

# `trigger` is the field this hook is adopted FOR. A handler that prints the value every observation
# to date carries — `manual` — would pass every real capture and answer the question wrongly the
# first time an `auto` compaction happens.
@test "trigger is READ, not assumed — manual and auto both survive to the row" {
  golden_payload manual 300 > "$PAY"; run_pay
  [ "$(jq -r '.trigger' "$LOG")" = "manual" ]
  : > "$LOG"
  golden_payload auto 300 > "$PAY"; run_pay
  [ "$(jq -r '.trigger' "$LOG")" = "auto" ]
}

@test "a payload with no trigger records a dash, never a fabricated manual" {
  feed '{"hook_event_name":"PostCompact","session_id":"s","compact_summary":"short"}'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.trigger' "$LOG")" = "-" ]
}

# ── the event gate: a mis-registration must be INERT ─────────────────────────────────────────────
# `PreCompact` is the near neighbour — it fires seconds earlier on the same action, is already wired
# fleet-wide, and carries a `trigger` of its own. A handler that did not gate on the event name
# would double-count every compaction while looking perfectly healthy.
@test "a PreCompact payload is refused — the event name gates the ledger" {
  feed '{"hook_event_name":"PreCompact","session_id":"s","trigger":"manual","custom_instructions":""}'
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(compact_rows)" -eq 0 ]
}

@test "a SessionStart source=compact payload is refused too" {
  feed '{"hook_event_name":"SessionStart","session_id":"s","source":"compact"}'
  [ "$status" -eq 0 ]
  [ "$(compact_rows)" -eq 0 ]
}

# ── fail-open doors ─────────────────────────────────────────────────────────────────────────────
@test "empty stdin exits 0 and writes nothing at all" {
  feed ''
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ ! -f "$LOG" ]
}

@test "malformed JSON exits 0, writes NO row, and leaves an abstain marker" {
  feed 'not json {{{'
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(compact_rows)" -eq 0 ]
  grep -q '"abstain":"malformed-json"' "$LOG"
}

@test "no jq on PATH exits 0 and abstains rather than writing a bogus row" {
  golden_payload manual 300 > "$PAY"
  : > "$OUT"; : > "$ERR"
  run bash -c 'PATH=/bin bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(compact_rows)" -eq 0 ]
  grep -q '"abstain":"no-jq"' "$LOG"
}

@test "the kill switch makes it wholly inert — no row, no marker, no output" {
  golden_payload manual 300 > "$PAY"
  : > "$OUT"; : > "$ERR"
  run bash -c 'CC_POST_COMPACT_DISABLED=1 bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ ! -f "$LOG" ]
}

@test "stdout is EMPTY on every payload class" {
  for p in \
    '{"hook_event_name":"PostCompact","session_id":"s","trigger":"manual","compact_summary":"x"}' \
    '{"hook_event_name":"PreCompact","session_id":"s","trigger":"manual"}' \
    '{"hook_event_name":"PostCompact"}' \
    'not json {{{' \
    '' ; do
    printf '%s' "$p" > "$PAY"
    : > "$OUT"; : > "$ERR"
    run bash -c 'bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
    [ "$status" -eq 0 ]
    [ ! -s "$OUT" ]
  done
}

@test "a summary carrying a quote, a backslash and a newline still yields ONE valid JSON line" {
  printf '%s' '{"hook_event_name":"PostCompact","session_id":"s","trigger":"manual","compact_summary":"he said \"hi\\\\there\\nsecond line\""}' > "$PAY"
  run_pay
  [ "$(wc -l < "$LOG")" -eq 1 ]
  run jq -e '.trigger == "manual"' "$LOG"
  [ "$status" -eq 0 ]
}

# ── the ledger is BOUNDED ───────────────────────────────────────────────────────────────────────
@test "the ledger rotates at its cap instead of growing without limit" {
  export POST_COMPACT_MAX_BYTES=200
  golden_payload manual 300 > "$PAY"; bash "$HOOK" < "$PAY"
  [ ! -f "$LOG.1" ]
  golden_payload manual 300 > "$PAY"; bash "$HOOK" < "$PAY"
  [ -f "$LOG.1" ]
  [ "$(compact_rows)" -eq 1 ]
}

@test "the handler is executable and is a bash script" {
  [ -x "$HOOK" ]
  head -1 "$HOOK" | grep -q '^#!/bin/bash'
}

@test "this wave registers NOTHING — the handler name appears in no settings file in the repo" {
  run grep -rl 'post-compact\.sh' "$REPO/settings-templates" "$REPO/.claude"
  [ "$status" -ne 0 ]
}
