#!/usr/bin/env bats
# A HOLD MUST NOT KILL A WATCHER THAT HAS COMMITTED (lr-wake 2026-10-18,
# docs/research/lr-wake-incident-2026-10-18/REPORT.md Wave A, RC1). Pane 332 at 07:24:22-33Z: the
# watcher had confirmed the shell and typed the disarm line when the foreground's load hold ran
# hf_recycle_disarm, a bare kill, one line short of the relaunch; panes 20, 21, 22 and 24 logged the
# same "CONFIRMED at a shell prompt — typing relaunch" with no relaunch after it, and the watchers of
# 20, 22 and 242 were answering the background-work dialog. Every hold also ran the slow unconfirm
# BEFORE the disarm, and said "The session stays alive" with claude gone.
#
# Driven through the extracted recycle_fire_commit / hf_recycle_hold / hf_recycle_disarm over stubs,
# as tests/handoff-recycle-load-hold.bats does. The watcher is a real process, so a kill is real; its
# journal is a file (HF_RCY_WATCHER_LOG, what the foreground exports at the detach).
#
# RED on origin/main (2a636f1b8): 1, 2, 3, 4 and 5. 6 is the control and passes before the fix.
# Mutants, one per site: drop the hf_recycle_watcher_committed test in hf_recycle_disarm (3 red) ·
# drop it in hf_recycle_hold (1, 2 red) · move the disarm back below the unconfirm (4 red) · make the
# liveness sentence unconditional (5 red).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$REPO/scripts/handoff-fire.sh}"
  HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  HOME="$(cd "$HOME" && pwd -P)"; export HOME
  # HERMETICITY (land ratchet): no live machine load, and no seam resolves outside the test dir.
  export CC_ADMIT_GATE=off CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$BATS_TEST_TMPDIR/deploy-repo"
  export CC_SESSIONS_DIRS="$BATS_TEST_TMPDIR/sessions"; mkdir -p "$CC_SESSIONS_DIRS"
  unset WATCHER_PID HF_RECYCLE_ATTEMPT HF_WATCHER_IS_JOB HF_PS_SNAPSHOT CC_TERM CC_TERM_KITTY_TO \
        HF_EXIT_READBACK HF_EXIT_ACTUATOR HF_RECYCLE_HOLD_LOAD_PER_CORE CC_GATE_MAX_LOAD_PER_CORE \
        RECYCLE_AWAIT RCY_SUBJECT_PID RCY_SUBJECT_LSTART 2>/dev/null || true

  FUNCS="$BATS_TEST_TMPDIR/funcs.sh"
  local f
  {
    grep '^_iso_now() {' "$HF"
    grep '^kt() {' "$HF"
    for f in _under_test emit_recycle_event hf_bounded hf_bounded_s kt_window_field composer_content \
             recycle_composer_gate hf_lr_script hf_recycle_fenced hf_recycle_lock_dir _hf_lstart \
             _hf_lock_raw _hf_lock_field _hf_lock_holder_alive hf_recycle_lock_write hf_recycle_lock_take \
             hf_recycle_lock_release hf_recycle_lock_acquire hf_recycle_watcher_committed hf_recycle_disarm \
             hf_wake_guard hf_recycle_unconfirm hf_recycle_hold hf_recycle_last_read hf_exit_readback \
             recycle_fire_commit composer_residue_dir composer_residue_record pid_is_cc hf_succ_mode \
             hf_succ_ours_staged write_teardown_marker hf_exit_signal_pin hf_exit_signal hf_exit_signal_grace hf_tdev_name hf_ps_on_tty \
             hf_load_per_core hf_recycle_load_bound hf_recycle_load_gate \
             hf_recycle_subject_pin hf_recycle_subject_gone hf_recycle_subject_yield; do
      sed -n "/^$f() {/,/^}/p" "$HF"
    done
  } > "$FUNCS"
  bash -n "$FUNCS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$FUNCS"
  grep -q '^recycle_fire_commit() {' "$FUNCS" || { echo "recycle_fire_commit not extracted" >&2; return 1; }

  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  CALLS="$BATS_TEST_TMPDIR/calls.log"; : > "$CALLS"
  READS="$STUB/reads"; : > "$READS"
  export CALLS READS
  cat > "$STUB/it2" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "session send") printf 'send %q\n' "${!#}" >> "$CALLS" ;;
  "session read")
    c="$(head -n 1 "$READS")"
    [ "$(wc -l < "$READS" | tr -d ' ')" -gt 1 ] && { tail -n +2 "$READS" > "$READS.t"; mv "$READS.t" "$READS"; }
    printf 'history\n────────────────────\n❯ %s\n────────────────────\n' "$c" ;;
