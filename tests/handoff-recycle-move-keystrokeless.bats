#!/usr/bin/env bats
# A KEYSTROKE-FREE MOVE (lr-wake 2026-10-18, docs/research/lr-wake-incident-2026-10-18/REPORT.md §4
# Wave S). Every in-place move typed its /exit and its relaunch, because a resume recycle never staged
# a successor: its fold, launch-lock and holder rails ran only in the watcher. At 8+/core that typing
# held or stranded the pane. Now the resume recycle stages its launcher behind those rails, the signal
# exit (SIGTERM, at rest, successor staged) replaces the typed /exit, and the load hold has nothing to
# hold.
#
# THE REPLAY. One move of session S from next4 to next3 in pane 332, over the move-lane fixture world
# (tests/helpers/lr-move-fixture.sh): the subject is a real process with a registry row and an at-rest
# transcript. The foreground half is driven through hf_succ_stage + recycle_fire_commit, extracted as
# tests/handoff-recycle-load-hold.bats does, at a STUBBED 30/core with the commit hold ON. Every it2
# call goes through the REAL bin/it2-kitty over a fake kitty, so any keystroke lands as a row in
# pane-keys.jsonl, the provenance log Wave D added. The pane half is the test acting as the pane's
# consumer: it takes the stage and sources it, which runs the REAL `handoff-fire.sh __succ-rails` and
# then the launcher; the launcher leaves what a resumed session leaves (a new process on the target,
# its row, its transcript there). lr_move_verdict, the move lane's own judge, then reads MOVED.
#
# THE Q3 BOUNDARY (decision 4dce9ca65af4, open). SIGTERM stops a session's background tasks, so a
# session with real background work must still be HELD before any signal: the last read's bg-work
# gate does that (HELD:bg-work:other). Case 2 pins it; case 3 is the control that a session whose only
# job is its inbox watcher (cc-await-ping) is signalled, today's answer for that case.
#
# RED-proof: case 1 fails on origin/main (9c392dbc8): the resume stage is refused, so the commit holds
# recycle-held-load at 30/core. Cases 2 and 3 pass there too (the bg-work gate and the watcher-only
# answer are older than this wave); they guard the boundary the new signal path must not cross.
# Case 4 is the instrument's positive control: the typed /exit DOES land in pane-keys.jsonl.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  HOME="$(cd "$HOME" && pwd -P)"; export HOME
  # shellcheck source=/dev/null
  . "$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/helpers/lr-move-fixture.sh"
  mvf_setup                                              # REPO, LRD, SRC (next4), DST (next3), registry
  HF="${HF_OVERRIDE:-$REPO/scripts/handoff-fire.sh}"
  # HERMETICITY (land ratchet): no live machine load, and no seam resolves outside the test dir.
  export CC_ADMIT_GATE=off CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$BATS_TEST_TMPDIR/deploy-repo"
  export CC_SESSIONS_DIRS="$BATS_TEST_TMPDIR/sessions"; mkdir -p "$CC_SESSIONS_DIRS"
  unset WATCHER_PID HF_RECYCLE_ATTEMPT HF_WATCHER_IS_JOB CC_TERM CC_TERM_KITTY_TO KITTY_WINDOW_ID \
        HF_EXIT_READBACK HF_EXIT_ACTUATOR HF_RECYCLE_HOLD_LOAD_PER_CORE CC_GATE_MAX_LOAD_PER_CORE \
        CC_PANE_SUCCESSOR HF_LAUNCH_LOCK HF_FOLD_STUB LR_RECORD_ID LR_ATTEMPT \
        CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_DIR KITTY_LISTEN_ON 2>/dev/null || true

  FUNCS="$BATS_TEST_TMPDIR/funcs.sh"
  local f
  {
    grep '^_iso_now() {' "$HF"
    grep '^kt() {' "$HF"
    for f in _under_test emit_recycle_event hf_bounded hf_bounded_s kt_window_field composer_content \
             recycle_composer_gate hf_lr_script hf_recycle_fenced hf_recycle_lock_dir _hf_lstart \
             _hf_lock_raw _hf_lock_field _hf_lock_holder_alive hf_recycle_lock_write hf_recycle_lock_take \
             hf_recycle_lock_release hf_recycle_lock_acquire hf_recycle_watcher_committed hf_recycle_disarm hf_wake_guard \
             hf_recycle_unconfirm hf_recycle_hold hf_recycle_last_read hf_exit_readback recycle_fire_commit \
             composer_residue_dir composer_residue_record hf_succ_mode hf_succ_ours_staged hf_succ_lib_load hf_succ_stage \
             hf_exit_signal hf_exit_signal_grace hf_load_per_core hf_recycle_load_bound hf_recycle_load_gate \
             hf_recycle_subject_pin hf_recycle_subject_gone hf_recycle_subject_yield \
             hf_transcript_at_rest hf_bg_work_gate hf_bg_work_kind; do
      sed -n "/^$f() {/,/^}/p" "$HF"
    done
  } > "$FUNCS"
  bash -n "$FUNCS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$FUNCS"
  grep -q '^recycle_fire_commit() {' "$FUNCS" || { echo "recycle_fire_commit not extracted" >&2; return 1; }

  # ── the pane, through the REAL it2-kitty over a fake kitty ─────────────────────────────────────
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  export IT2_LOG="$BATS_TEST_TMPDIR/it2-calls.log" KCALLS="$BATS_TEST_TMPDIR/kitty-calls.log"
  export READS="$STUB/reads"; : > "$IT2_LOG"; : > "$KCALLS"; : > "$READS"
  export CC_PANE_KEYS_LOG="$HOME/.claude/logs/pane-keys.jsonl"
  # get-text serves the NEXT queued composer content (the last one repeats) inside a box.
  cat > "$STUB/kitty" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$KCALLS"
