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
assert "⚠ WALL trajectory" in line, line
assert "248" not in line, line
assert "231" not in line, line
assert "154" not in line, line
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

# ---------------------------------------------------------------------------------------------
# S5 · M3c · strand_score — USAGE_TELEMETRY_100P §5.2 S5, the instrument that CAN fail.
#
# THE SCORE IT REPLACES WAS A TAUTOLOGY. The synthesis evaluated its fire rule at each window's
# LAST sample — the one instant where `100 - weekly_pct` has already converged to the realised
# strand — got 8/8, and published `4/4 recall, 0 FP, median ~20 h lead`. Every part of that was
# an artefact of WHERE it was read. Scoring at fixed distances BEFORE the reset is what makes a
# wrong answer reachable, and RP-32 is the case that proves the harness is not quietly re-writing
# the tautology one layer down.

STRAND_SCORE_LOAD='
def window(acct, reset_t, rates, step_h=0.1):
    """A whole weekly window: rates = [(hours, weekly_pp_per_h), ...] from the window open."""
    out, t, wp = [], reset_t - 168.0 * 3600.0, 0.0
    for hours, rate in rates:
        for _ in range(int(hours / step_h)):
            out.append({"acct": acct, "weekly_pct": min(100.0, wp), "session_pct": 10,
                        "_t": t, "weekly_reset_at": iso(reset_t),
                        "session_reset_at": iso(t + 3 * 3600.0)})
            wp += rate * step_h
            t += step_h * 3600.0
    return out
'

