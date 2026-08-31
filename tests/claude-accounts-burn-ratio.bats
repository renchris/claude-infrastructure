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
# THE FLOOR WIDENED 0.05 → 0.714 on 2026-08-31 (weekly-reset-utilization-2026-08-25.md §3, §6).
# The divisor corrects for PHASE only under an assumption of LINEAR burn, and this fleet's burn is
# heavily back-loaded: the shipped projection backtests at a mean absolute 46 pp error at day 3
# (12% and 17% on day 3 → closed 98% and 100%; a 119% ⚠ WALL → closed 99%). So the projection now
# speaks only in the window's last 48 h, where linear and empirical converge (day 6: −17 pp;
# day 7: −2 pp). The ARITHMETIC cases below are unchanged in what they pin and were moved into
# that phase — the ratio identities were never the defect, only the phase they were trusted in.

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
  # 47h left = 121h elapsed of 168 = 72.0%, just past the 71.4% floor. Deliberately ONE hour
  # inside it: a control far from the boundary would still pass if the floor were moved again.
  run_wp 60 47
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
}

@test "ABSTAINS mid-week, where the linear divisor is refuted (the 46 pp error class)" {
  # Dead halfway: 84h left. This is the exact phase the backtest measures at a mean absolute
  # 46 pp error at day 3, and it USED TO PROJECT — 50/84 rendered a confident 1.00x / 100%.
  # Two real windows read 12% and 17% here and closed at 98% and 100%.
  run_wp 50 84
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
  # ...and the over-pace side of the same phase, which is where the FALSE `⚠ WALL` came from:
  # next@08-23 read 51% at day 3, projected 119% ⚠ WALL, and closed at 99%.
  run_wp 51 84
  [ "$output" = "NONE" ]
}

@test "ABSTAINS one hour short of the speak window — the floor is a floor, not a rounding" {
  # 49h left = 119h elapsed = 70.8%, just under the 71.4% floor. Pairs with the CONTROL above:
  # together they pin the boundary to within an hour, so widening or narrowing it reds one of them.
  run_wp 60 49
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "burn ratio is 1.00x when consumption exactly tracks elapsed window" {
  # 42h left => 75% elapsed, 75% of the bucket spent => dead on pace. Inside the speak window.
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
  # This is the ONE phase where that warning survives the 2026-08-31 widening (day 6-7, where
  # linear and empirical converge to −17 and −2 pp).
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
