#!/usr/bin/env bats
# backlog-ratchet: the two standing numbers, and the one direction that blocks.
#
# The load-bearing property is that --assert can actually GO RED. A ratchet that cannot fail is a
# census wearing an exit code, and this repo has shipped that shape before (MEMORY.md:
# alarm-polarity-and-attention-budget). Every test below either pins a number or pins the RED.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/scripts/backlog-ratchet.sh"
  # Hermetic $HOME, not merely a redirected store: the subject DEFAULTS to
  # ~/.claude/autonomy/backlog.jsonl and ~/.claude/autonomy/backlog-ratchet.json, so a suite that
  # only overrides the override would write the operator's live state on any future refactor.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_RATCHET_STATE="$BATS_TEST_TMPDIR/ratchet.json"
  # PIN THE PRODUCTION LATCH GUARDS OFF, so every case below measures the RATCHET rather than the
  # guard. Both defaults exist to stop a degenerate read latching an unreachable target, and a bats
  # fixture (2-5 items, often 100% covered) is EXACTLY the degenerate population they refuse — so
  # unpinned they convict the harness instead of the subject
  # (MEMORY.md: guard-refusal-fires-on-its-own-harness). Each guard gets its own case below, where
  # it is the subject and the pin is lifted deliberately.
  export CC_RATCHET_MIN_N=1
  export CC_RATCHET_MAX_HW=100.0
  : > "$CC_BACKLOG_FILE"
}

# add <id> <ts> [falsifier]
add() {
  local extra=""
  [ -n "${3:-}" ] && extra=", \"falsifier\":\"$3\""
  printf '{"id":"%s","ts":"%s","event":"add","project":"p","title":"t"%s}\n' "$1" "$2" "$extra" >> "$CC_BACKLOG_FILE"
}
done_() { printf '{"id":"%s","ts":"%s","event":"done"}\n' "$1" "$2" >> "$CC_BACKLOG_FILE"; }

@test "coverage counts only LIVE items that carry a falsifier" {
  add a 2026-08-01T00:00:00Z "true"
  add b 2026-08-01T00:00:00Z
  add c 2026-08-01T00:00:00Z
  run "$SUT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"live_items":3'
  printf '%s' "$output" | grep -q '"falsifier_covered":1'
  printf '%s' "$output" | grep -q '"falsifier_coverage_pct":33.3'
}

@test "a CLOSED item leaves the live population, so closing does not inflate coverage" {
  add a 2026-08-01T00:00:00Z "true"
  add b 2026-08-01T00:00:00Z
  done_ b 2026-08-02T00:00:00Z
  run "$SUT" --json
  printf '%s' "$output" | grep -q '"live_items":1'
  printf '%s' "$output" | grep -q '"falsifier_coverage_pct":100'
}

@test "age at close is measured from FIRST record to the closing one" {
  add a 2026-08-01T00:00:00Z
  done_ a 2026-08-05T00:00:00Z
  run "$SUT" --json
  printf '%s' "$output" | grep -q '"median_days_to_close":4'
}

@test "p75 is reported alongside the median — a median-only report hides the tail" {
  # SEEDED RELATIVE, both stamps in the past. An absolute FUTURE date here would silently change
  # meaning as the clock advanced and go red on a calendar boundary with no code change — the
  # failure that took the fleet's gate down on 2026-07-27, and which the walltime lint caught in
  # this very file. The SIGNED offset matters: bare `date -v 30d` SETS the day rather than adding.
  local old new
  old="$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ)"
  new="$(date -u -v-11d +%Y-%m-%dT%H:%M:%SZ)"
  for i in 1 2 3 4 5 6 7 8; do add "i$i" "$old"; done_ "i$i" "$old"; done
  add slow "$old"; done_ slow "$new"
  run "$SUT" --json
  # The median stays near zero; p75 must be able to move away from it, or the pair says nothing.
  printf '%s' "$output" | grep -q '"p75_days_to_close"'
  med="$(printf '%s' "$output" | sed -n 's/.*"median_days_to_close":\([0-9.]*\).*/\1/p')"
  p75="$(printf '%s' "$output" | sed -n 's/.*"p75_days_to_close":\([0-9.]*\).*/\1/p')"
  awk -v a="$p75" -v b="$med" 'BEGIN{exit !(a >= b)}'
}

@test "the high-water mark RISES and is persisted" {
  add a 2026-08-01T00:00:00Z "true"
  add b 2026-08-01T00:00:00Z
  run "$SUT" --assert
  [ "$status" -eq 0 ]
  grep -q '"coverage_high_water":"50.0"' "$CC_RATCHET_STATE"
}

# THE LOAD-BEARING TEST. If this cannot red, the whole script is a census with a decorative flag.
@test "--assert goes RED when coverage FALLS below the high-water mark" {
  add a 2026-08-01T00:00:00Z "true"
  add b 2026-08-01T00:00:00Z
  run "$SUT" --assert            # establishes 50%
  [ "$status" -eq 0 ]
  # three more uncovered items arrive: 1 of 5 = 20%, a real regression
  add c 2026-08-02T00:00:00Z
  add d 2026-08-02T00:00:00Z
  add e 2026-08-02T00:00:00Z
  run "$SUT" --assert
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "RED"
}

