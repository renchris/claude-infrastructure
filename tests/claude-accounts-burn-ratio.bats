#!/usr/bin/env bats
# wall_projection() — the window-PHASE view of the weekly bucket (USAGE_TELEMETRY_100P §1, §3.2).
#
# A point-in-time percentage against a periodically resetting counter is dominated by where you
# are in the window, not by how you are using it. On 2026-08-16 the readout showed three accounts
# at 1-3% weekly with every `pace to 100%` line reading BEHIND; the previous complete windows had
# closed at 91/92/100/85%. The low readings were three windows that had just RESET. Every figure
# was correct and its obvious interpretation was inverted.
#
# The abstain floor is the load-bearing case, not a nicety, and it is now THE LAST 24 h rather
# than the first 8 (docs/research/weekly-reset-utilization-2026-08-25.md §3, §6). Two distinct
# defects sit under one floor:
#
#   * too early to divide — at 1 h elapsed a 1% reading projects to 168%, so an un-floored
#     projection pages on every fresh window, manufacturing the alarm the metric exists to remove;
#   * too early to BELIEVE — burn is back-loaded, not linear, so mid-week the divisor corrects
#     phase and leaves the shape error underneath: a measured mean 46 pp at day 3, 35 pp at day 5,
#     ~20 pp at day 6, ~2 pp at day 7. Silence is the honest reading until the window is closing.
#
# Cases 1-2 pin the abstain, 3 pins that it is a floor and not a stub, and 4-5 pin the two
# mid-week regimes the widening exists for — including the one ⚠ WALL in the backtest, which
# fired at day 3 at 119% against a 99% close and was FALSE.

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

@test "ABSTAINS mid-week where the linear model is wrong by a mean 46pp" {
  # The doc's day-3 median: 21% used with 96h left (72h elapsed). Linear projects 49%; the
  # windows that read like this closed at 92-100%. This case is the whole item — the old 0.05
  # floor let this row speak, and it spoke wrongly for four more days.
  run_wp 21 96
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "ABSTAINS on the day-3 ⚠ WALL that never arrived (next@08-23: 119% projected, 99% actual)" {
  # The one over-projection in the backtest. Silence here is what removes a false page, so this
  # arm is the reason the widening is not a pure loss of signal.
  run_wp 51 96
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "CONTROL: projects once inside the last day, so the abstains above are a floor not a stub" {
  # 24h left is the boundary itself and must SPEAK — MIN_ELAPSED_FRAC is derived from
  # PROJ_SPEAKS_LAST_H by the same arithmetic, so this is exact and not a float near-miss.
  run_wp 90 24
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
  # …and one hour earlier it does not. Both sides, or the boundary is unpinned.
  run_wp 90 25
  [ "$output" = "NONE" ]
}

@test "burn ratio is 1.00x when consumption exactly tracks elapsed window" {
  # 8.4h left => 95% of the window elapsed; 95% of the bucket spent => dead on pace
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
  # 99% spent with 5% of the window left projects past 100: the account hits its limit before
  # reset and is DOWN until it. This is the regime the flag survives for.
  run_wp 99 8.4
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
