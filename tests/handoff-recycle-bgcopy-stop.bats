#!/usr/bin/env bats
# Regression guard for the recycle's backgrounded copy — handoff-fire.sh rcy_bgcopy_find and
# rcy_bgcopy_stop (operator ruling 2026-10-04, decision 75ea14d27d0f).
#
# THE DEFECT. "Move to background and exit" (the keep-tasks answer to the background-work dialog)
# moves the WHOLE conversation into a background job on 2.1.284. On 2026-10-03 that copy kept taking
# Stop-hook-driven turns and fired 10 unapproved paid draws beside a successor that never booted.
# The fix stops the copy within seconds and keeps its tasks; these tests pin how the copy is found
# (only the record THIS answer wrote), which config dir the stop runs under (the job's own), and
# that every doubtful case leaves the copy alone and says so.

setup() {
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts-absent"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  eval "$(sed -n '/^rcy_bgcopy_find() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^rcy_bgcopy_stop() {/,/^}/p' "$HF")"
  hf_bounded() { "$@"; }   # the real one wraps a timeout binary; the bound is not under test here
  export CC_RECYCLE_BGCOPY_WAIT_S=0

  OLD="389eb846-3bb1-44b6-9928-ba67e233652a"
  NEW="032aa97f-b032-49ea-bb3d-c47cad04493d"
  TR="$BATS_TEST_TMPDIR/$OLD.jsonl"
  printf '{"type":"user","sessionId":"%s"}\n' "$OLD" > "$TR"
  # The stub records its argv and the config dir it ran under.
  STUB="$BATS_TEST_TMPDIR/claude-stub"
  cat > "$STUB" <<'SH'
#!/usr/bin/env bash
printf '%s|%s\n' "$CLAUDE_CONFIG_DIR" "$*" >> "$HOME/claude-calls.log"
exit "${STUB_RC:-0}"
SH
  chmod +x "$STUB"; export CC_RECYCLE_CLAUDE_BIN="$STUB"
}

continued_in() { printf '{"type":"continued-in","sessionId":"%s","continuedInSessionId":"%s"}\n' "$OLD" "$1" >> "$TR"; }
job() { # $1=config dir name $2=uuid → a job state like 2.1.284 writes
  mkdir -p "$HOME/$1/jobs/${2:0:8}"
  printf '{"sessionId":"%s","state":"stopped","providerEnv":{"CLAUDE_CONFIG_DIR":"%s"},"fan":[{"id":"b1","kind":"shell","label":"pnpm review:bottles"},{"id":"b2","kind":"shell","label":"done one","doneAt":1}]}\n' \
    "$2" "$HOME/$1" > "$HOME/$1/jobs/${2:0:8}/state.json"
}

@test "find: only the continued-in record written AFTER the answer counts" {
  continued_in "aaaaaaaa-0000-0000-0000-000000000000"
  off="$(wc -c < "$TR" | tr -d ' ')"
  run rcy_bgcopy_find "$TR" "$off"
  [ -z "$output" ]
  continued_in "$NEW"
  run rcy_bgcopy_find "$TR" "$off"
  [ "$output" = "$NEW" ]
}

@test "stop: runs claude stop <short> under the JOB's config dir, not the predecessor's" {
  off="$(wc -c < "$TR" | tr -d ' ')"; continued_in "$NEW"; job .claude-tertiary "$NEW"
  run rcy_bgcopy_stop "$TR" "$off"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-calls.log")" = "$HOME/.claude-tertiary|stop 032aa97f" ]
  [[ "$output" == "bgcopy=032aa97f stopped"* ]] || false
  [[ "$output" == *"its tasks keep running: pnpm review:bottles;"* ]] || false
  [[ "$output" == *"claude attach 032aa97f"* ]] || false
}

@test "CONTROL: no continued-in record → nothing is stopped, and the line says the copy may run" {
  run rcy_bgcopy_stop "$TR" "$(wc -c < "$TR" | tr -d ' ')"
  [ "$status" -eq 0 ]
  [[ "$output" == "bgcopy=unknown"* ]] || false
  [ ! -e "$HOME/claude-calls.log" ]
}

@test "CONTROL: a job folder with the same short id but another uuid is NOT stopped" {
  off="$(wc -c < "$TR" | tr -d ' ')"; continued_in "$NEW"
  job .claude-quaternary "032aa97f-ffff-ffff-ffff-ffffffffffff"
  run rcy_bgcopy_stop "$TR" "$off"
  [[ "$output" == *"job state not found, NOT stopped"* ]] || false
  [ ! -e "$HOME/claude-calls.log" ]
}

@test "a failed claude stop is reported as FAILED, never as stopped" {
  off="$(wc -c < "$TR" | tr -d ' ')"; continued_in "$NEW"; job .claude-quaternary "$NEW"
  STUB_RC=1 run rcy_bgcopy_stop "$TR" "$off"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude stop FAILED rc=1"* ]] || false
  [[ "$output" != *" stopped ("* ]] || false
}
