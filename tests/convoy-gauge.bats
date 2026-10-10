#!/usr/bin/env bats
# convoy-gauge.sh — the detect-only gauge for a LaunchServices/trust/keychain lock convoy.
#
# WHY: on 2026-10-09 the user's lsd held its database lock for ~7.5 minutes behind trustd and secd;
# ~45 lsd threads piled up, Claude TUIs froze, and load did not predict it. The instrument is the
# thread count of the user's lsd/trustd/secd/tccd (2-7 at rest, 45 and 84 in the two incidents).
# Every binary here is a stub (ps, sample, getconf, sysctl, sleep, the page transport), so no
# test reads a live daemon, samples one, writes the live flag or pages anyone.
#
# The subject always runs under /bin/bash (3.2 on this box), the interpreter launchd gives it.
#
# RED-proof (each mutant run against this suite on a scratch copy of the script; the unmutated
# control ran green beside them):
#   2026-10-09
#   trip floor 16 -> 60                      reds the trip case and the 12 that need a trip first
#   in-between band `STATE="$PREV"` -> clear reds ONLY "12 threads from tripped"
#   in-between band `STATE="$PREV"` -> tripped reds ONLY "12 threads from clear"
#   confirming read's verdict dropped        reds ONLY "a first read of 45 with a confirming read of 5"
#   `|0) continue` removed (0 is a count)    reds ONLY "an absent daemon is null" (that site is gone
#                                            since 2026-10-10: a pid with no `ps -M` rows now never
#                                            reaches a count; the same case pins it)
#   a fresh flag no longer reads as tripped  reds the repeat-run, 12-from-tripped, confirm-delay,
#                                            clear-edge and nothing-measurable cases
#   2026-10-10 (review round): see the mutant list printed beside each new case's name below.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  G="$REPO/scripts/convoy-gauge.sh"
  export FX="$BATS_TEST_TMPDIR/fx"; mkdir -p "$FX"
  export CONVOY_GAUGE_LOG="$FX/gauge.jsonl" CONVOY_GAUGE_SHED_DIR="$FX/cc-shed"
  export CONVOY_GAUGE_TRANSITIONS_LOG="$FX/transitions.log"
  export CONVOY_GAUGE_EVIDENCE_DIR="$FX/evidence" CONVOY_GAUGE_CONFIRM_S=0
  FLAG="$FX/cc-shed/active"

  # ps, the two reads the gauge makes:
  #   `-axo pid=,ppid=,uid=,state=,pri=,comm=` is the process table (axo.fail = ps fails, prints
#   nothing): one row per pid in pid.<name>
  #   (no file = no such process), parented by launchd, ours and at /usr/libexec/<name> unless
  #   parent.<pid> / uid.<pid> / path.<pid> say otherwise; then one row per "<state> <pri>" line of
  #   bands.out, as unrelated processes.
  #   `-M -p <a,b>` prints a header and one row per thread of each listed pid: threads.<pid> holds the
  #   count for each successive read of that pid (the last one repeats); no file = the pid is gone.
  cat > "$FX/ps" <<'STUB'
