#!/usr/bin/env bats
# strand_score — M3c, the instrument that CAN fail. USAGE_TELEMETRY_100P §5.2 S5,
# RED-proof cases RP-31..RP-35.
#
# WHAT IT REPLACES. The synthesis scored the strand rule on 8 binary cells evaluated at the
# horizon's CLOSE, where the projection has already converged to `100 - weekly_pct` — i.e. to the
# true strand. It agreed with the identity function on 8/8 windows and published `4/4 recall,
# 0 FP, ~20 h median lead` off that agreement. Scoring at FIXED distances from the reset instead
# puts the projection where it can be, and will be, wrong.
#
# RP-32 IS THE CASE THE WHOLE FILE EXISTS FOR. burn_wk_ewma_ph filters on its lookback but NOT on
# the future: handed the full series with now=t_eval it weights samples that had not happened yet,
# and because its 48 h lookback then reaches the end-of-window burst, a 96 h-out projection comes
# out nearly exact. That is the same tautology in a second costume. The truncation is one line of
# code and it is the only thing separating this harness from the one it replaced.
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
STEP_H = 0.1                     # 6 min, the series cadence
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")

def window(acct, reset_ago_h, segments, observe_from_h=None):
    """One weekly window that CLOSED reset_ago_h hours ago.

    segments = [(hours, pp_per_h), ...] walked forward from the window OPENING. The series stops
    at the reset (completed_weekly_windows wants the last sample within WEEKLY_TAIL_GAP_H of it).
    observe_from_h truncates the OBSERVATION to the last N hours before the reset, which is how a
    bucket is starved of an evaluable sample without changing the window itself."""
    reset_t = NOW - reset_ago_h * 3600.0
    total = sum(s[0] for s in segments)
    out, t, wp = [], 0.0, 0.0
    for hours, rate in segments:
        n = int(round(hours / STEP_H))
        for _ in range(n):
            ts = reset_t - (total - t) * 3600.0
            if observe_from_h is None or (reset_t - ts) / 3600.0 <= observe_from_h:
                out.append({"acct": acct, "weekly_pct": min(100.0, wp), "session_pct": 10,
                            "_t": ts, "weekly_reset_at": iso(reset_t),
                            "session_reset_at": iso(ts + 3 * 3600.0)})
            wp += rate * STEP_H
            t += STEP_H
    return out
'

