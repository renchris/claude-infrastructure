#!/usr/bin/env bats
# tests/capacity-marginal.bats — the TWO-ARM marginal experiment in scripts/capacity-ramp.sh.
#
# Split from tests/capacity-ramp.bats on purpose: that suite pins the S6-DOD D1 RAMP (its two
# hard-learned properties — tracked-pid teardown and refuse-before-launch), and this one pins a
# different subject that happens to live in the same file — an EXPERIMENT whose output is a number
# other people will quote. The properties worth pinning are correspondingly different, and all four
# are failure modes this repo has already committed at least once:
#
#   1. A BLIND PROBE NEVER READS 0. A dead load probe that returned 0 would produce a log of
#      0.000-per-session rows, which is the exact conclusion the experiment exists to test. Same
#      rule as the ramp's own D3 UNVERIFIABLE branch, one instrument over.
#   2. THE CENSUS CONTROL MUST BE ABLE TO FAIL. A trial is valid only when the session census moved
#      by EXACTLY 1. The wave that motivated this work had its headline finding ("64% of runnable
#      threads are our own automation") killed by a census that stayed flat while load moved.
#   3. THE NULL ARM BOUNDS THE CLAIM. §8.5.7 measured this box at 29.15 -> 59.80 load with session
#      count constant. A per-unit delta smaller than the box's own drift over the same window is not
#      a measurement, and the report must say UNRESOLVED rather than print it.
#   4. THE FIGURE CARRIES ITS OWN LIMITS. The unit is resident-idle, so every number is a lower
#      bound, and none of them licenses moving CC_HW_DEFAULT_MAX_LOAD_PER_CORE.
#
# sysctl is STUBBED (tests/handoff-fire-capacity-gate.bats' pattern) rather than driven through the
# CC_RAMP_LOADAVG_OVERRIDE seam, so these cases exercise the REAL probe — including the
# `{ 1.23 4.56 7.89 }` field-2 parse, which an override would skip straight past.
#
# RED-PROOF (recorded 2026-08-19). M10 is the standing mutation: the SAME row relabelled valid makes
# the median 2 instead of 1.5, so M9 is asserting an exclusion that changes the answer. That fixture
# had to be rebuilt once and the reason is worth keeping — the first attempt used [1, 1, 1] valid
# against a 17.00 outlier, and a median over [1, 1, 1, 17] is still 1. The case passed with the
# control deleted, because the median was doing the control's job. A mutation that the statistic
# absorbs is not a mutation.
# M8 and M12 are the positive controls for the refusal cases (M6/M7/M11 and the absent-log arm), so
# none of them is asserting a refusal the subject emits unconditionally.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/capacity-ramp.sh"
  TMP="$(mktemp -d)"
  export CC_RAMP_PIDFILE="$TMP/pids.txt"
  export CC_RAMP_FIFODIR="$TMP"
  export CC_RAMP_SETTLE=0
  export CC_RAMP_MARGINAL_SETTLE=0
  export CC_RAMP_MARGINAL_LOG="$TMP/marginal.jsonl"
  export CC_RAMP_BIN=/bin/echo
  # Hermetic HOME: seg_read() and the default log path both live under it.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  printf '{"ts":"%s","t":42,"seg":0,"lim":1629615,"pct":0.00}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$HOME/.claude/logs/compressor-sentinel.jsonl"
}

teardown() { bash "$SCRIPT" down >/dev/null 2>&1 || true; rm -rf "$TMP"; }

# stub_sysctl: a sysctl that answers from a QUEUE of 1-minute load values, one per call, repeating
# the last when the queue runs dry. The wire format is real — `sysctl -n vm.loadavg` prints
# `{ 1.23 4.56 7.89 }`, so field 2 is the 1-minute figure and field 1 is a brace. A stub that
# printed a bare number would let a `$1`-vs-`$2` slip pass.
stub_sysctl() { # $@ = successive load1 values
  printf '%s\n' "$@" > "$TMP/loadq"
  cat > "$TMP/sysctl" <<'STUB'
#!/bin/bash
q="$(dirname "$0")/loadq"; n="$(dirname "$0")/loadn"
case "$2" in
  vm.loadavg)
    i=$(( $(cat "$n" 2>/dev/null || echo 0) + 1 )); echo "$i" > "$n"
    total="$(wc -l < "$q")"; [ "$i" -gt "$total" ] && i="$total"
    printf '{ %s 0.00 0.00 }\n' "$(sed -n "${i}p" "$q")" ;;
  hw.ncpu) echo 10 ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$TMP/sysctl"
  export CC_RAMP_SYSCTL="$TMP/sysctl"
}