@test "RP-31: strand_score scores CLOSED windows at fixed horizons, and the bias is REACHABLE" {
  # One closed window: 156 h at 0.30 pp/h, then a late burst at 2.5 pp/h. It closes at 76.6%,
  # so the realised strand is 23.4 pp. Read 96 h out, the nowcast has seen only the slow pace and
  # projects ~49.6 pp — a +26 pp error. THAT is the point: at the last sample the same arithmetic
  # would have been exactly right, which is why the old score could not fail.
  run python3 -c "$LOAD$STRAND_SCORE_LOAD"'
sam = window("next3", NOW - 2 * 3600.0, [(156.0, 0.30), (11.9, 2.5)])
sc = ca.strand_score(sam, now=NOW)
assert sc["windows"] == 1, sc
by = {b["h"]: b for b in sc["buckets"]}
for h in (96.0, 48.0, 24.0, 12.0, 6.0):
    assert by[h]["n"] == 1, (h, by[h])            # every bucket has an evaluable cell
assert 20.0 < by[96.0]["bias"] < 32.0, by[96.0]   # measured +25.90
assert by[96.0]["mae"] == abs(by[96.0]["bias"]), by[96.0]
# ...and it CONVERGES as the horizon closes, which is the estimator being what it is sold as:
# a good nowcaster precisely because it is a bad forecaster (§5.1 LB-2).
assert by[6.0]["bias"] < by[96.0]["bias"] / 3.0, (by[6.0], by[96.0])
lines = ca.render_strand_score(sc)
assert "1 CLOSED weekly window" in lines[0], lines
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32 CONTROL: the harness is CAUSAL — it cannot see the burn that came after the cell" {
  # burn_wk_ewma_ph filters by lookback, not by DIRECTION. Handing it the whole series would let
  # a 12 h cell average over the late burst it is supposed to be blind to, the projection would
  # already know the answer, and the bias would collapse toward zero — the tautology rebuilt one
  # layer down. This case computes both and asserts they DIFFER, so a future edit that drops the
  # slice cannot pass.
  run python3 -c "$LOAD$STRAND_SCORE_LOAD"'
reset_t = NOW - 2 * 3600.0
sam = window("next3", reset_t, [(156.0, 0.30), (11.9, 2.5)])
cell = [c for c in ca.strand_score(sam, now=NOW)["buckets"] if c["h"] == 12.0][0]["cells"][0]
# the same cell scored NON-causally: every sample, including the ones after this instant
peek_e = [e for e in sam if e["_t"] == cell["at_t"]][0]
ewma, _ = ca.burn_wk_ewma_ph(sam, peek_e["_t"], cell["at_h"])
peek = ca.wk_strand_pp({"weekly_pct": peek_e["weekly_pct"], "weekly_reset_h": cell["at_h"],
                        "burn_wk_ewma_ph": ewma})
assert abs(peek - cell["realised"]) < abs(cell["projected"] - cell["realised"]), (peek, cell)
assert abs(peek - cell["projected"]) > 1.0, (peek, cell)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33 CONTROL: an unevaluable cell is EXCLUDED, never imputed and never counted as a hit" {
  # A window observed only over its last 20 h has no sample 96/48/24 h before its reset. L2
  # says those cells report nothing; imputing a zero would credit the projector with three
  # perfect calls it never made, and a mean over imputed zeros is the vacuous pass again.
  run python3 -c "$LOAD$STRAND_SCORE_LOAD"'
reset_t = NOW - 2 * 3600.0
sam = [e for e in window("next3", reset_t, [(156.0, 0.30), (11.9, 2.5)])
       if (reset_t - e["_t"]) / 3600.0 <= 20.0]
sc = ca.strand_score(sam, now=NOW)
by = {b["h"]: b for b in sc["buckets"]}
assert sc["windows"] == 1, sc                      # the window itself IS still closed+observed
for h in (96.0, 48.0, 24.0):
    assert by[h]["n"] == 0, (h, by[h])
    assert by[h]["bias"] is None and by[h]["mae"] is None, by[h]
for h in (12.0, 6.0):
    assert by[h]["n"] == 1, (h, by[h])             # CONTROL: the horizons it CAN answer
empty = [l for l in ca.render_strand_score(sc) if "96h" in l][0]
assert "no evaluable sample" in empty, empty       # the emptiness is printed, not dashed away
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-34 CONTROL: the LIVE window is never scored — it has no realised strand yet" {
  # completed_weekly_windows already refuses it (RP-9), and this is that refusal seen from the
  # consumer that would otherwise publish an error against a number that does not exist.
  run python3 -c "$LOAD$STRAND_SCORE_LOAD"'
live = window("next3", NOW + 24 * 3600.0, [(140.0, 0.30)])
sc = ca.strand_score(live, now=NOW)
assert sc["windows"] == 0, sc
assert all(b["n"] == 0 for b in sc["buckets"]), sc
# CONTROL: the same shape with its reset in the PAST scores normally, so this is the live-window
# rule firing and not an always-empty harness.
closed = window("next3", NOW - 2 * 3600.0, [(166.0, 0.30)])
assert ca.strand_score(closed, now=NOW)["windows"] == 1
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-35: agree grades the BINARY question, never the sign of a clamped quantity" {
  # wk_strand_pp is clamped at zero, so a signed strand has no negative branch and a naive
  # sign-agreement rate reads 100% by construction — the same defect as the old score. `agree`
  # asks what the planner acts on: does this window strand at all? A window that filled to 100%
  # while the nowcast said pp would die is a DISAGREEMENT, and must score as one.
  run python3 -c "$LOAD$STRAND_SCORE_LOAD"'
# 156 h at 0.30 (=46.8 pp), then a burst that takes it to exactly 100: realised strand 0.
sam = window("next3", NOW - 2 * 3600.0, [(156.0, 0.30), (11.9, 4.5)])
sc = ca.strand_score(sam, now=NOW)
by = {b["h"]: b for b in sc["buckets"]}
assert by[96.0]["cells"][0]["realised"] < 0.5, by[96.0]["cells"][0]   # it did NOT strand
assert by[96.0]["cells"][0]["projected"] > 0.5, by[96.0]["cells"][0]  # ...but the nowcast said it would
assert by[96.0]["agree"] == 0.0, by[96.0]
# CONTROL: the window that DID strand agrees at the same horizon, so agree is not always 0.
did = ca.strand_score(window("next3", NOW - 2 * 3600.0, [(156.0, 0.30), (11.9, 2.5)]), now=NOW)
assert [b for b in did["buckets"] if b["h"] == 96.0][0]["agree"] == 1.0, did
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-36: --strand-score answers without a config, and exits 3 when it can measure NOTHING" {
  # Two properties in one run. (a) The branch returns before load_cfg(), like --agents: HOME is
  # fixtured and there is no accounts.json, so a branch placed after load_cfg() would exit
  # non-zero for the wrong reason. (b) An empty series exits 3, NEVER 0 — a harness whose every
  # cell is empty and whose exit code says success is the vacuous pass this suite exists to stop.
  : > "$CC_UTIL_LOG"
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 3 ] || { echo "status=$status"; echo "$output"; false; }
  [[ "$output" == *"no evaluable sample"* ]] || { echo "$output"; false; }
  [[ "$output" == *"0 CLOSED weekly window"* ]] || { echo "$output"; false; }
  # CONTROL: with real closed windows in the series the SAME command exits 0 and reports cells.
  python3 -c "$LOAD$STRAND_SCORE_LOAD"'
import json
with open(os.environ["CC_UTIL_LOG"], "w") as f:
    for e in window("next3", NOW - 2 * 3600.0, [(156.0, 0.30), (11.9, 2.5)], step_h=0.5):
        f.write(json.dumps({"ts": iso(e["_t"]), "acct": e["acct"],
                            "session_pct": e["session_pct"], "weekly_pct": e["weekly_pct"],
                            "session_reset_at": e["session_reset_at"],
                            "weekly_reset_at": e["weekly_reset_at"]}) + chr(10))'
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "status=$status"; echo "$output"; false; }
  [[ "$output" == *"1 CLOSED weekly window"* ]] || { echo "$output"; false; }
}
