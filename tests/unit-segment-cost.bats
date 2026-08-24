#!/usr/bin/env bats
# unit-segment-cost.sh — the per-unit compressor-SEGMENT meter that closes G3 of
# docs/research/orchestration-units-2026-08-19/Z-completeness-critic.md (*"Per-unit segment cost is
# UNMEASURED for every one of the seven units in §2, so the wall with four incidents behind it has
# no number and no rank"*).
#
# THE PROPERTY UNDER TEST IS NOT "IT PRINTS A NUMBER". The same synthesis REFUTES the naive form of
# this measurement with data — §6 N9, *"the paired arrival differential failed independently for two
# agents (Δ never returned to baseline; drift > signal)"* — and the way that failed is the whole
# reason this suite exists: **it produced values.** So the load-bearing cases here (04, 05, 06) are
# the ones that assert a number is WITHHELD. A meter that cannot say "the box moved more than the
# unit did" will publish the box's mood as a unit cost, and every case that only checks a happy-path
# number would pass against exactly that meter.
#
# HERMETICITY: `sysctl` and `vm_stat` are stubbed under BATS_TEST_TMPDIR and the compressor reading
# is driven from a file, so a case can move the box under the meter mid-run. Nothing reads the mood
# of the machine running the suite; the two probes are macOS-only and this suite runs on Linux CI,
# which is the point — an untestable term is one that rots (capacity-admit-active.bats says the same
# about the same two sysctls).
#
# RED-PROOF (re-runnable — `git stash push scripts/unit-segment-cost.sh`, run, `git stash pop`):
# all 11 cases FAIL against pristine trunk, where the subject does not exist. Cases 06 and 07 are
# additionally RED against the FIRST draft of the subject, which is why they are here: draft 1 took
# the band as `max(span, rate x elapsed)` with no floor, so a flat baseline gave band 0 and promoted
# a one-segment blip to MEASURED (06), and it took the peak from the run window alone, which emitted
# `retained > peak` on the first fixture that moved the meter (07).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJ="$REPO/scripts/unit-segment-cost.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"

  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  # The compressor reading lives in a FILE, not an env var, so a fixture command can move the box
  # while the meter is sampling it. That is the only way to fixture a differential at all.
  export STUB_STATE="$BATS_TEST_TMPDIR/comp"
  echo "${STUB_COMPPAGES:-4000}" > "$STUB_STATE"

  cat > "$BIN/sysctl" <<'EOF'
#!/bin/bash
case "$*" in
  *vm.compressor_segment_limit*)       echo "${STUB_SEGLIM:-262144}" ;;
  *vm.compressor_segment_buffer_size*) echo "${STUB_SEGBUF:-65536}" ;;
  *vm.swapusage*)                      echo "total = 8192.00M  used = ${STUB_SWAP:-0.00}M  free = 8192.00M  (encrypted)" ;;
  *) exit 1 ;;
esac
EOF
  # A 16 KiB page size, as on the Apple-silicon target: four pages to a 64 KiB segment. The divisor
  # is DERIVED and never the literal 4 — case 02 is that assertion.
  cat > "$BIN/vm_stat" <<'EOF'
#!/bin/bash
echo "Mach Virtual Memory Statistics: (page size of ${STUB_PGSZ:-16384} bytes)"
echo "Pages free:                          2000000."
echo "Pages occupied by compressor:        $(cat "$STUB_STATE")."
EOF
  chmod +x "$BIN/sysctl" "$BIN/vm_stat"
  export PATH="$BIN:$PATH"
  export CC_USC_SYSCTL="$BIN/sysctl"
  export CC_USC_LOG="$BATS_TEST_TMPDIR/usc.jsonl"
  # The subject SOURCES scripts/lib/capacity-admit.sh for the segment arithmetic, which brings that
  # file's admission gate into reach. That gate reads LIVE load, reclaimable memory and a `ps`
  # session census, so a suite that left it armed would go red-by-desk rather than by its subject
  # (backlog 5ef0dcb22aec). Only the pure probe is used here — `cc_capacity_admit` is never called —
  # so the gate is switched off rather than having its three terms pinned.
  export CC_ADMIT_GATE=off
  # Short windows so the suite runs in seconds. The DEFAULTS are asserted in case 11; a suite that
  # only ever runs its subject at fixture timings never notices the shipped ones drifting.
  export CC_USC_INTERVAL=1 CC_USC_BASELINE_S=2 CC_USC_SETTLE_S=2
}

# Moves the stubbed box by <delta> segments-worth of pages, once, after <sleep> seconds. Emitted as
# a command string for `-- <cmd>` so the movement happens DURING the unit's window.
bump() { # $1=sleep $2=pages-to-add
  printf 'sleep %s; echo $(( $(cat "$STUB_STATE") + %s )) > "$STUB_STATE"' "$1" "$2"
}

