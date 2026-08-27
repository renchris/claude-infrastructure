#!/usr/bin/env bats
# strand_score — the weekly-drain planner's own mutation test. USAGE_TELEMETRY_100P §5.2 S5 (M3c),
# RED-proof cases RP-28..RP-32.
#
# WHAT MAKES THIS WORTH BUILDING, and it is the ONLY thing that does. The synthesis's score was
# evaluated at each window's LAST sample, where the projection has already converged to
# `100 - weekly_pct` — i.e. to the realised strand itself — so it agreed with the identity function
# on 8/8 windows and COULD NOT have disagreed. This walks a fixed distance from the reset instead,
# where the projection can be, and will be, wrong. RP-30 is that property as an assertion: a real
# error, with the right sign, on a window whose pace changed after the evaluation instant.
#
# THE FAILURE THIS SUITE EXISTS TO CATCH IS THE HARNESS PEEKING. Replaying M3a at a past instant
# means every later sample in the series is a FUTURE sample, and an estimator handed the whole
# series would read the outcome it is supposed to be predicting. RP-31 pins that at both layers.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; the CLI case writes its own series.

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
STEP_H = 0.1
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")

def window(acct, closed_h_ago, span_h, rate_pph, tail=None):
    """One CLOSED weekly window: samples every 6 min from `span_h` before its reset up to the
    reset itself (so completed_weekly_windows sees a tail inside WEEKLY_TAIL_GAP_H), accruing at
    rate_pph. `tail` = (hours_before_reset, other_rate) switches the pace for the final stretch,
    which is what makes an early projection WRONG rather than merely early."""
    reset_t = NOW - closed_h_ago * 3600.0
    out, wp = [], 0.0
    n = int(round(span_h / STEP_H))
    for i in range(n + 1):
        h_left = span_h - i * STEP_H
        out.append({"acct": acct, "_t": reset_t - h_left * 3600.0,
                    "weekly_pct": round(wp, 4), "session_pct": 10,
                    "session_reset_at": iso(NOW + 3 * 3600.0),
                    "weekly_reset_at": iso(reset_t)})
        r = rate_pph
        if tail is not None and h_left <= tail[0]:
            r = tail[1]
        wp += r * STEP_H
    return out
'

