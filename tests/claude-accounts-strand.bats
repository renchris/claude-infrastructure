#!/usr/bin/env bats
# The weekly-drain planner's arithmetic — exchange_rate (S1c), completed_weekly_windows (S1d),
# burn_wk_ewma_ph and wk_strand_pp (S3), and strand_score (S5). USAGE_TELEMETRY_100P §5.2 / §5.3,
# cases RP-9..RP-16 and RP-30..RP-33.
#
# WHAT THIS SUITE IS FOR. The fleet strands 43 pp per 8 completed account-weeks and no surface
# names which account is losing it. Every figure that claim rests on comes out of the two
# helpers pinned here, and BOTH of them have a failure mode that returns a plausible number:
#
#   * completed_weekly_windows — the synthesis's rule was "reset observed with the last sample
#     <= 3 h before it", which ADMITS THE CURRENTLY-LIVE WINDOW, because a live window's newest
#     sample is always some hours before its own reset. It reported 51 pp over 9 account-weeks
#     against a true 43 pp over 8. `gap-IS-the-mechanism`: a detector for "the window ended"
#     that fires DURING the window. RP-9 is that defect, and it is not hypothetical — it was hit
#     while the spec was being written.
#   * exchange_rate — the trailing fit already reads 0.2000 (from 08-21) and 0.2012 (from 08-22),
#     above the shipped band's 0.198 ceiling, at p = 0.0948. Not proven to be drift; a frozen
#     literal has no path to learn that it became one. RP-10..RP-12 pin all THREE arms of the
#     abstain, because a two-arm implementation is exactly how "abstain" becomes "always None".
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
from datetime import datetime, timedelta, timezone
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
NOW = time.time()
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def s(t_ago_h, sp=10, wp=40, acct="next3", sra=None, wra=None):
    e = {"acct": acct, "session_pct": sp, "weekly_pct": wp, "_t": NOW - t_ago_h * 3600.0}
    e["session_reset_at"] = iso(sra) if sra is not None else None
    e["weekly_reset_at"] = iso(wra) if wra is not None else None
    return e
'

