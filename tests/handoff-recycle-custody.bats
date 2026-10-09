#!/usr/bin/env bats
# handoff-fire.sh --recycle — the RESUME DEBT (docs/plans/CLOSE_RESUME_CUSTODY.md §2 D2-D4).
#
# THE INCIDENT (2026-09-28 23:12Z). An upgrade mover recycled pane 405. /exit landed, the window was
# destroyed seconds later and its tty reused by a new window; the watcher's tty-only probe
# "CONFIRMED a shell", nothing re-enumerated the pane, both relaunch writes failed, and the only
# outputs were a recycle-dead row and an alarm whose push timed out. The session was abandoned.
#
# WHAT THIS SUITE PINS. The foreground opens a debt for the closed session before /exit; the
# detached watcher re-checks the pane's SURFACE between exit and relaunch, and every arm that ends
# with no claude in the pane SETTLES the debt (relaunch the same sid in a new window, or escalate),
# while engagement DISCHARGES it. cc-resume-debt is a recorder here (CC_RESUME_DEBT_BIN): the suite
# asserts what the watcher asked for, never what the ledger did with it.
#
# Harness: the watcher is invoked directly, like tests/handoff-recycle-remote-resume.bats. `ps` is a
# PHASE-AWARE shim — a bare zsh until the relaunch has been typed (the it2 stub records the typed
# text in $HOME/it2-screen), and then a claude when ENGAGE_AS_CLAUDE=1. The it2 stub can drop the
# pane after VANISH_AFTER `session list --json` calls and can refuse every write (SEND_FAIL=1).

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  [ -f "$HF" ] || { echo "subject missing: $HF" >&2; return 1; }

  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-such-sweep-stamp.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin" "$HOME/.claude/logs" "$HOME/.claude/autonomy"
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms"
  export CC_ADMIT_IDL="$HOME/.claude/autonomy/idl.jsonl"; : > "$CC_ADMIT_IDL"

  export CC_NOTIFY_BIN="$HOME/.claude/bin/cc-notify"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$HOME/ccnotify-calls.log"\n' > "$CC_NOTIFY_BIN"
  chmod +x "$CC_NOTIFY_BIN"

  export DEBT_LOG="$BATS_TEST_TMPDIR/debt.log"
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/cc-resume-debt"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$DEBT_LOG" > "$CC_RESUME_DEBT_BIN"
  chmod +x "$CC_RESUME_DEBT_BIN"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
args="$*"
cc=0
[ "${ENGAGE_AS_CLAUDE:-0}" = 1 ] && [ -s "$HOME/it2-screen" ] && cc=1
case "$args" in *pgid=*) printf '4242\n'; exit 0 ;; esac
# One fixed start time, so the watcher's launch lock (W2b) can stamp its holder.
case "$args" in *lstart=*) printf 'Tue Sep 29 10:00:00 2026\n'; exit 0 ;; esac
case "$args" in
  *"-axww -o args="*) [ "$cc" = 1 ] && printf 'claude --resume %s\n' "$SESS"; exit 0 ;;
  *"-o pid= -t"*)     printf '100\n' ;;
  *"-o tpgid= -t"*)   printf '100\n' ;;
  *"-o comm= -t"*)    if [ "$cc" = 1 ]; then printf 'claude\n'; else printf -- '-zsh\n'; fi ;;
  *pid=,ppid=*)       printf '100 1\n' ;;
  *"pid=,comm= -g"*)  printf '100 /bin/zsh\n' ;;
  *"-p 100"*)         if [ "$cc" = 1 ]; then printf 'claude\n'; else printf '/bin/zsh\n'; fi ;;
