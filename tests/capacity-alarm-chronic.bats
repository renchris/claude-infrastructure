#!/usr/bin/env bats
# capacity-alarm rung 8 — the CHRONIC ratchets: swapfile count + kernel zone data.kalloc.1024.
# cc-backlog a216d8753946 · scripts/capacity-alarm.sh D5 · docs/research/panic-2026-08-24-fifth-watchdog.md
#
# Panic #5 died on day 10.9 of one boot holding 73 swapfiles and 9.89 GB in data.kalloc.1024 — two
# LEVELS that ratchet for days and that no acute rung can see. What this suite pins, in order:
#   1. the pre-rung-8 ladder cannot name that state at all (a control replayed from git);
#   2. the ratchets page but NEVER raise the verdict (a level only a reboot clears would latch it for
#      weeks — D1 of the same file);
#   3. neither instrument reports a made-up 0 — including the item's own path, /private/var/vm,
#      which holds 0 swapfiles on this macOS while the kernel reports swap;
#   4. the zone read is damped, bounded without coreutils, skipped under a storm, and never carried
#      across a reboot.
# `|| false` on every non-final [[ ]]/[ ] — errexit-exempt assertions are dead.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs" "$HOME/.claude/autonomy/pages"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  A="$REPO/scripts/capacity-alarm.sh"
  D="$BATS_TEST_TMPDIR"
  export CC_CAP_LOG="$D/cap.jsonl"
  export CC_PAGES_DIR="$HOME/.claude/autonomy/pages"
  # Every ACUTE rung pinned neutral (capacity-alarm.bats setup(), same reason): the verdict is a max
  # over live readings, and several assertions here need it OK to prove rung 8 did not move it. The
  # high pressure/segment floors also keep the storm-skip out of every test that does not own it.
  export CC_CAP_LOAD_WARN_PER_CORE=9999 CC_CAP_LOAD_ALARM_PER_CORE=9999
  export CC_CAP_WARN_GB=0 CC_CAP_ALARM_GB=0
  export CC_CAP_PRESSURE_WARN=9999 CC_CAP_PRESSURE_ALARM=9999
  export CC_CAP_PROC_WARN_GB=999999
  export CC_CAP_SEG_WARN_PCT=999999 CC_CAP_SEG_ALARM_PCT=999999
  export CC_CAP_COAL_WARN=999999 CC_CAP_COAL_ALARM=999999
  export CC_CAP_SWAP_DELTA_MB=999999
  # The two footprint(1) samples cost seconds each and are not under test here.
  export CC_CAP_COAL_FP=0 CC_CAP_AUTO_COAL=0
  UNPIN=( -u CC_CAP_LOAD_WARN_PER_CORE -u CC_CAP_LOAD_ALARM_PER_CORE -u CC_CAP_WARN_GB
          -u CC_CAP_ALARM_GB -u CC_CAP_PRESSURE_WARN -u CC_CAP_PRESSURE_ALARM -u CC_CAP_PROC_WARN_GB
          -u CC_CAP_SEG_WARN_PCT -u CC_CAP_SEG_ALARM_PCT -u CC_CAP_COAL_WARN -u CC_CAP_COAL_ALARM
          -u CC_CAP_SWAP_DELTA_MB )
  # Hermetic boot epoch: three days up. The test that owns the reboot guard overrides it.
  CC_CAP_BOOTTIME=$(( $(date -u +%s) - 3 * 86400 ))
  export CC_CAP_BOOTTIME
}

# classify() alone, every threshold at its SHIPPED default. Single-quoted bash -c body: no
# apostrophes may appear inside it (one closes the quote and the suite reports zero tests).
run_classify() { # <script> <args...>
  local script="$1"; shift
  bash -c '
    WARN_GB=8; ALARM_GB=3; PROC_WARN_GB=3; SEG_WARN_PCT=45; SEG_ALARM_PCT=70
    SWAP_DELTA_MB=256; SWAP_WINDOW_S=600; COAL_WARN=500; COAL_ALARM=700
    LOAD_WARN_PER_CORE=1.5; LOAD_ALARM_PER_CORE=2.5; PRESSURE_WARN=2; PRESSURE_ALARM=4
    SWAPFILE_WARN=12; SWAPFILE_ALARM=20; KALLOC_WARN_GB=4; KALLOC_ALARM_GB=6
    '"$(sed -n '/^classify() {/,/^}/p' "$script")"'
    CC_CAP_RUNG_DETAIL=1 classify "$@"
  ' _ "$@"
}