esac
exit 0
SH
  # The unconfirm's CLI: records each call and whether the watcher was still alive when it ran.
  cat > "$STUB/lr-transplant.sh" <<'SH'
#!/usr/bin/env bash
a=0; kill -0 "${WATCHER_PID:-0}" 2>/dev/null && a=1
printf 'transplant %s watcher-alive=%s\n' "$*" "$a" >> "$CALLS"
exit 0
SH
  # shellcheck disable=SC2016  # the stub's own $1 and $CALLS, expanded when it runs
  printf '#!/usr/bin/env bash\nprintf "sleep %%s\\n" "$1" >> "$CALLS"\n' > "$STUB/sleep"
  chmod +x "$STUB/it2" "$STUB/sleep" "$STUB/lr-transplant.sh"
  # shellcheck disable=SC2329  # stubs, invoked by the extracted functions under test
  _hf_resume_debt() { printf 'debt %s\n' "$*" >> "$CALLS"; }
  # shellcheck disable=SC2329
  as_write() { printf 'as_write %q\n' "$2" >> "$CALLS"; }
  # shellcheck disable=SC2329
  as_write_transports() { echo stub; }
  export HF_SLEEP="$STUB/sleep" HF_DIR="$REPO/scripts" HF_TIMEOUT_S="" HF_TIMEOUT_BIN=""
  export HF_LR_TRANSPLANT="$STUB/lr-transplant.sh"
  export HF_KERN_WAKETIME=1 HF_RECYCLE_LOCK_GATE=on LR_LOCKS_DIR="$BATS_TEST_TMPDIR/locks"
  export CC_PANE_SUCCESSOR_DIR="$BATS_TEST_TMPDIR/succ"; mkdir -p "$CC_PANE_SUCCESSOR_DIR"
  # shellcheck disable=SC1091
  . "$REPO/lib/pane-successor.sh"
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  SID=332 CMD="relaunch-cmd" RCY_IT2="$STUB/it2" RCY_REMOTE=0 RCY_SAME_ACCOUNT=0 RCY_REST_PROVEN=0
  # shellcheck disable=SC2034
  RCY_TRANSPLANTED_SOURCE=0 RCY_TRANSPLANT_CAUSE="" RESUME_LAUNCHER="lr-launch.sh" RESUME_CFG="$HOME/.claude-next" RCY_SOURCE_SESSION=""
  # shellcheck disable=SC2034  # the operands an unconfirm hands lr-transplant
  RCY_TS_SID="2e9ed9f2-0000-4000-8000-000000000332" HF_TS_CFG="$HOME/.claude-next" HF_TS_TO="$HOME/.claude-tertiary"
  SESS="2e9ed9f2-0000-4000-8000-000000000332"
  # shellcheck disable=SC2034  # recycle_fire's locals, read by the functions under test (dynamic scope)
  tty=/dev/ttys999 cmdfile="$BATS_TEST_TMPDIR/handoff-recycle-cmd-332"
  : > "$cmdfile"
  sleep 300 >/dev/null 2>&1 3>&- & WATCHER_PID=$!
  echo "$WATCHER_PID" > "$BATS_TEST_TMPDIR/watcher.pid"
  export WATCHER_PID
  hf_recycle_lock_acquire "$SID"
  hf_recycle_lock_write "$HF_RECYCLE_LOCK" watcher "$WATCHER_PID"
  export HF_RCY_WATCHER_LOG="$BATS_TEST_TMPDIR/watcher.log"
  printf '%s\n' "→ armed: __recycle pid=$WATCHER_PID pgid=$WATCHER_PID sid=$SID tty=$tty caller=none" \
    "→ pane_proof: __recycle reached pane $SID" > "$HF_RCY_WATCHER_LOG"
  printf '%s\n' "" "/exit" > "$READS"
}

teardown() {
  [ -f "$BATS_TEST_TMPDIR/watcher.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/watcher.pid")" 2>/dev/null || true; }
  return 0
}

