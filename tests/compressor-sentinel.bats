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

  # THE PRE-FIX CONTROL. Every case in §5c must be able to FAIL, and the only artifact that proves
  # it is the REAL code as it stood before this diff — replayed from git, never a mutant of this
  # file (memory: control-must-replay-the-real-artifact). Extracted the same way as lib.sh.
  #
  # PINNED SHA, NOT `origin/main`. 808c09609 is 6dd3ea468^ — the last commit whose census still read
  # `split($4, p, "/")` and whose selectors still took comm from the truncated `pid=,ppid=,rss=,
  # comm=,args=` stream. `origin/main` MOVES: the moment 6dd3ea468 landed there, this replayed the
  # POST-fix artifact and every §5c control below compared the fix to itself — GREEN, permanently,
  # asserting nothing. A vacuous control is worse than a red one: a red control gets fixed, a
  # vacuous one gets trusted. (memory: control-must-replay-the-real-artifact)
  #
  # AND THE MARKER, because the pin alone is not enough — a sha can be re-pointed, and a `git show`
  # that fails silently leaves an EMPTY prelib whose functions are all missing rather than pre-fix.
  # `exe_table` is the identifier 6dd3ea468 INTRODUCED, so its absence is what makes this artifact
  # provably the older one. Measured: 0 occurrences at the pin, 3 at HEAD.
  git -C "$REPO" show 808c09609:scripts/compressor-sentinel.sh 2>/dev/null \
    | sed -n '/^[a-z_]*() {/,/^}/p' > "$D/prelib.sh"
  [ -s "$D/prelib.sh" ] || skip "pre-fix commit 808c09609 unavailable (shallow clone?)"
  ! grep -q 'exe_table' "$D/prelib.sh" || false

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
    CLIFF_PCT="${CLIFF_PCT:-60}" \
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

  # ORDERING LAW — MOST SPECIFIC FIRST, and it is load-bearing rather than tidy. Each caller's
  # format is a SUBSTRING of a longer one: the snapshot's `pid=,ppid=,rss=,pcpu=,args=` contains the
  # actuator's `pid=,ppid=,rss=,args=`, and the census's `pid=,ppid=,rss=,comm=` ends with the
  # by-executable aggregate's `rss=,comm=`. Get the order wrong and one caller silently reads
  # another's fixture file — and since those files are EMPTY in most tests, the symptom is not a red
  # test but a green one over a mechanism that never ran. The actuator arm carries NO comm column as
  # of the fnm-space fix (§5c): `ps` widens only its LAST column, so a comm requested before `args=`
  # comes back truncated to 16 characters and cannot yield a basename at all. PS_CENSUS therefore
  # feeds BOTH the census and `exe_table`, which is the point — one node-ness predicate, one fixture.
  # The routing test in §5 is the positive control that keeps this order honest from here on.
  # 2026-09-30: `exe_table gui` adds a `pid=,args=` read (the automation-switch pid list). Its
  # substring is DISJOINT from the four above — `pid=,args=` occurs in none of them, since every
  # longer format has `rss=` before `args=` — so it can sit first without shadowing anything.
  cat > "$STUB/ps" <<'SH'
#!/bin/bash
case "$*" in
  *"pid=,args="*)                  cat "$PS_ARGV"   2>/dev/null ;;
  *"pid=,ppid=,rss=,pcpu=,args="*) cat "$PS_SNAP"   2>/dev/null ;;
  *"pid=,ppid=,rss=,args="*)       cat "$PS_ACT"    2>/dev/null ;;
  *"pid=,ppid=,rss=,comm="*)       cat "$PS_CENSUS" 2>/dev/null ;;
  *"rss=,comm="*)                  cat "$PS_EXE"    2>/dev/null ;;
  *"lstart="*) st=0; case "$*" in *stat=*) st=1 ;; esac; p=""; while [ $# -gt 0 ]; do [ "$1" = "-p" ] && p="$2"; shift; done
               awk -F'\t' -v p="$p" -v s="$st" '$1 == p { if (s) print ($3 == "" ? "T" : $3) " " $2; else print $2 }' "$PS_LSTART" 2>/dev/null ;;
  *) echo "stub-ps $*" ;;
esac
SH

  : > "$D/ps.census"; : > "$D/ps.act"; : > "$D/ps.snap"; : > "$D/ps.exe"; : > "$D/ps.argv"; : > "$D/ps.lstart"
  export PS_CENSUS="$D/ps.census" PS_ACT="$D/ps.act" PS_SNAP="$D/ps.snap" PS_EXE="$D/ps.exe" \
         PS_ARGV="$D/ps.argv" PS_LSTART="$D/ps.lstart"
  chmod +x "$STUB"/pick "$STUB"/vm_stat "$STUB"/sysctl "$STUB"/ps
}

run_daemon() { # <ticks> [extra env assignments already exported by the caller]
  run env PATH="$STUB:$PATH" \
    CC_SENTINEL_LOG="$LOG" CC_SENTINEL_INTERVAL="${IV:-1}" \
    CC_SENTINEL_CENSUS_EVERY="${CENSUS_EVERY:-6}" \
    CC_SENTINEL_FOLLOWUP_N="${FUP_N:-1}" CC_SENTINEL_FOLLOWUP_SEC=1 \
    CC_SENTINEL_ACT="${ACT:-off}" CC_SENTINEL_ACT_PARENT="${PARENT:-on}" \
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
  # SUB-CLIFF by intent: 2.4M pages = 600K segs = exactly 60% of the stub limit, which since panic
  # #5 is the CLIFF (level-only, one-tick trip). Pin the cliff out so this keeps testing the regime
  # it was written for; §8 owns the other one.
  export CC_SENTINEL_CLIFF_PCT=101
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
  # Sub-cliff by intent (the ramp crests 80% of the stub limit) — §8 proves the cooldown is
  # deliberately NOT honoured up there.
  export CC_SENTINEL_CLIFF_PCT=101
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
# select_stop_targets <prev_census_pids> <rss_floor_kb> <cap>, reading `pid ppid rss comm args`.
# The ppid column belongs to the parent-breaker (§5b) and is inert here — which is itself asserted
# below, because a silently mis-indexed column would read ppid as RSS and re-admit the whole fleet.

# EXE is the `exe_table` capture the actuator takes alongside its args table. mkexe derives it from
# the SAME fixture rows the case already writes, so a case states its processes once: field 4 of an
# actuator row is argv[0], and its basename is what the real exe_table would have reported. Cases
# that need the two tables to DISAGREE (a stale pid, a recycled one) write $D/exe by hand instead.
# 2026-09-16: six fields, not four. exe_table gained a full path (5) and a PATH-PROTECTION flag (6)
# when the cohort stopped being an allow-list of the single name `node`. mkexe computes both by the
# same rules the subject uses, from the same fixture row, so a case still states its processes once.
# A fixture whose argv[0] is a BARE NAME therefore now renders as PROTECTED — which is correct and
# is the point: the subject fails closed on any process it cannot name by absolute path.
mkexe() { # <actuator rows>  → "<pid> <ppid> <rss> <exe_basename> <exe_path> <protected>"
  awk '$1 ~ /^[0-9]+$/ { b = $4; sub(/.*\//, "", b); gsub(/[[:space:]]+/, "_", b)
                         prot = 0
                         if ($4 !~ /^\//) prot = 1
                         else if ($4 ~ /^\/System\// || $4 ~ /^\/usr\/libexec\// \
                               || $4 ~ /^\/usr\/sbin\// || $4 ~ /^\/sbin\//) prot = 1
                         if (b == "claude" || b == "claude.exe") prot = 1
                         f = $4; gsub(/[[:space:]]+/, "_", f)
                         print $1, $2, $3, b, f, prot }' <<< "$1" > "$D/exe"
}

sel() { # <prev pids> <stdin lines> [exe_file]
  [ -n "${3:-}" ] || mkexe "$2"
  run env bash -c '. "$1"; select_stop_targets "$2" "$3" 102400 200' \
    _ "$D/lib.sh" "${3:-$D/exe}" "$1" <<< "$2"
}

@test "claude.exe is NEVER stopped, however big or however new" {
  sel "" "$(printf '901 1 4000000 /Users/x/.claude/bin/claude.exe --resume\n902 1 4000000 /usr/local/bin/claude serve')"
  [ -z "$output" ] || false
  # POSITIVE CONTROL: the same shape with a plain node comm IS selected, so the emptiness above is
  # the exclusion working and not the selector being broken.
  sel "" "$(printf '903 1 4000000 /opt/homebrew/bin/node dist/worker.js')"
  [ "$output" = "903 4000000 node" ] || false
}

@test "anything claude- or mcp-shaped in argv is excluded even with a node comm" {
  sel "" "$(printf '904 1 900000 /opt/homebrew/bin/node /Users/x/.claude/hooks/foo.js\n905 1 900000 /opt/homebrew/bin/node /opt/mcp-server/index.js')"
  [ -z "$output" ] || false
  # POSITIVE CONTROL — the same two rows with innocent argv ARE selected. Without it this case reads
  # green against a selector whose columns are off by one, which is exactly the mutation the ppid
  # column introduced: at the wrong offset `comm` becomes an argv word and nothing matches ^node.
  sel "" "$(printf '904 1 900000 /opt/homebrew/bin/node /w/app/hooks/foo.js\n905 1 900000 /opt/homebrew/bin/node /w/app/index.js')"
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "2" ] || false
}

@test "non-node executables are out of the cohort entirely" {
  # THE MEANING OF THIS CASE CHANGED ON 2026-09-16 AND THE ASSERTION DID NOT, which is why it is
  # kept rather than rewritten. It was written when the cohort was the allow-list `^node`, so the
  # emptiness below was that name test. The cohort is now keyed on path-protection instead (ten
  # `clang-format` processes killed this box twice while `^node` selected nothing), and what keeps
  # these two rows out today is the FIRST argument: `sel ""` passes an EMPTY previous census, i.e.
  # a daemon that has not yet observed the population, and in that window the generic arm stands
  # down and only `node` is eligible. Same verdict, different mechanism — and this case is one of
  # the two that went red and caught the window when the guard was missing.
  sel "" "$(printf '906 1 4000000 /Applications/Chrome.app/Contents/MacOS/Chrome --type=renderer\n907 1 4000000 /usr/bin/python3 train.py')"
  [ -z "$output" ] || false
  # WITH a baseline, the same two rows ARE selectable — that is the repair, stated as its own
  # assertion so the line above can never be read as "non-node is permanently out".
  sel "1 2" "$(printf '906 1 4000000 /Applications/Chrome.app/Contents/MacOS/Chrome --type=renderer\n907 1 4000000 /usr/bin/python3 train.py')"
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "2" ] || false
}

@test "the RSS floor holds: a 100 MB worker is not the burst" {
  sel "" "$(printf '908 1 102400 /opt/homebrew/bin/node w.js\n909 1 102401 /opt/homebrew/bin/node w.js')"
  [ "$output" = "909 102401 node" ] || false
}

@test "RSS is read from the RSS column, never from the ppid beside it" {
  # The floor is the one field the new ppid column sits next to, so this is its per-site mutant: a
  # 50 MB worker whose PARENT pid happens to be a large number must still fall under the floor.
  sel "" "$(printf '920 4000000 51200 /opt/homebrew/bin/node w.js')"
  [ -z "$output" ] || false
  sel "" "$(printf '920 4000000 4000000 /opt/homebrew/bin/node w.js')"   # POSITIVE CONTROL
  [ "$output" = "920 4000000 node" ] || false
}

@test "BURST COHORT: a pid present at the previous census is never stopped" {
  # The whole point of the census — stop what just appeared, not the fleet that was already working.
  sel "910 912" "$(printf '910 1 900000 /opt/homebrew/bin/node old.js\n911 1 900000 /opt/homebrew/bin/node new.js')"
  [ "$output" = "911 900000 node" ] || false
}

@test "the pid match is exact, not a substring of the census list" {
  # Without the space-delimited index test, census pid 9110 would shadow burst pid 911.
  sel "9110 9112" "$(printf '911 1 900000 /opt/homebrew/bin/node new.js')"
  [ "$output" = "911 900000 node" ] || false
}

@test "the cap is enforced — a 500-process burst yields exactly 200 stops" {
  local many=""
  for i in $(seq 1000 1499); do many="$many$i 1 900000 /opt/homebrew/bin/node w.js"$'\n'; done
  sel "" "$many"
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "200" ] || false
}

# ══ 5b. THE PARENT-BREAKER — the spawner is not in the cohort ═════════════════════════════════════
# select_break_parents <cohort_pids> <min_children> <cap> <self_pid> <self_ppid>, same stdin table.
#
# WHY THIS EXISTS AT ALL (docs/research/crash-rootcause-2026-08-09.md §7). Freezing the cohort does
# not end the storm: the 03:39 panic's 700 node procs were postcss workers of ONE `next-server`
# whose comm is not `^node`, so §5's rule cannot reach it, and it re-minted the horde across every
# 60 s cooldown. Every case below is a way that reach can fail — either by missing the spawner or by
# freezing something whose freezing costs more than the storm.
#
# 70001/70002 stand in for the daemon's own pid and its launcher. They are constants here on purpose:
# a test that passed the LIVE $$ could not tell "the guard excluded me" from "that pid was absent".

brk() { # <cohort pids> <stdin lines> [min] [cap] [exe_file]
  [ -n "${5:-}" ] || mkexe "$2"
  run env bash -c '. "$1"; select_break_parents "$2" "$3" "$4" "$5" 70001 70002' \
    _ "$D/lib.sh" "${5:-$D/exe}" "$1" "${3:-3}" "${4:-4}" <<< "$2"
}

@test "THE INCIDENT: three postcss workers name the next-server that is not in the cohort" {
  brk "40001 40002 40003" "$(printf '36923 1 3432416 /w/reso/node_modules/.bin/next-server next-server (v16.2.6)\n40001 36923 900000 /opt/homebrew/bin/node postcss.js\n40002 36923 900000 /opt/homebrew/bin/node postcss.js\n40003 36923 900000 /opt/homebrew/bin/node postcss.js')"
  [ "$output" = "36923 3 next-server" ] || false
}

@test "the threshold is a real floor: two burst children are not a spawner, three are" {
  local t; t="$(printf '36923 1 3432416 /w/reso/.bin/next-server serve\n40001 36923 900000 /opt/homebrew/bin/node p.js\n40002 36923 900000 /opt/homebrew/bin/node p.js\n40003 36923 900000 /opt/homebrew/bin/node p.js')"
  brk "40001 40002" "$t"          # only two of the three are in the cohort
  [ -z "$output" ] || false
  brk "40001 40002 40003" "$t"    # POSITIVE CONTROL: the same table, one more child
  [ "$output" = "36923 3 next-server" ] || false
}

@test "min is a SEAM that moves the verdict, not a constant the test restates" {
  local t; t="$(printf '500 1 9000 /bin/watcher run\n40001 500 900000 /opt/homebrew/bin/node p.js\n40002 500 900000 /opt/homebrew/bin/node p.js')"
  brk "40001 40002" "$t" 3
  [ -z "$output" ] || false
  brk "40001 40002" "$t" 2
  [ "$output" = "500 2 watcher" ] || false
}

@test "pid 1 is never the spawner — it is where an EXITED spawner's orphans reparent" {
  # The one bucket guaranteed to clear any threshold is the one whose 'parent' is launchd, i.e. the
  # case where the thing that minted the burst is already gone. Stopping launchd ends the box.
  #
  # THE launchd ROW IS THE POINT, not scenery. Written without it this case passed with the pid<=1
  # guard DELETED — the parent-has-a-row guard was quietly doing the work, so the assertion measured
  # a sibling (memory sibling-guard-makes-the-fixture-vacuous). A real `ps -ax` always carries pid 1;
  # with it present, this guard is the only thing standing between the actuator and `kill -STOP 1`.
  brk "40001 40002 40003" "$(printf '1 0 20000 /sbin/launchd\n40001 1 900000 /opt/homebrew/bin/node p.js\n40002 1 900000 /opt/homebrew/bin/node p.js\n40003 1 900000 /opt/homebrew/bin/node p.js')"
  [ -z "$output" ] || false
  # POSITIVE CONTROL: the identical three children under a live parent ARE attributed, launchd still
  # in the table — so the emptiness above is pid 1 being refused, not the selector being broken.
  brk "40001 40002 40003" "$(printf '1 0 20000 /sbin/launchd\n777 1 9000 /w/app/serve.sh run\n40001 777 900000 /opt/homebrew/bin/node p.js\n40002 777 900000 /opt/homebrew/bin/node p.js\n40003 777 900000 /opt/homebrew/bin/node p.js')"
  [ "$output" = "777 3 serve.sh" ] || false
}

@test "claude.exe is never the spawner, however much of the burst it owns" {
  # SIGSTOP is only reversible while something is left running to send SIGCONT, and on this box that
  # something is the operator's session. Three exclusions, three shapes, one assertion each.
  brk "40001 40002 40003" "$(printf '800 1 4000000 /Users/x/.claude/bin/claude.exe --resume\n40001 800 900000 /opt/homebrew/bin/node p.js\n40002 800 900000 /opt/homebrew/bin/node p.js\n40003 800 900000 /opt/homebrew/bin/node p.js')"
  [ -z "$output" ] || false
  brk "40001 40002 40003" "$(printf '801 1 900000 /opt/homebrew/bin/node /opt/mcp-server/index.js\n40001 801 900000 /opt/homebrew/bin/node p.js\n40002 801 900000 /opt/homebrew/bin/node p.js\n40003 801 900000 /opt/homebrew/bin/node p.js')"
  [ -z "$output" ] || false
  brk "40001 40002 40003" "$(printf '70001 1 9000 /bin/bash sentinel\n40001 70001 900000 /opt/homebrew/bin/node p.js\n40002 70001 900000 /opt/homebrew/bin/node p.js\n40003 70001 900000 /opt/homebrew/bin/node p.js')"
  [ -z "$output" ] || false   # the daemon itself
  brk "40001 40002 40003" "$(printf '70002 1 9000 /bin/bash launcher\n40001 70002 900000 /opt/homebrew/bin/node p.js\n40002 70002 900000 /opt/homebrew/bin/node p.js\n40003 70002 900000 /opt/homebrew/bin/node p.js')"
  [ -z "$output" ] || false   # …and its launcher
}

@test "a parent already IN the cohort is not counted a second time" {
  # It is about to be frozen as a child. Naming it again would report two spawners stopped over one
  # process that receives exactly one signal — the inflated-count defect, in a log read after a panic.
  brk "500 40001 40002 40003" "$(printf '500 1 900000 /opt/homebrew/bin/node orchestrator.js\n40001 500 900000 /opt/homebrew/bin/node p.js\n40002 500 900000 /opt/homebrew/bin/node p.js\n40003 500 900000 /opt/homebrew/bin/node p.js')"
  [ -z "$output" ] || false
  # POSITIVE CONTROL: the same node orchestrator, this time NOT in the cohort (it predates the burst,
  # so the census spared it) — which is precisely the spawner this mechanism exists to reach.
  brk "40001 40002 40003" "$(printf '500 1 900000 /opt/homebrew/bin/node orchestrator.js\n40001 500 900000 /opt/homebrew/bin/node p.js\n40002 500 900000 /opt/homebrew/bin/node p.js\n40003 500 900000 /opt/homebrew/bin/node p.js')"
  [ "$output" = "500 3 node" ] || false
}

@test "a parent with no row of its own is never named — a comm cannot be fabricated" {
  brk "40001 40002 40003" "$(printf '40001 999 900000 /opt/homebrew/bin/node p.js\n40002 999 900000 /opt/homebrew/bin/node p.js\n40003 999 900000 /opt/homebrew/bin/node p.js')"
  [ -z "$output" ] || false
}

@test "TWO spawners are both named, ranked by how much of the burst each owns" {
  # The case a unanimity rule ('the cohort shares ONE parent') answers with silence while both
  # servers keep minting. Ranking, not first-seen: the bigger spawner is emitted LAST by ps here.
  brk "40001 40002 40003 40004 40005" "$(printf '501 1 9000 /w/a/.bin/next-server a\n40001 501 900000 /opt/homebrew/bin/node p.js\n40002 501 900000 /opt/homebrew/bin/node p.js\n40003 502 900000 /opt/homebrew/bin/node p.js\n40004 502 900000 /opt/homebrew/bin/node p.js\n40005 502 900000 /opt/homebrew/bin/node p.js\n502 1 9000 /w/b/.bin/next-server b')" 2
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "2" ] || false
  [ "$(echo "$output" | head -1)" = "502 3 next-server" ] || false
  [ "$(echo "$output" | tail -1)" = "501 2 next-server" ] || false
}

@test "the cap keeps the BIGGEST spawners, not the ones ps happened to emit first" {
  local t="" c=""
  # Four spawners owning 2,3,4,5 of the burst, emitted smallest-first so a line cut takes the wrong two.
  for s in 1:2 2:3 3:4 4:5; do
    local p="${s%%:*}" n="${s##*:}" i
    t="$t$((600 + p)) 1 9000 /w/$p/.bin/next-server s"$'\n'
    for i in $(seq 1 "$n"); do
      t="$t$((41000 + p * 100 + i)) $((600 + p)) 900000 /opt/homebrew/bin/node p.js"$'\n'
      c="$c $((41000 + p * 100 + i))"
    done
  done
  brk "$c" "$t" 2 2
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "2" ] || false
  [ "$(echo "$output" | head -1)" = "604 5 next-server" ] || false
  [ "$(echo "$output" | tail -1)" = "603 4 next-server" ] || false
}

@test "the cohort pid match is exact, not a substring" {
  # Cohort 400010 must not credit child 40001 to its parent — the same space-delimited index law §5
  # already carries for the census list, asserted here because it is a SECOND, independent call site.
  brk "400010 400020 400030" "$(printf '505 1 9000 /w/a/.bin/next-server a\n40001 505 900000 /opt/homebrew/bin/node p.js\n40002 505 900000 /opt/homebrew/bin/node p.js\n40003 505 900000 /opt/homebrew/bin/node p.js')"
  [ -z "$output" ] || false
}

@test "an empty cohort names nobody — no burst, no spawner" {
  brk "" "$(printf '506 1 9000 /w/a/.bin/next-server a\n40001 506 900000 /opt/homebrew/bin/node p.js\n40002 506 900000 /opt/homebrew/bin/node p.js\n40003 506 900000 /opt/homebrew/bin/node p.js')"
  [ -z "$output" ] || false
}

# ── the actuator end to end ───────────────────────────────────────────────────────────────────────

@test "the actuator is DISARMED by default, and says so in the snapshot" {
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  run_daemon 3
  grep -q 'actuator: DISARMED' "$SNAPLOG" || false
  ! grep -q 'SIGSTOP pid=' "$SNAPLOG" || false
  ! grep -q 'SIGSTOP parent pid=' "$SNAPLOG" || false
  ! grep -q 'parent-break' "$SNAPLOG" || false
}

@test "CC_SENTINEL_ACT=stop reaches the actuator branch (and signals nothing here)" {
  # The ps stub hands back pids in the 999xxx range, which cannot exist — macOS pids wrap below
  # 100000 — so `kill -STOP` fails and this proves the branch is WIRED without signalling anything
  # on the real machine. That impossibility is the reason this test is safe to run at all.
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  printf '999901 1 900000 /opt/homebrew/bin/node w.js\n' > "$PS_ACT"
  # The exe table names it. Without this row the pid is unidentifiable and the actuator selects
  # NOTHING — the fail-safe §5c pins directly. CENSUS_EVERY is lifted past the run so no census
  # takes place: these pids must read as burst, and a census would file them as incumbents.
  printf '999901 1 900000 /opt/homebrew/bin/node\n' > "$PS_CENSUS"
  CENSUS_EVERY=99 ACT=stop run_daemon 3
  grep -q 'actuator: SIGSTOPped 0 process' "$SNAPLOG" || false
  ! grep -q 'DISARMED' "$SNAPLOG" || false
  # THE ROUTING CONTROL. `SIGSTOPped 0` is also what a run reads when the actuator's `ps` was routed
  # to another caller's (empty) fixture, so it cannot on its own prove the table arrived. The count
  # of SELECTED procs can: it is 1 here and would be 0 if PS_ACT never reached the selector.
  grep -qF 'parent-break none — no eligible parent owns >= 3 of the 1 selected burst procs' "$SNAPLOG" || false
}

