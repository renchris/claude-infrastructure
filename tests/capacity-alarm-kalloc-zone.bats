#!/usr/bin/env bats
# capacity-alarm's kalloc ZONE page: the ceiling, the tiers, the carry, the kernel's osr_code 9 line,
# its own notification, and the readout line that names it.
# docs/research/panic-2026-10-18-zone-map-shebang-leak.md § Answer 4-6, improvements 5-6, 9.
#
# The zone read ALARM for 12 days to the 2026-10-18 panic and nothing acted. What this suite pins:
#   1. the page's ceiling is the measured 20,955,520 elements (~19.98 GiB), not panic #5's 9.89 GB;
#   2. tiers at 50/70/85% of it, each with the level, the TRAILING-3-day slope and the ETA;
#   3. a SKIPPED/timed-out read carries this boot's last value at any age — the page stays up;
#   4. the first `killing_idle_process … osr_code: 9` kernel line pages, once, bounded scan;
#   5. a named notification per tier crossing and daily, posted by the alarm itself, never in pages/;
#   6. the readout names the zone on its own line, outside the escalation count.
# Fixtures reach the regime: a 3-day series ending at 19 GiB, 95% of the ceiling.
# RED-proof: tests 1-10 fail against the pre-change script (git show 36afca47f:scripts/capacity-alarm.sh):
#   no kalloc-zone.page/state is written, the carry expires at 4×900 s, no log(1) scan runs.
# `|| false` on every non-final [[ ]]/[ ] — errexit-exempt assertions are dead.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs" "$HOME/.claude/autonomy/pages"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  A="$REPO/scripts/capacity-alarm.sh"
  D="$BATS_TEST_TMPDIR"
  Z="$HOME/.claude/autonomy"
  SERIES="$HOME/.claude/logs/kalloc-zone-series.tsv"
  export CC_CAP_LOG="$D/cap.jsonl"
  export CC_PAGES_DIR="$Z/pages"
  # Every acute rung pinned neutral (capacity-alarm-chronic.bats setup(), same reason).
  export CC_CAP_LOAD_WARN_PER_CORE=9999 CC_CAP_LOAD_ALARM_PER_CORE=9999
  export CC_CAP_WARN_GB=0 CC_CAP_ALARM_GB=0
  export CC_CAP_PRESSURE_WARN=9999 CC_CAP_PRESSURE_ALARM=9999
  export CC_CAP_PROC_WARN_GB=999999
  export CC_CAP_SEG_WARN_PCT=999999 CC_CAP_SEG_ALARM_PCT=999999
  export CC_CAP_COAL_WARN=999999 CC_CAP_COAL_ALARM=999999
  export CC_CAP_SWAP_DELTA_MB=999999
  export CC_CAP_COAL_FP=0 CC_CAP_AUTO_COAL=0
  export CC_CAP_OSR9=off CC_CAP_ZONE_NOTIFY=off CC_CAP_CONVOY=off
  # The pages name alarm-reboot-prep.sh; were anything to run it, it must not reach the live cc-sessions.
  export CC_REBOOT_PREP_SESSIONS="$BATS_TEST_TMPDIR/no-cc-sessions"
  export CC_REBOOT_PREP_CLAUDE_TMP="$BATS_TEST_TMPDIR/no-claude-tmp"
  export CC_REBOOT_PREP_KITTY_SOCK_PREFIX="$BATS_TEST_TMPDIR/no-kitty-"
  export CC_REBOOT_PREP_SOCKS_DIR="$BATS_TEST_TMPDIR/no-cc-socks"
  NOW="$(date -u +%s)"
  BOOT=$((NOW - 4 * 86400))
  export CC_CAP_BOOTTIME="$BOOT"
  mkdir -p "$D/bin"
}

