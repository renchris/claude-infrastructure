#!/usr/bin/env bats
# WAVE B2 (lr-wake 2026-10-18, REPORT §4 tier 3; spec c2-capacity-admit-rescue-loop.md §5.3): the
# admission gate's ACTIVE term counts CPU-active turns, against a ceiling in cores.
#
# THE PROPERTY. The old term counted every session whose latest beat is `kind:"prompt"`, so a turn
# blocked in `sleep` counted as load (REPORT RC9; c2 §2.6, the rescuer 2cc3a7fa counting as one of
# its own 8). Gate cases 01-09 replay that with REAL `sleep` processes carrying real prompt beats, so
# the old census genuinely counts them, and a sample file saying what their trees burn. Sampler cases
# 10-13 run scripts/active-cpu-sampler.sh against real processes named `claude`.
#
# RED-PROOF (2026-10-19, this file run against origin/main's capacity-admit.sh, spawn-presence.sh and
# cc-beat.sh at 9c392dbc8): 11 of 13 fail. 01-04, 06, 07 and 09 fail because the gate counts the
# sleepers, has no core ceiling and notes no blindness; 10-13 because the sampler does not exist. 05
# and 08 are CONTROLS that pass on both sides: they pin the revert switch and the no-sampler path to
# the old behavior.
#
# LOAD: the box this runs on sat at load 60-120 on 10 cores the day it was written, so the sampler
# cases never assert an absolute CPU share for the busy process (a runnable loop may get 0.1 core
# there). They assert the sleeper reads ~0 and the busy tree reads well above it, and feed the sampler's
# own file to the gate at a threshold below what the busy tree measured.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/capacity-admit.sh"
  SAMPLER="$REPO/scripts/active-cpu-sampler.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"; mkdir -p "$CC_BEAT_DIR"
  export CC_SP_BEAT_LIB="$REPO/hooks/lib/cc-beat.sh"
  export CC_ADMIT_PRESENCE_LIB="$REPO/scripts/lib/spawn-presence.sh"
  export CC_ADMIT_NOTIFY_BIN="$BATS_TEST_TMPDIR/notify"
  printf '#!/bin/bash\nexit 0\n' > "$CC_ADMIT_NOTIFY_BIN"; chmod +x "$CC_ADMIT_NOTIFY_BIN"
  export CC_ADMIT_ACTIVE_CPU_FILE="$BATS_TEST_TMPDIR/active-cpu.json"
  export CC_ACTIVE_CPU_FILE="$CC_ADMIT_ACTIVE_CPU_FILE"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *hw.ncpu*)                           echo "${STUB_NCPU:-10}" ;;
  *vm.loadavg*)                        echo "{ 1.00 1.00 1.00 }" ;;
  *vm.compressor_segment_limit*)       echo 262144 ;;
  *vm.compressor_segment_buffer_size*) echo 65536 ;;
  *vm.swapusage*)                      echo "total = 8192.00M  used = 0.00M  free = 8192.00M  (encrypted)" ;;
  *) exit 1 ;;
esac
EOF
  chmod +x "$BIN/sysctl"
  export CC_ADMIT_SYSCTL="$BIN/sysctl"
  # Only the ACTIVE term may decide here: every other term is pinned well clear of its ceiling.
  export CC_ADMIT_LOADAVG_OVERRIDE=1.0 CC_ADMIT_HEADROOM_OVERRIDE=64 CC_ADMIT_SEGMENT_OVERRIDE=1
  export CC_SP_TREES_OVERRIDE=3 CC_ADMIT_RESERVE_TERM=off
  export CC_BEAT_NOW=1000000 CC_SP_NOW=1000000 CC_SP_HOUR=12
  unset CC_SP_ACTIVE_OVERRIDE CC_ADMIT_ACTIVE_CEILING CC_ADMIT_ACTIVE_SIGNAL CC_ADMIT_RESTORE_R
  : > "$BATS_TEST_TMPDIR/pids"
}

teardown() {
  local p
  while read -r p; do [ -n "$p" ] || continue; kill "$p" 2>/dev/null || true; done < "$BATS_TEST_TMPDIR/pids"
  return 0
}

