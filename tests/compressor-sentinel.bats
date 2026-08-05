#!/usr/bin/env bats
# compressor-sentinel — the guard for the axis three kernel panics died on
# (docs/research/panic-compressor-2026-08-05.md).
#
# WHAT THIS SUITE HAS TO PROVE, and why each is a test rather than a comment:
#   · THE ARITHMETIC. The whole sensor is a substitution: zprint hangs under the storm it measures,
#     so segments are inferred from vm_stat pages ÷ (buffer/pagesize) plus swap ÷ 65536 (§7.7). If
#     that inference is wrong the daemon is confidently blind, and nothing downstream would notice —
#     a wrong segment count still produces plausible rows forever.
#   · THE CONJUNCTION. §6's discriminator is level AND rate. Either one alone has a benign
#     counterpart (this box idles under 15%; every build ramps), so a test that only drives both
#     together would pass against a broken OR.
#   · TWO CONSECUTIVE TICKS. A single spike must not trip. This is the difference between an alarm
#     that gets acted on and one that gets muted.
#   · UNREADABLE ⇒ NO ROW. capacity-alarm.sh shipped `${SWAP_MB:-0}` and rendered a dead sysctl as
#     the healthy value 0 for weeks. The negative control here is that a broken instrument produces
#     NOTHING, and the positive control beside it is that the same run WITH the sysctl produces a row.
#   · THE ACTUATOR'S EXCLUSIONS. This is the first thing on this box that signals live processes
#     without being asked. claude.exe must be unstoppable by construction, not by luck.
#
# PROOF DISCIPLINE (this repo's bar):
#   · $HOME is FIXTURED and every log/page path is redirected into $BATS_TEST_TMPDIR. The subject
#     appends to ~/.claude/logs/ and writes ~/.claude/autonomy/pages/, so an unfixtured run would
#     mutate the operator's live telemetry — the exact trap tests/capacity-alarm-segments.bats:17
#     records having sprung for real.
#   · NO real zprint, ps, sysctl, vm_stat, kill or launchctl. vm_stat/sysctl/ps are stubbed on PATH;
#     the actuator is exercised through its pure selector, never through a signal.
#   · Non-final `[ ]` is errexit-EXEMPT under bats and therefore DEAD as an assertion (memory
#     bats-dead-assertions-errexit-exemptions) — every one below carries `|| false`.
#   · Every ABSENCE assertion has a POSITIVE CONTROL beside it.
#
# RED-PROOF: against a tree without scripts/compressor-sentinel.sh, setup's `[ -f "$S" ]` fails and
# every case fails at setup rather than passing vacuously.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/compressor-sentinel.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude/logs" "$HOME/.claude/autonomy/pages"
  [ -f "$S" ] || false

  # The functions are the unit under test, and the script cannot be sourced — its body IS an
  # infinite daemon loop. Extract every top-level function into a sourceable lib instead.
  sed -n '/^[a-z_]*() {/,/^}/p' "$S" > "$D/lib.sh"
  bash -n "$D/lib.sh" || false

  export LOG="$D/cs.jsonl"
  export SNAPLOG="${LOG%.jsonl}-snap.log"
  export PAGE="$HOME/.claude/autonomy/pages/compressor-sentinel.page"
  STUB="$D/bin"; mkdir -p "$STUB"
}

# ── extract-function runner ───────────────────────────────────────────────────────────────────────
# Thresholds arrive as globals, exactly as the subject reads them, so a test can drive the predicate
# without a machine. A prefix assignment on the CALL (`TRIP_SEG_RATE=50 run_fn ...`) is visible here.
run_fn() { # <fn> <args...>
  run env \
    TRIP_SEG_PCT="${TRIP_SEG_PCT:-15}"   TRIP_SEG_RATE="${TRIP_SEG_RATE:-600}" \
    TRIP_CBU_MB="${TRIP_CBU_MB:-640}"    TRIP_SWAP_MB="${TRIP_SWAP_MB:-1024}" \
    INTERVAL="${INTERVAL:-10}" \
    bash -c '. "$1"; shift; f="$1"; shift; "$f" "$@"' _ "$D/lib.sh" "$@"
}