rows_of() { grep "\"class\":\"$1\"" "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; }
# The watcher's journal, as pane 332's watcher 77512 wrote it at 07:24:22Z.
journal_committed() { echo "→ pane $SID CONFIRMED at a shell prompt after 125s — typing relaunch" >> "$HF_RCY_WATCHER_LOG"; }

# Neither killed nor unconfirmed, and nothing was typed.
assert_left_alone() {
  kill -0 "$WATCHER_PID" 2>/dev/null || { echo "the watcher was killed"; false; }
  ! grep -q '^transplant --phase unconfirm' "$CALLS" || { echo "unconfirmed under the relaunch:"; cat "$CALLS"; false; }
  ! grep -q '^send' "$CALLS" || { echo "a keystroke was sent:"; cat "$CALLS"; false; }
  [ -d "$HF_RECYCLE_LOCK" ] || { echo "the watcher's pane lock was released"; false; }
  [ -n "$(rows_of recycle-disarm-refused-committed)" ] || { cat "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; false; }
}

@test "1 [RED] pane 332: the journal says CONFIRMED and the load gate holds — no kill, no held-load, rc 0" {
  journal_committed
  CC_FIRE_CAPACITY_GATE=on HF_LOAD_PER_CORE=30 run recycle_fire_commit "$SESS"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  assert_left_alone
  [ -z "$(rows_of recycle-held-load)" ] || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [[ "$output" != *"/exit NOT submitted"* ]] || { echo "$output"; false; }
  [[ "$output" == *"the watcher owns the relaunch"* ]] || { echo "$output"; false; }
  [[ "$output" == *"recycle NOT held (load)"* ]] || { echo "not the load hold: $output"; false; }
}

@test "2 [RED] a hold that owes an unconfirm leaves a committed watcher's source alone (type-attempt in the journal)" {
  echo "2026-10-18T07:24:22Z type-attempt pane=$SID attempt=1 rc=0" >> "$HF_RCY_WATCHER_LOG"
  RCY_CONFIRM_RAN=1 run hf_recycle_hold load "load 15.72/core is above the 8/core bound" "load 15.72/core"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
  assert_left_alone
}

@test "3 [RED] every bare disarm site is guarded: the dialog being answered (bgwork@) refuses the kill" {
  echo "→ bgwork@139s: the /exit raised the background-work dialog; stop-if-watcher answered '1' (Exit and stop tasks)" >> "$HF_RCY_WATCHER_LOG"
  hf_recycle_disarm
  kill -0 "$WATCHER_PID" 2>/dev/null || { echo "the watcher was killed"; false; }
  [ -d "$HF_RECYCLE_LOCK" ] || { echo "the watcher's pane lock was released"; false; }
  rows_of recycle-disarm-refused-committed | grep -q 'bgwork@139s' || { cat "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; false; }
}

@test "4 [RED] a hold before the commit: exit-aborted first, the disarm BEFORE the slow unconfirm" {
  RCY_CONFIRM_RAN=1 run hf_recycle_hold load "load 8.72/core is above the 8/core bound" "load 8.72/core"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  [ -s "$cmdfile.exit-aborted" ] || { echo "no exit-aborted marker"; ls "$BATS_TEST_TMPDIR"; false; }
  ! kill -0 "$WATCHER_PID" 2>/dev/null || { echo "watcher still armed"; false; }
  grep -q '^transplant --phase unconfirm.* watcher-alive=0$' "$CALLS" || { echo "the unconfirm ran with the watcher alive:"; cat "$CALLS"; false; }
}

@test "5 [RED] 'The session stays alive' only when the pane reads cc" {
  # shellcheck disable=SC2329  # the pane probe the hold reads
  pane_cc_state() { printf shell; }
  run hf_recycle_hold load "load 28.09/core is above the 8/core bound" "load 28.09/core"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  [[ "$output" != *"The session stays alive"* ]] || { echo "$output"; false; }
  [[ "$output" == *"unconfirm rc n/a. The session is NOT running"* ]] || { echo "$output"; false; }
  setup
  # shellcheck disable=SC2329
  pane_cc_state() { printf cc; }
  run hf_recycle_hold load "load 28.09/core is above the 8/core bound" "load 28.09/core"
  [[ "$output" == *"unconfirm rc n/a. The session stays alive."* ]] || { echo "$output"; false; }
}

@test "6 CONTROL a journal with no commit in it: the hold kills the watcher and releases its lock, as before" {
  CC_FIRE_CAPACITY_GATE=on HF_LOAD_PER_CORE=30 run recycle_fire_commit "$SESS"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  ! kill -0 "$WATCHER_PID" 2>/dev/null || { echo "watcher still armed"; false; }
  [ -n "$(rows_of recycle-held-load)" ] || { cat "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; false; }
  [ -z "$(rows_of recycle-disarm-refused-committed)" ]
}
