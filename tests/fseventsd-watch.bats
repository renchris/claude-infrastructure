#!/usr/bin/env bats
# fseventsd-watch.sh — the fseventsd memory-bloat detector and (root) restart watchdog.
#
# WHY: on 2026-10-04 fseventsd held a 64 GB footprint (56 GB compressed), filled swap to 40.7 of
# 42 GB and got every land gate SIGKILLed by the compressor sentinel; nothing on the box said so.
# The instrument is top's MEM/CMPRS for the daemon's pid. Every binary is a stub here (ps, top,
# sysctl, kill, sleep, sample, the pager), so no test reads the live daemon or signals anything.

bats_require_minimum_version 1.5.0

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  W="$REPO/scripts/fseventsd-watch.sh"
  F="$BATS_TEST_TMPDIR/fx"; mkdir -p "$F"
  export FSE_WATCH_STATE="$F/state" FSE_WATCH_LOG="$F/log.jsonl" FSE_WATCH_LEDGER="$F/restarts.jsonl"
  export FSE_WATCH_NOW=1790000000
  daemon 317 4-00:00:00
  mem 317 3553K 0B
  printf '#!/bin/bash\ncat "%s/ps.out"\n' "$F" > "$F/ps"
  printf '#!/bin/bash\ncat "%s/top.out"\n' "$F" > "$F/top"
  printf '#!/bin/bash\necho "total = 43008.00M  used = 41676.50M  free = 1331.50M  (encrypted)"\n' > "$F/sysctl"
  printf '#!/bin/bash\necho "$*" >> "%s/page.argv"\n' "$F" > "$F/page"
  printf '#!/bin/bash\nexit 0\n' > "$F/sleep"
  # kill: -0 succeeds while the pid is in ps.out. -TERM/-KILL remove it, unless $F/ignore-<sig> exists,
  # and launchd's respawn (pid 9001) is simulated unless $F/no-respawn exists.
  cat > "$F/kill" <<EOF
#!/bin/bash
echo "\$*" >> "$F/kill.argv"
sig="\${1#-}"; pid="\$2"
grep -q "^ *\$pid " "$F/ps.out" || exit 1
[ "\$sig" = 0 ] && exit 0
[ -e "$F/ignore-\$sig" ] && exit 0
grep -v "^ *\$pid " "$F/ps.out" > "$F/ps.tmp"; mv "$F/ps.tmp" "$F/ps.out"
[ -e "$F/no-respawn" ] || echo " 9001     00:01 /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/FSEvents.framework/Versions/A/Support/fseventsd" >> "$F/ps.out"
exit 0
EOF
  # shellcheck disable=SC2016  # $*, $3, $4 are the stub's own args, expanded when it runs
  printf '#!/bin/bash\necho "$*" >> "%s/sample.argv"; [ "$3" = -file ] && echo stack > "$4"\n' "$F" > "$F/sample"
  chmod +x "$F/ps" "$F/top" "$F/sysctl" "$F/page" "$F/sleep" "$F/kill" "$F/sample"
  export FSE_WATCH_PS="$F/ps" FSE_WATCH_TOP="$F/top" FSE_WATCH_SYSCTL="$F/sysctl" FSE_WATCH_PAGE="$F/page"
  export FSE_WATCH_SLEEP="$F/sleep" FSE_WATCH_KILL="$F/kill" FSE_WATCH_SAMPLE="$F/sample" FSE_WATCH_SAMPLE_DIR="$F/samples"
}

# daemon <pid> <etime> — ps rows: an unrelated process and fseventsd (full path, as Darwin prints comm)
daemon() {
  printf '%s\n' "  501     01:00 /usr/bin/something" \
    "  $1 $2 /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/FSEvents.framework/Versions/A/Support/fseventsd" > "$F/ps.out"
}
# mem <pid> <MEM> <CMPRS> — top -l 1 -pid output, header and all
mem() {
  printf '%s\n' "Processes: 812 total, 4 running, 808 sleeping, 5021 threads" \
    "PhysMem: 63G used (8G wired, 30G compressor), 600M unused." "" \
    "PID    MEM   CMPRS COMMAND" "$1  $2 $3 fseventsd" > "$F/top.out"
}
run_at() { FSE_WATCH_NOW="$1" run "$W" "${@:2}"; }
root_at() { FSE_WATCH_ROOT_OK=1 FSE_WATCH_NOW="$1" run "$W" --restart; }
field() { printf '%s\n' "$output" | grep -o "$1=[^ ]*" | head -1 | cut -d= -f2; }