@test "RP-28: strand_score scores every horizon bucket, and a bucket with no sample that far out abstains" {
  # A 120 h window closing 10 h ago at a flat 0.5 pp/h => it ends at 60% and strands 40 pp. Every
  # bucket at or inside 96 h has an evaluable sample; there is deliberately nothing older, so the
  # harness must report n=0 there rather than reaching for the nearest sample it can find.
  run python3 -c "$LOAD"'
sam = window("next3", 10.0, 120.0, 0.5)
buckets = ca.strand_score(sam, now=NOW)
by = {b["h"]: b for b in buckets}
assert sorted(by) == [6.0, 12.0, 24.0, 48.0, 96.0], sorted(by)
for h in (6.0, 12.0, 24.0, 48.0, 96.0):
    assert by[h]["n"] == 1, (h, by[h])
    assert by[h]["cells"][0]["at_reset_h"] >= h, (h, by[h]["cells"])
# a flat window is nowcast almost exactly: 60 + 0.5*h_left lands on 100 - 40 at every horizon
for h in (6.0, 12.0, 24.0, 48.0, 96.0):
    assert abs(by[h]["bias"]) < 1.0, (h, by[h])
    assert by[h]["agree"] == 100.0, (h, by[h])
# ...and a horizon the series cannot reach is n=0 with NULL statistics, never a scored zero. The
# reachable arm is 110 h and not 119: at T−119h the window is one hour old, M3a is below its own
# 6.8 h measured-span floor, and that abstain is a SECOND reason for an empty cell — a case that
# cannot tell the two apart proves nothing about either.
far = ca.strand_score(sam, buckets=(110.0, 130.0), now=NOW)
assert far[0]["n"] == 1, far[0]
assert far[1]["n"] == 0 and far[1]["bias"] is None and far[1]["mae"] is None, far[1]
assert far[1]["agree"] is None, far[1]
# the floor abstain is real too, and it is EXCLUDED rather than scored
assert ca.strand_score(sam, buckets=(119.0,), now=NOW)[0]["n"] == 0
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-29 CONTROL: only CLOSED windows are scored, and the LIVE one is never among them" {
  # The S1d rule is the foundation this whole harness stands on: a detector for "the window ended"
  # that fires DURING the window admits the live window's current level as a realised strand. The
  # naive gap-only rule reported 51 pp over 9 account-weeks; the fixed one reports 43 over 8.
  run python3 -c "$LOAD"'
live = window("next2", -60.0, 100.0, 0.5)      # reset 60 h in the FUTURE
live = [e for e in live if e["_t"] <= NOW]     # ...so only its past half exists
closed = window("next3", 10.0, 120.0, 0.5)
assert len(ca.completed_weekly_windows(live, now=NOW)) == 0
b = ca.strand_score(live + closed, now=NOW)
by = {x["h"]: x for x in b}
assert by[24.0]["n"] == 1, by[24.0]
assert all(c["acct"] == "next3" for c in by[24.0]["cells"]), by[24.0]["cells"]
# ...and the CONTROL: two closed windows score two cells, so RP-29 is a filter and not a cap of 1
two = ca.strand_score(closed + window("next4", 30.0, 120.0, 0.4), now=NOW)
assert {x["h"]: x for x in two}[24.0]["n"] == 2, two
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-30: the score CAN be wrong — a window whose pace collapsed late scores a real signed error" {
  # THE WHOLE POINT. A 120 h window that runs its first 24 h at 0.85 pp/h and the remaining 96 h at
  # 0.36, closing near 55% — so ~45 pp die. At T−96h the nowcast still sees the fast pace: 20.4 +
  # 0.85*96 = 102, i.e. it projects the window FILLING and clamps the strand to zero. It is wrong
  # by the entire 45 pp, with a negative bias, and it disagrees with the outcome on the one binary
  # the block actually drives. At T−6h it has converged and is nearly right. A harness that reads
  # 0.0 in every cell is the tautology all over again.
  run python3 -c "$LOAD"'
sam = window("next3", 8.0, 120.0, 0.85, tail=(96.0, 0.36))
by = {b["h"]: b for b in ca.strand_score(sam, now=NOW)}
far, near = by[96.0], by[6.0]
assert far["n"] == 1 and near["n"] == 1, (far, near)
assert far["cells"][0]["projected"] == 0.0, far["cells"]   # it said the window would FILL
assert far["cells"][0]["realised"] > 40.0, far["cells"]
assert far["bias"] < -40.0, far          # projected far less strand than actually died
assert far["mae"] > 40.0, far
assert far["agree"] == 0.0, far          # it said FILL; the window stranded
assert abs(near["bias"]) < 5.0, near     # converged by the last hours
assert near["agree"] == 100.0, near
# ...and the MAE is a magnitude, never a signed mean laundered through a rename
assert far["mae"] >= abs(far["bias"]) - 1e-9, far
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31: the harness CANNOT peek — causality holds at the slice AND inside the estimator" {
  # Replaying M3a at a past instant makes every later sample a FUTURE sample. An estimator handed
  # the whole series reads the outcome it is meant to be predicting, and RP-30 would then pass for
  # the wrong reason — the vacuous pass this suite exists to catch. Two independent guards:
  #  (a) burn_wk_ewma_ph itself refuses samples after `now`;
  #  (b) strand_score slices to `_t <= evaluation instant` before calling it.
  run python3 -c "$LOAD"'
sam = window("next3", 8.0, 120.0, 0.85, tail=(96.0, 0.36))
# (a) the estimator: the same instant, with and without the future half of the series, agrees
mid = NOW - 60.0 * 3600.0
past = [e for e in sam if e["_t"] <= mid]
v_all, sp_all = ca.burn_wk_ewma_ph(sam, mid, 52.0)
v_past, sp_past = ca.burn_wk_ewma_ph(past, mid, 52.0)
assert v_all is not None and v_past is not None, (v_all, v_past)
assert abs(v_all - v_past) < 1e-9, (v_all, v_past)
assert abs(sp_all - sp_past) < 1e-9, (sp_all, sp_past)
# and it is a REFUSAL of the future, not an accident of the lookback: samples strictly after `now`
# are dropped even when they sit well inside 48 h of it.
fut = [e for e in sam if mid < e["_t"] <= mid + 10 * 3600.0]
assert len(fut) > 50, len(fut)
assert abs(ca.burn_wk_ewma_ph(past + fut, mid, 52.0)[0] - v_past) < 1e-9
# (b) the harness slices anyway, so the guard is belt AND braces: RP-30 survives an estimator
# that lost its own filter.
by = {b["h"]: b for b in ca.strand_score(sam, now=NOW)}
assert by[96.0]["agree"] == 0.0, by[96.0]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32: --strand-score answers with no config, no keychain and no sweep, and renders n and bias" {
  # Placed before load_cfg() for the same reason --agents is. A hermetic $HOME has no accounts.json
  # and no keychain; a branch sitting after load_cfg() exits non-zero the moment $HOME is fixtured,
  # which is exactly how that coupling was found the first time.
  local log="$BATS_TEST_TMPDIR/util-series.jsonl"
  python3 -c "$LOAD"'
import json
sam = window("next3", 8.0, 120.0, 0.85, tail=(96.0, 0.36)) + window("next4", 30.0, 120.0, 0.4)
with open(os.environ["BATS_TEST_TMPDIR"] + "/util-series.jsonl", "w") as f:
    for e in sorted(sam, key=lambda x: x["_t"]):
        f.write(json.dumps({"ts": iso(e["_t"]), "acct": e["acct"],
                            "session_pct": e["session_pct"], "weekly_pct": e["weekly_pct"],
                            "session_reset_at": e["session_reset_at"],
                            "weekly_reset_at": e["weekly_reset_at"]}) + "\n")
'
  [ -s "$log" ]
  run env CC_UTIL_LOG="$log" python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"strand-score"* ]] || { echo "$output"; false; }
  [[ "$output" == *"2 completed weekly windows"* ]] || { echo "$output"; false; }
  [[ "$output" == *"T−24h"* ]] || { echo "$output"; false; }
  # §5.4 acceptance 2: NOT "it is accurate" — it is that 24/12/6 carry non-zero n and report a
  # bias that COULD have been non-zero. Every cell reading 0.0 is the tautology all over again.
  run env CC_UTIL_LOG="$log" python3 "$CA_BIN" --strand-score --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
by = {b["h"]: b for b in d["buckets"]}
assert d["windows"] == 2, d["windows"]
for h in (24.0, 12.0, 6.0):
    assert by[h]["n"] > 0, (h, by[h])
assert any(abs(by[h]["bias"]) > 1.0 for h in by if by[h]["n"]), by
print("OK")' <<<"$output"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