#!/bin/bash
echo "$*" >> "$FX/ps.argv"
case "$*" in
  "-M -p "*)
    echo "USER       PID   TT   %CPU STAT PRI     STIME     UTIME COMMAND"
    for pid in $(echo "$3" | tr , ' '); do
      [ -f "$FX/threads.$pid" ] || continue
      c=$(( $(cat "$FX/calls.$pid" 2>/dev/null || echo 0) + 1 )); echo "$c" > "$FX/calls.$pid"
      n="$(awk -v c="$c" '{ print (c <= NF) ? $c : $NF }' "$FX/threads.$pid")"
      i=0; while [ "$i" -lt "$n" ]; do
        if [ "$i" = 0 ]; then echo "user     $pid   ??    0.0 S    31T   0:00.01   0:00.01 /usr/libexec/daemon"
        else echo "         $pid         0.0 S    31T   0:00.00   0:00.00 "; fi
        i=$((i + 1))
      done
    done ;;
  "-axo pid=,ppid=,uid=,state=,pri=,comm=")
    [ ! -e "$FX/axo.fail" ] || exit 1
    for f in "$FX"/pid.*; do
      [ -f "$f" ] || continue
      for pid in $(cat "$f"); do
        printf '%5s %5s %5s S    31 %s\n' "$pid" "$(cat "$FX/parent.$pid" 2>/dev/null || echo 1)" \
          "$(cat "$FX/uid.$pid" 2>/dev/null || id -u)" "$(cat "$FX/path.$pid" 2>/dev/null || echo "/usr/libexec/${f##*/pid.}")"
      done
    done
    awk '{ printf "%5d     1     0 %-4s %3s /usr/libexec/other\n", 9000 + NR, $1, $2 }' "$FX/bands.out" ;;
esac
STUB
  cat > "$FX/sample" <<'STUB'
#!/bin/bash
echo "$*" >> "$FX/sample.argv"
[ "$3" = -file ] && echo "call graph of $1" > "$4"
STUB
  # The page transport speaks cc-notify's contract: a verdict token on stderr, and an exit code.
  # NOTIFY_DESK / NOTIFY_ORCH: an rc for that role, or `hang` (traps TERM the way cc-notify does).
  cat > "$FX/notify" <<'STUB'
#!/bin/bash
printf 'phone_fallback=%s %s\n' "${CC_NOTIFY_PHONE_FALLBACK:-unset}" "$*" >> "$FX/notify.argv"
case "$2" in desk) rc="${NOTIFY_DESK:-0}" ;; orchestrator) rc="${NOTIFY_ORCH:-0}" ;; *) rc=9 ;; esac
if [ "$rc" = hang ]; then
  trap 'echo "cc-notify: verdict=interrupted reason=signal" >&2; echo "$2" >> "$FX/notify.interrupted"; exit 143' TERM
  /bin/sleep 300 & wait; exit 0
fi
if [ "$rc" = 0 ]; then echo "cc-notify: verdict=delivered" >&2; else echo "cc-notify: verdict=unresolvable reason=role-unset" >&2; fi
exit "$rc"
STUB
  printf '#!/bin/bash\necho "{ 197.20 180.00 150.00 }"\n' > "$FX/sysctl"
  # shellcheck disable=SC2016  # $* is the stub's own argv, expanded when it runs
  printf '#!/bin/bash\necho "$*" >> "$FX/sleep.argv"\n' > "$FX/sleep"
  chmod +x "$FX/ps" "$FX/sample" "$FX/notify" "$FX/sysctl" "$FX/sleep"
  export CONVOY_GAUGE_PS="$FX/ps" CONVOY_GAUGE_SAMPLE="$FX/sample"
  export CONVOY_GAUGE_NOTIFY="$FX/notify" CONVOY_GAUGE_SYSCTL="$FX/sysctl" CONVOY_GAUGE_SLEEP="$FX/sleep"
  export CONVOY_GAUGE_GETCONF="$FX/no-getconf"
  printf 'R 31\nR 4\nS 31\nR 46\nR 20\nR 97\nU 31\nR 31\n' > "$FX/bands.out"
  echo 101 > "$FX/pid.lsd"; echo 102 > "$FX/pid.trustd"; echo 103 > "$FX/pid.secd"; echo 104 > "$FX/pid.tccd"
  threads 5 3 4 2
}

# threads <lsd> <trustd> <secd> <tccd> — each argument is the count per successive read ("45 5" =
# 45 on the first read, 5 from the second on). Resets the read counters.
threads() {
  rm -f "$FX"/calls.*
  echo "$1" > "$FX/threads.101"; echo "$2" > "$FX/threads.102"
  echo "$3" > "$FX/threads.103"; echo "$4" > "$FX/threads.104"
}
gauge() { run /bin/bash "$G"; }
row() { tail -1 "$CONVOY_GAUGE_LOG" | jq -r "$1"; }
lines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }
evidence_dirs() { find "$FX/evidence" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '; }
# all_dead <file of pids> — every pid in it is gone (an orphan is reaped by launchd a beat later)
all_dead() {
  local p i
  for p in $(cat "$1"); do
    i=0; while kill -0 "$p" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i + 1)); done
    ! kill -0 "$p" 2>/dev/null || return 1
  done
}

