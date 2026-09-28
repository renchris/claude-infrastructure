#!/usr/bin/env bats
# memory-nudge.sh — MEMORY_NUDGE_INTERVAL parsing and the fire-turn IDL row.
#
# The defect this pins: `[ "$INTERVAL" -gt 0 ] 2>/dev/null || exit 0` read every non-integer
# value exactly like the documented kill switch 0, so a typo (`abc`, `-3`) silenced the nudge
# with nothing to say why (docs/research/truememory-2026-09-27.md §3.3). Now 0 is the kill
# switch, and anything else that is not a positive integer falls back to 12. Leading zeros are
# decimal: bash arithmetic would read `012` as octal 10.
#
# The fire row: the hook logs one IDL row on each DECISION turn and none on the others, so
# scripts/idl-expected-fires.tsv can measure fires against the nudge-*.count denominator.
#
# Assertions are simple commands only (bash exempts `[[ ]]` from errexit in a bats body).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/memory-nudge.sh"
  # Fixture $HOME and state: an unfixtured run would count and log against the live machine.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # A small, healthy index: over-limit would fire on prompt 1 and hide the cadence.
  IDX="$BATS_TEST_TMPDIR/mem/MEMORY.md"; mkdir -p "$(dirname "$IDX")"
  printf -- '- [A](a.md) — one\n- [B](b.md) — two\n' > "$IDX"
}

# prompts <sid> <n> — send n prompts; leaves the LAST prompt's stdout in $LAST and the
# number of prompts that printed anything in $FIRED.
prompts() {
  local i out
  FIRED=0 LAST=""
  for ((i = 1; i <= $2; i++)); do
    out="$(printf '{"session_id":"%s","cwd":"/nonexistent-cwd-xyz"}' "$1" | MEMORY_INDEX_PATH="$IDX" bash "$HOOK")"
    [ -z "$out" ] || FIRED=$(( FIRED + 1 ))
    LAST="$out"
  done
}
idl_n() { if [ -f "$CC_IDL" ]; then wc -l <"$CC_IDL" | tr -d ' '; else echo 0; fi; }

@test "0 is the kill switch: silent, no counter written, no IDL row" {
  export MEMORY_NUDGE_INTERVAL=0
  prompts s-kill 12
  [ "$FIRED" -eq 0 ]
  [ ! -f "$MEMORY_NUDGE_STATE_DIR/nudge-s-kill.count" ]
  [ "$(idl_n)" = "0" ]
}

@test "abc is a typo, not the kill switch: behaves as 12" {
  export MEMORY_NUDGE_INTERVAL=abc
  prompts s-abc 11
  [ "$FIRED" -eq 0 ]
  prompts s-abc 1
  [ "$FIRED" -eq 1 ]
  # The rendered hook output: exactly one JSON object carrying the nudge.
  [ "$(printf '%s' "$LAST" | jq -s 'length')" = "1" ]
  [ "$(printf '%s' "$LAST" | jq -r '.hookSpecificOutput.hookEventName')" = "UserPromptSubmit" ]
  printf '%s' "$LAST" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'MEMORY CHECK (periodic)'
}

@test "-3 is a typo, not the kill switch: behaves as 12" {
  export MEMORY_NUDGE_INTERVAL=-3
  prompts s-neg 11
  [ "$FIRED" -eq 0 ]
  prompts s-neg 1
  [ "$FIRED" -eq 1 ]
}

@test "012 is twelve, not octal ten" {
  export MEMORY_NUDGE_INTERVAL=012
  prompts s-oct 10
  [ "$FIRED" -eq 0 ]
  prompts s-oct 2
  [ "$FIRED" -eq 1 ]
}

@test "a fire turn writes exactly one IDL row; the eleven quiet turns write none" {
  export MEMORY_NUDGE_INTERVAL=12
  prompts s-row 11
  [ "$(idl_n)" = "0" ]
  prompts s-row 1
  [ "$(idl_n)" = "1" ]
  [ "$(jq -r '.hook' <"$CC_IDL")" = "memory-nudge" ]
  [ "$(jq -r '.disposition' <"$CC_IDL")" = "fired" ]
  [ "$(jq -r '.reason' <"$CC_IDL")" = "periodic" ]
  [ "$(jq -r '.sid' <"$CC_IDL")" = "s-row" ]
  [ "$(jq -r '.count' <"$CC_IDL")" = "12" ]
}
