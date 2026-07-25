#!/usr/bin/env bats
# cc-blockers — the operator one-glance view of safeguard-blocked fired peers. Renders the reaper's
# kind=="safeguard-blocked" board rows (latest per pane); read-only; robust to the shared board's mixed
# actors and malformed lines. Hermetic: a temp board file via CC_REAPER_IDL — never the real ~/.claude.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-blockers"
  D="$BATS_TEST_TMPDIR"
  BOARD="$D/idl.jsonl"
  export CC_REAPER_IDL="$BOARD"
  sg() { # <ts> <pane> <name> <model> <refusal> <recover_cmd> — append a safeguard-blocked row
    jq -nc --arg ts "$1" --arg p "$2" --arg n "$3" --arg m "$4" --arg r "$5" --arg cmd "$6" \
      '{ts:$ts,actor:"cc-reaper",kind:"safeguard-blocked",pane:$p,name:$n,account:"claude-quaternary",blocked_model:$m,refusal:$r,firedBy:"ORIG",recover_cmd:$cmd}' >> "$BOARD"; }
}

@test "absent board → clean 'none' message, exit 0" {
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'no safeguard-blocked'
}

@test "absent board --json → empty array" {
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.')" = '[]' ]
}

@test "renders a safeguard-blocked row: slug, account, model, refusal, recover command" {
  sg "2026-07-25T09:05:00Z" "725A269A" "wt-pool-2-725A269A" "Fable 5" "safeguards flagged this message" "cc-recover-safeguard 725A269A"
  run "$C"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'wt-pool-2-725A269A'
  echo "$output" | grep -q 'Fable 5'
  echo "$output" | grep -q 'safeguards flagged this message'
  echo "$output" | grep -q 'cc-recover-safeguard 725A269A'
}

@test "dedup: multiple rows for one pane → only the LATEST is shown" {
  sg "2026-07-25T09:05:00Z" "PANE1" "peer-1" "Fable 5" "older refusal" "cc-recover-safeguard PANE1"
  sg "2026-07-25T09:10:00Z" "PANE1" "peer-1" "Fable 5" "NEWER refusal" "cc-recover-safeguard PANE1"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]
  [ "$(echo "$output" | jq -r '.[0].refusal')" = "NEWER refusal" ]
}

@test "ignores non-safeguard board rows (surface-page / selfcheck)" {
  printf '%s\n' '{"ts":"2026-07-25T09:00:00Z","actor":"cc-reaper","kind":"surface-page","cause":"crashed","name":"x","pane":"P0"}' >> "$BOARD"
  printf '%s\n' '{"ts":"2026-07-25T09:01:00Z","actor":"cc-reaper","kind":"selfcheck-page","live":3,"enumerated":2,"delta":1}' >> "$BOARD"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -c '.')" = '[]' ]      # no safeguard rows → empty
  run "$C"
  echo "$output" | grep -qi 'no safeguard-blocked sessions surfaced'
}

@test "robust to a malformed (non-JSON) line in the shared board" {
  printf '%s\n' 'THIS IS NOT JSON at all' >> "$BOARD"
  sg "2026-07-25T09:05:00Z" "PANE2" "peer-2" "Fable 5" "refused" "cc-recover-safeguard PANE2"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 1 ]         # the good row survives; the junk line is skipped
  [ "$(echo "$output" | jq -r '.[0].pane')" = "PANE2" ]
}

@test "two distinct blocked panes → two rows, newest first" {
  sg "2026-07-25T09:05:00Z" "PANE-A" "peer-a" "Fable 5" "ra" "cc-recover-safeguard PANE-A"
  sg "2026-07-25T09:20:00Z" "PANE-B" "peer-b" "Fable 5" "rb" "cc-recover-safeguard PANE-B"
  run "$C" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq 'length')" = 2 ]
  [ "$(echo "$output" | jq -r '.[0].pane')" = "PANE-B" ]   # newest first
}

@test "unknown arg → exit 2" {
  run "$C" --bogus
  [ "$status" -eq 2 ]
}
