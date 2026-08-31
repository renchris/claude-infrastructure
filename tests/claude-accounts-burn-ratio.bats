#!/usr/bin/env bats
# wall_projection() — the window-PHASE view of the weekly bucket (USAGE_TELEMETRY_100P §1, §3.2).
#
# A point-in-time percentage against a periodically resetting counter is dominated by where you
# are in the window, not by how you are using it. On 2026-08-16 the readout showed three accounts
# at 1-3% weekly with every `pace to 100%` line reading BEHIND; the previous complete windows had
# closed at 91/92/100/85%. The low readings were three windows that had just RESET. Every figure
# was correct and its obvious interpretation was inverted.
#
# The abstain floor is the load-bearing case, not a nicety: at 1 h elapsed a 1% reading projects
# to 168%, so an un-floored projection pages on every fresh window — manufacturing exactly the
# false alarm the metric exists to remove. Cases 1 and 2 pin both sides of that floor.
#
# THERE ARE NOW TWO FLOORS, and the second one is why the arithmetic cases below moved from 84 h
# remaining to 42 h (docs/research/weekly-reset-utilization-2026-08-25.md §3, §6). Dividing by
# elapsed fraction corrects for PHASE only under an assumption of LINEAR burn, and across the four
# windows with day-1 coverage burn is heavily back-loaded, so the shape error survives underneath
# the phase fix. Backtested at day 3 this function was wrong by a mean 46 pp — it under-projected
# three accounts that closed at 92-100% and flagged a ⚠ WALL for the fourth that never arrived —
# and still by 35 pp at day 5. Linear and empirical converge only at the close (-17 pp day 6,
# -2 pp day 7), so it now abstains outside SPEAK_WITHIN_H of the reset.
#
# The arithmetic cases were re-parameterised, NOT re-pointed: 42 h remaining is 0.75 elapsed, so
# every ratio/projection they assert is the same exact number as before, computed inside the
# region where the function is now allowed to speak. What they pin is the division, and moving a
# fixture into the admissible region preserves that; leaving them at 84 h would have turned them
# into assertions that the new floor does not exist.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/bin/claude-accounts"
  # HERMETICITY: the subject reads ~/.claude* for config and the utilization series. Fixture $HOME
  # so no case can touch the operator's live tree or be steered by its contents.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
}