GIB=1073741824
mk_zprint() { # <GiB> [sleep seconds] — a zprint stub in the real output shape; counts its calls
  local inuse; inuse="$(awk -v g="$1" 'BEGIN{printf "%.0f", g * 1048576}')"
  {
    printf '#!/bin/bash\necho x >> "%s"\n' "$D/zprint.calls"
    [ -n "${2:-}" ] && printf 'exec /bin/sleep %s\n' "$2"
    printf 'echo "data.kalloc.1024            1024          0K          0K          0           0    %s     0K      0"\n' "$inuse"
  } > "$D/bin/zprint"
  chmod +x "$D/bin/zprint"
  export CC_CAP_ZPRINT="$D/bin/zprint"
}
seed_series() { # <end GiB> <GiB/day> — 7 measured samples, 12 h apart, inside the trailing 3 days
  local i e
  : > "$SERIES"
  for i in 0 1 2 3 4 5 6; do
    e=$((NOW - 30 - (6 - i) * 43190))
    awk -v e="$e" -v g="$1" -v r="$2" -v i="$i" -v G="$GIB" 'BEGIN{printf "%d %.0f\n", e, (g - r * (6 - i) * 0.5) * G}' >> "$SERIES"
  done
}
mk_osa() { # [exit code] — records "<title>|<message>" per post
  printf '#!/bin/bash\ncat >/dev/null\nprintf "%%s|%%s\\n" "$2" "$3" >> "%s"\nexit %s\n' "$D/osa.log" "${1:-0}" > "$D/bin/osascript"
  chmod +x "$D/bin/osascript"
  export CC_CAP_OSASCRIPT="$D/bin/osascript" CC_CAP_ZONE_NOTIFY=on
}
mk_log() { # <body file> [sleep] — log(1) stub printing the body; counts its calls
  {
    printf '#!/bin/bash\necho x >> "%s"\n' "$D/log.calls"
    [ -n "${2:-}" ] && printf 'exec /bin/sleep %s\n' "$2"
    printf 'echo "Timestamp               Ty Process[PID:TID]"\ncat "%s"\n' "$1"
  } > "$D/bin/log"
  chmod +x "$D/bin/log"
  export CC_CAP_LOGBIN="$D/bin/log"
}
osr9_line() { # <time> <pid> [code]
  printf '2026-10-18 %s Df kernel[0:8c6] [com.apple.xnu:memorystatus] memorystatus: killing_idle_process pid %s [dmd] jetsam_reason->osr_code: %s\n' "$1" "$2" "${3:-9}"
}
zs() { sed -n "s/^$1=//p" "$Z/kalloc-zone.state" | head -1; }
row_field() { printf '%s\n' "$output" | tail -n 1 | jq -r --arg k "$1" '.[$k] | tostring'; }
nlines() { if [ -f "$1" ]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }

@test "the page names the MEASURED ceiling — 20,955,520 elements — and never panic #5's 9.89 GB" {
  seed_series 19 1; mk_zprint 19
  run /bin/bash "$A" --quiet
  [ -f "$Z/kalloc-zone.page" ] || false
  grep -q 'panicked the box at 20955520 elements (~19.98 GiB)' "$Z/kalloc-zone.page" || false
  grep -q 'data.kalloc.1024 19.00 GiB = 95% of the ~19.98 GiB panic ceiling' "$Z/kalloc-zone.page" || false
  ! grep -q '9\.89' "$Z/kalloc-zone.page" || false
  [ "$(zs ceiling_elems)" = 20955520 ]
}

@test "tiers at 50/70/85% of the ceiling, each carrying level, trailing slope and ETA" {
  local p g want
  for p in "9.5:0" "10.5:1" "14.5:2" "17.5:3" "19:3"; do
    g="${p%%:*}"; want="${p#*:}"
    rm -f "$CC_CAP_LOG"; seed_series "$g" 1; mk_zprint "$g"
    run /bin/bash "$A" --json
    [ "$(row_field kalloc_tier)" = "$want" ] || { echo "$g GiB -> tier $(row_field kalloc_tier), want $want"; false; }
    [ "$(zs tier)" = "$want" ] || false
    [ "$(zs slope_gib_day)" = "1.00" ] || { echo "$g: slope $(zs slope_gib_day)"; false; }
    # The span is the fitted samples' own: the oldest leaves the 3-day window when one alarm run
    # takes a minute or more under load, so 2.5 d is as correct as 3.0 d here.
    [[ "$(zs slope_src)" =~ ^trailing\ (2\.[5-9]|3\.0)\ d$ ]] || { echo "$g: $(zs slope_src)"; false; }
    grep -qE "· \+1\.00 GiB/day \(trailing [0-9.]+ d\) · ceiling in ~" "$Z/kalloc-zone.page" || false
  done
  # 19 GiB at 1 GiB/day: 0.98 GiB of room ⇒ 1.0 d, dated from now.
  [ "$(zs eta_days)" = "1.0" ] || false
  [ "$(zs eta_date)" = "$(date -r $((NOW + 86400)) +%Y-%m-%d)" ] || false
  sed -n 2p "$Z/kalloc-zone.page" | grep -q "^kalloc zone tier 3 of 3 .* ceiling ETA $(zs eta_date)$"
}

