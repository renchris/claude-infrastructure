#!/usr/bin/env bats
# burn_5h_ewma_ph — S7 · M1, the roll-aware EWMA of the 5h session meter.
# USAGE_TELEMETRY_100P §5.2 S7, RED-proof cases RP-33..RP-37.
#
# 🚨 BOTH OF THIS METRIC'S HAZARDS PRODUCE A PLAUSIBLE WRONG NUMBER, WHICH IS WHY THE CASES
# BELOW ASSERT MAGNITUDE AND NOT ONLY PRESENCE.
#
#   1. THE UNIT. The formula emits %/h; `burn_5h_ph` is consumed by `_su_projected` as
#      fraction/h (`su + b * ahead`, su ∈ [0,1]). Shipped under the old key, or consumed without
#      the /100, the projection saturates to 1.0 on every row — a 100× error whose symptom is
#      "every account is under 5h pressure", i.e. a finding rather than a crash. RP-33/RP-34.
#   2. THE ROLL SPELLING. The roll test must be `_reset_key`'s ROUNDING (S1a). Under truncation
#      the roll branch fires on 46.0% of adjacent pairs and injects an absolute LEVEL where a
#      delta belongs; measured MAE degrades 0.0282 → 0.2110, 5.4× worse than the incumbent this
#      replaces. RP-35.
#
# It ships on AVAILABILITY and ROLL-AWARENESS, not accuracy — and its named blind spot is
# session_pct ≥ 40, the burst regime the weekly planner creates, where the incumbent is more
# accurate. That is in the docstring and RP-37 pins that the incumbent key survives beside it.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; samples passed explicitly.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
}

LOAD='
import importlib.machinery, importlib.util, os, sys, time
from datetime import datetime, timezone
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
NOW = time.time()
STEP_H = 0.1
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def series(hours, rate, acct="next3", reset_in_h=4.0, start_pct=0.0):
    """`hours` of samples at 6 min cadence ending NOW, session_pct accruing at `rate` %/h."""
    out, sp = [], start_pct
    n = int(round(hours / STEP_H))
    for i in range(n, -1, -1):
        out.append({"acct": acct, "session_pct": round(sp, 6), "weekly_pct": 30.0,
                    "_t": NOW - i * STEP_H * 3600.0,
                    "session_reset_at": iso(NOW + reset_in_h * 3600.0),
                    "weekly_reset_at": iso(NOW + 100 * 3600.0)})
        sp += rate * STEP_H
    return out
'

