#!/usr/bin/env bats
# kalloc-leak-rate.sh: data.kalloc.1024 growth before vs after a cutover, raw and per Bash tool call.
# docs/research/panic-2026-10-18-zone-map-shebang-leak.md § Post-0070 fleet measurement.
#
# What this suite pins:
#   1. a slower zone after the cutover at equal activity reads `reduced` with the right ratio;
#   2. the verdict is per Bash call: the same raw rate on a 4x busier fleet is `reduced`, at equal
#      activity `unchanged` — the raw rate alone would call both the same;
#   3. a side whose zone fit spans < 90% of the window is `insufficient`, exit 1, never a verdict;
#   4. the before side's calls are counted from a rotated .gz sibling, not only the live log.
# `|| false` on every non-final [[ ]] — errexit-exempt assertions are dead.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  S="$REPO/scripts/kalloc-leak-rate.sh"
  D="$BATS_TEST_TMPDIR"
  T0=1800000000
}

# series BEFORE_ELEM_S AFTER_ELEM_S [AFTER_HOURS] — a row every 900 s, 24 h before T0 and AFTER_HOURS after
series() {
  awk -v t0="$T0" -v rb="$1" -v ra="$2" -v ah="${3:-24}" 'BEGIN {
    for (t = t0 - 86400; t < t0 + ah*3600; t += 900) {
      e = (t < t0) ? (t - t0 + 86400) * rb : 86400 * rb + (t - t0) * ra
      printf "%d %d\n", t, 1000000000 + e * 1024 } }' > "$D/series.tsv"
}

# calls FROM TO EVERY — one "[ISO] [sid] cmd" line per EVERY seconds in [FROM, TO)
calls() {
  /usr/bin/perl -e 'use POSIX "strftime"; for ($t = $ARGV[0]; $t < $ARGV[1]; $t += $ARGV[2]) {
    print strftime("[%Y-%m-%dT%H:%M:%SZ]", gmtime $t), " [sid] true\n" }' "$@"
}

@test "slower zone at equal activity reads reduced, ratio 0.25" {
  series 20 5
  calls $((T0 - 86400)) $((T0 + 86400)) 60 > "$D/bash.log"
  run "$S" --cutover "$T0" --series "$D/series.tsv" --bash-log "$D/bash.log"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=reduced ratio=0.25"* ]]
}

@test "the verdict is per Bash call: a 4x busier fleet at the same raw rate is reduced, equal is unchanged" {
  series 20 20
  { calls $((T0 - 86400)) "$T0" 60; calls "$T0" $((T0 + 86400)) 15; } > "$D/bash.log"
  run "$S" --cutover "$T0" --series "$D/series.tsv" --bash-log "$D/bash.log"
  [[ "$output" == *"verdict=reduced ratio=0.25"* ]] || false
  calls $((T0 - 86400)) $((T0 + 86400)) 60 > "$D/bash.log"
  run "$S" --cutover "$T0" --series "$D/series.tsv" --bash-log "$D/bash.log"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=unchanged ratio=1.00"* ]]
}

@test "an after side spanning under 90% of the window is insufficient, exit 1" {
  series 20 5 20
  calls $((T0 - 86400)) $((T0 + 86400)) 60 > "$D/bash.log"
  run "$S" --cutover "$T0" --series "$D/series.tsv" --bash-log "$D/bash.log"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"verdict=insufficient"* ]] || false
  [[ "$output" != *"verdict=reduced"* ]]
}

@test "before-side calls are read from the rotated .gz sibling" {
  series 20 5
  calls $((T0 - 86400)) "$T0" 60 | /usr/bin/gzip -c > "$D/bash.log.$(date -u -r "$T0" +%Y%m%dT%H%M%SZ).gz"
  calls "$T0" $((T0 + 86400)) 60 > "$D/bash.log"
  run "$S" --cutover "$T0" --series "$D/series.tsv" --bash-log "$D/bash.log"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=reduced ratio=0.25"* ]]
}

# --span (plan KALLOC_TRIGGER_ELIMINATION W5): one side only, the per-call figure kalloc-slo.sh compares
# across boots. 20 elem/s over the 85,500 s the rows span, 1,426 calls inside it: 1199.16 per call.
@test "--span prints one side's per-call growth; a span under 90% of --window is insufficient" {
  series 20 5
  calls $((T0 - 86400)) $((T0 + 86400)) 60 > "$D/bash.log"
  run "$S" --span $((T0 - 86400)) "$T0" --series "$D/series.tsv" --bash-log "$D/bash.log"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"per_call=1199.1"* ]] || false
  run "$S" --span $((T0 - 43200)) "$T0" --series "$D/series.tsv" --bash-log "$D/bash.log"
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"verdict=insufficient"* ]] || false
  run "$S" --span $((T0 - 43200)) "$T0" --window 43200 --series "$D/series.tsv" --bash-log "$D/bash.log"
  [ "$status" -eq 0 ] || false
  run "$S" --span "$T0"
  [ "$status" -eq 2 ]
}