@test "healthy daemon: 3.5 MB ⇒ verdict=ok, one JSONL row carrying footprint, swap and age" {
  run "$W"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=ok"* ]] || false
  [ "$(wc -l < "$FSE_WATCH_LOG" | tr -d ' ')" = 1 ]
  run tail -1 "$FSE_WATCH_LOG"
  [[ "$output" == *'"pid":317,"fp_mb":3,"cmprs_mb":0,"growth_mb_h":null,"age_s":345600,"swap_mb":41676,"verdict":"ok","action":"none"'* ]] || false
}

@test "top units parse: 64G with 56G compressed is 65536/57344 MB and reads act; 1024M+ trend suffix reads 1024" {
  mem 317 64G 56G
  run "$W"
  [ "$(field fp)" = 65536MB ]
  [ "$(field cmprs)" = 57344MB ]
  [[ "$output" == *"verdict=act"* ]] || false
  mem 317 1024M+ 512M-
  run "$W"
  [ "$(field fp)" = 1024MB ]
  [[ "$output" == *"verdict=ok"* ]] || false
}

@test "thresholds: 8 GB is warn, 16 GB is act, and both are env knobs" {
  mem 317 8192M 0B;  run "$W"; [[ "$output" == *"verdict=warn"* ]] || false
  mem 317 8191M 0B;  run "$W"; [[ "$output" == *"verdict=ok"* ]] || false
  mem 317 16G 0B;    run "$W"; [[ "$output" == *"verdict=act"* ]] || false
  mem 317 600M 0B
  FSE_WATCH_WARN_MB=500 run "$W";                     [[ "$output" == *"verdict=warn"* ]] || false
  FSE_WATCH_WARN_MB=500 FSE_WATCH_ACT_MB=600 run "$W"; [[ "$output" == *"verdict=act"* ]] || false
}

@test "growth is MB/h between runs of the SAME pid; a new daemon pid resets it to null" {
  mem 317 1000M 0B; run_at 1790000000
  mem 317 1500M 0B; run_at 1790001800                # +500 MB in 30 min
  [ "$(field growth)" = 1000MB/h ]
  daemon 9001 00:10; mem 9001 4M 0B; run_at 1790002100
  [ "$(field growth)" = nullMB/h ]
}

@test "--notify pages on each RISE (ok→warn, warn→act), is damped while level, re-pages after the interval" {
  mem 317 9G 0B;  run_at 1790000000 --notify
  [[ "$output" == *"action=paged"*"verdict=warn"* ]] || false
  [[ "$(cat "$F/page.argv")" == "--source fseventsd-watch -- fseventsd warn: footprint 9216 MB"*"sudo killall fseventsd"*"0057-fseventsd-watchdog.sh --confirm com.claude.fseventsd-watchdog" ]] || false
  run_at 1790000300 --notify
  [[ "$output" == *"action=page-damped"* ]] || false
  mem 317 17G 0B; run_at 1790000600 --notify
  [[ "$output" == *"action=paged"*"verdict=act"* ]] || false
  run_at 1790000900 --notify
  [[ "$output" == *"action=page-damped"* ]] || false
  run_at $(( 1790000600 + 21600 )) --notify
  [[ "$output" == *"action=paged"* ]] || false
  [ "$(wc -l < "$F/page.argv" | tr -d ' ')" = 3 ]
}

@test "--notify: an undelivered page is said, never claimed, and the rise is retried next run" {
  printf '#!/bin/bash\nexit 1\n' > "$F/page"
  mem 317 9G 0B; run_at 1790000000 --notify
  [[ "$output" == *"action=page-undelivered-rc1"* ]] || false
  printf '#!/bin/bash\nexit 0\n' > "$F/page"
  run_at 1790000300 --notify
  [[ "$output" == *"action=paged"* ]] || false
}

@test "--notify below warn pages nothing" {
  run "$W" --notify
  [[ "$output" == *"action=none"*"verdict=ok"* ]] || false
  [ ! -e "$F/page.argv" ]
}

