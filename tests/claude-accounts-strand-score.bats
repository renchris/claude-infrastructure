#!/usr/bin/env bats
# strand_score / --strand-score — the instrument that CAN FAIL. USAGE_TELEMETRY_100P §5.2 S5
# (M3c), RED-proof cases RP-29..RP-33.
#
# WHY THIS EXISTS, AND WHY IT IS THE PREREQUISITE FOR S6. The synthesis published
# `4/4 recall · 0 FP · median ~20 h lead` for the strand arithmetic. That score evaluated the
# projection at the horizon's CLOSE, where it has already converged to `100 - weekly_pct`, i.e.
# to the true strand — so it agreed with the IDENTITY FUNCTION on 8/8 windows. A harness whose
# every cell must read 0.0 measures nothing; it is the vacuous pass in its purest form
# (`control-must-replay-the-real-artifact.md`, `verification-harness-vacuous-pass-traps.md`).
#
# THIS harness scores each completed window at FIXED DISTANCES from its reset — 96/48/24/12/6 h —
# where the projection can be, and demonstrably is, wrong. RP-30 is the case that proves the
# instrument has that property: on a window that burns steadily and then STOPS, the 24 h cell must
# be off by ~14 pp while the 6 h cell has converged. A harness that cannot produce that spread is
# the tautology again under a new name, and S6 must not be built on it.
#
# CAUSALITY IS THE IMPLEMENTATION TRAP. `burn_wk_ewma_ph` filters its own 48 h lookback but does
# NOT drop samples AFTER `now` — it has never had to, because every other caller passes wall-clock
# time. Replaying history is the first caller for which "after now" is a real set, and feeding it
# the whole series lets each cell see the future it is supposed to be predicting. RP-30 pins the
# 24 h projection at the value only pre-instant data can produce.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; samples passed explicitly except
# in RP-33, which is the CLI case and drives CC_UTIL_LOG.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
}

LOAD='
import importlib.machinery, importlib.util, json, os, sys, time
from datetime import datetime, timezone
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
NOW = time.time()
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def window(acct="next3", reset_ago_h=1.0, span_h=120.0, rate=0.6, flat_from_h=24.0,
           tail_h=0.5, step_h=0.25):
    """One CLOSED weekly window: the meter climbs at `rate` %/h and then goes FLAT for the last
    `flat_from_h` hours. The flat tail is the whole point -- it is what makes the far horizons
    over-predict and the near ones converge, i.e. what gives the harness something to be wrong
    about. reset_t is snapped to a whole minute so _reset_key round-trips it exactly."""
    reset_t = round((NOW - reset_ago_h * 3600.0) / 60.0) * 60.0
    wra = iso(reset_t)
    out, wp = [], 0.0
    t = reset_t - span_h * 3600.0
    while t <= reset_t - tail_h * 3600.0 + 1e-6:
        out.append({"acct": acct, "_t": t, "weekly_pct": wp, "session_pct": 10,
                    "weekly_reset_at": wra, "session_reset_at": iso(t + 3 * 3600.0)})
        if (reset_t - t) / 3600.0 > flat_from_h:
            wp += rate * step_h
        t += step_h * 3600.0
    return out, reset_t
'

