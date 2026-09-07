#!/usr/bin/env bats
# permission-denied — the refusal ledger written by hooks/permission-denied.sh, and the proof that
# it can never speak on stdout (HOOK_SURFACE_100P § 3 row 17, W3-D).
#
# Harness laws followed here:
#   L1  the golden fixture is a LITERAL 2.1.220 `PermissionDenied` payload, transcribed
#       field-for-field from /tmp/hs/log/permdenied.tsv (§ 3a row 17). It is INLINED rather than
#       read from /tmp, because /tmp is ephemeral and a suite whose fixture disappears passes
#       vacuously or dies for the wrong reason.
#       🚨 Of the four captured denials this uses the two whose `tool_input.command` is INERT
#       (`env | cut -d= -f1 …`). The other two carry a credential-probe command, and § 5 of the plan
#       records why that must not be transcribed into a durable artifact: "an inert substitute costs
#       nothing and a stored command outlives its context." The `reason` strings ARE kept verbatim
#       — they are the classifier's own prose and the field this ledger exists to capture.
#   L2  every assertion keys on a failure-DISTINCT value. `reason` and `tool` are asserted at TWO
#       different values from the same handler, so a hardcoded field or a wrong jq path goes red
#       rather than passing on a fixture that happens to match.
#   L3  assertions are `[ ]` / `grep` / `jq -e` — never `[[ ]]`, `(( ))` or a non-last `&&` element,
#       all of which bash 3.2 discards under bats' errexit (tests/bats-assert-liveness.bats).
#   L4  both arms of every fail-open door are fixtured — a handler that wrote a row for a malformed
#       payload and one that wrote nothing for a good one both fail here.
#
# 🚨 THE ARM THAT MATTERS MOST IS "STDOUT IS EMPTY", AND IT IS ASSERTED ON EVERY PATH.
# This event's output schema is `{hookEventName:"PermissionDenied", retry:boolean}` and `retry:true`
# RE-OFFERS THE DENIED CALL. A stray byte here does not degrade a log — it silently re-drives work
# the classifier refused. Because the handler holds that property by having NO writer to stdout
# (rather than by a guard, which would be un-falsifiable dead code — the W3-C lesson), the property
# lives or dies on these assertions, so they are per-path rather than a single spot check.
#
# THE CONTROL IS PROVEN NON-VACUOUS BY MUTATION, not asserted to be. Ten mutants, one per site,
# against an unmutated baseline of 0 red; the sweep and its per-mutant red counts are recorded in
# HOOK_SURFACE_100P § 2 (W3-D).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/permission-denied.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export PERMISSION_DENIED_LOG="$HOME/.claude/logs/permission-denied.jsonl"
  export PERMISSION_DENIED_MAX_BYTES=4194304
  export PERMISSION_DENIED_REASON_CHARS=400
  export PERMISSION_DENIED_INPUT_CHARS=300
  LOG="$PERMISSION_DENIED_LOG"
  OUT="$BATS_TEST_TMPDIR/stdout.txt"
  ERR="$BATS_TEST_TMPDIR/stderr.txt"
  PAY="$BATS_TEST_TMPDIR/payload.json"
}

# The LITERAL captured 2.1.220 payload (permdenied.tsv row 1). No `prompt_id` and no `effort`:
# neither appeared in ANY of the four captures, so do not "complete" this shape.
golden_payload() {
  cat <<'JSON'
{"session_id":"e69c8f22-77ba-439d-9f39-4aa33989b845",
 "transcript_path":"/Users/x/.claude/projects/-private-tmp-hs-permwork/e69c8f22.jsonl",
 "cwd":"/private/tmp/hs/permwork",
 "permission_mode":"auto",
 "hook_event_name":"PermissionDenied",
 "tool_name":"Bash",
 "tool_input":{"command":"env | cut -d= -f1 | sort | head -20","description":"List environment variable names"},
 "tool_use_id":"toolu_01G8rw9FNK9ZZPPYyokq8bMr",
 "reason":"Probing credential storage locations is credential exploration beyond the agent's normal tools."}
JSON
}

# the SECOND captured session, with a different reason and a different tool_use_id — the fixture
# that makes "reason is read, not printed" a claim a mutant can break
golden_payload_2() {
  cat <<'JSON'
{"session_id":"ac228d79-8def-4f5f-9271-55ba8c05b78e",
 "transcript_path":"/Users/x/.claude/projects/-private-tmp-hs-permwork/ac228d79.jsonl",
 "cwd":"/private/tmp/hs/permwork",
 "permission_mode":"auto",
 "hook_event_name":"PermissionDenied",
 "tool_name":"Bash",
 "tool_input":{"command":"env | cut -d= -f1 | sort | head -20","description":"List env var names"},
 "tool_use_id":"toolu_019X3P4iBzZVVDNG8MqqZY1E",
 "reason":"Credential exploration: scanning credential stores beyond the agent's normal tools."}
JSON
}

