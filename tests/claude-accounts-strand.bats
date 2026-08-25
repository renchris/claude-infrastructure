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