@test "45 lsd threads, confirmed: trips, writes the flag, captures evidence once and pages the desk once" {
  threads 45 3 4 2
  gauge
  [ "$status" -eq 0 ]
  [[ "$output" == *"state=tripped"* ]] || false
  [ "$(row '[.state,.prev,.transition,.captured,.page,.cut]|map(tostring)|join(",")')" = "tripped,clear,trip,true,desk,false" ]
  [ "$(row '[.lsd,.trustd,.secd,.tccd,.max,.confirm_max]|join(",")')" = "45,3,4,2,45,45" ]
  [ "$(row '[.lsd_pid,.trustd_pid,.secd_pid,.tccd_pid]|join(",")')" = "101,102,103,104" ]
  [ -f "$FLAG" ]
  # evidence: one directory, ps -M and one 1 s sample per present daemon, and the row names it
  [ "$(evidence_dirs)" = 1 ]
  local d; d="$(row .evidence_dir)"
  [ -d "$d" ]
  [ "$(grep -c . "$d/lsd.ps-M.txt")" = 46 ]                       # header + 45 thread rows
  [ "$(lines "$FX/sample.argv")" = 4 ]
  grep -qx "103 1 -file $d/secd.sample.txt" "$FX/sample.argv"
  [ -s "$d/secd.sample.txt" ]
  # the page: once, to the desk role, with the four counts and the operator's instruction
  [ "$(lines "$FX/notify.argv")" = 1 ]
  grep -q -- '--role desk TRIP lsd=45 trustd=3 secd=4 tccd=2 ' "$FX/notify.argv"
  grep -q 'a Claude pane can freeze about 1 s after you focus it; avoid cycling panes until the clear line' "$FX/notify.argv"
  [ "$(printf '%s\n' "$output" | grep -c '^convoy-gauge: TRIP ')" = 1 ]   # the transition line on stderr
  [ "$(lines "$FX/transitions.log")" = 1 ]                        # and in its own log
  grep -q 'Z TRIP lsd=45 trustd=3 secd=4 tccd=2 ' "$FX/transitions.log"
}

@test "a second tripped run refreshes the flag but captures nothing and pages nobody" {
  threads 45 3 4 2
  gauge
  local since; since="$(cat "$FLAG")"
  touch -A -000140 "$FLAG"                                        # 100 s old: fresh, but visibly not new
  local aged; aged="$(stat -f %m "$FLAG")"
  gauge
  [ "$status" -eq 0 ]
  [ "$(row '[.state,.prev,.transition,.captured,.evidence_dir,.page]|map(tostring)|join(",")')" = "tripped,tripped,none,false,null,none" ]
  [ "$(evidence_dirs)" = 1 ]
  [ "$(lines "$FX/sample.argv")" = 4 ]
  [ "$(lines "$FX/notify.argv")" = 1 ]
  [ "$(lines "$FX/transitions.log")" = 1 ]
  [ "$(stat -f %m "$FLAG")" -gt "$aged" ]
  [ "$(cat "$FLAG")" = "$since" ]                                 # the trip time survives the refresh
}

@test "7 threads from clear stays clear: no flag, no evidence, no page, exit 0" {
  threads 7 3 4 2
  gauge
  [ "$status" -eq 0 ]
  [ "$(row '[.state,.transition,.max,.captured]|map(tostring)|join(",")')" = "clear,none,7,false" ]
  [ ! -e "$FLAG" ]
  [ "$(evidence_dirs)" = 0 ]
  [ "$(lines "$FX/notify.argv")" = 0 ]
}

@test "hysteresis: 12 threads from clear holds clear" {
  threads 12 3 4 2
  gauge
  [ "$(row '[.state,.transition,.max]|map(tostring)|join(",")')" = "clear,none,12" ]
  [ ! -e "$FLAG" ]
  [ "$(lines "$FX/notify.argv")" = 0 ]
}

