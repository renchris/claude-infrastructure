#!/usr/bin/env bats
# PANE 332 REPLAYED (lr-wake 2026-10-18, docs/research/lr-wake-incident-2026-10-18/REPORT.md Wave A and
# a-failed-self-recycle.md). Session 2e9ed9f2 was moved in place twice, next4→next (batch 030847Z) and
# next→next3 (batch 070336Z). Both times the watcher's 60 s nudge typed the /exit before the foreground
# committed, and the foreground then held at its load gate and killed the watcher: at 03:41 after the
# relaunch had engaged (the bundle said STRANDED, falsely), at 07:24:33 between the disarm line and the
# relaunch line (a bare zsh, the incident's image).
#
# The record, scrubbed (paths under ~): tests/fixtures/move-lane-2026-10-18/pane332/
#   watcher-68693-move1.txt, watcher-77512-move2.txt — the two watchers' own journals ($TMPDIR logs)
#   handoffs-rows.jsonl — ~/.claude/logs/handoffs.jsonl:780-784 and :889-895
#   history-exit.jsonl  — the two `/exit` prompts history.jsonl recorded for 2e9ed9f2
# Case 1 re-reads the ordering FROM the record; 2 and 3 replay each REAL journal through the fixed
# hold, the foreground's held-load call at 03:41:08 and 07:24:33 (memory control-must-replay-the-real-
# artifact). RED on origin/main (2a636f1b8): 2 and 3 (the hold kills the watcher). 1 is the record and
# passes everywhere.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$REPO/scripts/handoff-fire.sh}"
  FX="$REPO/tests/fixtures/move-lane-2026-10-18/pane332"
  HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  HOME="$(cd "$HOME" && pwd -P)"; export HOME
  # HERMETICITY (land ratchet): no live machine load, and no seam resolves outside the test dir.
  export CC_ADMIT_GATE=off CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  unset WATCHER_PID RECYCLE_AWAIT HF_RECYCLE_ATTEMPT 2>/dev/null || true
  FUNCS="$BATS_TEST_TMPDIR/funcs.sh"
  local f
  {
    grep '^_iso_now() {' "$HF"
    grep '^kt() {' "$HF"
    for f in _under_test emit_recycle_event hf_bounded hf_bounded_s kt_window_field hf_lr_script \
             hf_recycle_lock_dir _hf_lstart _hf_lock_raw _hf_lock_field _hf_lock_holder_alive \
             hf_recycle_lock_write hf_recycle_lock_take hf_recycle_lock_release hf_recycle_lock_acquire \
             hf_recycle_watcher_committed hf_recycle_disarm hf_recycle_unconfirm hf_recycle_hold; do
      sed -n "/^$f() {/,/^}/p" "$HF"
    done
  } > "$FUNCS"
  bash -n "$FUNCS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$FUNCS"
  export HF_DIR="$REPO/scripts" HF_TIMEOUT_S="" HF_TIMEOUT_BIN="" HF_RECYCLE_LOCK_GATE=on
  export LR_LOCKS_DIR="$BATS_TEST_TMPDIR/locks"
  # The source the move had transplanted: the hold owes an unconfirm, and lr-transplant refused it
  # (rc 2, source-dead) both times. The stub records whether it was asked at all.
  CALLS="$BATS_TEST_TMPDIR/calls.log"; : > "$CALLS"; export CALLS
  printf '#!/usr/bin/env bash\nprintf "transplant %%s\\n" "$*" >> "$CALLS"\nexit 2\n' > "$BATS_TEST_TMPDIR/lr-transplant.sh"
  chmod +x "$BATS_TEST_TMPDIR/lr-transplant.sh"
  export HF_LR_TRANSPLANT="$BATS_TEST_TMPDIR/lr-transplant.sh"
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  SID=332 CMD="relaunch-cmd" RCY_REMOTE=1 RCY_TRANSPLANTED_SOURCE=1
  # shellcheck disable=SC2034
  RCY_TS_SID="2e9ed9f2-9e21-4161-a0f7-10b329ade8f0" HF_TS_CFG="$HOME/.claude-next" HF_TS_TO="$HOME/.claude-tertiary"
  # shellcheck disable=SC2034  # recycle_fire's locals (dynamic scope)
  tty=/dev/ttys002 cmdfile="$BATS_TEST_TMPDIR/handoff-recycle-cmd-332"
  sleep 300 >/dev/null 2>&1 3>&- & WATCHER_PID=$!
  echo "$WATCHER_PID" > "$BATS_TEST_TMPDIR/watcher.pid"
  export WATCHER_PID
  hf_recycle_lock_acquire "$SID"
  hf_recycle_lock_write "$HF_RECYCLE_LOCK" watcher "$WATCHER_PID"
}

