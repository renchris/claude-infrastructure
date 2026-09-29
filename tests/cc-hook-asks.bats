#!/usr/bin/env bats
# cc-hook-asks — the read-only record of hook confirmation prompts
# (docs/research/hook-ask-confirmations-2026-09-28.md §6-§7).
#
# One fixture HOME (tests/fixtures/cc-hook-asks/mkfixture.py) carries one ask per outcome class, the
# same session in two account dirs plus a symlinked third (dedupe), a subagent and a workflow agent,
# two concurrent same-reason asks that only the validate-bash log still holds (the heuristic join),
# a 2.1.220-era curl ask only curl-audit holds, and synthetic log rows that must be skipped. Every
# assertion keys on a tool_use_id named for its case, read from --json, so a wrong join names itself.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  CHA="$REPO/bin/cc-hook-asks"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  python3 "$REPO/tests/fixtures/cc-hook-asks/mkfixture.py" "$HOME"
  export CC_HOOK_ASKS_NOW=1789905600 TZ=UTC
}

# field <tool_use_id> <key> — one field of one row of `--json` output
field() {
  "$CHA" 7 --json | python3 -c '
import json, sys
tid, key = sys.argv[1], sys.argv[2]
for line in sys.stdin:
    o = json.loads(line)
    if o.get("tool_use_id") == tid:
        print(o.get(key)); break
else:
    print("NO-ROW")' "$1" "$2"
}

@test "each outcome class is classified from its tool_result" {
  [ "$(field toolu_ran outcome)" = "ran" ]
  [ "$(field toolu_rej outcome)" = "rejected" ]
  [ "$(field toolu_int outcome)" = "interrupted" ]
  [ "$(field toolu_auto outcome)" = "auto-denied" ]
  [ "$(field toolu_pend outcome)" = "pending" ]
  [ "$(field toolu_pr outcome)" = "ran" ]
}

@test "a rejection keeps the operator's feedback" {
  [ "$(field toolu_rej feedback)" = "not now, stash first" ]
}

@test "the archive's cleared_tool_use_id proves shown and gives the wait, even when resolved_by=Stop" {
  [ "$(field toolu_ran shown)" = "yes" ]
  [ "$(field toolu_ran waited_s)" = "42" ]
  [ "$(field toolu_ran outcome)" = "ran" ]
  [ "$(field toolu_auto shown)" = "no" ]
}

@test "hooks and agent kinds are named: main, subagent, workflow" {
  [ "$(field toolu_pend hook)" = "curl-gate" ]
  [ "$(field toolu_pr hook)" = "pr-gate" ]
  [ "$(field toolu_ran agent)" = "main" ]
  [ "$(field toolu_sub agent)" = "subagent" ]
  [ "$(field toolu_wf agent)" = "workflow" ]
  [ "$(field toolu_wf agent_id)" = "awf" ]
}

@test "a session copied into two account dirs and a symlinked third yields one row per ask" {
  run "$CHA" 7 --json
  [ "$status" -eq 0 ]
  n=$(printf '%s\n' "$output" | grep -c '"tool_use_id": "toolu_ran"')
  [ "$n" -eq 1 ]
  # the validate-bash log row for toolu_ran is accounted for by its attachment, not added again
  total=$(printf '%s\n' "$output" | grep -c '"tool_use_id"')
  [ "$total" -eq 11 ]
}

@test "log-only concurrent same-reason asks join heuristically, in time order, past target decoys" {
  [ "$(field toolu_h1 joined)" = "heuristic" ]
  [ "$(field toolu_h2 joined)" = "heuristic" ]
  [ "$(field toolu_h1 outcome)" = "interrupted" ]
  [ "$(field toolu_h2 outcome)" = "interrupted" ]
  # the log row at TH+3 is nearer toolu_h2 (TH+2) but was asked first, so it is toolu_h1's: its wait
  # runs from TH+3 to toolu_h1's result at TH+90
  [ "$(field toolu_h1 waited_s)" = "87.0" ]
  [ "$(field toolu_h2 waited_s)" = "87.0" ]
  [ "$(field toolu_decoy joined)" = "NO-ROW" ]
}

@test "a curl ask only curl-audit holds joins exactly, shows the redacted command, and is coverage=partial" {
  [ "$(field toolu_c220 joined)" = "log-exact" ]
  [ "$(field toolu_c220 coverage)" = "partial" ]
  [ "$(field toolu_c220 outcome)" = "ran" ]
  run field toolu_c220 command
  [[ "$output" == *"<REDACTED>"* ]] || false
  [[ "$output" != *"sk-live-SECRET"* ]] || false
}

@test "synthetic rows are skipped: all-zero and non-UUID sids, curl replay rows" {
  run "$CHA" 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"synthetic skipped 3"* ]] || false
  [[ "$output" != *"No URL parsed"* ]] || false
  [[ "$output" != *"/tmp/x"* ]] || false
}

@test "the table ends with per-hook counts, a coverage line naming its denominator, and a verdict" {
  run "$CHA" 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"validate-bash: 8 asks"* ]] || false
  [[ "$output" == *"curl-gate: 2 asks"* ]] || false
  [[ "$output" == *"pr-gate: 1 asks"* ]] || false
  [[ "$output" == *"coverage: 11 asks over 7 days"* ]] || false
  [[ "$output" == *"coverage=partial 1"* ]] || false
  [[ "${lines[${#lines[@]}-1]}" == "verdict: COMPLETE" ]] || false
}

@test "--hook and --outcome filter the rows" {
  run "$CHA" 7 --hook curl-gate --json
  [ "$(printf '%s\n' "$output" | grep -c '"tool_use_id"')" -eq 2 ]
  run "$CHA" 7 --outcome interrupted --json
  [ "$(printf '%s\n' "$output" | grep -c '"tool_use_id"')" -eq 3 ]
  run "$CHA" 7 --outcome nonsense
  [ "$status" -eq 2 ]
}

@test "the window excludes asks older than DAYS" {
  run "$CHA" 0.1 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '"tool_use_id"')" -eq 0 ]
}

@test "a hit deadline prints a PARTIAL verdict instead of a silent short count" {
  run "$CHA" 7 --deadline 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict: PARTIAL"* ]] || false
}

@test "read-only: nothing under HOME changes; --out is the only write" {
  before=$(find "$HOME" -exec stat -f '%N %m %z' {} + | sort | shasum)
  run "$CHA" 7 --out "$BATS_TEST_TMPDIR/rows.jsonl"
  [ "$status" -eq 0 ]
  after=$(find "$HOME" -exec stat -f '%N %m %z' {} + | sort | shasum)
  [ "$before" = "$after" ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/rows.jsonl")" -eq 11 ]
}
