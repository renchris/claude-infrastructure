#!/usr/bin/env bats
# lr-recon-watchdog.bats — the §C9 watchdog for the lr_recon daemon.
#
# Hermetic: HOME, LR_STATE_DIR and LR_RECON_ROOT live under $BATS_TEST_TMPDIR; kill and page are fakes
# that record their argv; sleep is `true`. The "daemon" holder is a real `sleep 900` this test starts,
# read with its REAL lstart, so condition 1 (the holder is alive) runs through the real /bin/ps.
# Clock and wake time are pinned through LR_RECON_NOW / LR_RECON_WAKETIME.

SUT="$BATS_TEST_DIRNAME/../scripts/limit-recover/lr-recon-watchdog.sh"
PLIST_DIR="$BATS_TEST_DIRNAME/../scripts/limit-recover"
T=1790000000
DEAD_LSTART="Mon Jan  1 00:00:00 2001"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"
  mkdir -p "$HOME" "$LR_RECON_ROOT" "$BATS_TEST_TMPDIR/bin"
  KLOG="$BATS_TEST_TMPDIR/kill.log"
  PLOG="$BATS_TEST_TMPDIR/page.log"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$KLOG" > "$BATS_TEST_TMPDIR/bin/fake-kill"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\n' "$PLOG" > "$BATS_TEST_TMPDIR/bin/fake-page"
  chmod +x "$BATS_TEST_TMPDIR/bin/fake-kill" "$BATS_TEST_TMPDIR/bin/fake-page"
  export LR_RECON_KILL="$BATS_TEST_TMPDIR/bin/fake-kill"
  export LR_RECON_PAGE="$BATS_TEST_TMPDIR/bin/fake-page"
  export LR_RECON_SLEEP=true
  export LR_RECON_WAKETIME=$((T - 100000))
  sleep 900 >/dev/null 2>&1 3>&- &  # outlives a 30-tick test under load; teardown kills it
  HOLDER=$!
  HOLDER_LSTART="$(TZ=UTC LC_ALL=C /bin/ps -o lstart= -p "$HOLDER" | tr -s ' ' | sed 's/^ //; s/ $//')"
  [ -n "$HOLDER_LSTART" ]
}

teardown() {
  [ -n "${HOLDER:-}" ] && kill "$HOLDER" 2>/dev/null || true
  [ -n "${HOLDER2:-}" ] && kill "$HOLDER2" 2>/dev/null || true
}

hb() {  # $1=pid $2=lstart $3=progress $4=wall $5=progress_wall
  printf '{"pid":%s,"lstart":"%s","progress":%s,"wall":%s.5,"uptime_raw":12.0,"progress_wall":%s.1}\n' \
    "$1" "$2" "$3" "$4" "$5" > "$LR_RECON_ROOT/heartbeat"
}

tick() {  # $1=now — one launchd tick
  LR_RECON_NOW="$1" run /bin/bash "$SUT"
  [ "$status" -eq 0 ]
}

fake_cpu() {  # route `ps -S -o time=` to $CPUF; every other ps call stays the real /bin/ps
  CPUF="$BATS_TEST_TMPDIR/cpu"
  printf '#!/bin/sh\ncase "$*" in *time=*) cat "%s"; exit 0 ;; esac\nexec /bin/ps "$@"\n' "$CPUF" \
    > "$BATS_TEST_TMPDIR/bin/fake-ps"
  chmod +x "$BATS_TEST_TMPDIR/bin/fake-ps"
  export LR_RECON_PS="$BATS_TEST_TMPDIR/bin/fake-ps"
}

ticks_cpu() {  # $1=from $2=to $3=start cs $4=cs added per 30 s tick — progress stays frozen throughout
  local now="$1" cs="$3"
  while [ "$now" -le "$2" ]; do
    printf '  %d:%02d.%02d\n' $((cs / 6000)) $((cs / 100 % 60)) $((cs % 100)) > "$CPUF"
    tick "$now"
    now=$((now + 30)); cs=$((cs + $4))
  done
}

