#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test exports its own CC_BILLING in its own subshell, on purpose
# billing-attribution.bats — the three-key attribution API's semantics (wave W2 of
# docs/plans/ZERO_HITL_ROTATION.md; spec docs/research/midturn-account-move-2026-10-25/REPORT.md §12
# row W2 and notes/SYNTHESIS.md §3.1/§3.8): scripts/lib/billing.py through bin/cc-billing, over a
# scratch registry, scratch config dirs and a fixture lane ledger. Never reads the live ~/.reso.
#
# Contracts held here:
#   · no ledger (switch off or on): billing == home, identity == home (the W2 acceptance read)
#   · switch off ignores a ledger that moves billing; CC_BILLING beats the billing.on switch file
#   · billing is time-aware: before a commit it is the row's prev_billing, from t_c on the target
#   · prepared moves nothing; aborted restores prev_billing; reverted returns to home
#   · identity is unknown after any move away from home, and home again only after a re-home
#   · unknown is first-class: a moving row with no billing, or a session with no findable home,
#     reads `unknown`, never home (R5)
#   · home comes from the registry, else the newest store holding the transcript
#   · --billed-to and --mismatched answer over ledger ∪ registry; usage errors exit 2
# RED-proof: (a) file-absence: before W2 none of billing.py / cc-billing existed, so every test failed.
# (b) mutants on a scratch copy, 2026-10-26: STATE_EFFECT counting "prepared" reds 5; dropping the
# `r["_t"] <= at` filter reds 4; identity ignoring the rehomed cut reds 8; a missing billing falling
# back to the prior row reds 9.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  CLI="$REPO/bin/cc-billing"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_LANES_DIR="$BATS_TEST_TMPDIR/lanes"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"
  export CC_ACCOUNTS_JSON="$REPO/accounts.json"
  unset CC_BILLING CC_BILLING_LEDGER
  mkdir -p "$HOME" "$CC_LANES_DIR" "$CC_REGISTRY_DIR"
  LEDGER="$CC_LANES_DIR/ledger.jsonl"
}

# reg <pane> <sid> <account-as-session-register-writes-it> [startedAt]
reg() {
  printf '{"paneUUID":"%s","session_id":"%s","account":"%s","pid":1,"startedAt":%s}\n' \
    "$1" "$2" "$3" "${4:-1000}" > "$CC_REGISTRY_DIR/$1.json"
}

# row <t> <sid> <state> [billing] [prev_billing] [home]   ("-" leaves a key out)
row() {
  local j
  j=$(printf '{"t":%s,"sid":"%s","state":"%s","lane":"L1","move_id":"m1"' "$1" "$2" "$3")
  [ "${4:--}" != - ] && j="$j,\"billing\":\"$4\""
  [ "${5:--}" != - ] && j="$j,\"prev_billing\":\"$5\""
  [ "${6:--}" != - ] && j="$j,\"home\":\"$6\""
  printf '%s}\n' "$j" >> "$LEDGER"
}

field() { "$CLI" --sid "$1" --field "$2" "${@:3}"; }

@test "no ledger: billing and identity are home, switch off and on" {
  reg 1 S1 claude-tertiary
  run "$CLI" --sid S1 --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.home,.billing,.identity,.billing_source,.switch]|join(" ")' <<<"$output")" = "next3 next3 home off off" ]
  CC_BILLING=1 run "$CLI" --sid S1 --json
  [ "$(jq -r '[.home,.billing,.identity,.billing_source,.switch]|join(" ")' <<<"$output")" = "next3 next3 home no-ledger on" ]
}

@test "switch off ignores a ledger that moves billing" {
  reg 1 S1 claude-tertiary
  row 100 S1 committed next4 next3
  [ "$(field S1 billing)" = next3 ]
  [ "$(field S1 identity)" = home ]
  [ "$(CC_BILLING=1 field S1 billing)" = next4 ]
}

@test "CC_BILLING beats the billing.on switch file" {
  reg 1 S1 claude-tertiary
  row 100 S1 committed next4 next3
  touch "$CC_LANES_DIR/billing.on"
  [ "$(field S1 billing)" = next4 ]
  [ "$(CC_BILLING=off field S1 billing)" = next3 ]
  [ "$(CC_BILLING=0 "$CLI" --status --json | jq -r .switch)" = off ]
}

@test "billing is time-aware around the commit" {
  export CC_BILLING=1
  reg 1 S1 claude-tertiary
  row 100 S1 prepared next4 next3
  row 105 S1 committed next4 next3
  [ "$(field S1 billing --at 50)" = next3 ]
  [ "$(field S1 billing --at 104)" = next3 ]
  [ "$(field S1 billing --at 105)" = next4 ]
  [ "$(field S1 billing)" = next4 ]
  # the same instant in ms and ISO-8601
  [ "$(field S1 billing --at 105000)" = next4 ]
  [ "$(field S1 billing --at 1970-01-01T00:01:45Z)" = next4 ]
  [ "$(field S1 billing --at 1970-01-01T00:01:44Z)" = next3 ]
}