# A zprint stub in the real output shape, with a DECOY zone first so the parser must match exactly.
# It counts its own invocations, which is how "the zone map was not walked" is asserted rather than
# assumed. With a sleep it EXECs, so the pid the bound kills is the one holding the time.
mk_zprint() { # <cur inuse> [sleep seconds]
  mkdir -p "$D/bin"
  {
    printf '#!/bin/bash\n'
    printf 'echo x >> "%s"\n' "$D/zprint.calls"
    if [ -n "${2:-}" ]; then printf 'exec /bin/sleep %s\n' "$2"; fi
    printf 'cat <<ROW\n'
    printf 'zone name                   size        size        size      #elts       #elts       inuse   size  count\n'
    printf 'data.kalloc.512              512          0K          0K          0           0    99999999     0K      0\n'
    printf 'data.kalloc.1024            1024          0K          0K          0           0    %s     0K      0\n' "$1"
    printf 'ROW\n'
  } > "$D/bin/zprint"
  chmod +x "$D/bin/zprint"
  export CC_CAP_ZPRINT="$D/bin/zprint"
}

mk_swapdir() { # <n> — n files under a private prefix, and point the rung at it
  mkdir -p "$D/vm"
  local i=0
  while [ "$i" -lt "$1" ]; do : > "$D/vm/swapfile$i"; i=$((i + 1)); done
  export CC_CAP_SWAPFILE_PREFIX="$D/vm/swapfile"
}

mk_sysctl_swaptotal() { # <total MB> — vm.swapusage stubbed; every other key reaches the real sysctl
  mkdir -p "$D/bin"
  cat > "$D/bin/sysctl" <<SC
#!/bin/bash
case "\$*" in
  *vm.swapusage*) echo 'total = $1M  used = 0.00M  free = $1M  (encrypted)' ;;
  *)              exec /usr/sbin/sysctl "\$@" ;;
esac
SC
  chmod +x "$D/bin/sysctl"
  export CC_CAP_SYSCTL="$D/bin/sysctl"
}

row_field() { # <key> — from the LAST line of $output (the --json row); jq also proves it parses
  printf '%s\n' "$output" | tail -n 1 | jq -r --arg k "$1" '.[$k] | tostring'
}

calls() { if [ -f "$D/zprint.calls" ]; then wc -l < "$D/zprint.calls" | tr -d ' '; else echo 0; fi; }

@test "RED-PROOF: the pre-rung-8 classify cannot see panic #5's chronic state at all" {
  # The newest commit of the script whose classify() has no rung-8 term. A control that cannot run
  # must SKIP LOUDLY rather than pass (memory control-must-replay-the-real-artifact).
  local sha pre="$D/pre.sh" found=""
  for sha in $(git -C "$REPO" log --format=%H -n 40 -- scripts/capacity-alarm.sh); do
    git -C "$REPO" show "$sha:scripts/capacity-alarm.sh" > "$pre" 2>/dev/null || continue
    grep -q '^classify() {' "$pre" || continue
    if ! sed -n '/^classify() {/,/^}/p' "$pre" | grep -q 'KALLOC_ALARM_GB'; then found="$sha"; break; fi
  done
  [ -n "$found" ] || skip "no pre-rung-8 commit of capacity-alarm.sh reachable — the control cannot run"
  # Panic #5's chronic state on an otherwise healthy box: 73 swapfiles, 9.89 GB in the zone.
  run run_classify "$pre" 99 0 1 0 "" "" "" 73 9.89
  [ "$status" -eq 0 ] || false
  [[ "$output" == OK* ]] || false
  [[ "$output" != *"kalloc="* ]] || false      # <-- the gap: nothing in the ladder names either axis
  [[ "$output" != *"swapfiles="* ]] || false
}

