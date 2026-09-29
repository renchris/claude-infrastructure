#!/usr/bin/env bats
# coreaudiod-watch.sh — the coreaudiod IO-context leak detector and (root) restart watchdog.
#
# WHY: under CPU starvation coreaudiod stopped releasing client IO contexts; it held 5,117 and then
# 4,641 of them when restarted, reached ~200% CPU, and nothing on the box ever said so
# (docs/research/coreaudiod-spin-2026-09-29.md). The instrument is the held-context count read from
# `pmset -g assertions`; every binary is a stub here, so no test reads the live daemon or kills it.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  W="$REPO/scripts/coreaudiod-watch.sh"
  F="$BATS_TEST_TMPDIR/fx"; mkdir -p "$F"
  export CA_WATCH_STATE="$F/state" CA_WATCH_LOG="$F/log.jsonl" CA_WATCH_HOT_FLAG="$F/hot/coreaudiod-hot"
  export CA_WATCH_NOW=1790000000
  # ps: one coreaudiod row, fields pid time etime rss comm (overridable per test)
  printf '%s\n' "  501   0:00.10     01:00  1000 /usr/bin/something" \
                "  777   ${PS_TIME:-0:10.00}  ${PS_ETIME:-01:00:00} 65536 /usr/sbin/coreaudiod" > "$F/ps.out"
  printf '#!/bin/bash\ncat "%s/ps.out"\n' "$F" > "$F/ps"
  printf '#!/bin/bash\ncat "%s/pmset.out"\n' "$F" > "$F/pmset"
  printf '#!/bin/bash\necho "$*" >> "%s/killall.argv"\n' "$F" > "$F/killall"
  printf '#!/bin/bash\necho "$*" >> "%s/notify.argv"\n' "$F" > "$F/notify"
  chmod +x "$F/ps" "$F/pmset" "$F/killall" "$F/notify"
  export CA_WATCH_PS="$F/ps" CA_WATCH_PMSET="$F/pmset" CA_WATCH_KILLALL="$F/killall" CA_WATCH_NOTIFY="$F/notify"
  asrt 0
}

# asrt <n output contexts> [<age of one extra audio-in context, HH:MM:SS>]
# Each context is the real pair: an idle-sleep assertion AND its display-sleep twin, with a
# Resources line — plus an unrelated caffeinate assertion that must never count.
asrt() {
  {
    echo "Listed by owning process:"
    echo "   pid 15336(caffeinate): [0x0010360c00018b4c] 03:40:57 PreventUserIdleSystemSleep named: \"caffeinate command-line tool\""
    local i
    for ((i = 0; i < $1; i++)); do
      echo "   pid 777(coreaudiod): [0x00106c26000$i] 05:00:00 PreventUserIdleSystemSleep named: \"com.apple.audio.context$i.preventuseridlesleep\""
      printf '\tResources: audio-out BuiltInSpeakerDevice\n'
      echo "   pid 777(coreaudiod): [0x00506c26000$i] 05:00:00 PreventUserIdleDisplaySleep named: \"com.apple.audio.context$i.preventuseridledisplaysleep\""
    done
    if [ -n "${2:-}" ]; then
      echo "   pid 777(coreaudiod): [0x00106c2600mic] $2 PreventUserIdleSystemSleep named: \"com.apple.audio.BuiltInMicrophoneDevice.context.preventuseridlesleep\""
      printf '\tResources: audio-in BuiltInMicrophoneDevice\n'
    fi
  } > "$F/pmset.out"
}
field() { printf '%s\n' "$output" | grep -o "$1=[^ ]*" | head -1 | cut -d= -f2; }

@test "healthy daemon: 0 contexts ⇒ verdict=ok, no hot flag, one JSONL line" {
  run "$W"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=ok"* ]] || false
  [ ! -e "$CA_WATCH_HOT_FLAG" ]
  [ "$(wc -l < "$CA_WATCH_LOG" | tr -d ' ')" = 1 ]
}

@test "counts only coreaudiod idle-sleep contexts: display-sleep twins and other owners are ignored" {
  asrt 7
  run "$W"
  [ "$(field ctx)" = 7 ]
}

@test "leak past the floor ⇒ verdict=leaking and the hot flag appears; recovery removes it" {
  asrt 301
  run "$W"
  [[ "$output" == *"verdict=leaking"* ]] || false
  [ -f "$CA_WATCH_HOT_FLAG" ]
  asrt 3
  CA_WATCH_NOW=1790000300 run "$W"
  [[ "$output" == *"verdict=ok"* ]] || false
  [ ! -e "$CA_WATCH_HOT_FLAG" ]
}

@test "CPU is a RATE between runs of the same pid: 180 s of cpu over 300 s ⇒ 60% ⇒ hot" {
  echo "777 10 1789999700 ok 0 0" > "$CA_WATCH_STATE"
  sed -i '' 's/ 0:10.00 / 3:10.00 /' "$F/ps.out"         # 10 s -> 190 s cumulative
  run "$W"
  [[ "$output" == *"cpu=60% (interval)"* ]] || false
  [[ "$output" == *"verdict=hot"* ]] || false
}