@test "no heartbeat: exits 0 silently and writes nothing" {
  LR_RECON_NOW=$T run /bin/bash "$SUT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$LR_RECON_ROOT/watchdog.state" ]
  [ ! -e "$LR_RECON_ROOT/watchdog.log" ]
}

@test "(1) no kill inside 180 s of stalled progress (reads 30 s apart, last advance 100 s ago)" {
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 100)) $((T - 100))
  tick $((T - 100))
  tick $((T - 70))
  tick "$T"
  [ ! -e "$KLOG" ]
  grep -q '^progress=7$' "$LR_RECON_ROOT/watchdog.state"
  grep -q "^progress_seen=$((T - 100))\$" "$LR_RECON_ROOT/watchdog.state"
}

@test "179 s since first seeing the value is still no kill, even with an older progress_wall" {
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 179)) $((T - 400))
  tick $((T - 179))
  tick "$T"
  [ ! -e "$KLOG" ]
}

@test "(2) no kill within 120 s of a wake (stalled 400 s, woke 60 s ago)" {
  export LR_RECON_WAKETIME=$((T - 60))
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 300)) $((T - 400))
  tick $((T - 300))
  tick "$T"
  [ ! -e "$KLOG" ]
  grep -q 'woke 60s ago — no kill' "$LR_RECON_ROOT/watchdog.log"
}

@test "(3) kill after two stale reads: TERM, then KILL when the same holder survives" {
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 300)) $((T - 400))
  tick $((T - 300))
  [ ! -e "$KLOG" ]
  tick "$T"
  [ "$(sed -n 1p "$KLOG")" = "-TERM $HOLDER" ]
  [ "$(sed -n 2p "$KLOG")" = "-KILL $HOLDER" ]
  grep -q "KILL -TERM pid=$HOLDER" "$LR_RECON_ROOT/watchdog.log"
}

@test "W7d: a slow holder (CPU advancing, progress frozen 300 s) is not killed" {
  fake_cpu
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 300)) $((T - 300))
  ticks_cpu $((T - 300)) "$T" 6100 20  # 0.20 s a tick: a starved pass, 1.2 s per 180 s window
  [ ! -e "$KLOG" ]
  grep -q "slow, not stalled: pid=$HOLDER progress=7 unchanged 300s, CPU +1.20s over the last 180s" \
    "$LR_RECON_ROOT/watchdog.log"
}

@test "W7d: a wedged holder (CPU frozen but for heartbeat noise) is killed at 180 s" {
  fake_cpu
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 300)) $((T - 300))
  ticks_cpu $((T - 300)) $((T - 150)) 6100 1  # 0.01 s a tick: the heartbeat thread alone
  [ ! -e "$KLOG" ]
  ticks_cpu $((T - 120)) $((T - 120)) 6106 0
  [ "$(sed -n 1p "$KLOG")" = "-TERM $HOLDER" ]
  grep -q "KILL -TERM pid=$HOLDER: progress=7 unchanged 180s; CPU +0.06s over the last 180s, under the 0.50s floor" \
    "$LR_RECON_ROOT/watchdog.log"
}

@test "W7d: a holder that was working and then wedged dies once the trailing window is quiet" {
  fake_cpu
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 600)) $((T - 600))
  ticks_cpu $((T - 600)) $((T - 360)) 100 50  # working hard for 240 s
  ticks_cpu $((T - 330)) $((T - 210)) 500 0   # then frozen: the last 0.5 s is still in the window
  [ ! -e "$KLOG" ]
  ticks_cpu $((T - 180)) $((T - 180)) 500 0   # the last advance has aged out of the window
  [ "$(sed -n 1p "$KLOG")" = "-TERM $HOLDER" ]
}

@test "a progressing holder that burns CPU is not killed at 900 s (a slow, I/O-bound pass)" {
  fake_cpu
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 900)) $((T - 900))
  ticks_cpu $((T - 900)) "$T" 100 100  # 2026-10-08: progress 564 frozen under load 404, 83% in lstat
  [ ! -e "$KLOG" ]
  grep -q "slow, not stalled: pid=$HOLDER progress=7 unchanged 900s, CPU +6.00s over the last 180s" \
    "$LR_RECON_ROOT/watchdog.log"
  grep -q "working-holder ceiling 3600s — no kill" "$LR_RECON_ROOT/watchdog.log"
}

