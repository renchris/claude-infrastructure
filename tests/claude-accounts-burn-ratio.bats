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
# THE FLOOR MOVED 0.05 -> 0.90 ON 2026-08-25, and the cases below moved with it. Dividing by
# elapsed fraction corrects for PHASE only if burn is LINEAR, and it is not: phase 0.0-0.7 burns
# 10.9 weekly-pp/day against 25.2 in phase 0.7-1.0, and this projector's backtested MAE runs
# 47.2 / 46.9 / 46.2 / 36.7 / 18.3 pp at phase 0.1 / 0.3 / 0.5 / 0.7 / 0.9 — against 5.3 pp for
# the constant predictor "94" at mid-week. So the old floor let the renderer speak for ~95% of
# every week in the regime where it is 8.7x worse than a constant. The arithmetic cases are
# therefore re-anchored past the new floor (phase 0.95, i.e. 8.4 h left) — the INVARIANTS they
# pin are unchanged, only the phase they are evaluated at. Two new cases pin the widening
# itself, and one of those pins 0.90 rather than the weaker 0.714 that a sibling doc prescribes.
# Sources: docs/research/drain-telemetry-2026-08-25/axis-D-windows.md §4-§5 + SYNTHESIS §1.5;
# docs/research/weekly-reset-utilization-2026-08-25.md §3, §6.

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

@test "ABSTAINS at mid-week, where the linear model is refuted (the 46 pp class)" {
  # Phase 0.50 — 84h elapsed of 168. The projector's backtested MAE here is 46.2 pp, against
  # 5.3 pp for a constant predictor: four windows sat at 61, 31, 20 and 13% at exactly this
  # phase and ALL FOUR closed at 92-100%. This reading is the item's whole subject, and under
  # the old 0.05 floor it rendered `0.50x burn` as though it meant something.
  run_wp 50 84
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "ABSTAINS with 1.75 d left — the floor is 0.90, NOT the weaker 'last ~2 days' (0.714)" {
  # weekly-reset-utilization §6 prescribes "the last ~2 days" (phase 0.714), but its own §3
  # backtest still reads 35 pp of error at day 5 and cites day 6 (-17 pp) / day 7 (-2 pp) as the
  # convergent region; the drain-telemetry wave resolved the same question at 0.90 on more data.
  # This case is the mutant-proof against relaxing the floor back to the doc's literal wording.
  run_wp 50 42
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "CONTROL: projects once past the floor, so the abstains above are the floor and not a stub" {
  # Phase 0.905 — 16h left of the window. First side of the floor that speaks.
  run_wp 90 16
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
  # 99% spent with 5% of the window still to run projects to 104%: the account hits its limit
  # before the reset and is DOWN until it.
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