@test "the fixed classify names panic #5's chronic state — and leaves the verdict OK (D5)" {
  run run_classify "$A" 99 0 1 0 "" "" "" 73 9.89
  [ "$status" -eq 0 ] || false
  [ "$output" = "OK swap=OK headroom=OK pressure=OK maxproc=OK segments=SKIPPED coalition=SKIPPED load=SKIPPED swapfiles=ALARM kalloc=ALARM" ]
}

@test "rung 8 floors, pinned from BOTH sides — swapfiles 20/12, kalloc 6/4 GB" {
  local p sf kg ws wk
  for p in "20::ALARM:SKIPPED" "19::WARN:SKIPPED" "12::WARN:SKIPPED" "11::OK:SKIPPED" "0::OK:SKIPPED" \
           ":6:SKIPPED:ALARM" ":5.99:SKIPPED:WARN" ":4:SKIPPED:WARN" ":3.99:SKIPPED:OK" ":0.08:SKIPPED:OK"; do
    IFS=: read -r sf kg ws wk <<< "$p"
    run run_classify "$A" 99 0 1 0 "" "" "" "$sf" "$kg"
    [[ "$output" == OK*" swapfiles=$ws kalloc=$wk" ]] || { echo "probe $p -> $output"; false; }
  done
}

@test "an unreadable ratchet is SKIPPED, never a made-up 0 — and neither masks nor survives the acute ladder" {
  local v
  for v in '' '?' '-1' 'n/a'; do
    run run_classify "$A" 99 0 1 0 "" "" "" "$v" "$v"
    [[ "$output" == "OK "*"swapfiles=SKIPPED kalloc=SKIPPED" ]] || { echo "[$v] $output"; false; }
  done
  # An acute ALARM is never softened by a calm rung 8...
  run run_classify "$A" 1 0 1 0 "" "" "" 0 0.08
  [[ "$output" == "ALARM "*"swapfiles=OK kalloc=OK" ]] || false
  # ...and NO-DATA does not blind rung 8, which needs no vm_stat.
  run run_classify "$A" "" 0 "" "" "" "" "" 73 9.89
  [ "$output" = "NO-DATA swap=SKIPPED headroom=SKIPPED pressure=SKIPPED maxproc=SKIPPED segments=SKIPPED coalition=SKIPPED load=SKIPPED swapfiles=ALARM kalloc=ALARM" ]
}

@test "swapfiles are counted at the configured prefix, and the row names that prefix" {
  mk_swapdir 3; mk_zprint 1024
  run /bin/bash "$A" --json --no-append
  [ "$(row_field swapfiles)" = 3 ] || false
  [ "$(row_field swapfile_prefix)" = "$D/vm/swapfile" ]
}

@test "0 swapfiles is a READING only while the kernel reports no swap — otherwise it is REFUSED" {
  mk_swapdir 0; mk_zprint 1024
  mk_sysctl_swaptotal 0.00
  run /bin/bash "$A" --json --no-append
  [ "$(row_field swapfiles)" = 0 ] || false            # a clean box
  mk_sysctl_swaptotal 3072.00
  run /bin/bash "$A" --json --no-append
  [ "$(row_field swapfiles)" = null ]                  # the item's dead-path shape: refused, never 0
}

@test "LIVE: with swap in use, the kernel's own prefix counts at least one swapfile" {
  local total n
  total="$(/usr/sbin/sysctl -n vm.swapusage | sed -n 's/.*total = \([0-9.]*\)M.*/\1/p')"
  awk -v t="${total:-0}" 'BEGIN{exit !(t+0 > 0)}' || skip "no swap in use on this box — nothing to count"
  run env CC_CAP_KALLOC=off /bin/bash "$A" --json --no-append
  n="$(row_field swapfiles)"
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "swapfiles=$n with ${total} MB of swap"; false; }
  [ "$n" -ge 1 ]
}

