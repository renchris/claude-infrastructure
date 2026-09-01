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
# THE FLOOR MOVED 2026-09-01: 0.05 (~8.4 h elapsed) -> 6/7 (the day-6 mark, ~24 h left). The old
# floor guarded the ARITHMETIC near zero elapsed and said nothing about whether the LINEAR divisor
# above it is true — and it is not. Weekly burn accelerates 2.3x in the last 30% of the window, so
# backtesting this function at day 3 gives a mean absolute error of 46 pp (12% projected to 28%
# against a 98% actual; 51% projected to 119% "⚠ WALL" against a 99% actual), still 35 pp at day 5,
# and a CONSTANT predictor of ~94 beats it 8.7x mid-week. Convergence arrives only at the end
# (day 6: -17 pp; day 7: -2 pp). The in-range cases below therefore MOVED — the same assertions
# re-sited above the new floor, invariant unchanged — and the mid-week silence the widening exists
# to produce gets cases of its own (the four backtested day-3 windows, verbatim).
# Evidence: docs/research/weekly-reset-utilization-2026-08-25.md §3/§6 and
# docs/research/drain-telemetry-2026-08-25/axis-D-windows.md §4a/§5.

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
  # RE-SITED ABOVE THE NEW FLOOR (was 10/144, one day in — which the widened floor now silences,
  # correctly). 20h left = 148h elapsed of 168 = 88.1%, past the day-6 mark.
  run_wp 10 20
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
}

@test "ABSTAINS across the whole mid-week regime — the 46pp error class" {
  # The four windows backtested in weekly-reset-utilization-2026-08-25 §3, at day 3 (96h left),
  # with what the LINEAR projection said and what the window actually closed at:
  #   12% -> 28% (actual 98)   17% -> 40% (actual 100)
  #   25% -> 58% (actual 92)   51% -> 119% ⚠WALL (actual 99)
  # Mean absolute error 46 pp, in BOTH directions. Every one of them must now be silent.
  for pct in 12 17 25 51; do
    run_wp "$pct" 96
    [ "$status" -eq 0 ]
    [ "$output" = "NONE" ]
  done
}

@test "ABSTAINS at day 5 too — 'nearly there' is still 35pp wrong" {
  # 48h left = day 5. The error is smaller than at day 3 and still an order of magnitude worse
  # than the constant predictor's 5.3 pp, so the floor sits ABOVE this point, not at it.
  run_wp 47 48
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "the floor is the DAY-6 MARK: silent at 25h left, speaking at 24h" {
  # The tight boundary pair. It fixes WHERE the floor is, not merely that one exists — the old
  # 0.05 floor passes every other case in this file while speaking through all of mid-week.
  run_wp 60 25
  [ "$output" = "NONE" ]
  run_wp 60 24
  [ "$output" != "NONE" ]
}

@test "burn ratio is 1.00x when consumption exactly tracks elapsed window" {
  # RE-SITED (was 50/84, the halfway mark). At the floor itself — 24h left, 6/7 elapsed —
  # 85.714% spent is dead on pace to land at exactly 100.
  run_wp 85.7142857143 24
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qE '^1\.0000 100\.00$'
}

@test "burn ratio is 0.50x when half on pace — the under-use signal" {
  # RE-SITED (was 25/84). Half of 85.714% at the same phase — half pace, projecting to 50%.
  run_wp 42.8571428571 24
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qE '^0\.5000 50\.00$'
}

@test "projects PAST 100 when over pace — the wall the alarm exists for" {
  # RE-SITED (was 75/84). 95% spent with 24h left projects to ~110.8%: the account hits its
  # limit before reset and is DOWN until then. This is the regime the widened floor PRESERVES —
  # at day 6 the linear model has converged (-17 pp) and the flag is worth raising again.
  run_wp 95 24
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