admit() { # $1=caller → prints the reason, exits with the gate's rc
  bash -c '. "$1"; cc_capacity_admit "$2" spawn; rc=$?; cc_capacity_admit_reason; exit $rc' _ "$LIB" "$1"
}
row() { jq -r "select(.caller==\"$1\") | .$2 // \"\"" "$CC_ADMIT_IDL"; }
lstart_of() { TZ=UTC ps -o lstart= -p "$1" | tr -s ' ' | sed 's/^ *//;s/ *$//'; }
track() { printf '%s\n' "$1" >> "$BATS_TEST_TMPDIR/pids"; }

# N real sessions blocked in `sleep`, each with a live prompt beat: the old census counts every one.
SLEEPERS=""
sleepers() { # $1=N
  local i p
  SLEEPERS=""
  for i in $(seq 1 "$1"); do
    sleep 300 >/dev/null 2>&1 3>&- & p=$!; track "$p"
    jq -cn --arg sid "s$i" --argjson pid "$p" --arg ls "$(lstart_of "$p")" \
      '{sid:$sid,t:999990,kind:"prompt",pid:$pid,lstart:$ls,who:"auto",seq:1}' > "$CC_BEAT_DIR/s$i.json"
    SLEEPERS="$SLEEPERS $p"
  done
}

# A sample file. $1=age in s; then "pid:cores:mid" triples. Pass t via SAMPLE_T to override.
sample() {
  local age="$1" t trees="" sep="" spec pid cores mid
  shift
  t=$(( $(date +%s) - age ))
  for spec in "$@"; do
    pid="${spec%%:*}"; cores="${spec#*:}"; mid="${cores#*:}"; cores="${cores%%:*}"
    trees="${trees}${sep}{\"pid\":${pid},\"lstart\":\"x\",\"cores\":${cores},\"mid_turn\":${mid}}"; sep=","
  done
  printf '{"v":1,"t":%d,"window_s":15,"beats_live":%s,"other_cores":0,"trees":[%s]}\n' \
    "$t" "${BEATS_LIVE:-true}" "$trees" > "$CC_ADMIT_ACTIVE_CPU_FILE"
}
busy() { local i out=""; for i in $(seq 1 "$1"); do out="$out $((70000 + i)):1.2:true"; done; printf '%s' "$out"; }

# ══ the gate ═══════════════════════════════════════════════════════════════════════════════════════

@test "01 sessions blocked in sleep do NOT count: nine sleeping mid-turn sessions admit" {
  sleepers 9
  local specs="" p
  for p in $SLEEPERS; do specs="$specs $p:0.00:true"; done
  # shellcheck disable=SC2086
  sample 5 $specs
  run admit sleep-a
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(row sleep-a terms)" == *active* ]] || false   # the term ran and cleared; it was not skipped
  [ "$(row sleep-a blind)" = "" ]
}

@test "02 a CPU-busy session counts: eight busy turns refuse at the 10-core ceiling 8, seven admit" {
  # shellcheck disable=SC2046
  sample 5 $(busy 8)
  run admit busy-a
  [ "$status" -eq 9 ]
  [ "$(row busy-a term)" = active ]
  [[ "$output" == *"8 sessions mid-turn + 1 > CPU-active (>=0.25 core) ceiling 10 cores x 0.8 = 8"* ]] || { echo "$output"; false; }
  # shellcheck disable=SC2046
  sample 5 $(busy 7)
  run admit busy-b
  [ "$status" -eq 0 ]
}

@test "03 only MID-TURN trees count, and only at or over the threshold" {
  # Seven busy turns, plus a busy tree between turns, plus a mid-turn tree just under 0.25 core.
  # shellcheck disable=SC2046
  sample 5 $(busy 7) 80001:3.5:false 80002:0.24:true
  run admit mix-a
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The threshold is the gate's own knob: at 0.2 the 0.24 tree is CPU-active and the box is full.
  CC_ADMIT_ACTIVE_CPU_MIN_CORES=0.2 run admit mix-b
  [ "$status" -eq 9 ]
  [ "$(row mix-b term)" = active ]
}

