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
  cat > "$STUB/ps" <<'SH'
#!/bin/bash
case "$*" in
  *"pid=,ppid=,rss=,pcpu=,args="*) cat "$PS_SNAP"   2>/dev/null ;;
  *"pid=,ppid=,rss=,args="*)       cat "$PS_ACT"    2>/dev/null ;;
  *"pid=,ppid=,rss=,comm="*)       cat "$PS_CENSUS" 2>/dev/null ;;
  *"rss=,comm="*)                  cat "$PS_EXE"    2>/dev/null ;;
  *) echo "stub-ps $*" ;;
esac
SH

  : > "$D/ps.census"; : > "$D/ps.act"; : > "$D/ps.snap"; : > "$D/ps.exe"
  export PS_CENSUS="$D/ps.census" PS_ACT="$D/ps.act" PS_SNAP="$D/ps.snap" PS_EXE="$D/ps.exe"
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
mkexe() { # <actuator rows>  → "<pid> <ppid> <rss> <exe_basename>"
  awk '$1 ~ /^[0-9]+$/ { b = $4; sub(/.*\//, "", b); gsub(/[[:space:]]+/, "_", b)
                         print $1, $2, $3, b }' <<< "$1" > "$D/exe"
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
  sel "" "$(printf '906 1 4000000 /Applications/Chrome.app/Contents/MacOS/Chrome --type=renderer\n907 1 4000000 /usr/bin/python3 train.py')"
  [ -z "$output" ] || false
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
  [ "${output%%|*}" = "1 1 878" ] || false
  [ "${output#*|}" = " 1011" ] || false
}

@test "SELECTOR SITE: an fnm node is SEEN — the name comes from exe_table, not the args table" {
  # exe_table is RUN here rather than hand-written: the point of the case is that it resolves a comm
  # whose path contains spaces, which no field-split of the actuator's own table can do.
  mkstubs 0 0 0
  printf '1001 1 900000 %s\n' "$FNM" > "$PS_CENSUS"
  run env PATH="$STUB:$PATH" bash -c '. "$1"; exe_table' _ "$D/lib.sh"
  [ "$output" = "1001 1 900000 node" ] || false
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
  printf '1201 4242 900000 node\n' > "$D/exe.mm"
  sel "" '1201 7 900000 /opt/homebrew/bin/node /w/app/w.js' "$D/exe.mm"
  [ -z "$output" ] || false
  # POSITIVE CONTROL — the identical row with the ppids AGREEING is selected.
  printf '1201 7 900000 node\n' > "$D/exe.ok"
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
  printf '36923 1 3432416 next-server\n40001 36923 900000 node\n40002 36923 900000 node\n40003 36923 900000 node\n' > "$D/exe.named"
  brk "40001 40002 40003" "$(printf '36923 1 3432416 /w/reso/node_modules/.bin/next-server next-server\n40001 36923 900000 /opt/homebrew/bin/node p.js\n40002 36923 900000 /opt/homebrew/bin/node p.js\n40003 36923 900000 /opt/homebrew/bin/node p.js')" 3 4 "$D/exe.named"
  [ "$output" = "36923 3 next-server" ] || false
}

@test "BREAK-PARENTS SITE: a modelcontextprotocol spawner is protected by the class test" {
  printf '36924 1 3432416 node\n40001 36924 900000 node\n40002 36924 900000 node\n40003 36924 900000 node\n' > "$D/exe.mcp"
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

BOOTS=1786686149          # 2026-08-14T05:42:29Z — tonight's real boot
BOOTSTAMP=202608132242    # the same instant, in touch's format

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

mkcohort() { # <psmap>  — TAB-separated "pid<TAB>lstart" rows. A pid ABSENT from the map is gone.
  PSMAP="$D/psmap"; printf '%s\n' "$1" > "$PSMAP"
  FDB="$D/frozen.tsv"; : > "$FDB"
  PROBDB="$D/probation.tsv"; : > "$PROBDB"
  KILLLOG="$D/kill.calls"; : > "$KILLLOG"
  cat > "$STUB/ps" <<'SH'
#!/bin/bash
pid=""
while [ $# -gt 0 ]; do
  if [ "$1" = "-p" ]; then pid="$2"; shift; fi
  shift
done
awk -F'\t' -v p="$pid" '$1==p {print $2}' "$PSMAP"
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

run_rel() { # <now-epoch> <mode> [<parent_ok 0|1>] [<cliff 0|1>]
  run env PATH="$STUB:$PATH" PSMAP="$PSMAP" FROZEN_DB="$FDB" SNAP="$SNAPLOG" KILLLOG="$KILLLOG" \
      HOLD_MIN_S="${HOLD_MIN_S:-60}" HOLD_MAX_S="${HOLD_MAX_S:-600}" \
      PARENT_HOLD_MIN_S="${PARENT_HOLD_MIN_S:-600}" PROBATION_DB="$PROBDB" \
      bash -c 'kill() { printf "%s\n" "$*" >> "$KILLLOG"; }; . "$1"; release_frozen "$2" "$3" "$4" "$5"' \
      _ "$D/lib.sh" "$1" "$2" "${3:-0}" "${4:-0}"
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

run_ke() { # <now-epoch> <reason>
  run env PATH="$STUB:$PATH" PSMAP="$PSMAP" FROZEN_DB="$FDB" SNAP="$SNAPLOG" KILLLOG="$KILLLOG" \
      KILL_MIN_HOLD_S="${KILL_MIN_HOLD_S:-30}" \
      bash -c 'kill() { printf "%s\n" "$*" >> "$KILLLOG"; }; . "$1"; kill_escalate "$2" "$3"' \
      _ "$D/lib.sh" "$1" "$2"
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
  run timeout 10 env PATH="$STUB:$PATH" PSMAP="$PSMAP" CC_SENTINEL_LOG="$LOG" \
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