@test "hysteresis: 12 threads from tripped holds tripped, keeps the flag fresh and sends no clear page" {
  threads 45 3 4 2
  gauge
  touch -A -000140 "$FLAG"
  local aged; aged="$(stat -f %m "$FLAG")"
  threads 12 3 4 2
  gauge
  [ "$(row '[.state,.prev,.transition,.max]|map(tostring)|join(",")')" = "tripped,tripped,none,12" ]
  [ "$(stat -f %m "$FLAG")" -gt "$aged" ]
  [ "$(lines "$FX/notify.argv")" = 1 ]                            # the trip page only
}

# mutants (2026-10-10): TRIP default 16->30 · -ge->-gt at both trip sites — each reds this case
@test "the trip floor is 16, inclusive: 15 from clear holds clear, 16 trips" {
  threads 15 3 4 2
  gauge
  [ "$(row '[.state,.transition]|join(",")')" = "clear,none" ]
  threads 16 3 4 2
  gauge
  [ "$(row '[.state,.transition,.confirm_max]|map(tostring)|join(",")')" = "tripped,trip,16" ]
}

# mutants (2026-10-10): CLEAR default 8->11 · 8->5 · -le->-lt — each reds this case
@test "the clear ceiling is 8, inclusive: 9 from tripped holds tripped, 8 clears" {
  threads 45 3 4 2
  gauge
  threads 9 3 4 2
  gauge
  [ "$(row '[.state,.transition]|join(",")')" = "tripped,none" ]
  threads 8 3 4 2
  gauge
  [ "$(row '[.state,.transition]|join(",")')" = "clear,clear" ]
  [ ! -e "$FLAG" ]
}

@test "a first read of 45 with a confirming read of 5 does not trip" {
  threads "45 5" 3 4 2
  gauge
  [ "$status" -eq 0 ]
  [ "$(row '[.state,.transition,.lsd,.max,.confirm_max,.captured]|map(tostring)|join(",")')" = "clear,none,45,45,5,false" ]
  [ ! -e "$FLAG" ]
  [ "$(evidence_dirs)" = 0 ]
  [ "$(lines "$FX/notify.argv")" = 0 ]
}

@test "the confirming read waits 5 s by default, and only when a clear gauge first reads past the floor" {
  unset CONVOY_GAUGE_CONFIRM_S
  threads 7 3 4 2
  gauge
  [ "$(lines "$FX/sleep.argv")" = 0 ]
  threads 45 3 4 2
  gauge
  [ "$(cat "$FX/sleep.argv")" = 5 ]
  gauge                                                           # already tripped: nothing to confirm
  [ "$(lines "$FX/sleep.argv")" = 1 ]
}

@test "clear edge: the flag goes, the desk gets one page with the counts and how long it was tripped" {
  threads 45 3 4 2
  gauge
  echo "since=$(( $(date +%s) - 125 )) lsd=45 trustd=3 secd=4 tccd=2" > "$FLAG"
  threads 5 3 4 2
  gauge
  [ "$status" -eq 0 ]
  ! [[ "$output" == *": line "* ]] || false                       # no bash 3.2 runtime error on either edge
  [ "$(row '[.state,.prev,.transition,.page]|join(",")')" = "clear,tripped,clear,desk" ]
  [ ! -e "$FLAG" ]
  [ "$(lines "$FX/notify.argv")" = 2 ]
  tail -1 "$FX/notify.argv" | grep -Eq -- '--role desk CLEAR lsd=5 trustd=3 secd=4 tccd=2 .*tripped for 2m0[5-9]s'
  [ "$(lines "$FX/transitions.log")" = 2 ]
  gauge                                                           # still clear: not a transition
  [ "$(row .transition)" = none ]
  [ "$(lines "$FX/notify.argv")" = 2 ]
}

