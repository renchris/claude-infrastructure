#!/usr/bin/env bats
# handoff-fire.sh — the keystroke-free successor's PRODUCER and the watcher's CLAIM-OR-REVOKE
# (docs/plans/RECYCLE_KEYSTROKELESS_DELIVERY.md §D1; the 2026-10-09 pane-44 strand).
#
# A fresh-mode recycle stages its relaunch (lib/pane-successor.sh) before the /exit; whichever process
# regains the pane's tty runs it, and the watcher learns the outcome from the claim rename. These cases
# drive the REAL lib against the REAL watcher, with an it2 stub that times out on every send — the
# slowest pane-44 reading — so a successor that starts here started with no keystrokes at all.

setup() {
  # M11 pins (tests/handoff-fire-capacity-gate.bats PIN-GUARD): this suite fires; the gate is not its subject.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_DIR KITTY_WINDOW_ID KITTY_LISTEN_ON CC_TERM \
        RESUME_LAUNCHER RCY_TRANSPLANT_CAUSE CC_PANE_SUCCESSOR CC_PANE_SUCCESSOR_TTY CC_PANE_SUCCESSOR_NOW
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export CC_PANE_SUCCESSOR_LIB="$REPO/lib/pane-successor.sh"
  [ -f "$CC_PANE_SUCCESSOR_LIB" ] || { echo "lib missing: $CC_PANE_SUCCESSOR_LIB" >&2; return 1; }
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin" "$HOME/.claude/logs" "$HOME/.claude/autonomy"
  export CC_PANE_SUCCESSOR_DIR="$BATS_TEST_TMPDIR/succ"
  export HF_LOAD_PER_CORE=0
}

# ── THE PRODUCER ─────────────────────────────────────────────────────────────────────────────────
producer_funcs() {
  local f
  for f in _iso_now _under_test emit_recycle_event hf_load_per_core hf_succ_lib_load hf_succ_mode hf_succ_stage; do
    eval "$(sed -n "/^$f() {/,/^}/p" "$HF")"
    declare -F "$f" >/dev/null || { echo "could not extract $f" >&2; return 1; }
  done
  TARGET_CFG="$BATS_TEST_TMPDIR/cfg-next2"
  config_dir_for_launcher() { [ "$1" = claude2 ] && echo "$TARGET_CFG"; }
  # shellcheck disable=SC2034  # read by the sourced hf_succ_stage through dynamic scope
  LAUNCHER=claude2 SID=44 WATCHER_PID=$$ rcy_old_sid=6defb493
  CMD="echo \"\$CLAUDE_CONFIG_DIR\" > '$BATS_TEST_TMPDIR/ran-with'"
  BASE="$BATS_TEST_TMPDIR/handoff-recycle-cmd-44.sh"; printf '%s\n' "$CMD" > "$BASE"
}

@test "fresh mode stages a self-sufficient .cmd: an explicit CLAUDE_CONFIG_DIR that beats the consumer's inherited one" {
  producer_funcs
  run hf_succ_stage /dev/ttys013 "$BASE"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local c="$CC_PANE_SUCCESSOR_DIR/ttys013.cmd" m="$CC_PANE_SUCCESSOR_DIR/ttys013.json"
  [ -f "$c" ] || { echo "no .cmd staged"; ls -la "$CC_PANE_SUCCESSOR_DIR"; false; }
  [ -f "$m" ] || { echo "no meta staged"; ls -la "$CC_PANE_SUCCESSOR_DIR"; false; }
  grep -qx "export CLAUDE_CONFIG_DIR=$TARGET_CFG" "$c" || { cat "$c"; false; }
  grep -qx 'export CC_ACCOUNT_PINNED=1' "$c"
  [ "$(jq -r '.mode' "$m")" = fresh ]
  [ "$(jq -r '.watcher_pid' "$m")" = "$$" ]
  [ "$(jq -r '.pane_tty' "$m")" = /dev/ttys013 ]
  [ -n "$(jq -r '.watcher_lstart' "$m")" ]
  # The predecessor's account must not reach the successor: source it the way the consumer does,
  # from a shell that still carries a DIFFERENT config dir.
  CLAUDE_CONFIG_DIR=/predecessor/cfg bash -c '. "$1"' _ "$c"
  [ "$(cat "$BATS_TEST_TMPDIR/ran-with")" = "$TARGET_CFG" ]
}

