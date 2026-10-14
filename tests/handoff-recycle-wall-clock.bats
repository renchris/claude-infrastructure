#!/usr/bin/env bats
# The recycle watcher's clocks are WALL seconds (pane 434, 2026-10-14; docs/research/
# recycle-failure-2026-10-14.md § Q1, fix F5).
#
# THE DEFECT. The shell-wait loop counted `waited=$((waited+rcy_poll))` and the engage loop
# `rcy_t=$((rcy_t + RCY_ENGAGE_INTERVAL))`: sums of SLEEP seconds, blind to the time each iteration's
# own ps/jq/it2 forks take. At ~31/core pane 434's "first dialog check at 15s" came 2 min 40 s after
# arming, and every bound (the 600 s shell wait, the engage window) stretched by the same factor.
#
# THE SUBJECT IS SLOWED, NOT THE CLOCK. A `ps` shim makes every pane-state read cost PS_SLOW_S
# seconds, the way load does, and logs when each read began; the it2 stub logs when the dialog was
# read. The reported "bgwork@<N>s" must then be at least the wall seconds between the loop's first
# read and that dialog read, less a fixed slack for the forks between computing N and the read.

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  LIB="$REPO_SRC/hooks/lib/pane-modal.sh"
  [ -f "$HF" ] && [ -f "$LIB" ] || { echo "subject missing" >&2; return 1; }

  # Pinned, never ambient (M11 / MACHINE_CAPACITY_V2 §11.3), one export per line for the pin ratchet.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  export H="$BATS_TEST_TMPDIR/home"; mkdir -p "$H/.claude/bin"; export HOME="$H"
  export CC_HANDOFF_ALARM_DIR="$H/.claude/handoff-alarms"
  export CC_PANE_MODAL_LIB="$LIB"
  export CC_NOTIFY_BIN="$H/.claude/bin/cc-notify"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CC_NOTIFY_BIN"; chmod +x "$CC_NOTIFY_BIN"

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SHIM/osascript"
  # pane_cc_state's ROOT query is the slow read; it answers no processes, so the pane reads
  # `unknown` and the loop never leaves. Every other ps form is the real one.
  cat > "$SHIM/ps" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"-o pid= -t"*) date +%s >> "$HOME/ps-roots.log"; /bin/sleep "${PS_SLOW_S:-3}"; exit 0 ;;
esac
exec /bin/ps "$@"
SH
  chmod +x "$SHIM/osascript" "$SHIM/ps"
  export PATH="$SHIM:$PATH"

  export SCREEN="$BATS_TEST_TMPDIR/screen.txt"
  printf '%s\n' \
    "   Background work is running" "   The following will stop when you exit:" "" "   shell · sleep 600" "" \
    "   ❯ 1. Exit and stop tasks" "     2. Move to background and exit" "     3. Stay" "" \
    "   Enter to confirm · Esc to cancel" > "$SCREEN"
  export STUB_PANE="WALL-PANE"
  cat > "$H/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "${STUB_PANE:-WALL-PANE}"
    else printf '%s\n' "${STUB_PANE:-WALL-PANE}"; fi
    exit 0 ;;
  "session read") date +%s >> "$HOME/reads.log"; cat "$SCREEN"; exit 0 ;;
esac
exit 0
SH
  chmod +x "$H/.claude/bin/it2"

  CMDFILE="$BATS_TEST_TMPDIR/relaunch.cmd"; printf 'claude --permission-mode auto\n' > "$CMDFILE"
  # The answer is OFF so the dialog is only READ and REPORTED ("bgwork@<N>s … holding"), never sent.
  export CMDFILE CC_RECYCLE_BGWORK_ANSWER=off CC_RECYCLE_BGWORK_EVERY_S=3 HF_RECYCLE_SHELL_POLL_S=1
  export HF_RECYCLE_SHELL_WAIT_S=9
}

@test "[RED] shell wait: 'bgwork@<N>s' is at least the wall seconds since the loop's first read when each read is slow" {
  run bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR"
  local n first read slack=3
  n="$(printf '%s\n' "$output" | grep -o 'bgwork@[0-9]*s' | head -1 | tr -dc '0-9')"
  first="$(head -1 "$H/ps-roots.log" 2>/dev/null)"
  read="$(head -1 "$H/reads.log" 2>/dev/null)"
  echo "n=$n first=$first read=$read"; echo "$output"
  [ -n "$n" ]
  [ -n "$first" ]
  [ -n "$read" ]
  echo "reported=${n}s wall=$((read - first))s" >&3
  [ $((n + slack)) -ge $((read - first)) ] \
    || { echo "reported ${n}s for $((read - first)) wall seconds — a sum of sleeps, not a clock"; false; }
}

@test "[RED] shell wait: the bound HF_RECYCLE_SHELL_WAIT_S holds in wall seconds" {
  # 9 s of sleep-sum is 9 iterations, ~36 wall seconds at 3 s a read; in wall seconds the loop gives
  # up within one slow iteration of the bound. Measured from the first slow read to the LAST one,
  # which comes after the loop: the watcher re-reads the pane twice on the way out (the at_shell
  # re-check and the dead verdict), so the allowance is the in-flight iteration plus those reads,
  # four reads in all. The sleep-sum code spans ~42 s here; the wall-clock code ~15 s.
  run bash "$HF" __recycle "$STUB_PANE" "$BATS_TEST_TMPDIR/no-such-tty" "$CMDFILE" "$BATS_TEST_TMPDIR"
  local first last bound=9 iter=$(( 4 * ${PS_SLOW_S:-3} + 1 ))
  first="$(head -1 "$H/ps-roots.log" 2>/dev/null)"
  last="$(tail -1 "$H/ps-roots.log" 2>/dev/null)"
  echo "$output"
  [ -n "$first" ]
  [ -n "$last" ]
  echo "loop span=$((last - first))s for a ${bound}s bound" >&3
  [ $((last - first)) -le $((bound + iter)) ] \
    || { echo "the ${bound}s bound ran $((last - first)) wall seconds"; false; }
}
