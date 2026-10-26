#!/usr/bin/env bats
# The brownout term in scripts/lib/capacity-admit.sh (lockup incident 2026-10-25,
# ~/incident-2026-10-25/solution/DESIGN.md C4, cases a-i of its test list).
#
# The replay cases run the library's OWN predicate (cc_brownout_v2_replay shares _CC_BO_AWK_FN with the
# live read) over the real capacity-alarm rows of 10-15, 10-23, 10-24 and 10-25, kept verbatim in
# tests/fixtures/capacity-admit-brownout/alarm-rows.tsv. The pinned numbers were measured on that
# artifact the day it was cut; a change to a threshold or to the window reds case 01/02, and each of
# the three votes has its own per-site mutant (case 03) that must red the replay.
#
# Hermetic: HOME, the state dir, the IDL, the decision log, the lockwatch dir and the alarm log are all
# under the test tmpdir, every other admission term is switched off, and pages go to a recorder.

load helpers/cc-stub   # stubs the kernel never execs as #! (kalloc leak)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/capacity-admit.sh"
  ROWS="$REPO/tests/fixtures/capacity-admit-brownout/alarm-rows.tsv"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ADMIT_BROWNOUT_LOG="$BATS_TEST_TMPDIR/brownout.jsonl"
  export CC_LOCKWATCH_DIR="$BATS_TEST_TMPDIR/lockwatch"; mkdir -p "$CC_LOCKWATCH_DIR"
  export CC_ADMIT_BROWNOUT_ALARM_LOG="$BATS_TEST_TMPDIR/capacity-alarm.jsonl"
  export CC_ADMIT_BROWNOUT_LATCH="$BATS_TEST_TMPDIR/brownout-latch.json"
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  cc_stub "$BATS_TEST_TMPDIR" notify "$(printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/pages.txt"\n' "$BATS_TEST_TMPDIR")"
  # Only the brownout term may decide in this file.
  export CC_ADMIT_LOAD_TERM=off CC_ADMIT_HEADROOM_TERM=off CC_ADMIT_SEGMENT_TERM=off
  export CC_ADMIT_ACTIVE_TERM=off CC_ADMIT_RESERVE_TERM=off
  # and pinned, so a term switched back on by a case still reads no live box
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0 CC_ADMIT_HEADROOM_OVERRIDE=64
  unset CC_ADMIT_BROWNOUT CC_ADMIT_GATE CC_ADMIT_TOKEN LR_ADMIT_TOKEN CC_ADMIT_BROWNOUT_NOW
  NOW=1792879070   # 2026-10-24T21:57:50Z, the replay's first fire
}

# n rows ending at NOW, `gap` seconds apart, each with the given sessions and coalition count.
alarm_rows() { # $1=n $2=sessions $3=coal $4=gap
  local i e
  : > "$CC_ADMIT_BROWNOUT_ALARM_LOG"
  for ((i = $1 - 1; i >= 0; i--)); do
    e=$(( NOW - i * $4 ))
    printf '{"ts":"%s","verdict":"ALARM","sessions":%s,"coal_procs":%s}\n' \
      "$(date -u -r "$e" +%Y-%m-%dT%H:%M:%SZ)" "$2" "$3" >> "$CC_ADMIT_BROWNOUT_ALARM_LOG"
  done
}
brownout_rows() { alarm_rows 20 45 700 60; }   # all three V2 votes
healthy_rows()  { alarm_rows 20 20 200 60; }   # none

admit() { # $1=caller → prints the reason, exits with the gate's rc
  bash -c '. "$1"; cc_capacity_admit "$2" "test spawn"; rc=$?; cc_capacity_admit_reason; exit $rc' _ "$LIB" "$1"
}

# Replay summary over the fixture: "<first fire after 10-24T12Z> <hits 10-24> <hits 10-25> <hits 10-15>/<rows> <hits 10-23>/<rows>"
replay_summary() { # $1=library to source
  grep -v '^#' "$ROWS" | bash -c '. "$1"; cc_brownout_v2_replay' _ "$1" | awk '
    function day(e) { return e >= 1792886400 ? "25" : e >= 1792800000 ? "24" : e >= 1792713600 ? "23" : e >= 1792022400 && e < 1792108800 ? "15" : "x" }
    { d = day($1); n[d]++; if ($2 == 1) { h[d]++; if (d == "24" && $1 >= 1792843200 && first == "") first = $1 } }
    END { printf "%s %d %d %d/%d %d/%d\n", first, h["24"], h["25"], h["15"], n["15"], h["23"], n["23"] }'
}

