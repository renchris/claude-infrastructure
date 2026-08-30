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
# THE FLOOR IS 0.90, WIDENED FROM 0.05 (2026-08-30). Dividing by elapsed fraction corrects the
# PHASE error only under an assumption of LINEAR burn, and burn on this fleet is heavily
# back-loaded (2.3× acceleration in the last 30% of the window), so the SHAPE error survived
# underneath the phase fix. Backtested MAE of this function, n=8 completed windows, LOO
# (docs/research/drain-telemetry-2026-08-25/axis-D-windows.md §5):
#
#     phase   0.1    0.3    0.5    0.7    0.9
#     MAE    47.2   46.9   46.2   36.7   18.3   pp        (a CONSTANT predictor scores 5.3)
#
# So the mid-week cases below are not "noisy input" cases — they pin that a projection which was
# CONFIDENTLY WRONG by 60-70 pp on three of four backtested windows now says nothing at all. The
# 0.05 floor is subsumed, so case 1 is unchanged and still passes.

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

# pace_line([one synthetic row]) -> the rendered block. Drives the RENDERER, not the estimator,
# because the `AT THE WALL` arm exists precisely to survive the estimator's abstention.
pl() {
  SUT="$SUT" python3 <<'PY'
import importlib.machinery, importlib.util, os, sys
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["SUT"])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(m)
print(m.pace_line([{"acct": "acctX",
                    "weekly_pct": float(os.environ["WP_PCT"]),
                    "weekly_reset_h": float(os.environ["WP_H"]),
                    "burn_wk_ewma_ph": float(os.environ["WP_EWMA"])}]))
PY
}

run_pl() { export WP_PCT="$1" WP_H="$2" WP_EWMA="$3"; run pl; }

@test "ABSTAINS on a barely-started window (the 168% false-alarm class)" {
  # 1% used, 167h left => 0.6% elapsed, well under the 5% floor. An un-floored projection
  # would read ~168% and page. The honest answer is 'too early to say'.
  run_wp 1 167
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "CONTROL: projects once past the floor, so the abstain above is the floor and not a stub" {
  # Deep in the window: 8.4h left of 168 = phase 0.95, above the 0.90 floor.
  run_wp 92 8.4
  [ "$status" -eq 0 ]
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
  # 99% spent at phase 0.95 projects past 100: the account hits its limit before reset and is DOWN
  run_wp 99 8.4
  [ "$status" -eq 0 ]
  proj="$(printf '%s' "$output" | awk '{print $2}')"
  [ "$(python3 -c "print(1 if $proj >= 100 else 0)")" -eq 1 ]
}

@test "ABSTAINS mid-week on the exact day-3 readings the shipped projection got wrong" {
  # The backtest that motivated the widening (weekly-reset-utilization-2026-08-25.md §3). Each of
  # these produced a CONFIDENT number under the 0.05 floor; each was wrong by 34-70 pp. Day 3 of
  # 7 => 96h left => phase 0.43.
  run_wp 12 96   # old: 0.28x, "28% by reset"  — the window actually closed at 98%
  [ "$output" = "NONE" ]
  run_wp 17 96   # old: 0.40x, "40% by reset"  — actually closed at 100%
  [ "$output" = "NONE" ]
  run_wp 25 96   # old: 0.58x, "58% by reset"  — actually closed at 92%
  [ "$output" = "NONE" ]
  run_wp 51 96   # old: 1.19x, "119% ⚠ WALL"   — actually closed at 99%, no wall ever arrived
  [ "$output" = "NONE" ]
}

@test "ABSTAINS at day 5 — the floor is the MAE table, not the 'last two days' reading" {
  # The narrative fix reads 'speak only in the last ~2 days'; the MAE table says phase 0.7 still
  # costs 36.7 pp against a 5.3 pp constant. This case pins that the code followed the measurement
  # and not the prose: 48h left = phase 0.714, and it stays silent.
  run_wp 47 48
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "the floor sits AT 0.90 — both sides, so it is a threshold and not a coincidence" {
  # Straddled at 0.3h, not asserted ON the boundary: phase 0.90 is 16.8h left, and 16.8 has no
  # exact binary representation, so (168-16.8)/168 lands at 0.8999999999999999 and the equality
  # case is a float coin-flip rather than a statement about the threshold.
  run_wp 90 16.7    # phase 0.9006 — speaks
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
  run_wp 90 17.0    # phase 0.8988, a fifth of an hour earlier — silent
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

@test "an account ALREADY at 100% reads as AT THE WALL mid-week, not 'on pace to fill'" {
  # THE REGRESSION THE WIDENING WOULD OTHERWISE INTRODUCE. next3 sat at exactly 100% for 11.2h on
  # 2026-08-11; such an account is DOWN until reset. Under the 0.05 floor the projected-WALL arm
  # caught it at any phase. Under 0.90 that arm is silent mid-week, so the renderer must state the
  # OBSERVED level instead — 100% is a reading, and a reading needs no phase gate.
  run_pl 100 60 0.0     # phase 0.64: wall_projection abstains here
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'AT THE WALL'
  ! printf '%s' "$output" | grep -q 'on pace to fill the window' || false
}

@test "CONTROL: mid-week BELOW the wall renders no wall at all — the false alarm stays dead" {
  # Same phase, the day-3 reading that projected 119% ⚠ WALL and actually closed at 99%. The
  # arm above must not have re-admitted it: no glyph, no ratio, no projection.
  run_pl 51 96 0.6
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'on pace to fill the window'
  ! printf '%s' "$output" | grep -q '⚠' || false
  ! printf '%s' "$output" | grep -qE '[0-9]\.[0-9][0-9]×' || false
}

@test "the derived fields are exported for machine consumers, not just rendered" {
  # the governed dispatcher routes on these; a renderer-only metric cannot be routed on
  grep -q 'r\["burn_ratio"\] = ratio' "$SUT"
  grep -q 'r\["proj_end_pct"\] = proj' "$SUT"
  grep -q 'r\["wall_risk"\] = proj >= 100.0' "$SUT"
}