# mutant (2026-10-10): the null-hold loop removed — reds this case (lsd=null clears on the 2nd run)
@test "a null holds a trip: the daemon that tripped going unreadable is not a clear; a low one is" {
  threads 45 3 4 2
  gauge
  mv "$FX/pid.lsd" "$FX/away.lsd"                                 # lsd drops out of the table mid-convoy
  gauge
  [ "$status" -eq 0 ]
  [ "$(row '[.lsd,.max,.state,.transition,.null_hold]|map(tojson)|join(",")')" = 'null,4,"tripped","none","lsd"' ]
  [ -f "$FLAG" ]
  grep -q ' lsd=45 ' "$FLAG"                                      # the last known count is carried forward
  gauge                                                           # and is still there a tick later
  [ "$(row '[.state,.null_hold]|join(",")')" = "tripped,lsd" ]
  [ "$(lines "$FX/notify.argv")" = 1 ]                            # no CLEAR page, no second TRIP
  mv "$FX/away.lsd" "$FX/pid.lsd"; threads 5 3 4 2
  rm "$FX/pid.tccd"                                               # tccd (last seen at 2) goes null
  gauge
  [ "$(row '[.state,.transition,.null_hold]|map(tojson)|join(",")')" = '"clear","clear",null' ]
  [ "$(lines "$FX/notify.argv")" = 2 ]
}

@test "an absent daemon is null, never 0: no pid, or a pid that printed no thread rows" {
  rm "$FX/pid.secd"                                               # no user-owned secd at all
  rm "$FX/threads.104"                                            # tccd's pid vanished before ps read it
  echo 45 > "$FX/threads.101"
  gauge
  [ "$status" -eq 0 ]
  [ "$(row '[.lsd,.trustd,.secd,.tccd,.max,.secd_pid,.tccd_pid]|map(tojson)|join(",")')" = "45,3,null,null,45,null,null" ]
  # and the evidence covers only what was there to read
  local d; d="$(row .evidence_dir)"
  [ "$(cd "$d" && echo *.ps-M.txt)" = "lsd.ps-M.txt trustd.ps-M.txt" ]
  [ "$(lines "$FX/sample.argv")" = 2 ]
}

@test "nothing measurable: exit 3, an all-null row, and a tripped flag is neither refreshed nor removed" {
  threads 45 3 4 2
  gauge
  touch -A -000140 "$FLAG"
  local aged; aged="$(stat -f %m "$FLAG")"
  rm "$FX"/pid.*
  gauge
  [ "$status" -eq 3 ]
  [ "$(row '[.lsd,.trustd,.secd,.tccd,.max,.state,.transition]|map(tojson)|join(",")')" = 'null,null,null,null,null,"tripped","none"' ]
  [ "$(stat -f %m "$FLAG")" = "$aged" ]
  [ "$(lines "$FX/notify.argv")" = 1 ]
}

# mutants: `bounded` removed from the sample call (2026-10-09) · the runner's group KILL removed
# (2026-10-10; the samples ignore TERM, so only the KILL ends them) — each reds this case
@test "a sample that hangs does not hang the gauge: each is cut at its bound, killed, and the row is still written" {
  printf '#!/bin/bash\necho $$ >> "$FX/sample.pids"\ntrap "" TERM\nexec /bin/sleep 300\n' > "$FX/sample"
  threads 45 3 4 2
  local t0=$SECONDS
  CONVOY_GAUGE_SAMPLE_TIMEOUT_S=1 gauge
  [ $(( SECONDS - t0 )) -lt 20 ]
  [ "$status" -eq 0 ]
  [ "$(row '[.state,.transition,.captured]|map(tostring)|join(",")')" = "tripped,trip,true" ]
  [ "$(grep -c '^sample .* rc=124$' "$(row .evidence_dir)/meta.txt")" = 4 ]
  [ "$(lines "$FX/sample.pids")" = 4 ]
  all_dead "$FX/sample.pids"                                      # no wedged sampler outlives the gauge
  [ ! -d "$FX/cc-shed/convoy-gauge.lock" ]                        # the single-flight lock is released
}