@test "RED CONTROL, LIVE: the path the item named reads a false 0 while the kernel reports swap" {
  # Why the rung reads vm.swapfileprefix instead: on this macOS /private/var/vm holds sleepimage only.
  # If swapfiles ever appear there again this control has nothing to show, and SKIPS, not passes.
  local total vmn=0 f
  total="$(/usr/sbin/sysctl -n vm.swapusage | sed -n 's/.*total = \([0-9.]*\)M.*/\1/p')"
  awk -v t="${total:-0}" 'BEGIN{exit !(t+0 > 0)}' || skip "no swap in use on this box — the control cannot show anything"
  for f in /private/var/vm/swapfile*; do [ -e "$f" ] && vmn=$((vmn + 1)); done
  [ "$vmn" -eq 0 ] || skip "/private/var/vm holds $vmn swapfiles on this box — that path is not dead here"
  echo "/private/var/vm counts 0 against ${total} MB of swap"
}

@test "the zone read: cur inuse x elem size, from the EXACT zone — and the verdict does not move" {
  mk_zprint 10838624                                   # this box on 2026-09-10, 16 days up
  run /bin/bash "$A" --json --no-append
  [ "$status" -ne 64 ] || false
  [ "$(row_field kalloc1024_gb)" = "10.34" ] || false  # not the 99999999-element decoy zone above it
  [ "$(row_field kalloc1024_src)" = measured ] || false
  [[ "$(row_field kalloc1024_at)" =~ ^[0-9]+$ ]] || false
  [ "$(row_field chronic_verdict)" = ALARM ] || false
  [ "$(row_field verdict)" = OK ]
}

@test "the zone read is BOUNDED without coreutils — a wedged zprint yields null, never 0, and the tick ends" {
  mk_zprint 10838624 30
  local t0=$SECONDS
  run env CC_CAP_KALLOC_TIMEOUT_S=1 /bin/bash "$A" --json --no-append
  [ $((SECONDS - t0)) -lt 20 ] || { echo "the bound did not hold: $((SECONDS - t0))s"; false; }
  [ "$(row_field kalloc1024_gb)" = null ] || false
  [ "$(row_field kalloc1024_src)" = timeout ] || false
  [ "$(calls)" = 1 ]                                   # non-vacuity: it really was invoked
}

@test "the zone read is DAMPED — a second row inside the window carries, with its OWN measured-at" {
  mk_zprint 10838624
  run /bin/bash "$A" --json
  [ "$(row_field kalloc1024_src)" = measured ] || false
  local at1; at1="$(row_field kalloc1024_at)"
  run /bin/bash "$A" --json
  [ "$(row_field kalloc1024_src)" = carried ] || false
  [ "$(row_field kalloc1024_at)" = "$at1" ] || false   # the carry never claims to be fresh
  [ "$(row_field kalloc1024_gb)" = "10.34" ] || false
  [ "$(calls)" = 1 ]                                   # one zone walk for two rows
}

@test "a carry never crosses a reboot — and the SAME prior row inside the boot is carried (control)" {
  mk_zprint 5000000                                    # 4.77 GB fresh
  local now; now="$(date -u +%s)"
  printf '{"ts":"%s","verdict":"OK","headroom_gb":20,"swap_used_mb":0,"swapfiles":3,"kalloc1024_gb":9.89,"kalloc1024_at":%s}\n' \
    "$(date -u -r $((now - 100)) +%Y-%m-%dT%H:%M:%SZ)" "$((now - 100))" > "$CC_CAP_LOG"
  run env CC_CAP_BOOTTIME="$((now - 50))" /bin/bash "$A" --json --no-append
  [ "$(row_field kalloc1024_src)" = measured ] || false   # a pre-boot 9.89 is not this boot's zone
  [ "$(row_field kalloc1024_gb)" = "4.77" ] || false
  run env CC_CAP_BOOTTIME="$((now - 500))" /bin/bash "$A" --json --no-append
  [ "$(row_field kalloc1024_src)" = carried ] || false
  [ "$(row_field kalloc1024_gb)" = "9.89" ]
}

@test "under a storm the zone map is NOT walked (D2) — the rung SKIPs rather than risk the tick" {
  mk_zprint 10838624
  run env CC_CAP_SEG_WARN_PCT=0 /bin/bash "$A" --json --no-append
  [ "$(row_field seg_pct)" != null ] || skip "segment estimate unreadable here — cannot induce a storm"
  [ "$(row_field kalloc1024_src)" = skipped-storm ] || false
  [ "$(row_field kalloc1024_gb)" = null ] || false
  [ "$(calls)" = 0 ]
}