esac
exit 0
SH
  chmod +x "$SHIM/ps" "$SHIM/osascript"
  export PATH="$SHIM:$PATH"

  export STUB_PANE="CUSTODY-PANE"
  export SESS="5e55f00d-0000-4000-8000-00000000c405"
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    printf 'x' >> "$HOME/it2-list.count"; n="$(wc -c < "$HOME/it2-list.count" | tr -d ' ')"
    if [ -n "${VANISH_AFTER:-}" ] && [ "$n" -gt "$VANISH_AFTER" ]; then
      [ "${3:-}" = --json ] && printf '[{"id": "OTHER-PANE", "tty": "/dev/ttys998"}]\n' || printf 'OTHER-PANE\n'
    else
      [ "${3:-}" = --json ] && printf '[{"id": "%s", "tty": "/dev/ttys999"}, {"id": "OTHER-PANE", "tty": "/dev/ttys998"}]\n' "$STUB_PANE" \
                            || printf '%s\nOTHER-PANE\n' "$STUB_PANE"
    fi
    exit 0 ;;
  "session send")
    [ "${SEND_FAIL:-0}" = 1 ] && exit 1
    txt="${!#}"; [ "${#txt}" -gt 3 ] && printf '%s' "$txt" > "$HOME/it2-screen" ;;
  "session read") cat "$HOME/it2-screen" 2>/dev/null ;;
esac
exit 0
SH
  chmod +x "$HOME/.claude/bin/it2"
  export IT2_BIN="$HOME/.claude/bin/it2"

  CMDFILE="$BATS_TEST_TMPDIR/relaunch.cmd"
  printf 'cd /tmp && nocorrect bash /tmp/lr-launch-c405.sh\n' > "$CMDFILE"
  TTYF="$BATS_TEST_TMPDIR/ttys999"; : > "$TTYF"
  export CMDFILE TTYF
  export HF_RECYCLE_SHELL_WAIT_S=6 FIRE_TYPE_ATTEMPTS=1 FIRE_TYPE_SETTLE=0 FIRE_TYPE_PRESETTLE=0
  # The typing loop is a deadline now (RECYCLE_KEYSTROKELESS_DELIVERY §D2.7, default 600 s); 0 keeps
  # the old two rounds, which is all a case here that serves a non-echoing screen should wait.
  export CC_RECYCLE_TYPE_DEADLINE_S=0
  export RCY_BOOT_WAIT_S=1 RCY_BOOT_STALE_S=2 RCY_BOOT_IVL_S=0.2 RCY_BOOT_SLOW_IVL_S=1 RCY_BOOT_PANE_EVERY=2
}

# A fresh-brief recycle: the closed session is $6, nothing is resumed.
drive_fresh() { run bash "$HF" __recycle "$STUB_PANE" "$TTYF" "$CMDFILE" /tmp "$SESS"; }
# A resume-mode recycle: $10 cfg, $11 the resumed sid, $12 the engagement baseline.
drive_resume() {
  run bash "$HF" __recycle "$STUB_PANE" "$TTYF" "$CMDFILE" /tmp "$SESS" "" "" "" \
    "$HOME/.claude-next" "$SESS" "2026-09-28T23:12:00"
}
rows() { cat "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; }

@test "a pane that vanished between exit and relaunch is never typed into and its session is settled (new window, same sid)" {
  export VANISH_AFTER=1                        # pane_proof enumerates it; the surface re-check does not
  drive_fresh
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"relaunch surface gone"* ]] || { echo "$output"; false; }
  run grep -c 'session send' "$HOME/it2-calls.log"
  [ "$output" = 0 ] || { cat "$HOME/it2-calls.log"; false; }
  rows | grep '"class":"recycle-dead"' | grep -q 'relaunch surface gone' || { rows; false; }
  grep -qxF "settle --sid $SESS" "$DEBT_LOG" || { cat "$DEBT_LOG"; false; }
}

@test "relaunch write failure settles the debt, and the row names the surface after the failed writes" {
  export SEND_FAIL=1
  drive_fresh
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  rows | grep '"class":"recycle-dead"' | grep -q 'pane present after the failed writes' || { rows; false; }
  grep -qxF "settle --sid $SESS" "$DEBT_LOG" || { cat "$DEBT_LOG"; false; }
}