@test "04 the ceiling scales with the core count" {
  # shellcheck disable=SC2046
  sample 5 $(busy 9)
  STUB_NCPU=20 run admit cores-a                # 20 x 0.8 = 16
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # shellcheck disable=SC2046
  sample 5 $(busy 16)
  STUB_NCPU=20 run admit cores-b
  [ "$status" -eq 9 ]
  [[ "$output" == *"ceiling 20 cores x 0.8 = 16"* ]] || { echo "$output"; false; }
  # shellcheck disable=SC2046
  sample 5 $(busy 3)
  STUB_NCPU=4 run admit cores-c                 # 4 x 0.8 = 3
  [ "$status" -eq 9 ]
  # shellcheck disable=SC2046
  sample 5 $(busy 2)
  STUB_NCPU=4 run admit cores-d
  [ "$status" -eq 0 ]
  # The factor is a knob too, and an explicit CC_ADMIT_ACTIVE_CEILING still wins over both.
  STUB_NCPU=4 CC_ADMIT_ACTIVE_PER_CORE=0.5 run admit cores-e   # 4 x 0.5 = 2
  [ "$status" -eq 9 ]
  STUB_NCPU=4 CC_ADMIT_ACTIVE_CEILING=6 run admit cores-f
  [ "$status" -eq 0 ]
}

@test "05 CONTROL: CC_ADMIT_ACTIVE_SIGNAL=beat reverts to the old term exactly" {
  sleepers 9
  local specs="" p
  for p in $SLEEPERS; do specs="$specs $p:0.00:true"; done
  # shellcheck disable=SC2086
  sample 5 $specs
  CC_ADMIT_ACTIVE_SIGNAL=beat run admit revert-a
  [ "$status" -eq 9 ]
  [ "$(row revert-a term)" = active ]
  [[ "$output" == *"9 sessions mid-turn + 1 > active ceiling 8"* ]] || { echo "$output"; false; }
}

@test "06 a STALE sample falls back to the beat census, and the row names the blindness" {
  sleepers 9
  local specs="" p
  for p in $SLEEPERS; do specs="$specs $p:0.00:true"; done
  # shellcheck disable=SC2086
  sample 600 $specs
  run admit stale-a
  [ "$status" -eq 9 ]                           # the old census counts the nine: never wider than before
  [[ "$output" == *"9 sessions mid-turn + 1 > active ceiling 8"* ]] || { echo "$output"; false; }
  [[ "$(row stale-a blind)" == *"active-cpu(stale)"* ]] || false
}

@test "07 a sample whose beat producer is dead, or that does not parse, falls back the same way" {
  sleepers 9
  local specs="" p
  for p in $SLEEPERS; do specs="$specs $p:0.00:true"; done
  # shellcheck disable=SC2086
  BEATS_LIVE=false sample 5 $specs
  run admit dead-a
  [ "$status" -eq 9 ]
  [[ "$(row dead-a blind)" == *"active-cpu(beats-dead)"* ]] || false
  printf '{"t":' > "$CC_ADMIT_ACTIVE_CPU_FILE"
  run admit torn-a
  [ "$status" -eq 9 ]
  [[ "$(row torn-a blind)" == *"active-cpu("* ]] || false
}

@test "08 CONTROL: no sample file at all is the old term, silently (the sampler is not installed)" {
  sleepers 9
  run admit none-a
  [ "$status" -eq 9 ]
  [[ "$output" == *"9 sessions mid-turn + 1 > active ceiling 8"* ]] || { echo "$output"; false; }
  [ "$(row none-a blind)" = "" ]
}

@test "09 the pane's short form still reads the CPU-active refusal" {
  # shellcheck disable=SC2046
  sample 5 $(busy 8)
  run bash -c '. "$1"; cc_capacity_admit short-a spawn; cc_capacity_admit_short' _ "$LIB"
  [ "$output" = "box full 9/8" ] || { echo "$output"; false; }
}

# ══ the sampler ════════════════════════════════════════════════════════════════════════════════════

