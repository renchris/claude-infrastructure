#!/usr/bin/env bats
# THE SUBJECT, PINNED AT ARM (move-lane-double-submit; the 2026-10-17 pane-7 strand). Batch
# 20261017T073813Z-next2-next-26358 moved session 9f6593c5 (pane 7) from next2 to next. The
# watcher armed at 07:54:14; the commit tail (confirm, last read, load gate, debt) then ran until
# 07:59:48. Inside that stretch pane 7's claude (pid 65405) exited (07:55:26), the watcher typed the
# relaunch and claude 79475 came up (07:57:48). The tail's /exit then went into 79475, which ended
# 07:59:55 with exit 0, and the move closed STRANDED with its resume debt open. The record is
# tests/fixtures/move-lane-2026-10-17/pane7 (paths scrubbed), and case 1 re-reads that ordering
# from it before replaying it.
#
# Driven through recycle_fire_commit over stubs, extracted as tests/handoff-recycle-load-hold.bats
# does. The subject is a real process, orphaned so launchd reaps it the moment it is killed; each
# case kills it at a different step of the tail, so each of the three re-reads has its own case.
#
# RED-proof (pre-fix: the tail types /exit whatever became of the subject): 1, 2, 3 fail before the
# fix. Mutants, one per site, each red on its own case: drop re-read 1 (case 1 then reads "before the
# resume debt") · drop re-read 2 (case 2 then opens the debt) · drop re-read 3 (case 3 then types
# /exit) · make hf_recycle_subject_gone `return 1` (1-3) · make hf_recycle_subject_pin pin nothing
# (1-3) · drop its HF_REMOTE_ROW_PID arm (6). 4 and 5 are the controls and pass before the fix.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$REPO/scripts/handoff-fire.sh}"
  FX="$REPO/tests/fixtures/move-lane-2026-10-17/pane7"
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
        HF_EXIT_READBACK HF_EXIT_ACTUATOR HF_REMOTE_ROW_PID RCY_SUBJECT_PID RCY_SUBJECT_LSTART 2>/dev/null || true

  FUNCS="$BATS_TEST_TMPDIR/funcs.sh"
  local f
  {
    grep '^_iso_now() {' "$HF"
    grep '^kt() {' "$HF"
    for f in _under_test emit_recycle_event hf_bounded hf_bounded_s kt_window_field composer_content \
             recycle_composer_gate hf_lr_script hf_recycle_fenced hf_recycle_lock_dir _hf_lstart \
             _hf_lock_raw _hf_lock_field _hf_lock_holder_alive hf_recycle_lock_write hf_recycle_lock_take \
             hf_recycle_lock_release hf_recycle_lock_acquire hf_recycle_disarm hf_wake_guard \
             hf_recycle_unconfirm hf_recycle_hold hf_recycle_last_read hf_exit_readback recycle_fire_commit \
             composer_residue_dir composer_residue_record pid_is_cc hf_succ_mode hf_succ_ours_staged \
             write_teardown_marker hf_exit_signal_pin hf_exit_signal hf_exit_signal_grace \
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
  # it2: `session send` is recorded; `session read` serves the next queued composer content and, with
  # KILL_ON_READ set, first ends the subject — pane 7's claude exiting while the tail read its box.
  cat > "$STUB/it2" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "session send") printf 'send %q\n' "${!#}" >> "$CALLS" ;;
  "session read")
    [ -z "${KILL_ON_READ:-}" ] || { kill "$SUBJ" 2>/dev/null; n=0; while ps -p "$SUBJ" >/dev/null 2>&1 && [ "$n" -lt 40 ]; do sleep 0.05; n=$((n + 1)); done; }
    c="$(head -n 1 "$READS")"
    [ "$(wc -l < "$READS" | tr -d ' ')" -gt 1 ] && { tail -n +2 "$READS" > "$READS.t"; mv "$READS.t" "$READS"; }
    printf 'history\n────────────────────\n❯ %s\n────────────────────\n' "$c" ;;
