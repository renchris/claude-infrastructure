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
# THE FLOOR MOVED, AND THE FIXTURES MOVED WITH IT (weekly-reset-utilization-2026-08-25 §3, §6).
# The original floor was `MIN_ELAPSED_FRAC = 0.05` — it excluded only the regime where the
# arithmetic is noise. But dividing by elapsed fraction corrects the PHASE error only if burn is
# LINEAR, and fleet burn is heavily back-loaded: backtested at day 3 the projection erred by a
# mean 46 pp, still 35 pp at day 5, converging only in the last ~2 days. The floor is now
# `PROJ_SPEAK_REMAIN_H = 48.0` hours REMAINING, so the arithmetic cases below are re-anchored at
# 42 h left — inside the window where the projection is worth reading — and the invariant they
# pin (the ratio's arithmetic, and >100 flagged rather than printed) is unchanged. Cases 9-12
# pin the new floor itself: silent where the linear model is refuted, on both sides of the
# boundary, and saying WHY rather than going quiet.

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

# apply_burn(rows, cfg, samples) over ONE synthetic row -> the projection keys it stamped.
# Goes through apply_burn rather than wall_projection because the abstain REASON is attached
# there, beside the other burn facts, and a stamp asserted anywhere else is not the one shipped.
# `samples` must be non-empty: apply_burn returns early on an empty series, which would make
# every arm below pass vacuously.
stamp() {
  SUT="$SUT" WP_PCT="$1" WP_H="$2" python3 <<'PY'
import importlib.machinery, importlib.util, os, sys, time
sys.argv = ["claude-accounts"]
path = os.environ["SUT"]
loader = importlib.machinery.SourceFileLoader("ca", path)
spec = importlib.util.spec_from_loader("ca", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
row = {"acct": "t", "weekly_pct": float(os.environ["WP_PCT"]),
       "weekly_reset_h": float(os.environ["WP_H"])}
m.apply_burn([row], {}, samples=[{"acct": "t", "_t": time.time(),
                                  "weekly_pct": float(os.environ["WP_PCT"])}])
out = []
for k in ("burn_ratio", "proj_end_pct", "wall_risk"):
    if k in row:
        out.append(f"{k}={row[k]:.4f}" if isinstance(row[k], float) else f"{k}={row[k]}")
if "burn_ratio_abstain" in row:
    out.append("ABSTAIN " + row["burn_ratio_abstain"])
print(" | ".join(out) if out else "EMPTY")
PY
}

@test "ABSTAINS on a barely-started window (the 168% false-alarm class)" {
  # 1% used, 167h left => 0.6% elapsed, well under the 5% floor. An un-floored projection
  # would read ~168% and page. The honest answer is 'too early to say'.
  run_wp 1 167
  [ "$status" -eq 0 ]
  [ "$output" = "NONE" ]
}

@test "CONTROL: projects once inside the speaking window, so the abstain is a floor not a stub" {
  # Same account with 42h left: 126h elapsed of 168 = 75%, inside the last 2 days.
  run_wp 10 42
  [ "$status" -eq 0 ]
  [ "$output" != "NONE" ]
}

@test "burn ratio is 1.00x when consumption exactly tracks elapsed window" {
  # 42h left => 75% elapsed; 75% of the bucket spent => dead on pace
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

@test "ABSTAINS mid-week on the three windows the linear model got wrong by 46pp" {
  # The backtest that motivated the wider floor (weekly-reset-utilization-2026-08-25 §3), read at
  # day 3 => 96h left. Each row is `weekly_pct at day 3` and what the window ACTUALLY closed at:
  #
  #   next3@08-18  12%  ->  old projection 28%   actual 98%   error -70pp
  #   next2@08-22  17%  ->  old projection 40%   actual 100%  error -60pp
  #   next4@08-23  25%  ->  old projection 58%   actual 92%   error -34pp
  #
  # Every one of these passed the OLD 5%-elapsed floor (day 3 is 43% elapsed) and published a
  # number that was wrong by more than half the bucket. Silence is the honest answer here.
  for pct in 12 17 25; do
    run_wp "$pct" 96
    [ "$status" -eq 0 ]
    [ "$output" = "NONE" ]
  done
  # ...and the over-projection of the same class: 51% at day 3 read `119% ⚠ WALL` and closed 99%.
  run_wp 51 96
  [ "$output" = "NONE" ]
}

@test "the floor is at 48h REMAINING — speaks at the boundary, silent one step outside it" {
  # Pins the constant's VALUE, its DIRECTION, and its INCLUSIVITY. A mutant that flips the
  # comparison, or that keeps an elapsed-FRACTION floor of any size, fails one of these arms:
  # an elapsed-fraction floor low enough to admit 48.0h left also admits 48.1h.
  run_wp 60 48.0
  [ "$output" != "NONE" ]
  run_wp 60 48.1
  [ "$output" = "NONE" ]
  # and it is a floor on the WINDOW, not on the reading: the same silence at a high pct
  run_wp 95 96
  [ "$output" = "NONE" ]
}

@test "the mid-window abstain STAMPS ITS REASON — absence must read as refusal, not outage" {
  # The projection is now silent 5 days in 7, so absence is the NORMAL state. A null that cannot
  # say why reads as a missing measurement (the same argument that makes burn_wk_ewma_ph stamp
  # its span). Asserts the three projection keys are ABSENT and the reason key is present.
  run stamp 12 96
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'ABSTAIN'
  printf '%s' "$output" | grep -q 'mid-window (4.0d left)'
  ! printf '%s' "$output" | grep -q 'burn_ratio=' || false
}

@test "CONTROL: no abstain reason is stamped when the projection SPEAKS" {
  # Without this the case above passes against an unconditional stamp, which would assert a
  # refusal over a live number.
  run stamp 75 42
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'burn_ratio=1.0000'
  ! printf '%s' "$output" | grep -q 'ABSTAIN' || false
}