@test "a NEW daemon pid falls back to the lifetime average instead of a bogus delta" {
  echo "999 99999 1789999700 ok 0 0" > "$CA_WATCH_STATE"
  run "$W"
  [[ "$output" == *"cpu=0% (lifetime)"* ]] || false      # 10 s over 1 h
}

@test "ps time and etime parse: 123:45.67 cpu over 1-02:03:04 age" {
  sed -i '' 's/ 0:10.00  01:00:00 / 123:45.67  1-02:03:04 /' "$F/ps.out"
  run "$W"
  run tail -1 "$CA_WATCH_LOG"
  [[ "$output" == *'"age_s":93784'* ]] || false
  [[ "$output" == *'"cpu_pct":7,'* ]]                     # 7425 s / 93784 s
}

@test "--notify speaks on the ok→leaking edge, is damped while it persists, re-arms after recovery" {
  asrt 400
  run "$W" --notify
  [[ "$output" == *"action=notified"* ]] || false
  [[ "$(cat "$F/notify.argv")" == *"400 leaked IO contexts"*"killall coreaudiod"* ]] || false
  CA_WATCH_NOW=1790000300 run "$W" --notify
  [[ "$output" == *"action=notify-damped"* ]] || false
  asrt 0;   CA_WATCH_NOW=1790000600 run "$W" --notify
  asrt 400; CA_WATCH_NOW=1790000900 run "$W" --notify
  [[ "$output" == *"action=notified"* ]] || false
  [ "$(wc -l < "$F/notify.argv" | tr -d ' ')" = 2 ]
}

@test "--restart past the hard floor kills coreaudiod once, then respects the gap" {
  asrt 1000
  CA_WATCH_ROOT_OK=1 run "$W" --restart
  [[ "$output" == *"action=restarted"* ]] || false
  [ "$(cat "$F/killall.argv")" = coreaudiod ]
  CA_WATCH_ROOT_OK=1 CA_WATCH_NOW=1790000300 run "$W" --restart
  [[ "$output" == *"action=deferred-gap"* ]] || false
  [ "$(wc -l < "$F/killall.argv" | tr -d ' ')" = 1 ]
}

@test "--restart never cuts a live call: a young audio-in context defers it, an old one does not" {
  asrt 1000 00:20:00
  CA_WATCH_ROOT_OK=1 run "$W" --restart
  [[ "$output" == *"action=deferred-input-live"* ]] || false
  [ ! -e "$F/killall.argv" ]
  asrt 1000 50:00:00                                         # leaked mic context, 50 h old
  CA_WATCH_ROOT_OK=1 run "$W" --restart
  [[ "$output" == *"action=restarted"* ]] || false
}

@test "--restart below the floor, or high CPU without a leak, does nothing" {
  asrt 299
  echo "777 10 1789999700 ok 0 0" > "$CA_WATCH_STATE"
  sed -i '' 's/ 0:10.00 / 9:10.00 /' "$F/ps.out"            # 180% interval CPU, but only 299 ctx
  CA_WATCH_ROOT_OK=1 run "$W" --restart
  [[ "$output" == *"action=none"* ]] || false
  [ ! -e "$F/killall.argv" ]
}

@test "--restart at 300+ contexts AND >=100% interval CPU restarts before the hard floor" {
  asrt 300
  echo "777 10 1789999700 ok 0 0" > "$CA_WATCH_STATE"
  sed -i '' 's/ 0:10.00 / 9:10.00 /' "$F/ps.out"
  CA_WATCH_ROOT_OK=1 run "$W" --restart
  [[ "$output" == *"action=restarted"* ]] || false
}

@test "--restart refuses to run without root" {
  run "$W" --restart
  [ "$status" -eq 2 ]
  [ ! -e "$F/killall.argv" ]
}

@test "no coreaudiod process ⇒ verdict=absent, not a false ok" {
  printf '  501 0:00.10 01:00 1000 /usr/bin/something\n' > "$F/ps.out"
  run "$W"
  [[ "$output" == *"verdict=absent"* ]]
}

@test "unreadable assertion table ⇒ verdict=unknown, never ok" {
  : > "$F/pmset.out"
  run "$W"
  [[ "$output" == *"verdict=unknown"* ]]
}

@test "CA_WATCH=0 is inert" {
  asrt 5000
  CA_WATCH=0 run "$W" --notify
  [[ "$output" == *"verdict=ok"* ]] || false
  [ ! -e "$F/notify.argv" ]
  [ ! -e "$CA_WATCH_LOG" ]
}

@test "runs under /bin/bash 3.2, the interpreter launchd gives it" {
  asrt 301
  run /bin/bash "$W"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=leaking"* ]]
}
