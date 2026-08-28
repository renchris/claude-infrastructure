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
# false alarm the metric exists to remove.
#
# THERE ARE NOW TWO FLOORS, for two different defects, and the SECOND one is wider
# (docs/research/weekly-reset-utilization-2026-08-25.md §3, §6):
#
#   MIN_ELAPSED_FRAC (0.05)       a NOISY DENOMINATOR. Case 1 pins it.
#   MIN_PROJ_ELAPSED_FRAC (0.714) the WRONG MODEL. `proj_end` divides by elapsed fraction, which
#                                 is exact only under LINEAR burn; measured burn is heavily
#                                 back-loaded, so the mid-week projection errs by a mean 46 pp
#                                 and once fired ⚠ WALL on a window that closed at 99%. Cases
#                                 2/2b/2c pin it and its carve-out.
#
# Every arithmetic case below therefore reads its window inside the last ~2 days, where linear and
# empirical converge — that is not fixture noise, it is the only phase where the number exists.

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

@test "ABSTAINS mid-week — the linear model is REFUTED there, not merely noisy" {
  # ASSERTION INVERTED IN PLACE, and the inversion IS the fix. This case used to read `run_wp 10
  # 144` and assert `!= NONE` as the CONTROL for case 1's floor. That day-1 reading is exactly
  # what the backtest measures as broken: `proj_end` divides by elapsed fraction, which corrects
  # for PHASE, and a phase fix looks like it corrects for shape too. It does not — burn is
  # heavily back-loaded (empirical median at day 3 is 21% against the linear model's 43%).
  #
  # The fixture below is the backtest's own worst row, replayed: next@2026-08-23 sat at 51% with
  # 96h left (day 3), the shipped projection read 1.19x -> 119% and rendered ⚠ WALL, and the
  # window closed at 99%. A wall that never arrived, on the ONE account of four that was ahead of
  # linear; the other three under-projected by 34-70 pp. Mean absolute error 46 pp.
  run_wp 51 96
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
  # ...and it is the PHASE that decides, not the reading: the same 51% deep in the window speaks.
  run_wp 51 24
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
}

@test "2b the shape floor is EXACTLY the last 2 days — both sides of 48h, so it is a boundary" {
  # A floor asserted from one side only is satisfiable by an always-None stub AND by an
  # off-by-one that admits the whole week. 48.0h left = 120h elapsed = frac 0.7142857, admitted;
  # one minute earlier in the window is not.
  run_wp 60 48
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
  run_wp 60 48.1
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "2c CARVE-OUT: an account already AT the wall projects at ANY phase — that is not a forecast" {
  # The shape floor exists because extrapolating a back-loaded curve is wrong. weekly_pct 100 is
  # not an extrapolation: the account is DOWN until reset (next3 sat at exactly 100% for 11.2h on
  # 2026-08-11). Silencing its ⚠ WALL would drop an alarm about a FACT to fix a forecast.
  run_wp 100 96
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
  proj="$(printf '%s' "$output" | awk '{print $2}')"
  [ "$(python3 -c "print(1 if $proj >= 100 else 0)")" -eq 1 ]
  # The NOISE floor is absolute and the carve-out does NOT pierce it — at frac 0 this divides by
  # zero, so a carve-out written as an early `return` rather than a second predicate crashes here.
  run_wp 100 168
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "burn ratio is 1.00x when consumption exactly tracks elapsed window" {
  # 42h left = 126h elapsed = frac 0.75, inside the last 2 days. 75% of the bucket spent at 75%
  # elapsed => dead on pace. (Was 50/84 — the halfway mark, which the shape floor now abstains on.)
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
  # 90% spent at 75% elapsed projects to 120%: the account hits its limit early and is DOWN.
  # This is the phase where the alarm SURVIVES the shape floor, and where its residual error is
  # one-signed — linear still UNDER-projects here (-17pp at day 6), so a fired WALL is
  # trustworthy even though silence is not proof of safety.
  run_wp 90 42
  [ "$status" -eq 0 ]
  proj="$(printf '%s' "$output" | awk '{print $2}')"
  [ "$(python3 -c "print(1 if $proj >= 100 else 0)")" -eq 1 ]
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
