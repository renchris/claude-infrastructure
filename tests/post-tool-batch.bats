#!/usr/bin/env bats
# post-tool-batch — the all-tool-call census written by hooks/post-tool-batch.sh, and the proof that
# it is INERT on the binary that does not have the event (HOOK_SURFACE_100P § 3 row 4, W3-C).
#
# Harness laws followed here:
#   L1  the golden fixture is the LITERAL 2.1.220 PostToolBatch payload, transcribed field-for-field
#       from the capture in /tmp/hs/log/batch.tsv (HOOK_SURFACE_100P § 3a row 4 — three parallel
#       Bash calls: alpha/beta/gamma). It is INLINED rather than read from /tmp because /tmp is
#       ephemeral; a suite whose fixture disappears passes vacuously or dies for the wrong reason.
#   L2  every assertion keys on a failure-DISTINCT value. The census's whole point is the batch SIZE
#       and the tool MIX, so `n` is asserted at two different values from the same handler and the
#       tool names are asserted as their real names — a handler that hardcodes n, that emits one row
#       per call, or that reads a top-level `.tool_name` (which this payload does not have, so the
#       `// "?"` default would win) goes RED. See "the control that can fail" below.
#   L3  assertions are `[ ]` / `grep` / `jq -e`.
#   L4  both arms of every fail-open door are fixtured — a handler that wrote a row for a malformed
#       payload and one that wrote nothing for a good one both fail here.
#
# THE CONTROL IS PROVEN NON-VACUOUS BY MUTATION, not asserted to be. Nine mutants were applied to
# hooks/post-tool-batch.sh, one per site, against an unmutated baseline of 0 red, and every one
# reddened at least one test here:
#   n hardcoded to 1 → 3 red · tool-name read off the wrong path → 3 red · event-name gate deleted
#   → 1 red · rotation deleted → 1 red · shape gate deleted → 1 red · malformed-JSON abstain deleted
#   → 1 red · exit 1 on empty stdin → 13 red · no-jq abstain deleted → 1 red · the row emitted as
#   raw text instead of jq-encoded → 7 red.
# Re-run after the suite moved from `$?` to bats' `run`/`$status`, with the two binary paths pointed
# at absent files so the 450 MB grep arm SKIPS — no mutant touches it, and the 0-red baseline under
# the same skip is what shows the skip does not manufacture the greens.
# Two of those mutants came back GREEN on the first attempt and both were real findings rather than
# test bugs: the event-name gate had no arm that exercised it (a real PostToolUse payload has no
# `tool_calls`, so the SHAPE gate refused it first — hence the separate synthetic arm below), and a
# `type == "array"` guard turned out to be unfalsifiable dead code and was deleted from the subject.
#
# THE 114 ARM IS MEASURED, NOT ASSUMED. `PostToolBatch` is absent from 2.1.114's enum, so the
# harness there never dispatches it and a registration is a silent no-op (unknown event names are
# accepted with no error, no warning, no log line — HOOK_SURFACE_100P § 5). That claim is checked
# against the two INSTALLED binaries with a positive control on the same instrument: the identical
# grep must FIND the name in 2.1.220. Without that control an absence proves only that the pattern
# was wrong. Two further binary-independent arms cover the operational hazard — pointed at an event
# 114 DOES dispatch, the handler must write nothing rather than mint an n=1 row per call — and they
# are separate on purpose, because the two gates that produce that inertness are independent and one
# fixture only ever exercises one of them.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/post-tool-batch.sh"
  # the installed binaries live under the REAL home; capture it before fixturing HOME
  REAL_HOME="$HOME"
  BIN114="${CC_BIN_114:-$REAL_HOME/.claude-versions/2.1.114/node_modules/@anthropic-ai/claude-code/bin/claude.exe}"
  BIN220="${CC_BIN_220:-$REAL_HOME/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe}"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export POST_TOOL_BATCH_LOG="$HOME/.claude/logs/tool-batch-census.jsonl"
  export POST_TOOL_BATCH_MAX_BYTES=4194304
  LOG="$POST_TOOL_BATCH_LOG"
}

