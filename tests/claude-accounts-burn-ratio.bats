#!/usr/bin/env bats
# wall_projection() — the window-PHASE view of the weekly bucket (USAGE_TELEMETRY_100P §1, §3.2).
#
# A point-in-time percentage against a periodically resetting counter is dominated by where you
# are in the window, not by how you are using it. On 2026-08-16 the readout showed three accounts
# at 1-3% weekly with every `pace to 100%` line reading BEHIND; the previous complete windows had
# closed at 91/92/100/85%. The low readings were three windows that had just RESET. Every figure
# was correct and its obvious interpretation was inverted.
#
# The abstain window is the load-bearing case, not a nicety, and it is TWO-SIDED.
#
# Side 1 — TOO EARLY. At 1 h elapsed a 1% reading projects to 168%, so an un-floored projection
# pages on every fresh window, manufacturing exactly the false alarm the metric exists to remove.
#
# Side 2 — MID-WINDOW, added after the linear divisor was backtested against what actually
# happened (`docs/research/weekly-reset-utilization-2026-08-25.md` §3). Dividing by elapsed
# fraction corrects PHASE only if burn is linear, and it is heavily back-loaded: the empirical
# median reads 0.49× at day 3, not the ~1.0 the original derivation asserted, and this function's
# own day-3 projections erred by a MEAN 46 pp — under-projecting three accounts that closed at
# 92-100%, and raising a ⚠ WALL at 119% on one that closed at 99%. So the projection speaks only
# in the last ~2 days, where linear and empirical converge (day 6: −17 pp; day 7: −2 pp).
#
# Cases 1-2 pin the early side; cases 3-5 pin the mid-window side (including the false WALL, which
# is the arm that fires an alarm rather than suppressing one); cases 6-9 pin the arithmetic inside
# the window where the function is allowed to speak.

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

@test "ABSTAINS one day in, where the phase fix used to speak and the shape error is opening" {
  # 24h elapsed of 168 = 14.3%, clear of the old 5% floor — this case PASSED before the
  # back-loading backtest and now must not. Day 1 is where the linear model is least wrong
  # (−7 pp) and it is already wrong; the gap peaks at day 4 (−27 pp).
  run_wp 10 144
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "ABSTAINS mid-window on the under-projection that closed 86 pp higher" {
  # next3@08-18, replayed: 12% at day 3 (72h left). The linear divisor said 28% by reset.
  # It closed at 98%. A 0.28x 'far behind' reading is the exact inversion this metric exists
  # to prevent, arriving through the correction that was supposed to prevent it.
  run_wp 12 72
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "ABSTAINS mid-window on the ⚠ WALL that never arrived — the alarm-raising arm" {
  # next@08-23, replayed: 51% at day 3 (72h left) => 1.19x, projecting 119%, which pace_line
  # renders as '⚠ WALL trajectory'. The window closed at 99%. Suppressing a false alarm is a
  # weaker claim than suppressing a false all-clear, so this arm is pinned separately: the
  # mid-window abstain has to hold in BOTH directions or it is just a polarity change.
  run_wp 51 72
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "the abstain releases exactly at the last 2 days, and not one hour earlier" {
  # 48h left is the first hour the projection may speak; 48.5h left is still silent. Without
  # both arms the boundary could sit anywhere in the week and every case above would still pass.
  run_wp 75 48
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
  run_wp 75 48.5
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "burn ratio is 1.00x when consumption exactly tracks elapsed window" {
  # 42h left => 126h of 168 elapsed = 0.75 of the window, three quarters of the bucket spent
  # => dead on pace. (Inputs moved inside the speaking window; the arithmetic is unchanged.)
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
  # 90% spent at 0.75 of the window projects to 120%: the account hits its limit early and is
  # DOWN until reset. Inside the last 2 days this is the reading the ⚠ WALL flag is for, and
  # it is the reading the day-6/day-7 convergence (−17 pp, −2 pp) makes safe to act on.
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
