#!/usr/bin/env bats
# capacity-alarm rung 5 — compressor SEGMENT saturation, the axis the machine died on 2026-07-30.
#
# WHY THIS ROW EXISTS. The 02:18:05 panic read `watchdog timeout: no checkins from watchdogd in 92
# seconds`, but the kernel's own verdict 149 s earlier was:
#     {"compressor_exhausted": 1, "zone_map_is_exhausted": 0, "swap_low": 0, "swap_exhausted": 0}
# with memorystatus_available_pages: 1310531 — twenty gigabytes free, swap healthy, pressure normal.
# Every rung capacity-alarm already had reads a HEALTHY box in that state. The panic log's own
# `Compressor Info: 33% of compressed pages limit (OK) and 100% of segments limit (BAD)` names the
# only term that was out of range, and `COMP` was sampled but never reached classify().
#
# THE PROOF THAT MATTERS is the positive control below: the REAL pre-fix classify() recovered from
# git must call the real dying state OK. A hand-written approximation would pass vacuously
# (memory control-must-replay-the-real-artifact).

setup() {
  # Fixture HOME before anything else. capacity-alarm.sh appends to ~/.claude/logs/capacity-alarm.jsonl
  # and writes/removes ~/.claude/autonomy/pages/capacity-alarm.page, so an unfixtured run mutates the
  # operator's live telemetry — observed for real: a bare smoke run of this script during development
  # appended a row to the live log, which is precisely what the hermeticity ratchet exists to stop.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs" "$HOME/.claude/autonomy/pages"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  A="$REPO/scripts/capacity-alarm.sh"
  # classify() is extracted and sourced in isolation by run_classify below, so a probe never touches
  # the live machine's zprint/sysctl — the suite must be identical on a loaded box and an idle one.
  D="$BATS_TEST_TMPDIR"
}

# Run classify() from an arbitrary copy of the script with explicit thresholds.
run_classify() { # <script> <args...>
  local script="$1"; shift
  bash -c '
    WARN_GB=8; ALARM_GB=3; PROC_WARN_GB=3; SEG_WARN_PCT=45; SEG_ALARM_PCT=70
    '"$(sed -n '/^classify() {/,/^}/p' "$script")"'
    classify "$@"
  ' _ "$@"
}

@test "POSITIVE CONTROL: the REAL pre-fix classify recovered from git calls the dying box OK" {
  # The newest commit of scripts/capacity-alarm.sh whose classify() has no seg/rung-5 term. If no
  # such commit is reachable the control cannot run, and a control that cannot run must SKIP LOUDLY.
  local sha pre="$D/pre.sh" found=""
  for sha in $(git -C "$REPO" log --format=%H -n 40 -- scripts/capacity-alarm.sh); do
    git -C "$REPO" show "$sha:scripts/capacity-alarm.sh" > "$pre" 2>/dev/null || continue
    grep -q '^classify() {' "$pre" || continue
    if ! sed -n '/^classify() {/,/^}/p' "$pre" | grep -q 'SEG_ALARM_PCT'; then found="$sha"; break; fi
  done
  [ -n "$found" ] || skip "no pre-rung-5 commit of capacity-alarm.sh reachable — control cannot run"

  # The literal 2026-07-30 02:15:36 state: headroom 20 GB, swap 0 MB, pressure normal(1), no outlier.
  run run_classify "$pre" 20 0 1 0
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]   # <-- the bug: three minutes from a kernel panic, reported healthy
}

@test "the fixed classify turns that same dying state into ALARM" {
  run run_classify "$A" 20 0 1 0 100
  [ "$status" -eq 0 ]
  [ "$output" = "ALARM" ]
}

@test "rung 5 thresholds: 70 ALARM / 45 WARN / 44 OK" {
  run run_classify "$A" 99 0 1 0 70;  [ "$output" = "ALARM" ]
  run run_classify "$A" 99 0 1 0 45;  [ "$output" = "WARN" ]
  run run_classify "$A" 99 0 1 0 44;  [ "$output" = "OK" ]
}

@test "an unreadable segment count is SKIPPED, never a fabricated healthy 0" {
  # Empty and non-numeric must both leave the verdict untouched — the failure that would otherwise
  # reintroduce the exact bug this rung exists to catch (a broken sensor reading as green).
  run run_classify "$A" 99 0 1 0 '';  [ "$output" = "OK" ]
  run run_classify "$A" 99 0 1 0 '?'; [ "$output" = "OK" ]
  # ...and it must not MASK a real breach on another rung either.
  run run_classify "$A" 1 0 1 0 '';   [ "$output" = "ALARM" ]
}

@test "rung 5 cannot downgrade a breach found by another rung" {
  run run_classify "$A" 1 512 4 9 0
  [ "$output" = "ALARM" ]
}

@test "read_segments refuses to invent a number when zprint is unreadable" {
  # Three distinct unreadable shapes, each of which must fail (non-zero) rather than print a 0 that
  # would render as a healthy 0.0%.
  local stub="$D/bin"; mkdir -p "$stub"
  printf '#!/bin/bash\necho "zone name a b c d e f g h"\n' > "$stub/zprint"   # row absent
  chmod +x "$stub/zprint"
  run bash -c 'CC_CAP_ZPRINT='"$stub"'/zprint; '"$(sed -n '/^read_segments() {/,/^}/p' "$A")"'
               read_segments'
  [ "$status" -ne 0 ]
  [ -z "$output" ]

  printf '#!/bin/bash\necho "compressor_segment 184 0K 0K 0 0 BOGUS 0K 0"\n' > "$stub/zprint"
  chmod +x "$stub/zprint"
  run bash -c 'CC_CAP_ZPRINT='"$stub"'/zprint; '"$(sed -n '/^read_segments() {/,/^}/p' "$A")"'
               read_segments'
  [ "$status" -ne 0 ]

  run bash -c 'CC_CAP_ZPRINT=/nonexistent/zprint; '"$(sed -n '/^read_segments() {/,/^}/p' "$A")"'
               read_segments'
  [ "$status" -ne 0 ]
}

@test "read_segments parses a well-formed row: inuse is column 7" {
  local stub="$D/bin2"; mkdir -p "$stub"
  printf '#!/bin/bash\necho "compressor_segment 184 0K 0K 0 0 814807 0K 0"\n' > "$stub/zprint"
  chmod +x "$stub/zprint"
  run bash -c 'CC_CAP_ZPRINT='"$stub"'/zprint; '"$(sed -n '/^read_segments() {/,/^}/p' "$A")"'
               read_segments'
  [ "$status" -eq 0 ]
  [[ "$output" == 814807\ * ]] || false
}

@test "the in-script selftest is GREEN and reports 5 rungs" {
  run env CC_CAP_SELFTEST=1 bash "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"selftest GREEN (5 rungs"* ]] || false
  [[ "$output" != *"control FAIL"* ]] || false
}