@test "RP-9: a completed weekly window requires its reset to be in the PAST" {
  # Two windows for one account. (i) reset 24 h ago, last sample 0.1 h before it, 90% -> a real
  # 10 pp strand. (ii) reset 2 h in the FUTURE, last sample now, 92% -> live, not completed.
  # The naive gap-only rule returns BOTH and totals 18 pp. That is the 51-vs-43 defect exactly.
  run python3 -c "$LOAD"'
done_reset = NOW - 24 * 3600
live_reset = NOW + 2 * 3600
samples = [s(24.1 + i * 0.1, wp=90 - i, wra=done_reset) for i in range(6)]
samples += [s(0.0 + i * 0.1, wp=92, wra=live_reset) for i in range(6)]
w = ca.completed_weekly_windows(samples, now=NOW)
assert len(w) == 1, w
assert abs(w[0]["strand"] - 10.0) < 1e-9, w
assert w[0]["acct"] == "next3", w
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-9b CONTROL: a window the series LOST before its close is not counted as a 100% strand" {
  # The other direction of the same rule. A past reset whose newest sample is 20 h old was never
  # observed to its close; counting it would mint a fabricated strand out of a sampling gap.
  run python3 -c "$LOAD"'
samples = [s(44 + i * 0.1, wp=60, wra=NOW - 24 * 3600) for i in range(6)]
assert ca.completed_weekly_windows(samples, now=NOW) == [], "lost window was counted"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-10: exchange_rate ABSTAINS when the trailing fit leaves the sane band" {
  # 400 pairs, sum(dsession) = 2,000 pp and sum(dweekly) = 460 pp => K = 0.230, past K_SANE's
  # 0.210 ceiling. Outside the band the PLAN changed (or the meter did) and no K-consuming
  # metric may render: silently widening the band would launder a plan change into a number.
  run python3 -c "$LOAD"'
SRA, WRA = NOW + 3 * 3600, NOW + 100 * 3600
samples, sp, wp = [], 0.0, 0.0
for i in range(401):
    samples.append(s(160 - i * 0.4, sp=sp, wp=wp, sra=SRA, wra=WRA))
    sp += 5.0; wp += 1.15
k, sds, src = ca.exchange_rate(samples)
assert k is None, (k, sds, src)
assert src is None, (k, sds, src)
assert abs(sds - 2000.0) < 1.0, sds
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-11 CONTROL: a healthy fit is USED, not abstained (the arm that makes RP-10 a control)" {
  # Same shape, sum(dweekly) = 385 pp => K = 0.1925, the value three independent reproductions
  # landed on. An implementation that abstains unconditionally passes RP-10 and fails here.
  run python3 -c "$LOAD"'
SRA, WRA = NOW + 3 * 3600, NOW + 100 * 3600
samples, sp, wp = [], 0.0, 0.0
for i in range(401):
    samples.append(s(160 - i * 0.4, sp=sp, wp=wp, sra=SRA, wra=WRA))
    sp += 5.0; wp += 0.9625
k, sds, src = ca.exchange_rate(samples)
assert src == "live", (k, sds, src)
assert abs(k - 0.1925) < 0.002, k
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-12 CONTROL: a thin fit FALLS BACK to the frozen constant (three arms, not two)" {
  # sum(dsession) = 100 pp, below K_MIN_SDS = 300. Too thin to fit is a THIRD state, distinct
  # from both "fitted" and "insane" — collapsing it into either loses a real distinction.
  run python3 -c "$LOAD"'
SRA, WRA = NOW + 3 * 3600, NOW + 100 * 3600
samples, sp, wp = [], 0.0, 0.0
for i in range(21):
    samples.append(s(20 - i * 0.4, sp=sp, wp=wp, sra=SRA, wra=WRA))
    sp += 5.0; wp += 0.96
k, sds, src = ca.exchange_rate(samples)
assert src == "frozen", (k, sds, src)
assert k == 0.192, k
assert abs(sds - 100.0) < 1.0, sds
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-12b CONTROL: a pair that ROLLED is excluded from the fit, not read as a huge delta" {
  # Pins the KEY witness specifically. The pct-decrease witness is redundant here — a rolled pair
  # whose meter FELL is already dropped by the ds >= 0 guard. The dangerous case is a roll the
  # meter crosses going UP: 55 pp of a fresh window read as 55 pp of accrual inside the old one.
  # Uncaught it drags the pooled fit 0.1925 -> 0.1874, which is INSIDE K_SANE, so no band guard
  # ever sees it — the wrong number ships looking exactly like a right one.
  run python3 -c "$LOAD"'
SRA, WRA = NOW + 3 * 3600, NOW + 100 * 3600
samples, sp, wp = [], 0.0, 0.0
for i in range(401):
    samples.append(s(160 - i * 0.4, sp=sp, wp=wp, sra=SRA, wra=WRA))
    sp += 5.0; wp += 0.9625
clean, _, _ = ca.exchange_rate(samples)
assert abs(clean - 0.1925) < 0.002, clean
# one rolled pair spliced on the end: the 5h stamp jumps 5 h and the meter reads HIGHER, not lower
samples.append(s(0.1, sp=sp + 55.0, wp=wp + 0.1, sra=SRA + 5 * 3600, wra=WRA))
with_roll, _, src = ca.exchange_rate(samples)
assert src == "live", src
assert abs(with_roll - clean) < 1e-9, (clean, with_roll)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- S3: burn_wk_ewma_ph (M2) and wk_strand_pp (M3a) ------------------------------------------

@test "RP-13: burn_wk_ewma_ph CROSSES a weekly roll instead of discarding it" {
  # 20 h of samples, the weekly window rolling at the midpoint (96 -> 2 pp, stamp +168 h), then
  # 2 -> 8 pp over the following 10 h. The incumbent widest-pair estimator computes d = b - a < 0
  # across that roll and leaves the field ABSENT — so it is blind for the first stretch of every
  # weekly window, which is exactly when the week's plan is set. Stated positively: the roll
  # branch takes the new window's LEVEL as the increment, a lower bound, never a discard.
  run python3 -c "$LOAD"'
OLD, NEW = NOW + 1 * 3600, NOW + 168 * 3600
sam = []
for i in range(100):                                  # 20 h .. 10 h ago, pre-roll, 86 -> 96
    sam.append(s(20.0 - i * 0.1, wp=86 + i * 0.1, wra=OLD))
for i in range(101):                                  # 10 h .. now, post-roll, 2 -> 8
    sam.append(s(10.0 - i * 0.1, wp=2 + i * 0.06, wra=NEW))
v, span = ca.burn_wk_ewma_ph(sam, NOW, 24.0)
assert v is not None, (v, span)
assert span > 15.0, span
assert v > 0.8, v
# and the incumbent, over the same series, is blind — the blindness stated as an assertion
r = {"acct": "next3", "weekly_pct": 8, "weekly_reset_h": 24.0}
ca.apply_burn([r], {}, samples=sam)
assert "burn_wk_ewma_ph" in r, r
assert "wk_strand_pp" in r, r
assert "burn_wk_ppd" in r, r          # S1 kept the incumbent field populated beside the EWMA
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-14: wk_strand_pp ABSTAINS below the 6.8h measured-span floor" {
  # 6 samples spanning 0.6 h. Below WK_EWMA_MIN_SPAN_H a +-1 pp quantization step exceeds 25% of
  # the weekly meter's realised mean of 0.592 %/h, so the number would be reading its own
  # rounding. The floor is on the RAW MEASURED span — not the weighted span, not the requested
  # lookback — because those two can both be large while the evidence is not.
  run python3 -c "$LOAD"'
WRA = NOW + 100 * 3600
sam = [s(0.6 - i * 0.1, wp=40 + i * 0.1, wra=WRA) for i in range(6)]
v, span = ca.burn_wk_ewma_ph(sam, NOW, 100.0)
assert v is None, (v, span)
assert span < 6.8, span
r = {"acct": "next3", "weekly_pct": 40, "weekly_reset_h": 100.0}
assert ca.wk_strand_pp(r) is None, ca.wk_strand_pp(r)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-15 CONTROL: above the floor it PROJECTS — without this, RP-14 is an always-None stub" {
  # 90 samples spanning 9 h at a steady 0.5 %/h, 40% used with 100 h left. 40 + 0.5*100 = 90,
  # so ~10 pp die at reset. The arithmetic is a nowcast of the shortfall, nothing more.
  run python3 -c "$LOAD"'
WRA = NOW + 100 * 3600
sam = [s(9.0 - i * 0.1, wp=35.5 + i * 0.05, wra=WRA) for i in range(91)]
v, span = ca.burn_wk_ewma_ph(sam, NOW, 100.0)
assert v is not None, (v, span)
assert span >= 6.8, span
assert abs(v - 0.5) < 0.05, v
r = {"acct": "next3", "weekly_pct": 40, "weekly_reset_h": 100.0, "burn_wk_ewma_ph": v}
st = ca.wk_strand_pp(r)
assert st is not None and 8.0 < st < 12.0, st
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-16: an OVERSHOOT is never rendered as a number — the clamp is behaviour, not a comment" {
  # next at phase 0.32 on 2026-08-25: weekly_pct 52, 114 h left, EWMA 1.725 %/h -> a raw
  # projection of 248.7%. In that regime EVERY projector measured here is badly wrong (the
  # incumbent renders 154.6%, this EWMA 231.4%, against a truth near 100%), so the clamp keeps
  # the shortfall regime -- where the arithmetic converges -- and discards the overshoot. The
  # account is reported as on a WALL TRAJECTORY, which is true and actionable; "248%" is neither.
  run python3 -c "$LOAD"'
r = {"acct": "next", "weekly_pct": 52, "weekly_reset_h": 114.0, "burn_wk_ewma_ph": 1.725}
st = ca.wk_strand_pp(r)
assert st == 0.0, st
line = ca.pace_line([r])
assert "248" not in line, line
assert "231" not in line, line
assert "154" not in line, line
# AMENDED 2026-09-01 (backlog 70ed289c10fb), invariant unchanged: the clamp is still what this
# case is for, and no overshoot renders as a number. What moved is WHERE the ⚠ WALL flag may be
# claimed. This fixture sits at phase 0.32 -- mid-week -- and the backtest of exactly this row
# (51% at day 3) projected 119% against a 99% actual; across mid-week the linear projector errs
# by a mean 46 pp, so `wall_projection` now abstains below 6/7 elapsed and this row raises no
# flag at all. The flag is re-asserted below in the LAST DAY, where linear and empirical have
# converged (-17 pp at day 6, -2 pp at day 7) and hitting 100% early really is imminent.
assert "⚠ WALL" not in line, line
assert "× burn" not in line, line
w = {"acct": "next", "weekly_pct": 95, "weekly_reset_h": 20.0, "burn_wk_ewma_ph": 1.0}
assert ca.wk_strand_pp(w) == 0.0, w
wline = ca.pace_line([w])
assert "⚠ WALL trajectory" in wline, wline
assert "1.08× burn" in wline, wline
assert "107" not in wline, wline          # still the RATIO, never the >100 projection
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-16b CONTROL: a NEGATIVE strand is clamped to zero, never flipped into a positive one" {
  # The other side of the clamp. max(0, ...) must not become abs(...): an account projected to
  # overshoot by 20 pp has NO strand, and rendering 20 pp at risk would invert the decision.
  run python3 -c "$LOAD"'
r = {"acct": "next", "weekly_pct": 90, "weekly_reset_h": 10.0, "burn_wk_ewma_ph": 3.0}
assert ca.wk_strand_pp(r) == 0.0, ca.wk_strand_pp(r)
r2 = {"acct": "next", "weekly_pct": 90, "weekly_reset_h": 10.0, "burn_wk_ewma_ph": 0.2}
assert abs(ca.wk_strand_pp(r2) - 8.0) < 1e-9, ca.wk_strand_pp(r2)
# and the abstain arms: a reset stamp outside the bucket is bad data, not a signal
assert ca.wk_strand_pp({"weekly_pct": 50, "weekly_reset_h": 200.0, "burn_wk_ewma_ph": 0.5}) is None
assert ca.wk_strand_pp({"weekly_pct": 50, "weekly_reset_h": 0.0, "burn_wk_ewma_ph": 0.5}) is None
assert ca.wk_strand_pp({"weekly_pct": None, "weekly_reset_h": 10.0, "burn_wk_ewma_ph": 0.5}) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ── S5 · M3c · strand_score — the instrument that CAN fail ─────────────────────────────────────
#
# WHY THIS EXISTS. The synthesis's score evaluated the fire rule at each window's LAST sample,
# where the projection has already converged to `100 - weekly_pct` — i.e. to the true strand — so
# it agreed with the identity function on 8 of 8 windows and produced 8 binary cells that could
# not have come out any other way. `control-must-replay-the-real-artifact.md` and
# `verification-harness-vacuous-pass-traps.md` are the two traps it walked into at once.
#
# THE FIXTURE IS BUILT TO MAKE THE NOWCAST WRONG, and that is the point of the suite. A window
# that burns steadily and then FREEZES for its last two days is the shape the fleet actually
# strands in: at 48 h out, extrapolating the burn says the window fills exactly; it did not.

SCORE_FIXTURE='
RESET_T = round((NOW - 10 * 3600) / 60.0) * 60.0        # 10 h ago, minute-aligned so the
                                                        # _reset_key round-trip is exact
def window(segs, acct="next3", end_h=0.5, reset_t=None):
    """One weekly window at 6-min cadence. segs = [(hours, %/h), ...] walked from the window
    start; the meter saturates at 100, because the real one does."""
    rt = RESET_T if reset_t is None else reset_t
    start_h = sum(h for h, _ in segs)
    out, wp, t = [], 0.0, -start_h
    for hours, rate in segs:
        for _ in range(int(round(hours / 0.1))):
            if t > -end_h + 1e-9:
                break
            out.append({"acct": acct, "weekly_pct": round(min(100.0, wp), 4), "session_pct": 10,
                        "_t": rt + t * 3600.0,
                        "weekly_reset_at": iso(rt),
                        "session_reset_at": iso(rt + 3 * 3600.0)})
            wp += rate * 0.1
            t += 0.1
    return out

FREEZE = [(118.0, 0.6), (50.0, 0.0)]      # burns to 70.8%, then dies for two days: strands 29.1
SPRINT = [(120.0, 0.2), (48.0, 1.6)]      # idles at 0.2 %/h, then fills the window in its last 2 d
'

@test "RP-30: strand_score scores at FIXED horizons, and the far horizons are WRONG" {
  # 118 h at 0.6 %/h reaches 70.8%, then the window freezes for its last 50 h and closes there,
  # stranding 29.1 pp. The nowcast made 48 h out extrapolates the live burn and lands 24 pp under
  # the truth — which is the whole reason a horizon-stratified score is not the tautology the
  # last-sample rule was. Made 6 h out, after the freeze dominates the EWMA, it is nearly exact.
  # A harness whose every cell reads 0.0 has not been run against anything.
  run python3 -c "$LOAD$SCORE_FIXTURE"'
res = ca.strand_score(window(FREEZE), now=NOW)
assert res["windows"] == 1, res["windows"]
b = {x["h"]: x for x in res["buckets"]}
# the FAR horizons: the burn extrapolates over the freeze, so the loss is UNDER-stated
assert b[48.0]["n"] == 1 and b[48.0]["bias"] < -20.0, b[48.0]
assert b[96.0]["n"] == 1 and b[96.0]["bias"] < -20.0, b[96.0]
# the NEAR horizon: the freeze is in the EWMA now, and the nowcast converges
assert b[6.0]["n"] == 1 and abs(b[6.0]["bias"]) < 2.0, b[6.0]
# the stratification is the finding — a scorer that collapsed the horizons would hide it
assert abs(b[48.0]["bias"]) > 10 * abs(b[6.0]["bias"]) + 5.0, (b[48.0], b[6.0])
# AGREEMENT IS NOT ACCURACY, and this window is the case that separates them: both horizons get
# the DECISION right (it strands), and the far one is still 24 pp out on how much. Scoring only
# the decision is how a 24 pp error reads as a clean bucket — which is why bias and MAE are
# reported beside it and why S6 stays gated on reading all three.
assert b[48.0]["agree"] == 1.0 and b[6.0]["agree"] == 1.0, (b[48.0], b[6.0])
assert b[48.0]["mae"] > 20.0 and b[6.0]["mae"] < 2.0, (b[48.0], b[6.0])
# realised belongs to the WINDOW, identical in every cell; only the projection moves
assert all(abs(c["realised"] - 29.1) < 0.3 for x in res["buckets"] for c in x["cells"]), res
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-30b CONTROL: the score is SIGNED, and a far cell can get the DECISION wrong" {
  # The opposite window shape, and it is the one that makes the aggregate a measurement rather
  # than a constant. An account that idles for five days and then sprints fills its window: 48 h
  # out the nowcast projects 66 pp of loss against a realised ZERO — a large POSITIVE bias and a
  # sign DISAGREEMENT, where FREEZE gives a large negative one. A scorer reporting |error| would
  # average these two into a confident-looking number that describes neither.
  run python3 -c "$LOAD$SCORE_FIXTURE"'
res = ca.strand_score(window(SPRINT), now=NOW)
b = {x["h"]: x for x in res["buckets"]}
assert b[48.0]["n"] == 1 and b[48.0]["bias"] > 20.0, b[48.0]        # OVER-states the loss
assert b[48.0]["agree"] == 0.0, b[48.0]                             # ...and calls it wrong
assert b[48.0]["cells"][0]["realised"] < 0.5, b[48.0]               # the window actually FILLED
assert b[6.0]["n"] == 1 and abs(b[6.0]["bias"]) < 2.0, b[6.0]
assert b[6.0]["agree"] == 1.0, b[6.0]
# the two shapes must not cancel: SIGNED bias is what shows a projector is biased rather than
# merely noisy, and it is the number S6 would be gated on.
both = ca.strand_score(window(FREEZE) + window(SPRINT, acct="next4"), now=NOW)
bb = {x["h"]: x for x in both["buckets"]}[48.0]
assert bb["n"] == 2, bb
assert bb["mae"] > 20.0, bb                       # both cells are badly wrong
assert abs(bb["bias"]) < bb["mae"], bb            # ...in OPPOSITE directions
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31 CONTROL: the estimator is CAUSAL — a cell never sees past its own instant" {
  # THE MUTANT THIS CATCHES IS THE OBVIOUS IMPLEMENTATION. burn_wk_ewma_ph filters on
  # `now - _t <= LOOKBACK`, and for a sample AFTER `now` that difference is NEGATIVE — so it
  # passes, and its EWMA weight 2**(-(now-t)/hl) is not merely included but EXPONENTIALLY LARGE
  # (a sample 48 h ahead weighs 64x). Handing the whole account series to a cell evaluated 48 h
  # out therefore lets the freeze that had not happened yet DOMINATE the rate: the projection
  # collapses onto the realised strand, the harness scores hindsight, and every bucket reports a
  # bias near zero. That is the tautology this suite exists to prevent, wearing a lead time.
  run python3 -c "$LOAD$SCORE_FIXTURE"'
sam = window(FREEZE)
res = ca.strand_score(sam, now=NOW)
c = {x["h"]: x for x in res["buckets"]}[48.0]["cells"][0]
assert c["signed_error"] < -20.0, c         # a non-causal read of this fixture scores ~0
assert abs(c["at_h"] - 48.0) < 0.15, c      # and it is scored AT the horizon, not near the end
assert abs(c["signed_error"] - (c["projected"] - c["realised"])) < 1e-9, c
# the same fixture with everything after the horizon DELETED must score the cell identically —
# that is what causal MEANS, and it is the assertion a hindsight scorer cannot pass. The window
# tail is restored only so completed_weekly_windows still sees a window observed to its close.
cut = c["reset_t"] - 48.0 * 3600.0
tr = ca.strand_score([e for e in sam if e["_t"] <= cut + 1]
                     + [e for e in sam if e["_t"] > cut][-6:], now=NOW)
tc = {x["h"]: x for x in tr["buckets"]}[48.0]["cells"][0]
assert abs(tc["projected"] - c["projected"]) < 1e-9, (c, tc)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32 CONTROL: a bucket with no evaluable sample reports n=0 and is EXCLUDED, not imputed" {
  # Two abstain arms, and neither may be scored as a hit — imputing one is how a harness reports
  # perfect agreement over cells it never evaluated.
  #   (a) the series does not reach back to the horizon at all;
  #   (b) it does, but burn_wk_ewma_ph refuses on its own span floor (6.8 h), and walking to an
  #       OLDER witness only makes the span shorter, so the whole bucket abstains.
  # A 12 h window supplies both: nothing at 24 h or beyond, and no 6.8 h of history at the 6 h
  # horizon either.
  run python3 -c "$LOAD$SCORE_FIXTURE"'
res = ca.strand_score(window([(6.0, 0.6), (6.0, 0.0)]), now=NOW)
assert res["windows"] == 1, res           # the WINDOW is completed — this is not a missing window
b = {x["h"]: x for x in res["buckets"]}
for h in (96.0, 48.0, 24.0, 12.0, 6.0):
    assert b[h]["n"] == 0, (h, b[h])
    assert b[h]["bias"] is None and b[h]["mae"] is None and b[h]["agree"] is None, b[h]
    assert b[h]["cells"] == [], b[h]
# an abstained bucket renders as the WORD, never as a blank or a zero (L2)
txt = chr(10).join(ca.render_strand_score(res))
assert "no evaluable sample" in txt, txt
assert "0.00" not in txt, txt
# ...and the full fixture, which DOES evaluate, is the control that the floor is not blanket
assert {x["h"]: x for x in ca.strand_score(window(FREEZE), now=NOW)["buckets"]}[6.0]["n"] == 1
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33: --strand-score answers with no keychain, no sweep and no accounts.json" {
  # Placed before load_cfg() for the same reason --agents is. Fixtured $HOME has no accounts.json
  # and the usage endpoint is unreachable; if this branch fell through to a sweep it would hang
  # or exit non-zero, which is exactly how the --agents coupling was found.
  python3 -c "$LOAD$SCORE_FIXTURE"'
import json
for e in window(FREEZE):
    e["ts"] = iso(e.pop("_t"))
    print(json.dumps(e))' > "$CC_UTIL_LOG"
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"strand-score"* ]] || { echo "$output"; false; }
  [[ "$output" == *"1 completed window(s)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"sign-agree"* ]] || { echo "$output"; false; }
  # the far horizon is present AND wrong — §5.4's acceptance is precisely that a bucket's bias
  # COULD have been non-zero, not that it is small
  [[ "$output" == *"48h"* ]] || { echo "$output"; false; }
  run python3 "$CA_BIN" --strand-score --json
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *'"windows": 1'* ]] || { echo "$output"; false; }
  # an EMPTY series says so rather than rendering an empty table that reads as a clean result
  : > "$CC_UTIL_LOG"
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"nothing to score yet"* ]] || { echo "$output"; false; }
  [[ "$output" != *"sign-agree"* ]] || { echo "$output"; false; }
}