@test "frozen progress past 3600 s is killed even while it burns CPU (a spinning loop)" {
  fake_cpu
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 3600)) $((T - 3600))
  ticks_cpu $((T - 3600)) $((T - 3600)) 100 100
  ticks_cpu $((T - 210)) $((T - 30)) 2000 100
  [ ! -e "$KLOG" ]
  ticks_cpu "$T" "$T" 2700 100
  [ "$(sed -n 1p "$KLOG")" = "-TERM $HOLDER" ]
  grep -q "unchanged 3600s; past the 3600s ceiling, whatever its CPU" "$LR_RECON_ROOT/watchdog.log"
}

@test "a first pass (progress 0) that accrues CPU is not killed at 900 s" {
  fake_cpu
  E="$(TZ=UTC LC_ALL=C date -j -f '%a %b %d %T %Y' "$HOLDER_LSTART" +%s)"
  hb "$HOLDER" "$HOLDER_LSTART" 0 "$E" "$E"
  ticks_cpu $((E + 10)) $((E + 910)) 100 20  # 2026-10-07: ~860 s first passes, 0.9 s CPU per 180 s
  [ ! -e "$KLOG" ]
  grep -q "slow, not stalled: pid=$HOLDER progress=0 unchanged 900s, CPU +1.20s over the last 180s" \
    "$LR_RECON_ROOT/watchdog.log"
}

@test "a holder with no CPU reading still dies at the 900 s ceiling" {
  fake_cpu
  printf 'garbage\n' > "$CPUF"
  E="$(TZ=UTC LC_ALL=C date -j -f '%a %b %d %T %Y' "$HOLDER_LSTART" +%s)"
  hb "$HOLDER" "$HOLDER_LSTART" 0 "$E" "$E"
  tick $((E + 10))
  tick $((E + 880))
  [ ! -e "$KLOG" ]
  tick $((E + 910))
  [ "$(sed -n 1p "$KLOG")" = "-TERM $HOLDER" ]
  grep -q "progress=0 unchanged 900s; past the 900s ceiling with no CPU evidence of work" \
    "$LR_RECON_ROOT/watchdog.log"
}

@test "W7d: an unparsable CPU reading is no verdict, never a kill" {
  fake_cpu
  printf 'garbage\n' > "$CPUF"
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 300)) $((T - 300))
  tick $((T - 300))
  tick "$T"
  [ ! -e "$KLOG" ]
  grep -q "no CPU reading across 180s yet — no kill" "$LR_RECON_ROOT/watchdog.log"
}

@test "W7d: a fresh holder at progress 0 is spared by the startup grace, then judged after it" {
  fake_cpu
  E="$(TZ=UTC LC_ALL=C date -j -f '%a %b %d %T %Y' "$HOLDER_LSTART" +%s)"
  hb "$HOLDER" "$HOLDER_LSTART" 0 "$E" "$E"
  ticks_cpu $((E + 10)) $((E + 580)) 100 0  # CPU frozen too: only the grace spares it
  [ ! -e "$KLOG" ]
  grep -q "first pass: progress=0 for 570s, holder started 580s ago (startup grace 600s) — no kill" \
    "$LR_RECON_ROOT/watchdog.log"
  ticks_cpu $((E + 610)) $((E + 610)) 100 0
  [ "$(sed -n 1p "$KLOG")" = "-TERM $HOLDER" ]
}

@test "progress that advances between reads is never killed" {
  hb "$HOLDER" "$HOLDER_LSTART" 7 $((T - 300)) $((T - 400))
  tick $((T - 300))
  hb "$HOLDER" "$HOLDER_LSTART" 8 "$T" $((T - 400))
  tick "$T"
  [ ! -e "$KLOG" ]
}

