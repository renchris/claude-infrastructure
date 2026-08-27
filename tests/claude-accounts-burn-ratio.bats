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
# THE FLOOR IS NOW THE LAST 48 h, not 8.4 h (weekly-reset-utilization-2026-08-25 §3, §6). The 0.05
# floor removed the PHASE error and left the SHAPE error underneath it: dividing by elapsed
# fraction is only a correction if burn is linear, and over 8 completed weekly windows it is
# heavily back-loaded (empirical median 0.49× at day 3 where linear says 1.00×). Backtested, the
# projection erred by a mean 46 pp at day 3 and 35 pp at day 5, and the single ⚠ WALL it raised
# mid-week was a false alarm (119% projected, 99% actual). Cases 1-4 pin the floor: below it on
# BOTH the phase side and the newly-covered mid-week side, and above it on both sides of the
# 48 h boundary. Every arithmetic case therefore runs inside the converged tail.

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
  # 1% used, 167h left => 0.6% elapsed. An un-floored projection would read ~168% and page.
  # The honest answer is 'too early to say'.
  run_wp 1 167
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "ABSTAINS mid-week, where the linear divisor errs by a mean 46pp" {
  # THE REGRESSION CASE for the widened floor. next3's window on 2026-08-18 read 12% at day 3
  # (96h left): the shipped projection said 0.28x / 28% and the window CLOSED AT 98% — a 70 pp
  # miss, the largest of four backtested. Day 3 is 43% elapsed, far above the old 0.05 floor, so
  # this case is RED against it: the phase floor let every one of those four misses through.
  run_wp 12 96
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
  # ...and it is not a mid-week quirk of a low reading. next@08-23 sat at 51% on day 3 and the
  # same arithmetic raised a WALL at 119% against an actual close of 99%. Silence there too.
  run_wp 51 96
  [ "$output" = "NONE" ]
}

@test "ABSTAINS at 49h left and SPEAKS at 48h — the floor is the last 2 days, exactly" {
  # The two sides of CONVERGED_REMAIN_H. Below the boundary the empirical shortfall is still
  # -24 pp (day 5); the last 48 h is where linear and empirical converge (-17 pp at day 6,
  # -2 pp at day 7). A one-hour step across the boundary is the whole assertion.
  run_wp 50 49
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
  run_wp 50 48
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
}

@test "CONTROL: projects inside the converged tail, so the abstains above are the floor not a stub" {
  # 42h left = 75% elapsed, inside the last 2 days.
  run_wp 60 42
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
}

@test "burn ratio is 1.00x when consumption exactly tracks elapsed window" {
  # 42h left => 75% elapsed, 75% of the bucket spent => dead on pace
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
  # Inside the tail this is the projection's honest regime — it is the SAME arithmetic that
  # was suppressed mid-week above, and the difference is only where in the window it speaks.
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