@test "RP-33: burn_5h_ewma_ph is %/h under its OWN key — not fraction/h, and not the old key" {
  # 6 h at 4.0 %/h. The value must read ~4, never ~0.04 (fraction/h wearing the new key's name)
  # and never ~400. The magnitude IS the assertion: presence alone cannot tell those apart.
  run python3 -c "$LOAD"'
sam = series(6.0, 4.0)
v, span = ca.burn_5h_ewma_ph(sam, NOW)
assert v is not None, (v, span)
assert 3.6 < v < 4.4, v
assert span >= 5.5, span
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-34: _su_projected divides by 100 — without it every account reads as 5h-saturated" {
  # THE MUTANT THIS KILLS is a one-character omission at the single consumer. At 4.0 %/h over a
  # 1 h lookahead the honest projection is 0.20 + 0.04 = 0.24. Consumed without the /100 it is
  # min(1.0, 0.20 + 4.0) = 1.0 — the row reads as a fully-spent 5h window, _soft's SF multiplier
  # collapses, and the router softens every account it can measure. It never raises an error.
  run python3 -c "$LOAD"'
R = {"PROJ_LOOKAHEAD_H": 1.0}
r = {"acct": "next3", "session_pct": 20, "session_reset_h": 4.0, "burn_5h_ewma_ph": 4.0}
p = ca._su_projected(r, R)
assert 0.22 < p < 0.26, p
assert p < 0.5, "saturated — the /100 is missing at the consumer"
# CONTROL 1: the incumbent key is still honoured, in ITS unit (fraction/h), for anything that
# has not been migrated. 0.04 fraction/h over 1 h is the SAME rate and must give the SAME answer.
old = ca._su_projected({"acct": "next3", "session_pct": 20, "session_reset_h": 4.0,
                        "burn_5h_ph": 0.04}, R)
assert abs(old - p) < 1e-9, (old, p)
# CONTROL 2: the projection is still CAPPED at the window reset — pressure past the reset does
# not exist, and a lookahead longer than the runway must not invent it.
near = ca._su_projected({"acct": "next3", "session_pct": 20, "session_reset_h": 0.1,
                         "burn_5h_ewma_ph": 4.0}, R)
assert 0.20 < near < 0.21, near
# CONTROL 3: the kill switch still kills it, so this whole term stays defeatable
import os
os.environ["CC_ROUTE_PROJ"] = "off"
try:
    assert ca._su_projected(r, R) == 0.20, ca._su_projected(r, R)
finally:
    del os.environ["CC_ROUTE_PROJ"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-35: a 5h ROLL is crossed, not discarded, and the roll test is the ROUNDED key" {
  # (a) The incumbent's newest-adjacent-pair form goes blind across a reset: b - a < 0, the
  #     field is left absent, and the router loses the 5h rate exactly at a roll. Here the new
  #     window's LEVEL substitutes as a lower bound and the estimate survives.
  # (b) THE SPELLING. The reset stamp jitters sub-second and straddles the minute boundary; a
  #     truncation key splits one window into two on 46.0% of pairs, and the roll branch then
  #     injects an ABSOLUTE level as a delta. This asserts the jitter is NOT read as a roll by
  #     pinning the rate: a truncation spelling reads the accumulated level and lands far high.
  run python3 -c "$LOAD"'
# (a) 3 h at 5 %/h, a reset, then 3 h at 5 %/h in the new window
pre = series(3.0, 5.0, reset_in_h=0.0)
for e in pre:
    e["_t"] -= 3.0 * 3600.0
post = series(3.0, 5.0, reset_in_h=2.0, start_pct=0.0)
for e in post:
    e["session_reset_at"] = iso(NOW + 2.0 * 3600.0)
v, span = ca.burn_5h_ewma_ph(pre + post, NOW)
assert v is not None, "abstained on a ROLL — the one thing it must never do"
assert 3.0 < v < 8.0, v                        # ~5 %/h, not the 15 pp level injected as a delta
# (b) the same series with the reset stamp jittering ±0.4 s across a minute boundary and NO
# reset at all. A truncation key calls ~half of those pairs rolls and injects the level.
flat = series(6.0, 4.0)
base = NOW + 4.0 * 3600.0
base = (base // 60.0) * 60.0                   # land it exactly on a minute boundary
for i, e in enumerate(flat):
    e["session_reset_at"] = iso(base + (-0.4 if i % 2 else 0.4))
vj, _ = ca.burn_5h_ewma_ph(flat, NOW)
assert vj is not None, vj
assert 3.6 < vj < 4.4, ("jitter read as a roll: %r" % vj)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-36 CONTROL: it ABSTAINS below the 1.3 h span floor and below 2 pairs — and only there" {
  # Below SU_EWMA_MIN_SPAN_H a ±1 pp quantization step is more than a quarter of the 5h meter's
  # realised mean, so the number would be reading its own rounding. The paired arm is what makes
  # this a control rather than an always-None stub.
  run python3 -c "$LOAD"'
assert ca.burn_5h_ewma_ph(series(0.6, 4.0), NOW)[0] is None, "did not abstain below the floor"
assert ca.burn_5h_ewma_ph(series(0.1, 4.0), NOW)[0] is None, "did not abstain on one pair"
assert ca.burn_5h_ewma_ph([], NOW)[0] is None
assert ca.burn_5h_ewma_ph(None, NOW)[0] is None
# CONTROL: just above the floor it SPEAKS
v, span = ca.burn_5h_ewma_ph(series(2.0, 4.0), NOW)
assert v is not None, (v, span)
assert span >= ca.SU_EWMA_MIN_SPAN_H, span
# ...and the abstain REPORTS ITS SPAN, because a null that cannot say why reads as a missing
# measurement rather than as a refusal (L2).
_, short = ca.burn_5h_ewma_ph(series(0.6, 4.0), NOW)
assert 0.0 < short < ca.SU_EWMA_MIN_SPAN_H, short
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-37: apply_burn stamps the new key and KEEPS the incumbent burn_5h_ph populated" {
  # One release of overlap, and it is not caution: anything still reading burn_5h_ph keeps the
  # number it has always read. Deleting it in the same change turns a missed reader into a
  # silent zero, which is the direction nothing can detect.
  run python3 -c "$LOAD"'
rows = [{"acct": "next3", "session_pct": 24, "session_reset_h": 4.0,
         "weekly_pct": 30, "weekly_reset_h": 100.0}]
ca.apply_burn(rows, {}, samples=series(6.0, 4.0))
r = rows[0]
assert "burn_5h_ewma_ph" in r, r
assert 3.6 < r["burn_5h_ewma_ph"] < 4.4, r          # %/h
assert "burn_5h_span_h" in r and r["burn_5h_span_h"] >= 5.5, r
assert "burn_5h_ph" in r, r                          # the incumbent is NOT overwritten
assert 0.03 < r["burn_5h_ph"] < 0.05, r              # ...and stays in ITS unit, fraction/h
assert r["burn_5h_ph"] != r["burn_5h_ewma_ph"], r    # two keys, two units, never aliased
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