@test "01 (a) the real 10-24/25 rows: the replay first refuses at 21:57:50Z and holds through the collapse" {
  [ -f "$ROWS" ] || false
  run replay_summary "$LIB"
  [ "$status" -eq 0 ] || false
  # shellcheck disable=SC2086  # deliberate: split the summary into its fields
  set -- $output
  [ "$1" = 1792879070 ] || { echo "first fire $1, want 1792879070 (21:57:50Z): $output"; false; }
  [ "$2" = 18 ] || { echo "10-24 hits $2, want 18: $output"; false; }
  [ "$3" = 103 ] || { echo "10-25 hits $3, want 103: $output"; false; }
}

@test "02 (b) normal days: 10-15 and 10-23 refuse on 2% of their rows or fewer" {
  run replay_summary "$LIB"
  # shellcheck disable=SC2086  # deliberate: split the summary into its fields
  set -- $output
  [ "$4" = 0/1366 ] || { echo "10-15: $4, want 0/1366"; false; }
  [ "$5" = 8/1011 ] || { echo "10-23: $5, want 8/1011"; false; }
  awk -v a="${5%/*}" -v b="${5#*/}" 'BEGIN { exit !(a / b <= 0.02) }' || false
}

@test "03 (c) one mutant per vote reds the replay: sessions, coalition, cadence" {
  local pinned site mutant out
  pinned="$(replay_summary "$LIB")"
  for site in '(s >= S)' '(c >= C)' '(rows < R)'; do
    mutant="$BATS_TEST_TMPDIR/mutant.sh"
    sed "s/$site/0/" "$LIB" > "$mutant"   # BRE: a bare ( is literal
    ! cmp -s "$LIB" "$mutant" || { echo "mutant for $site changed nothing — the site moved"; false; }
    out="$(replay_summary "$mutant")"
    [ "$out" != "$pinned" ] || { echo "deleting $site left the replay at '$pinned' — that vote is untested"; false; }
  done
}

@test "04 (d) immune to CC_ADMIT_LOAD_TERM=off, CC_ADMIT_ACTIVE_TERM=off and CC_ADMIT_GATE=off" {
  brownout_rows
  export CC_ADMIT_BROWNOUT=on CC_ADMIT_BROWNOUT_NOW="$NOW"
  run admit cc-dispatch
  [ "$status" -eq 9 ] || { echo "$output"; false; }
  CC_ADMIT_GATE=off run admit cc-dispatch
  [ "$status" -eq 9 ] || { echo "gate-off admitted: $output"; false; }
  [ "$(jq -r 'select(.verdict == "refuse") | .basis' "$CC_ADMIT_IDL" | sort -u)" = brownout ] || false
  [ "$(jq -r 'select(.verdict == "refuse") | .term' "$CC_ADMIT_IDL" | sort -u)" = brownout ] || false
  # the operator kill switch is the one way through
  CC_ADMIT_BROWNOUT=off run admit cc-dispatch
  [ "$status" -eq 0 ] || false
}

@test "05 (e) not budget-charged: 10 consecutive refusals never become budget-expired" {
  brownout_rows
  export CC_ADMIT_BROWNOUT=on CC_ADMIT_BROWNOUT_NOW="$NOW" CC_ADMIT_BUDGET=3
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    run admit strand-fill
    [ "$status" -eq 9 ] || { echo "refusal $i admitted: $output"; false; }
  done
  ! grep -q budget-expired "$CC_ADMIT_IDL" || false
  [ ! -s "$CC_ADMIT_STATE_DIR/strand-fill.refusals" ] || false
  # one rising-edge page for the episode, not one per refusal
  [ "$(grep -c 'brownout ON' "$BATS_TEST_TMPDIR/pages.txt")" = 1 ] || false
}

