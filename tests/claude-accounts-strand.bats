#!/usr/bin/env bats
# The weekly-drain planner's arithmetic — exchange_rate (S1c), completed_weekly_windows (S1d),
# burn_wk_ewma_ph and wk_strand_pp (S3). USAGE_TELEMETRY_100P §5.2 / §5.3, cases RP-9..RP-16.
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

# ---- S5 · M3c · strand_score — the harness that CAN fail --------------------------------------
#
# WHY THESE CASES EXIST. The score S5 replaces evaluated M3a's fire rule at each window's LAST
# sample, where the projection has already converged to `100 - weekly_pct` — the realised strand
# itself — so it agreed with the identity function on 8 of 8 windows and published `4/4 recall,
# 0 FP, median ~20 h lead`. It could not have come out any other way. RP-30 is the same estimator
# read at fixed distances from the reset, where it demonstrably does come out wrong.

SSLOAD='
def segs(acct, reset, segments, step_h=0.1, wp0=0.0, now=None):
    """segments = [(hours, weekly pp/h), ...] walked forward to `reset`. The whole tail of one
    weekly window, so completed_weekly_windows sees a reset in the past observed to its close."""
    out, wp = [], wp0
    t = -sum(h for h, _ in segments)
    for hours, rate in segments:
        for _ in range(int(round(hours / step_h))):
            out.append({"acct": acct, "weekly_pct": round(wp, 4), "session_pct": 10,
                        "_t": reset + t * 3600.0, "weekly_reset_at": iso(reset),
                        "session_reset_at": iso(NOW + 3 * 3600.0)})
            wp += rate * step_h
            t += step_h
    return out
R = NOW - 6 * 3600.0            # a weekly reset 6 h in the PAST: a COMPLETED window
'

