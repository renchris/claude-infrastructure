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
  # the shortfall regime -- where the arithmetic converges -- and discards the overshoot.
  #
  # WALL ARM UPDATED IN PLACE 2026-08-29, named invariant unchanged. This case used to also
  # assert `⚠ WALL trajectory` in the line at THIS phase, on the reasoning that the flag is
  # "true and actionable" even where the number is not. That reasoning was falsified by the
  # backtest in weekly-reset-utilization-2026-08-25.md §3: next@08-23 read 51% at day 3, burn
  # 1.19x, projected 119% ⚠WALL -- and the window closed at 99%. The wall never arrived. It is
  # the one mid-week WALL we have ground truth for and it was a FALSE ALARM, so the flag was
  # not carrying the direction while the number was wrong; both were wrong together. It cannot
  # be otherwise: mid-week burn_ratio has MAE 46 pp, and 6 of 8 completed windows finished
  # BELOW 100 (85, 91, 92, 92, 98, 99, 100, 100), so a flag fired at phase 0.32 is reading a
  # property of nearly every window rather than of this one. `wall_projection` now abstains
  # below phase 0.90 and the row falls to its plain arm. RP-16c is the control that the flag
  # still fires where it IS supportable -- this is a narrowed warning, never a deleted one.
  run python3 -c "$LOAD"'
r = {"acct": "next", "weekly_pct": 52, "weekly_reset_h": 114.0, "burn_wk_ewma_ph": 1.725}
st = ca.wk_strand_pp(r)
assert st == 0.0, st
line = ca.pace_line([r])
assert "on pace to fill the window" in line, line
assert "⚠ WALL trajectory" not in line, line
assert "248" not in line, line
assert "231" not in line, line
assert "154" not in line, line
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-16c CONTROL: the ⚠ WALL flag still fires near the wall, so RP-16 narrows it not deletes it" {
  # Same account 8.4 h from reset (phase 0.95, above wall_projection's floor) at 99% with the
  # EWMA carrying it past 100. Here linear and empirical have converged (-2 pp at day 7) and an
  # account that reaches 100% is DOWN until reset, so the warning is both supportable and
  # actionable. Without this case RP-16 is satisfied by a renderer that dropped ⚠ WALL entirely.
  run python3 -c "$LOAD"'
r = {"acct": "next", "weekly_pct": 99, "weekly_reset_h": 8.4, "burn_wk_ewma_ph": 0.5}
assert ca.wk_strand_pp(r) == 0.0, ca.wk_strand_pp(r)
line = ca.pace_line([r])
assert "⚠ WALL trajectory" in line, line
assert "104" not in line, line   # and the overshoot is STILL never a number
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
