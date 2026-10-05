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
  # One export per line: the pin-guard (handoff-fire-capacity-gate.bats case 25) reads them that way.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts-absent"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  eval "$(sed -n '/^rcy_bgcopy_find() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^rcy_bgcopy_stop() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^rcy_acct_for_cfg() {/,/^}/p' "$HF")"
  export CC_ACCOUNT_MAP="$REPO_SRC/lib/account-map.generated.sh"
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

# ── W3 P1b: resume mode, the resumed sid, and acct=/cfg= on every line a human acts on ─────────────

@test "a continued-in record naming the RESUMED sid is never stopped" {
  off="$(wc -c < "$TR" | tr -d ' ')"; continued_in "$NEW"; job .claude-tertiary "$NEW"
  run rcy_bgcopy_stop "$TR" "$off" "$NEW"
  [ "$status" -eq 0 ]
  [ "$output" = "bgcopy=032aa97f — is the resumed session itself, NOT stopped" ] || { echo "$output"; false; }
  [ ! -e "$HOME/claude-calls.log" ]
}

@test "not found: the line names the predecessor's account and config, and a stop that runs there" {
  mkdir -p "$HOME/.claude-tertiary/projects/-p"; mv "$TR" "$HOME/.claude-tertiary/projects/-p/"
  TR="$HOME/.claude-tertiary/projects/-p/$OLD.jsonl"
  off="$(wc -c < "$TR" | tr -d ' ')"; continued_in "$NEW"
  run rcy_bgcopy_stop "$TR" "$off"
  [[ "$output" == *"NOT stopped (acct=next3 cfg=$HOME/.claude-tertiary, the predecessor's)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"stop it with: CLAUDE_CONFIG_DIR=$HOME/.claude-tertiary claude stop 032aa97f" ]] || { echo "$output"; false; }
}

@test "failed: the line names the JOB's account and config" {
  off="$(wc -c < "$TR" | tr -d ' ')"; continued_in "$NEW"; job .claude-quaternary "$NEW"
  STUB_RC=1 run rcy_bgcopy_stop "$TR" "$off"
  [[ "$output" == *"FAILED rc=1 (acct=next4 cfg=$HOME/.claude-quaternary;"* ]] || { echo "$output"; false; }
}

@test "acct: an undeclared config dir prints its basename, an empty one prints ?" {
  run rcy_acct_for_cfg "$HOME/.claude-secondary";  [ "$output" = next2 ]
  run rcy_acct_for_cfg "/x/.claude-elsewhere";     [ "$output" = .claude-elsewhere ]
  run rcy_acct_for_cfg "";                         [ "$output" = "?" ]
}

# THE WATCHER, in resume mode. lr-transplant renamed the source transcript to .handed-off, so the
# predecessor's keep-work answer re-creates <sid>.jsonl in the SOURCE store and writes continued-in
# there; the TARGET store holds a transplanted copy of the same sid, which transcript_for_sid would
# also resolve. The it2 stub plays the predecessor: the digit answer appends the record by path.
_watcher() { # $1=uuid the continued-in record names
  local LIB="$REPO_SRC/hooks/lib/pane-modal.sh" H="$HOME"
  export CC_PANE_MODAL_LIB="$LIB" CC_HANDOFF_ALARM_DIR="$H/.claude/handoff-alarms" HANDOFF_ACCOUNT_SWEEP=off
  mkdir -p "$H/.claude/bin" "$BATS_TEST_TMPDIR/shim"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BATS_TEST_TMPDIR/shim/osascript"; chmod +x "$BATS_TEST_TMPDIR/shim/osascript"
  export PATH="$BATS_TEST_TMPDIR/shim:$PATH" CC_NOTIFY_BIN="$H/.claude/bin/cc-notify"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"
  export SCREEN="$BATS_TEST_TMPDIR/screen.txt"
  cat > "$SCREEN" <<'SCR'
✻ Cooked for 10s · done 5:49 AM · 1 shell still running
▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔
   Background work is running
   The following will stop when you exit:

   shell · sleep 600

   ❯ 1. Exit and stop tasks
     2. Move to background and exit
     3. Stay
─
   Enter to confirm · Esc to cancel
SCR
  export SRC_TX="$H/.claude-secondary/projects/-p/$OLD.jsonl" TGT_CFG="$H/.claude-tertiary" CI_UUID="$1"
  mkdir -p "${SRC_TX%/*}" "$TGT_CFG/projects/-p"
  printf '{"type":"user","sessionId":"%s"}\n' "$OLD" > "$SRC_TX.handed-off"
  printf '{"type":"user","sessionId":"%s"}\n' "$OLD" > "$TGT_CFG/projects/-p/$OLD.jsonl"
  export CC_PROJECTS_DIRS="$TGT_CFG/projects ${H}/.claude-secondary/projects"
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "BGWORK-PANE", "tty": "/dev/ttys999"}]\n'; else echo BGWORK-PANE; fi ;;
  "session read") if [ -e "$HOME/gone" ]; then echo "(session ended)"; else cat "$SCREEN"; fi ;;
  "session send")
    case "${5-}" in [0-9])
      printf '{"type":"continued-in","sessionId":"x","continuedInSessionId":"%s"}\n' "$CI_UUID" >> "$SRC_TX"
      : > "$HOME/gone" ;;
    esac ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"
  printf 'claude --resume %s\n' "$OLD" > "$BATS_TEST_TMPDIR/relaunch.cmd"
  export HF_RECYCLE_SHELL_WAIT_S=6 CC_RECYCLE_BGWORK_EVERY_S=3 CC_RECYCLE_BGCOPY_WAIT_S=2 CC_ACCOUNT_MAP
  # __recycle SID tty cmdfile LAUNCH_DIR old_sid MARKER GOAL prompt RESUME_CFG resumed_sid T0 SRC_TX
  bash "$HF" __recycle BGWORK-PANE "$BATS_TEST_TMPDIR/no-such-tty" "$BATS_TEST_TMPDIR/relaunch.cmd" "$BATS_TEST_TMPDIR" \
    "$OLD" "" "" "" "$TGT_CFG" "$OLD" "$(date -u +%FT%T)" "$SRC_TX" >/dev/null 2>&1 || true
}
row() { jq -c --arg c "$1" 'select(.class==$c)' "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null | tail -1; }

@test "RESUME MODE: the watcher stops the copy, reading the SOURCE transcript, and both rows carry acct=/cfg=" {
  job .claude-secondary "$NEW"
  _watcher "$NEW"
  run row recycle-bgwork-answered
  [[ "$(printf '%s' "$output" | jq -r .detail)" == *"; acct=next2 cfg=$HOME/.claude-secondary" ]] || { echo "$output"; false; }
  run row recycle-bgcopy-stop
  [[ "$(printf '%s' "$output" | jq -r .detail)" == "bgcopy=032aa97f stopped (acct=next2 config $HOME/.claude-secondary,"* ]] || { echo "$output"; false; }
  [ "$(cat "$HOME/claude-calls.log")" = "$HOME/.claude-secondary|stop 032aa97f" ]
}

@test "RESUME MODE: a copy whose uuid IS the resumed sid is left running" {
  job .claude-secondary "$OLD"
  _watcher "$OLD"
  run row recycle-bgcopy-stop
  [[ "$(printf '%s' "$output" | jq -r .detail)" == "bgcopy=389eb846 — is the resumed session itself, NOT stopped" ]] || { echo "$output"; false; }
  [ ! -e "$HOME/claude-calls.log" ]
}
