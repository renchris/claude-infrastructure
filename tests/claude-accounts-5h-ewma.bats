#!/usr/bin/env bats
# burn_5h_ewma + its consumption in _su_projected — M1. USAGE_TELEMETRY_100P §5.2 S7,
# RED-proof cases RP-32..RP-35.
#
# 🚨 BOTH OF THIS METRIC'S HAZARDS PRODUCE A PLAUSIBLE WRONG NUMBER, AND NEITHER RAISES ANYTHING.
#
#   * THE UNIT. The estimator emits %/h. `burn_5h_ph`, the field it supersedes, is fraction/h —
#     `_su_projected` computes `su + b * ahead` with `su` in [0, 1]. Write %/h into that and the
#     sum saturates at `min(1.0, ...)` on essentially every row: a 100x error that does not read
#     as an error, it reads as "every account is under 5h pressure", i.e. a fleet-wide soften with
#     a plausible story. RP-34 is the divide; RP-34b is the control that the divide is not simply
#     a mute.
#   * THE ROLL SPELLING. `_reset_key` is minute-ROUNDED (S1a). Under truncation the roll branch
#     fires on 46.0% of adjacent pairs and injects an ABSOLUTE meter level as a delta: MAE
#     degrades 0.0282 -> 0.2110, i.e. 5.4x WORSE than the incumbent this replaces. RP-33.
#
# WHAT IT WINS IS AVAILABILITY, NOT ACCURACY, and the suite is written to say so. The incumbent
# takes the single newest adjacent pair and DISCARDS it outright when the 5h window rolled between
# the two samples (`d < 0`). Windows roll every five hours by construction, so the incumbent goes
# blind on a fixed schedule. RP-33 is that case: the incumbent leaves the field absent, this
# reconstructs the post-roll accrual as a lower bound.
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
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def ramp(hours, pph, sra_t, start_pct=0.0, step_h=0.1, acct="next3", t_end_ago_h=0.0):
    """A flat 5h window: session_pct climbs at `pph` %/h, one reset stamp throughout."""
    out, n = [], int(round(hours / step_h))
    for i in range(n + 1):
        t = NOW - t_end_ago_h * 3600.0 - (n - i) * step_h * 3600.0
        out.append({"acct": acct, "_t": t, "weekly_pct": 40.0,
                    "session_pct": start_pct + pph * i * step_h,
                    "session_reset_at": iso(sra_t), "weekly_reset_at": iso(NOW + 100 * 3600)})
    return out
'