@test "RP-30: strand_score scores M3a at FIXED horizons, and the bias is NOT zero out at 96h" {
  # The fixture is a window that burns 0.6 %/h for 110 h and then SLOWS to 0.4 %/h for its last
  # 30 h, closing at 78% — a 22 pp strand. Read at 96 h out, the nowcast sees only the fast pace
  # and projects a 16 pp strand: WRONG BY 6 pp, in the direction that matters (it under-projects
  # the loss). Read at 6 h out it is within 0.1 pp. That convergence IS §5.1 LB-2's claim — a good
  # nowcaster precisely because it is a bad forecaster — and this is the first time it is measured
  # rather than asserted. A harness that reported 0.00 at every horizon would be the tautology.
  run python3 -c "$LOAD$SSLOAD"'
sam = segs("next3", R, [(110.0, 0.6), (30.0, 0.4)])
sc = ca.strand_score(sam, now=NOW)
assert sc["windows"] == 1, sc["windows"]
by = {b["h"]: b for b in sc["buckets"]}
assert sorted(by) == [6.0, 12.0, 24.0, 48.0, 96.0], sorted(by)
for h in (96.0, 48.0, 24.0, 12.0, 6.0):
    assert by[h]["n"] == 1, by[h]
assert -7.0 < by[96.0]["bias"] < -5.0, by[96.0]        # measured -6.02
assert -7.0 < by[48.0]["bias"] < -5.0, by[48.0]
assert abs(by[6.0]["bias"]) < 0.5, by[6.0]             # measured -0.06
# it CONVERGES as the horizon closes -- monotone in |error|, which is the whole LB-2 claim
mae = [by[h]["mae"] for h in (96.0, 48.0, 24.0, 12.0, 6.0)]
assert mae == sorted(mae, reverse=True), mae
assert mae[0] > 20 * mae[-1], mae
txt = ca.render_strand_score(sc)
assert "scored against 1 completed weekly window(s)" in txt, txt
assert "12h" in txt and "sign-agree" in txt, txt
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31 CONTROL: the projection is CAUSAL — samples after the read instant cannot enter it" {
  # THE REPLAY-THE-REAL-ARTIFACT TRAP, as a mutant. burn_wk_ewma_ph filters on
  # `now - e._t <= LOOKBACK`, and for a sample in the FUTURE that difference is NEGATIVE, so it
  # passes -- and its weight 2**(-negative/hl) is greater than 1, so it does not merely leak in,
  # it DOMINATES. Handing the whole series to the estimator therefore scores a projection nothing
  # ever rendered, and scores it with the answer in hand.
  #
  # Two series with an IDENTICAL first 110 h and the same closing pct, differing only in the last
  # 30 h. The 96 h and 48 h cells sit inside the shared prefix, so a causal implementation must
  # return the SAME projection for both. Measured: 16.00356 for both, against a full-series
  # implementation that reads 33.78 / 24.90 for one and 10.64 / 13.32 for the other.
  run python3 -c "$LOAD$SSLOAD"'
a = ca.strand_score(segs("next3", R, [(110.0, 0.6), (30.0, 0.4)]), now=NOW)
b = ca.strand_score(segs("next3", R, [(110.0, 0.6), (20.0, 0.1), (10.0, 1.0)]), now=NOW)
for h in (96.0, 48.0):
    pa = [c for c in a["cells"] if c["h"] == h][0]["projected"]
    pb = [c for c in b["cells"] if c["h"] == h][0]["projected"]
    assert abs(pa - pb) < 1e-9, (h, pa, pb)
    assert 15.0 < pa < 17.0, (h, pa)     # and it is the CAUSAL value, not either mutant reading
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32 CONTROL: a horizon the series never covered is n=0 and EXCLUDED, never a zero error" {
  # An unmeasured cell counted as agreement is exactly how the old harness reached 8/8. A series
  # that only reaches 40 h back cannot be read at 96 h or 48 h; those cells must report NOTHING,
  # and the renderer must print the dash rather than a 0.00 that reads as a perfect score.
  run python3 -c "$LOAD$SSLOAD"'
sam = [e for e in segs("next3", R, [(110.0, 0.6), (30.0, 0.4)]) if (R - e["_t"]) / 3600.0 <= 40.0]
sc = ca.strand_score(sam, now=NOW)
by = {b["h"]: b for b in sc["buckets"]}
for h in (96.0, 48.0):
    assert by[h]["n"] == 0 and by[h]["bias"] is None and by[h]["mae"] is None, by[h]
    assert by[h]["sign_agree"] is None, by[h]
assert by[24.0]["n"] == 1 and by[24.0]["bias"] is not None, by[24.0]
assert not [c for c in sc["cells"] if c["h"] in (96.0, 48.0)], sc["cells"]
txt = ca.render_strand_score(sc)
line96 = [l for l in txt.split(chr(10)) if l.strip().startswith("96h")][0]
assert "—" in line96 and "0.00" not in line96, line96
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33 CONTROL: sign-agreement can be 0%, and a LIVE window is never scored" {
  # (a) Both series are clamped at 0 by M3a, so agreement on the SIGN of the error would be
  # vacuously 1.0. The rate reported is agreement on the binary claim pace_line actually makes --
  # will this window strand MATERIALLY (>= 0.5 pp)? A window that burns 0.8 %/h and then STALLS
  # projects "fills the window" at 96 h and closes 12 pp short: 0% agreement, as it should be.
  # (b) completed_weekly_windows S1d: a window whose reset has not happened is not a result.
  run python3 -c "$LOAD$SSLOAD"'
stall = ca.strand_score(segs("next2", R, [(110.0, 0.8), (30.0, 0.0)]), now=NOW)
by = {b["h"]: b for b in stall["buckets"]}
assert by[96.0]["sign_agree"] == 0.0, by[96.0]         # said "no strand"; it stranded 12 pp
assert by[6.0]["sign_agree"] == 1.0, by[6.0]
assert [c for c in stall["cells"] if c["h"] == 96.0][0]["projected"] == 0.0, stall["cells"][0]
live = ca.strand_score(segs("next3", NOW + 40 * 3600.0, [(110.0, 0.6), (30.0, 0.4)]), now=NOW)
assert live["windows"] == 0 and live["cells"] == [], live
assert all(b["n"] == 0 for b in live["buckets"]), live["buckets"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-34 e2e: --strand-score answers with no config, no keychain and no sweep" {
  # Placed before load_cfg() for the same reason as --agents: a question about HISTORY must not
  # block behind a 4-account sweep or require a Claude accounts.json to exist. $HOME here is an
  # empty fixture dir, so a branch sited after load_cfg() exits non-zero -- which is exactly how
  # the --agents coupling was found.
  local log="$BATS_TEST_TMPDIR/util.jsonl"
  python3 - "$log" <<'PY'
import json, sys, time
from datetime import datetime, timezone
now = time.time(); reset = now - 6 * 3600.0
def iso(t): return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
wp, t, rows = 0.0, -140.0, []
while t < -0.04:
    rows.append({"ts": iso(reset + t * 3600.0), "acct": "next3", "session_pct": 10,
                 "weekly_pct": round(wp, 4), "session_reset_at": iso(now + 3 * 3600.0),
                 "weekly_reset_at": iso(reset)})
    wp += (0.6 if t < -30.0 else 0.4) * 0.1
    t += 0.1
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  CC_UTIL_LOG="$log" run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  [[ "$output" == *"scored against 1 completed weekly window(s)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"sign-agree"* ]] || { echo "$output"; false; }
  # §5.4 acceptance 2: non-zero n at 24h, 12h and 6h, and a bias that COULD have been non-zero
  CC_UTIL_LOG="$log" run python3 "$CA_BIN" --strand-score --json
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  echo "$output" > "$BATS_TEST_TMPDIR/sc.json"
  run python3 - "$BATS_TEST_TMPDIR/sc.json" <<'PY'
import json, sys
by = {b["h"]: b for b in json.load(open(sys.argv[1]))["buckets"]}
for h in (24.0, 12.0, 6.0):
    assert by[h]["n"] >= 1, by[h]
assert abs(by[96.0]["bias"]) > 1.0, by[96.0]     # not a table of zeroes
print("OK")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
  # an EMPTY series is an honest refusal, not a crash and not a table over nothing
  CC_UTIL_LOG="$BATS_TEST_TMPDIR/empty.jsonl" run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  [[ "$output" == *"nothing to score"* ]] || { echo "$output"; false; }
}