@test "END TO END: the spawner is identified from the trip's own ps table" {
  # The full chain in one run — ps routing → cohort selection → parent attribution → kill attempt →
  # verdict — against three impossible-pid children of one impossible-pid next-server. Nothing on
  # this machine can be signalled by it, and `0 of 1 spawner` is the proof the kill was attempted.
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  printf '999900 1 3432416 /w/reso/node_modules/.bin/next-server next-server\n999901 999900 900000 /opt/homebrew/bin/node postcss.js\n999902 999900 900000 /opt/homebrew/bin/node postcss.js\n999903 999900 900000 /opt/homebrew/bin/node postcss.js\n' > "$PS_ACT"
  printf '999900 1 3432416 /w/reso/node_modules/.bin/next-server\n999901 999900 900000 /opt/homebrew/bin/node\n999902 999900 900000 /opt/homebrew/bin/node\n999903 999900 900000 /opt/homebrew/bin/node\n' > "$PS_CENSUS"
  CENSUS_EVERY=99 ACT=stop run_daemon 3
  grep -qF 'actuator: parent-break SIGSTOPped 0 of 1 spawner(s), each owning >= 3 of the 3 selected burst procs' "$SNAPLOG" || false
  grep -q 'actuator: SIGSTOPped 0 process' "$SNAPLOG" || false
}

@test "CC_SENTINEL_ACT_PARENT=off is a real opt-out, and the snapshot says which" {
  # The opt-out must be legible in the record: a trip that broke no parent because it was told not to
  # is a different event from one that found none, and a post-mortem reads only this log.
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  printf '999900 1 3432416 /w/reso/node_modules/.bin/next-server next-server\n999901 999900 900000 /opt/homebrew/bin/node postcss.js\n999902 999900 900000 /opt/homebrew/bin/node postcss.js\n999903 999900 900000 /opt/homebrew/bin/node postcss.js\n' > "$PS_ACT"
  ACT=stop PARENT=off run_daemon 3
  grep -qF 'actuator: parent-break off (CC_SENTINEL_ACT_PARENT=off)' "$SNAPLOG" || false
  ! grep -q 'SIGSTOP parent pid=' "$SNAPLOG" || false
  grep -q 'actuator: SIGSTOPped 0 process' "$SNAPLOG" || false   # the cohort arm is untouched by it
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

# ══ 7. SNAPSHOT ATTRIBUTION — rank first, then name ══════════════════════════════════════════════
# The first shape of this snapshot fired 18 times across the 2026-08-06/07 incident and could not say
# what consumed the memory in EITHER direction (machine-lag-and-kitty-2026-08-06.md §7-bis(b)): an
# argv list cut at `head -80` (truncated in 16 of 18 trips) beside a COMM-only top-30, which renders
# every Node workload as `node`. Joined by pid, 1-8 of the LARGEST rows stayed unidentified at every
# trip, and two successive analyses read a confident "tsc = 0" off it that was an artifact of the
# instrument. These are the tests that stop each half coming back.

# top_by_rss <n> <argv_max> — stdin is `ps -Awwo pid=,ppid=,rss=,pcpu=,args=`
tbr() { run env bash -c '. "$1"; top_by_rss "$2" "$3"' _ "$D/lib.sh" "$1" "$2" <<< "$3"; }

@test "the bound is a RANK, not a line cut: the biggest row is found wherever ps emitted it" {
  # THE control that separates this from `head -N`. The largest process is emitted LAST, so a line
  # cut returns precisely the two rows the post-mortem does not need and drops the one it does.
  tbr 2 0 "$(printf '100 1 200000 0.0 node small.js\n200 1 300000 0.0 node mid.js\n300 1 900000 0.0 node huge.js\n')"
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "2" ] || false
  echo "$output" | head -1 | grep -q 'huge.js' || false      # ranked first, though emitted last
  echo "$output" | tail -1 | grep -q 'mid.js' || false
  ! echo "$output" | grep -q 'small.js' || false             # the SMALLEST is what falls off
}

@test "full argv distinguishes two workloads that COMM alone renders identically" {
  # The second blindness, stated as its own case: under `-o comm` both of these are `node`, which is
  # exactly why no count of tsc — zero or four — could be read off the old log.
  tbr 2 0 "$(printf '400 1 1480000 5.0 node /w/wt-n16-gates/node_modules/typescript/bin/tsc --noEmit\n401 1 3432416 0.0 node /w/reso/node_modules/.bin/next-server\n')"
  echo "$output" | grep -q 'tsc --noEmit' || false
  echo "$output" | grep -q 'next-server' || false
  [ "$(echo "$output" | grep -c ' node ')" = "2" ] || false  # …and both still show the interpreter
}

@test "the argv cap STAMPS what it dropped, and 0 means uncapped" {
  # A per-ROW tail cut is categorically not the head -80 defect: that dropped whole processes in
  # silence, this shortens one NAMED row and says by how much. Agent briefs ride in argv, so the cap
  # is what keeps 13 snapshots per trip inside a 25 MiB rotation.
  local long; long="$(printf 'node worker.js %s' "$(printf 'x%.0s' $(seq 1 500))")"
  tbr 1 40 "$(printf '500 1 900000 0.0 %s\n' "$long")"
  echo "$output" | grep -q 'node worker.js' || false          # the identity survives the cut
  echo "$output" | grep -qE '…\[\+[0-9]+ chars\]' || false     # …and the cut announces itself
  # POSITIVE CONTROL: the same row uncapped carries the whole tail and no stamp, so the assertion
  # above is the cap working rather than the renderer always printing that marker.
  tbr 1 0 "$(printf '500 1 900000 0.0 %s\n' "$long")"
  ! echo "$output" | grep -q 'chars\]' || false
  [ "$(echo "$output" | grep -c 'xxxxx')" = "1" ] || false
}

@test "argv is taken VERBATIM — internal whitespace is not rewritten by a field rejoin" {
  # Rejoining $5..$NF collapses runs of spaces, which silently edits the forensic record. A path with
  # a double space is the cheapest thing that catches it.
  tbr 1 0 "$(printf '600 1 900000 0.0 /Applications/My  App.app/Contents/MacOS/My  App --flag\n')"
  echo "$output" | grep -q 'My  App.app' || false
  echo "$output" | grep -q 'MacOS/My  App --flag' || false
}

@test "a %CPU column a locale renders as 0,0 does not drop every row on the floor" {
  # The fourth column is matched as any non-blank rather than [0-9.]+ precisely so a decimal-comma
  # locale cannot empty the whole section while looking rendered.
  tbr 1 0 "$(printf '700 1 900000 0,0 node w.js\n')"
  echo "$output" | grep -q 'node w.js' || false
  # NEGATIVE CONTROL: a genuine header line still has no place in the output.
  tbr 2 0 "$(printf '  PID  PPID    RSS %%CPU ARGS\n700 1 900000 0.0 node w.js\n')"
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "1" ] || false
}

@test "rss_by_exe sees the swarm the ranked section cannot: many small workers, one big total" {
  # Forty workers at 180 MB each outweigh any single row and appear in none of them. Removing the old
  # unranked list without this would have been a net loss of exactly this shape.
  local many=""
  for i in $(seq 1 40); do many="$many"'184320 /opt/homebrew/bin/node'$'\n'; done
  many="$many"'900000 /Applications/Dia.app/Contents/MacOS/Dia'$'\n'
  run env bash -c '. "$1"; rss_by_exe 2' _ "$D/lib.sh" <<< "$many"
  echo "$output" | head -1 | grep -qE '7200\.0 MB +x40 +node' || false   # 40 x 180 MB ranks first
  echo "$output" | tail -1 | grep -qE 'x1 +Dia' || false
}

@test "an executable path containing spaces groups whole — comm is the trailing field" {
  # `…/Google Chrome for Testing` is a real path on this box. Splitting on whitespace would shard one
  # browser into four fabricated executables.
  run env bash -c '. "$1"; rss_by_exe 3' _ "$D/lib.sh" \
    <<< "$(printf '189488 /Users/x/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing\n4816 /Users/x/Helpers/chrome_crashpad_handler\n')"
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "2" ] || false
  echo "$output" | head -1 | grep -q 'x1    Google Chrome for Testing$' || false
}

@test "END TO END: a trip snapshot names the workload, and neither old blind section survives" {
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  printf '43687 1 1480000 92.0 node /w/wt-n16-gates/node_modules/typescript/bin/tsc --noEmit\n24847 1 3432416 0.1 next-server (v16.2.12)\n' > "$PS_SNAP"
  printf '1480000 /opt/homebrew/bin/node\n3432416 next-server (v16.2.12)\n' > "$PS_EXE"
  run_daemon 3
  [ -f "$SNAPLOG" ] || false
  grep -q -- '--- top 30 by RSS, full argv' "$SNAPLOG" || false
  grep -q 'tsc --noEmit' "$SNAPLOG" || false                    # the question §7-bis could not answer
  grep -q 'next-server (v16.2.12)' "$SNAPLOG" || false
  grep -q -- '--- RSS by executable, top 15' "$SNAPLOG" || false
  grep -q -- '--- vm_stat ---' "$SNAPLOG" || false              # unchanged section, still there
  # The two defective sections are GONE by name, not merely widened.
  ! grep -q 'head -80' "$SNAPLOG" || false
  ! grep -q 'top by memory' "$SNAPLOG" || false
}

@test "the follow-up samples carry argv too — the ramp watch was the blindest part of the record" {
  # Twelve COMM-only samples used to follow every trip, so a process BORN after the trip appeared
  # nowhere in the record at all.
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  printf '43687 1 1480000 92.0 node /w/wt/node_modules/typescript/bin/tsc --noEmit\n' > "$PS_SNAP"
  FUP_N=3 run_daemon 6
  grep -q -- '--- follow-up 1/3' "$SNAPLOG" || false
  [ "$(grep -c -- '--- top 10 by RSS' "$SNAPLOG")" -ge 1 ] || false   # the tighter follow-up rank
  [ "$(grep -c 'tsc --noEmit' "$SNAPLOG")" -ge 2 ] || false           # trip snapshot AND a follow-up
}

@test "ps unreadable renders NO ROWS explicitly — an empty section would read as an idle box" {
  # Same contract the sysctl readers hold: "could not measure" must never render as the healthy
  # value. Here the healthy-looking value is a section with nothing under it.
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  : > "$PS_SNAP"; : > "$PS_EXE"
  run_daemon 3
  grep -q 'NO ROWS — ps was unreadable' "$SNAPLOG" || false
  # POSITIVE CONTROL: the identical run with ps readable renders rows and no such marker, so the
  # assertion above is the absence being reported and not the marker being printed unconditionally.
  # mkstubs, not just rm — it rewinds the stub's tick counter, and without that the second run
  # resumes past the ramp on a flat sequence, never trips, and the control passes vacuously.
  rm -f "$SNAPLOG" "$LOG" "$PAGE"
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  printf '43687 1 1480000 92.0 node tsc --noEmit\n' > "$PS_SNAP"
  printf '1480000 /opt/homebrew/bin/node\n' > "$PS_EXE"
  run_daemon 3
  ! grep -q 'NO ROWS' "$SNAPLOG" || false
  grep -q 'tsc --noEmit' "$SNAPLOG" || false
}

@test "a non-numeric snapshot seam is REFUSED at startup, never rendered as an empty section" {
  # awk turns `-v n=abc` into 0, and n=0 renders a section with a header and nothing under it — a
  # typo would silently restore the blindness. Each seam is asserted separately: one shared loop can
  # be right for the variable it was tested with and never read the other three.
  mkstubs 800000 0 0
  for v in CC_SENTINEL_SNAP_TOPN CC_SENTINEL_SNAP_TOPN_FUP CC_SENTINEL_SNAP_ARGV_MAX CC_SENTINEL_SNAP_AGG_N; do
    run env PATH="$STUB:$PATH" CC_SENTINEL_LOG="$LOG" "$v=abc" bash "$S" --ticks 1
    [ "$status" -eq 64 ] || false
    echo "$output" | grep -q "$v" || false
  done
  # POSITIVE CONTROL: the same run with a numeric value proceeds, so 64 above is the guard and not
  # the daemon being broken by the presence of the variable.
  run env PATH="$STUB:$PATH" CC_SENTINEL_LOG="$LOG" CC_SENTINEL_SNAP_TOPN=5 bash "$S" --ticks 1
  [ "$status" -eq 0 ] || false
}

# ── PANIC ATTRIBUTION (master 66ef300dd0b4 — "the next death is attributable") ───
# A kernel panic writes NO crash row: the ledger's writer is a daemon the panic kills, so
# claude-crashes.jsonl's last row predates panic #6 by 15 minutes and 132 of 171 rows read
# cause:"abrupt-unknown". The kernel meanwhile writes the answer into a *.panic report that nothing
# in this repo has ever parsed — and macOS is rotating those away (3 of 5 remain). These cases pin
# the reader against BOTH real report shapes, fixtured, never against /Library.
#
# Fixtures are byte-shaped like the live reports, verified against them on 2026-08-09:
#   panic-full      → carries `"procname":"<comm>"` runs  → a census
#   panic-base+socd → carries the verdict and NO table    → census_source must say so
panic_fixture_full() { # <dir> <name>
  mkdir -p "$1"
  { printf '{"bug_type":"210","timestamp":"2026-08-09 03:41:24.00 -0700"}\n'
    printf '{"panicString":"panic(cpu 3): watchdog timeout: no checkins from watchdogd in 94 seconds\\n'
    printf 'Compressor Info: 32%% of compressed pages limit (OK) and 100%% of segments limit (BAD) with 68 swapfiles and OK swap space\\n"'
    local i=0
    while [ "$i" -lt 7 ]; do printf ',"p%s":{"procname":"node","pageFaults":1}' "$i"; i=$((i+1)); done
    printf ',"q0":{"procname":"claude.exe","pageFaults":1}'
    printf ',"q1":{"procname":"bash","pageFaults":1}}\n'
  } > "$1/$2"
}
panic_fixture_base() { # <dir> <name> — verdict, but NO process table
  mkdir -p "$1"
  { printf '{"bug_type":"210","timestamp":"2026-08-09 04:18:59.00 -0700"}\n'
    printf '{"panicString":"panic(cpu 3): watchdog timeout\\n'
    printf 'Compressor Info: 32%% of compressed pages limit (OK) and 100%% of segments limit (BAD) with 66 swapfiles and OK swap space\\n"}\n'
  } > "$1/$2"
}
scan() { CC_PANIC_DIRS="$D/panics" CC_PANIC_LEDGER="$D/panic.jsonl" bash "$S" --panic-scan; }

@test "panic reader: extracts the kernel's own kill-axis verdict" {
  panic_fixture_full "$D/panics" "panic-full-2026-08-09-034124.0002.panic"
  run scan
  [ "$status" -eq 0 ] || false
  jq -e '.verdict | test("100% of segments limit \\(BAD\\)")' "$D/panic.jsonl" >/dev/null || false
  jq -e '.panicked_at == "2026-08-09 03:41:24.00 -0700"' "$D/panic.jsonl" >/dev/null || false
}

# The culprit, counted by the kernel. This is the whole argument that the CC fleet is the VICTIM
# and a dev-server worker pool is the killer — recoverable in one command instead of the multi-hour
# manual trace it took the first time.
@test "panic reader: censuses the process table by procname, ranked" {
  panic_fixture_full "$D/panics" "panic-full-2026-08-09-034124.0002.panic"
  run scan
  jq -e '.census_source == "report-process-table"' "$D/panic.jsonl" >/dev/null || false
  jq -e '.census | startswith("node=7")' "$D/panic.jsonl" >/dev/null || false
  jq -e '.census | test("claude.exe=1")' "$D/panic.jsonl" >/dev/null || false
}

# The negative control, and the reason census_source exists. The FIRST draft of this reader counted
# every quoted token and "found" a process table in a panic-base+socd report that provably has none
# — census_source read `report-process-table` over a census of JSON keys (bug_type=2 socId=1). It
# got past a reading of the code; only opening the real artifact caught it.
@test "panic reader: a report with NO process table says so — never a census of JSON keys" {
  panic_fixture_base "$D/panics" "panic-base+socd-2026-08-09-041859.000.panic"
  run scan
  [ "$status" -eq 0 ] || false
  jq -e '.census_source == "absent-no-process-table"' "$D/panic.jsonl" >/dev/null || false
  jq -e '.census == ""' "$D/panic.jsonl" >/dev/null || false
  jq -e '.verdict | test("segments limit")' "$D/panic.jsonl" >/dev/null || false   # verdict still read
  ! jq -e '.census | test("bug_type")' "$D/panic.jsonl" >/dev/null || false
}

# Truncation does not degrade the ranking, it REVERSES it: measured against the live 6.5 MB report,
# a 2 MB bound returned `bash=33 node=21` and named the wrong culprit. A reversed culprit is worse
# than no culprit, so the bound being reached is DECLARED.
@test "panic reader: a truncated read is declared, never a quietly biased ranking" {
  panic_fixture_full "$D/panics" "panic-full-2026-08-09-034124.0002.panic"
  export CC_PANIC_HEAD_BYTES=400
  run scan
  jq -e '.census | test("node")' "$D/panic.jsonl" >/dev/null || false   # positive control: a census WAS taken
  jq -e '.census_source == "report-process-table-TRUNCATED"' "$D/panic.jsonl" >/dev/null || false
}

@test "panic reader: the same panic is recorded ONCE, however often the daemon restarts" {
  panic_fixture_full "$D/panics" "panic-full-2026-08-09-034124.0002.panic"
  scan >/dev/null 2>&1; scan >/dev/null 2>&1; scan >/dev/null 2>&1
  [ "$(grep -c . "$D/panic.jsonl")" -eq 1 ] || false
}

@test "panic reader: a NEW panic after a recorded one is appended (the paired act-rule)" {
  panic_fixture_full "$D/panics" "panic-full-2026-08-09-034124.0002.panic"
  scan >/dev/null 2>&1
  sleep 1; panic_fixture_base "$D/panics" "panic-base+socd-2026-08-09-041859.000.panic"
  scan >/dev/null 2>&1
  [ "$(grep -c . "$D/panic.jsonl")" -eq 2 ] || false
}

# "No panic has happened" and "I could not look" are DIFFERENT facts. One exit code for both is
# what makes a blind sensor read healthy (memory: sensor-default-off-makes-blindness-the-shipping-path).
@test "panic reader: no panic report is exit 0; an unreadable directory is exit 3" {
  mkdir -p "$D/panics"
  run scan
  [ "$status" -eq 0 ] || false
  [ ! -f "$D/panic.jsonl" ] || false
  CC_PANIC_DIRS="$D/nonexistent" CC_PANIC_LEDGER="$D/panic.jsonl" run bash "$S" --panic-scan
  [ "$status" -eq 3 ] || false
}

# A reader for the LAST death must never cost the evidence for the NEXT one.
@test "panic reader: a failing scan cannot stop the sensor from starting" {
  export CC_PANIC_DIRS="$D/nonexistent"
  run env CC_SENTINEL_LOG="$D/s.jsonl" bash "$S" --once
  [ "$status" -eq 0 ] || false
  [ -s "$D/s.jsonl" ] || false     # positive control: the tick still produced a row
}

@test "panic reader: CC_PANIC_SCAN=off skips it entirely" {
  panic_fixture_full "$D/panics" "panic-full-2026-08-09-034124.0002.panic"
  export CC_PANIC_DIRS="$D/panics" CC_PANIC_LEDGER="$D/panic.jsonl" CC_PANIC_SCAN=off
  run env CC_SENTINEL_LOG="$D/s.jsonl" bash "$S" --once
  [ ! -f "$D/panic.jsonl" ] || false
}


# ══ 5c. THE fnm-SPACE BLINDNESS — the census the actuator was reading was structurally 0 ══════════
#
# THE DEFECT, in two different shapes, in the two different `ps` streams this file runs.
# `ps` widens only its LAST column, so exactly one of `comm=` and `args=` can be complete:
#
#   · census, `pid=,ppid=,rss=,comm=` — comm IS last, so its value is COMPLETE and its SPACES SPLIT.
#     `$4` of `/Users/…/Library/Application Support/fnm/…/bin/node` is `/Users/…/Library/Application`,
#     whose basename is `Application`, which fails `^node`. Every fnm-installed node was dropped.
#     Measured on the live box 2026-08-11: census read 0 while 4 node processes were resident, and
#     the research measured 12,105 dropped rows of 55,631.
#
#   · the actuator, `pid=,ppid=,rss=,comm=,args=` — comm is NOT last, so `ps` truncates it to a
#     FIXED 16 characters (`/Users/chrisren/`, `/Library/Applica`, `endpointsecurity` — all exactly
#     16, measured). There the basename was not merely split, it was ABSENT: no real node install
#     has a path under 16 characters, so the cohort test could match nothing but a process whose
#     comm was literally the 4-character string `node`. argv[0] is no escape — it carries the same
#     spaced path and splits identically.
#
# Hence the two-table shape under test: the NAME comes from the comm-last read, and `args=` keeps
# the last column in the actuator's read so every exclusion still sees a complete argv.

precensus() { # <PS_CENSUS contents> — the census as it stood BEFORE this diff
  [ -n "${PS_CENSUS:-}" ] || mkstubs 0 0 0
  printf '%s\n' "$1" > "$PS_CENSUS"
  run env PATH="$STUB:$PATH" bash -c '. "$1"; census' _ "$D/prelib.sh"
}
nowcensus() { # <PS_CENSUS contents> — the census as it stands now
  [ -n "${PS_CENSUS:-}" ] || mkstubs 0 0 0
  printf '%s\n' "$1" > "$PS_CENSUS"
  run env PATH="$STUB:$PATH" bash -c '. "$1"; census' _ "$D/lib.sh"
}

FNM='/Users/x/Library/Application Support/fnm/node-versions/v22.21.1/installation/bin/node'

@test "CENSUS SITE: an fnm node is COUNTED — and the pre-fix census read the same fixture as 0" {
  local rows; rows="$(printf '1001 1 900000 %s\n1002 1 900000 %s\n1003 1 900000 /opt/homebrew/bin/node' "$FNM" "$FNM")"
  # THE CONTROL FIRST, so a green below cannot be a test that never had a way to fail. The pre-fix
  # census sees ONLY the homebrew row: the two fnm rows basename to `Application`.
  precensus "$rows"
  [ "${output%%|*}" = "1 1 878" ] || false
  nowcensus "$rows"
  [ "${output%%|*}" = "3 3 2636" ] || false
  [ "${output#*|}" = " 1001 1002 1003" ] || false
}

@test "CENSUS SITE: a basename containing spaces stays ONE field and never counts as node" {
  # `Razer Elevation Service` is 41 of 1224 live rows. Emitted raw it would make exe_table's own 4th
  # field ambiguous for every consumer — the same defect one layer down.
  nowcensus "$(printf '1010 1 900000 /Library/Application Support/Razer/Razer Elevation Service\n1011 1 900000 %s' "$FNM")"
  [ "${output%%|*}" = "1 1 878" ] || false          # the NUMBERS are still node-only: 1 proc, not 2
  # THE ROSTER IS NOT. Since 2026-09-16 it lists every unprotected process over the floor, because
  # its one consumer is the "new since the last census" gate and a roster that named only node left
  # that gate inert for every other executable — which is how ten clang-format processes read as
  # freshly-spawned forever. A wider roster can only EXCLUDE more from the cohort, never less.
  [ "${output#*|}" = " 1010 1011" ] || false
}

