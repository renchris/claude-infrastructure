#!/usr/bin/env bats
# tests/capacity-ceiling-derivation.bats — THE RECORDED POPULATION, MADE EXECUTABLE.
#
# WHY THIS SUITE EXISTS. `CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0` shipped in `0fc3a3d33` with no
# derivation, and its code comment cited "§9.5's measured ceiling" — a section that contains no such
# derivation and whose own closing line is "a projection from a single high-variance window is not a
# measurement". Backlog item e981656df348 asked for the number to be DERIVED, explicitly not raised.
# The derivation returned a NEGATIVE result, and a negative result stated in a paragraph decays
# exactly the way the false citation did. So it is stated here instead, as a control that can fail.
#
# THE PATTERN IS THE REPO'S OWN. scripts/capacity-alarm.sh:154-157 ships uncalibrated floors and
# pins its known false-ALARM population in its selftest, "so a future re-derivation has to argue
# with a control rather than with this paragraph". The GATE carried the same defect and had no such
# control. This is it.
#
# 🚨 THIS SUITE IS PLATFORM-PORTABLE ON PURPOSE, and that is not incidental. tests/capacity-admit.bats
# is 14/21 RED on Linux because the library's probes are Darwin (`sysctl`, `vm_stat`) — so a control
# added there could only ever be checked on the one box whose numbers are under dispute.
# `cc_hw_load_verdict` is pure awk over three arguments, so the population is an INPUT here and this
# suite is green anywhere. Verified 2026-08-19 on Linux x86_64 and required to stay that way.
#
# RED-PROOF (recorded 2026-08-19, every mutation run):
#   · constant mutated 2.0 -> 3.0 .......................... D1 RED
#   · FATAL_PER_CORE mutated 2.53 -> 6.50 (a separable
#     population) ......................................... D5 RED, D8 RED, D6 still green
#   · the false citation restored verbatim in the library .. D7 RED
# D6 staying green through the D5 mutation is the load-bearing one: it proves `separator` can find a
# ceiling when one exists, so D5's silence is a result and not a broken sweep.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/capacity-admit.sh"
  [ -r "$LIB" ] || { echo "library missing: $LIB"; return 1; }
  # HERMETICITY. Sourcing the library is enough to owe both of these, even though every case below
  # calls only `cc_hw_load_verdict` — three arguments in, a string out, no probe touched.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # CC_ADMIT_GATE=off rather than pinning the three instrument terms: the ADMISSION GATE is not this
  # suite's subject. The subject is the CONSTANT and the pure verdict function it feeds, and the
  # population is supplied as arguments — so a live box's load, headroom and session census must not
  # be able to reach any assertion here, not even to make one pass.
  export CC_ADMIT_GATE=off
}

# ── THE POPULATION ─────────────────────────────────────────────────────────────────────────────
# Every figure below is quoted from a TRACKED file in this repo, not from a memory of a session.
# Source for all three: scripts/capacity-alarm.sh:139-147, which in turn cites the 2026-08-05 panic
# and MACHINE_CAPACITY_V2.md §8.5.7. Load figures are on a 10-core box; the per-core column is what
# the gate actually compares.
#
#   FATAL     2026-08-05 watchdogd-starvation panic .. 25.30 / 10 = 2.53/core
#   SURVIVED  §8.5.7, 13 consecutive samples at a
#             CONSTANT 31-32 sessions ................ 29.15-59.80 = 2.92-5.98/core
#   SURVIVED  reso, 42 h at load 25, no panic ........ 25.00 / 10 = 2.50/core
#
# The 13 are quoted INDIVIDUALLY from MACHINE_CAPACITY_V2.md:486 — 29.15, 37.66, 44.35, 45.96,
# 47.01, 49.94, 50.43, 55.56, 56.96, 56.04, 54.74, 56.24, 59.80 — divided by 10 cores. They are
# listed rather than summarised because "2.92-5.98" is a range and a range is not a population; the
# separability question is answered by the extremes, but a reader checking this suite against the
# plan must be able to check every row, not two.
FATAL_PER_CORE=2.53
SURVIVED_PER_CORE="2.500 2.915 3.766 4.435 4.596 4.701 4.994 5.043 5.556 5.696 5.604 5.474 5.624 5.980"

verdict() { # $1=per-core load $2=candidate ceiling → ADMIT|REFUSE (the SUBJECT, never a re-implementation)
  # ncpu=1 so the first argument IS the per-core figure; the function divides by n itself.
  # shellcheck disable=SC1090
  ( . "$LIB" >/dev/null 2>&1; cc_hw_load_verdict "$1" 1 "$2" ) | awk '{print $1}'
}