# The LITERAL captured 2.1.220 payload. `tool_response` is a bare string here, which is what the
# harness actually sent; do not "correct" it to the PostToolUse object shape.
golden_payload() {
  cat <<'JSON'
{"session_id":"7738f61b-b906-47da-ab94-9104a7aaf2db",
 "transcript_path":"/Users/x/.claude/projects/-private-tmp-hs-scratch/7738f61b.jsonl",
 "cwd":"/private/tmp/hs/scratch",
 "prompt_id":"7980057e-bccd-481d-8759-6efae3c167da",
 "permission_mode":"auto","effort":{"level":"low"},
 "hook_event_name":"PostToolBatch",
 "tool_calls":[
  {"tool_name":"Bash","tool_input":{"command":"echo alpha","description":"Echo alpha"},
   "tool_use_id":"toolu_01TMEuKZjmi5DNZouPGyEzPu","tool_response":"alpha"},
  {"tool_name":"Bash","tool_input":{"command":"echo beta","description":"Echo beta"},
   "tool_use_id":"toolu_01YP6M8E7iBcZbb7Z26zFDwh","tool_response":"beta"},
  {"tool_name":"Bash","tool_input":{"command":"echo gamma","description":"Echo gamma"},
   "tool_use_id":"toolu_01UKWHLvepcmjbH5ixoyKHGS","tool_response":"gamma"}]}
JSON
}