@test "06 (f) recovery admits are spaced 1 per 5 min while in brownout" {
  brownout_rows
  export CC_ADMIT_BROWNOUT=on
  CC_ADMIT_BROWNOUT_NOW="$NOW" run admit boot-resume-launch
  [ "$status" -eq 0 ] || { echo "first recovery refused: $output"; false; }
  CC_ADMIT_BROWNOUT_NOW="$(( NOW + 60 ))" run admit boot-resume-launch
  [ "$status" -eq 9 ] || { echo "second within 5 min admitted: $output"; false; }
  [[ "$output" == *"spaced 1 per 300s"* ]] || false
  CC_ADMIT_BROWNOUT_NOW="$(( NOW + 301 ))" run admit lr-fire-resume
  [ "$status" -eq 0 ] || { echo "after the spacing: $output"; false; }
}

@test "07 (g) a stale lockwatch heartbeat gives no V1 vote; a fresh one does" {
  export CC_ADMIT_BROWNOUT=on
  printf '{"v":1,"level":2,"kitty_rc":"ok"}\n' > "$CC_LOCKWATCH_DIR/state.json"
  : > "$CC_LOCKWATCH_DIR/hb"
  touch -t "$(date -r $(( $(date +%s) - 60 )) +%Y%m%d%H%M.%S)" "$CC_LOCKWATCH_DIR/hb"
  run admit agent-tool
  [ "$status" -eq 0 ] || { echo "stale hb voted: $output"; false; }
  : > "$CC_LOCKWATCH_DIR/hb"
  run admit agent-tool
  [ "$status" -eq 9 ] || { echo "fresh hb at level 2 did not vote: $output"; false; }
  [[ "$output" == *V1* ]] || false
  printf '{"v":1,"level":0}\n' > "$CC_LOCKWATCH_DIR/state.json"
  run admit agent-tool
  [ "$status" -eq 0 ] || false
}

@test "08 (h) observe mode (the default) logs would-refuse and admits; the shadow audit arms it" {
  brownout_rows
  export CC_ADMIT_BROWNOUT_NOW="$NOW"
  run admit cc-dispatch
  [ "$status" -eq 0 ] || { echo "observe refused: $output"; false; }
  [ "$(jq -r '.verdict' "$CC_ADMIT_BROWNOUT_LOG" | tail -1)" = would-refuse ] || false
  [ "$(jq -r '.mode' "$CC_ADMIT_BROWNOUT_LOG" | tail -1)" = observe ] || false
  jq -e 'select(.verdict == "admit") | .brownout | test("^observe:would-refuse V2 .*sessions=45,coal=700,rows900=")' "$CC_ADMIT_IDL" >/dev/null || false
  [ ! -s "$BATS_TEST_TMPDIR/pages.txt" ] || false            # observe never pages
  # pass_gate alone does not arm it: pass_band must hold too
  printf '{"pass_gate":true,"pass_band":false}\n' > "$CC_LOCKWATCH_DIR/shadow-audit.json"
  run admit cc-dispatch
  [ "$status" -eq 0 ] || false
  printf '{"pass_gate":true,"pass_band":true}\n' > "$CC_LOCKWATCH_DIR/shadow-audit.json"
  run admit cc-dispatch
  [ "$status" -eq 9 ] || { echo "armed audit did not refuse: $output"; false; }
  # healthy rows clear it whatever the mode
  healthy_rows
  run admit cc-dispatch
  [ "$status" -eq 0 ] || false
}