@test "resume, transplant and remote recycles NEVER stage — their rails run in the watcher first" {
  producer_funcs
  RESUME_LAUNCHER=/tmp/lr-launch.sh run hf_succ_stage /dev/ttys013 "$BASE"
  [ "$status" -eq 1 ]; [[ "$output" == *"resume recycle"* ]] || { echo "$output"; false; }
  RCY_TRANSPLANTED_SOURCE=1 run hf_succ_stage /dev/ttys013 "$BASE"
  [ "$status" -eq 1 ]; [[ "$output" == *"transplant recycle"* ]] || { echo "$output"; false; }
  RCY_TRANSPLANT_CAUSE=voluntary run hf_succ_stage /dev/ttys013 "$BASE"
  [ "$status" -eq 1 ]
  RCY_REMOTE=1 run hf_succ_stage /dev/ttys013 "$BASE"
  [ "$status" -eq 1 ]; [[ "$output" == *"remote recycle"* ]] || { echo "$output"; false; }
  [ ! -e "$CC_PANE_SUCCESSOR_DIR/ttys013.cmd" ] || { ls -la "$CC_PANE_SUCCESSOR_DIR"; false; }
}

@test "an absent lib or no target config dir is one line and the typed path — never a failed recycle" {
  producer_funcs
  CC_PANE_SUCCESSOR_LIB="$BATS_TEST_TMPDIR/nope.sh" HF_DIR="$BATS_TEST_TMPDIR/nowhere" HOME="$BATS_TEST_TMPDIR/nohome" \
    run hf_succ_stage /dev/ttys013 "$BASE"
  [ "$status" -eq 1 ]; [[ "$output" == *"lib/pane-successor.sh not found"* ]] || { echo "$output"; false; }
  LAUNCHER=claude-nobody run hf_succ_stage /dev/ttys013 "$BASE"
  [ "$status" -eq 1 ]; [[ "$output" == *"no config dir"* ]] || { echo "$output"; false; }
  [ ! -e "$CC_PANE_SUCCESSOR_DIR/ttys013.cmd" ]
}

# ── THE WATCHER ──────────────────────────────────────────────────────────────────────────────────
# Fresh-mode __recycle, run in the BACKGROUND so the test can stage for its real pid and play the
# consumer. `ps` (the watcher's PATH only) reads a claude on the pane while $HOME/pane-cc exists and a
# bare zsh otherwise; the consumer side uses the real ps, which is what the lib's watcher proof reads.
# it2 times out on EVERY send (rc 124) and echoes nothing.
watcher_world() {
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms" CC_NOTIFY_BIN="$HOME/.claude/bin/cc-notify"
  export CC_ADMIT_IDL="$HOME/.claude/autonomy/idl.jsonl"; : > "$CC_ADMIT_IDL"
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/cc-resume-debt"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CC_NOTIFY_BIN"; printf '#!/usr/bin/env bash\nexit 0\n' > "$CC_RESUME_DEBT_BIN"
  chmod +x "$CC_NOTIFY_BIN" "$CC_RESUME_DEBT_BIN"
  WSHIM="$BATS_TEST_TMPDIR/wshim"; mkdir -p "$WSHIM"
  cat > "$WSHIM/ps" <<'SH'
#!/usr/bin/env bash
args="$*"
cc=0; [ -f "$HOME/pane-cc" ] && cc=1
case "$args" in *pgid=*) printf '4242\n'; exit 0 ;; esac
case "$args" in *lstart=*) printf 'Tue Sep 29 10:00:00 2026\n'; exit 0 ;; esac
case "$args" in
  *"-axww -o args="*) [ "$cc" = 1 ] && printf 'claude --permission-mode auto\n'; exit 0 ;;
  *"-o pid= -t"*)     printf '100\n' ;;
  *"-o tpgid= -t"*)   printf '100\n' ;;
  *"-o comm= -t"*)    if [ "$cc" = 1 ]; then printf 'claude\n'; else printf -- '-zsh\n'; fi ;;
  *pid=,ppid=*)       printf '100 1\n' ;;
  *"pid=,comm= -g"*)  printf '100 /bin/zsh\n' ;;
  *"-p 100"*)         if [ "$cc" = 1 ]; then printf 'claude\n'; else printf '/bin/zsh\n'; fi ;;
