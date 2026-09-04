#!/usr/bin/env bats
# idle-slope-sweep.sh — Phase A's decisive test: regress load on resident-session count.
#
# WHAT THIS SUITE CAN AND CANNOT COVER. The sweep's launch arm spawns real `claude` processes and
# sleeps for minutes; nothing here does that, and nothing here should. What IS covered is everything
# that decides whether a produced number is trustworthy: the fit itself (against a synthetic series
# whose slope is known exactly), and every REFUSAL — because each refusal exists to stop the script
# emitting a clean-looking figure that is wrong.
#
# The refusals are the load-bearing half. A sweep that ran with a 10 s settle, or on a box already at
# the gate ceiling, still prints a slope; the number simply is not the one it claims to be, and it
# arrives carrying no marking that says so. Every test below that asserts a non-zero exit is
# asserting that a plausible wrong answer was refused instead of printed.
#
# The two MUTATION CHECKS at the bottom neuter one behaviour each in a COPY and assert a positive
# test above flips.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/idle-slope-sweep.sh"
  D="$BATS_TEST_TMPDIR"

  # load = 5.0 + 1.6N and runnable = 0.10 + 0.03N, exactly. A fit that cannot recover a slope it was
  # handed is not a fit, and a synthetic series is the only way to know the arithmetic is right —
  # a real sweep has no ground truth to check against.
  cat > "$D/known.txt" <<'EOF'
0 5.0 0.10
3 9.8 0.19
6 14.6 0.28
9 19.4 0.37
EOF
}

# ── the fit ───────────────────────────────────────────────────────────────────────────────────────

@test "1: the regression recovers a KNOWN slope exactly" {
  run bash -c "'$S' --regress < '$D/known.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"load1"*"+1.60000"* ]] || false
  [[ "$output" == *"mean_runnable"*"+0.03000"* ]]
}

@test "2: R2 is reported beside every slope, never omitted" {
  run bash -c "'$S' --regress < '$D/known.txt'"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'R2 ' <<< "$output")" -eq 2 ]
  [[ "$output" == *"R2 1.000"* ]]
}

@test "3: a NOISY series reports a low R2 rather than a confident slope" {
  # The whole reason R2 is mandatory: these points are not on a line, and the slope must arrive
  # visibly untrustworthy rather than looking identical to test 1's.
  printf '0 5.0 0.10\n3 4.0 0.50\n6 9.0 0.05\n9 3.0 0.60\n' > "$D/noisy.txt"
  run bash -c "'$S' --regress < '$D/noisy.txt'"
  [ "$status" -eq 0 ]
  r2="$(sed -n 's/.*load1.*R2 \([0-9.]*\)).*/\1/p' <<< "$output")"
  [ -n "$r2" ]
  awk -v v="$r2" 'BEGIN{exit !(v < 0.5)}'
}

@test "4: fewer than 3 points is REFUSED, not fitted" {
  printf '0 5.0 0.10\n9 19.4 0.37\n' > "$D/two.txt"
  run bash -c "'$S' --regress < '$D/two.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not computed"* ]] || false
  [[ "$output" == *"2 usable point"* ]] || false
  # It must NOT have printed a slope — a perfect two-point fit is the most misleading output here.
  ! grep -q 'SLOPE = ' <<< "$output" || false
}

@test "5: --regress reads nothing from the machine, so a loaded box cannot refuse it" {
  # Re-analysing last week's sweep must not depend on today's load.
  CC_SLOPE_MAX_START_LOAD=0 run bash -c "'$S' --regress < '$D/known.txt'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"+1.60000"* ]]
}

# ── the refusals ──────────────────────────────────────────────────────────────────────────────────

@test "6: a settle below the 90 s EWMA floor is REFUSED" {
  run "$S" --settle 10 --points "0 3 6"
  [ "$status" -eq 64 ]
  [[ "$output" == *"below the 90 s EWMA floor"* ]]
}

@test "7: a point above CC_SLOPE_MAX_N is REFUSED before anything launches" {
  CC_SLOPE_MAX_N=8 run "$S" --points "0 3 99"
  [ "$status" -eq 64 ]
  [[ "$output" == *"exceeds"* ]]
}

@test "8: a non-numeric point is REFUSED" {
  run "$S" --points "0 3 six"
  [ "$status" -eq 64 ]
  [[ "$output" == *"not a non-negative integer"* ]]
}