@test "the slope is the TRAILING 3 days, not the since-boot mean — and the mean only stands in, labelled" {
  # 10 days up: 0.5 GiB/day for 7 days, then 3 GiB/day. A since-boot mean reads ~1.25 GiB/day and
  # puts the ceiling days late; the trailing fit must read the acceleration.
  local i e g
  export CC_CAP_BOOTTIME=$((NOW - 10 * 86400))
  : > "$SERIES"
  for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13; do      # every 12 h, days -10 .. -3.5 at 0.5/day
    e=$((NOW - 10 * 86400 + i * 43200 + 600)); g="$(awk -v i="$i" 'BEGIN{print 0.1 + i * 0.25}')"
    awk -v e="$e" -v g="$g" -v G="$GIB" 'BEGIN{printf "%d %.0f\n", e, g * G}' >> "$SERIES"
  done
  seed_series_tail() { for i in 0 1 2 3 4 5 6; do
      awk -v e=$((NOW - 60 - (6 - i) * 43200)) -v i="$i" -v G="$GIB" 'BEGIN{printf "%d %.0f\n", e, (3.6 + i * 1.5) * G}' >> "$SERIES"; done; }
  seed_series_tail
  mk_zprint 12.6
  run /bin/bash "$A" --json
  awk -v s="$(zs slope_gib_day)" 'BEGIN{exit !(s >= 2.9 && s <= 3.1)}' || { echo "slope $(zs slope_gib_day)"; false; }
  # No series at all: the since-boot mean, SAID to be one.
  rm -f "$SERIES" "$CC_CAP_LOG"
  run /bin/bash "$A" --json --no-append
  [ "$(row_field kalloc_slope_gib_day)" = "1.26" ] || { echo "mean $(row_field kalloc_slope_gib_day)"; false; }
  run /bin/bash "$A" --quiet
  [ "$(zs slope_src)" = "since-boot mean" ]
}

@test "a timed-out read 2 h after the last sample CARRIES it — the page is not retracted (was: 4×900 s expiry)" {
  seed_series 19 1
  printf '{"ts":"%s","verdict":"OK","headroom_gb":20,"swap_used_mb":0,"kalloc1024_gb":19.00,"kalloc1024_at":%s}\n' \
    "$(date -u -r $((NOW - 7200)) +%Y-%m-%dT%H:%M:%SZ)" "$((NOW - 7200))" > "$CC_CAP_LOG"
  printf '%s\nstale\n' "$NOW" > "$Z/kalloc-zone.page"
  mk_zprint 19 30
  run env CC_CAP_KALLOC_TIMEOUT_S=1 /bin/bash "$A" --json
  [ "$(nlines "$D/zprint.calls")" = 1 ] || false             # a fresh read WAS attempted, and cut
  [ "$(row_field kalloc1024_src)" = carried-after-timeout ] || { echo "src=$(row_field kalloc1024_src)"; false; }
  [ "$(row_field kalloc1024_gb)" = "19.00" ] || false
  [ "$(row_field kalloc1024_at)" = "$((NOW - 7200))" ] || false   # its own age, never claimed fresh
  [ -f "$Z/kalloc-zone.page" ] || false
  grep -q 'carried-after-timeout, read 120 min ago' "$Z/kalloc-zone.page"
}