@test "SELECTOR SITE: an fnm node is SEEN — the name comes from exe_table, not the args table" {
  # exe_table is RUN here rather than hand-written: the point of the case is that it resolves a comm
  # whose path contains spaces, which no field-split of the actuator's own table can do.
  mkstubs 0 0 0
  printf '1001 1 900000 %s\n' "$FNM" > "$PS_CENSUS"
  run env PATH="$STUB:$PATH" bash -c '. "$1"; exe_table' _ "$D/lib.sh"
  # SIX fields since 2026-09-16: pid ppid rss basename FULL_PATH PROTECTED. The full path is how the
  # protection flag is computed, and the spaces in this very path are why it is underscore-collapsed
  # the same way the basename is — field 6 must stay readable as $6 whatever the path contains.
  [ "$output" = "1001 1 900000 node ${FNM// /_} 0" ] || false
  printf '%s\n' "$output" > "$D/exe.fnm"
  sel "" "$(printf '1001 1 900000 %s /w/app/worker.js' "$FNM")" "$D/exe.fnm"
  [ "$output" = "1001 900000 node" ] || false
}

@test "SELECTOR SITE: the pre-fix selector could not see that same process — 16-char truncation" {
  # The pre-fix stdin format, spelled as REAL ps emits it: comm truncated to 16 chars and padded,
  # then the full argv. `$4` is `/Users/x/Library` — basename `Library`, not `^node`.
  run env bash -c '. "$1"; select_stop_targets "" 102400 200' _ "$D/prelib.sh" \
    <<< "$(printf '1001 1 900000 /Users/x/Library %s /w/app/worker.js' "$FNM")"
  [ -z "$output" ] || false
  # POSITIVE CONTROL — the pre-fix selector is not simply broken: a SHORT comm it can basename works.
  run env bash -c '. "$1"; select_stop_targets "" 102400 200' _ "$D/prelib.sh" \
    <<< '1002 1 900000 /opt/homebrew/bin/node /w/app/worker.js'
  [ "$output" = "1002 900000 node" ] || false
}

@test "SELECTOR SITE: mcp is excluded as a CLASS, including the spelling the substring test missed" {
  # `modelcontextprotocol` contains no `mcp` substring at all, so the pre-fix `args ~ /mcp/` would
  # have handed it to SIGSTOP the moment the cohort test started working — this is the B.3 hazard
  # that made the class test non-optional in the same diff as the census repair.
  sel "" "$(printf '1101 1 900000 /opt/homebrew/bin/node /w/@modelcontextprotocol/server/index.js\n1102 1 900000 /opt/homebrew/bin/node /w/mcp-server/index.js\n1103 1 900000 /opt/homebrew/bin/node /w/tools/mcp/run.js\n1104 1 900000 /opt/homebrew/bin/node --title=agent_mcp w.js')"
  [ -z "$output" ] || false
  # POSITIVE CONTROL — four innocent rows of the SAME shape ARE selected, so the emptiness above is
  # the exclusion firing and not the selector being inert.
  sel "" "$(printf '1101 1 900000 /opt/homebrew/bin/node /w/server/index.js\n1102 1 900000 /opt/homebrew/bin/node /w/build/index.js\n1103 1 900000 /opt/homebrew/bin/node /w/tools/run.js\n1104 1 900000 /opt/homebrew/bin/node --title=agent w.js')"
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "4" ] || false
  # AND THE CONTROL ON THE PRE-FIX RULE: the old substring test really did miss the first spelling.
  run env bash -c '. "$1"; select_stop_targets "" 102400 200' _ "$D/prelib.sh" \
    <<< '1101 1 900000 /opt/homebrew/bin/node /w/@modelcontextprotocol/server/index.js'
  [ "$output" = "1101 900000 node" ] || false
}

@test "RECYCLE GUARD: a pid the two tables disagree about on PPID is never a target" {
  # The hazard the second read opens. Both tables carry ppid, they are taken back-to-back, so a
  # healthy process agrees trivially and a pid reused between the reads has to reproduce its
  # predecessor's parent to get through.
  printf '1201 4242 900000 node /opt/homebrew/bin/node 0\n' > "$D/exe.mm"
  sel "" '1201 7 900000 /opt/homebrew/bin/node /w/app/w.js' "$D/exe.mm"
  [ -z "$output" ] || false
  # POSITIVE CONTROL — the identical row with the ppids AGREEING is selected.
  printf '1201 7 900000 node /opt/homebrew/bin/node 0\n' > "$D/exe.ok"
  sel "" '1201 7 900000 /opt/homebrew/bin/node /w/app/w.js' "$D/exe.ok"
  [ "$output" = "1201 900000 node" ] || false
}

@test "RECYCLE GUARD: a pid absent from the exe table is never a target" {
  : > "$D/exe.empty"
  sel "" '1202 1 900000 /opt/homebrew/bin/node /w/app/w.js' "$D/exe.empty"
  [ -z "$output" ] || false
}

@test "BREAK-PARENTS SITE: a spawner the exe table cannot name is PROTECTED, not frozen" {
  # UNIDENTIFIABLE ⇒ NEVER ACTED ON. Here the ignorance is worse than in the cohort: without a name
  # the claude/claude.exe test cannot be applied at all, so the only safe reading of an unnamed
  # parent is that it might be one. It costs a missed spawner; the converse costs the session.
  printf '40001 36923 900000 node\n40002 36923 900000 node\n40003 36923 900000 node\n' > "$D/exe.noparent"
  brk "40001 40002 40003" "$(printf '36923 1 3432416 /w/reso/node_modules/.bin/next-server next-server\n40001 36923 900000 /opt/homebrew/bin/node p.js\n40002 36923 900000 /opt/homebrew/bin/node p.js\n40003 36923 900000 /opt/homebrew/bin/node p.js')" 3 4 "$D/exe.noparent"
  [ -z "$output" ] || false
  # POSITIVE CONTROL — the same table with the spawner NAMED yields the incident's own verdict.
  printf '36923 1 3432416 next-server /w/reso/node_modules/.bin/next-server 0\n40001 36923 900000 node /opt/homebrew/bin/node 0\n40002 36923 900000 node /opt/homebrew/bin/node 0\n40003 36923 900000 node /opt/homebrew/bin/node 0\n' > "$D/exe.named"
  brk "40001 40002 40003" "$(printf '36923 1 3432416 /w/reso/node_modules/.bin/next-server next-server\n40001 36923 900000 /opt/homebrew/bin/node p.js\n40002 36923 900000 /opt/homebrew/bin/node p.js\n40003 36923 900000 /opt/homebrew/bin/node p.js')" 3 4 "$D/exe.named"
  [ "$output" = "36923 3 next-server" ] || false
}

@test "BREAK-PARENTS SITE: a modelcontextprotocol spawner is protected by the class test" {
  # SIX-FIELD FIXTURE, and the reason is a vacuous pass this diff created and then removed: with a
  # four-field row the protection flag reads EMPTY, fails closed, and the spawner is spared for a
  # reason that has nothing to do with the mcp class test this case exists to prove. It stayed green
  # throughout and proved nothing (memory: sibling-guard-makes-the-fixture-vacuous).
  printf '36924 1 3432416 node /opt/homebrew/bin/node 0\n40001 36924 900000 node /opt/homebrew/bin/node 0\n40002 36924 900000 node /opt/homebrew/bin/node 0\n40003 36924 900000 node /opt/homebrew/bin/node 0\n' > "$D/exe.mcp"
  brk "40001 40002 40003" "$(printf '36924 1 3432416 /opt/homebrew/bin/node /w/@modelcontextprotocol/server/i.js\n40001 36924 900000 /opt/homebrew/bin/node p.js\n40002 36924 900000 /opt/homebrew/bin/node p.js\n40003 36924 900000 /opt/homebrew/bin/node p.js')" 3 4 "$D/exe.mcp"
  [ -z "$output" ] || false
}

# ══ 5d. OBSERVE — the rung that lets a predicate change be watched before it acts ═════════════════

@test "CC_SENTINEL_ACT=observe selects and logs a would-stop, and signals NOTHING" {
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  printf '999901 1 900000 /opt/homebrew/bin/node w.js\n' > "$PS_ACT"
  printf '999901 1 900000 /opt/homebrew/bin/node\n' > "$PS_CENSUS"
  CENSUS_EVERY=99 ACT=observe run_daemon 3
  grep -qF 'WOULD-STOP pid=999901 rss_kb=900000 comm=node' "$SNAPLOG" || false
  grep -qF 'actuator: WOULD have SIGSTOPped 1 process(es)' "$SNAPLOG" || false
  ! grep -q 'DISARMED' "$SNAPLOG" || false
  # It is NOT the armed verb — a run that printed SIGSTOP here would mean the mode is decorative.
  ! grep -qE '^SIGSTOP ' "$SNAPLOG" || false
}

@test "observe and stop select the SAME set — the mode changes the act, never the predicate" {
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  printf '999901 1 900000 /opt/homebrew/bin/node w.js\n999902 1 900000 /opt/homebrew/bin/node /w/mcp-server/i.js\n' > "$PS_ACT"
  printf '999901 1 900000 /opt/homebrew/bin/node\n999902 1 900000 /opt/homebrew/bin/node\n' > "$PS_CENSUS"
  CENSUS_EVERY=99 ACT=observe run_daemon 3
  grep -qF 'actuator: WOULD have SIGSTOPped 1 process(es)' "$SNAPLOG" || false
  # REBUILD the stub machine: it owns the per-tick sequence AND the tick counter, so a second run
  # over the spent counter starts mid-ramp and never reaches the two consecutive breaching ticks.
  : > "$SNAPLOG"
  mkstubs "$(printf '800000\n1200000\n1600000\n2000000')" 0 0
  printf '999901 1 900000 /opt/homebrew/bin/node w.js\n999902 1 900000 /opt/homebrew/bin/node /w/mcp-server/i.js\n' > "$PS_ACT"
  printf '999901 1 900000 /opt/homebrew/bin/node\n999902 1 900000 /opt/homebrew/bin/node\n' > "$PS_CENSUS"
  CENSUS_EVERY=99 ACT=stop run_daemon 3
  grep -qF 'actuator: SIGSTOPped 0 process(es)' "$SNAPLOG" || false   # impossible pid ⇒ kill fails
  grep -qF 'parent-break none — no eligible parent owns >= 3 of the 1 selected burst procs' "$SNAPLOG" || false
}


# ══ 6. THE FREEZE READER — the deaths that write NO panic file ════════════════════════════════════
# WHY THIS SECTION EXISTS. On 2026-08-13 21:22:39 the box wedged during active use and was recovered
# by holding the power button 80 minutes later. No panic string, no SOCD data, so panic_scan
# correctly reported `none` and the ledger — the store built so the next death is attributable —
# recorded NOTHING about the worst stability event since the compressor panics.
#
# WHAT EACH CASE HAS TO PROVE, and why a comment would not do:
#   · THE DISCRIMINATOR IS REAL. `force_off` records, `wdog` defers. Both branches need a case, and
#     the deferral needs a POSITIVE CONTROL beside it or "no row" proves only that nothing ran.
#   · THE PARSE. The boot epoch is the row's identity. Its first draft captured `usec` and the
#     live machine returned 597125 — a well-formed, all-digit, fifty-six-years-wrong boot id that
#     every type check passes. That is pinned here, against the REAL sysctl format.
#   · THE PAYLOAD IS EVERY SAMPLER. Keeping only the newest row threw away the one fact that
#     describes the trigger. A test that only counted rows would not have seen it.
#
# The subject is driven through `--freeze-scan` (the real script, real wiring), never through an
# extracted function — the panic reader's `scan()` idiom, for the same reason.

fz() { CC_FREEZE_RESET_DIRS="$D/rc" CC_PANIC_DIRS="$D/panics" CC_PANIC_LEDGER="$D/fz.jsonl" \
       CC_FREEZE_SAMPLERS="$FZ_SAMPLERS" PATH="$STUB:$PATH" bash "$S" --freeze-scan; }

# The real `kern.boottime` shape, verbatim from this box — `usec` included, because that token IS
# the trap. BOOT_SEC/SHUTDOWN_REASON are the knobs; an empty BOOT_SEC makes the sysctl fail.
# It DELEGATES rather than clobbers. A whole-daemon case needs both stubs — the compressor sysctls
# from mkstubs and the kern.* pair from here — and the first draft simply overwrote $STUB/sysctl,
# so `mkstubs; mkfreezestubs` silently removed kern.boottime and the reader failed for a reason
# that had nothing to do with the case under test. Call mkstubs FIRST; this wraps whatever it wrote.
mkfreezestubs() { # <boot_sec> <shutdown_reason>
  export BOOT_SEC="$1" SHUTDOWN_REASON="$2"
  mkdir -p "$D/rc" "$D/panics"
  export FZ_SAMPLERS="${FZ_SAMPLERS:-$D/cap.jsonl:$D/sent.jsonl}"
  if [ -f "$STUB/sysctl" ] && ! grep -q 'kern.boottime' "$STUB/sysctl"; then
    mv "$STUB/sysctl" "$STUB/sysctl.inner"
  fi
  cat > "$STUB/sysctl" <<'SH'
#!/bin/bash
case "$2" in
  kern.boottime)
    [ -n "$BOOT_SEC" ] || exit 1
    printf '{ sec = %s, usec = 597125 }\n' "$BOOT_SEC" ;;
  kern.shutdownreason)
    [ -n "$SHUTDOWN_REASON" ] || exit 1
    printf '%s\n' "$SHUTDOWN_REASON" ;;
  *)
    [ -x "${0}.inner" ] || exit 1
    exec "${0}.inner" "$@" ;;
esac
SH
  chmod +x "$STUB/sysctl"
}

mkresetcounter() { # <name> <boot-faults-line> <mtime-YYYYMMDDhhmm>
  printf 'Reset count: 0\nBoot failure count: 1\nBoot faults: %s\nBoot stage: 0x40\n' "$2" > "$D/rc/$1"
  touch -t "$3" "$D/rc/$1"
}

BOOTS=1786686149          # 2026-08-14T05:42:29Z — a real boot, from this box's own ledger
# DERIVED FROM $BOOTS, never written out a second time as a literal. `touch -t` takes LOCAL
# wall-clock while $BOOTS is an absolute epoch, so a hand-written companion stamp is "the same
# instant" ONLY in the timezone it was authored in — and this pair was authored at -0700. The box
# now runs -0500, which placed every ResetCounter fixture 7,229 s BEFORE the boot epoch, i.e.
# outside freeze_boot_faults' 120 s floor (compressor-sentinel.sh:1107). The reader then found no
# ResetCounter at all and four cases silently fell back to kern.shutdownreason — including the two
# whose whole subject is that the ResetCounter OUTRANKS it. Deriving the stamp makes the two the
# same instant BY CONSTRUCTION, in any zone, so the suite cannot rot when the machine moves.
# The `%M` truncation drops $BOOTS' :29 seconds, leaving the file 29 s before the boot — deliberate
# and well inside the 120 s slack, exactly as the original pair intended.
BOOTSTAMP="$(date -r "$BOOTS" '+%Y%m%d%H%M')"

@test "freeze reader: a forced power-off with no panic is RECORDED as a freeze" {
  mkfreezestubs "$BOOTS" "btn_rst,finger_reset force_off ap_panic"
  mkresetcounter "ResetCounter-2026-08-13-224317.diag" "btn_rst,finger_reset force_off" "$BOOTSTAMP"
  run fz
  [ "$status" -eq 0 ] || false
  jq -e '.kind == "freeze"' "$D/fz.jsonl" >/dev/null || false
  jq -e '.boot_faults == "btn_rst,finger_reset force_off"' "$D/fz.jsonl" >/dev/null || false
  jq -e '.signature_source == "resetcounter"' "$D/fz.jsonl" >/dev/null || false
}

# THE PARSE REGRESSION. `.*sec = ` is greedy and walks to `usec`; against the real sysctl that
# returned the MICROSECONDS (597125) as the boot epoch. Numeric, well-formed, and wrong by decades.
@test "freeze reader: the boot epoch is sec, NEVER usec — the greedy-match trap" {
  mkfreezestubs "$BOOTS" "force_off"
  mkresetcounter "ResetCounter-x.diag" "btn_rst force_off" "$BOOTSTAMP"
  run fz
  [ "$status" -eq 0 ] || false
  jq -e --argjson b "$BOOTS" '.boot == $b' "$D/fz.jsonl" >/dev/null || false
  ! jq -e '.boot == 597125' "$D/fz.jsonl" >/dev/null || false
}

# The floor is the guard for the NEXT format change, not for the bug already fixed. A boot id that
# is bogus-but-numeric would key a row no later run could match — re-recording the same boot forever.
@test "freeze reader: an implausible boot epoch REFUSES rather than keying a row nothing can match" {
  mkfreezestubs "597125" "force_off"
  mkresetcounter "ResetCounter-x.diag" "btn_rst force_off" "$BOOTSTAMP"
  run fz
  [ "$status" -eq 3 ] || false
  [ ! -f "$D/fz.jsonl" ] || false
}

# A watchdog death already writes a .panic and panic_scan already records it. Recording it here too
# would make ONE event TWO incidents and inflate every count taken off this ledger.
@test "freeze reader: a wdog boot defers — and the SAME fixture without wdog records (control)" {
  mkfreezestubs "$BOOTS" "wdog,reset_in1"
  mkresetcounter "ResetCounter-2026-08-09-041902.diag" "wdog,reset_in1" "$BOOTSTAMP"
  run fz
  [ "$status" -eq 0 ] || false
  [ ! -f "$D/fz.jsonl" ] || false
  printf '%s\n' "$output" | grep -q 'watchdog boot' || false
  # POSITIVE CONTROL: identical run, faults line swapped for the button — a row appears.
  mkresetcounter "ResetCounter-2026-08-09-041902.diag" "btn_rst,finger_reset force_off" "$BOOTSTAMP"
  run fz
  jq -e '.kind == "freeze"' "$D/fz.jsonl" >/dev/null || false
}

# THE `ap_panic` TRAP. kern.shutdownreason on this box carries an `ap_panic` token on a boot where
# no panic occurred and none was recoverable. Classifying on the sysctl alone calls a freeze a panic.
@test "freeze reader: the ResetCounter OUTRANKS kern.shutdownreason, whose ap_panic token lies" {
  mkfreezestubs "$BOOTS" "btn_rst,finger_reset force_off ap_panic"
  mkresetcounter "ResetCounter-x.diag" "btn_rst,finger_reset force_off" "$BOOTSTAMP"
  run fz
  jq -e '.signature == "btn_rst,finger_reset force_off"' "$D/fz.jsonl" >/dev/null || false
  # Both artifacts are stored RAW so a later reader can re-adjudicate this one's reading.
  jq -e '.shutdown_reason | test("ap_panic")' "$D/fz.jsonl" >/dev/null || false
}

@test "freeze reader: a clean boot writes no row — the sysctl is consulted and says nothing" {
  mkfreezestubs "$BOOTS" ""
  run fz
  [ "$status" -eq 0 ] || false
  [ ! -f "$D/fz.jsonl" ] || false
  printf '%s\n' "$output" | grep -q 'clean' || false
}

# THE DARK WINDOW is the whole point of the row: a freeze's difficulty is that the evidence stops,
# and the samplers' last row is where it stopped.
@test "freeze reader: dark_from is the newest PRE-boot sampler row; post-boot rows are ignored" {
  mkfreezestubs "$BOOTS" "force_off"
  mkresetcounter "ResetCounter-x.diag" "btn_rst force_off" "$BOOTSTAMP"
  { echo '{"ts":"2026-08-14T04:20:30Z","load_1m":9.34}'
    echo '{"ts":"2026-08-14T04:22:39Z","load_1m":13.11,"ptys_used":9}'
    echo '{"ts":"2026-08-14T05:45:02Z","load_1m":122.13}'; } > "$D/cap.jsonl"   # last row is POST-boot
  echo '{"ts":"2026-08-14T04:22:54Z","seg":225161}' > "$D/sent.jsonl"
  run fz
  jq -e '.dark_from == "2026-08-14T04:22:54Z"' "$D/fz.jsonl" >/dev/null || false
  jq -e '.dark_to == "2026-08-14T05:42:29Z"' "$D/fz.jsonl" >/dev/null || false
  jq -e '.dark_minutes > 79 and .dark_minutes < 80' "$D/fz.jsonl" >/dev/null || false
  # the post-boot row must not be the one kept — that would erase the whole window
  ! jq -e '.last_ticks["cap.jsonl"].load_1m == 122.13' "$D/fz.jsonl" >/dev/null || false
}

# Keeping only the NEWEST row loses the trigger. Measured on the real incident: the sentinel won the
# boundary by 15 s, while load_1m 13.11 and ptys_used 9 — the only description of what was happening
# — live in capacity-alarm's row. This case is why last_ticks is a map and not one object.
@test "freeze reader: last_ticks holds EVERY sampler, not just the one that won the boundary" {
  mkfreezestubs "$BOOTS" "force_off"
  mkresetcounter "ResetCounter-x.diag" "btn_rst force_off" "$BOOTSTAMP"
  echo '{"ts":"2026-08-14T04:22:39Z","load_1m":13.11,"ptys_used":9}' > "$D/cap.jsonl"
  echo '{"ts":"2026-08-14T04:22:54Z","seg":225161}' > "$D/sent.jsonl"
  run fz
  jq -e '.sampler_source == "sent.jsonl"' "$D/fz.jsonl" >/dev/null || false      # newest won
  jq -e '.last_ticks["cap.jsonl"].load_1m == 13.11' "$D/fz.jsonl" >/dev/null || false
  jq -e '.last_ticks["cap.jsonl"].ptys_used == 9' "$D/fz.jsonl" >/dev/null || false
  jq -e '.last_ticks["sent.jsonl"].seg == 225161' "$D/fz.jsonl" >/dev/null || false
}

# "I could not read a sampler" and "the sampler had nothing before this boot" are different facts.
@test "freeze reader: sampler_source names the blindness — absent vs present-but-no-preboot-row" {
  mkfreezestubs "$BOOTS" "force_off"
  mkresetcounter "ResetCounter-x.diag" "btn_rst force_off" "$BOOTSTAMP"
  run fz                                        # no sampler files exist at all
  jq -e '.sampler_source == "none-readable"' "$D/fz.jsonl" >/dev/null || false
  jq -e '.dark_from == null and .dark_minutes == null' "$D/fz.jsonl" >/dev/null || false
  jq -e '.last_ticks == {}' "$D/fz.jsonl" >/dev/null || false
  rm -f "$D/fz.jsonl"
  echo '{"ts":"2026-08-14T09:00:00Z","load_1m":1}' > "$D/cap.jsonl"   # exists, but POST-boot only
  run fz
  jq -e '.sampler_source == "readable-no-preboot-row"' "$D/fz.jsonl" >/dev/null || false
}

@test "freeze reader: one boot is recorded ONCE, however often the daemon restarts" {
  mkfreezestubs "$BOOTS" "force_off"
  mkresetcounter "ResetCounter-x.diag" "btn_rst force_off" "$BOOTSTAMP"
  fz >/dev/null 2>&1; fz >/dev/null 2>&1; fz >/dev/null 2>&1
  [ "$(grep -c . "$D/fz.jsonl")" -eq 1 ] || false
}

@test "freeze reader: a NEW boot after a recorded one is appended (the paired act-rule)" {
  mkfreezestubs "$BOOTS" "force_off"
  mkresetcounter "ResetCounter-x.diag" "btn_rst force_off" "$BOOTSTAMP"
  fz >/dev/null 2>&1
  mkfreezestubs "$((BOOTS + 86400))" "force_off"
  mkresetcounter "ResetCounter-y.diag" "btn_rst force_off" "202608142242"
  fz >/dev/null 2>&1
  [ "$(grep -c . "$D/fz.jsonl")" -eq 2 ] || false
}

