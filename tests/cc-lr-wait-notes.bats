#!/usr/bin/env bats
# bin/cc-lr — what every "in flight" / "QUEUED" / "END THE TURN" line owes its reader
# (lr-reliability 2026-10-10 REPORT D10 + the peer note, wave A item A6).
#
# The night of 2026-10-11: requests waited on a poller tick that held its lock 25-48 min while every
# wait line said "still in flight" and promised mail that never came. Each such line now names a
# deadline and the read to run after it, and names a tick that has held poller.lock past 600 s.
# MESSAGE ONLY: the exit codes are pinned unchanged below.
#
# HERMETIC: HOME, LR_STATE_DIR, LR_RECON_ROOT, LR_POLLER_LOCK_DIR in BATS_TEST_TMPDIR; cc-find and
# the actuators are stubs. The only process touched is a `sleep` this file starts and kills.

NOW=1790000500

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LR="$REPO/bin/cc-lr"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"; mkdir -p "$LR_RECON_ROOT/owned"
  export LR_RECON_NOW="$NOW" LR_RECON_WAKETIME=0
  export LR_POLLER_LOCK_DIR="$BATS_TEST_TMPDIR/poller.lock"
  SID="aaaaaaaa-1111-4000-8000-000000000001"
  export CC_LR_FIND_BIN="$BATS_TEST_TMPDIR/cc-find"
  export CC_LR_FLEET_BIN="$BATS_TEST_TMPDIR/lr-fleet.sh"
  export CC_LR_HANDOFF_BIN="$BATS_TEST_TMPDIR/lr-handoff.sh"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_LR_POLLER_LABEL="com.reso.lr-reset-poller"
  STUBBIN="$BATS_TEST_TMPDIR/stubbin"; mkdir -p "$STUBBIN"
  PATH="$STUBBIN:$PATH"; export PATH
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/launchctl.argv"\n' "$BATS_TEST_TMPDIR" > "$STUBBIN/launchctl"
  printf '#!/usr/bin/env bash\nexit 97\n' > "$CC_ACCOUNTS_BIN"
  printf '#!/usr/bin/env bash\nif [ "$1" = --limited ]; then printf "%%s\\t117\\tclaude-next\\t%s/.claude-next\\t%s/wt\\tLIVE\\tLIMITED\\n" "%s"; exit 0; fi\nprintf "%%s\\t117\\tclaude-next\\t%s/.claude-next\\t%s/wt\\tLIVE\\tLIMITED\\n" "%s"\n' \
    "$HOME" "$HOME" "$SID" "$HOME" "$HOME" "$SID" > "$CC_LR_FIND_BIN"
  for s in "$CC_LR_FLEET_BIN" "$CC_LR_HANDOFF_BIN"; do
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/actuator.argv"\nexit 0\n' "$BATS_TEST_TMPDIR" > "$s"
  done
  chmod +x "$STUBBIN/launchctl" "$CC_ACCOUNTS_BIN" "$CC_LR_FIND_BIN" "$CC_LR_FLEET_BIN" "$CC_LR_HANDOFF_BIN"
  unset CLAUDE_CODE_SESSION_ID CC_PANE_ID ITERM_SESSION_ID KITTY_WINDOW_ID
  SLEEP_PID=""
}

teardown() {
  if [ -n "$SLEEP_PID" ]; then kill "$SLEEP_PID" 2>/dev/null || true; wait "$SLEEP_PID" 2>/dev/null || true; fi
}

recon_live() {
  : > "$LR_STATE_DIR/recon.on"
  printf '{"pid":1,"progress":7,"progress_wall":%s}' "$NOW" > "$LR_RECON_ROOT/heartbeat"
}
# A poller lock held by a live process, stamped the way lr-reset-poller.sh stamps it, <age> s old.
tick_lock() { # <age seconds> [lstart override]
  sleep 300 & SLEEP_PID=$!
  mkdir -p "$LR_POLLER_LOCK_DIR"
  echo "$SLEEP_PID" > "$LR_POLLER_LOCK_DIR/pid"
  if [ -n "${2:-}" ]; then printf '%s\n' "$2" > "$LR_POLLER_LOCK_DIR/lstart"
  else ps -o lstart= -p "$SLEEP_PID" | tr -s ' ' > "$LR_POLLER_LOCK_DIR/lstart"; fi
  touch -t "$(date -r "$(( $(date +%s) - $1 ))" +%Y%m%d%H%M.%S)" "$LR_POLLER_LOCK_DIR/pid"
}

@test "a recover QUEUED for the reconciler names its deadline and the read to run after it" {
  recon_live
  run bash "$LR" recover 117
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"cc-lr: expect a verdict by 20"*"Z; if no verdict by then: cc-lr status aaaaaaaa"* ]] || { echo "$output"; false; }
  [[ "$output" != *"poller tick pid"* ]] || { echo "$output"; false; }
}

@test "a live tick holding poller.lock for 15 min is named on the QUEUED line, and the rc is unchanged" {
  recon_live; tick_lock 900
  run bash "$LR" recover 117
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"cc-lr: poller tick pid $SLEEP_PID has held the lock for 15 min; your request has not started"* ]] || { echo "$output"; false; }
}

@test "CONTROL — a tick 2 min old, a dead holder, or a recycled pid (lstart differs) is never named" {
  recon_live; tick_lock 120
  run bash "$LR" recover 117
  [[ "$output" != *"poller tick pid"* ]] || { echo "young: $output"; false; }
  kill "$SLEEP_PID"; wait "$SLEEP_PID" 2>/dev/null || true; SLEEP_PID=""
  rm -f "$LR_STATE_DIR/requests/$SID.cc-lr.json"
  tick_lock 900 "Thu Jan  1 00:00:00 1970"
  run bash "$LR" recover 117
  [[ "$output" != *"poller tick pid"* ]] || { echo "recycled: $output"; false; }
  kill "$SLEEP_PID"; wait "$SLEEP_PID" 2>/dev/null || true
  touch -t "$(date -r "$(( $(date +%s) - 900 ))" +%Y%m%d%H%M.%S)" "$LR_POLLER_LOCK_DIR/pid"
  SLEEP_PID=""
  run bash "$LR" recover 117
  [[ "$output" != *"poller tick pid"* ]] || { echo "dead: $output"; false; }
}

@test "recover --limited: the END THE TURN summary carries the deadline line and the stuck-tick line once" {
  recon_live; tick_lock 1500
  run bash "$LR" recover --limited
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Verdicts arrive as mail; END THE TURN."* ]] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c 'expect a verdict by')" -eq 1 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | grep -c "poller tick pid $SLEEP_PID has held the lock for 25 min")" -eq 1 ] || { echo "$output"; false; }
}