@test "--restart: act on ONE run waits; the 2nd consecutive run samples, SIGTERMs, confirms the new pid, ledgers it" {
  mem 317 64G 56G
  root_at 1790000000
  [[ "$output" == *"action=none"*"verdict=act"* ]] || false
  [ ! -e "$F/kill.argv" ]
  root_at 1790000300
  [[ "$output" == *"action=restarted new_pid=9001"* ]] || false
  [ "$(cat "$F/sample.argv")" = "317 3 -file $F/samples/fseventsd-sample-1790000300.txt" ]
  [ "$(head -1 "$F/kill.argv")" = "-TERM 317" ]
  run ! grep -q -- -KILL "$F/kill.argv"
  run cat "$FSE_WATCH_LEDGER"
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == *'"old_pid":317,"new_pid":9001,"fp_mb":65536,"cmprs_mb":57344'*'"signal":"TERM","action":"restarted","sample":"'"$F"'/samples/fseventsd-sample-1790000300.txt"'* ]] || false
}

@test "--restart: a daemon that ignores SIGTERM gets SIGKILL, and the ledger says so" {
  touch "$F/ignore-TERM"; mem 317 20G 1G
  root_at 1790000000; root_at 1790000300
  [[ "$output" == *"action=restarted new_pid=9001"* ]] || false
  grep -qx -- '-KILL 317' "$F/kill.argv"
  grep -q '"signal":"KILL","action":"restarted"' "$FSE_WATCH_LEDGER"
}

@test "--restart: no respawn within the wait is reported, never a clean restart" {
  touch "$F/no-respawn"; mem 317 20G 1G
  root_at 1790000000; root_at 1790000300
  [[ "$output" == *"action=restarted-no-respawn"* ]] || false
  grep -q '"new_pid":null,' "$FSE_WATCH_LEDGER"
}

@test "--restart respects the cooldown, and a NEW pid restarts the consecutive-run count" {
  mem 317 20G 1G
  root_at 1790000000; root_at 1790000300
  [[ "$output" == *"action=restarted"* ]] || false
  mem 9001 20G 1G                                     # the new daemon is (impossibly) bloated at once
  root_at 1790000600
  [[ "$output" == *"action=none"* ]] || false         # run 1 of the new pid
  root_at 1790000900
  [[ "$output" == *"action=deferred-gap"* ]] || false # run 2, but inside the 30 min gap
  [ "$(grep -c -- '-TERM' "$F/kill.argv")" = 1 ]
}

@test "--restart: a failing or disabled sampler never blocks the restart" {
  printf '#!/bin/bash\nexit 1\n' > "$F/sample"; mem 317 20G 1G
  root_at 1790000000; root_at 1790000300
  [[ "$output" == *"action=restarted"* ]] || false
  grep -q '"sample":""' "$FSE_WATCH_LEDGER"
}

@test "--restart below act does nothing, however long it lasts" {
  mem 317 12G 1G
  root_at 1790000000; root_at 1790000300; root_at 1790000600
  [[ "$output" == *"action=none"*"verdict=warn"* ]] || false
  [ ! -e "$F/kill.argv" ]
}

@test "--restart refuses to run without root" {
  mem 317 64G 1G
  run "$W" --restart
  [ "$status" -eq 2 ]
  [ ! -e "$F/kill.argv" ]
}

@test "no fseventsd process ⇒ verdict=absent, not a false ok" {
  printf '  501     01:00 /usr/bin/something\n' > "$F/ps.out"
  run "$W"
  [[ "$output" == *"verdict=absent"* ]] || false
}

@test "unreadable footprint (no row for the pid, or a unit that does not parse) ⇒ verdict=unknown, never ok" {
  : > "$F/top.out"
  run "$W"
  [[ "$output" == *"verdict=unknown"* ]] || false
  mem 317 N/A 0B
  run "$W"
  [[ "$output" == *"verdict=unknown"* ]] || false
  [ ! -e "$FSE_WATCH_LOG" ]
}

@test "FSE_WATCH=0 is inert" {
  mem 317 64G 1G
  FSE_WATCH=0 run "$W" --notify
  [[ "$output" == *"verdict=ok"* ]] || false
  [ ! -e "$F/page.argv" ]
  [ ! -e "$FSE_WATCH_LOG" ]
}

@test "runs under /bin/bash 3.2, the interpreter launchd gives it, including the restart path" {
  mem 317 20G 1G
  run /bin/bash "$W"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=act"* ]] || false
  FSE_WATCH_ROOT_OK=1 FSE_WATCH_ACT_RUNS=1 run /bin/bash "$W" --restart
  [[ "$output" == *"action=restarted new_pid=9001"* ]] || false
}