esac
exit 0
SH
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WSHIM/osascript"
  chmod +x "$WSHIM/ps" "$WSHIM/osascript"
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    if [ "${3:-}" = --json ]; then printf '[{"id": "SUCC-PANE", "tty": "/dev/ttys999"}]\n'
    else printf 'SUCC-PANE\n'; fi; exit 0 ;;
  "session send") exit 124 ;;
esac
exit 0
SH
  chmod +x "$HOME/.claude/bin/it2"
  WTTY="$BATS_TEST_TMPDIR/ttys999"; : > "$WTTY"
  WCMDF="$BATS_TEST_TMPDIR/relaunch.cmd"; printf 'cd /tmp && bash /tmp/lr-launch-succ.sh\n' > "$WCMDF"
  MARK="$BATS_TEST_TMPDIR/successor-ran"
  : > "$HOME/pane-cc"                                    # the predecessor is up when the watcher starts
}

start_watcher() { # → WPID; the watcher's stdout+stderr in $WOUT
  WOUT="$BATS_TEST_TMPDIR/watcher.out"
  PATH="$WSHIM:$PATH" IT2_BIN="$HOME/.claude/bin/it2" \
    HF_RECYCLE_SHELL_WAIT_S="${SHELL_WAIT:-60}" CC_RECYCLE_CLAIM_GRACE_S="${GRACE:-20}" \
    CC_RECYCLE_TYPE_DEADLINE_S=0 FIRE_TYPE_ATTEMPTS=1 FIRE_TYPE_SETTLE=0 FIRE_TYPE_PRESETTLE=0 \
    RCY_BOOT_WAIT_S=1 RCY_BOOT_STALE_S=2 RCY_BOOT_IVL_S=0.2 RCY_BOOT_SLOW_IVL_S=1 RCY_BOOT_PANE_EVERY=2 \
    RCY_ENGAGE_TIMEOUT=2 \
    bash "$HF" __recycle SUCC-PANE "$WTTY" "$WCMDF" /tmp > "$WOUT" 2>&1 3>&- &   # fd 3 closed: bats waits on it
  WPID=$!
}

stage_for_watcher() { # the producer's half, for the watcher's REAL pid + start time
  local wl m="$BATS_TEST_TMPDIR/meta.json" c="$BATS_TEST_TMPDIR/succ.cmd" i=0
  # After the heartbeat, as the foreground does (await_armed): a stage written before the watcher sets
  # its claim floor rcy_w_t0 (easy under load, while bash still parses this 18K-line script) reads as
  # an older recycle's claim. Same wait as tests/handoff-recycle-recovery-packet.bats.
  until grep -q '^→ armed:' "$WOUT" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -le 300 ] || { echo "watcher never armed"; cat "$WOUT"; return 1; }
    sleep 0.1
  done
  sleep 1                                                # the stage's whole-second mtime lands at or after it
  wl="$(TZ=UTC LC_ALL=C /bin/ps -o lstart= -p "$WPID" | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  [ -n "$wl" ] || { echo "watcher $WPID has no lstart"; return 1; }
  printf 'touch %q\n' "$MARK" > "$c"
  jq -n --arg tty "$WTTY" --arg wp "$WPID" --arg wl "$wl" --arg ce "$(date +%s)" \
     '{pane:"SUCC-PANE", pane_tty:$tty, pred_sid:"", watcher_pid:($wp|tonumber), watcher_lstart:$wl,
       created_epoch:($ce|tonumber), ttl_s:900, mode:"fresh", token:"t"}' > "$m"
  # shellcheck source=/dev/null
  . "$CC_PANE_SUCCESSOR_LIB"
  cc_pane_successor_stage "$WTTY" "$c" "$m"
}