# ── the incident COUNT, which is not the row count ────────────────────────────────────────────────
# The ledger is append-only over a jittering key, so one freeze can hold two rows — the live store
# does, and always will, because the ±5 s dedupe prevents the next duplicate without retracting the
# one already written. Everything anyone asks this ledger ("has it recurred?", "do we have the second
# data point the ring buffer waits on?") is a question about INCIDENTS, and a row count answers it
# 2x high on exactly the sample size where that flips the decision.
#
# THE CONTROL IS THE LOAD-BEARING CASE. A counter hard-wired to print 1 passes the duplicate case
# perfectly; only the distinct-boots case can tell "clusters correctly" from "always says one", and
# without it this falsifier could never fire and the row it guards would be immortal.
fzc() { CC_PANIC_LEDGER="$1" bash "$S" --freeze-incidents; }

# The two boots are the REAL pair from this box's ledger, one second apart — the jitter that made
# freeze_boot_already tolerant in the first place.
mkfreezerow() { # <file> <boot_epoch>
  printf '{"ts":"2026-08-14T06:48:44Z","kind":"freeze","boot":%s,"signature":"force_off"}\n' "$2" >> "$1"
}

@test "freeze count: one incident recorded TWICE over jittered boottime counts ONCE" {
  mkfreezerow "$D/count.jsonl" 1786686149
  mkfreezerow "$D/count.jsonl" 1786686150
  [ "$(grep -c '"kind":"freeze"' "$D/count.jsonl")" -eq 2 ] || false   # the naive answer, pinned
  run fzc "$D/count.jsonl"
  [ "$status" -eq 0 ] || false
  [ "$output" = "1" ] || false
}

@test "freeze count: two genuinely distinct boots count as TWO (the control)" {
  mkfreezerow "$D/count.jsonl" 1786686149
  mkfreezerow "$D/count.jsonl" 1787642176
  run fzc "$D/count.jsonl"
  [ "$output" = "2" ] || false
}

# Arrival order is not boot order once anything is backfilled; an unsorted cluster walk splits one
# boot in two the moment the pair lands out of sequence.
@test "freeze count: rows arriving OUT of boot order still cluster as one incident" {
  mkfreezerow "$D/count.jsonl" 1786686150
  mkfreezerow "$D/count.jsonl" 1786686149
  run fzc "$D/count.jsonl"
  [ "$output" = "1" ] || false
}

@test "freeze count: an absent ledger is 0 incidents, not an error" {
  run fzc "$D/nosuch.jsonl"
  [ "$status" -eq 0 ] || false
  [ "$output" = "0" ] || false
}

# A panic row is a different class and must not be counted as a freeze — the ledger holds both.
# The falsifier on backlog row dabe706c9d79 IS this count, so an empty answer under the kill switch
# would silently make that row un-retractable again — the failure the count was built to end. The
# switch stops the actuator; a read-only query actuates nothing. Paired with a control proving the
# switch still stops the daemon, so this exemption cannot quietly become a hole in it.
@test "freeze count: the CC_SENTINEL kill switch does not silence the read-only count" {
  mkfreezerow "$D/count.jsonl" 1786686149
  CC_SENTINEL=off CC_PANIC_LEDGER="$D/count.jsonl" run bash "$S" --freeze-incidents
  [ "$status" -eq 0 ] || false
  [ "$output" = "1" ] || false
  # CONTROL: the switch still stops the daemon itself.
  CC_SENTINEL=off run bash "$S" --once
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"disabled (CC_SENTINEL=off)"* ]] || false
}

@test "freeze count: panic rows in the same ledger are not counted" {
  printf '{"ts":"x","kind":"panic","boot":1786686149}\n' > "$D/count.jsonl"
  mkfreezerow "$D/count.jsonl" 1787642176
  run fzc "$D/count.jsonl"
  [ "$output" = "1" ] || false
}

# A forced power-off that ALSO left a report is not this class: the box died, wrote its panic, and
# the button was only how it got back.
@test "freeze reader: force_off WITH a fresh panic report defers to the panic reader" {
  mkfreezestubs "$BOOTS" "force_off"
  mkresetcounter "ResetCounter-x.diag" "btn_rst force_off" "$BOOTSTAMP"
  : > "$D/panics/panic-full-now.panic"; touch -t "$BOOTSTAMP" "$D/panics/panic-full-now.panic"
  run fz
  [ "$status" -eq 0 ] || false
  [ ! -f "$D/fz.jsonl" ] || false
  # POSITIVE CONTROL: the same run with that report aged OUT of this boot records the freeze.
  touch -t 202608090419 "$D/panics/panic-full-now.panic"
  run fz
  jq -e '.kind == "freeze"' "$D/fz.jsonl" >/dev/null || false
}

# A reader for the LAST death must never cost the evidence for the NEXT one — panic_scan's rule.
@test "freeze reader: a failing freeze scan cannot stop the sensor from starting" {
  mkstubs 100000 0 0
  # CC_PANIC_DIRS is pinned even though this case is about the FREEZE reader. Left unset, PANIC_DIRS
  # falls back to the real /Library/Logs/DiagnosticReports and the sibling panic_scan reads the
  # OPERATOR'S actual panic reports mid-suite — the unfixtured-sensor class this file's header bans.
  # It was caught by the CC_FREEZE_SCAN=off case below, which asserted an absent ledger and got a
  # genuine recorded panic in it instead: an absence assertion is what found the leak.
  mkdir -p "$D/panics"
  export CC_FREEZE_RESET_DIRS="$D/nonexistent" CC_PANIC_DIRS="$D/panics" BOOT_SEC="" SHUTDOWN_REASON=""
  run env PATH="$STUB:$PATH" CC_SENTINEL_LOG="$D/s.jsonl" bash "$S" --once
  [ "$status" -eq 0 ] || false
  [ -s "$D/s.jsonl" ] || false     # positive control: the tick still produced a row
}

@test "freeze reader: CC_FREEZE_SCAN=off skips it entirely" {
  mkstubs 100000 0 0                     # compressor sysctls FIRST; mkfreezestubs wraps them
  mkfreezestubs "$BOOTS" "force_off"
  mkresetcounter "ResetCounter-x.diag" "btn_rst force_off" "$BOOTSTAMP"
  export CC_FREEZE_RESET_DIRS="$D/rc" CC_PANIC_DIRS="$D/panics" CC_PANIC_LEDGER="$D/fz.jsonl" CC_FREEZE_SCAN=off
  run env PATH="$STUB:$PATH" CC_SENTINEL_LOG="$D/s.jsonl" bash "$S" --once
  [ ! -f "$D/fz.jsonl" ] || false
  # POSITIVE CONTROL: the identical run with the reader ON writes the row — so the absence above is
  # the switch working, not the fixture failing to reach the reader at all.
  mkstubs 100000 0 0
  mkfreezestubs "$BOOTS" "force_off"
  # CC_FREEZE_SCAN=on is passed EXPLICITLY: the `export ...=off` above is still in this test's
  # environment, so `env` would inherit it and the control would re-prove the off case — a control
  # that cannot distinguish itself from the assertion it is controlling for.
  run env PATH="$STUB:$PATH" CC_FREEZE_SCAN=on CC_FREEZE_RESET_DIRS="$D/rc" CC_PANIC_DIRS="$D/panics" \
      CC_PANIC_LEDGER="$D/fz.jsonl" CC_SENTINEL_LOG="$D/s2.jsonl" bash "$S" --once
  jq -e '.kind == "freeze"' "$D/fz.jsonl" >/dev/null || false
}

# ── THE UNFREEZE ARM (master 477f0b771ec3) ────────────────────────────────────────────────────────
# The actuator SIGSTOPs and, until this diff, nothing resumed. Measured 2026-08-19 on the live box:
# 109 trips, 59 real SIGSTOPped events, zero SIGCONT senders in the tree. The kill site itself calls
# SIGSTOP the reversible choice — so these cases exist to prove the reversal is real, and above all
# that it CANNOT fire on a process this daemon did not freeze.
#
# STUBBING NOTE, and it is the reason this block has its own runner: `ps` is a real binary, so a
# script in $STUB shadows it. `kill` is a bash BUILTIN — a PATH stub can NEVER shadow a builtin, and
# a suite that put `kill` in $STUB would silently signal REAL pids while reading green. It is
# intercepted as a shell FUNCTION inside the runner instead, which does take precedence.
#
# RED-PROOF: pre-fix, `release_frozen`/`record_frozen` are absent from lib.sh, so each case fails at
# its explicit locator assertion. NO case carries `skip` — a skipped case renders as `ok` and would
# make this whole block vacuous (memory: red-proof-fixture-must-not-call-the-subject).

mkcohort() { # <psmap>  — TAB-separated "pid<TAB>lstart[<TAB>stat]" rows. A pid ABSENT from the map is gone.
  PSMAP="$D/psmap"; printf '%s\n' "$1" > "$PSMAP"
  FDB="$D/frozen.tsv"; : > "$FDB"
  PROBDB="$D/probation.tsv"; : > "$PROBDB"
  KILLLOG="$D/kill.calls"; : > "$KILLLOG"
  # A FULL-TABLE read (no -p) prints NOTHING: kill_escalate now reads `exe_table gui` when handed no
  # capture, and an empty table is the belt ABSTAINING — so every custody case below keeps its exact
  # pre-2026-09-30 output, and the fail direction of that belt is pinned by all of them at once.
  #
  # THE STAT COLUMN (2026-09-30). Custody now reads `-o stat=,lstart=` in one fork; for that format
  # the stub prints "<stat> <lstart>", stat from an optional third map column and T (stopped) when
  # absent — the state a ledgered row is in unless a case says someone resumed it. `-o lstart=` alone
  # (record_frozen, probation, the mutex) prints the lstart exactly as before.
  cat > "$STUB/ps" <<'SH'
#!/bin/bash
pid=""; o=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-p" ]; then pid="$2"; shift
  elif [ "$1" = "-o" ]; then o="$2"; shift; fi
  shift
done
[ -n "$pid" ] || exit 0
case "$o" in
  *stat=*) awk -F'\t' -v p="$pid" '$1==p { print ($3 == "" ? "T" : $3) " " $2 }' "$PSMAP" ;;
  *)       awk -F'\t' -v p="$pid" '$1==p {print $2}' "$PSMAP" ;;
esac
SH
  chmod +x "$STUB/ps"
}

ledger() { # <pid> <lstart> <kind> <frozen-at-epoch> <comm>
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$FDB"
}

# ANTI-VACUITY: every case calls this FIRST. If the arm is absent (pre-fix, or a refactor that
# renames it) the case dies here with a named reason instead of asserting over nothing.
have_arm() { # <fn>
  grep -q "^$1() {" "$D/lib.sh" || false
}

# Both custody runners run under the daemon's own `set -uo pipefail` (L88): an unbound expansion that
# aborts the function in the daemon must abort it here too, or the suite passes code that strands.
# APPLYSIG (optional, exported): a script the kill stub also calls, so a case can make the stub table
# FOLLOW the signals — custody that reads state must be tested against its own SIGCONT's effect.
run_rel() { # <now-epoch> <mode> [<parent_ok 0|1>] [<cliff 0|1>] [<protected " pid " list>]
  run env PATH="$STUB:$PATH" PSMAP="$PSMAP" FROZEN_DB="$FDB" SNAP="$SNAPLOG" KILLLOG="$KILLLOG" \
      HOLD_MIN_S="${HOLD_MIN_S:-60}" HOLD_MAX_S="${HOLD_MAX_S:-600}" \
      PARENT_HOLD_MIN_S="${PARENT_HOLD_MIN_S:-600}" PROBATION_DB="$PROBDB" \
      RELINQUISH_GRACE_S="${RELINQUISH_GRACE_S:-30}" \
      bash -c 'set -uo pipefail; kill() { printf "%s\n" "$*" >> "$KILLLOG"; [ -z "${APPLYSIG:-}" ] || "$APPLYSIG" "$@"; }; . "$1"; release_frozen "$2" "$3" "$4" "$5" "$6"' \
      _ "$D/lib.sh" "$1" "$2" "${3:-0}" "${4:-0}" "${5:- }"
}

@test "unfreeze: the breach clearing after the minimum hold SIGCONTs the WORKERS — never the spawner" {
  have_arm release_frozen
  # This case used to expect released=2 — worker AND parent on one clear tick. That expectation WAS
  # panic #5: the one-tick clear released the primed wave-2 spawner at 71.81% of the segment limit
  # (SIGCONT pid=39672 held_s=68) and the resumed pool drove 72% → 100%. The parent now rides its
  # own certificate (§8c); a test pinning the old behaviour would be an inverted guard
  # (memory: stale-assertion-becomes-an-inverted-guard).
  mkcohort "$(printf '4001\tMon 18 Aug 04:00:00 2026\n4002\tMon 18 Aug 04:00:01 2026')"
  ledger 4001 "Mon 18 Aug 04:00:00 2026" proc 1000 node
  ledger 4002 "Mon 18 Aug 04:00:01 2026" parent 1000 bash
  run_rel 1100 clear                                  # age 100 >= HOLD_MIN_S 60
  [ "$status" -eq 0 ] || false
  [ "$output" = "released=1 held=1 stale=0" ] || false
  [ "$(grep -cF -- '-CONT 4001' "$KILLLOG")" -eq 1 ] || false
  [ "$(grep -cF -- '-CONT 4002' "$KILLLOG")" -eq 0 ] || false
  [ "$(cut -f1 < "$FDB")" = "4002" ] || false          # the spawner is what stays owed
}

@test "unfreeze: mode=clear does NOT release inside the minimum hold, and keeps the row owed" {
  have_arm release_frozen
  mkcohort "$(printf '4001\tMon 18 Aug 04:00:00 2026')"
  ledger 4001 "Mon 18 Aug 04:00:00 2026" proc 1000 node
  run_rel 1030 clear                                  # age 30 < HOLD_MIN_S 60
  [ "$output" = "released=0 held=1 stale=0" ] || false
  [ ! -s "$KILLLOG" ] || false
  # POSITIVE CONTROL: the identical ledger one tick past the minimum DOES release, so the silence
  # above is the hold working rather than the runner failing to reach the signal at all.
  run_rel 1061 clear
  [ "$output" = "released=1 held=0 stale=0" ] || false
  [ "$(grep -cF -- '-CONT 4001' "$KILLLOG")" -eq 1 ] || false
}

@test "unfreeze: PID REUSE — a mismatched lstart is dropped with NO signal (+ positive control)" {
  have_arm release_frozen
  # 4001 is alive but STARTED LATER than the ledger says: the pid was recycled onto a different
  # process. Resuming it would SIGCONT an innocent third party — the one harm this arm can do.
  mkcohort "$(printf '4001\tMon 18 Aug 09:99:99 2026\n4002\tMon 18 Aug 04:00:01 2026')"
  ledger 4001 "Mon 18 Aug 04:00:00 2026" proc 1000 node
  ledger 4002 "Mon 18 Aug 04:00:01 2026" proc 1000 node
  run_rel 1100 clear
  [ "$output" = "released=1 held=0 stale=1" ] || false
  [ "$(grep -cF -- '-CONT 4001' "$KILLLOG")" -eq 0 ] || false   # the recycled pid: untouched
  [ "$(grep -cF -- '-CONT 4002' "$KILLLOG")" -eq 1 ] || false   # control: the matched pid resumed
}

@test "unfreeze: a pid that is gone entirely is stale, never signalled" {
  have_arm release_frozen
  mkcohort "$(printf '4002\tMon 18 Aug 04:00:01 2026')"          # 4001 absent = process gone
  ledger 4001 "Mon 18 Aug 04:00:00 2026" proc 1000 node
  run_rel 1100 clear
  [ "$output" = "released=0 held=0 stale=1" ] || false
  [ ! -s "$KILLLOG" ] || false
}

@test "unfreeze: mode=ceiling releases even while the breach is STILL live" {
  have_arm release_frozen
  mkcohort "$(printf '4001\tMon 18 Aug 04:00:00 2026')"
  ledger 4001 "Mon 18 Aug 04:00:00 2026" proc 1000 node
  run_rel 1700 ceiling                                # age 700 >= HOLD_MAX_S 600
  [ "$output" = "released=1 held=0 stale=0" ] || false
  [ "$(grep -cF -- '-CONT 4001' "$KILLLOG")" -eq 1 ] || false
}

@test "unfreeze: mode=ceiling HOLDS a fresh freeze — a live breach does not release early" {
  have_arm release_frozen
  mkcohort "$(printf '4001\tMon 18 Aug 04:00:00 2026')"
  ledger 4001 "Mon 18 Aug 04:00:00 2026" proc 1000 node
  run_rel 1500 ceiling                                # age 500 < HOLD_MAX_S 600, and still tripping
  [ "$output" = "released=0 held=1 stale=0" ] || false
  [ ! -s "$KILLLOG" ] || false
}

@test "unfreeze: mode=exit releases unconditionally, at age zero" {
  have_arm release_frozen
  # The daemon is going away. Without this the row's failure mode survives the fix: a restart would
  # strand the cohort with the only record of the debt in a file nothing reads again.
  mkcohort "$(printf '4001\tMon 18 Aug 04:00:00 2026')"
  ledger 4001 "Mon 18 Aug 04:00:00 2026" proc 1000 node
  run_rel 1000 exit                                   # age 0 — below BOTH bounds
  [ "$output" = "released=1 held=0 stale=0" ] || false
  [ "$(grep -cF -- '-CONT 4001' "$KILLLOG")" -eq 1 ] || false
}

@test "unfreeze: the ledger is rewritten to EXACTLY the rows still owed" {
  have_arm release_frozen
  mkcohort "$(printf '4001\tMon 18 Aug 04:00:00 2026\n4003\tMon 18 Aug 04:00:03 2026')"
  ledger 4001 "Mon 18 Aug 04:00:00 2026" proc 1000 node    # due
  ledger 4002 "Mon 18 Aug 04:00:02 2026" proc 1000 node    # gone → dropped
  ledger 4003 "Mon 18 Aug 04:00:03 2026" proc 1090 node    # too fresh → kept
  run_rel 1100 clear
  [ "$output" = "released=1 held=1 stale=1" ] || false
  [ "$(wc -l < "$FDB" | tr -d ' ')" -eq 1 ] || false
  [ "$(cut -f1 < "$FDB")" = "4003" ] || false
}

@test "unfreeze: record_frozen ledgers a live pid, and ledgers NOTHING for one already gone" {
  have_arm record_frozen
  mkcohort "$(printf '4001\tMon 18 Aug 04:00:00 2026')"
  run env PATH="$STUB:$PATH" PSMAP="$PSMAP" FROZEN_DB="$FDB" \
      bash -c '. "$1"; record_frozen 4001 proc node; record_frozen 4099 proc ghost' _ "$D/lib.sh"
  [ "$status" -eq 0 ] || false
  [ "$(wc -l < "$FDB" | tr -d ' ')" -eq 1 ] || false
  [ "$(cut -f1 < "$FDB")" = "4001" ] || false
  [ "$(cut -f2 < "$FDB")" = "Mon 18 Aug 04:00:00 2026" ] || false
  [ "$(cut -f3 < "$FDB")" = "proc" ] || false
}

@test "unfreeze: BOTH real-kill sites ledger the freeze, and the observe branch ledgers nothing" {
  # WHY THIS CASE IS STRUCTURAL AND THE OTHERS ARE BEHAVIOURAL. Everything above drives the arm
  # directly, so a diff that DELETED `record_frozen` from a kill site would leave all nine green:
  # the invariant lives in a call that is simply absent, and an absent token is invisible to every
  # assertion about the function it would have called (memory: invariant-can-live-in-an-absent-token).
  # A behavioural version would have to run the whole daemon with `kill` intercepted, and this
  # suite's contract is that it never signals — `kill` is a builtin, so an escape there would signal
  # REAL pids. So this asserts the WIRING and says so: it proves both sites call the recorder and
  # that the observe branch does not, not that the recorder then behaves (cases above own that).
  actuator="$(sed -n '/ACT_PARENT" = "on"/,/parent-break none/p' "$S")"
  [ -n "$actuator" ] || false                      # ANTI-VACUITY: the anchor still matches
  # Both REAL kill sites, each on the branch that actually signalled (`elif kill -STOP`).
  [ "$(printf '%s\n' "$actuator" | grep -cF 'record_frozen "$ppid" parent')" -eq 1 ] || false
  [ "$(printf '%s\n' "$actuator" | grep -cF 'record_frozen "$spid" proc')" -eq 1 ] || false
  [ "$(printf '%s\n' "$actuator" | grep -cF 'record_frozen')" -eq 2 ] || false
  # NEGATIVE + its control: observe computes the whole selection and signals nothing, so it must
  # ledger nothing — a debt recorded for a freeze that never happened would SIGCONT a stranger.
  obs="$(printf '%s\n' "$actuator" | grep -A2 'ACT" = "observe"')"
  [ -n "$obs" ] || false                           # control: the observe branch is still there
  [ "$(printf '%s\n' "$obs" | grep -cF 'record_frozen')" -eq 0 ] || false
}

# ══ 8. PANIC #5 (2026-08-24) — the cliff regime, the release split, probation, and the kill rung ═══
# docs/research/panic-2026-08-24-fifth-watchdog.md. The guard detected and froze BOTH storm waves in
# time — then its release arm, whose "breach over" test was the single-tick negation of the AND'd
# trip predicate, SIGCONTd the primed wave-2 spawner at 71.81% of the segment limit on one swapout
# lull (srate 536 < 600, held_s 68), and the resumed pool drove segments 72% → 100% in ~2 minutes.
# TRIP 4's actuation never reached disk (ticks stretched to 146 s under census+snapshot load).
# Each case below pins one limb of the repair; the fatal tick itself is replayed by number.

# ── 8a. the cliff arm of the trip predicate ───────────────────────────────────────────────────────

@test "cliff arm: level ALONE above CLIFF_PCT breaches at zero rate — and the fatal tick now trips" {
  run_fn classify_breach 610000 1000000 0 0 0
  [ "$status" -eq 0 ] || false
  [ "$output" = "cliff" ] || false
  # THE FATAL TICK, replayed by number: 71.81% at srate 536.2 read "clear" pre-fix and released the
  # spawner. It must now read as a breach.
  run_fn classify_breach 718100 1000000 536 0 0
  [ "$output" = "cliff" ] || false
  # SUB-CLIFF CONTROL: the same zero-rate sample below the cliff stays clear — the AND regime holds.
  run_fn classify_breach 590000 1000000 0 0 0
  [ "$status" -ne 0 ] || false
  [ -z "$output" ] || false
}

@test "cliff arm: CLIFF_PCT is a seam that moves the verdict, and composes with the seg arm" {
  CLIFF_PCT=50 run_fn classify_breach 550000 1000000 0 0 0
  [ "$output" = "cliff" ] || false
  CLIFF_PCT=50 run_fn classify_breach 550000 1000000 700 0 0
  [ "$output" = "seg+cliff" ] || false
  CLIFF_PCT=0 run_fn classify_breach 550000 1000000 0 0 0     # 0 disables the arm outright
  [ "$status" -ne 0 ] || false
}

# ── 8b. cliff loop behaviour ──────────────────────────────────────────────────────────────────────