# ══ 1. THE READ ITSELF — §7.7 arithmetic, sourced and not re-implemented ═══════════════════════

@test "01 sample reads segments through the SAME arithmetic the sentinel runs" {
  # 4,000 compressor pages at 16 KiB into 64 KiB segments = 4 pages/segment = 1,000 segments of a
  # 262,144 limit = 0.38%.
  echo 4000 > "$STUB_STATE"
  run "$SUBJ" sample
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .segs)" = 1000 ]
  [ "$(printf '%s' "$output" | jq -r .seg_pct)" = 0.38 ]
  [ "$(printf '%s' "$output" | jq -r .seg_limit)" = 262144 ]
}

@test "02 the divisor is DERIVED from the page size — a 4 KiB box is not read 4x low" {
  # Same 4,000 pages on a 4 KiB box is sixteen pages to a segment, i.e. 250 segments, not 1,000.
  # The literal 4 is right only at a 16 KiB page size, which is exactly the trap this asserts.
  echo 4000 > "$STUB_STATE"
  STUB_PGSZ=4096 run "$SUBJ" sample
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .segs)" = 250 ]
}

@test "03 SWAPPED-OUT segments count — a descriptor on disk still holds against the limit" {
  # The panics hit 100% of the SEGMENT limit at ~32% of the compressed-PAGES limit, with 66-68
  # swapfiles. A meter counting only resident segments would under-read the exact state it exists
  # to see. 8 GB of swap at 64 KiB per chunk is 131,072 segments with ZERO pages in core.
  echo 0 > "$STUB_STATE"
  STUB_SWAP=8192.00 run "$SUBJ" sample
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .segs)" = 131072 ]
  # ...and the control that proves the swap arm is what produced it: same box, no swap.
  run "$SUBJ" sample
  [ "$(printf '%s' "$output" | jq -r .segs)" = 0 ]
}

# ══ 2. THE DRIFT DISCIPLINE — the three cases that make this meter worth having ════════════════

@test "04 THE N9 CONTROL — a delta inside the drift band is WITHHELD, not published" {
  # The refuted method did not fail loudly; it produced values. Here the box moves on its own during
  # the baseline (so the band is real and non-degenerate) and the unit then moves it by LESS. The
  # only correct output is a withheld number.
  echo 4000 > "$STUB_STATE"
  # A noisy baseline that then goes QUIET, which is the shape that makes this deterministic: the
  # band is set by a drift of ~2,000 segments/s observed before the unit exists, and the unit then
  # moves the box by 40. Drift that merely CONTINUES through the run at the same rate would sit on
  # the band boundary and decide the case on sampling jitter.
  ( for _ in 1 2 3; do sleep 0.5; echo $(( $(cat "$STUB_STATE") + 8000 )) > "$STUB_STATE"; done ) &
  NOISE=$!
  run "$SUBJ" watch --label plain-subagent --units 8 -- bash -c "$(bump 1 160)"
  kill "$NOISE" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .verdict)" = INDETERMINATE ]
  [ "$(printf '%s' "$output" | jq -r .per_unit_peak_segs)" = null ]
  [ "$(printf '%s' "$output" | jq -r .why)" = "delta within the baseline drift band" ]
}

@test "05 a delta that CLEARS the band is MEASURED, and carries the per-unit cost and the wall" {
  # The positive control for case 04: without this, a meter that returned INDETERMINATE forever
  # would pass the suite. 120,000 pages added = 30,000 segments over 8 units = 3,750 each; the wall
  # at the 50% ceiling is 131,072 / 3,750 = 34 units.
  echo 4000 > "$STUB_STATE"
  run "$SUBJ" watch --label named-teammate --units 8 -- bash -c "$(bump 1 120000)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .verdict)" = MEASURED ]
  [ "$(printf '%s' "$output" | jq -r .per_unit_peak_segs)" = 3750.00 ]
  [ "$(printf '%s' "$output" | jq -r '.wall_units_at_50_pct')" = 34 ]
}

@test "06 THE QUIET-BOX FLOOR — a flat baseline does not make the band zero" {
  # RED against draft 1. A baseline that saw no movement has not measured the box to be still; it
  # has bounded its drift below the meter resolution over the window it watched. Taking that as
  # rate 0 makes the band 0 and promotes a ONE-SEGMENT blip to MEASURED — the N9 defect arriving
  # through a quiet box instead of a noisy one.
  echo 4000 > "$STUB_STATE"
  run "$SUBJ" watch --label workflow-agent --units 8 -- bash -c "$(bump 1 4)"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .baseline_rate_per_s)" = 0.0000 ]
  [ "$(printf '%s' "$output" | jq -r .baseline_span)" = 0 ]
  # The band is non-zero DESPITE a perfectly flat baseline, and the blip is therefore withheld.
  [ "$(printf '%s' "$output" | jq -r '.drift_band_segs > 0')" = true ]
  [ "$(printf '%s' "$output" | jq -r .verdict)" = INDETERMINATE ]
}