# mutants (2026-10-10): the gauge's TERM trap removed (lock held, no row) · the runner's TERM
# handler removed (the samples are orphaned) — each reds this case
@test "a gauge cut by TERM mid-capture kills its samples, releases the lock and still writes its row" {
  printf '#!/bin/bash\necho $$ >> "$FX/sample.pids"\ntrap "" TERM\nexec /bin/sleep 300\n' > "$FX/sample"
  threads 45 3 4 2
  # the caller's bound, as capacity-alarm runs it: the gauge leads its own process group
  /usr/bin/perl -e 'setpgrp(0, 0); exec @ARGV' /bin/bash "$G" > "$FX/out" 2>&1 &
  local gp=$! i=0 rc=0
  while [ "$(lines "$FX/sample.pids")" -lt 4 ] && [ "$i" -lt 100 ]; do sleep 0.1; i=$((i + 1)); done
  [ "$(lines "$FX/sample.pids")" = 4 ]
  kill -TERM -- "-$gp"
  wait "$gp" || rc=$?
  [ "$rc" -eq 143 ]
  [ "$(row '[.state,.transition,.cut]|map(tostring)|join(",")')" = "tripped,trip,true" ]
  [ "$(grep -c '^sample .* rc=143$' "$(row .evidence_dir)/meta.txt")" = 4 ]
  all_dead "$FX/sample.pids"
  [ ! -d "$FX/cc-shed/convoy-gauge.lock" ]
  [ "$(lines "$FX/transitions.log")" = 1 ]
}

@test "single-flight: a run that finds the edge lock held skips capture and page; a stale lock is broken" {
  mkdir -p "$FX/cc-shed/convoy-gauge.lock"
  threads 45 3 4 2
  gauge
  [ "$(row '[.state,.transition,.captured]|map(tostring)|join(",")')" = "tripped,none,false" ]
  [ "$(evidence_dirs)" = 0 ]
  [ "$(lines "$FX/notify.argv")" = 0 ]
  [ -d "$FX/cc-shed/convoy-gauge.lock" ]                          # not ours to release
  touch -A -001000 "$FX/cc-shed/convoy-gauge.lock"                # 10 min old: its holder was cut
  rm -f "$FLAG"
  gauge
  [ "$(row '[.transition,.captured]|map(tostring)|join(",")')" = "trip,true" ]
  [ "$(evidence_dirs)" = 1 ]
  # a FRESH lock whose holder is dead is broken too (a KILLed run cannot release it)
  /bin/sh -c 'exit 0' & local dead=$!; wait "$dead"
  mkdir -p "$FX/cc-shed/convoy-gauge.lock"; echo "$dead" > "$FX/cc-shed/convoy-gauge.lock/pid"
  rm -f "$FLAG"
  gauge
  [ "$(row '[.transition,.captured]|map(tostring)|join(",")')" = "trip,true" ]
  [ ! -d "$FX/cc-shed/convoy-gauge.lock" ]
}

@test "a flag older than 300 s is not a previous state: the next convoy is a fresh trip edge" {
  mkdir -p "$FX/cc-shed"; echo "since=1 lsd=45 trustd=3 secd=4 tccd=2" > "$FLAG"
  touch -A -001000 "$FLAG"
  threads 45 3 4 2
  gauge
  [ "$(row '[.prev,.transition,.captured]|map(tostring)|join(",")')" = "clear,trip,true" ]
  [ "$(lines "$FX/notify.argv")" = 1 ]
}

# mutant (2026-10-10): the uid match removed from the process-table read — reds this case
@test "reads only the current user's daemons, the busiest host instance of each, in two ps reads" {
  printf '101\n201\n301\n' > "$FX/pid.lsd"; echo 9 > "$FX/threads.201"   # two of ours: 5 and 9 threads
  echo 30 > "$FX/threads.301"; echo 0 > "$FX/uid.301"                  # root's lsd, busier: not ours
  gauge
  [ "$(row '[.lsd,.lsd_pid,.state]|join(",")')" = "9,201,clear" ]
  # one process-table read and one thread read, however many instances: a clear run stays cheap
  [ "$(lines "$FX/ps.argv")" = 2 ]
  local m; m="$(grep -- '^-M -p ' "$FX/ps.argv")"
  [[ ",${m#-M -p }," == *,201,* ]] || false                       # both of ours were counted
  [[ ",${m#-M -p }," != *,301,* ]] || false                       # root's never was
}

