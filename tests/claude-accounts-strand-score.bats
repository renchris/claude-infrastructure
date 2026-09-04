#!/usr/bin/env bats
# strand_score / --strand-score — M3c, the instrument that CAN fail.
# USAGE_TELEMETRY_100P §5.2 S5, RED-proof cases RP-29..RP-33.
#
# WHAT IT REPLACES. The synthesis scored the strand alarm on 8 binary cells evaluated at the
# horizon's CLOSE — the instant at which `100 - (weekly_pct + burn * weekly_reset_h)` has already
# converged to `100 - weekly_pct`, i.e. to the realised strand itself. A projector cannot lose
# against the identity function at the moment it BECOMES the identity function, and it duly
# scored 8/8. That is a tautology, not a validation, and it is the refutation that demoted M3b
# to "do not build until S5 has been run and read".
#
# THE TWO PROPERTIES THAT KEEP THIS FROM BECOMING THE SAME TAUTOLOGY are each pinned by their own
# CONTROL below, because both fail SILENTLY — a harness with either defect prints a beautiful
# table of small errors:
#   RP-31  CAUSAL — the EWMA at a cell sees only samples at or before the projection instant.
#   RP-32  REPLAYS THE REAL ARTIFACT — it feeds the estimator the account's whole series, the way
#          apply_burn does, not a pre-filtered single-window slice.
#
# Hermetic: $HOME, $CLAUDE_CONFIG_DIR and the series path all inside BATS_TEST_TMPDIR.

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
STEP_H = 0.5                         # the series cadence used by these fixtures
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")

def window(reset_ago_h, rate_pph, acct="next3", span_h=168.0, start_pct=0.0, cap=100.0):
    """One weekly window burning at a constant rate, sampled every STEP_H up to its own reset.
    reset_ago_h hours ago is the reset, so the window is CLOSED and observed to its close."""
    reset_t = round((NOW - reset_ago_h * 3600.0) / 60.0) * 60.0   # _reset_key rounds to the
                                       # minute, and completed_weekly_windows measures the tail
                                       # gap against that ROUNDED instant: an unaligned fixture
                                       # reset can put its own last sample 30s AFTER it and be
                                       # rejected for a negative gap.
    out, wp = [], start_pct
    n = int(span_h / STEP_H)
    for i in range(n, -1, -1):
        t = reset_t - i * STEP_H * 3600.0
        out.append({"acct": acct, "weekly_pct": min(cap, wp), "session_pct": 10, "_t": t,
                    "weekly_reset_at": iso(reset_t), "session_reset_at": iso(t + 3 * 3600.0)})
        wp += rate_pph * STEP_H
    return out

def write(sam, path=None):
    path = path or os.environ["CC_UTIL_LOG"]
    with open(path, "w") as f:
        for e in sorted(sam, key=lambda x: x["_t"]):
            d = dict(e); d["ts"] = iso(d.pop("_t"))
            f.write(json.dumps(d) + "\n")
    return path
'