@test "cliff: ONE breach tick trips, the snapshot goes minimal, and no follow-up spawns" {
  # Tick 2 jumps straight to 65% — a single spike, which BELOW the cliff must not trip (§3's first
  # case, with the cliff pinned out). Above it, one tick is all the warning there is.
  mkstubs "$(printf '800000\n2600000\n2600000')" 0 0
  run_daemon 3
  echo "$output" | grep -q 'TRIP why=' || false
  grep -q '═══ TRIP' "$SNAPLOG" || false
  # The minimal form: attribution skipped AND the skip is printed — never an empty section that
  # reads as an idle box. vm_stat (cheap, carries the free-page count) stays.
  grep -q 'cliff regime: attribution SKIPPED' "$SNAPLOG" || false
  ! grep -q -- '--- top 30 by RSS' "$SNAPLOG" || false
  grep -q -- '--- vm_stat ---' "$SNAPLOG" || false
  # No follow-up sweeps up there: 12 more ps passes were exactly the load that stretched trip 4's
  # tick past its own actuation.
  ! grep -q -- '--- follow-up' "$SNAPLOG" || false
}

@test "cliff: the cooldown does NOT gate re-trips — wave 2 re-ignited inside the 60 s window" {
  mkstubs "$(printf '800000\n2600000\n2800000\n3000000\n3200000')" 0 0
  run_daemon 5
  [ "$(echo "$output" | grep -c 'TRIP why=')" -ge 2 ] || false
  [ "$(grep -c '═══ TRIP' "$SNAPLOG")" -ge 2 ] || false
}

@test "cliff + armed: the INTENT line reaches disk BEFORE the signals (write-ahead)" {
  # TRIP 4 of panic #5 actuated — or did not — with nothing ever reaching disk. The intent line is
  # what makes a mid-flight death distinguishable from an actuation that never ran.
  mkstubs "$(printf '800000\n2600000\n2600000')" 0 0
  printf '999901 1 900000 /opt/homebrew/bin/node w.js\n' > "$PS_ACT"
  printf '999901 1 900000 /opt/homebrew/bin/node\n' > "$PS_CENSUS"
  CENSUS_EVERY=99 ACT=stop run_daemon 3
  grep -qF 'actuator: INTENT SIGSTOP cohort_n=1 cliff=1' "$SNAPLOG" || false
  intent_ln="$(grep -n 'actuator: INTENT' "$SNAPLOG" | head -1 | cut -d: -f1)"
  done_ln="$(grep -n 'actuator: SIGSTOPped' "$SNAPLOG" | head -1 | cut -d: -f1)"
  [ -n "$intent_ln" ] && [ -n "$done_ln" ] && [ "$intent_ln" -lt "$done_ln" ] || false
}

# ── 8c. the release split: a spawner is not a worker ──────────────────────────────────────────────

@test "unfreeze/panic5: a clear tick NEVER releases a spawner — the fatal SIGCONT, replayed and refused" {
  have_arm release_frozen
  mkcohort "$(printf '5001\tMon 24 Aug 19:56:46 2026')"
  ledger 5001 "Mon 24 Aug 19:56:46 2026" parent 1000 'next-server_(v16.2.6)'
  run_rel 1068 clear                                  # held 68 s — the exact fatal hold
  [ "$output" = "released=0 held=1 stale=0" ] || false
  [ ! -s "$KILLLOG" ] || false
  # POSITIVE CONTROL: the sustained-calm certificate + the parent's own hold DOES release — and the
  # released spawner is stamped onto probation.
  run_rel 1700 clear 1 0                              # age 700 >= PARENT_HOLD_MIN_S 600, parent_ok=1
  [ "$output" = "released=1 held=0 stale=0" ] || false
  [ "$(grep -cF -- '-CONT 5001' "$KILLLOG")" -eq 1 ] || false
  [ "$(grep -c '^5001	' "$PROBDB")" -eq 1 ] || false
}

@test "unfreeze/panic5: the certificate alone is not enough — the parent hold still binds" {
  have_arm release_frozen
  mkcohort "$(printf '5001\tMon 24 Aug 19:56:46 2026')"
  ledger 5001 "Mon 24 Aug 19:56:46 2026" parent 1000 next-server
  run_rel 1300 clear 1 0                              # parent_ok=1 but age 300 < 600
  [ "$output" = "released=0 held=1 stale=0" ] || false
  [ ! -s "$KILLLOG" ] || false
}

@test "unfreeze/panic5: the ceiling never releases a spawner — that case belongs to the kill rung" {
  have_arm release_frozen
  mkcohort "$(printf '5001\tMon 24 Aug 19:56:46 2026\n5002\tMon 24 Aug 19:56:47 2026')"
  ledger 5001 "Mon 24 Aug 19:56:46 2026" parent 1000 next-server
  ledger 5002 "Mon 24 Aug 19:56:47 2026" proc 1000 node
  run_rel 1700 ceiling                                # age 700 >= HOLD_MAX_S 600 for both
  # The WORKER releases at its ceiling (the pre-#5 rule, kept); the SPAWNER does not.
  [ "$output" = "released=1 held=1 stale=0" ] || false
  [ "$(grep -cF -- '-CONT 5002' "$KILLLOG")" -eq 1 ] || false
  [ "$(grep -cF -- '-CONT 5001' "$KILLLOG")" -eq 0 ] || false
}

@test "unfreeze/panic5: in the cliff regime NOTHING releases — not even a ceiling-aged worker" {
  have_arm release_frozen
  mkcohort "$(printf '5002\tMon 24 Aug 19:56:47 2026')"
  ledger 5002 "Mon 24 Aug 19:56:47 2026" proc 1000 node
  run_rel 1700 ceiling 0 1                            # cliff=1: resuming spends the frozen margin
  [ "$output" = "released=0 held=1 stale=0" ] || false
  [ ! -s "$KILLLOG" ] || false
  # POSITIVE CONTROL: the identical call off-cliff releases, so the hold above is the cliff working.
  run_rel 1700 ceiling 0 0
  [ "$output" = "released=1 held=0 stale=0" ] || false
}

@test "unfreeze/panic5: exit releases spawners too, and writes NO probation stamp" {
  # A stranded SIGSTOP with no living SIGCONT sender is strictly worse than a released spawner —
  # and a stamp the exiting daemon can never consume would be litter for a successor to trip on.
  have_arm release_frozen
  mkcohort "$(printf '5001\tMon 24 Aug 19:56:46 2026')"
  ledger 5001 "Mon 24 Aug 19:56:46 2026" parent 1000 next-server
  run_rel 1000 exit
  [ "$output" = "released=1 held=0 stale=0" ] || false
  [ "$(grep -cF -- '-CONT 5001' "$KILLLOG")" -eq 1 ] || false
  [ ! -s "$PROBDB" ] || false
}

# ── 8d. probation: a released spawner has not proven anything yet ─────────────────────────────────

run_prob() { # <now-epoch>
  run env PATH="$STUB:$PATH" PSMAP="$PSMAP" FROZEN_DB="$FDB" PROBATION_DB="$PROBDB" \
      SNAP="$SNAPLOG" KILLLOG="$KILLLOG" PROBATION_S="${PROBATION_S:-300}" \
      bash -c 'kill() { printf "%s\n" "$*" >> "$KILLLOG"; }; . "$1"; probation_refreeze "$2"' \
      _ "$D/lib.sh" "$1"
}

@test "probation: a breach inside the window re-freezes the spawner; reuse and expiry never signal" {
  have_arm probation_refreeze
  mkcohort "$(printf '5001\tMon 24 Aug 19:58:00 2026\n5002\tMon 24 Aug 19:58:01 2026')"
  printf '5001\tMon 24 Aug 19:58:00 2026\t900\tnext-server\n'  > "$PROBDB"   # released 100 s ago
  printf '5002\tMon 24 Aug 11:11:11 2026\t900\tnext-server\n' >> "$PROBDB"   # pid recycled: lstart differs
  printf '5003\tMon 24 Aug 19:58:02 2026\t100\tnext-server\n' >> "$PROBDB"   # expired: 900 s > 300 s window
  run_prob 1000
  [ "$output" = "refroze=1" ] || false
  [ "$(grep -cF -- '-STOP 5001' "$KILLLOG")" -eq 1 ] || false
  [ "$(grep -cF -- '-STOP 5002' "$KILLLOG")" -eq 0 ] || false
  [ "$(grep -cF -- '-STOP 5003' "$KILLLOG")" -eq 0 ] || false
  grep -q '^5001	' "$FDB" || false                    # back in custody, under the parent rules
  grep -q 'parent' "$FDB" || false
  [ ! -s "$PROBDB" ] || false                          # refrozen, recycled and expired all leave the file
}

# ── 8e. the kill rung: custody converts when the freeze is losing ─────────────────────────────────

run_kd() { # <pct> <srate> <trip_now> <debt_n>
  run env KILL_PCT="${KILL_PCT:-60}" \
      bash -c '. "$1"; kill_due "$2" "$3" "$4" "$5"' _ "$D/lib.sh" "$1" "$2" "$3" "$4"
}

@test "kill_due: fires on a re-trip over held debt and on climbing at altitude — never without debt" {
  have_arm kill_due
  run_kd 30 100 1 2;    [ "$output" = "retrip-over-debt" ] || false
  run_kd 70 500 0 2;    [ "$output" = "climbing-at-60pct" ] || false
  # Falling at altitude is reclaim under way — killing then would spend custody on a recovery.
  run_kd 70 -1200 0 2;  [ "$status" -ne 0 ] || false
  # No debt ⇒ nothing to escalate, whatever the level says: the rung converts CUSTODY, it is not a
  # general-purpose killer.
  run_kd 30 9000 0 0;   [ "$status" -ne 0 ] || false
  run_kd 95 9000 1 0;   [ "$status" -ne 0 ] || false
  run_kd 59 100 0 2;    [ "$status" -ne 0 ] || false   # below the line, no trip: the freeze is holding
}

run_ke() { # <now-epoch> <reason> [<exe_file>]
  run env PATH="$STUB:$PATH" PSMAP="$PSMAP" FROZEN_DB="$FDB" SNAP="$SNAPLOG" KILLLOG="$KILLLOG" \
      KILL_MIN_HOLD_S="${KILL_MIN_HOLD_S:-30}" RELINQUISH_GRACE_S="${RELINQUISH_GRACE_S:-30}" \
      bash -c 'set -uo pipefail; kill() { printf "%s\n" "$*" >> "$KILLLOG"; [ -z "${APPLYSIG:-}" ] || "$APPLYSIG" "$@"; }; . "$1"; kill_escalate "$2" "$3" "$4"' \
      _ "${KE_LIB:-$D/lib.sh}" "$1" "$2" "${3:-}"
}

@test "kill_escalate: kills only ledger-verified custody — the young, the claude-shaped and the recycled survive" {
  have_arm kill_escalate
  mkcohort "$(printf '6001\tMon 24 Aug 19:56:46 2026\n6002\tMon 24 Aug 19:59:00 2026\n6003\tMon 24 Aug 19:56:00 2026')"
  ledger 6001 "Mon 24 Aug 19:56:46 2026" parent 1000 'next-server_(v16.2.6)'  # age 100 >= 30 → killed
  ledger 6002 "Mon 24 Aug 19:59:00 2026" proc 1085 node                        # age 15 < 30 → spared, kept
  ledger 6003 "Mon 24 Aug 19:56:00 2026" proc 1000 claude.exe                  # belt: never, whatever the ledger says
  ledger 6004 "Mon 24 Aug 19:56:00 2026" parent 1000 next-server               # absent from ps → dropped, no signal
  run_ke 1100 test-reason
  [ "$output" = "killed=1 spared=2" ] || false
  [ "$(grep -cF -- '-KILL 6001' "$KILLLOG")" -eq 1 ] || false
  [ "$(grep -cF -- '-KILL 6002' "$KILLLOG")" -eq 0 ] || false
  [ "$(grep -cF -- '-KILL 6003' "$KILLLOG")" -eq 0 ] || false
  [ "$(grep -cF -- '-KILL 6004' "$KILLLOG")" -eq 0 ] || false
  [ "$(wc -l < "$FDB" | tr -d ' ')" -eq 2 ] || false   # the spared stay owed; the killed and gone are dropped
  # WRITE-AHEAD: the intent line precedes the first SIGKILL confirmation in the snap log.
  intent_ln="$(grep -n 'KILL-INTENT' "$SNAPLOG" | head -1 | cut -d: -f1)"
  kill_ln="$(grep -n 'SIGKILL pid=6001' "$SNAPLOG" | head -1 | cut -d: -f1)"
  [ -n "$intent_ln" ] && [ -n "$kill_ln" ] && [ "$intent_ln" -lt "$kill_ln" ] || false
}