# mutants (2026-10-10): the ppid-1 check removed (reds on secd) · the CoreSimulator path check
# removed (reds on trustd) · both removed (reds on all three, and the gauge trips)
@test "a busier iOS Simulator instance is never the reading: host daemons only, and the row names the pid" {
  local sim="/Library/Developer/CoreSimulator/Volumes/iOS_23D8133/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.3.simruntime/Contents/Resources/RuntimeRoot/usr/libexec"
  printf '101\n201\n' > "$FX/pid.lsd";    echo 20 > "$FX/threads.201"
  echo 58380 > "$FX/parent.201"; echo "$sim/lsd" > "$FX/path.201"        # launchd_sim's child
  printf '102\n202\n' > "$FX/pid.trustd"; echo 20 > "$FX/threads.202"
  echo "$sim/trustd" > "$FX/path.202"                                    # simulator path, ppid 1
  printf '103\n203\n' > "$FX/pid.secd";   echo 20 > "$FX/threads.203"
  echo 58380 > "$FX/parent.203"                                          # host-like path, not launchd's
  gauge
  [ "$status" -eq 0 ]
  [ "$(row '[.lsd,.trustd,.secd,.lsd_pid,.trustd_pid,.secd_pid,.max,.state]|map(tostring)|join(",")')" = "5,3,4,101,102,103,5,clear" ]
  [ "$(lines "$FX/sample.argv")" = 0 ]
}

@test "runnable processes per priority band come from ONE ps, beside the 1-minute load" {
  gauge
  [ "$(row '[.run_bg,.run_util,.run_default,.run_ui,.run_sys,(.load1 == 197.2)]|map(tostring)|join(",")')" = "1,1,2,1,1,true" ]
  [ "$(grep -c 'state=,pri=' "$FX/ps.argv")" = 1 ]
  touch "$FX/axo.fail"                                            # the table unreadable: null, not zeros
  gauge
  [ "$status" -eq 3 ]
  [ "$(row '[.run_bg,.run_default,.lsd,.max]|map(tojson)|join(",")')" = "null,null,null,null" ]
}

@test "the flag lives in getconf DARWIN_USER_TEMP_DIR/cc-shed when no directory is given" {
  mkdir -p "$FX/dtmp"
  # shellcheck disable=SC2016  # $1 is the stub's own argument
  printf '#!/bin/bash\n[ "$1" = DARWIN_USER_TEMP_DIR ] && echo "%s/dtmp/"\n' "$FX" > "$FX/getconf"
  chmod +x "$FX/getconf"
  unset CONVOY_GAUGE_SHED_DIR
  threads 45 3 4 2
  CONVOY_GAUGE_GETCONF="$FX/getconf" gauge
  [ -f "$FX/dtmp/cc-shed/active" ]
}

# mutant (2026-10-10): EVIDENCE_KEEP default 30->1 · the glob widened from convoy-* to * — each reds
@test "evidence pruning keeps the newest 30 convoy directories and touches nothing else" {
  mkdir -p "$FX/evidence/operator-notes"; touch -t 202601010000 "$FX/evidence/operator-notes"
  local i
  for i in $(seq 10 39); do                                       # 30 older captures, oldest first
    mkdir "$FX/evidence/convoy-202610${i:0:1}0T0000${i}Z-1"
    touch -t "2026090100${i}" "$FX/evidence/convoy-202610${i:0:1}0T0000${i}Z-1"
  done
  threads 45 3 4 2
  gauge
  [ "$(find "$FX/evidence" -mindepth 1 -maxdepth 1 -name 'convoy-*' -type d | wc -l | tr -d ' ')" = 30 ]
  [ ! -d "$FX/evidence/convoy-20261010T000010Z-1" ]               # the oldest went
  [ -d "$FX/evidence/convoy-20261010T000011Z-1" ]
  [ -d "$(row .evidence_dir)" ]                                   # the new one stayed
  [ -d "$FX/evidence/operator-notes" ]                            # not the gauge's: never pruned
}