@test "a relaunch that never booted (STALE:boot) settles the debt" {
  drive_fresh
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"STALE:boot"* ]] || { echo "$output"; false; }
  grep -qxF "settle --sid $SESS" "$DEBT_LOG" || { cat "$DEBT_LOG"; false; }
}

@test "engagement discharges the debt and never settles it" {
  export ENGAGE_AS_CLAUDE=1 HF_ENGAGE_BY_PROCESS=1 HF_ENGAGE_PROC_HOLD_S=0 RCY_ENGAGE_TIMEOUT=6
  drive_resume
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"ENGAGEMENT CONFIRMED BY PROCESS"* ]] || { echo "$output"; false; }
  grep -qxF "discharge --sid $SESS --why recycle engaged in pane $STUB_PANE" "$DEBT_LOG" || { cat "$DEBT_LOG"; false; }
  ! grep -q '^settle' "$DEBT_LOG"
}

@test "the transcript-turn engaged arm discharges too (structural: the harness cannot fake an assistant turn)" {
  run awk '/emit_recycle_event recycle-engaged 1 "\$RSID" "recycled in place; a real assistant turn/ { hit = NR }
           hit && NR == hit + 1 { print; exit }' "$HF"
  [[ "$output" == *'_hf_resume_debt discharge --sid "$RCY_DEBT_SID"'* ]] || { echo "line after: $output"; false; }
}

@test "the foreground opens the debt BEFORE typing /exit and abandons it when /exit never lands (structural)" {
  # The /exit loop is past every dry-run exit and types into a real pane, so it is pinned by order.
  open_ln="$(grep -n '_hf_resume_debt open --sid "\$rcy_debt_sid"' "$HF" | cut -d: -f1)"
  exit_ln="$(grep -n 'as_write "\$SID" "/exit" 2>/dev/null' "$HF" | cut -d: -f1)"
  aband_ln="$(grep -n '_hf_resume_debt abandon --sid "\$rcy_debt_sid" --why "exit never typed; session untouched"' "$HF" | cut -d: -f1)"
  refuse_ln="$(grep -n 'could not type /exit into \$SID' "$HF" | cut -d: -f1)"
  echo "open=$open_ln exit=$exit_ln abandon=$aband_ln refuse=$refuse_ln"
  [ -n "$open_ln" ]
  [ -n "$exit_ln" ]
  [ -n "$aband_ln" ]
  [ -n "$refuse_ln" ]
  # W2b: the PRIMARY keystroke is hf_exit_readback (typed, read back, then Enter); the as_write loop
  # above survives only behind HF_EXIT_READBACK=off. The debt must open immediately before the first.
  rb_ln="$(grep -n 'if ! hf_exit_readback "\$SID"; then' "$HF" | cut -d: -f1)"
  echo "readback=$rb_ln"
  [ -n "$rb_ln" ]
  [ "$open_ln" -lt "$rb_ln" ]
  [ $(( rb_ln - open_ln )) -lt 20 ]            # immediately before the keystroke, not somewhere upstream
  [ "$open_ln" -lt "$exit_ln" ]
  [ "$rb_ln" -lt "$exit_ln" ]
  [ "$exit_ln" -lt "$aband_ln" ]
  [ "$aband_ln" -lt "$refuse_ln" ]
  # A fresh-brief recycle hands the pane to a NEW sid, so its debt must say so (--mode fresh) or a
  # sweep after a dead watcher would resume the old sid beside its live successor.
  sed -n "${open_ln},$(( open_ln + 4 ))p" "$HF" | grep -qF -- '--mode "$(if [ -n "$RESUME_LAUNCHER" ]; then printf resume; else printf fresh; fi)"'
}

@test "a missing cc-resume-debt leaves the watcher's verdict exactly as before" {
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/no-such-cc-resume-debt" SEND_FAIL=1
  drive_fresh
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"relaunch write failed twice"* ]] || { echo "$output"; false; }
  [ ! -e "$DEBT_LOG" ]
}
