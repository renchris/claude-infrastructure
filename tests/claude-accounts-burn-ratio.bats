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
# THE FLOOR WIDENED FROM 0.05 TO 5/7 (weekly-reset-utilization-2026-08-25 §3/§6, backed by
# drain-telemetry-2026-08-25 axis-D §4-5). Dividing by elapsed fraction corrects PHASE only under
# an assumption of linear burn, and burn is back-loaded 2.3x in the last 30% of the window, so the
# shape error survived underneath the phase fix: backtested MAE is 46.2 pp at mid-week against
# 5.3 pp for a constant predictor that ignores the reading. The mid-week projection was therefore
# 8.7x worse than answering "94" — so it is now silent there, and speaks only inside the last 48 h.
# The arithmetic below the floor is UNCHANGED; only where it is published moved. Cases are sited
# accordingly: the ratio cases now use fixtures inside the speaking window, and the mid-week cases
# pin the silence with the SAME readings that used to render.

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
  # Inside the last 48h (47h left = 72.0% elapsed), above the 5/7 floor.
  run_wp 50 47
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
}

@test "burn ratio is 1.00x when consumption exactly tracks elapsed window" {
  # 42h left = 75% elapsed, 75% of the bucket spent => dead on pace
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
  # 90% spent at 75% elapsed projects to 120%: the account hits its limit early and is DOWN
  run_wp 90 42
  [ "$status" -eq 0 ]
  proj="$(printf '%s' "$output" | awk '{print $2}')"
  [ "$(python3 -c "print(1 if $proj >= 100 else 0)")" -eq 1 ]
}

@test "ABSTAINS mid-week — the 46pp error class the widened floor exists for" {
  # THE DEFECT, VERBATIM FROM THE BACKTEST (weekly-reset-utilization-2026-08-25 §3). Each of
  # these four is a real window read at day 3 (120h left), with what it ACTUALLY closed at.
  # Under the old 0.05 floor every one of them rendered a number, and every number was wrong by
  # 20-70 pp. Rendering nothing is not a degradation here — it is 8.7x more accurate than the
  # figure it replaces, measured against a constant predictor at 5.3 pp MAE.
  run_wp 12 120; [ "$output" = "NONE" ]   # projected 28%, closed 98%  -> was -70 pp
  run_wp 17 120; [ "$output" = "NONE" ]   # projected 40%, closed 100% -> was -60 pp
  run_wp 25 120; [ "$output" = "NONE" ]   # projected 58%, closed 92%  -> was -34 pp
  run_wp 51 120; [ "$output" = "NONE" ]   # projected 119% WALL, closed 99% -> a wall that never came
}

@test "ABSTAINS at the halfway mark, where a phase-only correction reads as if it worked" {
  # 84h left = phase 0.50, the old suite's own fixture for '1.00x, dead on pace'. It renders a
  # perfectly self-consistent 1.00x/100% and its backtested MAE there is 46.2 pp. This is the
  # case that makes the widening a CORRECTION rather than a tightening of an edge guard: the
  # reading is not noisy, it is confidently uninformative.
  run_wp 50 84
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "the floor sits at 5/7 — speaks at exactly 48h left, silent at 49h" {
  # BOTH SIDES, one hour apart, so the floor is pinned to its value and not merely to 'wider'.
  # 48h left is 120/168 elapsed, exactly 5/7, and the comparison is `<` so the boundary SPEAKS.
  run_wp 80 48
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
  run_wp 80 49
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "the arithmetic below the floor is unchanged — only its publication moved" {
  # MUTANT GUARD. An abstain-only suite passes against a wall_projection that returns
  # (None, None) unconditionally, which would silently kill the last-48h surface too. Drop the
  # floor to 0 in a copy of the subject and the OLD mid-week values must come back exactly.
  cp "$SUT" "$BATS_TEST_TMPDIR/unfloored"
  python3 - "$BATS_TEST_TMPDIR/unfloored" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = "MIN_ELAPSED_FRAC = 5.0 / 7.0"
assert old in s, "floor constant moved; update this mutant guard"
open(p, "w").write(s.replace(old, "MIN_ELAPSED_FRAC = 0.0", 1))
PY
  real="$SUT"
  SUT="$BATS_TEST_TMPDIR/unfloored"
  run_wp 50 84
  SUT="$real"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qE '^1\.0000 100\.00$'
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