# ── the stub machine ──────────────────────────────────────────────────────────────────────────────
# Every reading comes from a per-tick SEQUENCE file, so each scenario is written out literally rather
# than derived from a formula nobody can check. The tick counter advances on the LAST sysctl the
# subject reads in a tick (vm.lz4_compression_failures) — never on vm_stat, because the trip snapshot
# calls vm_stat again and a counter keyed on it would silently desynchronise the ramp it is measuring.
mkstubs() { # <occ-seq> <swap-MB-seq> <cbu-bytes-seq>   (each: newline-separated, last value repeats)
  printf '%s\n' "$1" > "$D/seq.occ"
  printf '%s\n' "$2" > "$D/seq.swap"
  printf '%s\n' "$3" > "$D/seq.cbu"
  echo 0 > "$D/tick"
  export TICKF="$D/tick" SEQ_OCC="$D/seq.occ" SEQ_SWAP="$D/seq.swap" SEQ_CBU="$D/seq.cbu"
  export STUB_SEG_LIMIT="${STUB_SEG_LIMIT:-1000000}" FAIL_SYSCTL="${FAIL_SYSCTL:-}"

  cat > "$STUB/pick" <<'SH'
#!/bin/bash
awk -v n="$(cat "$TICKF")" '{v[NR]=$1; last=NR} END{ i=n+1; if (i>last) i=last; print v[i] }' "$1"
SH

  cat > "$STUB/vm_stat" <<'SH'
#!/bin/bash
occ="$(pick "$SEQ_OCC")"; n="$(cat "$TICKF")"
echo "Mach Virtual Memory Statistics: (page size of 16384 bytes)"
echo "Pages free:                              884267."
echo "Pages active:                           1434909."
echo "Pages occupied by compressor:            ${occ}."
echo "Compressions:                            $((n * 1000))."
echo "Decompressions:                          $((n * 600))."
SH

  cat > "$STUB/sysctl" <<'SH'
#!/bin/bash
name="$2"
[ "$name" = "$FAIL_SYSCTL" ] && exit 1
case "$name" in
  vm.swapusage) printf 'total = 0.00M  used = %sM  free = 0.00M  (encrypted)\n' "$(pick "$SEQ_SWAP")" ;;
  vm.compressor_segment_limit)       echo "$STUB_SEG_LIMIT" ;;
  vm.compressor_segment_buffer_size) echo 65536 ;;
  vm.compressor_bytes_used)          pick "$SEQ_CBU" ;;
  vm.compressor_input_bytes)         echo 4000 ;;
  vm.compressor_compressed_bytes)    echo 1000 ;;
  vm.wk_compression_failures)        echo 7 ;;
  # LAST read of a full tick — advance here so every reading within one tick is self-consistent.
  vm.lz4_compression_failures)       echo 3; echo $(( $(cat "$TICKF") + 1 )) > "$TICKF" ;;
  *) exit 1 ;;
esac
SH

  cat > "$STUB/ps" <<'SH'
#!/bin/bash
case "$*" in
  *"pid=,ppid=,rss=,comm="*) cat "$PS_CENSUS" 2>/dev/null ;;
  *"pid=,rss=,comm=,args="*) cat "$PS_ACT" 2>/dev/null ;;
  *) echo "stub-ps $*" ;;
esac
SH

  : > "$D/ps.census"; : > "$D/ps.act"
  export PS_CENSUS="$D/ps.census" PS_ACT="$D/ps.act"
  chmod +x "$STUB"/pick "$STUB"/vm_stat "$STUB"/sysctl "$STUB"/ps
}

run_daemon() { # <ticks> [extra env assignments already exported by the caller]
  run env PATH="$STUB:$PATH" \
    CC_SENTINEL_LOG="$LOG" CC_SENTINEL_INTERVAL="${IV:-1}" \
    CC_SENTINEL_CENSUS_EVERY="${CENSUS_EVERY:-6}" \
    CC_SENTINEL_FOLLOWUP_N="${FUP_N:-1}" CC_SENTINEL_FOLLOWUP_SEC=1 \
    CC_SENTINEL_ACT="${ACT:-off}" \
    bash "$S" --ticks "$1"
}

