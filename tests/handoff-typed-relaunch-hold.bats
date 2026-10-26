#!/usr/bin/env bats
# THE TYPED-RELAUNCH HOLD, RE-KEYED (docs/plans/LR_SUSTAINED_LOAD_IMPL.md § W12b; G2 R8; REPORT §3.3).
# Under the operator's 15-40/core band the 24/20 load hold never releases, so a move whose successor
# stage was refused held HELD:load for good. Three levers, each driven here through recycle_fire_commit
# over stubs (extracted as tests/handoff-recycle-load-hold.bats does; a full recycle_fire needs a real
# tty holding a real claude), with the load stubbed through its seam HF_LOAD_PER_CORE:
#   1. the stage retry: a refused stage is asked once more (watcher lstart re-read, bounded) before the
#      commit-time hold, and a staged relaunch is exempt from it;
#   2. the key: ~/.reso/limit-recover/typed-relaunch-hold.mode, `load` (code default, today's bytes) or
#      `terminal` (a 2 s `kitty @ ls --match id:<P>` plus kitty's main thread at band ≥ 31 over 3
#      samples; otherwise `(held: unreachable)`, which the reconciler retries as TRANSIENT);
#   3. a held-load-after-confirm count in the hold's row.
#
# RED-proof on the parent (c85b7063b), measured: all 9 fail. 1, 2 and 5 hold HELD:load at 25/40 per
# core (no retry, no terminal key); 3 has no count; 6 holds on load, never unreachable; 9's floor does
# not exist. 4, 7 and 8 are behavioural controls (held, no actuator, the same operator line in both
# arms) and fail there only on lever 3's row suffix. Mutants, run on scratch copies via HF_OVERRIDE,
# measured red: drop the gate's two retry calls (1 2 3 4 6 7 8) · ignore the mode file in
# hf_typed_relaunch_hold_mode (5 6 7) · hf_terminal_responsive `return 0` first (5 6 8) · call
# hf_kitty_band without the floor (6) · ignore stage-retry.off (4) · drop the count increment (3).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$REPO/scripts/handoff-fire.sh}"
  [ -f "$BATS_TEST_TMPDIR/watcher.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/watcher.pid")" 2>/dev/null || true; }
  rm -rf "${BATS_TEST_TMPDIR:?}/home" "${BATS_TEST_TMPDIR:?}/locks" "${BATS_TEST_TMPDIR:?}/succ" "${BATS_TEST_TMPDIR:?}/lr" "${BATS_TEST_TMPDIR:?}/stub"
  HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  HOME="$(cd "$HOME" && pwd -P)"; export HOME
  # HERMETICITY (land ratchet): no live machine load, and no seam resolves outside the test dir.
  export CC_ADMIT_GATE=off CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$BATS_TEST_TMPDIR/deploy-repo"
  export CC_SESSIONS_DIRS="$BATS_TEST_TMPDIR/sessions"; mkdir -p "$CC_SESSIONS_DIRS"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/recon" TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$LR_STATE_DIR" "$TMPDIR"
  unset WATCHER_PID HF_RECYCLE_ATTEMPT HF_WATCHER_IS_JOB HF_PS_SNAPSHOT CC_TERM CC_TERM_KITTY_TO KITTY_WINDOW_ID \
        KITTY_LISTEN_ON HF_EXIT_READBACK HF_EXIT_ACTUATOR HF_RECYCLE_HOLD_LOAD_PER_CORE CC_GATE_MAX_LOAD_PER_CORE \
        HF_TYPED_RELAUNCH_HOLD HF_STAGE_RETRY_GATE HF_STAGE_RETRIED HF_KID_KPID CC_TERM_KITTY_PID HF_KID_PS_BIN \
        CC_KITTY_BIN CC_TERM_KITTY 2>/dev/null || true

  FUNCS="$BATS_TEST_TMPDIR/funcs.sh"
  local f
  {
    grep '^_iso_now() {' "$HF"
    grep '^kt() {' "$HF"
    grep '^in_kitty() {' "$HF"
    grep '^kitty_identity() {' "$HF"
    for f in _under_test emit_recycle_event hf_bounded hf_bounded_s kt_window_field composer_content \
             recycle_composer_gate hf_lr_script hf_recycle_fenced hf_recycle_lock_dir _hf_lstart \
             _hf_lock_raw _hf_lock_field _hf_lock_holder_alive hf_recycle_lock_write hf_recycle_lock_take \
             hf_recycle_lock_release hf_recycle_lock_acquire hf_recycle_watcher_committed hf_recycle_disarm hf_wake_guard \
             hf_recycle_unconfirm hf_recycle_hold hf_recycle_last_read hf_exit_readback recycle_fire_commit \
             composer_residue_dir composer_residue_record pid_is_cc hf_succ_mode hf_succ_ours_staged \
             hf_succ_lib_load hf_succ_stage \
             write_teardown_marker hf_exit_signal_pin hf_exit_signal hf_exit_signal_grace hf_tdev_name hf_ps_on_tty \
             hf_load_per_core hf_recycle_load_bound hf_recycle_load_gate \
             hf_typed_relaunch_hold_mode hf_terminal_responsive hf_succ_stage_retry hf_kitty_band \
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
  export CALLS READS STUB
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
  # kitty: logs its argv; answers per $STUB/kitty.rc (0 by default), after $STUB/kitty.sleep seconds.
  cat > "$STUB/kitty" <<'SH'
#!/usr/bin/env bash
printf 'kitty %s\n' "$*" >> "$CALLS"
[ -f "$STUB/kitty.sleep" ] && /bin/sleep "$(cat "$STUB/kitty.sleep")"
exit "$(cat "$STUB/kitty.rc" 2>/dev/null || echo 0)"
SH
  # ps -M: kitty's main thread at the PRI in $STUB/band (47 by default), the shape `ps -M -p` prints.
  cat > "$STUB/ps" <<'SH'
#!/usr/bin/env bash
printf 'ps %s\n' "$*" >> "$CALLS"
# The devname-free per-tty read, `-axo tdev=,<field>`: this world's one process is kitty (pid 610),
# on no terminal, so no pane tty holds anything.
case "$*" in
  "-axo tdev=,comm="|"-axo tdev=,command=") printf '?? /Applications/kitty.app/Contents/MacOS/kitty\n'; exit 0 ;;
  "-axo tdev=,"*) printf '?? 610\n'; exit 0 ;;