@test "a BLANK previous row does not break the chain — the series supplies this boot's last measured value" {
  printf '%s %s\n' "$((BOOT - 600))" "$((20 * GIB))" "$((NOW - 3600))" "$((18 * GIB))" > "$SERIES"
  printf '{"ts":"%s","verdict":"OK","headroom_gb":20,"swap_used_mb":0,"kalloc1024_gb":null,"kalloc1024_at":null}\n' \
    "$(date -u -r $((NOW - 60)) +%Y-%m-%dT%H:%M:%SZ)" > "$CC_CAP_LOG"
  mk_zprint 1 30
  run env CC_CAP_KALLOC_TIMEOUT_S=1 /bin/bash "$A" --json --no-append
  [ "$(row_field kalloc1024_gb)" = "18.00" ] || { echo "gb=$(row_field kalloc1024_gb)"; false; }   # not the pre-boot 20
  [ "$(row_field kalloc1024_at)" = "$((NOW - 3600))" ] || false
  [[ "$(row_field kalloc1024_src)" == carried-after-timeout ]]
}

@test "the page retracts on a READING below the floor and on a reboot — never on a blind tick" {
  seed_series 19 1; mk_zprint 19
  export CC_CAP_KALLOC_MIN_S=0
  run /bin/bash "$A" --quiet
  [ -f "$Z/kalloc-zone.page" ] || false
  mk_zprint 19 30                                            # blind: the carry holds, so does the page
  run env CC_CAP_KALLOC_TIMEOUT_S=1 /bin/bash "$A" --quiet
  [ -f "$Z/kalloc-zone.page" ] || false
  mk_zprint 1                                                # a real reading below the 4 GiB floor
  run /bin/bash "$A" --quiet
  [ ! -f "$Z/kalloc-zone.page" ] || false
  mk_zprint 19; run /bin/bash "$A" --quiet
  [ -f "$Z/kalloc-zone.page" ] || false
  # A reboot, read blind: nothing of the old boot carries, and its page is void.
  rm -f "$CC_CAP_LOG" "$SERIES"; mk_zprint 19 30
  run env CC_CAP_BOOTTIME=$((NOW - 30)) CC_CAP_KALLOC_TIMEOUT_S=1 /bin/bash "$A" --quiet
  [ ! -f "$Z/kalloc-zone.page" ] || false
  [ "$(zs boot)" = "$((NOW - 30))" ]
}

@test "osr_code 9: the first idle-kill line pages and notifies, ONCE — overlap and lookalikes not counted" {
  mk_zprint 2; mk_osa                                        # the zone itself is below every floor
  { osr9_line 08:20:01.550 8679; osr9_line 08:20:02.570 18401
    osr9_line 08:20:03.000 777 90                            # a different code
    printf '2026-10-18 08:20:04.000 Df kernel[0:8c6] memorystatus: killing_top_process pid 5 [x] jetsam_reason->osr_code: 9\n'
  } > "$D/log.body"
  mk_log "$D/log.body"
  run env CC_CAP_OSR9=on CC_CAP_OSR9_SCAN_S=0 /bin/bash "$A" --quiet
  [ "$(zs osr9_n)" = 2 ] || { echo "osr9_n=$(zs osr9_n)"; false; }
  grep -q "^KERNEL PRE-PANIC SIGN: 2 'killing_idle_process … osr_code: 9' line(s)" "$Z/kalloc-zone.page" || false
  [ "$(nlines "$D/osa.log")" = 1 ] || false
  grep -q '^kalloc.1024 PRE-PANIC — kernel idle-kill sweep (osr_code 9)' "$D/osa.log" || false
  # The next scan re-reads the overlap: nothing new is counted and nothing re-posts.
  run env CC_CAP_OSR9=on CC_CAP_OSR9_SCAN_S=0 /bin/bash "$A" --quiet
  [ "$(zs osr9_n)" = 2 ] || false
  osr9_line 09:00:00.000 4242 >> "$D/log.body"
  run env CC_CAP_OSR9=on CC_CAP_OSR9_SCAN_S=0 /bin/bash "$A" --quiet
  [ "$(zs osr9_n)" = 3 ] || false
  [ "$(nlines "$D/osa.log")" = 1 ]
}

