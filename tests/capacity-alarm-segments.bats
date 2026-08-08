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
# EVERY threshold classify() reads must be declared below, at the SHIPPED default. That list is a
# second copy of the subject's own defaults block, and it fails in a shape that does not name itself:
# an undeclared threshold makes `[ "$pl" -ge "" ]` emit "integer expression expected" on stderr, bats
# folds stderr into $output, and the probe then fails on a STRING COMPARISON while the verdict it
# computed was correct all along. The two PRESSURE_ entries arrived late, with the commit that gave
# rung 3 the floor seam every other rung already had, and four probes here went red for a rung none
# of them tests. NOTE the body is a SINGLE-QUOTED bash -c string: no apostrophes may appear inside it
# (one closes the quote and the whole suite reports zero tests rather than a syntax error).
run_classify() { # <script> <args...>
  local script="$1"; shift
  bash -c '
    WARN_GB=8; ALARM_GB=3; PROC_WARN_GB=3; SEG_WARN_PCT=45; SEG_ALARM_PCT=70
    SWAP_DELTA_MB=256; SWAP_WINDOW_S=600; COAL_WARN=500; COAL_ALARM=700
    LOAD_WARN_PER_CORE=1.5; LOAD_ALARM_PER_CORE=2.5
    PRESSURE_WARN=2; PRESSURE_ALARM=4
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

# ── read_segments under the 2026-08-05 D2 contract: est lane is PRIMARY, zprint is opt-in ─────────
# The extraction runs with a stub-only PATH so neither lane can touch the live machine — the old
# suite stubbed zprint alone, which was hermetic only while zprint was the only source.

mk_seg_stubs() { # <dir> [swap_used] — writes stub vm_stat + sysctl; caller may add zprint/timeout
  mkdir -p "$1"
  printf '#!/bin/bash\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Pages occupied by compressor:                       400."\n' > "$1/vm_stat"
  printf '#!/bin/bash\ncase "$2" in\n  vm.compressor_segment_limit) echo 1629615 ;;\n  vm.swapusage) echo "vm.swapusage: total = 4096.00M  used = %s  free = 4032.00M  (encrypted)" ;;\n  *) exit 1 ;;\nesac\n' "${2:-64.00M}" > "$1/sysctl"
  chmod +x "$1/vm_stat" "$1/sysctl"
}

run_read_segments() { # <script> <stubdir> [env...]
  local script="$1" stub="$2"; shift 2
  # SYSCTL is injected EXPLICITLY, not left to the stub-only PATH. Since 2026-08-08 read_segments
  # resolves sysctl absolutely (/usr/sbin/sysctl), so a PATH stub alone is simply bypassed and the
  # extraction would read the LIVE machine — the exact non-hermeticity this helper exists to prevent,
  # and it would fail silently, as a suite that passes on an idle box and flakes on a busy one.
  # vm_stat is still reached through PATH; only the sysctl half moved. Caller env comes after, so a
  # test can still override SYSCTL itself.
  run env PATH="$stub:/usr/bin:/bin" SYSCTL="$stub/sysctl" "$@" bash -c "$(sed -n '/^read_segments() {/,/^}/p' "$script")"'
               read_segments'
}

@test "read_segments refuses to invent a number when BOTH lanes are unreadable" {
  # Broken sysctl kills the limit read; broken vm_stat kills the est lane. Each must fail (non-zero,
  # no output) rather than print a value that would render as a healthy 0.0%.
  local stub="$D/bin"; mkdir -p "$stub"
  printf '#!/bin/bash\nexit 1\n' > "$stub/sysctl"; chmod +x "$stub/sysctl"
  printf '#!/bin/bash\nexit 1\n' > "$stub/vm_stat"; chmod +x "$stub/vm_stat"
  run_read_segments "$A" "$stub"
  [ "$status" -ne 0 ]
  [ -z "$output" ]

  # Limit readable, vm_stat broken — the est lane must still refuse.
  mk_seg_stubs "$stub"
  printf '#!/bin/bash\nexit 1\n' > "$stub/vm_stat"; chmod +x "$stub/vm_stat"
  run_read_segments "$A" "$stub"
  [ "$status" -ne 0 ]

  # vm_stat readable, swapusage unparsable — half an estimate is not an estimate.
  mk_seg_stubs "$stub"
  printf '#!/bin/bash\ncase "$2" in\n  vm.compressor_segment_limit) echo 1629615 ;;\n  *) echo "garbage" ;;\nesac\n' > "$stub/sysctl"
  chmod +x "$stub/sysctl"
  run_read_segments "$A" "$stub"
  [ "$status" -ne 0 ]
}

@test "read_segments est lane: in-core (pages×pgsz/64KiB) + swapped (used/64KiB), source tagged est" {
  # 400 pages × 16384 B = 100 in-core segments; 64.00M used = 1024 swapped segments; sum 1124.
  # The swapped term is why the estimate matches the kernel's own accounting — the segment limit
  # counts swapped-out descriptors too (xnu vm_compressor.c:595, panic-compressor-2026-08-05.md §4a).
  local stub="$D/bin2"; mk_seg_stubs "$stub"
  run_read_segments "$A" "$stub"
  [ "$status" -eq 0 ]
  [ "$output" = "1124 1629615 est" ]
}

@test "read_segments zprint lane is opt-in, timeout-wrapped, and falls through to est on failure" {
  # Opt-in + healthy: column 7 through a stub timeout that must be present (an unwrapped zprint is
  # the exact hang D2 removes).
  local stub="$D/bin3"; mk_seg_stubs "$stub"
  printf '#!/bin/bash\necho "compressor_segment 184 0K 0K 0 0 814807 0K 0"\n' > "$stub/zprint"
  printf '#!/bin/bash\nshift 3; exec "$@"\n' > "$stub/timeout"   # swallows -k 1 3
  chmod +x "$stub/zprint" "$stub/timeout"
  run_read_segments "$A" "$stub" CC_CAP_SEG_SOURCE=zprint
  [ "$status" -eq 0 ]
  [ "$output" = "814807 1629615 zprint" ]

  # Opt-in + broken zprint: falls THROUGH to the estimate rather than deleting the rung — a slow
  # lane that takes the rung down when it stalls would be strictly worse than not having it.
  printf '#!/bin/bash\necho "zone name a b c d e f g h"\n' > "$stub/zprint"; chmod +x "$stub/zprint"
  run_read_segments "$A" "$stub" CC_CAP_SEG_SOURCE=zprint
  [ "$status" -eq 0 ]
  [ "$output" = "1124 1629615 est" ]

  # Opt-in with NO timeout binary: the slow lane is skipped entirely, never run bare.
  rm -f "$stub/timeout"
  run_read_segments "$A" "$stub" CC_CAP_SEG_SOURCE=zprint CC_CAP_TIMEOUT=/nonexistent/timeout
  [ "$status" -eq 0 ]
  [ "$output" = "1124 1629615 est" ]
}

@test "read_prior swap baseline is the WINDOW MINIMUM, not the oldest row (decay must not hide growth)" {
  # Rows: outside-window trough (50) must be excluded; in-window 300 then trough 100 — the baseline
  # is 100, so growth measured from the trough catches a burst that an oldest-row (300) baseline
  # would subtract away. D1, docs/research/panic-compressor-2026-08-05.md §5.
  local log="$D/prior.jsonl" now
  now="$(date -u +%s)"
  ts() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
  printf '{"ts":"%s","swap_used_mb":50}\n'  "$(ts $((now-900)))"  > "$log"
  printf '{"ts":"%s","swap_used_mb":300}\n' "$(ts $((now-500)))" >> "$log"
  printf '{"ts":"%s","swap_used_mb":100}\n' "$(ts $((now-200)))" >> "$log"
  run bash -c '
    LOG='"$log"'; PRIOR_ROWS=15; SWAP_WINDOW_S=600; NOW_EPOCH='"$now"'
    '"$(sed -n '/^read_prior() {/,/^}/p' "$A")"'
    read_prior'
  [ "$status" -eq 0 ]
  [[ "$output" == 100\|* ]] || false
}

@test "the in-script selftest is GREEN and reports 7 rungs" {
  # The count is asserted ON PURPOSE and is meant to go red when a rung is added: the number in the
  # GREEN line is a CLAIM about coverage, and a claim that updates itself proves nothing. 6 → 7 on
  # 2026-08-05 when rung 7 (scheduler saturation, D4) landed.
  run env CC_CAP_SELFTEST=1 bash "$A"
  [ "$status" -eq 0 ]
  [[ "$output" == *"selftest GREEN (7 rungs"* ]] || false
  [[ "$output" != *"control FAIL"* ]] || false
}

# Rung 6 (the 2026-07-31 panic). That box died with 1002 procs in ONE terminal coalition while
# every other rung read healthy 20 minutes earlier. This asserts the same shape as the rung-5 pair
# above, in BOTH directions: the fatal sample must ALARM, and the highest HEALTHY sample of the
# 38-sample series the threshold was derived from (353) must stay OK. That second row IS the
# no-false-positive claim, executable — it goes RED if anyone retunes COAL_WARN down without
# re-deriving the denominator. See docs/research/panic-iterm2-coalition-2026-07-31.md §7.
#
# MATCHED LINE-WISE, not with `[[ $output == *…*…* ]]`. In a `[[ ]]` glob the `*` spans NEWLINES, so
# `*"coal='1002'"*"→ ALARM"*` would happily match the coal on one probe line and the verdict on a
# LATER one — a match that agrees only with its own fixture (memory lookup-miss-is-not-absence).
# grep anchors the whole claim inside ONE line, and it also survives a rung 8 appending a field,
# which is what broke these three assertions when rung 7 appended `load='…'` after `coal='…'`.
@test "rung 6: the fatal 1002-proc coalition ALARMs, the healthy 353 max stays OK" {
  run env CC_CAP_SELFTEST=1 bash "$A"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE "coal='1002'.* → ALARM$" || false
  printf '%s\n' "$output" | grep -qE "coal='353'.* → OK$"     || false
}

# An unreadable process table must SKIP rung 6, never report a healthy 0 — rung 3's standing policy,
# and the same failure the 2026-07-30 zprint control pins for rung 5.
@test "rung 6: an unreadable coalition count is SKIPPED, never a fabricated healthy 0" {
  run env CC_CAP_SELFTEST=1 bash "$A"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE "coal='\?'.* → OK$" || false
  run env CC_CAP_PS=/nonexistent/ps bash "$A" --no-append
  [[ "$output" == *"SKIPPED (ps unreadable)"* ]] || false
  [[ "$output" != *"0 procs in"* ]] || false
}