esac
exit 0
SH
  # shellcheck disable=SC2016  # the stub's own $1 and $CALLS, expanded when it runs
  printf '#!/usr/bin/env bash\nprintf "sleep %%s\\n" "$1" >> "$CALLS"\n' > "$STUB/sleep"
  chmod +x "$STUB/it2" "$STUB/sleep"
  # shellcheck disable=SC2329  # stubs, invoked by the extracted functions under test
  _hf_resume_debt() {
    printf 'debt %s\n' "$*" >> "$CALLS"
    [ -z "${KILL_ON_DEBT:-}" ] || subject_exit
  }
  # shellcheck disable=SC2329
  as_write() { printf 'as_write %q\n' "$2" >> "$CALLS"; }
  # shellcheck disable=SC2329
  as_write_transports() { echo stub; }
  export HF_SLEEP="$STUB/sleep" HF_DIR="$REPO/scripts" HF_TIMEOUT_S="" HF_TIMEOUT_BIN=""
  export HF_KERN_WAKETIME=1 HF_RECYCLE_LOCK_GATE=on LR_LOCKS_DIR="$BATS_TEST_TMPDIR/locks"
  export CC_PANE_SUCCESSOR_DIR="$BATS_TEST_TMPDIR/succ"; mkdir -p "$CC_PANE_SUCCESSOR_DIR"
  # shellcheck disable=SC1091
  . "$REPO/lib/pane-successor.sh"
  # The remote resume form pane 7 took (lr-handoff → handoff-fire --recycle --resume-launcher),
  # untransplanted here: the confirm is lr-transplant's subject, not this one's.
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  SID=7 CMD="relaunch-cmd" RCY_IT2="$STUB/it2" RCY_REMOTE=0 RCY_SAME_ACCOUNT=0 RCY_REST_PROVEN=0
  SESS="9f6593c5-fa6d-45eb-babd-5f3be41cd18f"
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  RCY_TRANSPLANTED_SOURCE=0 RCY_TRANSPLANT_CAUSE="" RESUME_LAUNCHER="lr-launch.sh" RESUME_CFG="$HOME/.claude-next" RCY_SOURCE_SESSION="$SESS"
  # shellcheck disable=SC2034  # recycle_fire's local, read by recycle_fire_commit (dynamic scope)
  tty=/dev/ttys999
  sleep 300 >/dev/null 2>&1 3>&- & WATCHER_PID=$!
  echo "$WATCHER_PID" > "$BATS_TEST_TMPDIR/watcher.pid"
  export WATCHER_PID
  hf_recycle_lock_acquire "$SID"
  hf_recycle_lock_write "$HF_RECYCLE_LOCK" watcher "$WATCHER_PID"
  # The SUBJECT: orphaned (the subshell exits at once), so launchd reaps it when it is killed and the
  # pid stops answering, as 65405 did.
  ( sleep 300 >/dev/null 2>&1 3>&- & echo $! > "$BATS_TEST_TMPDIR/subject.pid" )
  SUBJ="$(cat "$BATS_TEST_TMPDIR/subject.pid")"; export SUBJ
  # Pinned as recycle_fire_armed pins it, from the remote form's registry-row pid.
  RCY_REMOTE=1 HF_REMOTE_ROW_PID="$SUBJ" hf_recycle_subject_pin "$tty" "$SESS"
  printf '%s\n' "" "/exit" > "$READS"
}

teardown() {
  [ -f "$BATS_TEST_TMPDIR/watcher.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/watcher.pid")" 2>/dev/null || true; }
  [ -f "$BATS_TEST_TMPDIR/subject.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/subject.pid")" 2>/dev/null || true; }
  return 0
}