@test "RP-31: strand_score scores CLOSED windows at fixed horizons, and it can be WRONG" {
  # A 168 h window that idles at 0.10 pp/h for 140 h and then bursts at 2.0 pp/h for the last 28 h,
  # closing at 70 pp: realised strand 30 pp. At 96 h out the pace is the idle rate, so the
  # projection is near-total loss; at 6 h out the EWMA has the burst and the projection is close.
  # A harness that could not be wrong would report the same error at both.
  run python3 -c "$LOAD"'
sam = window("next3", 3.0, [(140.0, 0.10), (28.0, 2.0)])
res = ca.strand_score(sam)
assert res["windows"] == 1, res
b = {x["h"]: x for x in res["buckets"]}
for h in (96.0, 48.0, 24.0, 12.0, 6.0):
    assert b[h]["n"] == 1, (h, b[h])
# it is WRONG at long horizon and much closer at short horizon -- the whole point
assert abs(b[96.0]["bias"]) > 5.0, b[96.0]
assert abs(b[6.0]["bias"]) < abs(b[96.0]["bias"]) / 2.0, (b[96.0], b[6.0])
assert b[96.0]["mae"] == abs(b[96.0]["bias"]), b[96.0]      # n=1: MAE is |bias|
# ...and the realised strand is the window fact, identical in every bucket
for h in b:
    assert abs(b[h]["cells"][0]["realised"] - 30.0) < 1.0, b[h]["cells"]
assert res["material_pp"] == 4.0, res
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32 CONTROL: the EWMA at horizon H is CAUSAL — it never sees past the evaluation instant" {
  # THE MUTANT THIS FILE EXISTS FOR. burn_wk_ewma_ph filters on its 48 h lookback, not on the
  # future. Handed the full series it weights samples that had not happened yet, and at 96 h out
  # that lookback reaches the end-of-window burst, so the projection comes out nearly exact --
  # the tautology the old score already died of, wearing a second costume.
  #
  # Two arms. (a) the value the harness produces at 96 h equals the one computed from a
  # HAND-TRUNCATED series, to the float. (b) the acausal value is materially different, so arm (a)
  # is not satisfied by an implementation where truncation happens to be a no-op.
  run python3 -c "$LOAD"'
sam = window("next3", 3.0, [(140.0, 0.10), (28.0, 2.0)])
res = ca.strand_score(sam, buckets=(96.0,))
cell = res["buckets"][0]["cells"][0]
reset_t = max(e["_t"] for e in sam) + 3.0 * 3600.0
reset_t = ca._reset_key(sam[0]["weekly_reset_at"]) * 60.0
ev = [e for e in sam if (reset_t - e["_t"]) / 3600.0 >= 96.0]
s = max(ev, key=lambda e: e["_t"])
wrh = (reset_t - s["_t"]) / 3600.0
causal = [e for e in sam if e["_t"] <= s["_t"]]
ck, _ = ca.burn_wk_ewma_ph(causal, s["_t"], wrh)
want = ca.wk_strand_pp({"weekly_pct": s["weekly_pct"], "weekly_reset_h": wrh,
                        "burn_wk_ewma_ph": ck})
assert abs(cell["projected"] - want) < 1e-9, (cell["projected"], want)
# (b) the ACAUSAL number is a different number, so (a) is not vacuous
ak, _ = ca.burn_wk_ewma_ph(sam, s["_t"], wrh)
acausal = ca.wk_strand_pp({"weekly_pct": s["weekly_pct"], "weekly_reset_h": wrh,
                           "burn_wk_ewma_ph": ak})
assert abs(acausal - want) > 5.0, (acausal, want)
assert ak > ck, (ak, ck)          # the future burst inflates the rate it must not see
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33 CONTROL: a cell with no evaluable sample reports n=0 — never imputed, never a hit" {
  # A window observed only over its last 20 h. The 96/48/24 h buckets have no sample at that
  # distance and must contribute NOTHING; the 12 h and 6 h buckets do and must report. Imputing
  # the missing cells -- or counting them as agreements -- manufactures exactly the 8/8 the old
  # score published.
  run python3 -c "$LOAD"'
sam = window("next3", 3.0, [(140.0, 0.10), (28.0, 2.0)], observe_from_h=20.0)
res = ca.strand_score(sam)
b = {x["h"]: x for x in res["buckets"]}
for h in (96.0, 48.0, 24.0):
    assert b[h]["n"] == 0, (h, b[h])
    assert b[h]["bias"] is None and b[h]["mae"] is None and b[h]["agree"] is None, b[h]
    assert b[h]["cells"] == [], b[h]
for h in (12.0, 6.0):                           # CONTROL: the arms that CAN report, do
    assert b[h]["n"] == 1, (h, b[h])
    assert b[h]["bias"] is not None, (h, b[h])
# ...and an empty bucket renders as a dash, never as 0.0 -- a 0.0 reads as a perfect estimator
out = ca.render_strand_score(res)
assert "    96h    0        —        —        —" in out, out
assert "0.00" not in out.split(chr(10))[4], out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-34 CONTROL: only COMPLETED windows are scored — the LIVE one is excluded" {
  # It reuses completed_weekly_windows (S1d) rather than re-implementing the rule, because the
  # naive gap-only test ADMITS the currently-live window: a live window's newest sample is always
  # some hours before its own reset. Admitting it scores a projection against a strand that has
  # not happened.
  run python3 -c "$LOAD"'
closed = window("next3", 3.0, [(140.0, 0.10), (28.0, 2.0)])
live = [dict(e, weekly_reset_at=ca.datetime.fromtimestamp(NOW + 40 * 3600.0,
                                                          ca.timezone.utc).isoformat(),
             _t=NOW - (40 - i * 0.5) * 3600.0, weekly_pct=i * 1.0)
        for i, e in enumerate(closed[:80])]
res = ca.strand_score(closed + live)
assert res["windows"] == 1, res                    # the live window is NOT a window to score
for x in res["buckets"]:
    for c in x["cells"]:
        assert abs(c["realised"] - 30.0) < 1.0, c  # every cell belongs to the CLOSED window
# CONTROL: with NO closed window at all there is nothing to score, and it says so rather than
# reporting a table of zeroes.
empty = ca.strand_score(live)
assert empty["windows"] == 0, empty
assert all(x["n"] == 0 for x in empty["buckets"]), empty
assert "NO SCORED CELLS" in ca.render_strand_score(empty)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-35: agreement is scored at S6's MATERIAL FLOOR, not on the sign of a clamped quantity" {
  # wk_strand_pp clamps at zero, so projected and realised are both non-negative and their signs
  # agree unconditionally -- a 100% agreement rate that is a property of the clamp, not of the
  # estimator. The falsifiable binary underneath S6 is whether a MATERIAL strand happens, at
  # exactly the floor S6 fires on. Two windows, one that strands 30 pp and one that fills, scored
  # at a horizon where the projection calls the second one wrong.
  run python3 -c "$LOAD"'
stranded = window("next3", 3.0, [(140.0, 0.10), (28.0, 2.0)])         # closes at 70 -> 30 pp dies
filled = window("next4", 5.0, [(140.0, 0.10), (28.0, 3.07)])          # closes at ~100 -> 0 dies
res = ca.strand_score(stranded + filled, buckets=(96.0, 6.0))
b = {x["h"]: x for x in res["buckets"]}
assert res["windows"] == 2, res
assert b[96.0]["n"] == 2 and b[6.0]["n"] == 2, res
# at 96 h out BOTH read as heading for a large strand, so the filled account is called WRONG:
# agreement is 1 of 2, i.e. a rate that is neither 0 nor 1 and could have been either.
assert b[96.0]["agree"] == 0.5, b[96.0]["cells"]
# ...and by 6 h out the burst is in the EWMA and both are called right.
assert b[6.0]["agree"] == 1.0, b[6.0]["cells"]
# the floor is the KNOB, not decoration: lift it above BOTH the projection and the realised
# strand and the 96 h disagreement disappears, which pins that the comparison is against
# STRAND_MATERIAL_PP and not a hardcoded 0.
ca.STRAND_MATERIAL_PP = 200.0
hi = ca.strand_score(stranded + filled, buckets=(96.0,))
assert hi["buckets"][0]["n"] == 2, hi["buckets"][0]
assert hi["buckets"][0]["agree"] == 1.0, hi["buckets"][0]["cells"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-36: --strand-score answers with NO keychain, NO sweep and NO accounts.json" {
  # Same placement argument as --agents: this branch returns before load_cfg(). $HOME is fixtured
  # and holds no accounts.json, and the usage endpoint is unreachable -- if the flag were parsed
  # after load_cfg() this would exit non-zero, which is exactly how the --agents coupling was
  # found. The series is the ONLY input.
  python3 - <<'PY'
import json, os, time
from datetime import datetime, timezone
now = time.time()
reset_t = now - 3 * 3600.0
rows = []
wp = 0.0
for i in range(1680):                       # 168 h at 6 min
    t = reset_t - (168.0 - i * 0.1) * 3600.0
    rows.append({"ts": datetime.fromtimestamp(t, timezone.utc).isoformat(),
                 "acct": "next3", "session_pct": 10, "weekly_pct": min(100.0, wp),
                 "session_reset_at": None,
                 "weekly_reset_at": datetime.fromtimestamp(reset_t, timezone.utc).isoformat()})
    wp += (0.10 if i < 1400 else 2.0) * 0.1
with open(os.environ["CC_UTIL_LOG"], "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
PY
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"strand-score"* ]] || { echo "$output"; false; }
  [[ "$output" == *"1 window(s) scored"* ]] || { echo "$output"; false; }
  # §5.4 acceptance item 2: non-zero n in at least the 24/12/6 h buckets, and a bias that COULD
  # have been non-zero. A table whose every cell reads 0.0 is the tautology all over again.
  [[ "$output" != *"NO SCORED CELLS"* ]] || { echo "$output"; false; }
  run python3 "$CA_BIN" --strand-score --json
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  run python3 -c '
import json, sys
d = json.load(sys.stdin)
b = {x["h"]: x for x in d["buckets"]}
for h in (24.0, 12.0, 6.0):
    assert b[h]["n"] >= 1, (h, b[h])
    assert b[h]["bias"] is not None, (h, b[h])
assert any(abs(b[h]["bias"]) > 0.01 for h in b if b[h]["n"]), d   # it CAN be non-zero, and is
print("OK")' <<< "$output"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