@test "the log scan is BOUNDED and damped — a cut scan keeps its cursor, an early tick does not scan" {
  # The stub would hold for 600 s; the bound is 1 s. Under 300 s separates the two even at load
  # ~470, where one alarm tick alone takes about a minute (a 20 s ceiling measured the load).
  mk_zprint 2; : > "$D/log.body"; mk_log "$D/log.body" 600
  local t0=$SECONDS
  run env CC_CAP_OSR9=on CC_CAP_OSR9_TIMEOUT_S=1 /bin/bash "$A" --quiet
  [ $((SECONDS - t0)) -lt 300 ] || { echo "the bound did not hold: $((SECONDS - t0))s"; false; }
  [ "$(nlines "$D/log.calls")" = 1 ] || false
  [ "$(zs osr9_scan_at)" = "$BOOT" ] || false                # not advanced past the gap it missed
  mk_log "$D/log.body"
  run env CC_CAP_OSR9=on /bin/bash "$A" --quiet
  [ "$(zs osr9_scan_at)" -ge "$NOW" ] || false
  run env CC_CAP_OSR9=on /bin/bash "$A" --quiet              # inside the 300 s damping window
  [ "$(nlines "$D/log.calls")" = 2 ]
}

@test "auto mode: a hand run never reads the live log and never banners — the page is still written" {
  seed_series 19 1; mk_zprint 19; mk_osa; mk_log /dev/null
  run env -u CC_CAP_OSR9 -u CC_CAP_ZONE_NOTIFY -u XPC_SERVICE_NAME /bin/bash "$A" --quiet
  [ -f "$Z/kalloc-zone.page" ] || false
  [ "$(nlines "$D/log.calls")" = 0 ] || false
  [ "$(nlines "$D/osa.log")" = 0 ] || false
  run env -u CC_CAP_OSR9 -u CC_CAP_ZONE_NOTIFY XPC_SERVICE_NAME=com.claude.capacity-alarm /bin/bash "$A" --quiet
  [ "$(nlines "$D/log.calls")" = 1 ] || false               # control: the launchd tick does both
  [ "$(nlines "$D/osa.log")" = 1 ]
}

