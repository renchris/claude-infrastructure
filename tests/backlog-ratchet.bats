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
  [ "$status" -eq 0 ]                                  # the stale v1 mark must not red the new v3
  printf '%s' "$output" | grep -q "v1→v3"
  grep -q '"denominator_version":3' "$CC_RATCHET_STATE"
  ! grep -q '"coverage_high_water":"100.0"' "$CC_RATCHET_STATE" || false
  # …and the reset must be ONE event: a second run re-announces nothing.
  run "$SUT" --assert
  printf '%s' "$output" | grep -qv "v1→v3" || true
  ! printf '%s' "$output" | grep -q "RESET from"
}

# ── THE NUMERATOR SEES ALL THREE PROBE ARMS (item e08ad9ab1ff6) ─────────────────────────────────
# The regression these pin: coverage counted only the STORED `falsifier` field while cc-premise
# `assess` composes stored + derived-plan + derived-postland. `post-land RED:` rows store no probe
# ON PURPOSE (cc-premise derives it; postland-verify's --falsify-red header says storing an equal
# probe would shadow a tested arm), and postland-verify is the highest-volume generator — so every
# red trunk mechanically depressed coverage with no row losing any ability to re-check itself, and
# --assert went RED on that. A mutant that reverts the numerator to stored-only must kill case 1.

# postland_row <id> <suite> — a row of the class that is DERIVED-covered and stores nothing.
postland_row() {
  printf '{"id":"%s","ts":"2026-08-01T00:00:00Z","event":"add","project":"claude-infrastructure","source":"postland-verify","title":"post-land RED: tests/%s.bats::a test @ abcdef1234567"}\n' \
    "$1" "$2" >> "$CC_BACKLOG_FILE"
}

@test "a DERIVED-covered row counts as covered — the stored field is not the whole numerator" {
  add a 2026-08-01T00:00:00Z "true"
  postland_row r1 alpha
  postland_row r2 beta
  run "$SUT" --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"probeable_items":3'
  # 3, not 1: the two postland rows are spoken for by run_derived_postland_falsifier.
  printf '%s' "$output" | grep -q '"falsifier_covered":3'
  printf '%s' "$output" | grep -q '"falsifier_coverage_pct":100'
  printf '%s' "$output" | grep -q '"coverage_source":"premise"'
}

@test "a red trunk must NOT depress coverage — the defect that made --assert fire on the wrong event" {
  # Seed a mark, then file the burst of post-land RED rows a red trunk produces. Under the
  # stored-only numerator this fell from 100% to 25% and went RED; nothing about the store's
  # self-checking ability changed.
  add a 2026-08-01T00:00:00Z "true"
  printf '{"coverage_high_water":"100.0","denominator_version":3,"recorded":"2026-08-14T00:00:00Z"}\n' \
    > "$CC_RATCHET_STATE"
  postland_row r1 alpha
  postland_row r2 beta
  postland_row r3 gamma
  run "$SUT" --assert
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q "RED"
}

@test "the census reports coverage BY ARM, so a derived-covered store is not read as unprobed" {
  add a 2026-08-01T00:00:00Z "true"
  postland_row r1 alpha
  run "$SUT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "1 stored"
  printf '%s' "$output" | grep -q "1 derived-postland"
}

@test "a RED NAMES the generator whose rows are uncovered, instead of a generic instruction" {
  # The old text said "Add --falsifier to the generator that regressed" and named none — which for
  # the postland population also prescribed the change its sibling documents as harmful.
  printf '{"coverage_high_water":"90.0","denominator_version":3,"recorded":"2026-08-14T00:00:00Z"}\n' \
    > "$CC_RATCHET_STATE"
  add a 2026-08-01T00:00:00Z "true"
  printf '{"id":"u1","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"t","source":"sess-abc"}\n' >> "$CC_BACKLOG_FILE"
  printf '{"id":"u2","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"t","source":"sess-abc"}\n' >> "$CC_BACKLOG_FILE"
  run "$SUT" --assert
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "sess-abc (2 of 2)"
  ! printf '%s' "$output" | grep -q "the generator that regressed"
}