@test "prepared moves nothing; aborted restores prev_billing" {
  export CC_BILLING=1
  reg 1 S1 claude-tertiary
  row 100 S1 prepared next4 next3
  run "$CLI" --sid S1 --json
  [ "$(jq -r '[.billing,.billing_source,.identity]|join(" ")' <<<"$output")" = "next3 no-row home" ]
  row 101 S1 aborted next4 next3
  run "$CLI" --sid S1 --json
  [ "$(jq -r '[.billing,.state,.identity]|join(" ")' <<<"$output")" = "next3 aborted home" ]
}

@test "an abort that names no prev_billing leaves the earlier move standing" {
  export CC_BILLING=1
  reg 1 S1 claude-tertiary
  row 100 S1 committed next4 next3
  row 200 S1 aborted next2
  [ "$(field S1 billing)" = next4 ]
}

@test "reverted returns billing to home but identity stays unknown" {
  export CC_BILLING=1
  reg 1 S1 claude-tertiary
  row 100 S1 committed next4 next3
  [ "$(field S1 identity)" = unknown ]
  row 200 S1 reverted next3 next4
  run "$CLI" --sid S1 --json
  [ "$(jq -r '[.billing,.identity,(.identity_acct|tostring),.since]|join(" ")' <<<"$output")" = "next3 unknown null 200" ]
}

@test "a re-home closes the identity mismatch" {
  export CC_BILLING=1
  reg 1 S1 claude-tertiary 1000
  row 100 S1 committed next4 next3
  row 300 S1 rehomed next4 next3 next4
  reg 2 S1 claude-quaternary 2000   # the relaunched process registers under its new store
  run "$CLI" --sid S1 --json
  [ "$(jq -r '[.home,.billing,.identity,.identity_acct]|join(" ")' <<<"$output")" = "next4 next4 home next4" ]
  [ "$(field S1 billing --at 200)" = next4 ]
  [ "$(field S1 identity --at 200)" = unknown ]
}

@test "unknown is first-class: a move naming no billing, or no findable home" {
  export CC_BILLING=1
  reg 1 S1 claude-tertiary
  row 100 S1 committed - next3
  [ "$(field S1 billing)" = unknown ]
  [ "$(field S1 identity)" = unknown ]
  run "$CLI" --sid NOWHERE --json
  [ "$(jq -r '[.home,.billing,.identity]|join(" ")' <<<"$output")" = "unknown unknown unknown" ]
  CC_BILLING=0 run "$CLI" --sid NOWHERE --json
  [ "$(jq -r '[.home,.billing,.identity]|join(" ")' <<<"$output")" = "unknown unknown unknown" ]
}

@test "ledger names fold through aliases and config dirs; malformed lines are counted" {
  export CC_BILLING=1
  reg 1 S1 claude-tertiary
  # shellcheck disable=SC2088  # a literal ~ is the spelling under test
  row 100 S1 committed "~/.claude-quaternary" claude3
  echo 'not json' >> "$LEDGER"
  echo '{"sid":"S1","state":"committed"}' >> "$LEDGER"
  [ "$(field S1 billing)" = next4 ]
  [ "$(field S1 billing --at 99)" = next3 ]
  [ "$("$CLI" --status --json | jq -r '[.bad_rows,.sessions]|join(" ")')" = "2 1" ]
}

@test "home: registry first (newest row), else the newest store holding the transcript" {
  reg 1 S1 claude-secondary 1000
  reg 2 S1 claude-tertiary 5000
  [ "$(field S1 home)" = next3 ]
  mkdir -p "$HOME/.claude-next/projects/p" "$HOME/.claude-quaternary/projects/q"
  touch -t 202601010000 "$HOME/.claude-next/projects/p/S2.jsonl"
  touch -t 202602010000 "$HOME/.claude-quaternary/projects/q/S2.jsonl"
  run "$CLI" --sid S2 --json
  [ "$(jq -r '[.home,.home_source]|join(" ")' <<<"$output")" = "next4 transcript" ]
  [ "$(field S2 home --home "$HOME/.claude-next/")" = next ]
}

@test "--billed-to and --mismatched answer over ledger and registry" {
  export CC_BILLING=1
  reg 1 S1 claude-tertiary
  reg 2 S2 claude-quaternary
  reg 3 S3 claude-tertiary
  row 100 S1 committed next4 next3
  run "$CLI" --billed-to next4 --json
  [ "$output" = '["S1", "S2"]' ]
  [ "$("$CLI" --billed-to claude3)" = S3 ]
  [ "$("$CLI" --billed-to next4 --at 50 --json)" = '["S2"]' ]
  run "$CLI" --mismatched --json
  [ "$(jq -r '.[]|[.sid,.home,.billing]|join(" ")' <<<"$output")" = "S1 next3 next4" ]
  [ "$(CC_BILLING=0 "$CLI" --mismatched --json)" = '[]' ]
}

@test "usage errors exit 2" {
  run "$CLI"
  [ "$status" -eq 2 ]
  run "$CLI" --sid S1 --billed-to next
  [ "$status" -eq 2 ]
  run "$CLI" --sid S1 --at yesterday
  [ "$status" -eq 2 ]
  run "$CLI" --sid S1 --field quota
  [ "$status" -eq 2 ]
  run "$CLI" --billed-to nobody
  [ "$status" -eq 2 ]
  run "$CLI" --help
  [ "$status" -eq 0 ]
}
