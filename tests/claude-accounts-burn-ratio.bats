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
# FLOOR WIDENED 0.05 -> 0.90 (2026-08-29). The 0.05 floor removed the fresh-window alarm and then
# licensed the projection for the six days above it, where it is measurably uninformative: weekly
# burn is back-loaded 2.3x (10.9 pp/day through phase 0.7, 25.2 pp/day after), so dividing by
# elapsed fraction corrects the PHASE error and leaves the SHAPE error underneath. Backtested MAE
# is 46 pp at day 3 and 35 pp at day 5, against 5.3 pp for the constant "94%". The mid-week cases
# below are the ones that RED-prove the widening — each PASSED under the old floor by projecting a
# number that the window then missed by 34-70 pp. Sources: weekly-reset-utilization-2026-08-25.md
# §3/§6, drain-telemetry-2026-08-25/axis-D-windows.md §4/§4a/§5.

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

@test "CONTROL: projects once past the floor, so the abstain above is the floor and not a stub" {
  # 8.4h left of 168 => phase 0.95, above the floor. Without this case every abstain below is
  # satisfied by a function that never projects at all.
  run_wp 90 8.4
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
}

@test "ABSTAINS at mid-week, where the linear divisor is wrong by a mean 46 pp" {
  # Phase 0.5, dead on linear pace. The OLD floor answered '1.0000 100.00' here with full
  # confidence. Measured: at phase 0.5 the four observed windows sat at 61/31/20/13% and ALL
  # FOUR finished at 92-100%, so the reading carries essentially no information about the end.
  run_wp 50 84
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "ABSTAINS on the day-3 window that projected 28% and finished 98%" {
  # next3@08-18, verbatim from the backtest (weekly-reset-utilization §3): 12% used with 96h
  # left => 0.28x burn, linear projection 28%, ACTUAL final 98%. Error -70 pp. This is the
  # single worst row measured and the reason the floor moved; it PASSED under 0.05.
  run_wp 12 96
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "the floor sits at phase 0.90 — pinned from BOTH sides, one hour apart" {
  # 17h left => phase 0.8988, silent. 16h left => phase 0.9048, speaks. A floor asserted from
  # one side only is satisfied by any larger number, including a stub that never projects.
  run_wp 99 17
  [ "$output" = "NONE" ]
  run_wp 99 16
  [ "$output" != "NONE" ]
}

@test "burn ratio is 1.00x when consumption exactly tracks elapsed window" {
  # phase 0.95 (8.4h left), 95% of the bucket spent => dead on pace
  run_wp 95 8.4
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qE '^1\.0000 100\.00$'
}

@test "burn ratio is 0.50x when half on pace — the under-use signal" {
  run_wp 47.5 8.4
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qE '^0\.5000 50\.00$'
}

@test "projects PAST 100 when over pace — the wall the alarm exists for" {
  # 99% spent with 8.4h left projects to 104%: the account hits its limit before reset and is
  # DOWN until then. This is the one regime the widened floor deliberately KEEPS — near the
  # wall, where linear and empirical have converged (-2 pp at day 7).
  run_wp 99 8.4
  [ "$status" -eq 0 ]
  proj="$(printf '%s' "$output" | awk '{print $2}')"
  [ "$(python3 -c "print(1 if $proj >= 100 else 0)")" -eq 1 ]
}

@test "the floor CONSTANT is 0.90, so a silent revert to 0.05 cannot pass unnoticed" {
  # The behavioural cases above pin the boundary, but a reverted constant plus a re-tuned
  # fixture would satisfy them. This pins the value the research names.
  grep -qE '^MIN_ELAPSED_FRAC = 0\.90\b' "$SUT"
  ! grep -qE '^MIN_ELAPSED_FRAC = 0\.05\b' "$SUT" || false
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