# seed_log: write marginal rows straight into the log so the REPORT's arithmetic is testable without
# spawning anything. Field order matches m_emit exactly.
row() { # $1=event $2=i $3=s_pre $4=s_post $5=l_pre $6=l_post $7=valid
  printf '{"ts":"2026-08-19T00:00:00Z","event":"%s","i":%s,"sessions_pre":%s,"sessions_post":%s,"dsessions":%s,"load_pre":%s,"load_post":%s,"dload":%s,"ncpu":10,"settle":300,"valid":%s,"why":"fixture"}\n' \
    "$1" "$2" "$3" "$4" "$(( $4 - $3 ))" "$5" "$6" \
    "$(awk -v a="$5" -v b="$6" 'BEGIN{printf "%.3f", b - a}')" "$7" >> "$CC_RAMP_MARGINAL_LOG"
}

@test "M1 stat carries the LOAD term the ramp shipped without — per core, from the real probe" {
  stub_sysctl 12.50
  run bash "$SCRIPT" stat
  [ "$status" -eq 0 ]
  [[ "$output" == *"load=12.50(1.25/core)"* ]] || { echo "got: $output"; return 1; }
}

@test "M2 a dead load probe reads BLIND, never 0 — a 0 is the healthiest possible number" {
  export CC_RAMP_SYSCTL="$TMP/absent-sysctl"
  run bash "$SCRIPT" stat
  [ "$status" -eq 0 ]
  [[ "$output" == *"load=BLIND"* ]] || { echo "got: $output"; return 1; }
  [[ "$output" != *"load=0"* ]]
}

@test "M3 marginal REFUSES a blind load probe and spawns NOTHING" {
  # ncpu answers, vm.loadavg does not: the load arm alone is dead, which is the case a 0 would hide.
  cat > "$TMP/sysctl" <<'STUB'
#!/bin/bash
case "$2" in hw.ncpu) echo 10 ;; *) exit 1 ;; esac
STUB
  chmod +x "$TMP/sysctl"
  export CC_RAMP_SYSCTL="$TMP/sysctl"
  run bash "$SCRIPT" marginal 3
  [ "$status" -eq 4 ]
  [[ "$output" == *"BLIND"* ]] || false
  [ ! -f "$CC_RAMP_PIDFILE" ]
}

@test "M4 marginal REFUSES when hw.ncpu is unreadable — no per-core figure without a denominator" {
  cat > "$TMP/sysctl" <<'STUB'
#!/bin/bash
case "$2" in vm.loadavg) echo "{ 12.50 0 0 }" ;; *) exit 1 ;; esac
STUB
  chmod +x "$TMP/sysctl"
  export CC_RAMP_SYSCTL="$TMP/sysctl"
  run bash "$SCRIPT" marginal 3
  [ "$status" -eq 4 ]
  [[ "$output" == *"hw.ncpu unreadable"* ]] || false
  [ ! -f "$CC_RAMP_PIDFILE" ]
}

@test "M5 the NULL ARM runs FIRST and is recorded — the control before any unit is spent" {
  stub_sysctl 10.00 13.40
  run bash "$SCRIPT" marginal 0
  [ "$status" -eq 0 ]
  [ "$(jq -rs 'length' "$CC_RAMP_MARGINAL_LOG")" = "1" ]
  [ "$(jq -rs '.[0].event' "$CC_RAMP_MARGINAL_LOG")" = "null-arm" ]
  # Compared ARITHMETICALLY, not as a string: jq >= 1.7 preserves a number's literal spelling, so
  # the row's "3.400" renders as 3.400 here and as 3.4 under jq 1.6 — a string compare would pin the
  # jq version rather than the measurement.
  [ "$(jq -rs '(.[0].dload + 0) == 3.4' "$CC_RAMP_MARGINAL_LOG")" = "true" ]
  [[ "$output" == *"NULL ARM"* ]] || false
  [ ! -f "$CC_RAMP_PIDFILE" ]     # trials=0 spawns nothing; the control still ran
}