@test "a holder whose lstart mismatches (pid reuse) is not killed" {
  hb "$HOLDER" "$DEAD_LSTART" 7 $((T - 300)) $((T - 400))
  tick $((T - 300))
  hb "$HOLDER" "$DEAD_LSTART" 7 "$T" $((T - 400))
  tick "$T"
  [ ! -e "$KLOG" ]
  [ ! -e "$PLOG" ]
}

@test "(4) crash loop: one page at the second restart, latched for 15 min" {
  printf 'starting\nTraceback: boom-marker\n' > "$LR_RECON_ROOT/reconciler.err"
  hb "$HOLDER" "$HOLDER_LSTART" 1 "$T" "$T"
  tick "$T"
  hb 999991 "$DEAD_LSTART" 1 $((T + 60)) $((T + 60))
  tick $((T + 60))
  [ ! -e "$PLOG" ]
  hb 999992 "$DEAD_LSTART" 1 $((T + 120)) $((T + 120))
  tick $((T + 120))
  [ "$(wc -l < "$PLOG" | tr -d ' ')" -eq 1 ]
  grep -q 'crash loop' "$PLOG"
  grep -q 'boom-marker' "$PLOG"
  hb 999993 "$DEAD_LSTART" 1 $((T + 300)) $((T + 300))
  tick $((T + 300))
  [ "$(wc -l < "$PLOG" | tr -d ' ')" -eq 1 ]
  [ ! -e "$KLOG" ]
}

wedge_and_kill() {  # $1=pid $2=lstart $3=first tick — progress frozen, CPU 0 (a real sleep): killed at +180
  hb "$1" "$2" 7 "$3" "$3"
  tick "$3"
  tick $(($3 + 180))
  grep -q "KILL -TERM pid=$1:" "$LR_RECON_ROOT/watchdog.log"
}