[ "$1" = @ ] && shift
while [ "${1:-}" = --to ]; do shift 2; done
case "${1:-}" in
  ls) printf '[{"id":1,"is_focused":false,"tabs":[{"id":1,"windows":[{"id":332,"pid":4242,"title":"claude","cwd":"/tmp","is_focused":false,"foreground_processes":[]}]}]}]\n' ;;
  get-text)
    c="$(head -n 1 "$READS")"
    [ "$(wc -l < "$READS" | tr -d ' ')" -gt 1 ] && { tail -n +2 "$READS" > "$READS.t"; mv "$READS.t" "$READS"; }
    printf 'history\n────────────────────\n❯ %s\n────────────────────\n' "$c" ;;
esac
exit 0
SH
  # shellcheck disable=SC2016  # the stub's own $* and log path, expanded when it runs
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$IT2_LOG"\nexec %q "$@" 2>>"$IT2_LOG.err"\n' "$REPO/bin/it2-kitty" > "$STUB/it2"
  # shellcheck disable=SC2016  # the stub's own $1, expanded when it runs
  printf '#!/usr/bin/env bash\nprintf "sleep %%s\\n" "$1" >> "%s/sleeps.log"\n' "$BATS_TEST_TMPDIR" > "$STUB/sleep"
  chmod +x "$STUB/kitty" "$STUB/it2" "$STUB/sleep"
  # An explicit socket, as a detached caller names one: no KITTY_WINDOW_ID here (the consumer's take
  # must not see one either), and the fake kitty ignores --to.
  export CC_TERM_KITTY="$STUB/kitty" CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/kitty.sock"

  # ── the move: S, live on next4 in pane 332, transplanted to next3 ──────────────────────────────
  SESS="5e5e5e5e-0000-4000-8000-0000000000a1"; PANE=332
  mvf_session "$PANE" "$SESS"                            # the subject: MVF_PID, at rest on $SRC
  SUBJ="$MVF_PID"
  mvf_plan b-s move "$PANE:$SESS"
  printf '{"admitted":true,"target":"next3","target_auth":"ok"}\n' > "$BDIR/admit.json"
  SRCTX="$SRC/projects/-x/$SESS.jsonl"
  export RAILS_LOG="$BATS_TEST_TMPDIR/rails.log"; : > "$RAILS_LOG"
  # lr-transplant: confirm, unconfirm and fold-stub all succeed, and each call is logged.
  # shellcheck disable=SC2016  # the stub's own $* and log path, expanded when it runs
  printf '#!/usr/bin/env bash\nprintf "transplant %%s\\n" "$*" >> "$RAILS_LOG"\nexit 0\n' > "$STUB/lr-transplant.sh"
  chmod +x "$STUB/lr-transplant.sh"
  export HF_LR_TRANSPLANT="$STUB/lr-transplant.sh" HF_LR_LIB="$LRD/lr-lib.sh"
  export HF_DIR="$REPO/scripts" HF_SELF="$HF" HF_SLEEP="$STUB/sleep" HF_TIMEOUT_S="" HF_TIMEOUT_BIN=""
  export HF_KERN_WAKETIME=1 HF_RECYCLE_LOCK_GATE=on LR_LOCKS_DIR="$BATS_TEST_TMPDIR/locks"
  export CC_PANE_SUCCESSOR_DIR="$BATS_TEST_TMPDIR/succ"; mkdir -p "$CC_PANE_SUCCESSOR_DIR"
  export CC_PANE_SUCCESSOR_LIB="$REPO/lib/pane-successor.sh"
  # shellcheck disable=SC1091
  . "$REPO/lib/pane-successor.sh"
  # The launcher the resume stage starts: what a resumed session leaves on disk — a NEW process (the
  # predecessor was signalled), its env and row on the target, its one transcript there.
  LAUNCHER_SH="$BATS_TEST_TMPDIR/lr-launch.sh"
  cat > "$LAUNCHER_SH" <<'SH'