esac
printf 'USER   PID   TT  %%CPU STAT PRI     STIME     UTIME COMMAND\n'
printf 'chris  610   ??   1.0 S    %sT  0:01.00   0:02.00 /Applications/kitty.app/Contents/MacOS/kitty\n' "$(cat "$STUB/band" 2>/dev/null || echo 47)"
SH
  # shellcheck disable=SC2016  # the stub's own $1 and $CALLS, expanded when it runs
  printf '#!/usr/bin/env bash\nprintf "sleep %%s\\n" "$1" >> "$CALLS"\n' > "$STUB/sleep"
  chmod +x "$STUB/it2" "$STUB/sleep" "$STUB/kitty" "$STUB/ps"
  _hf_resume_debt() { printf 'debt %s\n' "$*" >> "$CALLS"; }
  as_write() { printf 'as_write %q\n' "$2" >> "$CALLS"; }
  as_write_transports() { echo stub; }
  # shellcheck disable=SC2329  # read by hf_succ_stage (fresh mode): the target account's config dir
  config_dir_for_launcher() { printf '%s\n' "$BATS_TEST_TMPDIR/cfg"; }
  export HF_SLEEP="$STUB/sleep" HF_DIR="$REPO/scripts" HF_TIMEOUT_S="" HF_TIMEOUT_BIN=""
  export HF_KERN_WAKETIME=1 HF_RECYCLE_LOCK_GATE=on LR_LOCKS_DIR="$BATS_TEST_TMPDIR/locks"
  export CC_PANE_SUCCESSOR_DIR="$BATS_TEST_TMPDIR/succ"; mkdir -p "$CC_PANE_SUCCESSOR_DIR"
  # shellcheck disable=SC1091
  . "$REPO/lib/pane-successor.sh"
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  SID=901 CMD="relaunch-cmd" RCY_IT2="$STUB/it2" RCY_REMOTE=0 RCY_SAME_ACCOUNT=0 RCY_REST_PROVEN=0 LAUNCHER=claude-next
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  RCY_TRANSPLANTED_SOURCE=0 RCY_TRANSPLANT_CAUSE="" RESUME_LAUNCHER="" RESUME_CFG="" RCY_SOURCE_SESSION=""
  SESS="a1b2c3d4-0000-4000-8000-000000000003"
  # shellcheck disable=SC2034  # recycle_fire's locals, read by recycle_fire_commit (dynamic scope)
  tty=/dev/ttys999 cmdfile="$BATS_TEST_TMPDIR/rcy.cmd"
  sleep 300 >/dev/null 2>&1 3>&- & WATCHER_PID=$!
  echo "$WATCHER_PID" > "$BATS_TEST_TMPDIR/watcher.pid"
  export WATCHER_PID
  hf_recycle_lock_acquire "$SID"
  hf_recycle_lock_write "$HF_RECYCLE_LOCK" watcher "$WATCHER_PID"
  printf '%s\n' "" "/exit" > "$READS"
}

