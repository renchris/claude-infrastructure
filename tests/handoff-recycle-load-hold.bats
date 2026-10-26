#!/usr/bin/env bats
# THE LOAD HOLD (docs/research/recycle-failures-kitty-2026-10-10/REPORT.md fix 8b). F1 typed /exit at
# ~45 runnable per core, and the post-exit path then failed 16 times to TYPE the relaunch. A recycle
# whose relaunch would be typed (no successor of ours staged) holds before either exit actuator when
# load per core is above the bound; a staged successor proceeds at any load.
#
# Driven through recycle_fire_commit over stubs, extracted from the subject as
# tests/handoff-fire-recycle-custody.bats does (a full recycle_fire needs a real tty holding a real
# claude). The world is a SELF-form fresh recycle, rest not proven, so the exit actuator it reaches is
# the typed /exit, recorded by the it2 stub as `send /exit`. The load reader is stubbed through its
# seam HF_LOAD_PER_CORE; nothing here reads the machine's load.
#
# RED-proof: 1, 2 and 5 fail on the pre-fix script (origin/main a60fa9925: no hold exists, so
# `send /exit` is reached with status 0). 3 and 4 pass before the fix by design; each is the control
# for one arm of the gate. Mutants, one per case, run on a scratch copy via HF_OVERRIDE, each red on
# its case only: 3 drop the hf_succ_ours_staged arm of hf_recycle_load_gate · 4 make its awk
# comparison `exit 0` (always above) · 5 drop the `b == "off"` arm of hf_recycle_load_bound, or its
# CC_FIRE_CAPACITY_GATE line.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$REPO/scripts/handoff-fire.sh}"
  # A case that builds a second world (it calls setup again) retires the first one's watcher, lock,
  # rows and stage, so no assertion can pass on the earlier world's evidence.
  [ -f "$BATS_TEST_TMPDIR/watcher.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/watcher.pid")" 2>/dev/null || true; }
  rm -rf "${BATS_TEST_TMPDIR:?}/home" "${BATS_TEST_TMPDIR:?}/locks" "${BATS_TEST_TMPDIR:?}/succ"
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
        HF_EXIT_READBACK HF_EXIT_ACTUATOR HF_RECYCLE_HOLD_LOAD_PER_CORE CC_GATE_MAX_LOAD_PER_CORE 2>/dev/null || true

  FUNCS="$BATS_TEST_TMPDIR/funcs.sh"
  local f
  {
    grep '^_iso_now() {' "$HF"
    grep '^kt() {' "$HF"
    for f in _under_test emit_recycle_event hf_bounded hf_bounded_s kt_window_field composer_content \
             recycle_composer_gate hf_lr_script hf_recycle_fenced hf_recycle_lock_dir _hf_lstart \
             _hf_lock_raw _hf_lock_field _hf_lock_holder_alive hf_recycle_lock_write hf_recycle_lock_take \
             hf_recycle_lock_release hf_recycle_lock_acquire hf_recycle_watcher_committed hf_recycle_disarm hf_wake_guard \
             hf_recycle_unconfirm hf_recycle_hold hf_recycle_last_read hf_exit_readback hf_recycle_delegate_ok recycle_fire_commit \
             composer_residue_dir composer_residue_record pid_is_cc hf_succ_mode hf_succ_ours_staged \
             write_teardown_marker hf_exit_signal_pin hf_exit_signal hf_exit_signal_grace hf_tdev_name hf_ps_on_tty \
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
  # it2: `session read` serves the NEXT queued composer content (the last one repeats) inside a box.
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
  # shellcheck disable=SC2016  # the stub's own $1 and $CALLS, expanded when it runs
  printf '#!/usr/bin/env bash\nprintf "sleep %%s\\n" "$1" >> "$CALLS"\n' > "$STUB/sleep"
  chmod +x "$STUB/it2" "$STUB/sleep"
  _hf_resume_debt() { printf 'debt %s\n' "$*" >> "$CALLS"; }
  as_write() { printf 'as_write %q\n' "$2" >> "$CALLS"; }
  as_write_transports() { echo stub; }
  export HF_SLEEP="$STUB/sleep" HF_DIR="$REPO/scripts" HF_TIMEOUT_S="" HF_TIMEOUT_BIN=""
  export HF_KERN_WAKETIME=1 HF_RECYCLE_LOCK_GATE=on LR_LOCKS_DIR="$BATS_TEST_TMPDIR/locks"
  export CC_PANE_SUCCESSOR_DIR="$BATS_TEST_TMPDIR/succ"; mkdir -p "$CC_PANE_SUCCESSOR_DIR"
  # shellcheck disable=SC1091
  . "$REPO/lib/pane-successor.sh"
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  SID=901 CMD="relaunch-cmd" RCY_IT2="$STUB/it2" RCY_REMOTE=0 RCY_SAME_ACCOUNT=0 RCY_REST_PROVEN=0
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  RCY_TRANSPLANTED_SOURCE=0 RCY_TRANSPLANT_CAUSE="" RESUME_LAUNCHER="" RESUME_CFG="" RCY_SOURCE_SESSION=""
  SESS="a1b2c3d4-0000-4000-8000-000000000002"
  # shellcheck disable=SC2034  # recycle_fire's local, read by recycle_fire_commit (dynamic scope)
  tty=/dev/ttys999
  # The watcher: a real process, so the disarm's kill and the lock's identity are real too.
  sleep 300 >/dev/null 2>&1 3>&- & WATCHER_PID=$!
  echo "$WATCHER_PID" > "$BATS_TEST_TMPDIR/watcher.pid"
  export WATCHER_PID
  hf_recycle_lock_acquire "$SID"
  hf_recycle_lock_write "$HF_RECYCLE_LOCK" watcher "$WATCHER_PID"
  # The last read sees an empty box; the read-back after a typed /exit sees /exit.
  printf '%s\n' "" "/exit" > "$READS"
}