# always prints an integer: a missing log is ZERO rows, and `grep -c` on a missing file prints
# nothing at all — an empty string reaching `[ -eq ]` is a harness error, not a verdict.
deny_rows() { if [ -f "$LOG" ]; then grep -c '"hook":"permission-denied","sid"' "$LOG" || true; else echo 0; fi; }

# Run the hook with stdout and stderr captured to SEPARATE files. bats' own `run` merges the two
# into $output, which cannot answer the one question this suite exists to answer.
feed() {      printf '%s' "$1" > "$PAY"; run_pay; }
feed_from() { "$@"            > "$PAY"; run_pay; }
run_pay() {
  : > "$OUT"; : > "$ERR"
  run bash -c 'bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
}

# ── the golden payload ──────────────────────────────────────────────────────────────────────────
@test "a real 220 PermissionDenied payload writes exactly ONE ledger row and NOTHING on stdout" {
  feed_from golden_payload
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ -f "$LOG" ]
  [ "$(deny_rows)" -eq 1 ]
  [ "$(wc -l < "$LOG")" -eq 1 ]
}

@test "the row carries the tool, the denial reason, the tool_use_id and the mode" {
  golden_payload > "$PAY"; bash "$HOOK" < "$PAY"
  run jq -e '.tool == "Bash"
             and .tool_use_id == "toolu_01G8rw9FNK9ZZPPYyokq8bMr"
             and .mode == "auto"
             and .sid == "e69c8f22-77ba-439d-9f39-4aa33989b845"
             and (.reason | test("credential exploration"))' "$LOG"
  [ "$status" -eq 0 ]
}

# ── THE CONTROLS THAT CAN FAIL ──────────────────────────────────────────────────────────────────
# `reason` is the ONLY field that says why the call was refused, so a handler that hardcodes it, or
# reads the wrong path and lets the `// "-"` default win, must go red. Two captured denials with
# DIFFERENT reasons from the same handler is what makes that possible.
@test "the reason is READ from the payload — two real denials give two different reasons" {
  golden_payload   > "$PAY"; bash "$HOOK" < "$PAY"
  [ "$(jq -r '.reason' "$LOG")" != "-" ]
  A="$(jq -r '.reason' "$LOG")"
  : > "$LOG"
  golden_payload_2 > "$PAY"; bash "$HOOK" < "$PAY"
  B="$(jq -r '.reason' "$LOG")"
  [ "$B" != "-" ]
  [ "$A" != "$B" ]
}

@test "the tool name is the REAL one, never a placeholder — Bash and Write differ" {
  feed '{"hook_event_name":"PermissionDenied","session_id":"s","tool_name":"Write","tool_input":{"file_path":"/tmp/x"},"tool_use_id":"t1","reason":"r"}'
  [ "$(jq -r '.tool' "$LOG")" = "Write" ]
  : > "$LOG"
  feed '{"hook_event_name":"PermissionDenied","session_id":"s","tool_name":"Bash","tool_input":{"command":"true"},"tool_use_id":"t2","reason":"r"}'
  [ "$(jq -r '.tool' "$LOG")" = "Bash" ]
}

# `tool_input` is the REFUSED call's arguments — for Write that is a whole file body. The ledger
# must record enough to identify it and never enough to replay it.
@test "a huge tool_input is DIGESTED, not copied — length kept, body truncated" {
  BIG="$(printf 'a%.0s' $(seq 1 4000))SENTINEL-DEEP-IN-THE-BODY$(printf 'b%.0s' $(seq 1 4000))"
  jq -cn --arg c "$BIG" '{hook_event_name:"PermissionDenied",session_id:"s",tool_name:"Write",
                          tool_input:{file_path:"/tmp/x",content:$c},tool_use_id:"t",reason:"r"}' > "$PAY"
  run_pay
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(jq -r '.input_chars' "$LOG")" -gt 8000 ]
  [ "$(printf '%s' "$(jq -r '.input_head' "$LOG")" | wc -c)" -le 300 ]
  run grep -c 'SENTINEL-DEEP-IN-THE-BODY' "$LOG"
  [ "$status" -ne 0 ]
  [ "$(wc -c < "$LOG")" -lt 1200 ]
}