teardown() {
  [ -f "$BATS_TEST_TMPDIR/watcher.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/watcher.pid")" 2>/dev/null || true; }
  return 0
}

epoch() { TZ=UTC date -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s; }
row_ts() { jq -r --arg c "$1" --arg w "$2" 'select(.class == $c and .target_pane == "332" and (.watcher_pid|tostring) == $w) | .ts' "$FX/handoffs-rows.jsonl" | head -1; }
rows_of() { grep "\"class\":\"$1\"" "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; }

@test "1 the record: each /exit was typed after the watcher armed and BEFORE the foreground's hold, whose source was already dead" {
  local w t_int t_exit t_hold i
  i=0
  for w in 68693 77512; do
    i=$((i + 1))
    t_int="$(jq -r 'select(.class == "recycle-intent" and .target_pane == "332") | .ts' "$FX/handoffs-rows.jsonl" | sed -n "${i}p")"
    t_exit="$(( $(sed -n "${i}p" "$FX/history-exit.jsonl" | jq -r .timestamp) / 1000 ))"
    t_hold="$(row_ts recycle-held-load "$w")"
    [ -n "$t_int" ] || { echo "watcher $w: no intent row"; false; }
    [ -n "$t_hold" ] || { echo "watcher $w: no held-load row"; false; }
    # intent < typed /exit < the hold: the foreground had not reached its own /exit (it held first).
    [ "$(epoch "$t_int")" -lt "$t_exit" ] || { echo "watcher $w: /exit not after the intent: $t_int $t_exit"; false; }
    [ "$t_exit" -lt "$(epoch "$t_hold")" ] || { echo "watcher $w: /exit not before the hold: $t_exit $t_hold"; false; }
    # The hold's unconfirm was refused: the session had already exited under it.
    jq -r --arg w "$w" 'select(.class == "recycle-held-load" and (.watcher_pid|tostring) == $w) | .detail' "$FX/handoffs-rows.jsonl" | grep -q 'unconfirm rc 2$'
    # And the watcher had confirmed the shell and started typing before the hold.
    grep -q 'CONFIRMED at a shell prompt' "$FX/watcher-$w-"*.txt
    [ "$(epoch "$(row_ts recycle-type-attempt "$w")")" -lt "$(epoch "$t_hold")" ]
  done
  # Move 2 stranded: a disarm line and no relaunch line in its journal.
  grep -q 'line=disarm' "$FX/watcher-77512-move2.txt"
  ! grep -q 'line=cmd' "$FX/watcher-77512-move2.txt"
}

@test "2 [RED] move 2 (07:24:33Z) replayed: the hold meets watcher 77512's real journal and leaves it to type the relaunch" {
  export HF_RCY_WATCHER_LOG="$FX/watcher-77512-move2.txt"
  RCY_CONFIRM_RAN=1 run hf_recycle_hold load "load 15.72/core is above the 8/core bound" "load 15.72/core is above the 8/core bound; re-run once the load falls"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
  kill -0 "$WATCHER_PID" 2>/dev/null || { echo "watcher killed between its disarm line and its relaunch line, as at 07:24:33Z"; false; }
  [ ! -s "$CALLS" ] || { echo "unconfirmed under the relaunch:"; cat "$CALLS"; false; }
  [ -z "$(rows_of recycle-held-load)" ]
  rows_of recycle-disarm-refused-committed | grep -q 'CONFIRMED at a shell prompt after 125s' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

@test "3 [RED] move 1 (03:41:08Z) replayed: an engaged watcher's journal turns the false STRANDED hold into a stand-aside" {
  export HF_RCY_WATCHER_LOG="$FX/watcher-68693-move1.txt"
  RCY_CONFIRM_RAN=1 run hf_recycle_hold load "load 28.09/core is above the 8/core bound" "load 28.09/core"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
  [[ "$output" != *"(held: load)"* ]] || { echo "a (held: load) line, which lr-handoff turns into STRANDED: $output"; false; }
  [ -z "$(rows_of recycle-held-load)" ]
  [ ! -s "$CALLS" ]
}