await_watcher() { # $1=seconds → 0 when the watcher exited inside the bound
  local i=0
  while kill -0 "$WPID" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -le $(( ${1:-90} * 5 )) ] || return 1
    sleep 0.2
  done
}
sends() { grep -c '^session send' "$HOME/it2-calls.log" 2>/dev/null || true; }

@test "THE INCIDENT, keystroke-free: under an always-timing-out it2 the consumer's claim starts the successor with ZERO sends" {
  watcher_world
  start_watcher
  stage_for_watcher
  # The predecessor exits and the pane's own shell (lr-fire-resume's fall-through) takes the stage.
  rm -f "$HOME/pane-cc"
  local claimed
  claimed="$(CC_PANE_SUCCESSOR_TTY=ttys999 bash -c '. "$1"; cc_pane_successor_take ttys999' _ "$CC_PANE_SUCCESSOR_LIB")" \
    || { echo "the consumer could not take the stage"; ls -la "$CC_PANE_SUCCESSOR_DIR"; cat "$WOUT"; false; }
  bash "$claimed"; : > "$HOME/pane-cc"                    # the successor claude is up
  await_watcher 90 || { kill "$WPID" 2>/dev/null; cat "$WOUT"; false; }
  [ -f "$MARK" ]
  grep -q 'successor claimed by the pane' "$WOUT" || { cat "$WOUT"; false; }
  [ "$(sends)" = 0 ] || { echo "sent $(sends) keystroke(s)"; cat "$HOME/it2-calls.log"; cat "$WOUT"; false; }
  grep -q '"class":"recycle-successor-claimed"' "$HOME/.claude/logs/handoffs.jsonl"
  ! grep -q 'relaunch typed into' "$WOUT" || { cat "$WOUT"; false; }
}

@test "no claim within the grace at a bare shell: the watcher REVOKES and the typed fallback runs" {
  watcher_world
  GRACE=2 start_watcher
  stage_for_watcher
  rm -f "$HOME/pane-cc"                                  # a shell with NO consumer: nothing takes it
  await_watcher 120 || { kill "$WPID" 2>/dev/null; cat "$WOUT"; false; }
  grep -q 'successor NOT claimed' "$WOUT" || { cat "$WOUT"; false; }
  [ -e "$CC_PANE_SUCCESSOR_DIR/ttys999.revoked" ] || { ls -la "$CC_PANE_SUCCESSOR_DIR"; false; }
  [ ! -e "$CC_PANE_SUCCESSOR_DIR/ttys999.cmd" ]
  [ ! -f "$MARK" ]
  grep -q 'lr-launch-succ.sh' "$HOME/it2-calls.log" || { echo "the typed fallback never ran"; cat "$WOUT"; false; }
  grep -q '"class":"recycle-successor-revoked"' "$HOME/.claude/logs/handoffs.jsonl"
}

@test "the watcher's EXIT trap revokes a stage still naming it (here: it gives up before any shell)" {
  watcher_world
  SHELL_WAIT=3 start_watcher
  stage_for_watcher
  # The pane never reaches a shell, so the watcher ends on its terminal arm with the stage untouched.
  await_watcher 120 || { kill "$WPID" 2>/dev/null; cat "$WOUT"; false; }
  [ -e "$CC_PANE_SUCCESSOR_DIR/ttys999.revoked" ] || { ls -la "$CC_PANE_SUCCESSOR_DIR"; cat "$WOUT"; false; }
  [ ! -e "$CC_PANE_SUCCESSOR_DIR/ttys999.cmd" ]
}

@test "nothing staged: the watcher types at once, as before (no grace wait, no successor lines)" {
  watcher_world
  GRACE=150 start_watcher
  rm -f "$HOME/pane-cc"
  await_watcher 100 || { kill "$WPID" 2>/dev/null; echo "the watcher waited out a grace with nothing staged"; cat "$WOUT"; false; }
  ! grep -q 'successor' "$WOUT" || { cat "$WOUT"; false; }
  grep -q 'lr-launch-succ.sh' "$HOME/it2-calls.log"
}