@test "07 the peak spans the SETTLE window — retained can never exceed peak" {
  # RED against draft 1, which took the peak from the run window alone and emitted retained > peak.
  # Compression LAGS the allocation that causes it, so a unit's worst occupancy routinely lands
  # after the unit has exited (§6 N5: a finished bg job still held 217-225 MB two minutes later).
  echo 4000 > "$STUB_STATE"
  # The command exits immediately; the box only moves afterwards, i.e. entirely inside settle.
  ( sleep 3; echo 124000 > "$STUB_STATE" ) &
  LATE=$!
  run "$SUBJ" watch --label bg-worker --units 4 -- true
  wait "$LATE" 2>/dev/null || true
  [ "$status" -eq 0 ]
  peak="$(printf '%s' "$output" | jq -r .peak_segs)"
  ret="$(printf '%s' "$output" | jq -r '.delta_retained_segs + .baseline_segs')"
  [ "$(awk -v p="$peak" -v r="$ret" 'BEGIN { print (p + 0.001 >= r) }')" = 1 ]
}

# ══ 3. BLINDNESS IS VISIBLE, NEVER ZERO ═══════════════════════════════════════════════════════

@test "08 an unreadable probe is a NAMED blindness with rc 3 — never a cost of zero" {
  # The defect capacity-alarm.sh ate on its launchd PATH: a dead rung reporting the healthy value.
  # A meter that renders "could not measure" as 0.00 would price every unit as free.
  CC_USC_SYSCTL=/bin/false run "$SUBJ" sample
  [ "$status" -eq 3 ]
  [ "$(printf '%s' "$output" | jq -r .verdict)" = SKIP ]
  [ -n "$(printf '%s' "$output" | jq -r .blind)" ]
  [ "$(printf '%s' "$output" | jq -r '.seg_pct // "absent"')" = absent ]
}

@test "09 a box that goes unreadable MID-RUN aborts the row rather than completing it" {
  # Half a differential is not a small differential, it is a fabricated one.
  echo 4000 > "$STUB_STATE"
  CC_USC_SYSCTL="$BATS_TEST_TMPDIR/dies" run "$SUBJ" watch --label x --units 1 --duration 2
  [ "$status" -eq 3 ]
  [ "$(printf '%s' "$output" | jq -r .verdict)" = SKIP ]
}

# ══ 4. STRUCTURE AND USAGE ════════════════════════════════════════════════════════════════════

@test "10 the arithmetic is SOURCED, not copied — and the proof is behavioural, not a grep" {
  # Three instruments already parse vm_stat in this tree (the gate, the monitor, the daemon) and
  # capacity-admit.sh:232 states why that is the cap: sharing a parser would make one subject's
  # tuning another's regression, so a CONSUMER must source rather than re-implement. A grep for the
  # sysctl NAMES cannot assert that — they legitimately appear in the blindness message, which has
  # to name the probes that would not answer. Two behavioural assertions instead:
  #
  # (a) point the lib somewhere unreadable and the subject cannot run AT ALL. A private copy of the
  #     arithmetic would keep working here, and that is exactly the regression this pins.
  CC_USC_LIB="$BATS_TEST_TMPDIR/absent.sh" run "$SUBJ" sample
  [ "$status" -eq 3 ]
  [[ "$output" == *"cannot read"* ]] || false

  # (b) PARITY on one fixture: what the subject reports IS what the shared function returns. This is
  #     the same shape tests/capacity-admit-active.bats case 06 uses to hold this arithmetic and the
  #     sentinel's own together — a behavioural control over the thing that actually breaks.
  echo 12345 > "$STUB_STATE"
  STUB_SWAP=1024.00 run "$SUBJ" sample
  [ "$status" -eq 0 ]
  mine="$(printf '%s' "$output" | jq -r .segs)"
  theirs="$(STUB_SWAP=1024.00 bash -c \
    '. "$1"; cc_hw_compressor_segment_pct "$2"' _ "$REPO/scripts/lib/capacity-admit.sh" "$BIN/sysctl" \
    | awk '{print $2}')"
  [ -n "$theirs" ]
  [ "$mine" = "$theirs" ]
}

@test "11 the shipped defaults are the ones the header documents, and usage errors are rc 64" {
  # A suite that only runs its subject at fixture timings never notices the shipped windows drifting.
  grep -q 'CC_USC_BASELINE_S:-30' "$SUBJ"
  grep -q 'CC_USC_SETTLE_S:-60' "$SUBJ"
  grep -q 'CC_USC_CEILING_PCT:-50' "$SUBJ"
  run "$SUBJ" watch --label x --units 0 --duration 5
  [ "$status" -eq 64 ]
  run "$SUBJ" watch --units 3 --duration 5
  [ "$status" -eq 64 ]
  run "$SUBJ" nonsense
  [ "$status" -eq 64 ]
}
