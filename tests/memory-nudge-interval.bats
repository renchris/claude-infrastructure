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
# Only the nudge's own rows: the ruling shadow logs one `memory-nudge:ruling` row per prompt into
# the same store (tests/memory-nudge-ruling-shadow.bats), and this suite is about the fire row.
idl_n() { if [ -f "$CC_IDL" ]; then jq -s '[.[] | select(.hook == "memory-nudge")] | length' "$CC_IDL"; else echo 0; fi; }
nrow() { jq -r --arg f "$1" 'select(.hook == "memory-nudge") | .[$f]' <"$CC_IDL"; }

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
  [ "$(nrow hook)" = "memory-nudge" ]
  [ "$(nrow disposition)" = "fired" ]
  [ "$(nrow reason)" = "periodic" ]
  [ "$(nrow sid)" = "s-row" ]
  [ "$(nrow count)" = "12" ]
}

# ── machine prompts on their own ×4 interval (docs/research/startup-hooks-2026-10-18/README.md §2 #7)
# A prompt starting with `<` (task-notification, teammate-message, system tags) counts in
# nudge-<sid>.mcount and fires every INTERVAL×4; typed prompts keep nudge-<sid>.count and INTERVAL.

# mprompts <sid> <n> <prompt-text> — like prompts, but the payload carries a prompt.
mprompts() {
  local i out
  FIRED=0 LAST=""
  for ((i = 1; i <= $2; i++)); do
    out="$(jq -cn --arg s "$1" --arg p "$3" '{session_id:$s,cwd:"/nonexistent-cwd-xyz",prompt:$p}' \
      | MEMORY_INDEX_PATH="$IDX" bash "$HOOK")"
    [ -z "$out" ] || FIRED=$(( FIRED + 1 ))
    LAST="$out"
  done
}

# MUTANT CONTROL, run by hand on 2026-10-18 and not committed: a copy of the hook with the machine
# split reverted (the `'<'*)` arm of the CF case deleted, so every prompt takes nudge-<sid>.count
# and the plain INTERVAL), fed this test's 11 machine prompts at INTERVAL=3, fired 3 times and
# wrote nudge-<sid>.count; the real hook fired 0 times. So the first FIRED assertion below goes
# RED on the mutant: the test discriminates the split rather than passing on any hook.
@test "a <task-notification> prompt advances its own counter, not the human one, and fires on INTERVAL×4" {
  export MEMORY_NUDGE_INTERVAL=3
  mprompts s-mach 11 '<task-notification><task-id>t1</task-id><status>completed</status></task-notification>'
  [ "$FIRED" -eq 0 ]
  [ ! -f "$MEMORY_NUDGE_STATE_DIR/nudge-s-mach.count" ]
  [ "$(cat "$MEMORY_NUDGE_STATE_DIR/nudge-s-mach.mcount")" = "11" ]
  [ "$(idl_n)" = "0" ]
  # Leading whitespace does not make a machine prompt typed (the classifier's own `\A\s*<`).
  mprompts s-mach 1 '  <teammate-message teammate_id="lead">go</teammate-message>'
  [ "$FIRED" -eq 1 ]
  printf '%s' "$LAST" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'MEMORY CHECK (periodic)'
  [ "$(idl_n)" = "1" ]
  [ "$(nrow count)" = "12" ]
  [ "$(nrow interval)" = "12" ]
}

@test "typed prompts still fire every INTERVAL while machine prompts interleave" {
  export MEMORY_NUDGE_INTERVAL=3
  local i typed_fires=0 machine_fires=0
  for i in 1 2 3 4 5 6; do
    mprompts s-mix 1 '<task-notification>done</task-notification>'
    machine_fires=$(( machine_fires + FIRED ))
    mprompts s-mix 1 "typed prompt number $i"
    typed_fires=$(( typed_fires + FIRED ))
  done
  [ "$typed_fires" -eq 2 ]                       # typed #3 and #6
  [ "$machine_fires" -eq 0 ]                     # 6 machine prompts < 12
  [ "$(cat "$MEMORY_NUDGE_STATE_DIR/nudge-s-mix.count")" = "6" ]
  [ "$(cat "$MEMORY_NUDGE_STATE_DIR/nudge-s-mix.mcount")" = "6" ]
}

@test "the abstain alarm's denominators stay exact across both counters" {
  export MEMORY_NUDGE_INTERVAL=1
  # 8 typed prompts fire 8 times; 12 machine prompts fire 12/4 = 3 times: 11 fires, 20 prompts.
  mprompts s-den 8 'typed'
  mprompts s-den 12 '<task-notification>x</task-notification>'
  [ "$(idl_n)" = "11" ]
  run env CC_ABSTAIN_LOG="$BATS_TEST_TMPDIR/abstain.log" CC_ABSTAIN_NMIN=10 CC_ABSTAIN_CENSUS=0 \
      CC_EXPECTED_SESSION_INDEX_LOG="$BATS_TEST_TMPDIR/none.log" \
      CC_EXPECTED_NUDGE_STATE_DIRS="$MEMORY_NUDGE_STATE_DIR" "$REPO/scripts/idl-abstain-alarm.sh" --run
  printf '%s' "$output" | grep -q 'OK  *memory-nudge  *rows=11  *D=11 '
  printf '%s' "$output" | grep -q 'OK  *memory-nudge:ruling  *rows=20  *D=20 '
}