@test "RP-29: strand_score scores a CLOSED window at fixed distances from its reset" {
  # The shape first: one completed account-week, one cell per horizon bucket, each taken at a
  # sample that was genuinely that far from the reset -- never at the close, which is where the
  # refuted score lived.
  run python3 -c "$LOAD"'
sam, reset_t = window()
sc = ca.strand_score(sam, now=NOW)
assert sc["n_windows"] == 1, sc
w = sc["windows"][0]
assert w["acct"] == "next3", w
assert abs(w["realised_pp"] - 42.4) < 0.3, w        # climbs to 57.6% and stops
byh = {b["h"]: b for b in sc["buckets"]}
assert sorted(byh) == [6.0, 12.0, 24.0, 48.0, 96.0], sorted(byh)
for h in (96.0, 48.0, 24.0, 12.0, 6.0):
    assert byh[h]["n"] == 1, (h, byh[h])
    cell = w["cells"][h]
    assert cell["at_reset_h"] >= h, (h, cell)       # evaluated AT OR BEFORE the horizon, never after
    assert cell["at_reset_h"] < h + 0.3, (h, cell)  # ...and at the LAST such sample, not the oldest
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-30: the harness CAN be wrong — far horizons miss by ~14pp, near ones have converged" {
  # THE ANTI-TAUTOLOGY CASE. The refuted score was the identity function on true strand; this one
  # has to be able to come out non-zero, and here it does, in the direction the plan predicts: a
  # window that burns steadily and then stops is OVER-predicted early (the pace it extrapolates
  # is real at that instant and does not last) and converges as the horizon closes.
  #
  # ...which is also the CAUSALITY assertion. At T-24h only the climbing segment exists, so the
  # projection is 100 - (57.6 + 0.6*24) = 28.0. An implementation that hands burn_wk_ewma_ph the
  # WHOLE series lets that cell see the flat tail it is supposed to be predicting, the EWMA
  # collapses toward 0 and the cell reads ~41.5 -- indistinguishable from a good forecast, and
  # entirely an artifact of the leak.
  run python3 -c "$LOAD"'
sam, reset_t = window()
sc = ca.strand_score(sam, now=NOW)
byh = {b["h"]: b for b in sc["buckets"]}
w = sc["windows"][0]
assert abs(w["cells"][24.0]["projected_pp"] - 28.0) < 0.6, w["cells"][24.0]
assert w["cells"][24.0]["projected_pp"] < 35.0, "the future leaked into the 24h cell"
for h in (96.0, 48.0, 24.0):
    assert byh[h]["bias"] < -10.0, (h, byh[h])      # over-predicted the burn => under-predicted strand
    assert byh[h]["mae"] > 10.0, (h, byh[h])
assert abs(byh[6.0]["bias"]) < 3.0, byh[6.0]        # converged
assert byh[12.0]["mae"] < byh[24.0]["mae"], byh     # MONOTONE toward the reset: the estimators
assert byh[6.0]["mae"] < byh[24.0]["mae"], byh      # own claim, now measured rather than asserted
# sign agreement is about WHETHER there is a strand, not how big: both sides say yes here
assert byh[24.0]["agree"] == 1 and byh[24.0]["agree_rate"] == 1.0, byh[24.0]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31 CONTROL: a window that holds its pace is scored NEAR ZERO at every horizon" {
  # Without this arm RP-30 is satisfied by a harness that reports a large error unconditionally --
  # a broken instrument reads "the projector is bad" on every input, which is the same failure as
  # a vacuous one reading "perfect" on every input, in the other direction. A steady window is
  # exactly what the arithmetic CAN nowcast, so it must score small.
  run python3 -c "$LOAD"'
sam, reset_t = window(rate=0.6, flat_from_h=0.0)     # no flat tail: 0.6 %/h the whole way
sc = ca.strand_score(sam, now=NOW)
byh = {b["h"]: b for b in sc["buckets"]}
assert sc["n_windows"] == 1, sc
for h in (96.0, 48.0, 24.0, 12.0, 6.0):
    assert byh[h]["n"] == 1, (h, byh[h])
    assert abs(byh[h]["bias"]) < 2.0, (h, byh[h])
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32 CONTROL: an unevaluable cell is n=0 and EXCLUDED, never imputed as a hit" {
  # L2, and the aggregate is where it bites. A (window, horizon) cell with no evaluable sample at
  # weekly_reset_h >= H has no evidence; counting it as agreement inflates the sign-agreement rate
  # with cells that were never scored, and counting its error as 0.0 pulls the bias toward
  # "unbiased" with rows that measured nothing. bias/mae must be None on such a bucket -- not 0.0,
  # which is a VALUE and reads as a measurement.
  run python3 -c "$LOAD"'
sam, reset_t = window(span_h=40.0, flat_from_h=24.0)   # the series never reaches T-48h at all
sc = ca.strand_score(sam, now=NOW)
byh = {b["h"]: b for b in sc["buckets"]}
for h in (96.0, 48.0):
    assert byh[h]["n"] == 0, (h, byh[h])
    assert byh[h]["bias"] is None and byh[h]["mae"] is None, (h, byh[h])
    assert byh[h]["agree_rate"] is None, (h, byh[h])
for h in (24.0, 12.0, 6.0):
    assert byh[h]["n"] == 1, (h, byh[h])
    assert byh[h]["bias"] is not None, (h, byh[h])
# ...and a LIVE window is not scorable at all: its strand is not realised yet. completed_weekly_
# windows already refuses it (S1d), and the harness inherits that refusal rather than re-deciding.
live, _ = window(reset_ago_h=-50.0, span_h=40.0)
assert ca.strand_score(live, now=NOW)["n_windows"] == 0
assert ca.strand_score([], now=NOW)["n_windows"] == 0
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33: --strand-score answers with no config, no keychain and no sweep, and abstains loudly" {
  # Placed BEFORE load_cfg() in main(), exactly like --agents, and for the same reason that branch
  # records: a question about the SERIES must not require a Claude accounts.json to exist, must not
  # block behind a 4-account sweep, and must not force one. $HOME here is an empty fixture and the
  # usage endpoint is unreachable; if the branch sat after load_cfg() this would exit non-zero.
  python3 -c '
import json, os, time
from datetime import datetime, timezone
def iso(t): return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
NOW = time.time()
reset_t = round((NOW - 3600.0) / 60.0) * 60.0
wp, t, rows = 0.0, reset_t - 120 * 3600.0, []
while t <= reset_t - 1800.0 + 1e-6:
    rows.append({"ts": iso(t), "acct": "next3", "weekly_pct": wp, "session_pct": 10,
                 "weekly_reset_at": iso(reset_t), "session_reset_at": iso(t + 3 * 3600.0)})
    if (reset_t - t) / 3600.0 > 24.0:
        wp += 0.15
    t += 900.0
open(os.environ["CC_UTIL_LOG"], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
'
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  [[ "$output" == *"strand-score"* ]] || { echo "$output"; false; }
  [[ "$output" == *"96h"* && "$output" == *"6h"* ]] || { echo "$output"; false; }
  [[ "$output" == *"bias"* && "$output" == *"MAE"* ]] || { echo "$output"; false; }
  # ACCEPTANCE §5.4 item 2 in miniature: the near buckets must carry a non-zero n, or the table is
  # the tautology wearing a new layout.
  [[ "$output" == *"1 completed"* || "$output" == *"windows scored: 1"* ]] || { echo "$output"; false; }

  # CONTROL: an empty series says so. A table of zeros over no windows is a rendered measurement
  # of nothing, which is the exact shape L2 forbids.
  : > "$CC_UTIL_LOG"
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  [[ "$output" == *"no completed weekly window"* ]] || { echo "$output"; false; }
  [[ "$output" != *"bias"* ]] || { echo "$output"; false; }
}