@test "an UNASKABLE cc-premise reports UNKNOWN and declines to judge — never the stored-only count" {
  # THE LOAD-BEARING FAIL-OPEN. The stored-only number is systematically LOWER, so falling back to
  # it would compare it against a mark recorded from the composed count and go RED on the sensor
  # being broken — a false alarm indistinguishable from a true one
  # (MEMORY.md: sensor-default-off-makes-blindness-the-shipping-path).
  export CC_RATCHET_PREMISE_BIN="$BATS_TEST_TMPDIR/no-such-cc-premise"
  printf '{"coverage_high_water":"90.0","denominator_version":3,"recorded":"2026-08-14T00:00:00Z"}\n' \
    > "$CC_RATCHET_STATE"
  add a 2026-08-01T00:00:00Z "true"
  add b 2026-08-01T00:00:00Z
  add c 2026-08-01T00:00:00Z
  run "$SUT" --assert
  [ "$status" -eq 0 ]                                   # NOT a RED — nothing was measured
  printf '%s' "$output" | grep -q "NOT MEASURED"
  # …and it must not latch anything, or one broken run re-baselines the fleet's target.
  grep -q '"coverage_high_water":"90.0"' "$CC_RATCHET_STATE"
  run "$SUT" --json
  printf '%s' "$output" | grep -q '"coverage_source":"unknown"'
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

# ── THE ENGINE GUARD IS FAIL-CLOSED (backlog 2366f99e04a7) ───────────────────────────────────────
# 🚨 HERE THE FAIL-OPEN DID NOT MERELY MISREPORT — IT WOULD HAVE RETRACTED A STANDING ROW, which is
# why this sibling's guard matters more than the trigger's. `--assert` is registered as the stored
# falsifier at autonomy-sweep.sh:803 for the row that same block files (condition
# backlog-ratchet-coverage-regression), and cc-premise's `run_falsifier` reads exit 0 as THE
# CONDITION IS GONE. So an absent jq did not fail to measure coverage: it told the currency pass the
# regression had cleared and handed the closer a retraction built on a measurement that never ran.
# 2 is in cc-premise's _FALSIFIER_UNASKABLE_RCS ({2,124,126,127}) and renders "UNVERIFIED".
#
# THE NO-FILING ARM IS PINNED TOO, because it is a deliberate asymmetry with the trigger sibling
# rather than an omission: this script's scheduled mode IS the probe, and a probe that writes to the
# ledger it is being asked about is not a probe. A later "consistency" edit that adds a filing here
# reds the last case below.

# A PATH with no jq on it — named, not shadowed: absence cannot be spelled as an override.
nojq_path() {
  local d="$BATS_TEST_TMPDIR/nojq" t p
  mkdir -p "$d"
  for t in dirname date mkdir rm head tr cat grep sed; do
    p="$(command -v "$t" 2>/dev/null)"
    [ -n "$p" ] && ln -sf "$p" "$d/$t"
  done
  printf '%s' "$d"
}

# THE MUTANT: the pre-fix fail-open restored at the one site this change touched, anchored both ways
# so a rename reds the anchor instead of quietly producing a mutant identical to the subject. A sed
# over the working tree rather than a `git show` of a ref — a branch name advances past the fix the
# moment it lands and the control would then compare the fix to itself
# (memory: control-must-replay-the-real-artifact).
eg_mutant() {
  EG_MUT="$BATS_TEST_TMPDIR/mutant-ratchet.sh"
  [ "$(grep -c 'CANNOT MEASURE (fail-closed, rc 2)' "$SUT")" -eq 1 ]
  # Delimiter `@`, not `|`: the replacement contains `||` and sed reads the first one as the closing
  # delimiter ("bad flag in substitute command"). Caught by running it, not by reading it.
  sed "s@^command -v jq .*@command -v jq >/dev/null 2>\&1 || { printf 'backlog-ratchet: jq missing — fail-open\\\\n' >\&2; exit 0; }@" "$SUT" > "$EG_MUT"
  [ "$(grep -c 'CANNOT MEASURE (fail-closed, rc 2)' "$EG_MUT")" -eq 0 ]
  chmod +x "$EG_MUT"
}

@test "no jq ⇒ rc 2 — the 0 it used to return RETRACTED its own stored falsifier" {
  # The store guard sits above the engine guard, so a fixture without a store would exit 0 at the
  # WRONG guard and say nothing about this change. setup() writes it; re-assert rather than trust.
  [ -f "$CC_BACKLOG_FILE" ]
  add a 2026-08-01T00:00:00Z "true"
  # `env` rather than a PATH prefix on `run`: the restricted PATH has no bash either, so the prefix
  # form exits 127 and every assertion would be measuring the harness.
  run env PATH="$(nojq_path)" /bin/bash "$SUT" --assert
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'CANNOT MEASURE'
}

@test "MUTANT: the pre-fix exit reaches 0 on the same fixture — the arm that credits the change" {
  [ -f "$CC_BACKLOG_FILE" ]
  add a 2026-08-01T00:00:00Z "true"
  eg_mutant
  run env PATH="$(nojq_path)" /bin/bash "$EG_MUT" --assert
  # rc 0 is exactly what cc-premise reads as THE CONDITION IS GONE.
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'fail-open'
}

@test "no jq ⇒ rc 2 in the census mode too, not only under --assert" {
  [ -f "$CC_BACKLOG_FILE" ]
  run env PATH="$(nojq_path)" /bin/bash "$SUT"
  [ "$status" -eq 2 ]
  run env PATH="$(nojq_path)" /bin/bash "$SUT" --json
  [ "$status" -eq 2 ]
}

@test "the engine-absent exit WRITES NOTHING — this sibling files no row, deliberately" {
  [ -f "$CC_BACKLOG_FILE" ]
  add a 2026-08-01T00:00:00Z "true"
  local before after
  before="$(cksum < "$CC_BACKLOG_FILE")"
  run env PATH="$(nojq_path)" /bin/bash "$SUT" --assert
  [ "$status" -eq 2 ]
  after="$(cksum < "$CC_BACKLOG_FILE")"
  [ "$before" = "$after" ]
  # …and it does not latch a high-water mark off a measurement that never happened.
  [ ! -f "$CC_RATCHET_STATE" ]
}

@test "POLARITY: engine present is never rc 2 — an alarm that always fires carries no bits" {
  add a 2026-08-01T00:00:00Z "true"
  run "$SUT" --assert
  [ "$status" -ne 2 ]
  run "$SUT" --json
  [ "$status" -eq 0 ]
}
