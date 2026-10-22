#!/usr/bin/env bats
# scripts/kalloc-slo.sh — the #! leak-rate SLO (plan KALLOC_TRIGGER_ELIMINATION_2026-10-22 W5,
# docs/research/kalloc-longterm-2026-10-21/REPORT.md §3 Phase 5).
#
# What this suite pins:
#   1. under the target at an unchanged per-call rate: verdict=ok, the 7-day median per boot-day, no row;
#   2. a 24-h slope above 0.45 GiB/day breaches and files ONE needs-human row carrying the census command;
#   3. a slope under 0.45 still breaches when growth per Bash call is > 1.5x the previous boot's;
#   4. a boot too young for a 24-h fit, or an unreadable series, ABSTAINS: exit 3, never ok, no row;
#   5. dedupe: a second breach while the row is open, or within the re-file window after it closed,
#      files nothing; past the window it files again;
#   6. inside the damping interval it re-prints the last verdict and evaluates nothing.
# Hermetic: series and Bash log are fixtures, cc-backlog is a stub that logs its argv. Every run is
# `/bin/bash <script>` — macOS's bash 3.2, the interpreter capacity-alarm's launchd tick uses.
# `|| false` on every non-final [[ ]] — errexit-exempt assertions are dead.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  S="$REPO/scripts/kalloc-slo.sh"
  D="$BATS_TEST_TMPDIR"
  NOW=1800000000
  BOOT=$((NOW - 3 * 86400))
  mkdir -p "$D/bin"
  # cc-backlog stub: logs argv; `needs` mints a fixed id; `list` prints the fixture ledger.
  # shellcheck disable=SC2016  # the stub's own $1/$*, not ours
  printf '#!/bin/bash\necho "$*" >> %q\ncase "$1" in needs) echo abcdef012345 ;; list) cat %q 2>/dev/null || echo "[]" ;; esac\n' \
    "$D/backlog.calls" "$D/ledger.json" > "$D/bin/cc-backlog"
  chmod +x "$D/bin/cc-backlog"
  export CC_KALLOC_SLO_BACKLOG="$D/bin/cc-backlog" CC_KALLOC_SLO_LOG="$D/slo.log"
}

# series PREV_GIB_DAY CUR_GIB_DAY [CUR_HOURS] — a row every 900 s: the previous boot for 3 days up to
# BOOT, then this boot from BOOT for CUR_HOURS (default to NOW). Each boot starts at 0.08 GiB.
series() {
  awk -v b="$BOOT" -v n="$NOW" -v rp="$1" -v rc="$2" -v ch="${3:-}" 'BEGIN {
    end = (ch == "") ? n : b + ch * 3600
    for (t = b - 3 * 86400; t < b - 300; t += 900) printf "%d %.0f\n", t, (0.08 + (t - b + 3 * 86400) / 86400 * rp) * 1073741824
    for (t = b + 300; t <= end; t += 900) printf "%d %.0f\n", t, (0.08 + (t - b) / 86400 * rc) * 1073741824 }' > "$D/series.tsv"
}
# calls FROM TO EVERY — one "[ISO] [sid] cmd" Bash-log line per EVERY seconds in [FROM, TO)
calls() {
  /usr/bin/perl -e 'use POSIX "strftime"; for ($t = $ARGV[0]; $t < $ARGV[1]; $t += $ARGV[2]) {
    print strftime("[%Y-%m-%dT%H:%M:%SZ]", gmtime $t), " [sid] true\n" }' "$@"
}
slo() { # [extra args] — one forced evaluation at NOW
  run /bin/bash "$S" --force --now "$NOW" --boot "$BOOT" --series "$D/series.tsv" --bash-log "$D/bash.log" \
    --state "$D/slo.state" "$@"
}
needs_count() { if [ -f "$D/backlog.calls" ]; then grep -c '^needs ' "$D/backlog.calls"; else echo 0; fi; }

@test "under target at an unchanged per-call rate: ok, median of the 7 boot-days, no row" {
  series 0.30 0.20
  calls $((BOOT - 3 * 86400)) $((NOW + 1)) 60 > "$D/bash.log"
  slo
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=ok "* ]] || false
  [[ "$output" == *"24 h slope 0.200 GiB/day"* ]] || false
  # 3 days at 0.20 from this boot, 3 at 0.30 from the last; the 7th day has no rows.
  [[ "$output" == *"target 7-day median 0.250 GiB/day over 6 day(s): met"* ]] || false
  [ "$(needs_count)" = 0 ] || false
  run grep -c '^verdict=ok$' "$D/slo.state"
  [ "$output" = 1 ]
}