@test "RP-32: the 5h EWMA is in %/h and reads the rate the series actually carries" {
  # 4 h of samples climbing at 8 %/h under one reset stamp. The EWMA (hl = 1 h) must read ~8,
  # not 0.08 (fraction/h) and not 480 (%/min). The span it reports is the RAW measured span —
  # the sum of usable dt — which is what the abstain is written against.
  run python3 -c "$LOAD"'
ss = ramp(4.0, 8.0, NOW + 3600.0)
v, span = ca.burn_5h_ewma(ss, NOW)
assert v is not None, (v, span)
assert 7.5 < v < 8.5, (v, span)                  # %/h — NOT 0.08 and NOT 480
assert abs(span - 4.0) < 0.05, (v, span)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32b: it ABSTAINS below the 1.3h raw span, and on fewer than two usable pairs" {
  # Below SU_EWMA_MIN_SPAN_H a +-1 pp quantization step exceeds 25% of the 5h meter's realised
  # mean, so the number would be reading its own rounding. The span is still RETURNED on an
  # abstain, because a null that cannot say why reads as a missing measurement, not a refusal.
  # A GAP is the third arm: pairs wider than SU_EWMA_MAX_DT_H are a hole in the series, not a
  # measurement, and counting their dt into the span is how a starved series clears the floor.
  run python3 -c "$LOAD"'
v, span = ca.burn_5h_ewma(ramp(0.8, 8.0, NOW + 3600.0), NOW)
assert v is None, (v, span)
assert 0.7 < span < 0.9, (v, span)               # the REASON is reported, not swallowed
v2, s2 = ca.burn_5h_ewma(ramp(0.1, 8.0, NOW + 3600.0), NOW)
assert v2 is None, (v2, s2)                      # 1 pair
v3, s3 = ca.burn_5h_ewma([], NOW)
assert v3 is None and s3 == 0.0, (v3, s3)
gap = [{"acct": "next3", "_t": NOW - 5.5 * 3600, "session_pct": 0.0,
        "session_reset_at": iso(NOW + 3600.0)},
       {"acct": "next3", "_t": NOW - 0.2 * 3600, "session_pct": 40.0,
        "session_reset_at": iso(NOW + 3600.0)},
       {"acct": "next3", "_t": NOW, "session_pct": 41.0,
        "session_reset_at": iso(NOW + 3600.0)}]
v4, s4 = ca.burn_5h_ewma(gap, NOW)
assert v4 is None, (v4, s4)                      # the 5.3 h pair is a GAP: not counted, not spanned
assert s4 < 0.3, (v4, s4)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33: a 5h ROLL is reconstructed, not discarded — the incumbent goes blind, this does not" {
  # Windows roll every five hours BY CONSTRUCTION, and the incumbent's newest-pair form reads
  # `d < 0` across the roll and leaves the field absent. The blindness is therefore scheduled, not
  # occasional. Here the new window's LEVEL is the post-roll accrual, taken as a lower bound.
  # NEVER abstain on a roll: the roll is the case this estimator exists for.
  run python3 -c "$LOAD"'
old = ramp(3.0, 8.0, NOW - 1.0 * 3600.0, start_pct=60.0, t_end_ago_h=1.0)
new = ramp(0.9, 6.0, NOW + 4.0 * 3600.0, start_pct=0.0)
ss = sorted(old + new, key=lambda e: e["_t"])
v, span = ca.burn_5h_ewma(ss, NOW)
assert v is not None, (v, span)
assert v > 0, (v, span)
assert span > ca.SU_EWMA_MIN_SPAN_H, (v, span)
# the incumbent on the same series: the newest pair is post-roll and fine, but the PAIR THAT
# STRADDLES the roll reads a negative delta and contributes nothing at all.
a = [e for e in ss if e["_t"] <= NOW - 0.95 * 3600.0][-1]
b = [e for e in ss if e["_t"] > NOW - 0.95 * 3600.0][0]
assert b["session_pct"] < a["session_pct"], (a["session_pct"], b["session_pct"])
assert ca._rolled(a, b, "session_reset_at", "session_pct") is True, (a, b)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33b CONTROL: with NO roll the level is never injected as a delta" {
  # The roll branch takes an ABSOLUTE meter level as the increment. Fired wrongly — which minute
  # TRUNCATION does on 46.0% of adjacent pairs — it degrades MAE 0.0282 -> 0.2110, 5.4x worse
  # than the incumbent it replaces. A flat, unrolled window must therefore read ZERO, not 70.
  run python3 -c "$LOAD"'
flat = ramp(4.0, 0.0, NOW + 3600.0, start_pct=70.0)
v, span = ca.burn_5h_ewma(flat, NOW)
assert v == 0.0, (v, span)                        # NOT 70/dt — the level is not a delta
# ...and a sub-second jitter across the minute boundary is not a roll either (S1a, RP-1)
j = [{"acct": "next3", "_t": NOW - 0.2 * 3600, "session_pct": 40.0,
      "session_reset_at": "2026-08-25T11:59:59.900Z"},
     {"acct": "next3", "_t": NOW - 0.1 * 3600, "session_pct": 44.0,
      "session_reset_at": "2026-08-25T12:00:00.100Z"},
     {"acct": "next3", "_t": NOW, "session_pct": 48.0,
      "session_reset_at": "2026-08-25T11:59:59.800Z"}]
assert ca._rolled(j[0], j[1], "session_reset_at", "session_pct") is False, j
v2, s2 = ca.burn_5h_ewma(j, NOW)
assert v2 is None, (v2, s2)                       # span 0.2h is below the floor — a refusal
assert abs(s2 - 0.2) < 0.02, (v2, s2)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-34: _su_projected DIVIDES the %/h key by 100 — otherwise every row saturates to 1.0" {
  # THE 100x ERROR THAT LOOKS LIKE A FINDING. `su` is a fraction; `burn_5h_ewma_ph` is %/h. Added
  # raw, `min(1.0, su + b * ahead)` pins to 1.0 on essentially every row, and the fleet reads as
  # uniformly under 5h pressure — a soften with a plausible story and no error anywhere.
  # 20% used, 8 %/h, 1 h of lookahead => 0.20 + 0.08 = 0.28. Raw, it would be 0.20 + 8 => 1.0.
  run python3 -c "$LOAD"'
R = {"PROJ_LOOKAHEAD_H": 1.0}
r = {"session_pct": 20.0, "session_reset_h": 5.0, "burn_5h_ewma_ph": 8.0}
su = ca._su_projected(r, R)
assert abs(su - 0.28) < 0.005, su
assert su < 1.0, su
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-34b CONTROL: the EWMA is PREFERRED where present, the incumbent still read where not" {
  # A `/100` implemented as "ignore the new key" also passes RP-34. Both halves are pinned: the
  # EWMA wins when stamped, and `burn_5h_ph` (fraction/h) is still honoured on a row that has only
  # it — which is what keeps the old key populated for one release from being decorative.
  run python3 -c "$LOAD"'
R = {"PROJ_LOOKAHEAD_H": 1.0}
both = {"session_pct": 20.0, "session_reset_h": 5.0,
        "burn_5h_ewma_ph": 8.0, "burn_5h_ph": 0.02}
assert abs(ca._su_projected(both, R) - 0.28) < 0.005, ca._su_projected(both, R)   # 0.08, not 0.02
old = {"session_pct": 20.0, "session_reset_h": 5.0, "burn_5h_ph": 0.02}
assert abs(ca._su_projected(old, R) - 0.22) < 0.005, ca._su_projected(old, R)
bare = {"session_pct": 20.0, "session_reset_h": 5.0}
assert abs(ca._su_projected(bare, R) - 0.20) < 1e-9, ca._su_projected(bare, R)
# the lookahead is still capped at the window reset — past it, pressure vanishes
near = {"session_pct": 20.0, "session_reset_h": 0.25, "burn_5h_ewma_ph": 8.0}
assert abs(ca._su_projected(near, R) - 0.22) < 0.005, ca._su_projected(near, R)
# ...and it stays SOFTEN-ONLY: it cannot lower the projection below the measured meter
assert ca._su_projected(both, R) >= 0.20, ca._su_projected(both, R)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-35: apply_burn stamps the new key BESIDE the old one, in its own unit" {
  # `burn_5h_ph` is kept populated for one release (§5.2 S7). A key that vanishes takes its
  # consumers down silently — _su_projected falls back to the raw meter and no surface says why.
  # The two must coexist and must differ by exactly the 100x their units imply.
  run python3 -c "$LOAD"'
ss = ramp(4.0, 8.0, NOW + 3600.0)
rows = [{"acct": "next3", "session_pct": 32.0, "session_reset_h": 1.0,
         "weekly_pct": 40.0, "weekly_reset_h": 100.0}]
ca.apply_burn(rows, {}, samples=ss)
r = rows[0]
assert "burn_5h_ewma_ph" in r, r
assert "burn_5h_ph" in r, r                        # the incumbent survives the release
assert 7.5 < r["burn_5h_ewma_ph"] < 8.5, r         # %/h
assert 0.075 < r["burn_5h_ph"] < 0.085, r          # fraction/h — the SAME rate, other unit
assert "burn_5h_span_h" in r and r["burn_5h_span_h"] > 1.3, r
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