subject_exit() {
  kill "$SUBJ" 2>/dev/null || true
  local n=0; while ps -p "$SUBJ" >/dev/null 2>&1 && [ "$n" -lt 40 ]; do sleep 0.05; n=$((n + 1)); done
}
rows_of() { grep "\"class\":\"$1\"" "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; }
sends_exit() { grep -cxF -- "send /exit" "$CALLS" || true; }
debts() { grep -c '^debt open' "$CALLS" || true; }

# The yield's whole receipt: status 0 (the watcher carries the relaunch, as after a submitted /exit),
# the row naming where it was noticed, the line, and no keystroke at all.
assert_yielded() { # $1=where
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  rows_of recycle-subject-exited | grep -q "claude pid $SUBJ (lstart [^)]*) exited on its own $1" \
    || { cat "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; echo "$output"; false; }
  [[ "$output" == *"→ exit: NOT typed — claude pid $SUBJ exited on its own $1"* ]] || { echo "$output"; false; }
  ! grep -q '^send' "$CALLS" || { echo "a keystroke was sent:"; cat "$CALLS"; false; }
  [ -z "$(rows_of recycle-exit-signal)" ]
}

@test "1 [RED] replay pane 7: the subject exited after the watcher armed — no /exit, no debt" {
  # The record's ordering, read from the record: 65405 ended before the first relaunch keystroke, one
  # relaunch ran (one lr-fire-resume spawn), the tail opened its debt after that, and 79475 ended
  # seconds after the debt — the /exit the tail typed.
  local e65 t_type n_spawn t_debt e79
  e65="$(jq -r .ended_at "$FX/close-65405.json")"
  t_type="$(jq -r 'select(.class == "recycle-type-attempt") | .ts' "$FX/handoffs-rows.jsonl" | head -1)"
  n_spawn="$(grep -c '"stage":"expect"' "$FX/bundle-events.jsonl")"
  t_debt="$(date -u -r "$(jq -r .opened_epoch "$FX/resume-debt.json")" +%Y-%m-%dT%H:%M:%SZ)"
  e79="$(jq -r .ended_at "$FX/close-79475.json")"
  [[ "$e65" < "$t_type" && "$t_type" < "$t_debt" && "$t_debt" < "$e79" ]] || { echo "$e65 $t_type $t_debt $e79"; false; }
  [ "$n_spawn" = 1 ]
  [ "$(jq -r .why "$FX/resume-debt.json")" = "recycle of pane 7 (resume-launcher, same sid) about to type /exit" ]
  grep -q 'ENGAGEMENT CONFIRMED BY PROCESS' "$FX/recycle-watcher.log"

  subject_exit
  run recycle_fire_commit "$SESS"
  assert_yielded "before the last read"
  [ "$(debts)" = 0 ] || { cat "$CALLS"; false; }
  [ -e "$BATS_TEST_TMPDIR/locks" ] && kill -0 "$WATCHER_PID"   # not disarmed: the relaunch is its
}

@test "2 [RED] the subject exits while the tail reads its box: caught before the resume debt opens" {
  export KILL_ON_READ=1
  run recycle_fire_commit "$SESS"
  assert_yielded "before the resume debt"
  [ "$(debts)" = 0 ] || { cat "$CALLS"; false; }
}

@test "3 [RED] the subject exits while the debt opens: caught before the typed /exit" {
  export KILL_ON_DEBT=1
  run recycle_fire_commit "$SESS"
  assert_yielded "before the typed /exit"
  [ "$(debts)" = 1 ] || { cat "$CALLS"; false; }
  [[ "$output" == *"the resume debt opened above stays for the watcher to discharge"* ]] || { echo "$output"; false; }
}

@test "4 CONTROL the subject alive through the tail: /exit typed once, debt opened, no yield row" {
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 0 ] || { echo "$output"; cat "$CALLS"; false; }
  [ "$(sends_exit)" = 1 ] || { cat "$CALLS"; false; }
  [ "$(debts)" = 1 ]
  [ -z "$(rows_of recycle-subject-exited)" ]
}

@test "5 CONTROL an unpinnable subject is never 'gone': the tail runs exactly as before the pin" {
  subject_exit
  # No row pid, no claude on the tty: nothing to pin.
  RCY_REMOTE=1 HF_REMOTE_ROW_PID="" hf_recycle_subject_pin "$tty" "$SESS"
  [ -z "$RCY_SUBJECT_PID" ] && [ -z "$RCY_SUBJECT_LSTART" ] || false
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(sends_exit)" = 1 ] || { cat "$CALLS"; false; }
  [ -z "$(rows_of recycle-subject-exited)" ]
}

@test "6 the pin is (pid, start time): the remote form takes the registry-row pid, and a reused pid reads gone" {
  [ "$RCY_SUBJECT_PID" = "$SUBJ" ] || { echo "pinned '${RCY_SUBJECT_PID}', want $SUBJ"; false; }
  [ "$RCY_SUBJECT_LSTART" = "$(_hf_lstart "$SUBJ")" ]
  if hf_recycle_subject_gone; then echo "a live subject read gone"; false; fi
  # Same pid, another start time: a different process now holds it.
  RCY_SUBJECT_LSTART="Thu Jan  1 00:00:00 1970"
  hf_recycle_subject_gone
}