#!/usr/bin/env bash
printf 'launcher %s\n' "$*" >> "$RAILS_LOG"
sleep 900 >/dev/null 2>&1 3>&- &
p=$!; echo "$p" >> "$BATS_TEST_TMPDIR/successor.pids"
printf '%s' "$MV_DST" > "$LR_MOVE_ENV_DIR/$p"
mv "$MV_SRC/projects/-x/$MV_SID.jsonl" "$MV_DST/projects/-x/$MV_SID.jsonl"
jq -c --argjson p "$p" '.pid = $p | .account = "claude-tertiary"' "$CC_REGISTRY_DIR/$MV_PANE.json" > "$CC_REGISTRY_DIR/$MV_PANE.json.t"
mv "$CC_REGISTRY_DIR/$MV_PANE.json.t" "$CC_REGISTRY_DIR/$MV_PANE.json"
SH
  chmod +x "$LAUNCHER_SH"
  export MV_SRC="$SRC" MV_DST="$DST" MV_SID="$SESS" MV_PANE="$PANE"

  # Stubs, invoked by the extracted functions under test; the pin's globals are read by hf_exit_signal.
  # shellcheck disable=SC2329,SC2034
  {
    _hf_resume_debt() { printf 'debt %s\n' "$*" >> "$RAILS_LOG"; }
    as_write() { printf 'as_write %q\n' "$2" >> "$RAILS_LOG"; }
    as_write_transports() { echo stub; }
    write_teardown_marker() { :; }
    hf_canary_hook() { :; }
    # Edges of the last read that are not this wave's subject: an unfocused pane, no subagents, no team.
    hf_focus_gate() { return 0; }
    subagent_dir_for_sid() { :; }
    live_subagents_of() { :; }
    hf_team_live() { return 1; }
    # The pin: the subject (pid + start time), exactly one claude naming S. The real pin reads the
    # pane's tty tree, which a fixture process does not have.
    hf_exit_signal_pin() {
      HF_EXIT_SIG_PID="$SUBJ"; HF_EXIT_SIG_LSTART="$(_hf_lstart "$SUBJ")"
      [ -n "$HF_EXIT_SIG_LSTART" ] || { HF_EXIT_SIG_WHY="subject gone"; HF_EXIT_SIG_PID=""; return 1; }
    }
  }
  # The subject's process table for the bg-work gate (hf_bg_work_kind's HF_PS_SNAPSHOT seam).
  export HF_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"
  printf '%s 1 Mon Oct 19 10:00:00 2026 claude --resume %s\n' "$SUBJ" "$SESS" > "$HF_PS_SNAPSHOT"

  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  SID=$PANE RCY_IT2="$STUB/it2" RCY_REMOTE=1 RCY_SAME_ACCOUNT=0 RCY_REST_PROVEN=0 RCY_FOCUSED=no
  # shellcheck disable=SC2034
  RCY_TRANSPLANTED_SOURCE=1 RCY_TRANSPLANT_CAUSE=voluntary RCY_SOURCE_SESSION="$SESS" RCY_TS_SID="$SESS"
  # shellcheck disable=SC2034
  HF_TS_CFG="$SRC" HF_TS_TO="$DST" HF_TS_TOMBSTONE="$SRC/projects/-x/$SESS.HANDOFF.json" RCY_SRC_TX="$SRCTX"
  # shellcheck disable=SC2034
  RESUME_LAUNCHER="$LAUNCHER_SH" RESUME_CFG="$DST" HF_REMOTE_ROW_PID="$SUBJ" rcy_old_sid="$SESS"
  export HF_LAUNCH_REC="rec-move-s" HF_LAUNCH_ATT=1 LR_RECORD_ID="rec-move-s"
  CMD="cd /tmp && bash $(printf %q "$LAUNCHER_SH")"
  # shellcheck disable=SC2034  # recycle_fire's locals (dynamic scope)
  tty=/dev/ttys999 cmdfile="$BATS_TEST_TMPDIR/handoff-recycle-cmd-332"
  printf '%s\n' "$CMD" > "$cmdfile"
  # The watcher: a real process, so the stage's watcher proof and the lock identity are real too.
  sleep 300 >/dev/null 2>&1 3>&- & WATCHER_PID=$!
  echo "$WATCHER_PID" > "$BATS_TEST_TMPDIR/watcher.pid"
  export WATCHER_PID
  hf_recycle_lock_acquire "$SID"
  hf_recycle_lock_write "$HF_RECYCLE_LOCK" watcher "$WATCHER_PID"
  hf_recycle_subject_pin "$tty" "$SESS"
  # The last read sees an empty box; a typed /exit (case 4) reads back as /exit.
  printf '%s\n' "" "/exit" > "$READS"
}