@test "9: a box above the start-load floor is REFUSED with its own exit code" {
  # Distinct from 64: a usage error is the operator's typo, a load refusal is the machine saying
  # not now. A caller that cannot tell them apart will retry the one that must not be retried.
  CC_SLOPE_MAX_START_LOAD=0 run "$S" --points "0 3 6"
  [ "$status" -eq 4 ]
  [[ "$output" == *"REFUSED"* ]]
}

@test "10: an unknown argument is a usage error" {
  run "$S" --bogus
  [ "$status" -eq 64 ]
}

# Tests 11-13 assert a SUCCESSFUL --dry-run, so each must pin the start-load floor OUT of the way.
# Unpinned they read the box's live load1, and the floor (default 14) refuses with rc 4 above it —
# so they are green on a quiet desk and RED inside postland-verify, whose own 534-suite corpus is
# what pushes load1 past 14. Measured 2026-09-04: solo rc 0 at load1 11; rc 4 at load1 19.2, in the
# foreground and under `taskpolicy -c background` alike (the QoS band is NOT the variable, load is).
# The floor is pinned HIGH here, never to 0 — test 9 uses 0 precisely to FORCE the refusal.
@test "11: --dry-run launches nothing and says so" {
  CC_SLOPE_MAX_START_LOAD=99999 run "$S" --dry-run --points "0 3 6"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]] || false
  [[ "$output" == *"nothing launched"* ]]
}

@test "12: --dry-run is exempt from the settle floor (it measures nothing)" {
  CC_SLOPE_MAX_START_LOAD=99999 run "$S" --dry-run --settle 5 --points "0 3 6"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]]
}

@test "13: it resolves a claude binary and names it, rather than assuming a path" {
  CC_SLOPE_MAX_START_LOAD=99999 run "$S" --dry-run --points "0 3 6"
  [ "$status" -eq 0 ]
  [[ "$output" == *"binary   :"* ]]
}

@test "14: an absent launcher is refused with the launcher exit code, not a crash" {
  CC_SLOPE_CLAUDE_BIN="$D/no-such-claude" run "$S" --points "0 3 6"
  [ "$status" -eq 4 ]
  [[ "$output" == *"REFUSED"* ]] || [[ "$output" == *"no claude binary"* ]]
}

# ── MUTATION CHECKS — each must FLIP a positive test above ────────────────────────────────────────

@test "M1: MUTATION — dropping the 3-point guard fits two points and reports R2=1.000" {
  m="$D/mutant1.sh"
  sed 's|if (n < 3) {|if (n < 0) {|' "$S" > "$m"
  chmod +x "$m"
  # The mutation must actually have applied — a no-op sed would pass this test vacuously.
  grep -q 'if (n < 0) {' "$m"
  ! grep -q 'if (n < 3) {' "$m" || false

  printf '0 5.0 0.10\n9 19.4 0.37\n' > "$D/two.txt"
  run bash -c "'$m' --regress < '$D/two.txt'"
  [ "$status" -eq 0 ]
  # Test 4 asserted no slope was printed. Neutered, the two points fit perfectly — which is exactly
  # the confident-looking non-result the guard exists to prevent.
  grep -q 'SLOPE = ' <<< "$output" || {
    echo "MUTATION SURVIVED: 3-point guard removed but still no slope printed"; false
  }
  [[ "$output" == *"R2 1.000"* ]]
}

@test "M2: MUTATION — dropping the settle floor accepts a 10 s settle" {
  m="$D/mutant2.sh"
  sed 's|if \[ "$SETTLE_S" -lt 90 \] && \[ "$DRY" = 0 \]; then|if [ "$SETTLE_S" -lt 0 ] \&\& [ "$DRY" = 0 ]; then|' "$S" > "$m"
  chmod +x "$m"
  grep -q 'SETTLE_S" -lt 0 ' "$m"
  ! grep -q 'SETTLE_S" -lt 90 ' "$m" || false

  # Test 6 asserted exit 64. Neutered, the settle check passes and the run proceeds far enough to
  # hit the NEXT refusal (the load floor, forced here) — proving it got past the settle gate rather
  # than being stopped by it.
  CC_SLOPE_MAX_START_LOAD=0 run "$m" --settle 10 --points "0 3 6"
  [ "$status" -ne 64 ] || {
    echo "MUTATION SURVIVED: settle floor removed but a 10 s settle was still refused with 64"; false
  }
  [ "$status" -eq 4 ]
}