@test "09 V4 latch and V5 lockup boot vote; --brownout-check exits 75 for discretionary" {
  export CC_ADMIT_BROWNOUT=on CC_ADMIT_BROWNOUT_NOW="$NOW"
  printf '{"surface_unavailable_since":%s,"by":"cc-dispatch"}\n' "$(( NOW - 600 ))" > "$CC_ADMIT_BROWNOUT_LATCH"
  run /bin/bash "$LIB" --brownout-check discretionary dl-sweep
  [ "$status" -eq 75 ] || { echo "$output"; false; }
  [[ "$output" == *V4* ]] || false
  printf '{"surface_unavailable_since":"%s","by":"operator"}\n' "$(date -u -r $(( NOW - 1900 )) +%Y-%m-%dT%H:%M:%SZ)" > "$CC_ADMIT_BROWNOUT_LATCH"
  run /bin/bash "$LIB" --brownout-check discretionary dl-sweep
  [ "$status" -eq 0 ] || { echo "a 31-min-old latch still voted: $output"; false; }
  rm -f "$CC_ADMIT_BROWNOUT_LATCH"
  printf '{"class":"LOCKUP_DEVFS"}\n' > "$CC_LOCKWATCH_DIR/boot-1792870000.json"
  CC_ADMIT_BROWNOUT_BOOTTIME="$(( $(date +%s) - 120 ))" CC_ADMIT_BROWNOUT_NOW="$(date +%s)" \
    run /bin/bash "$LIB" --brownout-check discretionary dl-sweep
  [ "$status" -eq 75 ] || { echo "$output"; false; }
  [[ "$output" == *V5* ]] || false
  # a boot file older than this boot is a previous boot's verdict, not a vote
  CC_ADMIT_BROWNOUT_BOOTTIME="$(( $(date +%s) + 100 ))" CC_ADMIT_BROWNOUT_NOW="$(( $(date +%s) + 200 ))" \
    run /bin/bash "$LIB" --brownout-check discretionary dl-sweep
  [ "$status" -eq 0 ] || false
  # a usage error is not a refusal
  run /bin/bash "$LIB" --bogus
  [ "$status" -eq 64 ] || false
}

@test "10 (i) under brownout classifier-warm.sh sleeps and asks again, never exiting 75" {
  brownout_rows
  export CC_ADMIT_BROWNOUT=on CC_ADMIT_BROWNOUT_NOW="$NOW" CC_RESEARCH_WARM_BROWNOUT_WAIT=1
  local pid i n=0
  /usr/bin/perl -e 'alarm 120; exec @ARGV' -- /bin/bash "$REPO/scripts/research-kit/jobs/classifier-warm.sh" \
    2> "$BATS_TEST_TMPDIR/warm.err" &
  pid=$!
  for i in $(seq 1 900); do
    n="$(grep -c 'asking again in 1s' "$BATS_TEST_TMPDIR/warm.err" 2>/dev/null || true)"
    [ "${n:-0}" -ge 2 ] && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.1
  done
  # still running after two refusals: it slept and asked again rather than exiting (75 or otherwise)
  kill -0 "$pid" 2>/dev/null || { wait "$pid"; echo "the runner EXITED rc=$? after $n refusal(s)"; cat "$BATS_TEST_TMPDIR/warm.err"; false; }
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  [ "${n:-0}" -ge 2 ] || { cat "$BATS_TEST_TMPDIR/warm.err"; false; }
}

@test "11 (i) under brownout classifier-warm.py serve spawns no worker; with it off, it does" {
  brownout_rows
  local sockd seen
  sockd="$(mktemp -d /tmp/ccbo.XXXXXX)"; seen="$BATS_TEST_TMPDIR/seen"; mkdir -p "$seen"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/rh" CC_RESEARCH_WARM_SOCK="$sockd/sock"
  export CC_ADMIT_BROWNOUT_NOW="$NOW" CC_RESEARCH_WARM_CHILD="touch $seen/\$\$; sleep 30"
  unset CC_BATS_ACTIVE CC_RESEARCH_ROUTER CC_RESEARCH_ROUTER_INNER CC_RESEARCH_WARM
  # serve one arm until it says it is serving, give its fill loop `$2` s, then end it (our own child).
  serve_arm() { # $1=CC_ADMIT_BROWNOUT $2=seconds after "serving on"
    local pid i
    CC_ADMIT_BROWNOUT="$1" /usr/bin/perl -e 'alarm 120; exec @ARGV' -- \
      /usr/bin/python3 "$REPO/scripts/research-kit/classifier-warm.py" serve 2> "$BATS_TEST_TMPDIR/serve-$1.err" &
    pid=$!
    for i in $(seq 1 300); do grep -q 'serving on' "$BATS_TEST_TMPDIR/serve-$1.err" 2>/dev/null && break; sleep 0.1; done
    grep -q 'serving on' "$BATS_TEST_TMPDIR/serve-$1.err" || { kill "$pid" 2>/dev/null; echo "serve never started"; return 1; }
    for i in $(seq 1 $(( $2 * 10 ))); do [ "$1" = off ] && [ -n "$(ls "$seen")" ] && break; sleep 0.1; done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  }
  serve_arm on 4
  [ -z "$(ls "$seen")" ] || { echo "a worker spawned under brownout: $(ls "$seen")"; false; }
  serve_arm off 30
  [ -n "$(ls "$seen")" ] || { echo "the control spawned nothing — case proves nothing"; cat "$BATS_TEST_TMPDIR/serve-off.err"; false; }
  rm -rf "$sockd"
}

