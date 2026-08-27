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
# THE FLOOR MOVED, 0.05 -> 0.90, AND THE CASES BELOW MOVED WITH IT (weekly-reset-utilization
# -2026-08-25 §3/§6; drain-telemetry-2026-08-25/axis-D-windows §5, SYNTHESIS-design §1.5). The
# 0.05 floor answered an ARITHMETIC objection. The measurement that came after it refutes the
# model underneath: dividing by elapsed fraction corrects for phase only if burn is LINEAR, and
# on this fleet it is heavily back-loaded — median 0.49x at day 3, not ~1.0. Backtested at day 3
# against the 8 completed windows this function errs by a mean 46 pp (-70 / -60 / -34 / +20),
# and by phase decile its MAE runs 47.2 / 46.9 / 46.2 / 36.7 / 18.3 against a CONSTANT
# predictor's 5.3. Mid-window it is 8.7x worse than the number 94, so the honest output there is
# no number at all.
#
# Cases 3-5 therefore assert ABSENCE where they used to assert a value, and each is paired with
# a late-phase CONTROL on the same shape — an abstain-everywhere stub passes the absence arms
# and fails every control. Case 2 is retargeted from the old floor to the new one.
#
# What is NOT weakened: the mid-week weekly signal. `wk_strand_pp` / `wk_wall_traj` (the 48 h
# roll-aware nowcast) speak at every phase, and `pace_line`'s ⚠ WALL flag was re-sourced onto
# them in the same change — pinned in tests/claude-accounts-strand.bats RP-16 and in
# claude-accounts-core.bats' weekly-drain case, both of which hold at phase 0.32.

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
  # RETARGETED from the 0.05 floor to the 0.90 one. This case used to sit at 24h elapsed
  # (phase 0.143) — inside the region the backtest since measured at a 46 pp error. 8h left of
  # 168 is phase 0.952, so the projector speaks: 95 / 0.952 = 99.75%.
  run_wp 95 8
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
}

@test "ABSTAINS mid-week, where the linear model is refuted (the 46pp error class)" {
  # Dead centre of the window: 84h left = phase 0.500. The old floor let this through and it
  # rendered `1.00× burn / 100% by reset` — a figure whose measured MAE at this decile is
  # 46.2 pp, against 5.3 pp for a constant predictor that reads no meter at all. Two windows
  # sat at 12% and 17% on day 3 and closed at 98% and 100%.
  run_wp 50 84
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "ABSTAINS on the under-use reading — the inversion that started this metric, mid-week" {
  # 25% at the halfway mark used to render `0.50× burn / 50% by reset`, which reads as gross
  # under-utilisation and is the exact premise §1 of USAGE_TELEMETRY_100P retracts. The
  # empirical median at day 3 IS 0.49×, and those windows finished at 92-100%.
  run_wp 25 84
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "ABSTAINS on a mid-week WALL — the false alarm it actually fired (119% projected, 99% actual)" {
  # 75% at the halfway mark projects to 150% and would flag ⚠ WALL. The live instance of this
  # class is next@08-23: 51% at day 3 -> 119% ⚠ WALL, and the window closed at 99%.
  # The WALL warning is not lost, it is re-sourced — pace_line reads wk_wall_traj (the 48h
  # nowcast), pinned at phase 0.32 by claude-accounts-strand.bats RP-16.
  run_wp 75 84
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "CONTROL: past the floor it still renders the RATIO and the >100 projection" {
  # The arm that stops the three abstains above from being satisfied by an always-None stub, and
  # pins the arithmetic itself as unchanged — only the window it speaks in moved.
  # 8h left = phase 0.952: 100 -> 1.0500 / 105.00, and 90 -> 0.9450 / 94.50.
  run_wp 100 8
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qE '^1\.0500 105\.00$'
  proj="$(printf '%s' "$output" | awk '{print $2}')"
  [ "$(python3 -c "print(1 if $proj >= 100 else 0)")" -eq 1 ]
  run_wp 90 8
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qE '^0\.9450 94\.50$'
}

@test "the floor is 0.90, and it is pinned as a VALUE — a drift back to 0.05 is the regression" {
  # The abstains above are all satisfied by any floor >= 0.5, so they cannot tell 0.90 from 0.60
  # and cannot catch a silent widening either. The threshold is a measured quantity (the decile
  # at which both backtests agree the error has fallen off: day 6 -17 pp, day 7 -2 pp — still
  # 18.3 MAE against a constant predictor's 5.3, so this is a threshold, not a warrant), so it is
  # BRACKETED as one — a pair one hour apart that admits 0.90 and no other round value:
  #   16h left = phase 0.90476 must SPEAK   (refutes any floor above it, e.g. 0.95)
  #   17h left = phase 0.89881 must ABSTAIN (refutes any floor below it, e.g. 0.85)
  # A bracket rather than the exact 16.8h boundary on purpose: 168 - 16.8 is 151.19999999999999
  # in binary float, so the boundary case tests the FPU, not the policy.
  run_wp 50 16
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
  run_wp 50 17
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
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