@test "CC_CAP_KALLOC=off switches the zone read off — null and src=off, never 0, and no zprint" {
  mk_zprint 10838624
  run env CC_CAP_KALLOC=off /bin/bash "$A" --json --no-append
  [ "$(row_field kalloc1024_src)" = off ] || false
  [ "$(row_field kalloc1024_gb)" = null ] || false
  [ "$(calls)" = 0 ]
}

@test "each ratchet pages on ITS OWN transition with a reboot advisory — and the combined page stays down" {
  export CC_CAP_KALLOC_MIN_S=0                         # sample every run, so no page reads a carry
  mk_zprint 7340032                                    # 7.00 GB — past the 6 GB floor
  mk_swapdir 20                                        # at the 20-file floor
  local P="$CC_PAGES_DIR" m0
  run /bin/bash "$A" --quiet
  [ -f "$P/capacity-alarm-kalloc.page" ] || false
  [ -f "$P/capacity-alarm-swapfiles.page" ] || false
  grep -q 'SCHEDULE A REBOOT' "$P/capacity-alarm-kalloc.page" || false
  grep -q 'data.kalloc.1024 holds 7.00 GB' "$P/capacity-alarm-kalloc.page" || false
  grep -q '^20 swapfiles at ' "$P/capacity-alarm-swapfiles.page" || false
  ! grep -q 'shed by CLOSING' "$P/capacity-alarm-kalloc.page" || false   # not the lever for a leak
  [ ! -f "$P/capacity-alarm.page" ] || false           # D5: the verdict is OK, so no combined page
  # TRANSITION-ONLY (D3): a standing ALARM does not rewrite its page, so its clock still says when it began.
  touch -t 202001010000 "$P/capacity-alarm-kalloc.page"
  m0="$(stat -f %m "$P/capacity-alarm-kalloc.page")"
  run /bin/bash "$A" --quiet
  [ "$(stat -f %m "$P/capacity-alarm-kalloc.page")" = "$m0" ] || false
  # ...and both RETRACT when the ratchets clear (a reboot; here, the stubs).
  mk_zprint 1024; rm -f "$D"/vm/swapfile*; mk_swapdir 3
  run /bin/bash "$A" --quiet
  [ ! -f "$P/capacity-alarm-kalloc.page" ] || false
  [ ! -f "$P/capacity-alarm-swapfiles.page" ]
}

@test "LIVE: both instruments answer on the real box with PATH=/usr/bin:/bin — the launchd floor" {
  run env -i PATH=/usr/bin:/bin HOME="$HOME" CC_CAP_LOG="$D/live.jsonl" CC_CAP_COAL_FP=0 \
          CC_CAP_AUTO_COAL=0 CC_CAP_KALLOC_TIMEOUT_S=20 /bin/bash "$A" --json --no-append
  local gb
  [ "$(row_field kalloc1024_src)" = measured ] || { echo "src=$(row_field kalloc1024_src)"; false; }
  gb="$(row_field kalloc1024_gb)"
  awk -v g="$gb" 'BEGIN{exit !(g+0 > 0)}' || { echo "kalloc1024_gb=$gb"; false; }   # a live kernel holds this zone
  [[ "$(row_field swapfiles)" =~ ^[0-9]+$ ]] || false
  [[ "$(row_field uptime_days)" =~ ^[0-9]+(\.[0-9])?$ ]]
}

@test "the in-script selftest is GREEN and runs rung 8 — its probes and both live instruments" {
  run env "${UNPIN[@]}" -u CC_CAP_BOOTTIME CC_CAP_SELFTEST=1 /bin/bash "$A"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" | grep 'control FAIL'; false; }
  [[ "$output" == *"selftest GREEN (7 rungs + rung 8's 2 chronic ratchets"* ]] || false
  printf '%s\n' "$output" | grep -qF "swapfiles='73' kalloc='9.89' → OK swapfiles=ALARM kalloc=ALARM" || false
  printf '%s\n' "$output" | grep -qE "control OK   swapfiles [0-9]+ counted at " || false
  printf '%s\n' "$output" | grep -qE "control (OK   data\.kalloc\.1024 [0-9.]+ GB|SKIP kalloc — zprint ran past)"
}