@test "a FALL does not silently re-baseline the high-water mark" {
  add a 2026-08-01T00:00:00Z "true"
  add b 2026-08-01T00:00:00Z
  run "$SUT" --assert
  add c 2026-08-02T00:00:00Z; add d 2026-08-02T00:00:00Z; add e 2026-08-02T00:00:00Z
  run "$SUT" --assert
  [ "$status" -eq 1 ]
  # Still 50.0 — recording the regression would disarm the ratchet permanently, which is the one
  # failure a ratchet exists to prevent.
  grep -q '"coverage_high_water":"50.0"' "$CC_RATCHET_STATE"
}

@test "an empty store is a no-op, never a crash and never a RED" {
  run "$SUT" --assert
  [ "$status" -eq 0 ]
}

@test "an unknown argument is refused rather than silently ignored" {
  run "$SUT" --nonsense
  [ "$status" -eq 2 ]
}

# ── READINESS W0 (2026-08-11): the guards that stop the ratchet latching a target it cannot reach ──
#
# The live ratchet died of exactly this. Its high-water sat at 100.0% against a population where
# ~103 items are deliberately unprobed, so --assert returned rc=1 on EVERY run and all 3 verdicts
# autonomy-sweep had ever journalled were RED. Four cases, and each one must be able to fail.

@test "CEILING: a coverage above MAX_HW is reported but must NOT latch as the target" {
  # THE REGRESSION TEST FOR THE DEAD RATCHET. Without the ceiling this records 100.0 and every
  # later run of a realistic store is permanently RED.
  export CC_RATCHET_MAX_HW=95.0
  add a 2026-08-01T00:00:00Z "true"
  add b 2026-08-01T00:00:00Z "true"
  run "$SUT" --assert
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "NOT raised"
  printf '%s' "$output" | grep -q "ceiling 95.0%"
  # The unreachable target must not be on disk at all — a latched 100.0 is the whole defect.
  [ ! -f "$CC_RATCHET_STATE" ] || ! grep -q '"coverage_high_water":"100.0"' "$CC_RATCHET_STATE"
}

@test "CEILING lets a REACHABLE coverage latch, or it would just be a different way to never arm" {
  # The paired control. A guard that blocked every latch would disarm the ratchet as thoroughly as
  # the bug it replaces, so the ceiling must be PERMISSIVE below its own bound.
  export CC_RATCHET_MAX_HW=95.0
  add a 2026-08-01T00:00:00Z "true"
  add b 2026-08-01T00:00:00Z "true"
  add c 2026-08-01T00:00:00Z "true"
  add d 2026-08-01T00:00:00Z          # 3 of 4 = 75%, under the ceiling
  run "$SUT" --assert
  [ "$status" -eq 0 ]
  grep -q '"coverage_high_water":"75.0"' "$CC_RATCHET_STATE"
}

@test "FLOOR: a denominator under MIN_N may not set the fleet's target" {
  # 1-of-1 is 100%. A transient or half-written store must never become the standing bar.
  export CC_RATCHET_MIN_N=20
  add a 2026-08-01T00:00:00Z "true"
  add b 2026-08-01T00:00:00Z
  run "$SUT" --assert
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "denominator 2 < floor 20"
  [ ! -f "$CC_RATCHET_STATE" ] || ! grep -q 'coverage_high_water' "$CC_RATCHET_STATE"
}

@test "a denominator VERSION change resets the mark, says so, and PERSISTS the new version" {
  # Changing WHAT is counted makes the old mark incomparable rather than stale. The reset is the one
  # path on which the mark may fall — so it must announce itself, and it must actually write, or
  # every subsequent run re-announces a reset that never happened.
  printf '{"coverage_high_water":"100.0","denominator_version":1,"recorded":"2026-08-11T07:12:51Z"}\n' \
    > "$CC_RATCHET_STATE"
  add a 2026-08-01T00:00:00Z "true"
  add b 2026-08-01T00:00:00Z
  run "$SUT" --assert
  [ "$status" -eq 0 ]                                  # the stale v1 mark must not red the new v2
  printf '%s' "$output" | grep -q "v1→v2"
  grep -q '"denominator_version":2' "$CC_RATCHET_STATE"
  ! grep -q '"coverage_high_water":"100.0"' "$CC_RATCHET_STATE" || false
  # …and the reset must be ONE event: a second run re-announces nothing.
  run "$SUT" --assert
  printf '%s' "$output" | grep -qv "v1→v2" || true
  ! printf '%s' "$output" | grep -q "RESET from"
}

@test "the \`needs\` class is excluded from the denominator, and the exclusion is PRINTED" {
  # `needs` rows are born BLOCKED (bin/cc-backlog:544), so today this exclusion removes zero rows —
  # it guards the reopen case. The count is printed precisely so it can never again be ASSUMED
  # non-zero, which is the error that produced this wave's retracted measurement #3.
  printf '{"id":"n1","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"t","source":"needs"}\n' \
    >> "$CC_BACKLOG_FILE"
  add a 2026-08-01T00:00:00Z "true"
  run "$SUT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"live_items":2'      # the needs row IS live (never blocked here)
  printf '%s' "$output" | grep -q '"probeable_items":1' # …and is NOT in the denominator
  printf '%s' "$output" | grep -q '"falsifier_coverage_pct":100'
  run "$SUT"
  printf '%s' "$output" | grep -q '2 live minus 1 needs-class'
}