@test "W7d: two watchdog kills in 10 min page as kills, never as a crash loop" {
  sleep 900 >/dev/null 2>&1 3>&- &
  HOLDER2=$!
  L2="$(TZ=UTC LC_ALL=C /bin/ps -o lstart= -p "$HOLDER2" | tr -s ' ' | sed 's/^ //; s/ $//')"
  wedge_and_kill "$HOLDER" "$HOLDER_LSTART" "$T"
  grep -q "^kills=$((T + 180))@${HOLDER}@" "$LR_RECON_ROOT/watchdog.state"
  wedge_and_kill "$HOLDER2" "$L2" $((T + 210))  # KeepAlive's restart, which we then kill too
  hb 999993 "$DEAD_LSTART" 1 $((T + 420)) $((T + 420))
  tick $((T + 420))
  kill "$HOLDER2" 2>/dev/null || true
  [ "$(grep -c "restart after this watchdog's kill — not a crash" "$LR_RECON_ROOT/watchdog.log")" -eq 2 ]
  grep -q '^pid_changes=$' "$LR_RECON_ROOT/watchdog.state"
  ! grep -q 'crash loop' "$PLOG" || false
  [ "$(wc -l < "$PLOG" | tr -d ' ')" -eq 1 ]
  grep -q "watchdog killed 2 stalled holders within 10 min (now pid 999993)" "$PLOG"
}

@test "W7d: two watchdog kills more than 10 min apart page nothing" {
  sleep 900 >/dev/null 2>&1 3>&- &
  HOLDER2=$!
  L2="$(TZ=UTC LC_ALL=C /bin/ps -o lstart= -p "$HOLDER2" | tr -s ' ' | sed 's/^ //; s/ $//')"
  wedge_and_kill "$HOLDER" "$HOLDER_LSTART" "$T"
  wedge_and_kill "$HOLDER2" "$L2" $((T + 630))  # killed at T+810, 630 s after the first
  hb 999993 "$DEAD_LSTART" 1 $((T + 840)) $((T + 840))
  tick $((T + 840))
  kill "$HOLDER2" 2>/dev/null || true
  [ ! -e "$PLOG" ]
}

@test "W7d: an external restart after a watchdog kill still counts, so the next one is a crash loop" {
  wedge_and_kill "$HOLDER" "$HOLDER_LSTART" "$T"
  hb 999991 "$DEAD_LSTART" 1 $((T + 210)) $((T + 210))
  tick $((T + 210))  # ours: the restart after the kill
  hb 999992 "$DEAD_LSTART" 1 $((T + 240)) $((T + 240))
  tick $((T + 240))  # external #1
  [ ! -e "$PLOG" ]
  hb 999993 "$DEAD_LSTART" 1 $((T + 270)) $((T + 270))
  tick $((T + 270))  # external #2
  grep -q "crash loop — holder pid changed 2 times" "$PLOG"
}

@test "two restarts more than 10 min apart are not a crash loop" {
  hb 999991 "$DEAD_LSTART" 1 "$T" "$T"
  tick "$T"
  hb 999992 "$DEAD_LSTART" 1 $((T + 60)) $((T + 60))
  tick $((T + 60))
  hb 999993 "$DEAD_LSTART" 1 $((T + 700)) $((T + 700))
  tick $((T + 700))
  [ ! -e "$PLOG" ]
}

@test "heartbeat stale >60 s with no live holder pages once per 15 min" {
  hb 999991 "$DEAD_LSTART" 1 $((T - 61)) $((T - 61))
  tick "$T"
  [ "$(wc -l < "$PLOG" | tr -d ' ')" -eq 1 ]
  grep -q 'heartbeat stale 61s' "$PLOG"
  tick $((T + 600))
  [ "$(wc -l < "$PLOG" | tr -d ' ')" -eq 1 ]
  tick $((T + 900))
  [ "$(wc -l < "$PLOG" | tr -d ' ')" -eq 2 ]
}

@test "a stale heartbeat with a LIVE holder does not page" {
  hb "$HOLDER" "$HOLDER_LSTART" 1 $((T - 120)) $((T - 120))
  tick "$T"
  [ ! -e "$PLOG" ]
}

@test "the default page goes through lr-page.sh, and only a posted page latches" {
  unset LR_RECON_PAGE
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\nexit "${OSA_RC:-0}"\n' "$PLOG" > "$BATS_TEST_TMPDIR/bin/osa"
  chmod +x "$BATS_TEST_TMPDIR/bin/osa"
  export LR_PAGE_OS_CHANNEL=on LR_PAGE_OSASCRIPT_BIN="$BATS_TEST_TMPDIR/bin/osa"
  export LR_PAGE_LOG="$BATS_TEST_TMPDIR/pages.log" LR_PAGE_CREDS="$BATS_TEST_TMPDIR/none"
  hb 999991 "$DEAD_LSTART" 1 $((T - 61)) $((T - 61))
  OSA_RC=1 tick "$T"
  grep -q "PAGE FAILED" "$LR_RECON_ROOT/watchdog.log"
  [ "$(grep -c "PAGE: lr-reconciler" "$LR_RECON_ROOT/watchdog.log")" = 0 ]
  tick $((T + 30))  # the failure did not latch: this run pages, through Notification Center
  [ "$(grep -c "PAGE: lr-reconciler" "$LR_RECON_ROOT/watchdog.log")" = 1 ]
  grep -q "reconciler-watchdog" "$PLOG"
  grep -q "heartbeat stale" "$PLOG"
  tick $((T + 60))  # the posted page latched
  [ "$(grep -c "PAGE: lr-reconciler" "$LR_RECON_ROOT/watchdog.log")" = 1 ]
}

@test "bash -n under /bin/bash (the launchd interpreter)" {
  run /bin/bash -n "$SUT"
  [ "$status" -eq 0 ]
}

@test "shellcheck bare is clean" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  run shellcheck "$SUT"
  [ "$status" -eq 0 ]
}

@test "the three reconciler plists pass plutil -lint" {
  command -v plutil >/dev/null || skip "plutil not available"
  run plutil -lint "$PLIST_DIR/com.reso.lr-reconciler.plist" \
    "$PLIST_DIR/com.reso.lr-reconciler-watchdog.plist" "$PLIST_DIR/com.reso.lr-reconciler-rig.plist"
  [ "$status" -eq 0 ]
}