@test "the notification: named, once per tier crossing, again after 24 h, retried on a failed post, never in pages/" {
  export CC_CAP_KALLOC_MIN_S=0
  seed_series 10.5 1; mk_zprint 10.5; mk_osa
  run /bin/bash "$A" --quiet
  [ "$(nlines "$D/osa.log")" = 1 ] || false
  grep -q "^kalloc.1024 zone 53% (10.50 GiB) · tier 1 · ceiling ETA $(date -r $((NOW + 820800)) +%Y-%m-%d)|data.kalloc.1024 10.50 GiB" "$D/osa.log" \
    || { cat "$D/osa.log"; false; }
  grep -q 'Reboot via: bash .*/scripts/alarm-reboot-prep.sh' "$D/osa.log" || false
  run /bin/bash "$A" --quiet                                 # same tier: silent
  [ "$(nlines "$D/osa.log")" = 1 ] || false
  seed_series 14.5 1; mk_zprint 14.5
  run /bin/bash "$A" --quiet                                 # crossing 70%
  [ "$(nlines "$D/osa.log")" = 2 ] || false
  [ "$(zs notified_reason)" = tier-2 ] || false
  sed -i '' "s/^notified_at=.*/notified_at=$((NOW - 90000))/" "$Z/kalloc-zone.state"
  run /bin/bash "$A" --quiet                                 # 25 h on: the daily re-send
  [ "$(nlines "$D/osa.log")" = 3 ] || false
  [ "$(zs notified_reason)" = daily ] || false
  seed_series 17.5 1; mk_zprint 17.5; mk_osa 1               # a post that fails is retried
  run /bin/bash "$A" --quiet
  [ "$(zs notified_tier)" = 2 ] || false
  mk_osa 0; run /bin/bash "$A" --quiet
  [ "$(zs notified_tier)" = 3 ] || false
  # Never in pages/: the sweep, cc-escalations and the readout count read only that directory.
  local f
  for f in "$Z"/pages/*kalloc*; do
    if [ -e "$f" ]; then echo "a kalloc page landed in pages/: $f"; false; fi
  done
  [ -f "$Z/kalloc-zone.page" ]
}

@test "the readout names the zone on its OWN line, with nothing else pending, outside the escalation count" {
  seed_series 19 1; mk_zprint 19
  run /bin/bash "$A" --quiet
  [ -f "$Z/kalloc-zone.page" ] || false
  export CC_OPREADOUT_STATE_DIR="$D/state" CC_IDL="$D/idl.jsonl" CC_ACTIVATION_DIR="$D/activation"
  export CC_DECISIONS_DIR="$D/decisions" CC_BACKLOG_FILE="$D/backlog.jsonl" CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export CC_ORB_BLG_CACHE_DIR="$D/blg" WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh" WRAP_TRUNK=origin/main
  export CC_SHARED_CHECKOUT="$D/none" CC_BACKLOG_KICK=off CC_BACKLOG_KICK_BIN="$D/none" CC_RESUME_DEBT_BIN=none
  export CC_HANDOFF_ALARM_DIR="$D/ha" CC_ANNOUNCE_ALARM_DIR="$D/aa" CC_COMPLETION_RECORDS_DIR="$D/cp"
  export CC_MAILBOX_DIR="$D/mb" CC_SWEEP_SEEN_DIR="$D/seen" LR_STATE_DIR="$D/lr"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off CC_BACKLOG_PROJECT_WARN=off
  mkdir -p "$CC_ACTIVATION_DIR" "$CC_DECISIONS_DIR" "$CC_HANDOFF_ALARM_DIR" "$CC_ANNOUNCE_ALARM_DIR" \
           "$CC_COMPLETION_RECORDS_DIR" "$CC_MAILBOX_DIR/dead-letter" "$CC_SWEEP_SEEN_DIR"
  : > "$CC_BACKLOG_FILE"
  run "$REPO/hooks/operator-readout.sh" --render --cwd "$D"
  [ "$status" -eq 0 ] || false
  printf '%s\n' "$output" | grep -q '^ ⚠ data.kalloc.1024 19.00 GiB = 95% of the ~19.98 GiB panic ceiling .* reboot via: bash ~/.claude/scripts/alarm-reboot-prep.sh$' \
    || { printf '%s\n' "$output"; false; }
  [[ "$output" != *"escalation record(s)"* ]] || false
  rm -f "$Z/kalloc-zone.page"                                # control: no page, no line
  run "$REPO/hooks/operator-readout.sh" --render --cwd "$D"
  [[ "$output" != *"data.kalloc.1024"* ]]
}

# Plan KALLOC_TRIGGER_ELIMINATION W5: the leak-rate SLO rides this job's tick; its logic is
# tests/kalloc-slo.bats. Here: who calls it, with what, the kill switch, and the report line.
@test "the SLO tick runs kalloc-slo.sh on the launchd tick only, with this boot and series; the report shows its stored line" {
  seed_series 19 1; mk_zprint 19
  # shellcheck disable=SC2016  # the stub's own $*
  printf '#!/bin/bash\necho "$*" >> "%s"\n' "$D/slo.calls" > "$D/bin/slo"
  export CC_CAP_KALLOC_SLO_SCRIPT="$D/bin/slo"
  run env -u CC_CAP_KALLOC_SLO -u XPC_SERVICE_NAME /bin/bash "$A" --quiet
  [ ! -e "$D/slo.calls" ] || false                           # auto: a hand run never ticks it
  run env -u CC_CAP_KALLOC_SLO XPC_SERVICE_NAME=com.claude.capacity-alarm /bin/bash "$A" --quiet
  run cat "$D/slo.calls"
  [[ "$output" == "--now "*" --boot $BOOT --series $SERIES --state $Z/kalloc-slo.state" ]] || false
  run env CC_CAP_KALLOC_SLO=off XPC_SERVICE_NAME=com.claude.capacity-alarm /bin/bash "$A" --quiet
  [ "$(nlines "$D/slo.calls")" = 1 ] || false                # the kill switch holds on the launchd tick
  run /bin/bash "$A" --no-append
  [[ "$output" == *"kalloc #! leak SLO:     not evaluated yet"* ]] || false
  printf 'at=%s\nline=verdict=ok · fixture\n' "$NOW" > "$Z/kalloc-slo.state"
  run /bin/bash "$A" --no-append
  [[ "$output" == *"kalloc #! leak SLO:     verdict=ok · fixture · "*" min ago"* ]]
}
