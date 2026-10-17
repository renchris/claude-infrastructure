#!/usr/bin/env bats
# capacity-alarm — the X5 consumer and the X17 load-rung switch
# (docs/research/load-root-cause-2026-10-17/DESIGN.md rows X5 and X17, work package WP-17).
#
# What this suite pins:
#   1. `record-only` in the mode file keeps rung 7 on the row but out of the verdict, and retracts
#      a load page raised before the flip — on the first run, with no hand step;
#   2. without the word, the same load is today's ALARM (the control that proves the switch);
#   3. a fresh attrib-latest.json whose writer is alive (pid AND start) replaces the one-shot pass;
#      stale, dead, recycled or top-less files fall back to it;
#   4. no output advises closing sessions.
# `|| false` on every non-final [[ ]]/[ ] — errexit-exempt assertions are dead.
#
# RED proof: CC_CAP_ALARM_UNDER_TEST points every test at another copy of the script, so the suite
# can be run against the pre-change file (it must sit in a scripts/ dir beside lib/capacity-attrib.py).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs" "$HOME/.claude/autonomy/pages"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  A="${CC_CAP_ALARM_UNDER_TEST:-$REPO/scripts/capacity-alarm.sh}"
  D="$BATS_TEST_TMPDIR"
  export CC_CAP_LOG="$D/cap.jsonl"
  export CC_PAGES_DIR="$HOME/.claude/autonomy/pages"
  export CC_CAP_LOAD_RUNG_MODE_FILE="$D/load-rung.mode"
  export CC_CAP_ATTRIB_LOG="$D/attrib/attrib.jsonl"
  mkdir -p "$D/attrib"
  # Every rung but 7 pinned neutral (capacity-alarm.bats setup(), same reason: the verdict is a max
  # over live readings). Rung 7 is driven by a sysctl stub at the shipped floors.
  export CC_CAP_WARN_GB=0 CC_CAP_ALARM_GB=0
  export CC_CAP_PRESSURE_WARN=9999 CC_CAP_PRESSURE_ALARM=9999
  export CC_CAP_PROC_WARN_GB=999999
  export CC_CAP_SEG_WARN_PCT=999999 CC_CAP_SEG_ALARM_PCT=999999
  export CC_CAP_COAL_WARN=999999 CC_CAP_COAL_ALARM=999999
  export CC_CAP_SWAP_DELTA_MB=999999
  export CC_CAP_SWAPFILE_WARN=999999 CC_CAP_SWAPFILE_ALARM=999999
  export CC_CAP_KALLOC_WARN_GB=999999 CC_CAP_KALLOC_ALARM_GB=999999 CC_CAP_KALLOC=off
  export CC_CAP_LOAD_WARN_PER_CORE=1.5 CC_CAP_LOAD_ALARM_PER_CORE=2.5
  export CC_CAP_COAL_FP=0 CC_CAP_AUTO_COAL=0 CC_CAP_CONVOY=off
  export CC_CAP_ATTRIB=off
  # 130 on 10 cores = 13/core: past the ALARM floor by 5x, so only the switch can make it OK.
  printf '%s\n' '#!/bin/bash' \
    'case "$*" in' \
    "  *hw.ncpu*)    echo 10 ;;" \
    "  *vm.loadavg*) echo '{ 130.00 120.00 110.00 }' ;;" \
    '  *)            exec /usr/sbin/sysctl "$@" ;;' \
    'esac' > "$D/sysctl-load"
  chmod +x "$D/sysctl-load"
  export CC_CAP_SYSCTL="$D/sysctl-load"
}

row_field() { # <key> — from the LAST line of $output (the --json row); jq also proves it parses
  printf '%s\n' "$output" | tail -n 1 | jq -r --arg k "$1" '.[$k] | tostring'
}

# The one-shot pass, stubbed: records each call and prints a recognisable top line; every other
# python use in the alarm (vm_stat, coalition) reaches the real interpreter.
mk_python_stub() {
  printf '%s\n' '#!/bin/bash' \
    'case "${1:-}" in' \
    "  */capacity-attrib.py) echo \"\$*\" >> '$D/oneshot.calls'; echo '4242 333 oneshot-stub'; exit 0 ;;" \
    'esac' \
    'exec python3 "$@"' > "$D/python-stub"
  chmod +x "$D/python-stub"
  export CC_CAP_PYTHON="$D/python-stub" CC_CAP_ATTRIB=on
}

# The start key of a live pid, read by the PRODUCER's own read_pid — the method the daemon stamps
# attrib-latest.json with, so the consumer is checked against the writer, not against itself.
pid_start() {
  /usr/bin/python3 -I -B -c '
import importlib.util, sys
s = importlib.util.spec_from_file_location("ca", sys.argv[1])
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.read_pid(int(sys.argv[2]))["start"])' "$REPO/scripts/lib/capacity-attrib.py" "$1"
}

mk_latest() { # <pid> <start> [top-json] — the daemon's file, written now
  local top='["4242 777 from-daemon\n"]'
  printf '{"v":1,"pid":%s,"start":"%s","interval":5,"ticks":9,"errors":0,"err":null,"top":%s}\n' \
    "$1" "$2" "${3:-$top}" > "$D/attrib/attrib-latest.json"
}