@test "panic5 wiring: the loop consults every new arm (locator, one per call site)" {
  # Structural, for test 106's reason: each invariant lives in a CALL, and an absent call is
  # invisible to every behavioural assertion about the function it would have reached.
  grep -qF 'KREASON="$(kill_due' "$S" || false
  grep -qF 'kill_escalate "$NOW" "$KREASON"' "$S" || false
  grep -qF 'probation_refreeze "$NOW"' "$S" || false
  grep -qF '[ "$CLIFF" = "0" ] && [ $((TICK % CENSUS_EVERY)) -eq 0 ]' "$S" || false
  grep -qF 'release_frozen "$NOW" "$RELMODE" "$PARENT_OK" "$CLIFF"' "$S" || false
  grep -qF 'snapshot_trip "$TS" "$WHY" "$HEAD_LINE" "$CLIFF"' "$S" || false
  # 2026-09-30: the trip reads the GUI-classed table, keeps it past the selection, and hands the SAME
  # capture to the kill rung — which is what makes the protected-class belt free on every kill tick.
  grep -qF 'exe_table gui > "$EXEF"' "$S" || false
  grep -qF 'kill_escalate "$NOW" "$KREASON" "$EXEF"' "$S" || false
  grep -qF 'TRIP_FIRED=0; EXEF=""' "$S" || false
  local between; between="$(sed -n '/exe_table gui > "\$EXEF"/,/kill_escalate "\$NOW"/p' "$S")"
  [ -n "$between" ] || false                                         # ANTI-VACUITY: both anchors hit
  ! printf '%s\n' "$between" | grep -qF 'rm -f "$EXEF"' || false     # not deleted before the kill rung
  grep -qF "printf 'actuator: protected-class spared" "$S" || false
  grep -qF 'release_frozen "$(date +%s)" sweep' "$S" || false
  # …and custody returns what a loop owner inherited, whatever its ACT, through the one liveness test
  # the mutex uses — so no hand-run can release the live daemon's cohort.
  grep -qF 'RELEASE-ON-DISARM' "$S" || false
  grep -qF 'RELEASE-ON-DISABLE' "$S" || false
  [ "$(grep -cF 'loop_owner_live "' "$S")" -ge 2 ] || false         # the mutex AND the off-drain
  # One ledger row per process: compacted once per trip after the stop loops, and read merged.
  grep -qF '[ $((PARENT_STOPPED + STOPPED)) -gt 0 ] && frozen_compact' "$S" || false
  [ "$(grep -cF 'src="$(frozen_read)"' "$S")" -eq 2 ] || false      # release_frozen AND kill_escalate
}

# ── 8f. the panic reader's dotfile shadow, the boot-jitter dedupe, and the mutex ──────────────────

@test "panic reader: .contents.panic never shadows the dated report — the hole panic #5 fell into" {
  # macOS stages the live panic text as `.contents.panic` beside the dated report, SAME basename
  # every panic. On 2026-08-18 it won the newest-file race; the basename-keyed idempotency check
  # then read every later panic's staging file as already-recorded, and panic #5 got NO ledger row.
  panic_fixture_base "$D/panics" "panic-base+socd-2026-08-24-200410.000.panic"
  sleep 1
  panic_fixture_base "$D/panics" ".contents.panic"     # newer mtime — pre-fix, this wins the race
  run scan
  [ "$status" -eq 0 ] || false
  jq -e '.report == "panic-base+socd-2026-08-24-200410.000.panic"' "$D/panic.jsonl" >/dev/null || false
  ! grep -qF '".contents.panic"' "$D/panic.jsonl" || false
  # ...and a directory holding ONLY the dotfile is genuinely "none", never a recorded dotfile.
  rm -f "$D/panics/panic-base+socd-2026-08-24-200410.000.panic" "$D/panic.jsonl"
  run scan
  [ "$status" -eq 0 ] || false
  [ ! -f "$D/panic.jsonl" ] || false
}

@test "freeze reader: the boot dedupe tolerates kern.boottime's ±1 s jitter (the double-record)" {
  # The live ledger holds the proof: boot 1786686149 was re-recorded eight days later as 1786686150.
  have_arm freeze_boot_already
  printf '{"kind":"freeze","boot":1786686149}\n' > "$D/pl.jsonl"
  run env PANIC_LEDGER="$D/pl.jsonl" bash -c '. "$1"; freeze_boot_already 1786686150' _ "$D/lib.sh"
  [ "$status" -eq 0 ] || false                         # 1 s off ⇒ the same boot
  run env PANIC_LEDGER="$D/pl.jsonl" bash -c '. "$1"; freeze_boot_already 1786686200' _ "$D/lib.sh"
  [ "$status" -ne 0 ] || false                         # 51 s off ⇒ genuinely another boot
  # End to end: the same freeze re-scanned with a jittered boot writes ONE row, not two.
  mkstubs 100000 0 0
  mkfreezestubs "$BOOTS" "force_off"
  mkresetcounter "ResetCounter-x.diag" "btn_rst force_off" "$BOOTSTAMP"
  fz >/dev/null 2>&1
  mkfreezestubs "$((BOOTS + 1))" "force_off"
  fz >/dev/null 2>&1
  [ "$(grep -c . "$D/fz.jsonl")" -eq 1 ] || false
}

@test "single instance: a live duplicate exits 0 before the loop; --ticks runs skip the mutex" {
  # SIX live sentinels were observed minutes after the panic-#5 reboot — six actuators racing one
  # freeze ledger. Identity is (pid,lstart), the same compare every signal path uses, so a STALE
  # pidfile (dead pid, or a reused pid with a different lstart) can never block a start — that
  # branch is the lstart mismatch already proven throughout §8c/§8e.
  mkstubs 800000 0 0
  mkcohort "$(printf '7001\tMon 24 Aug 20:00:00 2026')"          # ps -p map for proc_lstart
  printf '7001\nMon 24 Aug 20:00:00 2026\n' > "$D/cs.pid"        # PIDFILE derives from LOG
  # `timeout` IS NOT ON THE STOCK macOS PATH — it is coreutils, and bats runs this case with
  # PATH=.../usr/bin:/bin:/usr/sbin:/sbin, so a BARE `timeout` here resolved to nothing and the case
  # failed 127 ("command not found") on every run, on trunk, regardless of the subject. That is the
  # same class `scripts/unattended-path-lint.sh` exists to stop, reproduced inside the suite that
  # lints it. Resolve an ABSOLUTE binary (the repo's idiom: store the path `command -v` prints, never
  # the bare name) and SKIP when the box has none — a case that cannot run must say so rather than
  # report a verdict about the subject (memory: a gate refusal is not a gate result).
  local TO=""
  for c in "$(command -v gtimeout 2>/dev/null || true)" "$(command -v timeout 2>/dev/null || true)" \
           /opt/homebrew/bin/gtimeout /opt/homebrew/bin/timeout /usr/local/bin/gtimeout /usr/local/bin/timeout; do
    # AN `if`, NOT AN `A && B` CHAIN, and the shape is load-bearing twice over. This is candidate
    # SELECTION, not an assertion: a candidate that does not exist is the NORMAL case, so a failing
    # test here would be the loop working. The dead-assertion ratchet cannot tell the two apart from
    # an `&&` chain, and its fixer appended `|| false` — which under errexit fails the case on the
    # FIRST empty candidate. The gate says a decline is a hand-edit verified in both directions;
    # this one is verified by the pair below (a box WITH a timeout runs the case, a box without SKIPs).
    if [ -n "$c" ] && [ -x "$c" ]; then TO="$c"; break; fi
  done
  [ -n "$TO" ] || skip "no timeout(1) on this box — the mutex case needs a bounded run"
  run "$TO" 10 env PATH="$STUB:$PATH" PSMAP="$PSMAP" CC_SENTINEL_LOG="$LOG" \
      CC_PANIC_SCAN=off CC_FREEZE_SCAN=off bash "$S"             # TICKS=0: the daemon path
  [ "$status" -eq 0 ] || false                                   # a 124 here = the mutex did NOT fire
  echo "$output" | grep -q 'another live instance' || false
  [ "$(rows)" = "0" ] || false
  # CONTROL: a bounded run (the smoke, this suite) skips the mutex and proceeds under the same
  # pidfile — refusing hand-runs while the daemon lives would make every smoke read as broken.
  run env PATH="$STUB:$PATH" PSMAP="$PSMAP" CC_SENTINEL_LOG="$LOG" \
      CC_PANIC_SCAN=off CC_FREEZE_SCAN=off bash "$S" --ticks 1
  [ "$status" -eq 0 ] || false
  [ "$(rows)" = "1" ] || false
}

# ══ 5d. THE 2026-09-16 PANICS — the cohort is no longer an allow-list of one name ═════════════════
#
# Two watchdog panics, 35 minutes apart (15:54:00 and 16:28:56), same class, same 100 %-of-segments
# verdict, killed by TEN `clang-format` processes carrying 242 GB and 274 GB of anonymous footprint
# on a 64 GB box. The sentinel detected both storms early and correctly and then SIGSTOPped **zero
# processes on all twelve trips**, because `select_stop_targets` tested the executable NAME against
# `^node`. Full record: docs/research/kernel-watchdog-panic-2026-09-16.md.
#
# THE PRE-FIX ARTIFACT IS PINNED AND MARKED, for the reason setup() already gives at length:
# `origin/main` moves, and the moment this fix lands there an unpinned control would replay the
# POST-fix code and compare the fix to itself — green forever, asserting nothing. a37feb5a9 is the
# commit immediately before this change (its tree carries the diagnosis, not the repair), and
# `b !~ /^node/` is the literal this diff DELETES, so its presence proves the artifact is the old one.
prefix_lib() {
  [ -s "$D/prelib2.sh" ] && return 0
  git -C "$REPO" show a37feb5a9:scripts/compressor-sentinel.sh 2>/dev/null \
    | sed -n '/^[a-z_]*() {/,/^}/p' > "$D/prelib2.sh"
  [ -s "$D/prelib2.sh" ] || skip "pre-fix commit a37feb5a9 unavailable (shallow clone?)"
  grep -q 'b !~ /\^node/' "$D/prelib2.sh" || false     # the marker: this MUST be the pre-fix code
}

# The ten real rows, transcribed from the trip the sentinel itself wrote 22 s after the generator
# started: ~/.claude/logs/compressor-sentinel-snap.log, `═══ TRIP 2026-09-16T20:46:29Z ═══`.
# `ps -axwwo pid=,ppid=,rss=,args=` shape, exactly as the actuator reads it.
storm_rows() {
  printf '%s\n' \
    '92423 91887 971504 clang-format --style=file:.clang-format --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/xxhash.h' \
    '92469 91887 922288 clang-format --style=file:.clang-format --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/simde/x86/avx.h' \
    '92467 91887 905600 clang-format --style=file:.clang-format --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/simde/x86/avx2.h' \
    '92462 91887 877520 clang-format --style=file:.clang-format --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/simde/x86/fma.h' \
    '92461 91887 875552 clang-format --style=file:.clang-format --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/simde/x86/sse4.2.h' \
    '92458 91887 732112 clang-format --style=file:.clang-format --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/simde/wasm/simd128.h' \
    '92459 91887 695040 clang-format --style=file:.clang-format --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/simde/wasm/relaxed-simd.h' \
    '92476 91887 675328 clang-format --style=file:.clang-format --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/simde/x86/mmx.h' \
    '96492 91887 655648 clang-format --style=file:.clang-format --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/simde/x86/sse4.1.h' \
    '92460 91887 616928 clang-format --style=file:.clang-format --assume-filename=/private/tmp/kitty-dev/dependencies/darwin-arm64/include/simde/mips/msa.h' \
    '91887 91880 32768 python3 ./autoformat'
}

# The matching exe_table capture. HAND-WRITTEN rather than derived by mkexe, and that is the point of
# the case: argv[0] for these is the BARE word `clang-format` (the agent put an Xcode toolchain on
# PATH and invoked it by name), while exe_table reads `comm`, which is the resolved ABSOLUTE PATH.
# A fixture that derived the path from argv[0] would hold constant the one axis under test.
# The census roster as it stood one tick before the generator started: the shell that launched
# autoformat and launchd, and NOT the storm. An empty roster would make the case vacuous — the
# generic arm stands down without a baseline, so every row would be excluded for the wrong reason.
PRESTORM=" 1 91880 633 "
storm_exe() {
  local CF='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-format'
  local PY='/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python'
  { for pid in 92423 92469 92467 92462 92461 92458 92459 92476 96492 92460; do
      printf '%s 91887 900000 clang-format %s 0\n' "$pid" "$CF"; done
    printf '91887 91880 32768 Python %s 0\n' "$PY"
  } > "$D/exe.storm"
}

@test "PANIC 2026-09-16 RED-PROOF: the ten clang-format rows are selected — pre-fix selects NONE" {
  storm_exe
  # PRE-FIX: the real artifact, the real rows. This is the twelve-trip `cohort_n=0` reproduced.
  prefix_lib
  run env bash -c '. "$1"; select_stop_targets "$2" "$3" 102400 200' \
    _ "$D/prelib2.sh" "$D/exe.storm" "$PRESTORM" <<< "$(storm_rows)"
  [ "$status" -eq 0 ] || false
  [ -z "$output" ] || false                       # ← the panic, in one assertion
  # POST-FIX: all ten, and the spawner too (it is over the floor and unprotected).
  run env bash -c '. "$1"; select_stop_targets "$2" "$3" 102400 200' \
    _ "$D/lib.sh" "$D/exe.storm" "$PRESTORM" <<< "$(storm_rows)"
  [ "$status" -eq 0 ] || false
  [ "$(awk '$3 == "clang-format"' <<< "$output" | wc -l | tr -d ' ')" -eq 10 ] || false
}

@test "PANIC 2026-09-16: the parent-breaker now reaches the autoformat spawner — pre-fix it could not" {
  storm_exe
  local cohort=" 92423 92469 92467 92462 92461 92458 92459 92476 96492 92460 "
  prefix_lib
  run env bash -c '. "$1"; select_break_parents "$2" "$3" 3 4 70001 70002' \
    _ "$D/prelib2.sh" "$D/exe.storm" "$cohort" <<< "$(storm_rows)"
  # Pre-fix the cohort was EMPTY, so this is the honest replay: no cohort, no parent, and the log
  # line the box actually printed — "no eligible parent owns >= 3 of the 0 selected burst procs".
  run env bash -c '. "$1"; select_break_parents "$2" "$3" 3 4 70001 70002' \
    _ "$D/prelib2.sh" "$D/exe.storm" "$PRESTORM" <<< "$(storm_rows)"
  [ -z "$output" ] || false
  # POST-FIX, with the cohort the repaired selector produces: pid 91887 owns all ten.
  run env bash -c '. "$1"; select_break_parents "$2" "$3" 3 4 70001 70002' \
    _ "$D/lib.sh" "$D/exe.storm" "$cohort" <<< "$(storm_rows)"
  [ "$status" -eq 0 ] || false
  [ "$(awk 'NR==1 {print $1, $2}' <<< "$output")" = "91887 10" ] || false
}

@test "NEAR-MISS: a toolchain binary inside an .app bundle stays selectable" {
  # `.app/Contents/MacOS/` was the obvious way to spare the operator's GUI apps, and it is NOT used,
  # because BOTH of the 2026-09-16 generators would have escaped a naive /Applications test and the
  # SPAWNER would have escaped the bundle test itself: python3 on this box is Xcode's
  # Python.app/Contents/MacOS/Python — a framework stub, not a GUI app. Pin both directions.
  printf '%s\n' \
    '92423 91887 900000 clang-format --assume-filename=/x/simde/x86/avx512.h' \
    '91887 91880 900000 python3 ./autoformat' > "$D/rows.nm"
  printf '92423 91887 900000 clang-format /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-format 0\n91887 91880 900000 Python /Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python 0\n' > "$D/exe.nm"
  run env bash -c '. "$1"; select_stop_targets "$2" "$3" 102400 200' \
    _ "$D/lib.sh" "$D/exe.nm" "$PRESTORM" < "$D/rows.nm"
  [ "$(wc -l <<< "$output" | tr -d ' ')" -eq 2 ] || false
}

@test "NEGATIVE CONTROL: an Apple daemon is never selectable, however new and however large" {
  # The measured residue of the 60 s newness control on a healthy box was exactly two processes:
  # /usr/libexec/coreduetd and a `(git)` in parentheses. These two rules are why it is now zero.
  printf '336 1 900000 /usr/libexec/coreduetd\n302 1 900000 /usr/libexec/logd\n99 1 900000 /System/Library/CoreServices/x\n1 0 900000 /sbin/launchd\n' > "$D/rows.d"
  mkexe "$(cat "$D/rows.d")"
  run env bash -c '. "$1"; select_stop_targets "$2" "$3" 102400 200' _ "$D/lib.sh" "$D/exe" "$PRESTORM" < "$D/rows.d"
  [ -z "$output" ] || false
  # POSITIVE CONTROL: the identical shape under a non-system path IS selected, so the emptiness
  # above is the exclusion working rather than the selector being broken.
  printf '336 1 900000 /opt/homebrew/bin/clang-format x.h\n' > "$D/rows.p"
  mkexe "$(cat "$D/rows.p")"
  run env bash -c '. "$1"; select_stop_targets "$2" "$3" 102400 200' _ "$D/lib.sh" "$D/exe" "$PRESTORM" < "$D/rows.p"
  [ "$output" = "336 900000 clang-format" ] || false
}

@test "FAIL CLOSED: an exe row that cannot name a process by absolute path is PROTECTED" {
  # `(git)` — ps renders an exiting process's comm in parentheses. UNIDENTIFIABLE ⇒ NEVER ACTED ON
  # is this file's polarity, and a safety flag must fail toward protection, never toward selection
  # (memory: gate-default-decides-failure-direction). A SHORT row — one written before field 6
  # existed — must read the same way.
  printf '76746 1 900000 git gc --auto\n76747 1 900000 worker --run\n' > "$D/rows.u"
  printf '76746 1 900000 (git) (git) 1\n76747 1 900000 worker\n' > "$D/exe.u"   # row 2 has NO field 6
  run env bash -c '. "$1"; select_stop_targets "$2" "$3" 102400 200' _ "$D/lib.sh" "$D/exe.u" "$PRESTORM" < "$D/rows.u"
  [ -z "$output" ] || false
}

@test "claude.exe is STILL never stopped once the name allow-list is gone" {
  # The widening's most important regression: before this diff `^node` excluded claude.exe for free.
  # Now the exclusion has to be doing the work itself, so assert it against a clean absolute path.
  printf '901 1 4000000 /Users/x/.claude-260/node_modules/.bin/claude --permission-mode auto\n902 1 4000000 /usr/local/bin/claude serve\n903 1 4000000 /opt/x/bin/worker --mcp-server\n' > "$D/rows.c"
  mkexe "$(cat "$D/rows.c")"
  run env bash -c '. "$1"; select_stop_targets "$2" "$3" 102400 200' _ "$D/lib.sh" "$D/exe" "$PRESTORM" < "$D/rows.c"
  [ -z "$output" ] || false
}

@test "the census roster is name-agnostic and floored; its three NUMBERS stay node-only" {
  # The roster generalises (that IS the repair); n/orph/nrss must not, because 70,000+ logged rows
  # already mean "node" by those keys.
  cat > "$STUB/ps" <<'PSEOF'
#!/bin/sh
printf '%s\n' \
  '400 1 900000 /opt/homebrew/bin/node' \
  '401 1 900000 /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-format' \
  '402 1 900000 /usr/libexec/coreduetd' \
  '403 1   5000 /opt/homebrew/bin/tiny'
PSEOF
  chmod +x "$STUB/ps"
  run env PATH="$STUB:$PATH" bash -c '. "$1"; census 102400' _ "$D/lib.sh"
  [ "${output%%|*}" = "1 1 878 " ] || [ "${output%%|*}" = "1 1 878" ] || false   # node numbers: 1 proc
  local roster="${output#*|}"
  [[ "$roster" == *" 400 "* || "$roster" == *" 400" ]] || false   # node: on the roster
  [[ "$roster" == *" 401 "* || "$roster" == *" 401" ]] || false   # clang-format: on it too (the repair)
  [[ "$roster" != *" 402"* ]] || false                            # Apple daemon: never
  [[ "$roster" != *" 403"* ]] || false                            # under the floor: never
}

@test "ACT_MIN_COHORT: a one-off is not a storm, and the withholding is logged as a decision" {
  # A single freshly-spawned unprotected process over the floor became selectable when the cohort
  # stopped being name-keyed. Signals are withheld below the floor; the trip, snapshot and page have
  # already happened. Ten — the smallest cohort either 2026-09-16 panic produced — clears it.
  grep -q 'ACT_MIN_COHORT="\${CC_SENTINEL_ACT_MIN_COHORT:-3}"' "$S" || false
  grep -q 'actuator: HELD cohort_n=' "$S" || false
  # THE FLOOR IS SCOPED TO THE NEW CLASS. A cohort holding a node-named member is one the pre-fix
  # selector would also have produced, so the floor must not touch it — the write-ahead case above
  # asserts cohort_n=1 on exactly that shape and is the control that caught an unscoped floor
  # silently changing shipped behaviour. Assert the node escape hatch is present and is an AND.
  grep -q 'COHORT_NODE_N.*awk .\$3 ~ /\^node/' "$S" || false
  grep -q '\[ "\$COHORT_NODE_N" -eq 0 \]; then' "$S" || false
}

@test "NO BASELINE, NO GENERIC ARM: an unobserved population is not a burst" {
  # CENSUS_PIDS is empty for the first CENSUS_EVERY ticks of every daemon start — the minute after a
  # reboot, which is exactly when a box recovering from one panic is rebuilding toward the next. An
  # empty roster is NOT evidence that nothing was running; it is evidence that nothing was observed.
  # Without this guard the generic cohort reads the entire live desktop as newly-spawned.
  printf '906 1 4000000 /Applications/Cursor.app/Contents/MacOS/Cursor\n907 1 4000000 /opt/homebrew/bin/clang-format x.h\n908 1 4000000 /opt/homebrew/bin/node w.js\n' > "$D/rows.nb"
  mkexe "$(cat "$D/rows.nb")"
  run env bash -c '. "$1"; select_stop_targets "$2" "$3" 102400 200' _ "$D/lib.sh" "$D/exe" "" < "$D/rows.nb"
  [ "$output" = "908 4000000 node" ] || false        # the node arm only: unchanged from before this diff
  # WITH a baseline the same three rows give the generic cohort. This pair is the whole guard.
  run env bash -c '. "$1"; select_stop_targets "$2" "$3" 102400 200' _ "$D/lib.sh" "$D/exe" " 1 2 " < "$D/rows.nb"
  [ "$(echo "$output" | wc -l | tr -d ' ')" = "3" ] || false
}

@test "END TO END 2026-09-16: the whole actuator path reaches the clang-format storm and its spawner" {
  # THE INTEGRATION CLAIM THE UNIT CASES DO NOT MAKE. §5d proves the SELECTOR selects the ten rows
  # when handed a roster; it says nothing about whether the daemon, driving itself, ever gets there.
  # That path has four gates in series and each can silently empty the set: the census must have
  # taken a baseline (no baseline ⇒ the generic arm stands down), the storm must be NEW against it,
  # the path-protection flag must not forbid it, and the parent-breaker must then attribute it. This
  # case runs all four in one daemon, against the real 2026-09-16 shape.
  #
  # THE FIXTURE IS TICK-AWARE, which is what makes the newness gate real rather than assumed: the
  # box is quiet for two ticks so a census records a PRE-STORM roster, and only then does the storm
  # appear — exactly the ordering of the incident, where the census ran at 20:45:57 and autoformat
  # started at 20:46:07. A static fixture cannot express it: the storm would be in the very roster
  # that is supposed to predate it, and the case would pass for the wrong reason.
  mkstubs "$(printf '800000\n800000\n2600000\n2600000')" 0 0

  CF='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-format'
  PY='/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python'
  # Impossible pids, as §5b does: nothing on this machine can be signalled by this test, so the
  # verdict is read from the actuator's own INTENT and attribution lines, never from a delivered
  # signal. `SIGSTOPped 0` is therefore the EXPECTED tail and is not what is being asserted.
  : > "$D/pre.census"; : > "$D/pre.act"; : > "$D/storm.census"; : > "$D/storm.act"
  # THE PRE-STORM POPULATION MUST CONTAIN SOMETHING OVER THE ACTUATOR FLOOR, and the first draft of
  # this case did not — so the census roster came back EMPTY, the no-baseline guard fired, and the
  # generic arm correctly stood down. That read as the fix failing when it was the fixture failing.
  # A long-running editor over the floor is both realistic (the live box had 87 such processes) and
  # load-bearing: it is on the roster, so it is NOT new, so sparing it is the assertion that
  # separates "selected the storm" from "selected everything above the floor".
  # 999795 (redis-server) is the LIVE positive control on the newness gate. Since 2026-09-30 the
  # Cursor row is spared by class 2 (a launchd-started GUI bundle), not by newness, so without a
  # second long-running process over the floor the assertion below it would no longer exercise the
  # gate at all (memory: sibling-guard-makes-the-fixture-vacuous).
  printf '999790 1 900000 /Applications/Cursor.app/Contents/MacOS/Cursor\n999795 1 900000 /opt/homebrew/bin/redis-server\n999800 1 40000 /bin/zsh\n999801 999800 32768 %s\n' "$PY" > "$D/pre.census"
  printf '999790 1 900000 /Applications/Cursor.app/Contents/MacOS/Cursor\n999795 1 900000 /opt/homebrew/bin/redis-server\n999800 1 40000 /bin/zsh -l\n999801 999800 32768 python3 ./autoformat\n' > "$D/pre.act"
  cp "$D/pre.census" "$D/storm.census"; cp "$D/pre.act" "$D/storm.act"
  for p in 999810 999811 999812 999813 999814 999815 999816 999817 999818 999819; do
    printf '%s 999801 900000 %s\n' "$p" "$CF" >> "$D/storm.census"
    printf '%s 999801 900000 clang-format --style=file:.clang-format --assume-filename=/x/dependencies/simde/x86/avx512.h\n' "$p" >> "$D/storm.act"
  done

  cat > "$STUB/ps" <<'SH'
#!/bin/bash
# TICKF is bumped once per tick by the sysctl stub, so it reads N-1 during tick N. The storm
# arrives at tick 3, AFTER the census at tick 2 has recorded the quiet population.
# THE THRESHOLD IS 3, AND IT WAS MEASURED, NOT REASONED. The tick file is bumped by the sysctl
# stub BEFORE the census reads ps, so it already reads 2 on the census tick — a stub switching at
# >=2 hands the census the storm itself, the ten pids land on the roster, and they are then never
# "new". That produced a perfect cohort_n=0: the fix looking broken because the fixture had quietly
# removed the one condition it exists to test. Traced: comm at 2 (census), comm+args at 3 (trip).
if [ "$(cat "$TICKF")" -ge 3 ]; then P="$STORM_CENSUS"; A="$STORM_ACT"; else P="$PRE_CENSUS"; A="$PRE_ACT"; fi
case "$*" in
  *"pid=,ppid=,rss=,pcpu=,args="*) cat "$A" 2>/dev/null ;;
  *"pid=,ppid=,rss=,args="*)       cat "$A" 2>/dev/null ;;
  *"pid=,ppid=,rss=,comm="*)       cat "$P" 2>/dev/null ;;
  *) echo "stub-ps $*" ;;
esac
SH
  chmod +x "$STUB/ps"
  export PRE_CENSUS="$D/pre.census" PRE_ACT="$D/pre.act" \
         STORM_CENSUS="$D/storm.census" STORM_ACT="$D/storm.act"

  # ACT=observe, NOT stop, and it is the stronger choice rather than the timid one. Observe runs the
  # ENTIRE selection and attribution path and signals nothing, so every process the actuator would
  # touch is NAMED in the log. Under ACT=stop the per-target lines are written only after a
  # successful kill(2), and these are deliberately impossible pids, so the naming would be
  # unreachable and the case could only ever assert a summary count.
  CENSUS_EVERY=2 ACT=observe run_daemon 4

  # 1. THE COHORT IS THE STORM. Ten, not zero — the twelve real trips printed cohort_n=0.
  grep -qE 'actuator: INTENT WOULD-STOP cohort_n=10 ' "$SNAPLOG" || false
  [ "$(grep -c 'WOULD-STOP pid=9998' "$SNAPLOG")" -ge 10 ] || false
  # 2. THE SPAWNER IS ATTRIBUTED BY NAME. The parent-breaker needs a non-empty cohort to count
  #    against; on the day it printed "no eligible parent owns >= 3 of the 0 selected burst procs".
  grep -qE 'parent-break .* 1 spawner\(s\), each owning >= 3 of the 10 selected burst procs' "$SNAPLOG" || false
  grep -qF 'WOULD-STOP parent pid=999801 kids=10 comm=Python' "$SNAPLOG" || false
  # 3. THE PRE-STORM POPULATION IS SPARED. The shell that launched it was over no floor and is not
  #    new; asserting its ABSENCE is what separates "selected the storm" from "selected everything".
  ! grep -q 'pid=999800 ' "$SNAPLOG" || false
  # 4. AND THE LONG-RUNNING PROCESSES ARE SPARED THOUGH THEY ARE 900 MB. redis-server is unprotected
  #    by path and by class: the only thing keeping it out is that the census saw it a tick earlier.
  #    This is the newness gate. The editor is spared too, now by class 2 (a GUI bundle launchd
  #    started) — which is why redis, not Cursor, is the row that keeps the newness gate under test.
  ! grep -q 'pid=999795 ' "$SNAPLOG" || false
  ! grep -q 'pid=999790 ' "$SNAPLOG" || false
}

# ══ 5e. 2026-09-30 — THE OPERATOR'S APPS ARE NOT A STORM ═════════════════════════════════════════
#
# A browser starts a FRESH renderer per tab, so the newness gate that was supposed to keep GUI apps
# out of the generic cohort lets every recently-opened tab in. Three of them clear ACT_MIN_COHORT,
# the browser then owns the whole burst, and the parent-breaker freezes the browser. Since 790f2dc2d:
# 7 Dia parent freezes and 4 Dia SIGKILLs, the latest at 2026-09-30T15:51:34Z. exe_table field 6 is
# now a CLASS, and 2 (operator GUI app) / 3 (simulator OS image) are never selectable.
#
# THE PRE-FIX ARTIFACT, pinned and marked for the reason setup() gives: 861bc8a95 is the last commit
# before the class existed, and `exe_classify` is the identifier this change INTRODUCES, so its
# absence proves the replayed code is the old one.
prefix_lib3() {
  [ -s "$D/prelib3.sh" ] && return 0
  git -C "$REPO" show 861bc8a95:scripts/compressor-sentinel.sh 2>/dev/null \
    | sed -n '/^[a-z_]*() {/,/^}/p' > "$D/prelib3.sh"
  [ -s "$D/prelib3.sh" ] || skip "pre-fix commit 861bc8a95 unavailable (shallow clone?)"
  ! grep -q 'exe_classify' "$D/prelib3.sh" || false
  grep -q '^exe_table() {' "$D/prelib3.sh" || false        # …and it IS a sentinel lib, not an empty file
}

# THE WHOLE TRIP-TIME PATH through a <lib>, under launchd's interpreter: `exe_table gui` over the
# stubbed ps (PS_CENSUS comm rows, PS_ARGV args rows), then the cohort and the parent-breaker over
# PS_ACT, exactly as the loop chains them. Sets RP_COHORT (" pid pid ") and RP_PARENTS ("line;line;").
# A pre-fix lib ignores the `gui` argument, which is the point: it replays what the box actually ran.
replay_trip() { # <lib> <roster> [<floor> <cap>]
  run env PATH="$STUB:$PATH" /bin/bash -c '. "$1"; exe_table gui' _ "$1"
  [ "$status" -eq 0 ] || false
  printf '%s\n' "$output" > "$D/rp.exe"
  run /bin/bash -c '. "$1"; select_stop_targets "$2" "$3" "$4" "$5"' _ "$1" "$D/rp.exe" "$2" "${3:-40960}" "${4:-400}" < "$PS_ACT"
  [ "$status" -eq 0 ] || false
  RP_COHORT=" $(awk '$1 ~ /^[0-9]+$/ { printf "%s ", $1 }' <<< "$output")"
  run /bin/bash -c '. "$1"; select_break_parents "$2" "$3" 3 4 70001 70002' _ "$1" "$D/rp.exe" "$RP_COHORT" < "$PS_ACT"
  [ "$status" -eq 0 ] || false
  RP_PARENTS="$(printf '%s\n' "$output" | awk 'NF { printf "%s;", $0 }')"
}

# The args fixture for `ps -axwwo pid=,args=` derived from an actuator table: drop ppid and rss.
argv_of() { awk '$1 ~ /^[0-9]+$/ { $2 = ""; $3 = ""; print }' "$1"; }

DIA='/Applications/Dia.app/Contents/MacOS/Dia'
DIAR='/Applications/Dia.app/Contents/Frameworks/ArcCore.framework/Helpers/Browser Helper (Renderer).app/Contents/MacOS/Browser Helper (Renderer)'