# wall_projection(weekly_pct=$WP_PCT, weekly_reset_h=$WP_H) -> "ratio proj" | "NONE"
# Inputs arrive by env, not argv: the subject is a CLI that parses sys.argv at import, so any
# argv we pass would be read by IT rather than by us.
wp() {
  SUT="$SUT" python3 <<'PY'
import importlib.machinery, importlib.util, os, sys
sys.argv = ["claude-accounts"]
path = os.environ["SUT"]
loader = importlib.machinery.SourceFileLoader("ca", path)
spec = importlib.util.spec_from_loader("ca", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
r, p = m.wall_projection({"weekly_pct": float(os.environ["WP_PCT"]),
                          "weekly_reset_h": float(os.environ["WP_H"])})
print("NONE" if r is None else f"{r:.4f} {p:.2f}")
PY
}

run_wp() { export WP_PCT="$1" WP_H="$2"; run wp; }

@test "ABSTAINS on a barely-started window (the 168% false-alarm class)" {
  # 1% used, 167h left => 0.6% elapsed, well under the 5% floor. An un-floored projection
  # would read ~168% and page. The honest answer is 'too early to say'.
  run_wp 1 167
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "CONTROL: projects once inside BOTH floors, so the abstains are floors and not a stub" {
  # 42h left of 168 = 0.75 elapsed: past the 5% phase floor AND inside the 48h shape floor.
  run_wp 50 42
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
}

@test "burn ratio is 1.00x when consumption exactly tracks elapsed window" {
  # 0.75 through the week (42h left), three quarters of the bucket spent => dead on pace
  run_wp 75 42
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qE '^1\.0000 100\.00$'
}

@test "burn ratio is 0.50x when half on pace — the under-use signal" {
  run_wp 37.5 42
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qE '^0\.5000 50\.00$'
}

@test "projects PAST 100 when over pace — the wall the alarm exists for" {
  # 90% spent with 42h left projects to 120%: the account hits its limit early and is DOWN
  run_wp 90 42
  [ "$status" -eq 0 ]
  proj="$(printf '%s' "$output" | awk '{print $2}')"
  [ "$(python3 -c "print(1 if $proj >= 100 else 0)")" -eq 1 ]
}

@test "ABSTAINS mid-week on the four windows it was BACKTESTED wrong by 34-70 pp" {
  # The regression case, and it is real data, not a constructed one. Each pair below is a
  # measured day-3 reading (96h left) from docs/research/weekly-reset-utilization-2026-08-25.md
  # §3 with what that window ACTUALLY closed at. The old linear form projected 28 / 40 / 58 /
  # 119% against finals of 98 / 100 / 92 / 99% — errors of -70, -60, -34 and +20 pp, mean
  # absolute 46 pp. Two of these accounts sat at 12% and 17% on day 3 and finished at 98% and
  # 100%; no divisor recovers that from a linear model. Silence is the only honest output here.
  for pct in 12 17 25 51; do
    run_wp "$pct" 96
    [ "$status" -eq 0 ]
    [ "$output" = "NONE" ]
  done
}

@test "ABSTAINS on the mid-week ⚠ WALL that never arrived — the FALSE-POSITIVE direction" {
  # next@08-23 read 51% at day 3, which the linear form projected to 119% and rendered as a
  # ⚠ WALL trajectory. The window closed at 99%. The wall was manufactured by the model, and
  # a WALL flag is the most consequential thing this line renders, so it is pinned separately
  # from the under-projections above: widening the abstain has to suppress BOTH signs, not just
  # the one that reads as under-use.
  run_wp 51 96
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "the shape floor is at SPEAK_WITHIN_H and is INCLUSIVE — both sides pinned" {
  # 48h left speaks; a minute earlier does not. Pinning equality explicitly because the floor is
  # a boundary the constant is expected to move once >=2 more cycles land (§5.2 — 4 windows
  # refute linearity but cannot calibrate a curve), and a boundary nobody pinned moves silently.
  run_wp 60 48
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
  run_wp 60 48.1
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "ABSTAINS at day 5, where the projection is still wrong by ~35 pp" {
  # 120h elapsed / 48h left is the boundary above; day 5 proper (72h left) is outside it. This
  # is the case that keeps the floor from being widened to 'the last ~3 days' by someone reading
  # §6's prose without §3's table: the error is still 35 pp here.
  run_wp 47 72
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "BOTH floors survive as separate refusals, not one collapsed into the other" {
  # They are nested by arithmetic today (0.05 elapsed = 159.6h left, far outside 48h) but not by
  # design: they refuse for different reasons — phase noise vs a refuted linear shape — and a
  # future recalibration of the shape floor must not take the noise floor with it. Deleting
  # either check would leave this file's cases 1 and 5 passing, so the constants are pinned.
  grep -qE '^MIN_ELAPSED_FRAC = ' "$SUT"
  grep -qE '^SPEAK_WITHIN_H = ' "$SUT"
  grep -q 'if wrh > SPEAK_WITHIN_H:' "$SUT"
  grep -q 'if frac < MIN_ELAPSED_FRAC:' "$SUT"
}

@test "ABSTAINS on a reset stamp outside the bucket (bad data is not a signal)" {
  run_wp 50 400
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
  run_wp 50 0
  [ "$output" = "NONE" ]
}

@test "the footer no longer frames 100% as the target" {
  # 100% is the WALL — an account that reaches it is down until reset. The old caption read
  # 'pace to 100%', which named the failure mode as the goal.
  #
  # ASSERTION UPDATED IN PLACE, invariant unchanged (USAGE_TELEMETRY_100P §5.2 S3). This case
  # used to grep for the literal caption 'lands exactly at the 100% wall'. That string was the
  # PREVIOUS remedy for this defect and S3 replaced the caption it lived in: the footer is now
  # a per-account drain block headed 'pp that DIE at reset'. Greping a spelling rather than the
  # invariant is how a live assertion becomes a tripwire on its own subject's next fix — the
  # caption changed, the defect did not come back, and only the string moved. So the arms below
  # pin what the case is FOR: the header must name the loss, the wall flag must survive, and
  # neither the old target-framing nor a raw >100 projection may return.
  grep -q 'pp that DIE at reset' "$SUT"
  grep -q '⚠ WALL trajectory' "$SUT"
  ! grep -q '"pace to 100%: "' "$SUT" || false
  ! grep -q 'lands exactly at the 100% wall' "$SUT" || false
}

@test "the derived fields are exported for machine consumers, not just rendered" {
  # the governed dispatcher routes on these; a renderer-only metric cannot be routed on
  grep -q 'r\["burn_ratio"\] = ratio' "$SUT"
  grep -q 'r\["proj_end_pct"\] = proj' "$SUT"
  grep -q 'r\["wall_risk"\] = proj >= 100.0' "$SUT"
}