@test "M6 the report REFUSES a figure below the minimum trial count" {
  export CC_RAMP_MARGINAL_MIN_TRIALS=5
  row null-arm 0 14 14 20.00 20.05 true
  row trial 1 14 15 20.00 20.90 true
  row trial 2 15 16 20.90 21.85 true
  run bash "$SCRIPT" marginal-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"INSUFFICIENT"* ]] || false
  [[ "$output" == *"2 of 5"* ]] || false
  [[ "$output" != *"median marginal"* ]]
}

@test "M7 the report says UNRESOLVED when the median is inside the box's own drift" {
  export CC_RAMP_MARGINAL_MIN_TRIALS=3
  row null-arm 0 14 14 20.00 24.00 true     # 4.00 of drift with NO unit added
  row trial 1 14 15 20.00 20.30 true
  row trial 2 15 16 20.30 20.65 true
  row trial 3 16 17 20.65 20.90 true
  run bash "$SCRIPT" marginal-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNRESOLVED"* ]] || false
  [[ "$output" != *"median marginal"* ]]
}

@test "M8 POSITIVE CONTROL — it DOES resolve when the term clears the drift, with its limits attached" {
  export CC_RAMP_MARGINAL_MIN_TRIALS=3
  row null-arm 0 14 14 20.00 20.10 true     # 0.10 of drift
  row trial 1 14 15 20.00 21.00 true
  row trial 2 15 16 21.00 22.00 true
  row trial 3 16 17 22.00 23.00 true
  run bash "$SCRIPT" marginal-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESOLVED"* ]] || false
  [[ "$output" == *"median marginal ... 1 load"* ]] || false
  [[ "$output" == *"RESIDENT-IDLE"* ]] || false
  [[ "$output" == *"does NOT license moving CC_HW_DEFAULT_MAX_LOAD_PER_CORE"* ]]
}

@test "M9 THE CENSUS CONTROL — a trial whose census did not move by 1 is EXCLUDED, not averaged in" {
  # The fixture is chosen so exclusion CHANGES THE ANSWER. A median over [1, 2] is 1.5; admitting a
  # 17.00 delta drawn from a population that gained five sessions makes it 2. If the numbers were
  # picked so the median survived the outlier either way, this case would pass with the control
  # deleted — which is M10.
  export CC_RAMP_MARGINAL_MIN_TRIALS=2
  row null-arm 0 14 14 20.00 20.10 true
  row trial 1 14 15 20.00 21.00 true
  row trial 2 15 16 21.00 23.00 true
  row trial 3 16 21 23.00 40.00 false       # five sessions appeared: a delta over a moving population
  run bash "$SCRIPT" marginal-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"valid trials ....... 2"* ]] || false
  [[ "$output" == *"invalid trials ..... 1"* ]] || false
  [[ "$output" == *"median marginal ... 1.5 load"* ]]
}

@test "M10 MUTATION — counting that invalid trial moves the median, which is what M9 pins" {
  export CC_RAMP_MARGINAL_MIN_TRIALS=2
  row null-arm 0 14 14 20.00 20.10 true
  row trial 1 14 15 20.00 21.00 true
  row trial 2 15 16 21.00 23.00 true
  row trial 3 16 21 23.00 40.00 true        # the SAME row, mislabelled valid — the neutered control
  run bash "$SCRIPT" marginal-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"valid trials ....... 3"* ]] || false
  [[ "$output" != *"median marginal ... 1.5 load"* ]] || false # M9's figure is gone...
  [[ "$output" == *"median marginal ... 2 load"* ]]     # ...replaced by one the control was excluding
}

@test "M11 the report REFUSES to resolve a log with NO null arm — a delta without a control" {
  export CC_RAMP_MARGINAL_MIN_TRIALS=3
  row trial 1 14 15 20.00 21.00 true
  row trial 2 15 16 21.00 22.00 true
  row trial 3 16 17 22.00 23.00 true
  run bash "$SCRIPT" marginal-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNCONTROLLED"* ]] || false
  [[ "$output" != *"median marginal"* ]]
}

@test "M12 the report refuses an ABSENT log rather than reporting an empty experiment as 0" {
  run bash "$SCRIPT" marginal-report
  [ "$status" -eq 1 ]
  [[ "$output" == *"no marginal log"* ]]
}