# same shape, N and the tool mix varied — the census's two load-bearing fields
#
# 🚨 THE SUBSTITUTION IS BOUND TO A VARIABLE FIRST, AND THAT IS NOT STYLE. This helper used to
# inline `"$(printf … | sed …)"` directly as printf's argument, and bash 3.2 — which is what
# /bin/bash IS on macOS, and what bats runs when /bin wins the PATH — mis-parses the double quotes
# NESTED inside a double-quoted command substitution. The substitution then reached printf as THREE
# words instead of one, printf reused its format once per word, and the helper emitted three
# separate JSON documents each holding one transposed field:
#     …"tool_calls":["tool_name":"Bash","tool_name":"Bash","tool_name":"Bash"]}{…"tool_input":{}…
# The hook did exactly the right thing with that — abstained `malformed-json` — so the census was
# empty and `jq -r '.n'` read `null`, failing as `[: null: integer expression expected`, i.e. as a
# harness error rather than as a wrong value. Under bash 5 the identical file is GREEN, so this
# suite's verdict depended on which bash won the PATH, which is the one thing a test may not do.
# Binding to a local first is enough: measured, 3.2 yields the correct single-word value that way.
batch_payload() { # <tool_name>...
  local names="" calls
  for t in "$@"; do names="$names\"$t\","; done
  calls="$(printf '%s' "${names%,}" | sed 's/"\([^"]*\)"/{"tool_name":"\1","tool_input":{},"tool_response":"r"}/g')"
  printf '{"session_id":"sid-mix","prompt_id":"pid-mix","permission_mode":"acceptEdits",
           "effort":{"level":"high"},"hook_event_name":"PostToolBatch","tool_calls":[%s]}' "$calls"
}

# always prints an integer: a missing log is ZERO rows, and `grep -c` on a missing file prints
# nothing at all — an empty string reaching `[ -eq ]` is a harness error, not a verdict.
census_rows() { if [ -f "$LOG" ]; then grep -c '"n":' "$LOG" || true; else echo 0; fi; }

# Feed the hook through bats' `run` with the payload on stdin. The exit status is then an EXPLICIT
# assertion (`$status`) instead of an implicit errexit abort — and shellcheck never sees an indirect
# `$?`, which the land gate's .bats arm blocks on (SC2181). `feed` takes the payload as an argument;
# `feed_from` takes the NAME of a producer function and calls it.
#
# 🚨 NEITHER MAY BE PIPED INTO. `producer | helper` runs the helper in a SUBSHELL, so `run` sets
# `$status` in a process that immediately exits and the caller reads an EMPTY string — which fails
# as `[: : integer expected`, i.e. as a harness error rather than a wrong value. That is why
# `feed_from` calls the producer instead of reading the payload off its own stdin.
feed()      { printf '%s' "$1" > "$BATS_TEST_TMPDIR/payload.json"; run bash "$HOOK" < "$BATS_TEST_TMPDIR/payload.json"; }
feed_from() { "$@"             > "$BATS_TEST_TMPDIR/payload.json"; run bash "$HOOK" < "$BATS_TEST_TMPDIR/payload.json"; }

# ── the golden payload ──────────────────────────────────────────────────────────────────────────
@test "a real 220 batch payload writes exactly ONE census row" {
  feed_from golden_payload
  [ "$status" -eq 0 ]
  [ -f "$LOG" ]
  [ "$(census_rows)" -eq 1 ]
  [ "$(wc -l < "$LOG")" -eq 1 ]
}

@test "the census row carries the batch size, the tool mix and the fields PostToolUse lacks" {
  golden_payload | bash "$HOOK"
  run jq -e '.n == 3 and .tools.Bash == 3
             and .sid == "7738f61b-b906-47da-ab94-9104a7aaf2db"
             and .prompt_id == "7980057e-bccd-481d-8759-6efae3c167da"
             and .mode == "auto" and .effort == "low"' "$LOG"
  [ "$status" -eq 0 ]
}

# ── THE CONTROL THAT CAN FAIL ───────────────────────────────────────────────────────────────────
# Three calls and one call must produce DIFFERENT `n` from the same handler, and the tool names must
# be the real ones. A handler that hardcodes n=1, that emits a row per call, or that reads the wrong
# field path (the `// "?"` default winning) fails at least one of these three assertions. Verified
# to be non-vacuous by mutating the subject: replacing `.tool_calls | length` with `1` reddens the
# first assertion, and replacing `.tool_calls | map(.tool_name // "?")` with `[.tool_name // "?"]`
# reddens the third.
@test "batch size is READ from the payload, not assumed — three calls and one call differ" {
  batch_payload Bash Bash Bash | bash "$HOOK"
  [ "$(jq -r '.n' "$LOG")" -eq 3 ]
  : > "$LOG"
  batch_payload Bash | bash "$HOOK"
  [ "$(jq -r '.n' "$LOG")" -eq 1 ]
}

@test "the tool mix is the REAL per-call names, never a placeholder" {
  batch_payload Read Read Edit | bash "$HOOK"
  run jq -e '.n == 3 and .tools.Read == 2 and .tools.Edit == 1 and (.tools | has("?") | not)' "$LOG"
  [ "$status" -eq 0 ]
}

@test "a command carrying a quote, a backslash and a newline still yields ONE valid JSON line" {
  printf '%s' '{"hook_event_name":"PostToolBatch","session_id":"s","tool_calls":[{"tool_name":"Bash","tool_input":{"command":"echo \"hi\\\\there\\nsecond\""},"tool_response":"x"}]}' \
    | bash "$HOOK"
  [ "$(wc -l < "$LOG")" -eq 1 ]
  run jq -e '.n == 1' "$LOG"
  [ "$status" -eq 0 ]
}

# ── the 220-only arm, measured on both installed binaries ───────────────────────────────────────
@test "PostToolBatch is ABSENT from the installed 2.1.114 binary and PRESENT in 2.1.220" {
  [ -f "$BIN114" ] || skip "2.1.114 binary not installed at $BIN114 — the claim is unmeasurable here, not true by default"
  [ -f "$BIN220" ] || skip "2.1.220 binary not installed at $BIN220 — no positive control, so an absence would prove nothing"
  # positive control FIRST: the same instrument must find the name where it exists
  [ "$(grep -ca '"PostToolBatch"' "$BIN220" || true)" -gt 0 ]
  [ "$(grep -ca '"PostToolBatch"' "$BIN114" || true)" -eq 0 ]
  # and the instrument is not blind to 114 in general
  [ "$(grep -ca '"PostToolUseFailure"' "$BIN114" || true)" -gt 0 ]
}

# TWO INDEPENDENT GATES make a mis-registration inert, and they are tested separately because a
# single fixture cannot tell them apart. Measured while red-proving this suite: deleting the
# `hook_event_name` gate leaves the arm below GREEN, because a real PostToolUse payload has no
# `tool_calls` at all and the SHAPE gate refuses it on its own. So the arm below proves inertness
# for the shape the harness actually sends, and the arm after it is what pins the event gate.
@test "a real PostToolUse payload is refused — a mis-registration is inert, not wrong" {
  feed '{"hook_event_name":"PostToolUse","session_id":"s","tool_name":"Bash","tool_input":{"command":"echo x"},"tool_response":{"stdout":"x"}}'
  [ "$status" -eq 0 ]
  [ "$(census_rows)" -eq 0 ]
}

# 🚨 SYNTHETIC FIXTURE, and labelled as such. No event on either installed binary sends a
# `tool_calls` array under a name other than PostToolBatch, so this shape is not one the harness
# emits today — which is exactly why the event gate needs its own arm: without it the gate is
# unfalsifiable and would rot into decoration. The contract it defends is real and cheap to hold:
# only a payload that SAYS it is a batch may be counted as one, so a future event that borrows the
# field, or a copy of this handler pointed at the wrong event, cannot silently inflate the census.
@test "a NON-batch event carrying tool_calls is still refused — the event name gates the census" {
  feed '{"hook_event_name":"PostToolUse","session_id":"s","tool_calls":[{"tool_name":"Bash","tool_input":{},"tool_response":"x"}]}'
  [ "$status" -eq 0 ]
  [ "$(census_rows)" -eq 0 ]
}

# ── fail-open doors, all four ───────────────────────────────────────────────────────────────────
@test "empty stdin exits 0 and writes nothing at all" {
  feed ''
  [ "$status" -eq 0 ]
  [ ! -f "$LOG" ]
}

@test "malformed JSON exits 0, writes NO census row, and leaves an abstain marker" {
  feed 'not json {{{'
  [ "$status" -eq 0 ]
  [ "$(census_rows)" -eq 0 ]
  grep -q '"abstain":"malformed-json"' "$LOG"
}

@test "a tool_calls that is not an array exits 0 and writes no census row" {
  feed '{"hook_event_name":"PostToolBatch","session_id":"s","tool_calls":"three"}'
  [ "$status" -eq 0 ]
  [ "$(census_rows)" -eq 0 ]
  feed '{"hook_event_name":"PostToolBatch","session_id":"s","tool_calls":{"a":1}}'
  [ "$status" -eq 0 ]
  [ "$(census_rows)" -eq 0 ]
}

@test "a payload with no tool_calls exits 0 and writes no census row" {
  feed '{"hook_event_name":"PostToolBatch","session_id":"s"}'
  [ "$status" -eq 0 ]
  [ "$(census_rows)" -eq 0 ]
  feed '{"hook_event_name":"PostToolBatch","session_id":"s","tool_calls":[]}'
  [ "$status" -eq 0 ]
  [ "$(census_rows)" -eq 0 ]
}

@test "no jq on PATH exits 0 and abstains rather than writing a bogus row" {
  golden_payload > "$BATS_TEST_TMPDIR/payload.json"
  run env PATH=/bin bash "$HOOK" < "$BATS_TEST_TMPDIR/payload.json"
  [ "$status" -eq 0 ]
  [ "$(census_rows)" -eq 0 ]
  grep -q '"abstain":"no-jq"' "$LOG"
}

# ── the census is BOUNDED (HOOK_CHAIN_COST R-5: do not mint a second unbounded log) ─────────────
@test "the census log rotates at its cap instead of growing without limit" {
  export POST_TOOL_BATCH_MAX_BYTES=200
  golden_payload | bash "$HOOK"
  [ ! -f "$LOG.1" ]                      # under the cap: no rotation yet
  golden_payload | bash "$HOOK"
  [ -f "$LOG.1" ]                        # the first row pushed it over, so the next append rotated
  [ "$(census_rows)" -eq 1 ]
}

@test "the handler is executable and is a bash script" {
  [ -x "$HOOK" ]
  head -1 "$HOOK" | grep -q '^#!/bin/bash'
}