teardown() {
  [ -f "$BATS_TEST_TMPDIR/watcher.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/watcher.pid")" 2>/dev/null || true; }
  [ -f "$BATS_TEST_TMPDIR/subject.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/subject.pid")" 2>/dev/null || true; }
  return 0
}

# Our stage for the world's tty: the shape hf_succ_stage writes, naming THIS world's watcher.
stage_ours() {
  printf 'relaunch-cmd\n' > "$CC_PANE_SUCCESSOR_DIR/ttys999.cmd"
  printf '{"pane":"%s","pane_tty":"%s","watcher_pid":%s,"mode":"fresh"}\n' "$SID" "$tty" "${1:-$WATCHER_PID}" \
    > "$CC_PANE_SUCCESSOR_DIR/ttys999.json"
}
rows_of() { grep "\"class\":\"$1\"" "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; }
sends_exit() { grep -cxF -- "send /exit" "$CALLS" || true; }
# commit_at <stubbed load per core> — the commit with the capacity gate ON for this call only: setup
# pins it off (the hermeticity lint's rule 2) and off is also the hold's bypass (case 5).
commit_at() { CC_FIRE_CAPACITY_GATE=on HF_LOAD_PER_CORE="$1" run recycle_fire_commit "$SESS"; }

# The hold's whole receipt: status 1, the row, the parsable line with the re-run command, the watcher
# disarmed, and NO exit actuator reached: no keystroke, no signal row, no debt opened.
assert_held() {
  [ "$status" -eq 1 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  rows_of recycle-held-load | grep -q "load 45.00/core is above the 24/core bound" || { cat "$HOME/.claude/logs/handoffs.jsonl"; echo "$output"; false; }
  [[ "$output" == *"recycle ABORTED before /exit (held: load)"*"Re-run: relaunch-cmd"* ]] || { echo "$output"; false; }
  ! grep -q '^send' "$CALLS" || { echo "a keystroke was sent:"; cat "$CALLS"; false; }
  ! grep -q '^debt' "$CALLS" || { echo "the resume debt opened:"; cat "$CALLS"; false; }
  [ -z "$(rows_of recycle-exit-signal)" ] || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  ! kill -0 "$WATCHER_PID" 2>/dev/null || { echo "watcher still armed"; false; }
}

assert_proceeded() {
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  [ "$(sends_exit)" = 1 ] || { cat "$CALLS"; false; }
  [ -z "$(rows_of recycle-held-load)" ] || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

@test "1 [RED] load above the bound, stage refused (none staged): held as recycle-held-load, no exit actuator reached" {
  commit_at 45.00
  assert_held
  [[ "$output" == *"fresh recycle, no successor of ours staged for /dev/ttys999"* ]] || { echo "$output"; false; }
}

@test "2 [RED] load above the bound, not fresh mode, or a stage naming another watcher: both held" {
  # shellcheck disable=SC2034  # read by hf_succ_mode
  RESUME_LAUNCHER=resume-cmd
  commit_at 45.00
  assert_held
  [[ "$output" == *"(resume recycle, no successor"* ]] || { echo "$output"; false; }

  # A stage left by another watcher is not claimable for this relaunch.
  # shellcheck disable=SC2034
  RESUME_LAUNCHER=""
  setup
  stage_ours 1
  commit_at 45.00
  assert_held
}

@test "3 load above the bound with OUR successor staged: the recycle proceeds (keystroke-free relaunch)" {
  stage_ours
  commit_at 45.00
  assert_proceeded
}

@test "4 load below the bound with the stage refused: the recycle proceeds" {
  commit_at 2.00
  assert_proceeded
  # The bound is tunable, and CC_GATE_MAX_LOAD_PER_CORE (ship-land's factor) is its fallback.
  setup
  HF_RECYCLE_HOLD_LOAD_PER_CORE=50 commit_at 45.00
  assert_proceeded
  setup
  CC_GATE_MAX_LOAD_PER_CORE=50 commit_at 45.00
  assert_proceeded
}

@test "5 an unreadable load, or the hold switched off, proceeds; a junk bound takes the default 24" {
  # The capacity gate's one bypass is the hold's too (and what every recycle suite pins).
  HF_LOAD_PER_CORE=45.00 run recycle_fire_commit "$SESS"
  assert_proceeded
  setup
  commit_at ""
  assert_proceeded
  setup
  HF_RECYCLE_HOLD_LOAD_PER_CORE=off commit_at 45.00
  assert_proceeded
  setup
  HF_RECYCLE_HOLD_LOAD_PER_CORE=lots commit_at 45.00
  assert_held
}

# K2 (lr-wake 2026-10-18, docs/research/lr-wake-incident-2026-10-18/REPORT.md Wave A). Pane 332 at
# 07:24:33Z: the move's claude had already exited (the watcher had typed the disarm line) when the
# foreground reached this gate at 15.72/core and held, and the hold killed the watcher one line short
# of the relaunch. The subject is a real process pinned as recycle_fire_armed pins it, killed inside a
# stubbed last read, the step that took ~3 min at load 15-28/core. RED on origin/main (2a636f1b8): the
# gate holds (recycle-held-load, watcher killed) because nothing re-reads the subject at its call site.
@test "6 [RED] the subject exits inside the last read, then the load gate would hold: yields, the watcher lives" {
  ( sleep 300 >/dev/null 2>&1 3>&- & echo $! > "$BATS_TEST_TMPDIR/subject.pid" )
  SUBJ="$(cat "$BATS_TEST_TMPDIR/subject.pid")"
  RCY_REMOTE=1 HF_REMOTE_ROW_PID="$SUBJ" hf_recycle_subject_pin "$tty" "$SESS"
  [ "$RCY_SUBJECT_PID" = "$SUBJ" ] || { echo "subject not pinned"; false; }
  # shellcheck disable=SC2329  # the stub that replaces the extracted last read, invoked by the tail
  hf_recycle_last_read() {
    kill "$SUBJ" 2>/dev/null || true
    local n=0; while ps -p "$SUBJ" >/dev/null 2>&1 && [ "$n" -lt 40 ]; do sleep 0.05; n=$((n + 1)); done
    return 0
  }
  CC_FIRE_CAPACITY_GATE=on HF_LOAD_PER_CORE=30 run recycle_fire_commit "$SESS"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  rows_of recycle-subject-exited | grep -q "exited before the commit, noticed at the load hold" \
    || { cat "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; echo "$output"; false; }
  [ -z "$(rows_of recycle-held-load)" ] || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  ! grep -q '^send' "$CALLS" || { echo "a keystroke was sent:"; cat "$CALLS"; false; }
  kill -0 "$WATCHER_PID" 2>/dev/null || { echo "the watcher was killed"; false; }
}

# D1, THE DELEGATED FIRST /exit (docs/research/selfrecycle-latency-2026-10-26/REPORT.md). The same
# self-form commit world, now with the two inputs a real self-recycle has: the command file the
# watcher reads its markers beside, and the tool call this recycle runs inside (a live process).
# The foreground then writes exit-delegated beside exit-committed and types NOTHING; the watcher's
# half is tests/handoff-recycle-delegated-exit.bats. RED-proof: on 1a0ee3658 the first case reaches
# `send /exit` and writes no exit-delegated.
@test "D1: a self-recycle whose own call is alive writes exit-committed and exit-delegated and types nothing" {
  # shellcheck disable=SC2034  # recycle_fire's local and the detach's global, read by recycle_fire_commit
  cmdfile="$BATS_TEST_TMPDIR/relaunch.cmd"; sleep 300 >/dev/null 2>&1 3>&- & RCY_CALLER_PID_ARG=$!
  echo "$RCY_CALLER_PID_ARG" > "$BATS_TEST_TMPDIR/subject.pid"
  commit_at 0.50
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -e "$cmdfile.exit-committed" ] && [ -e "$cmdfile.exit-delegated" ] || false
  [ "$(sends_exit)" = 0 ] || { cat "$CALLS"; false; }
  [[ "$output" == *"exit: DELEGATED to the watcher"* ]]
}

@test "D1: CC_RECYCLE_DELEGATE_EXIT=off, or a remote recycle, types /exit here as before" {
  # shellcheck disable=SC2034  # recycle_fire's local and the detach's global, read by recycle_fire_commit
  cmdfile="$BATS_TEST_TMPDIR/relaunch.cmd"; sleep 300 >/dev/null 2>&1 3>&- & RCY_CALLER_PID_ARG=$!
  echo "$RCY_CALLER_PID_ARG" > "$BATS_TEST_TMPDIR/subject.pid"
  CC_RECYCLE_DELEGATE_EXIT=off commit_at 0.50
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$cmdfile.exit-delegated" ]
  [ "$(sends_exit)" = 1 ] || { cat "$CALLS"; false; }
  setup
  # shellcheck disable=SC2034  # globals read by hf_recycle_delegate_ok
  { cmdfile="$BATS_TEST_TMPDIR/relaunch2.cmd"; RCY_REMOTE=1; }
  sleep 300 >/dev/null 2>&1 3>&- & RCY_CALLER_PID_ARG=$!
  echo "$RCY_CALLER_PID_ARG" > "$BATS_TEST_TMPDIR/subject.pid"
  run hf_recycle_delegate_ok
  [ "$status" -eq 1 ]
}