# Two sessions named `claude`: one blocked in sleep; one whose CHILD burns CPU while the session
# itself waits (a Bash tool running a suite). Both carry a live prompt beat.
two_sessions() {
  mkdir -p "$BATS_TEST_TMPDIR/s" "$BATS_TEST_TMPDIR/b"
  ln -sf /bin/sleep "$BATS_TEST_TMPDIR/s/claude"
  ln -sf /bin/bash  "$BATS_TEST_TMPDIR/b/claude"
  # fds closed so bats never waits on them; teardown kills both (the busy one takes its child along)
  "$BATS_TEST_TMPDIR/s/claude" 300 >/dev/null 2>&1 3>&- & SLEEPY=$!; track "$SLEEPY"
  # shellcheck disable=SC2016  # $c belongs to the inner bash
  "$BATS_TEST_TMPDIR/b/claude" -c 'trap "kill \$c 2>/dev/null; exit 0" TERM; /bin/sh -c "while :; do :; done" & c=$!; wait' \
    </dev/null >/dev/null 2>&1 3>&- &
  BUSY=$!; track "$BUSY"
  sleep 1
  local p
  for p in "$SLEEPY" "$BUSY"; do
    jq -cn --arg sid "x$p" --argjson pid "$p" --arg ls "$(lstart_of "$p")" --argjson t "$(date +%s)" \
      '{sid:$sid,t:$t,kind:"prompt",pid:$pid,lstart:$ls,who:"auto",seq:1}' > "$CC_BEAT_DIR/x$p.json"
  done
  unset CC_BEAT_NOW
}
cores_of() { jq -r --argjson p "$1" '.trees[] | select(.pid == $p) | .cores' "$CC_ACTIVE_CPU_FILE"; }
mid_of()   { jq -r --argjson p "$1" '.trees[] | select(.pid == $p) | .mid_turn' "$CC_ACTIVE_CPU_FILE"; }

@test "10 sampler: the first tick stores a baseline and publishes nothing" {
  run /bin/bash "$SAMPLER" --once
  [ "$status" -eq 0 ]
  [ ! -e "$CC_ACTIVE_CPU_FILE" ]
  [ -s "${CC_ACTIVE_CPU_FILE%.json}.prev" ]
}

@test "11 sampler: a session blocked in sleep reads ~0 cores; a session whose child is busy reads far more" {
  two_sessions
  run /bin/bash "$SAMPLER" --once; [ "$status" -eq 0 ]
  sleep 3
  run /bin/bash "$SAMPLER" --once; [ "$status" -eq 0 ]
  local s b
  s="$(cores_of "$SLEEPY")"; b="$(cores_of "$BUSY")"
  echo "sleepy=$s busy=$b"
  [ -n "$s" ] && [ -n "$b" ] || false
  [ "$(mid_of "$SLEEPY")" = true ] && [ "$(mid_of "$BUSY")" = true ] || false
  awk -v s="$s" -v b="$b" 'BEGIN { exit !(s < 0.02 && b >= 0.05 && b > 5 * s) }'
  [ "$(jq -r .beats_live "$CC_ACTIVE_CPU_FILE")" = true ]
  # End to end: the gate counts the busy tree and not the sleeper (threshold set under what the busy
  # tree measured on this box, see LOAD above).
  run bash -c '. "$1"; CC_ADMIT_ACTIVE_CPU_MIN_CORES=0.04 CC_ADMIT_ACTIVE_CEILING=1 cc_capacity_admit e2e spawn' _ "$LIB"
  [ "$status" -eq 9 ]
  [[ "$(row e2e detail)" == "1 sessions mid-turn + 1 > CPU-active"* ]] || { row e2e detail; false; }
}

@test "12 sampler: a ps that produces nothing is a failed tick, never an idle box" {
  printf '#!/bin/bash\nexit 0\n' > "$BIN/ps-empty"; chmod +x "$BIN/ps-empty"
  CC_ACTIVE_CPU_PS="$BIN/ps-empty" run /bin/bash "$SAMPLER" --once
  [ "$status" -eq 1 ]
  [ ! -e "$CC_ACTIVE_CPU_FILE" ]
}

@test "13 sampler: no beat written inside the live window publishes beats_live:false" {
  two_sessions
  jq -c '.t = 1000' "$CC_BEAT_DIR/x$SLEEPY.json" > "$BATS_TEST_TMPDIR/o" && mv "$BATS_TEST_TMPDIR/o" "$CC_BEAT_DIR/x$SLEEPY.json"
  jq -c '.t = 1000' "$CC_BEAT_DIR/x$BUSY.json" > "$BATS_TEST_TMPDIR/o" && mv "$BATS_TEST_TMPDIR/o" "$CC_BEAT_DIR/x$BUSY.json"
  run /bin/bash "$SAMPLER" --once; [ "$status" -eq 0 ]
  sleep 1
  run /bin/bash "$SAMPLER" --once; [ "$status" -eq 0 ]
  [ "$(jq -r .beats_live "$CC_ACTIVE_CPU_FILE")" = false ]
}