@test "record-only: load 13/core with every other rung OK → rc 0, OK, no pages, load still on the row" {
  echo record-only > "$CC_CAP_LOAD_RUNG_MODE_FILE"
  run /bin/bash "$A" --json </dev/null
  [ "$status" -eq 0 ] || false
  [ "$(row_field verdict)" = OK ] || false
  [ "$(row_field load_1m)" = 130.00 ] || false
  [ "$(row_field load_per_core)" = 13.00 ] || false
  # the row that went to the log carries it too, not only stdout
  [ "$(tail -n 1 "$CC_CAP_LOG" | jq -r .load_1m)" = 130.00 ] || false
  [ ! -e "$CC_PAGES_DIR/capacity-alarm-load.page" ] || false
  [ ! -e "$CC_PAGES_DIR/capacity-alarm.page" ] || false
}

@test "record-only: a load page and combined page raised before the flip are gone after one run" {
  echo record-only > "$CC_CAP_LOAD_RUNG_MODE_FILE"
  local p
  for p in capacity-alarm-load.page capacity-alarm-load.page.notified capacity-alarm.page; do
    echo stale > "$CC_PAGES_DIR/$p"
  done
  run /bin/bash "$A" --quiet </dev/null
  [ "$status" -eq 0 ] || false
  [ ! -e "$CC_PAGES_DIR/capacity-alarm-load.page" ] || false
  [ ! -e "$CC_PAGES_DIR/capacity-alarm-load.page.notified" ] || false
  [ ! -e "$CC_PAGES_DIR/capacity-alarm.page" ] || false
}

@test "control: no mode file, or any other word, → the same load is today's ALARM with its pages" {
  run /bin/bash "$A" --json </dev/null
  [ "$status" -eq 2 ] || false
  [ "$(row_field verdict)" = ALARM ] || false
  [ -s "$CC_PAGES_DIR/capacity-alarm-load.page" ] || false
  [ -s "$CC_PAGES_DIR/capacity-alarm.page" ] || false
  echo "record-only please" > "$CC_CAP_LOAD_RUNG_MODE_FILE"
  run /bin/bash "$A" --json --no-append </dev/null
  [ "$status" -eq 2 ] || false
  [ "$(row_field verdict)" = ALARM ] || false
}

@test "selftest: record-only probes read the rung and leave the verdict OK" {
  run env -u CC_CAP_LOAD_WARN_PER_CORE -u CC_CAP_LOAD_ALARM_PER_CORE /bin/bash "$A" --selftest </dev/null
  [[ "$output" =~ "control OK   record-only load='5.98' → OK load=ALARM" ]] || false
  [[ "$output" =~ "control OK   record-only load='?' → OK load=SKIPPED" ]] || false
  ! [[ "$output" =~ "control FAIL record-only" ]] || false
}

@test "fresh attrib-latest.json, live pid@start → no one-shot pass, top_procs from the file" {
  mk_python_stub
  mk_latest "$$" "$(pid_start "$$")"
  run /bin/bash "$A" --json --no-append </dev/null
  [ ! -e "$D/oneshot.calls" ] || false
  [ "$(row_field top_src)" = attrib ] || false
  [ "$(printf '%s\n' "$output" | tail -n 1 | jq -r '.top_procs[0].cmd')" = from-daemon ] || false
  [ "$(printf '%s\n' "$output" | tail -n 1 | jq -r '.top_procs[0].mb')" = 777 ] || false
}

@test "stale file, dead pid, recycled pid or no top yet → the one-shot pass runs" {
  mk_python_stub
  local start dead
  start="$(pid_start "$$")"
  # stale: written a minute ago
  mk_latest "$$" "$start"
  touch -t "$(date -v-60S +%Y%m%d%H%M.%S)" "$D/attrib/attrib-latest.json"
  run /bin/bash "$A" --json --no-append </dev/null
  [ "$(wc -l < "$D/oneshot.calls" | tr -d ' ')" = 1 ] || false
  [ "$(printf '%s\n' "$output" | tail -n 1 | jq -r '.top_procs[0].cmd')" = oneshot-stub ] || false
  # dead: a reaped child's pid
  ( : ) & dead=$!; wait "$dead"
  mk_latest "$dead" "$start"
  run /bin/bash "$A" --json --no-append </dev/null
  [ "$(wc -l < "$D/oneshot.calls" | tr -d ' ')" = 2 ] || false
  # recycled: the pid is alive but is not the process that wrote the file
  mk_latest "$$" "1.000000"
  run /bin/bash "$A" --json --no-append </dev/null
  [ "$(wc -l < "$D/oneshot.calls" | tr -d ' ')" = 3 ] || false
  # alive and fresh, no pass finished yet: the one-shot runs, and --no-write even on an appending
  # run, so it never advances the daemon's delta state
  mk_latest "$$" "$start" null
  run /bin/bash "$A" --json </dev/null
  [ "$(wc -l < "$D/oneshot.calls" | tr -d ' ')" = 4 ] || false
  [[ "$(tail -n 1 "$D/oneshot.calls")" == *"/capacity-attrib.py --no-write" ]] || false
}

@test "no output advises closing sessions — stdout, the combined page or any rung page" {
  # every acute page that carries remedy text: load (rung 7) and headroom (rung 2)
  run env CC_CAP_WARN_GB=999999 CC_CAP_ALARM_GB=999999 /bin/bash "$A" </dev/null
  [ "$status" -eq 2 ] || false
  [ -s "$CC_PAGES_DIR/capacity-alarm-load.page" ] || false
  [ -s "$CC_PAGES_DIR/capacity-alarm-headroom.page" ] || false
  local all
  all="$(printf '%s\n' "$output"; cat "$CC_PAGES_DIR"/*.page)"
  ! printf '%s\n' "$all" | grep -qi 'closing' || false
  ! printf '%s\n' "$all" | grep -qiE 'close[a-z]* [a-z ]*session' || false
  printf '%s\n' "$all" | grep -q 'apply its fix row' || false
}