@test "RP-29: strand_score scores every (window, horizon) cell, and the cells are NOT the close" {
  # Two closed windows, both burning steadily to ~84%: the realised strand is ~16 pp. At each
  # horizon the projector sees the same constant rate, so it nowcasts ~16 pp too — small errors,
  # which is the CORRECT answer for a constant-rate fixture and is exactly why RP-30 exists.
  # What this case pins is the SHAPE: 5 buckets, cells at fixed distances from the reset, and
  # every bucket carrying evaluable n.
  run python3 -c "$LOAD"'
sam = window(10.0, 0.5, acct="next3") + window(180.0, 0.5, acct="next4")
sc = ca.strand_score(sam, now=NOW)
assert sc["windows"] == 2, sc["windows"]
assert sc["accts"] == 2, sc["accts"]
assert len(sc["buckets"]) == 5, sc["buckets"]
assert [b["h"] for b in sc["buckets"]] == [96.0, 48.0, 24.0, 12.0, 6.0], sc["buckets"]
assert len(sc["cells"]) == 10, len(sc["cells"])
for b in sc["buckets"]:
    assert b["n"] == 2, b               # every cell evaluable on a full-span fixture
    assert b["possible"] == 2, b
    assert abs(b["bias"]) < 4.0, b      # a constant rate IS well nowcast; RP-30 breaks it
    assert b["agree"] == 1.0, b
# the cell is taken at the LAST sample still >= H from the reset, never at the close: the 96h
# bucket must be evaluated ~96h out, not ~0h out. That is the whole difference from the old score.
for c in sc["cells"]:
    assert c["at_h"] >= c["h"], c              # evaluated at least H hours OUT from the reset...
    assert c["at_h"] < c["h"] + STEP_H + 1e-9, c   # ...and at the LAST such sample, not earlier
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-30 CONTROL: the harness CAN report a large error — it is not scoring the identity" {
  # THE CASE THE OLD SCORE COULD NOT FAIL. This window loafs for six days and then bursts: at
  # 96h out the projector sees the loafing rate and nowcasts a huge strand, and the window in
  # fact closes near 100 with almost nothing stranded. A far-horizon bias of tens of pp is the
  # TRUE property of this estimator (§5.1 LB-2 killed it as a forecaster for exactly this), so a
  # harness that reports ~0 everywhere is measuring hindsight, not the instrument.
  run python3 -c "$LOAD"'
reset_t = round((NOW - 10 * 3600.0) / 60.0) * 60.0
sam, wp = [], 0.0
for i in range(336, -1, -1):                       # 168h at 0.5h steps
    t = reset_t - i * STEP_H * 3600.0
    h_left = i * STEP_H
    sam.append({"acct": "next3", "weekly_pct": min(100.0, wp), "session_pct": 10, "_t": t,
                "weekly_reset_at": iso(reset_t), "session_reset_at": iso(t + 3 * 3600.0)})
    wp += (0.08 if h_left > 24.0 else 3.6) * STEP_H       # loaf, then BURST in the last day
sc = ca.strand_score(sam, now=NOW)
assert sc["windows"] == 1, sc
w = ca.completed_weekly_windows(sam, now=NOW)[0]
assert w["strand"] < 5.0, w                         # it very nearly filled the window
far = [b for b in sc["buckets"] if b["h"] == 96.0][0]
near = [b for b in sc["buckets"] if b["h"] == 6.0][0]
assert far["n"] == 1 and near["n"] == 1, (far, near)
assert far["bias"] > 25.0, far                      # the far horizon is BADLY wrong, and says so
assert far["mae"] > 25.0, far
assert far["agree"] == 0.0, far                     # ...and it flips the ALARM, which is the cost:
                                                    # at 96h out it says ">=4pp will die" about a
                                                    # window that in fact stranded ~2. That is the
                                                    # exact decision S6 is gated on.
assert near["mae"] < far["mae"] / 2.0, (near, far)  # it converges as the horizon closes
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31 CONTROL: the score is CAUSAL — a cell cannot see a sample from after its own instant" {
  # A harness that hands burn_wk_ewma_ph the whole series measures hindsight and prints a
  # flattering table. Proof by construction: truncating the series AT the 24h cell'"'"'s instant must
  # not move that cell at all. If future samples were leaking in, deleting them would.
  run python3 -c "$LOAD"'
reset_t = round((NOW - 10 * 3600.0) / 60.0) * 60.0
sam, wp = [], 0.0
for i in range(336, -1, -1):
    t = reset_t - i * STEP_H * 3600.0
    h_left = i * STEP_H
    sam.append({"acct": "next3", "weekly_pct": min(100.0, wp), "session_pct": 10, "_t": t,
                "weekly_reset_at": iso(reset_t), "session_reset_at": iso(t + 3 * 3600.0)})
    wp += (0.08 if h_left > 24.0 else 3.6) * STEP_H
full = [c for c in ca.strand_score(sam, now=NOW)["cells"] if c["h"] == 24.0][0]
assert full["projected"] is not None, full
cut_t = reset_t - 24.0 * 3600.0
trunc = [e for e in sam if e["_t"] <= cut_t]
# the truncated series no longer CLOSES the window (no sample within WEEKLY_TAIL_GAP_H of the
# reset), so score it against the projector directly at the same instant instead.
e = trunc[-1]
v, _sp = ca.burn_wk_ewma_ph(trunc, e["_t"], 24.0)
p = ca.wk_strand_pp({"weekly_pct": e["weekly_pct"], "weekly_reset_h": 24.0,
                     "burn_wk_ewma_ph": v})
assert abs(p - full["projected"]) < 1e-6, (p, full["projected"])
# ...and the MUTANT: the non-causal form (the whole series, including the burst that has not
# happened yet at the 24h mark) gives a MATERIALLY different answer. Without this the case above
# would pass vacuously on a fixture where past and future happen to agree.
v_hind, _ = ca.burn_wk_ewma_ph(sam, e["_t"], 24.0)
p_hind = ca.wk_strand_pp({"weekly_pct": e["weekly_pct"], "weekly_reset_h": 24.0,
                          "burn_wk_ewma_ph": v_hind})
assert abs(p_hind - full["projected"]) > 5.0, (p_hind, full["projected"])
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32 CONTROL: an unevaluable cell is EXCLUDED with its reason, never imputed as a hit" {
  # L2, and the specific failure it prevents: imputing a missing cell as zero error is how a
  # harness reports bias 0.00 in every bucket and calls it agreement. A window whose series
  # starts 30h before its reset has NO sample at 96h or 48h out — those cells must report n=0
  # with a reason, and must not enter any aggregate.
  run python3 -c "$LOAD"'
sam = window(10.0, 0.5, acct="next3", span_h=40.0, start_pct=60.0)
sc = ca.strand_score(sam, now=NOW)
assert sc["windows"] == 1, sc
by = {b["h"]: b for b in sc["buckets"]}
assert by[96.0]["n"] == 0 and by[96.0]["bias"] is None, by[96.0]
assert by[48.0]["n"] == 0 and by[48.0]["mae"] is None, by[48.0]
assert by[24.0]["n"] == 1, by[24.0]                    # 40h of history DOES reach 24h out
                                                       # with enough span left for the EWMA
assert by[6.0]["n"] == 1, by[6.0]
for h in (96.0, 48.0):
    c = [x for x in sc["cells"] if x["h"] == h][0]
    assert c["err"] is None and c["why"], c            # the reason travels WITH the exclusion
assert by[96.0]["possible"] == 1, by[96.0]             # possible counts it; n does not
# ...and the abstain is not "n=0 for every fixture": a full-span window fills all five.
full = ca.strand_score(window(10.0, 0.5, acct="next3"), now=NOW)
assert all(b["n"] == 1 for b in full["buckets"]), full["buckets"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33: --strand-score answers with NO keychain, NO sweep and NO accounts.json" {
  # Placed before load_cfg() for the same reason --agents is. $HOME is fixtured and there is no
  # accounts.json at all; a branch sited after load_cfg() exits non-zero here, which is exactly
  # how the hermetic --agents test found that coupling.
  python3 -c "$LOAD"'
sam = window(10.0, 0.5, acct="next3") + window(180.0, 0.5, acct="next4")
write(sam)
print("wrote", len(sam))'
  run python3 "$CA_BIN" --strand-score --hours 1008
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"horizon-stratified error over 2 completed weekly window(s)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"96h"* && "$output" == *"12h"* && "$output" == *"6h"* ]] || { echo "$output"; false; }
  # §5.4 acceptance 2: non-zero n at 24h, 12h and 6h, and a bias that COULD have been non-zero.
  # A table whose every cell reads "no evaluable cell" is the tautology all over again.
  [[ "$output" != *"no evaluable cell"* ]] || { echo "$output"; false; }
  run python3 "$CA_BIN" --strand-score --hours 1008 --json
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  run python3 - <<PY
import json, subprocess, os
out = subprocess.run(["python3", os.environ["CA_BIN"], "--strand-score", "--hours", "1008",
                      "--json"], capture_output=True, text=True)
d = json.loads(out.stdout)
assert d["windows"] == 2, d["windows"]
by = {b["h"]: b for b in d["buckets"]}
for h in (24.0, 12.0, 6.0):
    assert by[h]["n"] > 0, (h, by[h])
assert len(d["cells"]) == 10, len(d["cells"])
print("OK")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
  # an EMPTY series is an abstain with its reason, never an empty table read as agreement
  : > "$CC_UTIL_LOG"
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"Nothing to score"* ]] || { echo "$output"; false; }
}