@test "a 24-h slope above 0.45 GiB/day breaches and files one needs-human row with the census command" {
  series 0.30 0.60
  # Twice the zone rate on twice the Bash calls: per-call growth is flat, so only the slope leg fires.
  { calls $((BOOT - 3 * 86400)) "$BOOT" 60; calls "$BOOT" $((NOW + 1)) 30; } > "$D/bash.log"
  slo
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"verdict=breach (24 h slope 0.600 GiB/day > 0.45) "* ]] || false
  [[ "$output" == *"ratio 1.00 "* ]] || false
  [[ "$output" == *"operator row: new row abcdef012345"* ]] || false
  [ "$(needs_count)" = 1 ] || false
  run grep '^needs ' "$D/backlog.calls"
  [[ "$output" == *"--class needs-human --run bash $REPO/scripts/kalloc-exec-census.sh 600 --project claude-infrastructure"* ]] || false
  run grep -c '^filed_id=abcdef012345$' "$D/slo.state"
  [ "$output" = 1 ]
}

@test "a slope under 0.45 still breaches when growth per Bash call is over 1.5x the previous boot's" {
  series 0.40 0.40
  # Same zone rate, half the Bash calls this boot: each call now leaks twice as much.
  { calls $((BOOT - 3 * 86400)) "$BOOT" 30; calls "$BOOT" $((NOW + 1)) 60; } > "$D/bash.log"
  slo
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"verdict=breach (growth per Bash call 2.00x the previous boot's > 1.5x)"* ]] || false
  [ "$(needs_count)" = 1 ]
}

@test "the same rates at equal call volume read ok: the per-call leg is what moved" {
  series 0.40 0.40
  calls $((BOOT - 3 * 86400)) $((NOW + 1)) 60 > "$D/bash.log"
  slo
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"ratio 1.00 "* ]]
}

@test "a boot too young for a 24-h fit abstains: exit 3, not ok, no row — even at a breaching slope" {
  series 0.30 0.90 10
  BOOT_NOW=$((BOOT + 10 * 3600))
  calls $((BOOT - 3 * 86400)) $((BOOT_NOW + 1)) 60 > "$D/bash.log"
  NOW="$BOOT_NOW" slo
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"verdict=abstain (series too short: this boot's 24 h fit has "* ]] || false
  [[ "$output" != *"verdict=ok"* ]] || false
  [ "$(needs_count)" = 0 ] || false
  run grep -c '^verdict=abstain$' "$D/slo.state"
  [ "$output" = 1 ]
}

@test "an unreadable series abstains and says so" {
  slo --series "$D/missing.tsv"
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"verdict=abstain (zone series unreadable: $D/missing.tsv)"* ]] || false
  [ "$(needs_count)" = 0 ]
}

@test "dedupe: no second row while it is open or inside the re-file window; one more after it" {
  series 0.30 0.60
  calls $((BOOT - 3 * 86400)) $((NOW + 1)) 60 > "$D/bash.log"
  slo
  [ "$(needs_count)" = 1 ] || false
  printf '[{"id":"abcdef012345","status":"blocked"}]\n' > "$D/ledger.json"
  slo
  [ "$status" -eq 1 ] || false
  [[ "$output" == *"operator row: dup (row abcdef012345 still open)"* ]] || false
  [ "$(needs_count)" = 1 ] || false
  # The operator ran the census and the row closed; the slope has not come down yet.
  printf '[{"id":"abcdef012345","status":"done"}]\n' > "$D/ledger.json"
  NOW=$((NOW + 3600)) slo
  [[ "$output" == *"operator row: not filed (row abcdef012345 is closed, filed 1 h ago; re-file after 7 d)"* ]] || false
  [ "$(needs_count)" = 1 ] || false
  CC_KALLOC_SLO_REFILE_S=1800 NOW=$((NOW + 3600)) slo
  [[ "$output" == *"operator row: new row abcdef012345"* ]] || false
  [ "$(needs_count)" = 2 ]
}

@test "inside the damping interval it re-prints the last verdict and evaluates nothing" {
  series 0.30 0.60
  calls $((BOOT - 3 * 86400)) $((NOW + 1)) 60 > "$D/bash.log"
  slo
  [ "$(needs_count)" = 1 ] || false
  : > "$D/backlog.calls"
  run /bin/bash "$S" --now $((NOW + 600)) --boot "$BOOT" --series "$D/series.tsv" --bash-log "$D/bash.log" --state "$D/slo.state"
  [ "$status" -eq 0 ] || false
  [ "$output" = "kalloc-slo: damped verdict=breach age=600s" ] || false
  [ ! -s "$D/backlog.calls" ]
}