teardown() {
  [ -f "$BATS_TEST_TMPDIR/watcher.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/watcher.pid")" 2>/dev/null || true; }
  return 0
}

stage_ours() {
  printf 'relaunch-cmd\n' > "$CC_PANE_SUCCESSOR_DIR/ttys999.cmd"
  printf '{"pane":"%s","pane_tty":"%s","watcher_pid":%s,"mode":"fresh"}\n' "$SID" "$tty" "$WATCHER_PID" \
    > "$CC_PANE_SUCCESSOR_DIR/ttys999.json"
}
# A stub stage: refuses the first $1 calls (the "no readable start time" refusal), then stages ours.
stub_stage_refusing() {
  printf '%s\n' "$1" > "$STUB/stage.refusals"
  # shellcheck disable=SC2329  # replaces the extracted hf_succ_stage; called by the retry
  hf_succ_stage() {
    local left; left="$(cat "$STUB/stage.refusals")"
    printf 'stage %s\n' "$1" >> "$CALLS"
    if [ "$left" -gt 0 ]; then
      printf '%s\n' "$((left - 1))" > "$STUB/stage.refusals"
      echo "⚠ successor: watcher $WATCHER_PID has no readable start time — not staged; typed relaunch" >&2
      return 1
    fi
    stage_ours
  }
}
kitty_world() { # a kitty pane whose verified socket and pid are known; the stubs answer
  # shellcheck disable=SC2034  # read by kitty_identity / hf_terminal_responsive
  CC_TERM=kitty CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/kitty-610" CC_KITTY_BIN="$STUB/kitty" HF_KID_KPID=610 HF_KID_PS_BIN="$STUB/ps"
  export CC_TERM CC_TERM_KITTY_TO CC_KITTY_BIN HF_KID_KPID HF_KID_PS_BIN
}
mode_file() { printf '%s' "$1" > "$LR_STATE_DIR/typed-relaunch-hold.mode"; }
rows_of() { grep "\"class\":\"$1\"" "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; }
sends_exit() { grep -cxF -- "send /exit" "$CALLS" || true; }
commit_at() { CC_FIRE_CAPACITY_GATE=on HF_LOAD_PER_CORE="$1" run recycle_fire_commit "$SESS"; }
TODAY_25="load 25.00/core is above the 24/core bound and the relaunch would have to be typed (fresh recycle, no successor of ours staged for /dev/ttys999)"

assert_proceeded() {
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  [ "$(sends_exit)" = 1 ] || { cat "$CALLS"; false; }
  [ -z "$(rows_of recycle-held-load)" ] || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [ -z "$(rows_of recycle-held-unreachable)" ] || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}
assert_no_actuator() {
  [ "$status" -eq 1 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  ! grep -q '^send' "$CALLS" || { echo "a keystroke was sent:"; cat "$CALLS"; false; }
  ! grep -q '^debt' "$CALLS" || { echo "the resume debt opened:"; cat "$CALLS"; false; }
  ! kill -0 "$WATCHER_PID" 2>/dev/null || { echo "watcher still armed"; false; }
}

@test "1 [RED] stage retry: a stage refused once, at 25/core, is retried and staged — the move proceeds, no HELD:load" {
  stub_stage_refusing 1
  hf_succ_stage "$tty" "$cmdfile" 2>/dev/null && false   # the recycle's own first stage, refused
  commit_at 25.00
  assert_proceeded
  [ "$(grep -c '^stage ' "$CALLS")" -eq 2 ] || { cat "$CALLS"; false; }
  rows_of recycle-stage-retried | grep -q "staged on the retry" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

@test "2 [RED] stage retry, the real hf_succ_stage: the watcher's lstart is re-read and the stage written names it" {
  commit_at 25.00
  assert_proceeded
  [ -f "$CC_PANE_SUCCESSOR_DIR/ttys999.cmd" ] || { ls -la "$CC_PANE_SUCCESSOR_DIR"; echo "$output"; false; }
  wl="$(jq -r '.watcher_lstart // empty' "$CC_PANE_SUCCESSOR_DIR/ttys999.json")"
  [ -n "$wl" ] && [ "$(jq -r '.watcher_pid' "$CC_PANE_SUCCESSOR_DIR/ttys999.json")" = "$WATCHER_PID" ] \
    || { cat "$CC_PANE_SUCCESSOR_DIR/ttys999.json"; false; }
  rows_of recycle-stage-retried | grep -qF "lstart $wl" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

@test "3 [RED] a retry refused again holds HELD:load, once per recycle, and the row counts held-load-after-confirm (1, then 2)" {
  stub_stage_refusing 9
  commit_at 25.00
  assert_no_actuator
  [[ "$output" == *"recycle ABORTED before /exit (held: load)"* ]] || { echo "$output"; false; }
  rows_of recycle-held-load | grep -qF "$TODAY_25; held_load_after_confirm=1 stage_retry=refused" \
    || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [ "$(grep -c '^stage ' "$CALLS")" -eq 1 ] || { cat "$CALLS"; false; }
  [ "$(cat "$LR_STATE_DIR/held-load-after-confirm.count")" = 1 ] || false
  # a second recycle on the same box: the count runs on
  setup; stub_stage_refusing 9
  printf '1\n' > "$LR_STATE_DIR/held-load-after-confirm.count"
  commit_at 25.00
  rows_of recycle-held-load | grep -q "held_load_after_confirm=2 stage_retry=refused" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  # within ONE recycle the retry is spent: a second gate call does not stage again
  HF_STAGE_RETRIED=1 hf_succ_stage_retry "$tty" && false
  [ "$HF_STAGE_RETRY" = spent ] || { echo "HF_STAGE_RETRY=$HF_STAGE_RETRY"; false; }
}

@test "4 kill switch: stage-retry.off holds as today and never asks the stage again (stage_retry=off)" {
  stub_stage_refusing 1
  touch "$LR_STATE_DIR/stage-retry.off"
  commit_at 25.00
  assert_no_actuator
  rows_of recycle-held-load | grep -qF "$TODAY_25; held_load_after_confirm=1 stage_retry=off" \
    || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  ! grep -q '^stage ' "$CALLS" || { cat "$CALLS"; false; }
  # the env form is the same switch
  setup; stub_stage_refusing 1
  HF_STAGE_RETRY_GATE=off commit_at 25.00
  ! grep -q '^stage ' "$CALLS" || { cat "$CALLS"; false; }
}

@test "5 [RED] mode terminal (the FILE), a responsive kitty at 40/core: proceeds — one bounded ls on the verified socket, 3 band samples" {
  stub_stage_refusing 9
  kitty_world; mode_file terminal
  commit_at 40.00
  assert_proceeded
  grep -qxF "kitty @ --to unix:$BATS_TEST_TMPDIR/kitty-610 ls --match id:901" "$CALLS" || { cat "$CALLS"; false; }
  [ "$(grep -c '^ps -M -p 610$' "$CALLS")" -eq 3 ] || { cat "$CALLS"; false; }
  ! grep -q '^stage ' "$CALLS" || { echo "a responsive terminal needs no stage retry"; cat "$CALLS"; false; }
}

@test "6 [RED] mode terminal: a kitty that does not answer, answers too late, or sits below band 31 holds unreachable (TRANSIENT), never HELD:load" {
  stub_stage_refusing 9
  kitty_world; mode_file terminal
  printf 1 > "$STUB/kitty.rc"
  commit_at 40.00
  assert_no_actuator
  [[ "$output" == *"recycle ABORTED before /exit (held: unreachable): terminal not responsive: 'kitty @ ls --match id:901'"*"did not answer within 2s (rc 1)"* ]] || { echo "$output"; false; }
  [ -z "$(rows_of recycle-held-load)" ] || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  rows_of recycle-held-unreachable | grep -q "terminal not responsive.*stage_retry=refused" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  # our own bound firing is the same hold (a retry), never a verdict
  setup; stub_stage_refusing 9; kitty_world; mode_file terminal
  printf 5 > "$STUB/kitty.sleep"
  HF_TIMEOUT_BIN="$(command -v gtimeout || command -v timeout)" HF_TR_LS_BOUND_S=1 commit_at 40.00
  assert_no_actuator
  [[ "$output" == *"(held: unreachable): terminal not responsive"*"did not answer within 1s (rc 124)"* ]] || { echo "$output"; false; }
  # a kitty that answers but whose main thread reads 20 (below 31) is not responsive either
  setup; stub_stage_refusing 9; kitty_world; mode_file terminal
  printf 20 > "$STUB/band"
  commit_at 40.00
  assert_no_actuator
  [[ "$output" == *"(held: unreachable): terminal not responsive: kitty 610's main thread is below band 31 [20 20 20]"* ]] || { echo "$output"; false; }
  [ -z "$(rows_of recycle-held-load)" ] || false
}

@test "7 mode load: today's bytes — no file, a file reading load, and load beating an env terminal all hold the same pinned line" {
  stub_stage_refusing 9
  commit_at 25.00; a="${output//$WATCHER_PID/W}"
  assert_no_actuator
  rows_of recycle-held-load | grep -qF "$TODAY_25; held_load_after_confirm=1 stage_retry=refused" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  setup; stub_stage_refusing 9; kitty_world; mode_file load
  HF_TYPED_RELAUNCH_HOLD=terminal commit_at 25.00; b="${output//$WATCHER_PID/W}"
  assert_no_actuator
  ! grep -q '^kitty ' "$CALLS" || { echo "mode load asked kitty"; cat "$CALLS"; false; }
  [ "$a" = "$b" ] || { diff <(printf '%s\n' "$a") <(printf '%s\n' "$b"); false; }
  [[ "$a" == *"recycle ABORTED before /exit (held: load): $TODAY_25; re-run once the load falls"* ]] || { echo "$a"; false; }
}

@test "8 mode terminal on a pane that is not kitty's: no resource to key on, the load comparison decides as today" {
  stub_stage_refusing 9; mode_file terminal
  commit_at 25.00
  assert_no_actuator
  rows_of recycle-held-load | grep -qF "$TODAY_25; held_load_after_confirm=1 stage_retry=refused" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  ! grep -q '^kitty ' "$CALLS" || false
}

@test "9 hf_kitty_band: the default floor is W12's (≤ 4 is low), the terminal key's is 31; junk floors take the default" {
  printf 20 > "$STUB/band"
  HF_KID_PS_BIN="$STUB/ps" hf_kitty_band 610 || false
  rc=0; HF_KID_PS_BIN="$STUB/ps" hf_kitty_band 610 31 || rc=$?
  [ "$rc" = 1 ] || { echo "rc=$rc [$HF_KITTY_BAND_READ]"; false; }
  printf 4 > "$STUB/band"
  rc=0; HF_KID_PS_BIN="$STUB/ps" hf_kitty_band 610 || rc=$?
  [ "$rc" = 1 ] || false
  printf 31 > "$STUB/band"
  HF_KID_PS_BIN="$STUB/ps" hf_kitty_band 610 31 || false
  HF_KID_PS_BIN="$STUB/ps" hf_kitty_band 610 lots || false
}