# separator: echo the FIRST candidate ceiling that REFUSES the fatal and ADMITS every survivor, or
# nothing at all. Sweeps 0.00-6.50 in 0.01 steps; no separator can exist above the fatal value
# (anything >= it admits the death), so the range strictly contains every candidate worth testing.
# ONE implementation, used by both the real population and the positive control below — a sweep that
# could only ever be run against the case it is expected to fail is not a control.
separator() { # $1=fatal per-core  $2=space-separated survivors
  local fatal="$1" survivors="$2" c s ok
  for c in $(awk 'BEGIN{for(i=0;i<=650;i++) printf "%.2f\n", i/100}'); do
    [ "$(verdict "$fatal" "$c")" = "REFUSE" ] || continue
    ok=1
    for s in $survivors; do
      [ "$(verdict "$s" "$c")" = "ADMIT" ] || { ok=0; break; }
    done
    [ "$ok" = 1 ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

@test "D1 the shipped default is still the 2.0 that 0fc3a3d33 chose — a change must face this suite" {
  # shellcheck disable=SC1090
  run bash -c ". '$LIB' >/dev/null 2>&1; printf '%s' \"\$CC_HW_DEFAULT_MAX_LOAD_PER_CORE\""
  [ "$status" -eq 0 ]
  [ "$output" = "2.0" ]
}

@test "D2 the shipped ceiling REFUSES the one FATAL sample — the true positive, n=1" {
  [ "$(verdict "$FATAL_PER_CORE" 2.0)" = "REFUSE" ]
}

@test "D3 it also refuses ALL 14 SURVIVED samples — 14 false refusals against that 1 true one" {
  local s n=0
  for s in $SURVIVED_PER_CORE; do
    [ "$(verdict "$s" 2.0)" = "REFUSE" ] || { echo "survivor $s/core was ADMITTED at ceiling 2.0"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 14 ]
}

@test "D4 a SURVIVOR sits 0.03/core BELOW the fatal — the axis has no resolution here" {
  # reso: 42 h at load 25 on 10 cores with no panic. The panic was at 25.3. Whatever killed the box
  # is not visible in the 0.3 of load average that separates the two readings — and §8.5.7 measured
  # this same signal swinging 2x at CONSTANT session count.
  run awk -v a=2.50 -v b="$FATAL_PER_CORE" 'BEGIN{ exit !(b - a < 0.05 && b > a) }'
  [ "$status" -eq 0 ]
}

@test "D5 THE DERIVATION — NO ceiling separates fatal from survived, so the constant is underivable on this axis" {
  # Necessary and sufficient, stated exactly rather than sampled: a separating ceiling c must satisfy
  # `fatal > c` (REFUSE the death) and `max_survived <= c` (ADMIT every survivor). Both hold only if
  # max_survived < fatal. It is 5.98 against 2.53, so the admissible set is EMPTY.
  run awk -v fatal="$FATAL_PER_CORE" -v maxs=5.980 'BEGIN{ exit !(maxs >= fatal) }'
  [ "$status" -eq 0 ]
  # ...and behaviourally, through the subject itself, over every candidate in 0.01 steps.
  run separator "$FATAL_PER_CORE" "$SURVIVED_PER_CORE"
  [ "$status" -ne 0 ] || { echo "a separating ceiling was found at $output — the negative result is STALE, re-derive"; return 1; }
}

@test "D6 POSITIVE CONTROL — the same sweep DOES find a separator on a separable population" {
  # Without this, D5 passes just as happily when `separator` is broken and returns nothing for
  # everything. Fatal 5.00/core, survivors all at or under 3.00: a ceiling anywhere in [3.00, 5.00)
  # separates them, and the sweep must produce one.
  run separator 5.00 "0.50 1.20 2.00 2.75 3.00"
  [ "$status" -eq 0 ]
  run awk -v c="$output" 'BEGIN{ exit !(c + 0 >= 3.00 && c + 0 < 5.00) }'
  [ "$status" -eq 0 ]
}

@test "D7 the false citation cannot come back — the constant carries its real provenance" {
  # The line that shipped for three weeks was "2.0/core is §9.5's measured ceiling". §9.5 is a
  # self-correction that measures no ceiling. A ratchet, not a style check: the defect this item
  # exists to close is a comment asserting a derivation that does not exist.
  # The phrase may survive ONCE, on the line that records what the file used to say — deleting the
  # history is how the next reader re-adds the claim. Every OTHER occurrence is the defect returning.
  run bash -c "grep -n 'measured ceiling' '$LIB' | grep -vc 'used to read'"
  [ "$output" = "0" ]
  grep -q "UNDERIVED" "$LIB"
  grep -q "0fc3a3d33" "$LIB"
  grep -q "set is EMPTY" "$LIB"
}

@test "D8 MUTATION — every raise that buys anything admits the death, which is what D5 costs" {
  # The obvious "fix" for D3's 14 false refusals is to raise the ceiling above the survivors. Run it.
  # The lowest survivor (2.50) is the ONE that can be cleared without admitting the fatal, and
  # clearing it alone buys nothing — it retires 1 of the 14 false refusals. From the SECOND survivor
  # (2.915) upward, every ceiling that admits it admits the 2.53 death as well. That is the trade,
  # measured: this is what makes "do NOT blind-raise" a control rather than an instruction.
  [ "$(verdict 2.500 2.50)" = "ADMIT" ]
  [ "$(verdict "$FATAL_PER_CORE" 2.50)" = "REFUSE" ]   # the one raise that keeps the true positive
  local c
  for c in 2.92 3.00 4.00 5.98 6.00; do
    [ "$(verdict 2.915 "$c")" = "ADMIT" ] || { echo "ceiling $c does not clear the second survivor"; return 1; }
    [ "$(verdict "$FATAL_PER_CORE" "$c")" = "ADMIT" ] || { echo "ceiling $c still refuses the fatal — D5 would be wrong"; return 1; }
  done
}