rows() { [ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' || echo 0; }

# ══ 1. SEGMENT ARITHMETIC — the substitution the whole sensor rests on ════════════════════════════

@test "in-core segments: 16 KiB pages ⇒ compressor pages ÷ 4 (this box's real geometry)" {
  # 65536 / 16384 = 4. The research's own recipe, and the number the panic logs are read against.
  run_fn segs_in_core 472000 16384 65536
  [ "$status" -eq 0 ] || false
  [ "$output" = "118000" ] || false
}

@test "the ÷4 is DERIVED, not a literal: a 4 KiB page box must divide by 16" {
  # The control that catches the obvious shortcut. Hard-coding 4 would over-report in-core segments
  # by 4x on any 4 KiB-page machine — a fabricated ramp, in the direction that trips.
  run_fn segs_in_core 472000 4096 65536
  [ "$status" -eq 0 ] || false
  [ "$output" = "29500" ] || false
}

@test "segs_in_core refuses rather than divides by a nonsense geometry" {
  run_fn segs_in_core 472000 0 65536;  [ "$status" -ne 0 ] || false; [ -z "$output" ] || false
  run_fn segs_in_core 472000 16384 0;  [ "$status" -ne 0 ] || false; [ -z "$output" ] || false
  # ...and the positive control, so the two refusals above are a judgement and not a broken function.
  run_fn segs_in_core 472000 16384 65536; [ "$status" -eq 0 ] || false
}

@test "swapped segments are EXACT: swap used ÷ 65536, because swap is allocated in whole segments" {
  run_fn segs_swapped 76021760 65536      # 1160 segments exactly
  [ "$output" = "1160" ] || false
}

@test "swap parsing honours the UNIT — G is not M" {
  run_fn parse_swap_used_bytes <<< 'total = 8.00G  used = 2.00G  free = 6.00G  (encrypted)'
  [ "$output" = "2147483648" ] || false
  run_fn parse_swap_used_bytes <<< 'total = 1024.00M  used = 512.00M  free = 512.00M  (encrypted)'
  [ "$output" = "536870912" ] || false
}

@test "an unparseable swapusage line REFUSES — it never renders as 0 bytes of swap" {
  # A fabricated 0 here understates the swapped half of the pool, which on the fatal night was
  # 1.16M of the ~1.63M segments — i.e. most of the signal.
  run_fn parse_swap_used_bytes <<< 'total = 0.00M  free = 0.00M'
  [ "$status" -ne 0 ] || false
  [ -z "$output" ] || false
  run_fn parse_swap_used_bytes <<< 'total = 0.00M  used = 0.00X  free = 0.00M'
  [ "$status" -ne 0 ] || false
  [ -z "$output" ] || false
}

@test "vm_stat parsing reads the page size from vm_stat's OWN header, and all three counters" {
  mkstubs 800000 0 0
  run env PATH="$STUB:$PATH" TICKF="$TICKF" SEQ_OCC="$SEQ_OCC" \
    bash -c '. "$1"; read_vm_stat' _ "$D/lib.sh"
  [ "$status" -eq 0 ] || false
  [ "$output" = "16384 800000 0 0" ] || false
}

@test "vm_stat missing the compressor row REFUSES rather than reporting zero pages" {
  printf '#!/bin/bash\necho "Mach Virtual Memory Statistics: (page size of 16384 bytes)"\necho "Pages free: 12."\n' > "$STUB/vm_stat"
  chmod +x "$STUB/vm_stat"
  run env PATH="$STUB:$PATH" bash -c '. "$1"; read_vm_stat' _ "$D/lib.sh"
  [ "$status" -ne 0 ] || false
  [ -z "$output" ] || false
}

@test "read_num_sysctl refuses empty and non-numeric — never a fabricated 0" {
  printf '#!/bin/bash\ncase "$2" in ok) echo 4242 ;; junk) echo "not-a-number" ;; *) exit 1 ;; esac\n' > "$STUB/sysctl"
  chmod +x "$STUB/sysctl"
  run env PATH="$STUB:$PATH" bash -c '. "$1"; read_num_sysctl ok' _ "$D/lib.sh"
  [ "$output" = "4242" ] || false            # positive control
  run env PATH="$STUB:$PATH" bash -c '. "$1"; read_num_sysctl junk' _ "$D/lib.sh"
  [ "$status" -ne 0 ] || false; [ -z "$output" ] || false
  run env PATH="$STUB:$PATH" bash -c '. "$1"; read_num_sysctl absent' _ "$D/lib.sh"
  [ "$status" -ne 0 ] || false; [ -z "$output" ] || false
}

# ══ 2. THE TRIP PREDICATE — the conjunction is the discriminator ══════════════════════════════════
# classify_breach <seg_est> <seg_limit> <seg_rate/s> <dcbu B/s> <dswap B/s>

@test "seg arm fires only on level AND rate together" {
  run_fn classify_breach 200000 1000000 700 0 0     # 20% of limit, 700 seg/s
  [ "$status" -eq 0 ] || false
  [ "$output" = "seg" ] || false
}

@test "seg arm: level over the floor but rate BELOW it is not a trip" {
  # This box sits at a standing level under load. Level alone would page continuously and get muted.
  run_fn classify_breach 200000 1000000 599 0 0
  [ "$status" -ne 0 ] || false
  [ -z "$output" ] || false
}

@test "seg arm: rate over the floor but level BELOW it is not a trip" {
  # Every ordinary build ramps segments fast from a low base. Rate alone has benign counterparts.
  run_fn classify_breach 140000 1000000 5000 0 0
  [ "$status" -ne 0 ] || false
  [ -z "$output" ] || false
}

@test "the seg-rate floor is the documented seam, and it moves the verdict" {
  TRIP_SEG_RATE=50 run_fn classify_breach 200000 1000000 100 0 0
  [ "$output" = "seg" ] || false
  run_fn classify_breach 200000 1000000 100 0 0     # same sample, default floor 600
  [ "$status" -ne 0 ] || false
}

@test "compressor-bytes and swap arms fire independently of the segment arm" {
  # 640 MB and 1 GB per 10 s tick = 64 MB/s and 102.4 MB/s — how §7.1 states the ramp.
  run_fn classify_breach 0 1000000 0 100000000 0
  [ "$output" = "cbu" ] || false
  run_fn classify_breach 0 1000000 0 0 214748364
  [ "$output" = "swap" ] || false
  # The comparison is STRICTLY greater, so the floor itself is not a breach. Stated as a test because
  # a threshold whose boundary nobody pinned drifts by one refactor.
  run_fn classify_breach 0 1000000 0 67108864 0     # exactly 640 MB / 10 s
  [ "$status" -ne 0 ] || false
}

@test "the byte arms are RATES: the same delta under a stretched tick must not trip" {
  # A tick stretched by the storm is the instrument measuring itself. 640 MB in 10 s trips; the
  # identical 640 MB spread over a 40 s tick is 16 MB/s and must not.
  run_fn classify_breach 0 1000000 0 67108865 0    # 640 MB / 10 s + 1 B
  [ "$output" = "cbu" ] || false
  run_fn classify_breach 0 1000000 0 16777216 0    # 640 MB / 40 s
  [ "$status" -ne 0 ] || false
}

@test "a clear sample returns rc 1 and prints nothing; multiple arms combine into one reason" {
  run_fn classify_breach 100 1000000 1 10 10
  [ "$status" -ne 0 ] || false
  [ -z "$output" ] || false
  run_fn classify_breach 200000 1000000 700 100000000 214748364
  [ "$output" = "seg+cbu+swap" ] || false
}

# ══ 3. TWO CONSECUTIVE TICKS, AND THE COOLDOWN ═══════════════════════════════════════════════════

@test "a single spike does NOT trip — one breaching tick is not a ramp" {
  # Segments jump once (tick 2), then hold. Tick 2 breaches, tick 3 has Δ=0 and clears the streak.
  mkstubs "$(printf '800000\n2400000\n2400000\n2400000')" 0 0
  run_daemon 4
  [ "$status" -eq 0 ] || false
  [ "$(rows)" = "4" ] || false
  [ ! -f "$PAGE" ] || false
  [ ! -f "$SNAPLOG" ] || false
}

@test "two CONSECUTIVE breaching ticks trip: page, snapshot and a loud stderr line" {
  # A sustained ramp: +400,000 compressor pages per tick = +100,000 segments/tick, level well over
  # 15% of a 1,000,000 limit from the first sample.
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  run_daemon 3
  [ "$status" -eq 0 ] || false
  [ "$(rows)" = "3" ] || false
  echo "$output" | grep -q 'TRIP why=seg' || false
  [ -f "$PAGE" ] || false
  grep -q 'compressor-sentinel TRIP (seg)' "$PAGE" || false
  grep -q 'snapshot:' "$PAGE" || false
  [ -f "$SNAPLOG" ] || false
  grep -q '═══ TRIP' "$SNAPLOG" || false
  grep -q -- '--- vm_stat ---' "$SNAPLOG" || false
}

@test "the trip fires on tick 2 of the ramp, not tick 1 — consecutiveness is real" {
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  run_daemon 1
  [ "$(rows)" = "1" ] || false
  [ ! -f "$PAGE" ] || false      # one tick cannot have a rate at all, let alone two breaches
  run_daemon 2                   # fresh run, two ticks: baseline + one breach = still no trip
  [ ! -f "$PAGE" ] || false
}

@test "cooldown suppresses a second trip inside the window" {
  # Six ticks of unbroken ramp. Without a cooldown this trips on ticks 3, 4, 5 and 6; with the 60 s
  # cooldown (and the post-trip streak reset) exactly one TRIP line may appear in a ~6 s run.
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000\n2400000\n2800000\n3200000')" 0 0
  run_daemon 6
  [ "$(echo "$output" | grep -c 'TRIP why=')" = "1" ] || false
  [ "$(grep -c '═══ TRIP' "$SNAPLOG")" = "1" ] || false
}

@test "the follow-up snapshots run in the BACKGROUND — the JSONL keeps sampling during a trip" {
  # The trip lands on tick 3 and the run continues to tick 6, so the follow-up's own 1 s cadence
  # overlaps three more sampled ticks. That overlap IS the property: 12 x 5 s of blocking snapshots
  # would blind the log for a minute starting at the exact moment the ramp becomes interesting, and
  # §6 discriminator 4 makes a row GAP a distress signal in its own right.
  #
  # It must be tested with ticks REMAINING after the trip, because on exit the daemon KILLS the
  # follow-up rather than waiting 60 s for it — so a run that trips on its LAST tick correctly
  # produces no follow-up at all.
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  FUP_N=3 run_daemon 6
  grep -q -- '--- follow-up 1/3' "$SNAPLOG" || false
  [ "$(rows)" = "6" ] || false     # ...and not one sample was lost to the capture
}

# ══ 4. UNREADABLE ⇒ NO ROW (never a fabricated healthy 0) ═════════════════════════════════════════

@test "an unreadable TRIP-BEARING sysctl skips the tick: no row, and the reason on stderr" {
  mkstubs 800000 0 0
  FAIL_SYSCTL=vm.compressor_segment_limit run_daemon 2
  [ "$(rows)" = "0" ] || false
  echo "$output" | grep -q 'SKIP tick' || false
  echo "$output" | grep -q 'vm.compressor_segment_limit' || false
  [ "$status" -eq 3 ] || false     # zero rows on a bounded run is a BROKEN instrument, not success
}

@test "POSITIVE CONTROL: the same run with that sysctl readable emits rows" {
  # Without this, the assertion above would pass equally against a daemon that never writes anything.
  mkstubs 800000 0 0
  run_daemon 2
  [ "$(rows)" = "2" ] || false
  [ "$status" -eq 0 ] || false
}

@test "an unreadable DIAGNOSTIC sysctl still emits the row, as JSON null — never 0" {
  # The failure counters discriminate WHICH mechanism is running; they do not gate the trip. A build
  # without them must still be guarded. `null` is an honest absence; `0` would read as "no failures".
  mkstubs 800000 0 0
  FAIL_SYSCTL=vm.lz4_compression_failures run_daemon 1
  [ "$(rows)" = "1" ] || false
  grep -q '"fail":null' "$LOG" || false
  grep -qv '"fail":0' "$LOG" || false
}

@test "every emitted row is a parseable JSON document, not just a field that greps" {
  # The defect a 3-tick smoke caught during development: the census emitted `"n":8,2,3404` — three
  # bare values under one key. A per-field grep passes against that; the document does not parse.
  mkstubs 800000 0 0
  printf '400 1 950000 /opt/homebrew/bin/node w.js\n401 1 120000 /opt/homebrew/bin/node w.js\n' > "$PS_CENSUS"
  CENSUS_EVERY=1 run_daemon 3
  python3 -c 'import json,sys
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert len(rows) == 3, rows
assert rows[0]["el"] is None and rows[1]["el"] is not None
# the census is three SEPARATE keys, which is what the poisoned `"n":8,2,3404` row got wrong
assert rows[0]["n"] == 2 and rows[0]["orph"] == 2 and rows[0]["nrss"] == 1044, rows[0]' "$LOG" || false
}

# ══ 5. THE ACTUATOR — exclusions are structural, not incidental ═══════════════════════════════════
# select_stop_targets <prev_census_pids> <rss_floor_kb> <cap>, reading `pid rss comm args` on stdin.

sel() { # <prev pids> <stdin lines>
  run env bash -c '. "$1"; select_stop_targets "$2" 102400 200' _ "$D/lib.sh" "$1" <<< "$2"
}

@test "claude.exe is NEVER stopped, however big or however new" {
  sel "" "$(printf '901 4000000 /Users/x/.claude/bin/claude.exe --resume\n902 4000000 /usr/local/bin/claude serve')"
  [ -z "$output" ] || false
  # POSITIVE CONTROL: the same shape with a plain node comm IS selected, so the emptiness above is
  # the exclusion working and not the selector being broken.
  sel "" "$(printf '903 4000000 /opt/homebrew/bin/node dist/worker.js')"
  [ "$output" = "903 4000000 node" ] || false
}

@test "anything claude- or mcp-shaped in argv is excluded even with a node comm" {
  sel "" "$(printf '904 900000 /opt/homebrew/bin/node /Users/x/.claude/hooks/foo.js\n905 900000 /opt/homebrew/bin/node /opt/mcp-server/index.js')"
  [ -z "$output" ] || false
}

@test "non-node executables are out of the cohort entirely" {
  sel "" "$(printf '906 4000000 /Applications/Chrome.app/Contents/MacOS/Chrome --type=renderer\n907 4000000 /usr/bin/python3 train.py')"
  [ -z "$output" ] || false
}

@test "the RSS floor holds: a 100 MB worker is not the burst" {
  sel "" "$(printf '908 102400 /opt/homebrew/bin/node w.js\n909 102401 /opt/homebrew/bin/node w.js')"
  [ "$output" = "909 102401 node" ] || false
}

@test "BURST COHORT: a pid present at the previous census is never stopped" {
  # The whole point of the census — stop what just appeared, not the fleet that was already working.
  sel "910 912" "$(printf '910 900000 /opt/homebrew/bin/node old.js\n911 900000 /opt/homebrew/bin/node new.js')"
  [ "$output" = "911 900000 node" ] || false
}

@test "the pid match is exact, not a substring of the census list" {
  # Without the space-delimited index test, census pid 9110 would shadow burst pid 911.
  sel "9110 9112" "$(printf '911 900000 /opt/homebrew/bin/node new.js')"
  [ "$output" = "911 900000 node" ] || false
}

@test "the cap is enforced — a 500-process burst yields exactly 200 stops" {
  local many=""
  for i in $(seq 1000 1499); do many="$many$i 900000 /opt/homebrew/bin/node w.js"$'\n'; done
  sel "" "$many"
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "200" ] || false
}

@test "the actuator is DISARMED by default, and says so in the snapshot" {
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  run_daemon 3
  grep -q 'actuator: DISARMED' "$SNAPLOG" || false
  ! grep -q 'SIGSTOP pid=' "$SNAPLOG" || false
}

@test "CC_SENTINEL_ACT=stop reaches the actuator branch (and signals nothing here)" {
  # The ps stub hands back pids in the 999xxx range, which cannot exist — macOS pids wrap below
  # 100000 — so `kill -STOP` fails and this proves the branch is WIRED without signalling anything
  # on the real machine. That impossibility is the reason this test is safe to run at all.
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  printf '999901 900000 /opt/homebrew/bin/node w.js\n' > "$PS_ACT"
  ACT=stop run_daemon 3
  grep -q 'actuator: SIGSTOPped 0 process' "$SNAPLOG" || false
  ! grep -q 'DISARMED' "$SNAPLOG" || false
}

# ══ 6. SEAMS ═════════════════════════════════════════════════════════════════════════════════════

@test "CC_SENTINEL=off is a real kill switch: no rows, exit 0" {
  mkstubs 800000 0 0
  run env PATH="$STUB:$PATH" CC_SENTINEL=off CC_SENTINEL_LOG="$LOG" bash "$S" --ticks 2
  [ "$status" -eq 0 ] || false
  [ "$(rows)" = "0" ] || false
}

@test "the snap log follows CC_SENTINEL_LOG, so one override cannot leave trips in the live logs" {
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  run_daemon 3
  [ -f "$SNAPLOG" ] || false
  [ ! -f "$HOME/.claude/logs/compressor-sentinel-snap.log" ] || false
}

@test "--ticks rejects a non-integer rather than mis-comparing it every loop" {
  run bash "$S" --ticks abc
  [ "$status" -eq 64 ] || false
}