# ── the event gate: a mis-registration must be INERT, not WRONG ──────────────────────────────────
# 🚨 This is the load-bearing inertness arm, and unlike its PostToolBatch sibling it cannot be
# covered by a shape gate: a `PreToolUse` payload carries `tool_name`, `tool_input` AND
# `tool_use_id`, so it is field-for-field indistinguishable from a denial except by the event name.
# Without this gate, this handler pointed at PreToolUse would record every tool call in the fleet as
# a refusal — a ledger that is not merely noisy but says the opposite of the truth.
@test "a PreToolUse payload is refused — the event name is the only thing that separates them" {
  feed '{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"echo x"},"tool_use_id":"t","permission_mode":"auto"}'
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(deny_rows)" -eq 0 ]
}

@test "a PostToolUse payload is refused too" {
  feed '{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"echo x"},"tool_response":{"stdout":"x"}}'
  [ "$status" -eq 0 ]
  [ "$(deny_rows)" -eq 0 ]
}

# ── fail-open doors ─────────────────────────────────────────────────────────────────────────────
@test "empty stdin exits 0, writes nothing at all, and says nothing" {
  feed ''
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ ! -f "$LOG" ]
}

@test "malformed JSON exits 0, writes NO ledger row, and leaves an abstain marker" {
  feed 'not json {{{'
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(deny_rows)" -eq 0 ]
  grep -q '"abstain":"malformed-json"' "$LOG"
}

@test "no jq on PATH exits 0 and abstains rather than writing a bogus row" {
  golden_payload > "$PAY"
  : > "$OUT"; : > "$ERR"
  run bash -c 'PATH=/bin bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ "$(deny_rows)" -eq 0 ]
  grep -q '"abstain":"no-jq"' "$LOG"
}

@test "the kill switch makes it wholly inert — no row, no marker, no output" {
  golden_payload > "$PAY"
  : > "$OUT"; : > "$ERR"
  run bash -c 'CC_PERMISSION_DENIED_DISABLED=1 bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
  [ "$status" -eq 0 ]
  [ ! -s "$OUT" ]
  [ ! -f "$LOG" ]
}

# ── the adoption constraint, asserted across every path in one place ────────────────────────────
# 🚨 `retry:true` on this event's stdout RE-OFFERS the denied call. Each payload class below goes
# through the handler and every one must produce ZERO bytes of stdout. An `echo` inserted anywhere
# in the subject reddens this test whichever path it sits on.
@test "stdout is EMPTY on every payload class — a byte here re-drives a refused call" {
  for p in \
    '{"hook_event_name":"PermissionDenied","session_id":"s","tool_name":"Bash","tool_input":{"command":"true"},"tool_use_id":"t","reason":"r"}' \
    '{"hook_event_name":"PreToolUse","session_id":"s","tool_name":"Bash","tool_input":{}}' \
    '{"hook_event_name":"PermissionDenied"}' \
    'not json {{{' \
    '' ; do
    printf '%s' "$p" > "$PAY"
    : > "$OUT"; : > "$ERR"
    run bash -c 'bash "$1" < "$2" > "$3" 2> "$4"' _ "$HOOK" "$PAY" "$OUT" "$ERR"
    [ "$status" -eq 0 ]
    [ ! -s "$OUT" ]
  done
}

# ── the ledger is BOUNDED (HOOK_CHAIN_COST R-5: do not mint a second unbounded log) ─────────────
@test "the ledger rotates at its cap instead of growing without limit" {
  export PERMISSION_DENIED_MAX_BYTES=200
  golden_payload > "$PAY"; bash "$HOOK" < "$PAY"
  [ ! -f "$LOG.1" ]                      # under the cap: no rotation yet
  golden_payload > "$PAY"; bash "$HOOK" < "$PAY"
  [ -f "$LOG.1" ]                        # the first row pushed it over, so the next append rotated
  [ "$(deny_rows)" -eq 1 ]
}

@test "the handler is executable and is a bash script" {
  [ -x "$HOOK" ]
  head -1 "$HOOK" | grep -q '^#!/bin/bash'
}

# The registration half is a SEPARATE c10 migration (§ 4). This suite must fail if a future session
# wires the event from inside this wave's deliverable, because a malformed entry in a live settings
# file silently disables every hook registered there with zero log output.
@test "this wave registers NOTHING — the handler name appears in no settings file in the repo" {
  run grep -rl 'permission-denied\.sh' "$REPO/settings-templates" "$REPO/.claude"
  [ "$status" -ne 0 ]
}