@test "the page tries desk, then orchestrator, phone fallback off; the role that took it is recorded" {
  threads 45 3 4 2
  NOTIFY_DESK=3 gauge
  [ "$status" -eq 0 ]
  [ "$(row .page)" = orchestrator ]
  [ "$(lines "$FX/notify.argv")" = 2 ]
  [ "$(cut -d' ' -f1-3 "$FX/notify.argv" | tr '\n' '|')" = "phone_fallback=0 --role desk|phone_fallback=0 --role orchestrator|" ]
  # no banner and no sound from this file, on any path: starting one during a convoy parked coreaudiod
  [ "$(grep -v '^[[:space:]]*#' "$G" | grep -c -e osascript -e afplay)" = 0 ]
}

@test "no role takes the page: each rc is recorded and the transition line is still in its log" {
  threads 45 3 4 2
  NOTIFY_DESK=3 NOTIFY_ORCH=3 gauge
  [ "$status" -eq 0 ]
  [ "$(row .page)" = "undelivered:desk=rc3,orchestrator=rc3" ]
  [ "$(lines "$FX/notify.argv")" = 2 ]
  grep -q 'Z TRIP lsd=45 ' "$FX/transitions.log"
}

# mutant (2026-10-10): the runner's cut made KILL-only — reds this case (no interrupted verdict)
@test "a hung page is cut TERM-first, so cc-notify's own trap can report it, then the next role is tried" {
  threads 45 3 4 2
  local t0=$SECONDS
  NOTIFY_DESK=hang NOTIFY_ORCH=hang CONVOY_GAUGE_PAGE_TIMEOUT_S=1 gauge
  [ $(( SECONDS - t0 )) -lt 20 ]
  [ "$status" -eq 0 ]
  [ "$(row .page)" = "undelivered:desk=rc124,orchestrator=rc124" ]
  [ "$(tr '\n' ' ' < "$FX/notify.interrupted")" = "desk orchestrator " ]
}

# mutant (2026-10-10): both lookup candidates replaced with /nonexistent — reds this case
@test "with no transport given, the page finds cc-notify beside the script's REAL path, then in ~/.claude/bin" {
  unset CONVOY_GAUGE_NOTIFY
  # a scratch install: the real script under repo/, reached through a relative symlink, with a decoy
  # beside the link that must NOT be used (following the link is the point)
  mkdir -p "$FX/repo/scripts" "$FX/repo/bin" "$FX/live/scripts" "$FX/live/bin" "$HOME/.claude/bin"
  cp "$G" "$FX/repo/scripts/convoy-gauge.sh"
  cp "$FX/notify" "$FX/repo/bin/cc-notify"
  printf '#!/bin/bash\necho decoy >> "$FX/decoy"\nexit 9\n' > "$FX/live/bin/cc-notify"; chmod +x "$FX/live/bin/cc-notify"
  ln -s ../../repo/scripts/convoy-gauge.sh "$FX/live/scripts/convoy-gauge.sh"
  threads 45 3 4 2
  run /bin/bash "$FX/live/scripts/convoy-gauge.sh"
  [ "$(row .page)" = desk ]
  [ "$(lines "$FX/notify.argv")" = 1 ]
  [ ! -e "$FX/decoy" ]
  # the deployed fallback, when nothing sits beside the real path
  mv "$FX/repo/bin/cc-notify" "$HOME/.claude/bin/cc-notify"
  threads 5 3 4 2
  run /bin/bash "$FX/live/scripts/convoy-gauge.sh"
  [ "$(row '[.transition,.page]|join(",")')" = "clear,desk" ]
  [ "$(lines "$FX/notify.argv")" = 2 ]
  [ ! -e "$FX/decoy" ]
}