@test "exe_classify: every row gets its class — GUI roots and helpers 2, the near-misses 0, simulator OS 3" {
  have_arm exe_classify
  local SIM='/Library/Developer/CoreSimulator/Volumes/iOS_22A/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.0.simruntime/Contents/Resources/RuntimeRoot'
  local GC='/Applications/Google Chrome.app/Contents'
  local GCR="$GC/Frameworks/Google Chrome Framework.framework/Versions/140/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
  local PYS='/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python'
  {
    printf '@A 200\n'
    printf '5 99 90000 /Applications/Slack.app/Contents/Frameworks/Slack Helper (Renderer).app/Contents/MacOS/Slack Helper (Renderer)\n'
    printf '100 1 400000 %s\n101 100 90000 %s\n' "$DIA" "$DIAR"
    printf '102 100 51744 /Applications/Dia.app/Contents/Resources/agent-server-resources/dist/agent-server\n'
    printf '110 1 200000 %s/MacOS/Google Chrome\n111 110 90000 %s\n' "$GC" "$GCR"
    printf '120 1 300000 /Applications/kitty.app/Contents/MacOS/kitty\n121 120 20000 /Applications/kitty.app/Contents/MacOS/kitten\n'
    printf '130 1 90000 /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator\n'
    printf '140 1 90000 /Applications/OneDrive.app/Contents/OneDrive Sync Service.app/Contents/MacOS/OneDrive Sync Service\n'
    printf '150 1 90000 /Applications/Utilities/Adobe Creative Cloud Experience/CCXProcess/CCXProcess.app/Contents/MacOS/CCXProcess\n'
    printf '160 1 90000 /Users/x/Applications/VoiceInk.app/Contents/MacOS/VoiceInk\n'
    printf '200 1 200000 %s/MacOS/Google Chrome\n201 200 90000 %s\n' "$GC" "$GCR"
    printf '300 120 200000 /opt/homebrew/bin/node\n'
    printf '400 1 32768 %s\n410 1 900000 /Applications/Xcode.app/Contents/MacOS/Xcode\n411 410 32768 %s\n' "$PYS" "$PYS"
    printf '420 411 900000 /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-format\n'
    printf '430 1 90000 /Users/x/Library/Developer/CoreSimulator/Devices/0A1B/data/Containers/Bundle/Application/2C3D/MyApp.app/MyApp\n'
    printf '500 1 90000 %s/usr/libexec/lsd\n' "$SIM"
    printf '600 1 90000 /usr/libexec/coreduetd\n601 1 90000 (git)\n602 1 90000 node\n'
    printf '99 1 300000 /Applications/Slack.app/Contents/MacOS/Slack\n'
  } > "$D/cls.in"
  run /bin/bash -c '. "$1"; exe_classify gui' _ "$D/lib.sh" < "$D/cls.in"
  [ "$status" -eq 0 ] || false
  printf '%s\n' "$output" > "$D/cls.out"
  cls() { awk -v p="$1" '$1 == p { print $6 }' "$D/cls.out"; }
  [ "$(awk 'NF != 6' "$D/cls.out" | wc -l | tr -d ' ')" -eq 0 ] || false          # six fields, always
  [ "$(wc -l < "$D/cls.out" | tr -d ' ')" -eq 25 ] || false                         # markers are not rows
  local p
  for p in 100 101 110 111 120 121 130 140 150 160 99; do [ "$(cls "$p")" = "2" ] || { echo "pid $p: $(cls "$p")"; false; }; done
  [ "$(cls 5)" = "2" ] || false            # PID WRAP: a helper listed before its root still resolves
  for p in 102 200 201 300 400 411 420 430; do [ "$(cls "$p")" = "0" ] || { echo "pid $p: $(cls "$p")"; false; }; done
  [ "$(cls 410)" = "2" ] || false          # the Xcode IDE is an app — its Python stub child is NOT
  [ "$(cls 500)" = "3" ] || false
  for p in 600 601 602; do [ "$(cls "$p")" = "1" ] || { echo "pid $p: $(cls "$p")"; false; }; done
  # Rows of classes 0 and 1 are BYTE-IDENTICAL to the pre-class table's shape: basename and full path
  # underscore-collapsed, field 6 the old flag value.
  grep -qxF '102 100 51744 agent-server /Applications/Dia.app/Contents/Resources/agent-server-resources/dist/agent-server 0' "$D/cls.out" || false
  grep -qxF '601 1 90000 (git) (git) 1' "$D/cls.out" || false
  # PLAIN MODE (the census): no class 2 at all — the same Dia root reads 0 — while class 3 does not
  # depend on the mode.
  run /bin/bash -c '. "$1"; exe_classify' _ "$D/lib.sh" < "$D/cls.in"
  printf '%s\n' "$output" > "$D/cls.out"
  [ "$(cls 100)" = "0" ] || false
  [ "$(cls 101)" = "0" ] || false
  [ "$(cls 500)" = "3" ] || false
  [ "$(awk '$6 == "2"' "$D/cls.out" | wc -l | tr -d ' ')" -eq 0 ] || false
}

@test "RED-PROOF 2026-09-30T15:39:16Z: Dia's fresh renderers froze Dia — pre-fix selects 4 and breaks Dia; now nothing" {
  mkstubs 0 0 0
  printf '18285 1 400000 %s\n' "$DIA" > "$PS_CENSUS"
  printf '18285 1 400000 %s\n' "$DIA" > "$PS_ACT"
  for p in 43930 45904 46829 47473; do
    printf '%s 18285 90000 %s\n' "$p" "$DIAR" >> "$PS_CENSUS"
    printf '%s 18285 90000 %s --type=renderer\n' "$p" "$DIAR" >> "$PS_ACT"
  done
  printf '20405 18285 51744 /Applications/Dia.app/Contents/Resources/agent-server-resources/dist/agent-server\n' | tee -a "$PS_CENSUS" >> "$PS_ACT"
  argv_of "$PS_ACT" > "$PS_ARGV"
  local roster=" 1 18285 20405 "                  # Dia and its agent-server predate the trip
  # PRE-FIX, the real artifact at the live floor and cap: the incident, reproduced.
  prefix_lib3
  replay_trip "$D/prelib3.sh" "$roster"
  [ "$RP_COHORT" = " 43930 45904 46829 47473 " ] || { echo "pre cohort: $RP_COHORT"; false; }
  [ "$RP_PARENTS" = "18285 4 Dia;" ] || { echo "pre parents: $RP_PARENTS"; false; }
  # FIXED: the renderers are class 2 helpers of a class 2 root — no cohort, no spawner.
  replay_trip "$D/lib.sh" "$roster"
  [ "$RP_COHORT" = " " ] || { echo "cohort: $RP_COHORT"; false; }
  [ -z "$RP_PARENTS" ] || { echo "parents: $RP_PARENTS"; false; }
  # POSITIVE CONTROL, same run: the SAME four children under a node parent are a burst and break it —
  # so the silence above is the class, not a selector that stopped working.
  sed -i '' "s|^18285 1 400000 .*|18285 1 400000 /opt/homebrew/bin/node|" "$PS_CENSUS" "$PS_ACT"
  argv_of "$PS_ACT" > "$PS_ARGV"
  replay_trip "$D/lib.sh" "$roster"
  [ "$RP_COHORT" = " 43930 45904 46829 47473 " ] || { echo "control cohort: $RP_COHORT"; false; }
  [ "$RP_PARENTS" = "18285 4 node;" ] || { echo "control parents: $RP_PARENTS"; false; }
}

@test "09-16 STORM through exe_table: the Xcode Python stub stays the spawner under every parent" {
  # The near-miss, now carried by the ppid-1 anchor plus the /Contents/Developer/ carve-out rather
  # than a substring: whether autoformat's python3 was run from a shell, reparented to launchd, or
  # launched by the Xcode IDE (itself a class 2 app), it is NEVER an app, and neither is clang-format.
  local CF='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-format'
  local PYS='/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python'
  local pp
  mkstubs 0 0 0
  for pp in 91880 1 633; do
    printf '1 0 1000 /sbin/launchd\n91880 1 40000 /bin/zsh\n633 1 900000 /Applications/Xcode.app/Contents/MacOS/Xcode\n91887 %s 32768 %s\n' "$pp" "$PYS" > "$PS_CENSUS"
    printf '633 1 900000 /Applications/Xcode.app/Contents/MacOS/Xcode\n91887 %s 32768 python3 ./autoformat\n' "$pp" > "$PS_ACT"
    for p in 92423 92469 92467 92462 92461 92458 92459 92476 96492 92460; do
      printf '%s 91887 900000 %s\n' "$p" "$CF" >> "$PS_CENSUS"
      printf '%s 91887 900000 clang-format --style=file x.h\n' "$p" >> "$PS_ACT"
    done
    argv_of "$PS_ACT" > "$PS_ARGV"
    replay_trip "$D/lib.sh" " 1 91880 633 "
    [ "$(wc -w <<< "$RP_COHORT" | tr -d ' ')" -eq 10 ] || { echo "ppid $pp cohort: $RP_COHORT"; false; }
    [ "$RP_PARENTS" = "91887 10 Python;" ] || { echo "ppid $pp parents: $RP_PARENTS"; false; }
  done
}

@test "kitty-direct: node workers kitty spawned are a burst, but kitty is never their spawner" {
  mkstubs 0 0 0
  printf '73832 1 300000 /Applications/kitty.app/Contents/MacOS/kitty\n73900 73832 20000 /Applications/kitty.app/Contents/MacOS/kitten\n' > "$PS_CENSUS"
  printf '73832 1 300000 /Applications/kitty.app/Contents/MacOS/kitty\n' > "$PS_ACT"
  for p in 80011 80012 80013 80014; do
    printf '%s 73832 200000 /opt/homebrew/bin/node\n' "$p" >> "$PS_CENSUS"
    printf '%s 73832 200000 /opt/homebrew/bin/node w.js\n' "$p" >> "$PS_ACT"
  done
  argv_of "$PS_ACT" > "$PS_ARGV"
  prefix_lib3
  replay_trip "$D/prelib3.sh" " 1 73832 73900 "
  [ "$RP_PARENTS" = "73832 4 kitty;" ] || { echo "pre parents: $RP_PARENTS"; false; }   # the terminal, frozen
  replay_trip "$D/lib.sh" " 1 73832 73900 "
  [ "$RP_COHORT" = " 80011 80012 80013 80014 " ] || { echo "cohort: $RP_COHORT"; false; }
  [ -z "$RP_PARENTS" ] || { echo "parents: $RP_PARENTS"; false; }
}

@test "AUTOMATION REACH: a flagged Chrome at ppid 1 stays breakable; the operator's Chrome beside it does not" {
  # Reparenting to launchd is routine for automation browsers — all twelve ppid-1 Google Chrome roots
  # in the snap log carried --headless, --remote-debugging-port or --user-data-dir — so ppid alone
  # cannot be the GUI test. The argv switch is what keeps the 177-stop automation class reachable.
  local GC='/Applications/Google Chrome.app/Contents'
  local GCR="$GC/Frameworks/Google Chrome Framework.framework/Versions/140/Helpers/Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)"
  mkstubs 0 0 0
  printf '30035 1 200000 %s/MacOS/Google Chrome\n40000 1 200000 %s/MacOS/Google Chrome\n' "$GC" "$GC" > "$PS_CENSUS"
  printf '30035 1 200000 %s/MacOS/Google Chrome --headless=new --remote-debugging-port=9987 --user-data-dir=/tmp/bf-1\n40000 1 200000 %s/MacOS/Google Chrome\n' "$GC" "$GC" > "$PS_ACT"
  for p in 30101 30102 30103; do
    printf '%s 30035 90000 %s\n' "$p" "$GCR" >> "$PS_CENSUS"; printf '%s 30035 90000 %s --type=renderer\n' "$p" "$GCR" >> "$PS_ACT"
  done
  for p in 40101 40102 40103; do
    printf '%s 40000 90000 %s\n' "$p" "$GCR" >> "$PS_CENSUS"; printf '%s 40000 90000 %s --type=renderer\n' "$p" "$GCR" >> "$PS_ACT"
  done
  argv_of "$PS_ACT" > "$PS_ARGV"
  replay_trip "$D/lib.sh" " 1 30035 40000 "
  [ "$RP_COHORT" = " 30101 30102 30103 " ] || { echo "cohort: $RP_COHORT"; false; }
  [ "$RP_PARENTS" = "30035 3 Google_Chrome;" ] || { echo "parents: $RP_PARENTS"; false; }
}

@test "END TO END 2026-09-30: under /bin/bash, the storm is stopped and Dia's new tabs are spared and COUNTED" {
  # The L2123 end-to-end with Dia added at the live floor (40960 kB): a Dia that has been up for
  # hours, two old renderers, four renderers opened in the minute before the storm, a long-running
  # redis, and the 2026-09-16 clang-format storm. Run by /bin/bash explicitly — launchd's
  # interpreter is 3.2, and this is the one case that drives the whole loop through it.
  mkstubs "$(printf '800000\n800000\n2600000\n2600000')" 0 0
  local CF='/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang-format'
  local PYS='/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python'
  {
    printf '999700 1 400000 %s\n999701 999700 90000 %s\n999702 999700 90000 %s\n' "$DIA" "$DIAR" "$DIAR"
    printf '999795 1 900000 /opt/homebrew/bin/redis-server\n999800 1 40000 /bin/zsh\n999801 999800 32768 %s\n' "$PYS"
  } > "$D/pre.census"
  {
    printf '999700 1 400000 %s\n999701 999700 90000 %s --type=renderer\n999702 999700 90000 %s --type=renderer\n' "$DIA" "$DIAR" "$DIAR"
    printf '999795 1 900000 /opt/homebrew/bin/redis-server\n999800 1 40000 /bin/zsh -l\n999801 999800 32768 python3 ./autoformat\n'
  } > "$D/pre.act"
  cp "$D/pre.census" "$D/storm.census"; cp "$D/pre.act" "$D/storm.act"
  for p in 999703 999704 999705 999706; do
    printf '%s 999700 90000 %s\n' "$p" "$DIAR" >> "$D/storm.census"
    printf '%s 999700 90000 %s --type=renderer\n' "$p" "$DIAR" >> "$D/storm.act"
  done
  for p in 999810 999811 999812 999813 999814 999815 999816 999817 999818 999819; do
    printf '%s 999801 900000 %s\n' "$p" "$CF" >> "$D/storm.census"
    printf '%s 999801 900000 clang-format --style=file x.h\n' "$p" >> "$D/storm.act"
  done
  # Same tick-aware switch as the L2123 case (storm from tick 3, after the tick-2 census), plus the
  # two reads exe_table adds: kernel exec names (none here) and the pid,args automation read.
  cat > "$STUB/ps" <<'SH'
#!/bin/bash
if [ "$(cat "$TICKF")" -ge 3 ]; then P="$STORM_CENSUS"; A="$STORM_ACT"; else P="$PRE_CENSUS"; A="$PRE_ACT"; fi
case "$*" in
  *"pid=,ucomm="*)                 : ;;
  *"pid=,args="*)                  awk '{ $2 = ""; $3 = ""; print }' "$A" ;;
  *"pid=,ppid=,rss=,pcpu=,args="*) cat "$A" 2>/dev/null ;;
  *"pid=,ppid=,rss=,args="*)       cat "$A" 2>/dev/null ;;
  *"pid=,ppid=,rss=,comm="*)       cat "$P" 2>/dev/null ;;
  *) echo "stub-ps $*" ;;
esac
SH
  chmod +x "$STUB/ps"
  export PRE_CENSUS="$D/pre.census" PRE_ACT="$D/pre.act" \
         STORM_CENSUS="$D/storm.census" STORM_ACT="$D/storm.act"
  run env PATH="$STUB:$PATH" CC_SENTINEL_LOG="$LOG" CC_SENTINEL_INTERVAL=1 \
    CC_SENTINEL_CENSUS_EVERY=2 CC_SENTINEL_FOLLOWUP_N=1 CC_SENTINEL_FOLLOWUP_SEC=1 \
    CC_SENTINEL_ACT=observe CC_SENTINEL_ACT_RSS_KB=40960 \
    /bin/bash "$S" --ticks 4
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qE 'actuator: INTENT WOULD-STOP cohort_n=10 ' "$SNAPLOG" || false
  grep -qF 'WOULD-STOP parent pid=999801 kids=10 comm=Python' "$SNAPLOG" || false
  # THE BROWSER: never selected, never a spawner — and the sparing is a NUMBER in the record.
  ! grep -q 'comm=Dia' "$SNAPLOG" || false
  ! grep -q 'Browser_Helper' "$SNAPLOG" || false
  grep -qF 'actuator: protected-class spared app=4 sim=0 new over-floor proc(s)' "$SNAPLOG" || false
  # THE NEWNESS GATE, still live beside the class: redis is 900 MB, unprotected, and old.
  ! grep -q 'pid=999795 ' "$SNAPLOG" || false
}

@test "kill_escalate: a ledgered pid the trip's table classes as protected is SIGCONTed and dropped, never killed" {
  have_arm kill_escalate
  mkcohort "$(printf '7001\tMon 30 Sep 15:39:16 2026\n7002\tMon 30 Sep 15:39:17 2026')"
  ledger 7001 "Mon 30 Sep 15:39:16 2026" parent 1000 Dia
  ledger 7002 "Mon 30 Sep 15:39:17 2026" parent 1000 'next-server_(v16.2.6)'
  printf '7001 1 400000 Dia %s 2\n7002 1 700000 next-server_(v16.2.6) /w/.bin/next-server 0\n' "${DIA// /_}" > "$D/exe.k"
  run_ke 1100 climbing-at-60pct "$D/exe.k"
  [ "$output" = "killed=1 spared=1" ] || false
  [ "$(grep -cF -- '-CONT 7001' "$KILLLOG")" -eq 1 ] || false
  [ "$(grep -cF -- '-KILL 7001' "$KILLLOG")" -eq 0 ] || false
  [ "$(grep -cF -- '-KILL 7002' "$KILLLOG")" -eq 1 ] || false            # control: the class-0 spawner IS killed
  grep -qF 'SIGCONT pid=7001 held_s=100 kind=parent comm=Dia reason=protected-at-kill' "$SNAPLOG" || false
  ! grep -q '^7001	' "$FDB" || false                                     # dropped, not re-owed
  # THE FAIL DIRECTION: no capture, and the stub's full table is empty ⇒ the belt ABSTAINS and the
  # rung behaves exactly as before the class existed. (The L1827 case pins the same thing unchanged.)
  mkcohort "$(printf '7001\tMon 30 Sep 15:39:16 2026\n7002\tMon 30 Sep 15:39:17 2026')"
  ledger 7001 "Mon 30 Sep 15:39:16 2026" parent 1000 Dia
  ledger 7002 "Mon 30 Sep 15:39:17 2026" parent 1000 'next-server_(v16.2.6)'
  run_ke 1100 climbing-at-60pct "$D/no-such-exe"
  [ "$output" = "killed=2 spared=0" ] || false
}

@test "release_frozen sweep: a protected row is SIGCONTed and dropped; every other row keeps its hold" {
  have_arm release_frozen
  mkcohort "$(printf '4001\tMon 30 Sep 15:39:16 2026\n4002\tMon 30 Sep 15:39:17 2026')"
  ledger 4001 "Mon 30 Sep 15:39:16 2026" parent 1000 Dia
  ledger 4002 "Mon 30 Sep 15:39:17 2026" proc 1000 node
  run_rel 1900 sweep 0 0 " 4001 "                     # 4002 is 900 s old — past the worker ceiling
  [ "$output" = "released=1 held=1 stale=0" ] || false
  [ "$(grep -cF -- '-CONT 4001' "$KILLLOG")" -eq 1 ] || false
  [ "$(grep -cF -- '-CONT 4002' "$KILLLOG")" -eq 0 ] || false
  grep -qF 'SIGCONT pid=4001 held_s=900 kind=parent comm=Dia reason=protected' "$SNAPLOG" || false
  [ "$(cut -f1 < "$FDB")" = "4002" ] || false
  [ ! -s "$PROBDB" ] || false                          # a protected release is not a spawner on probation
  # CONTROL: the identical ledger under mode=ceiling releases the aged worker — so the hold above is
  # the sweep's scope, not a row the runner could not reach.
  run_rel 1900 ceiling
  [ "$output" = "released=1 held=0 stale=0" ] || false
}

# ══ SELF-RESTART ON CHANGED SOURCE ════════════════════════════════════════════════════════════════
# The land-to-live gap for this daemon closes itself, the way lead-supervisor's already does, so the
# deploy job needs no power to restart it (decision 68d9af489875). The verdict is a pure function;
# the daemon cases below run a COPY of the script so the edit that triggers a restart touches nothing
# in the tree.

@test "self-restart verdict: restarts only on a settled new digest with nothing in custody and no breach" {
  : > "$D/empty.tsv"; printf '1\tx\tworker\t0\tnode\n' > "$D/held.tsv"
  run_fn self_restart_verdict aaa aaa aaa "$D/empty.tsv" 0 0; [ "$output" = "same" ] || false
  run_fn self_restart_verdict ""  bbb bbb "$D/empty.tsv" 0 0; [ "$output" = "abstain" ] || false
  run_fn self_restart_verdict aaa ""  aaa "$D/empty.tsv" 0 0; [ "$output" = "abstain" ] || false
  run_fn self_restart_verdict aaa bbb aaa "$D/empty.tsv" 0 0; [ "$output" = "settling" ] || false
  run_fn self_restart_verdict aaa bbb bbb "$D/held.tsv"  0 0; [ "$output" = "hold-frozen" ] || false
  run_fn self_restart_verdict aaa bbb bbb "$D/empty.tsv" 2 0; [ "$output" = "hold-breach" ] || false
  run_fn self_restart_verdict aaa bbb bbb "$D/empty.tsv" 0 1; [ "$output" = "hold-breach" ] || false
  run_fn self_restart_verdict aaa bbb bbb "$D/nope.tsv"  0 0; [ "$output" = "restart" ] || false
  run_fn self_restart_verdict aaa bbb bbb "$D/empty.tsv" 0 0; [ "$output" = "restart" ] || false
}

sentinel_daemon_bg() { # <script-copy> <errlog> → the DAEMON's pid on stdout; its exit code lands in <errlog>.rc
  # A wrapper subshell owns the daemon so its rc survives: the caller gets this pid from `$(…)`,
  # which makes it no child of the test shell, so `wait` there cannot read it.
  # ACT is off unless the caller sets BG_ACT — the one case that needs an ARMED loop owner is the
  # STARTUP-SWEEP, which runs only when ACT=stop.
  ( env PATH="$STUB:$PATH" CC_SENTINEL_LOG="$LOG" CC_SENTINEL_INTERVAL=1 \
      CC_SENTINEL_SELFCHK_TICKS=1 CC_PANIC_SCAN=off CC_FREEZE_SCAN=off CC_SENTINEL_ACT="${BG_ACT:-off}" \
      bash "$1" 2>"$2" >/dev/null &
    echo $! > "$2.pid"; wait $!; echo $? > "$2.rc" ) >/dev/null 2>&1 &
  local i=0
  while [ ! -s "$2.pid" ] && [ "$i" -lt 40 ]; do sleep 0.05; i=$((i + 1)); done
  cat "$2.pid"
}

wait_exit() { # <pid> <max-seconds> → rc 0 once the pid is gone
  local i=0
  while kill -0 "$1" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -le "$(( $2 * 4 ))" ] || return 1
    sleep 0.25
  done
}

@test "self-restart: a daemon whose source changes exits 0 on its own, and says why" {
  cp "$S" "$D/sentinel-copy.sh"
  pid="$(sentinel_daemon_bg "$D/sentinel-copy.sh" "$D/err.log")"
  sleep 3
  kill -0 "$pid" 2>/dev/null || { cat "$D/err.log" >&2; false; }   # alive before the change
  printf '\n# a landed change\n' >> "$D/sentinel-copy.sh"
  wait_exit "$pid" 15 || { kill "$pid" 2>/dev/null; cat "$D/err.log" >&2; false; }
  i=0; while [ ! -s "$D/err.log.rc" ] && [ "$i" -lt 40 ]; do sleep 0.05; i=$((i + 1)); done
  [ "$(cat "$D/err.log.rc")" = "0" ] || false
  grep -q 'SELF-RESTART on-disk sha256 changed' "$D/err.log" || false
  [ ! -e "${LOG%.jsonl}.pid" ] || false                              # the mutex is released for the successor
}

@test "self-restart: HELD while the freeze ledger is non-empty — the daemon keeps running" {
  # THE PREMISE CHANGED 2026-09-30, AND THE ASSERTION DID NOT. This case used to seed the ledger
  # BEFORE starting an ACT=off daemon — i.e. a disarmed loop owner adopting a predecessor's custody,
  # which is exactly the stranded state RELEASE-ON-DISARM now hands back at startup (the row would be
  # gone before the first self-check, and this case would pass only by pinning the strand). So the
  # row is written AFTER the loop is running: a ledger that is non-empty while the daemon ticks, which
  # is the state the hold exists for (memory: stale-assertion-becomes-an-inverted-guard).
  cp "$S" "$D/sentinel-copy.sh"
  pid="$(sentinel_daemon_bg "$D/sentinel-copy.sh" "$D/err.log")"
  i=0; while [ "$(rows)" -lt 1 ] && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
  [ "$(rows)" -ge 1 ] || { kill "$pid" 2>/dev/null; cat "$D/err.log" >&2; false; }
  printf '%s\t%s\tworker\t%s\tnode\n' 999999 "x" "$(date +%s)" > "${LOG%.jsonl}-frozen.tsv"
  sleep 2
  printf '\n# a landed change\n' >> "$D/sentinel-copy.sh"
  sleep 5
  alive=0; kill -0 "$pid" 2>/dev/null && alive=1
  kill "$pid" 2>/dev/null || true
  [ "$alive" -eq 1 ] || { cat "$D/err.log" >&2; false; }
  grep -q 'SELF-RESTART deferred (hold-frozen)' "$D/err.log" || false
}