# The load band (lead ruling 2026-10-25, decision 888ad4830b80): observe-only by default.
# lb_checks <lib> → 0 iff observe logs a would-refuse row and admits, enforce refuses unbudgeted,
# under-band and non-autonomous callers write nothing.
lb_checks() {
  local lib="$1" sc="$BATS_TEST_TMPDIR/sysctl" r
  cc_stub "$BATS_TEST_TMPDIR" sysctl '#!/bin/bash
case "$*" in *hw.ncpu*) echo 10 ;; *) echo "{ 1.0 1.0 1.0 }" ;; esac'
  : > "$CC_ADMIT_IDL"
  lb() { CC_ADMIT_SYSCTL="$sc" bash -c '. "$1"; cc_capacity_admit "$2" "lb spawn"' _ "$lib" "$1"; }
  CC_ADMIT_LOADBAND_LOAD15=600 lb cc-dispatch || return 1                                    # observe admits
  r="$(jq -c 'select(.gate == "loadband")' "$CC_ADMIT_IDL")"
  [ "$(printf '%s\n' "$r" | jq -r '[.verdict, .mode, .caller, (.per_core | floor), .ceiling_per_core] | @tsv')" = "$(printf 'would-refuse\tobserve\tcc-dispatch\t60\t50')" ] || return 1
  r=0; CC_ADMIT_LOADBAND=enforce CC_ADMIT_LOADBAND_LOAD15=600 lb strand-fill || r=$?
  [ "$r" = 9 ] || return 1
  [ "$(jq -r 'select(.gate == "capacity-admit" and .verdict == "refuse") | .basis' "$CC_ADMIT_IDL")" = loadband ] || return 1
  [ ! -s "$CC_ADMIT_STATE_DIR/strand-fill.refusals" ] || return 1                            # no budget
  : > "$CC_ADMIT_IDL"
  CC_ADMIT_LOADBAND=enforce CC_ADMIT_LOADBAND_LOAD15=400 lb cc-dispatch || return 1          # 40/core: under
  CC_ADMIT_LOADBAND=enforce CC_ADMIT_LOADBAND_LOAD15=600 lb boot-resume-launch || return 1   # recovery: not autonomous
  [ -z "$(jq -c 'select(.gate == "loadband")' "$CC_ADMIT_IDL")" ] || return 1
  return 0
}

@test "12 load band: observe logs would-refuse and admits; enforce refuses without a budget charge" {
  lb_checks "$LIB" || { echo "load band contract broken"; cat "$CC_ADMIT_IDL"; false; }
}

@test "13 load band: one mutant on the comparison reds both the observe row and the enforce refusal" {
  local m="$BATS_TEST_TMPDIR/lb-mutant.sh"
  sed 's/print (p > c) ? 1 : 0/print 0/' "$LIB" > "$m"
  ! cmp -s "$LIB" "$m" || { echo "the comparison site moved"; false; }
  ! lb_checks "$m" || { echo "a load band that never fires passed the contract"; false; }
  # and the enforce half alone is pinned: a mutant that only stops refusing
  sed 's/\[ "\$mode" = enforce \] && return 75/:/' "$LIB" > "$m"
  ! cmp -s "$LIB" "$m" || { echo "the enforce site moved"; false; }
  ! lb_checks "$m" || { echo "an enforce that refuses nothing passed the contract"; false; }
}