teardown() {
  [ -f "$BATS_TEST_TMPDIR/watcher.pid" ] && { kill "$(cat "$BATS_TEST_TMPDIR/watcher.pid")" 2>/dev/null || true; }
  if [ -f "$BATS_TEST_TMPDIR/successor.pids" ]; then
    while read -r p; do kill "$p" 2>/dev/null || true; done < "$BATS_TEST_TMPDIR/successor.pids"
  fi
  mvf_teardown
}

rows_of() { grep "\"class\":\"$1\"" "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; }
keys() { [ -f "$CC_PANE_KEYS_LOG" ] && grep -c . "$CC_PANE_KEYS_LOG" || echo 0; }
stage_and_commit() { # the foreground's tail: stage, then commit with the hold ON at a stubbed load
  hf_succ_stage "$tty" "$cmdfile" > "$BATS_TEST_TMPDIR/stage.out" 2>&1 || true
  CC_FIRE_CAPACITY_GATE=on HF_LOAD_PER_CORE=30 run recycle_fire_commit "$SESS"
}
consume() { # the pane's consumer regains the tty when claude exits: take the stage, source it
  local claimed
  claimed="$(CC_PANE_SUCCESSOR_TTY=ttys999 bash -c '. "$1"; cc_pane_successor_take ttys999' _ "$CC_PANE_SUCCESSOR_LIB")" \
    || { echo "the consumer could not take the stage"; ls -la "$CC_PANE_SUCCESSOR_DIR"; cat "$BATS_TEST_TMPDIR/stage.out"; return 1; }
  bash -c '. "$1"' _ "$claimed"
}
move_verdict() {
  bash -c '. "$1/lr-lib.sh"; . "$1/lr-move-lib.sh"; lr_move_verdict "$2" "$3" "$4" "$5" "$6"' _ \
    "$LRD" "$SESS" "$PANE" "$SRC" "$DST" "$BDIR" | cut -f1,2
}
gone() { local n=0; while kill -0 "$1" 2>/dev/null && [ "$n" -lt 50 ]; do sleep 0.1; n=$((n + 1)); done; ! kill -0 "$1" 2>/dev/null; }

@test "1 [RED] a move at a stubbed 30/core: staged, signalled, rails in the pane — 0 typed keys, and the lane reads MOVED" {
  stage_and_commit
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$BATS_TEST_TMPDIR/stage.out"; cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [ "$(jq -r .mode "$CC_PANE_SUCCESSOR_DIR/ttys999.json")" = resume ] || { cat "$BATS_TEST_TMPDIR/stage.out"; false; }
  [ -z "$(rows_of recycle-held-load)" ] || { rows_of recycle-held-load; false; }
  rows_of recycle-exit-signal | grep -q "SIGTERM to claude pid $SUBJ" || { echo "$output"; cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  gone "$SUBJ" || { echo "the subject survived its SIGTERM"; false; }
  # The pane's consumer claims after claude's exit: the rails, then the launcher.
  consume || { cat "$RAILS_LOG"; false; }
  [ "$(cat "$cmdfile.rails")" = ok ] || { cat "$cmdfile.rails" "$RAILS_LOG"; false; }
  grep -q -- "--phase confirm --sid $SESS" "$RAILS_LOG" || { cat "$RAILS_LOG"; false; }
  grep -q '^launcher' "$RAILS_LOG" || { echo "the launcher never ran"; cat "$RAILS_LOG"; false; }
  # 0 keystrokes, read from the provenance log every it2-kitty send-text writes, and from the it2 seam.
  [ "$(keys)" = 0 ] || { echo "pane-keys.jsonl:"; cat "$CC_PANE_KEYS_LOG"; false; }
  ! grep -q '^session send' "$IT2_LOG" || { cat "$IT2_LOG"; false; }
  ! grep -q '^as_write' "$RAILS_LOG" || { cat "$RAILS_LOG"; false; }
  [ "$(move_verdict | cut -f1)" = MOVED ] || { move_verdict; false; }
}

@test "2 Q3: a session with a NON-WATCHER background job is HELD at the last read — never signalled, nothing typed" {
  # A CC Bash-tool shell under the subject, running a dev server: real work SIGTERM would stop.
  printf '%s %s Mon Oct 19 10:00:01 2026 /bin/zsh -c source %s/.claude/shell-snapshots/snapshot-zsh-1.sh && eval '"'"'npm run dev'"'"'\n' \
    70001 "$SUBJ" "$HOME" >> "$HF_PS_SNAPSHOT"
  printf '70002 70001 Mon Oct 19 10:00:01 2026 node dev-server\n' >> "$HF_PS_SNAPSHOT"
  stage_and_commit
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  rows_of recycle-held-bg-work | grep -q 'HELD:bg-work:other' || { cat "$HOME/.claude/logs/handoffs.jsonl"; echo "$output"; false; }
  [ -z "$(rows_of recycle-exit-signal)" ] || { rows_of recycle-exit-signal; false; }
  kill -0 "$SUBJ" 2>/dev/null || { echo "the subject was signalled"; false; }
  [ "$(keys)" = 0 ] || { cat "$CC_PANE_KEYS_LOG"; false; }
  ! grep -q '^debt' "$RAILS_LOG" || { echo "the resume debt opened:"; cat "$RAILS_LOG"; false; }
  # The hold disarmed the watcher, so its stage can no longer be claimed.
  ! kill -0 "$WATCHER_PID" 2>/dev/null || { echo "watcher still armed"; false; }
  if CC_PANE_SUCCESSOR_TTY=ttys999 bash -c '. "$1"; cc_pane_successor_take ttys999' _ "$CC_PANE_SUCCESSOR_LIB" >/dev/null; then
    echo "the stage of a disarmed watcher was claimable"; false
  fi
}

@test "3 Q3 control: a session whose only job is its inbox watcher (cc-await-ping) is signalled" {
  printf '%s %s Mon Oct 19 10:00:01 2026 /bin/zsh -c source %s/.claude/shell-snapshots/snapshot-zsh-1.sh && eval '"'"'cc-await-ping --timeout 3300'"'"'\n' \
    70001 "$SUBJ" "$HOME" >> "$HF_PS_SNAPSHOT"
  printf '70002 70001 Mon Oct 19 10:00:01 2026 /bin/bash %s/.claude/bin/cc-await-ping --timeout 3300\n' "$HOME" >> "$HF_PS_SNAPSHOT"
  stage_and_commit
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
  [ -z "$(rows_of recycle-held-bg-work)" ] || { rows_of recycle-held-bg-work; false; }
  rows_of recycle-exit-signal | grep -q "SIGTERM to claude pid $SUBJ" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [ "$(keys)" = 0 ] || { cat "$CC_PANE_KEYS_LOG"; false; }
}

@test "4 the instrument is not blind: the typed /exit (HF_EXIT_ACTUATOR=typed, load bound off) lands in pane-keys.jsonl" {
  HF_EXIT_ACTUATOR=typed HF_RECYCLE_HOLD_LOAD_PER_CORE=0 stage_and_commit
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
  [ "$(keys)" -ge 1 ] || { echo "no row in pane-keys.jsonl for a typed /exit"; cat "$IT2_LOG" "$KCALLS"; false; }
  grep -q '"head40":"/exit"' "$CC_PANE_KEYS_LOG" || { cat "$CC_PANE_KEYS_LOG"; false; }
}