@test "self-restart: an unchanged daemon does not restart (control)" {
  cp "$S" "$D/sentinel-copy.sh"
  pid="$(sentinel_daemon_bg "$D/sentinel-copy.sh" "$D/err.log")"
  sleep 5
  alive=0; kill -0 "$pid" 2>/dev/null && alive=1
  kill "$pid" 2>/dev/null || true
  [ "$alive" -eq 1 ] || { cat "$D/err.log" >&2; false; }
  ! grep -q 'SELF-RESTART' "$D/err.log" || false
}

# ══ 5f. 2026-09-30 — CUSTODY READS PROCESS STATE ══════════════════════════════════════════════════
#
# ROOT CAUSE OF THE 15:51:34Z KILL. The lead resumed Dia by hand (SIGCONT), but custody compared only
# (pid, lstart), so row 18285 stayed owed — and the next retrip-over-debt SIGKILLed the browser for
# it. Custody now reads `stat=,lstart=` in the same one fork: a ledgered pid that reads running,
# sleeping or idle past RELINQUISH_GRACE_S was resumed by someone else and is dropped, never killed.
#
# REAL SIGNALS, IN THIS BLOCK ONLY, AND ONLY TO THE TEST'S OWN CHILD: a `sleep` this case started.
# Darwin's report of a stopped task is the premise the relinquish arm rests on, so it is pinned
# against the kernel rather than a stub. The teardown resumes and ends that child whatever happens.
teardown() {
  if [ -n "${CHILD_PID:-}" ]; then kill -CONT "$CHILD_PID" 2>/dev/null || true; kill "$CHILD_PID" 2>/dev/null || true; fi
  if [ -n "${CHILD2_PID:-}" ]; then kill -CONT "$CHILD2_PID" 2>/dev/null || true; kill "$CHILD2_PID" 2>/dev/null || true; fi
  if [ -n "${DAEMON_PID:-}" ]; then kill "$DAEMON_PID" 2>/dev/null || true; fi
  true
}

stat_of() { ps -o stat= -p "$1" 2>/dev/null | tr -d ' '; }

# STOP THE TEST'S OWN CHILD, AND MAKE THE STOP STICK. `kill -STOP` sent right after `sleep … &`
# races the child's exec, and Darwin loses a stop that lands inside exec — measured ~30% of rounds
# under load: the child reads S and finishes its sleep, and the case reddens as "premise refuted"
# when the premise was never tested. So wait until the exec has happened (comm reads `sleep`), THEN
# stop, and re-send the stop on every poll until the state reads T.
stop_own_child() { # <pid> → rc 0 once the child reads T
  local i=0
  while [ "$(ps -o comm= -p "$1" 2>/dev/null | sed 's|.*/||')" != "sleep" ] && [ "$i" -lt 50 ]; do
    sleep 0.05; i=$((i + 1))
  done
  i=0
  while [ "$(stat_of "$1" | cut -c1)" != "T" ] && [ "$i" -lt 40 ]; do
    kill -STOP "$1" 2>/dev/null || true; sleep 0.1; i=$((i + 1))
  done
  [ "$(stat_of "$1" | cut -c1)" = "T" ]
}

# A STOPPED child of this test, ledgered the way record_frozen would have written it.
own_frozen_child() { # <ledger> <age_s>
  sleep 120 & CHILD_PID=$!
  stop_own_child "$CHILD_PID" || false
  printf '%s\t%s\tproc\t%s\tsleep\n' "$CHILD_PID" \
    "$(TZ=UTC ps -o lstart= -p "$CHILD_PID" | tr -s ' ' | sed 's/^ *//;s/ *$//')" \
    "$(( $(date +%s) - $2 ))" > "$1"
}

@test "DARWIN PREMISE: a SIGSTOPped task reads T, and a resumed one does not (own child only)" {
  sleep 30 & CHILD_PID=$!
  stop_own_child "$CHILD_PID" || false
  kill -CONT "$CHILD_PID"
  local i=0; while [ "$(stat_of "$CHILD_PID" | cut -c1)" = "T" ] && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i + 1)); done
  [ -n "$(stat_of "$CHILD_PID")" ] || false                              # still alive: the read is real
  [ "$(stat_of "$CHILD_PID" | cut -c1)" != "T" ] || false
  # And the helper custody uses reads the same state, with lstart byte-identical to proc_lstart.
  run /bin/bash -c '. "$1"; a="$(proc_stat_lstart "$2")"; b="$(proc_lstart "$2")"; [ "${a#* }" = "$b" ] && printf "%s" "${a%% *}"' _ "$D/lib.sh" "$CHILD_PID"
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s' "$output" | cut -c1)" != "T" ] || false
  run /bin/bash -c '. "$1"; proc_stat_lstart 999999' _ "$D/lib.sh"         # a gone pid reads EMPTY
  [ -z "$output" ] || false
}

@test "custody reads process state: a row resumed outside the sentinel is RELINQUISHED — never re-owed" {
  have_arm proc_stat_lstart
  mkcohort "$(printf '5001\tMon 30 Sep 15:39:16 2026\tS\n5002\tMon 30 Sep 15:39:17 2026\tS\n5003\tMon 30 Sep 15:39:18 2026\tT')"
  ledger 5001 "Mon 30 Sep 15:39:16 2026" parent 1000 Dia     # resumed, 40 s old   → relinquished
  ledger 5002 "Mon 30 Sep 15:39:17 2026" parent 1035 Dia     # resumed, 5 s old    → inside the grace
  ledger 5003 "Mon 30 Sep 15:39:18 2026" proc 940 node       # still stopped (T)   → the old rules: clear
  ledger 5009 "Mon 30 Sep 15:39:19 2026" proc 1000 node      # gone                → DROP-STALE
  run_rel 1040 clear
  [ "$output" = "released=2 held=1 stale=1" ] || false
  [ "$(grep -cF -- '-CONT 5001' "$KILLLOG")" -eq 1 ] || false   # the belt SIGCONT: resumes, never strands
  [ "$(grep -cF -- '-CONT 5002' "$KILLLOG")" -eq 0 ] || false
  [ "$(grep -cF -- '-CONT 5003' "$KILLLOG")" -eq 1 ] || false
  grep -qF 'RELINQUISH pid=5001 held_s=40 kind=parent comm=Dia stat=S (resumed outside the sentinel' "$SNAPLOG" || false
  grep -qF 'SIGCONT pid=5003 held_s=100 kind=proc comm=node reason=clear' "$SNAPLOG" || false
  [ "$(grep -c 'DROP-STALE pid=5009 ' "$SNAPLOG")" -eq 1 ] || false
  [ "$(cut -f1 < "$FDB")" = "5002" ] || false
  # A relinquished SPAWNER is not on probation: it was not our release, so there is nothing to watch.
  [ ! -s "$PROBDB" ] || false
}

@test "kill_escalate REPLAY 2026-09-30T15:51:34Z: the hand-resumed Dia row is relinquished, the stopped spawner is killed" {
  have_arm kill_escalate
  mkcohort "$(printf '18285\tMon 30 Sep 15:39:10 2026\tR\n42897\tMon 30 Sep 15:48:00 2026\tT')"
  ledger 18285 "Mon 30 Sep 15:39:10 2026" parent 1000 Dia                       # held 734 s, resumed by hand
  ledger 42897 "Mon 30 Sep 15:48:00 2026" parent 1634 'next-server_(v16.2.6)'   # held 100 s, still stopped
  run_ke 1734 retrip-over-debt
  [ "$output" = "killed=1 spared=1" ] || false
  [ "$(grep -cF -- '-CONT 18285' "$KILLLOG")" -eq 1 ] || false
  [ "$(grep -cF -- '-KILL 18285' "$KILLLOG")" -eq 0 ] || false
  [ "$(grep -cF -- '-KILL 42897' "$KILLLOG")" -eq 1 ] || false                  # control: the rung still kills
  grep -qF 'RELINQUISH pid=18285 held_s=734 kind=parent comm=Dia stat=R' "$SNAPLOG" || false
  [ ! -s "$FDB" ] || false                                                       # both rows settled
  # PRE-FIX (861bc8a95): the same ledger, the same map — and Dia is killed. The incident, replayed.
  prefix_lib3
  mkcohort "$(printf '18285\tMon 30 Sep 15:39:10 2026\tR\n42897\tMon 30 Sep 15:48:00 2026\tT')"
  ledger 18285 "Mon 30 Sep 15:39:10 2026" parent 1000 Dia
  ledger 42897 "Mon 30 Sep 15:48:00 2026" parent 1634 'next-server_(v16.2.6)'
  KE_LIB="$D/prelib3.sh" run_ke 1734 retrip-over-debt
  [ "$output" = "killed=2 spared=0" ] || false
  [ "$(grep -cF -- '-KILL 18285' "$KILLLOG")" -eq 1 ] || false
}

@test "startup custody: an ACT=off loop owner hands an inherited freeze back (RELEASE-ON-DISARM)" {
  own_frozen_child "${LOG%.jsonl}-frozen.tsv" 100
  cp "$S" "$D/sentinel-copy.sh"
  DAEMON_PID="$(sentinel_daemon_bg "$D/sentinel-copy.sh" "$D/err.log")"
  local i=0; while [ "$(rows)" -lt 1 ] && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
  [ "$(rows)" -ge 1 ] || { cat "$D/err.log" >&2; false; }
  grep -q 'RELEASE-ON-DISARM (ACT=off) released=1 held=0 stale=0' "$D/err.log" || { cat "$D/err.log" >&2; false; }
  [ "$(stat_of "$CHILD_PID" | cut -c1)" != "T" ] || false               # the child is running again
  [ ! -s "${LOG%.jsonl}-frozen.tsv" ] || false                          # and nothing is owed for it
}

@test "startup custody: CC_SENTINEL=off drains an inherited ledger — unless a live instance owns the loop" {
  own_frozen_child "${LOG%.jsonl}-frozen.tsv" 100
  # CONTROL FIRST: a pidfile naming a LIVE owner (the child itself stands in — any live pid with its
  # own true lstart is an owner to loop_owner_live) ⇒ the off-run must NOT release: a hand-run with
  # the switch off can never hand back the live daemon's cohort.
  printf '%s\n%s\n' "$CHILD_PID" "$(TZ=UTC ps -o lstart= -p "$CHILD_PID" | tr -s ' ' | sed 's/^ *//;s/ *$//')" > "${LOG%.jsonl}.pid"
  run env CC_SENTINEL=off CC_SENTINEL_LOG="$LOG" CC_PANIC_SCAN=off CC_FREEZE_SCAN=off bash "$S"
  [ "$status" -eq 0 ] || false
  ! printf '%s\n' "$output" | grep -q 'RELEASE-ON-DISABLE' || false
  [ "$(stat_of "$CHILD_PID" | cut -c1)" = "T" ] || false
  [ -s "${LOG%.jsonl}-frozen.tsv" ] || false
  # No owner ⇒ the predecessor's ledger is returned, then the switch is honoured: no rows, rc 0.
  rm -f "${LOG%.jsonl}.pid"
  run env CC_SENTINEL=off CC_SENTINEL_LOG="$LOG" CC_PANIC_SCAN=off CC_FREEZE_SCAN=off bash "$S"
  [ "$status" -eq 0 ] || false
  printf '%s\n' "$output" | grep -q 'RELEASE-ON-DISABLE released=1 held=0 stale=0' || false
  printf '%s\n' "$output" | grep -q 'disabled (CC_SENTINEL=off)' || false
  [ "$(rows)" = "0" ] || false
  [ "$(stat_of "$CHILD_PID" | cut -c1)" != "T" ] || false
  [ ! -s "${LOG%.jsonl}-frozen.tsv" ] || false
}

# ══ 5g. 2026-09-30 REVIEW — the custody defects the first pass left ═══════════════════════════════

@test "custody under set -u: an EMPTY frozen-at no longer aborts the pass — the good rows still settle" {
  have_arm release_frozen
  # `read` with a tab IFS collapses the empty field, so the comm lands in `at` and `$((now - at))`
  # reads the unbound variable `node`. On f8b4184be that aborted the pass: nothing released, the
  # ledger never rewritten, every frozen pid stranded on every later tick.
  mkcohort "$(printf '7001\tMon 30 Sep 15:39:16 2026\n7002\tMon 30 Sep 15:39:17 2026')"
  printf '999991\tMon 30 Sep 15:00:00 2026\tproc\t\tnode\n' >> "$FDB"       # GONE, empty frozen-at
  printf '7002\tMon 30 Sep 15:39:17 2026\tproc\t\tnode\n' >> "$FDB"          # LIVE, empty frozen-at
  ledger 7001 "Mon 30 Sep 15:39:16 2026" proc 1000 node                       # live, 100 s — a clear release
  run_rel 1100 clear
  [ "$output" = "released=1 held=0 stale=2" ] || { echo "$output"; false; }
  [ "$(grep -cF -- '-CONT 7001' "$KILLLOG")" -eq 1 ] || false
  [ "$(grep -cF -- '-CONT 7002' "$KILLLOG")" -eq 1 ] || false               # no age ⇒ resumed, never stranded
  [ "$(grep -cF -- '999991' "$KILLLOG")" -eq 0 ] || false                   # gone ⇒ never signalled
  grep -qF 'DROP-STALE pid=999991 held_s=? kind=proc' "$SNAPLOG" || false
  grep -qF 'DROP-MALFORMED pid=7002 kind=proc' "$SNAPLOG" || false
  [ ! -s "$FDB" ] || false
  # THE KILL RUNG, same seed: the aged row is killed, the malformed one is resumed — never killed.
  mkcohort "$(printf '7001\tMon 30 Sep 15:39:16 2026\n7002\tMon 30 Sep 15:39:17 2026')"
  printf '999991\tMon 30 Sep 15:00:00 2026\tproc\t\tnode\n7002\tMon 30 Sep 15:39:17 2026\tproc\t\tnode\n' >> "$FDB"
  ledger 7001 "Mon 30 Sep 15:39:16 2026" proc 1000 node
  run_ke 1100 retrip-over-debt
  [ "$output" = "killed=1 spared=1" ] || { echo "$output"; false; }
  [ "$(grep -cF -- '-KILL 7001' "$KILLLOG")" -eq 1 ] || false
  [ "$(grep -cF -- '-KILL 7002' "$KILLLOG")" -eq 0 ] || false
  [ "$(grep -cF -- '-CONT 7002' "$KILLLOG")" -eq 1 ] || false
}

@test "kill_escalate: a row resumed from outside and still inside a grace longer than KILL_MIN_HOLD_S is HELD, never killed" {
  have_arm kill_escalate
  # Age 35: past KILL_MIN_HOLD_S (30), inside a raised grace (40). On f8b4184be this fell through to
  # SIGKILL — the 15:51:34Z failure reopened by a knob.
  mkcohort "$(printf '7001\tMon 30 Sep 15:39:16 2026\tS\n7003\tMon 30 Sep 15:39:18 2026\tT')"
  ledger 7001 "Mon 30 Sep 15:39:16 2026" parent 1000 Dia
  ledger 7003 "Mon 30 Sep 15:39:18 2026" parent 1000 'next-server_(v16.2.6)'   # control: stopped, same age
  RELINQUISH_GRACE_S=40 run_ke 1035 retrip-over-debt
  [ "$output" = "killed=1 spared=1" ] || { echo "$output"; false; }
  [ "$(grep -cF -- '7001' "$KILLLOG")" -eq 0 ] || false                     # neither killed nor resumed yet
  [ "$(grep -cF -- '-KILL 7003' "$KILLLOG")" -eq 1 ] || false               # the stopped row IS killed
  [ "$(cut -f1 < "$FDB")" = "7001" ] || false                                # held: still owed
  # …and once past the grace the same row is relinquished (SIGCONT, dropped) — still never killed.
  mkcohort "$(printf '7001\tMon 30 Sep 15:39:16 2026\tS')"
  ledger 7001 "Mon 30 Sep 15:39:16 2026" parent 1000 Dia
  RELINQUISH_GRACE_S=40 run_ke 1041 retrip-over-debt
  [ "$output" = "killed=0 spared=1" ] || false
  [ "$(grep -cF -- '-CONT 7001' "$KILLLOG")" -eq 1 ] || false
  [ ! -s "$FDB" ] || false
}

# The stub table follows the signals: after -CONT the pid reads S, after -KILL it is gone.
mkapplysig() {
  cat > "$D/applysig" <<'SH'
#!/bin/bash
t="$PSMAP.t"
case "$1" in
  -CONT) awk -F'\t' -v OFS='\t' -v p="$2" '$1 == p { $3 = "S" } { print }' "$PSMAP" > "$t" ;;
  -KILL) awk -F'\t' -v p="$2" '$1 != p' "$PSMAP" > "$t" ;;
  *) exit 0 ;;
esac
mv -f "$t" "$PSMAP"
SH
  chmod +x "$D/applysig"
  export APPLYSIG="$D/applysig"
}

@test "ONE ROW PER PROCESS: a spawner owed as worker AND parent is held as a parent — its own SIGCONT is never read as an outside resume" {
  have_arm release_frozen
  # Panic #5's order: trip 1 ledgered the fresh spawner 42897 as a worker, TRIP 2 re-froze it as a
  # parent. On f8b4184be the first clear tick SIGCONTed the worker row (resuming the spawner), then
  # read that SIGCONT on the parent row as a resume from outside — released=2, no probation, and the
  # next retrip-over-debt had nothing left to kill.
  mkcohort "$(printf '42897\tMon 24 Aug 19:49:50 2026')"
  mkapplysig
  ledger 42897 "Mon 24 Aug 19:49:50 2026" proc 1000 'next-server_(v16.2.6)'
  ledger 42897 "Mon 24 Aug 19:49:50 2026" parent 1131 'next-server_(v16.2.6)'
  run_rel 1200 clear 0 0
  [ "$output" = "released=0 held=1 stale=0" ] || { echo "$output"; false; }
  [ ! -s "$KILLLOG" ] || false                                              # no signal at all
  ! grep -q 'RELINQUISH' "$SNAPLOG" || false
  # ONE row, the stricter kind, the EARLIEST freeze.
  [ "$(wc -l < "$FDB" | tr -d ' ')" -eq 1 ] || false
  [ "$(cut -f1,3,4 < "$FDB")" = "$(printf '42897\tparent\t1000')" ] || false
  run_ke 1300 retrip-over-debt
  [ "$output" = "killed=1 spared=0" ] || { echo "$output"; false; }
  [ "$(grep -cF -- '-KILL 42897' "$KILLLOG")" -eq 1 ] || false
  # THE KILL RUNG reads through the same merge: seeded with the pair directly, one kill, one debt.
  # "One kill" alone cannot tell: read raw, the first row kills and the stub then reports the second
  # gone (DROP-STALE). What only the merged row gives is the kill logged as the PARENT, at the
  # earliest freeze, with no stale second row behind it.
  mkcohort "$(printf '42897\tMon 24 Aug 19:49:50 2026')"
  ledger 42897 "Mon 24 Aug 19:49:50 2026" proc 1000 'next-server_(v16.2.6)'
  ledger 42897 "Mon 24 Aug 19:49:50 2026" parent 1131 'next-server_(v16.2.6)'
  : > "$SNAPLOG"
  run_ke 1300 retrip-over-debt
  [ "$output" = "killed=1 spared=0" ] || { echo "$output"; false; }
  grep -qF 'KILL-INTENT reason=retrip-over-debt debt=1 ' "$SNAPLOG" || false
  grep -qF 'SIGKILL pid=42897 held_s=300 kind=parent ' "$SNAPLOG" || { cat "$SNAPLOG"; false; }
  ! grep -q 'DROP-STALE pid=42897 ' "$SNAPLOG" || false
  [ ! -s "$FDB" ] || false
  # frozen_merge alone: parent wins, earliest frozen-at, first-seen order, distinct processes untouched.
  printf '5\tA\tproc\t300\tx\n6\tB\tproc\t200\ty\n5\tA\tparent\t100\tx\n5\tZ\tproc\t50\tx\n' > "$D/m.tsv"
  run /bin/bash -c '. "$1"; frozen_merge "$2"' _ "$D/lib.sh" "$D/m.tsv"
  [ "$output" = "$(printf '5\tA\tparent\t100\tx\n6\tB\tproc\t200\ty\n5\tZ\tproc\t50\tx')" ] || { echo "$output"; false; }
}

@test "STARTUP-SWEEP: an ARMED loop owner resumes an inherited protected row and its stamp, and keeps every other hold" {
  # The self-heal for GUI rows stranded by a daemon killed before its TERM trap ran. Until this case
  # only a text grep and the release_frozen unit covered it — a startup protected list forced EMPTY
  # passed every test. Real loop, ACT=stop; real signals to this test's OWN two
  # children only. The stub ps names child 1 a Dia root (class 2) and child 2 a plain node (class 0);
  # every `-p` read goes to the real ps, so custody sees the children's true state and lstart.
  mkstubs 0 0 0
  sleep 120 & CHILD_PID=$!; stop_own_child "$CHILD_PID" || false
  sleep 120 & CHILD2_PID=$!; stop_own_child "$CHILD2_PID" || false
  export C1="$CHILD_PID" C2="$CHILD2_PID" DIA_BIN="$DIA"
  cat > "$STUB/ps" <<'SH'
#!/bin/bash
case " $* " in *" -p "*) exec /bin/ps "$@" ;; esac
case "$*" in
  *"pid=,ucomm="*)           printf '1 launchd\n%s sleep\n%s sleep\n' "$C1" "$C2" ;;
  *"pid=,args="*)            printf '1 /sbin/launchd\n%s sleep 120\n%s sleep 120\n' "$C1" "$C2" ;;
  *"pid=,ppid=,rss=,comm="*) printf '1 0 1000 /sbin/launchd\n%s 1 400000 %s\n%s 1 200000 /opt/homebrew/bin/node\n' "$C1" "$DIA_BIN" "$C2" ;;
  *) : ;;
esac
SH
  chmod +x "$STUB/ps"
  local lt1 lt2 now; now="$(date +%s)"
  lt1="$(TZ=UTC /bin/ps -o lstart= -p "$C1" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  lt2="$(TZ=UTC /bin/ps -o lstart= -p "$C2" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  printf '%s\t%s\tparent\t%s\tDia\n%s\t%s\tproc\t%s\tnode\n' "$C1" "$lt1" "$((now - 100))" "$C2" "$lt2" "$now" \
    > "${LOG%.jsonl}-frozen.tsv"
  printf '%s\t%s\t%s\tDia\n%s\t%s\t%s\tnode\n' "$C1" "$lt1" "$now" "$C2" "$lt2" "$now" \
    > "${LOG%.jsonl}-frozen-probation.tsv"
  cp "$S" "$D/sentinel-copy.sh"
  DAEMON_PID="$(BG_ACT=stop sentinel_daemon_bg "$D/sentinel-copy.sh" "$D/err.log")"
  local i=0; while [ "$(rows)" -lt 1 ] && [ "$i" -lt 40 ]; do sleep 0.25; i=$((i + 1)); done
  [ "$(rows)" -ge 1 ] || { cat "$D/err.log" >&2; false; }                 # the loop is running: the sweep ran
  grep -q 'STARTUP-SWEEP released=1 held=1 stale=0' "$D/err.log" || { cat "$D/err.log" >&2; false; }
  [ "$(stat_of "$CHILD_PID" | cut -c1)" != "T" ] || false                  # the GUI row: resumed
  [ "$(stat_of "$CHILD2_PID" | cut -c1)" = "T" ] || false                  # the worker: still held
  [ "$(cut -f1 < "${LOG%.jsonl}-frozen.tsv")" = "$C2" ] || false
  [ "$(cut -f1 < "${LOG%.jsonl}-frozen-probation.tsv")" = "$C2" ] || false # only the protected stamp dropped
}
