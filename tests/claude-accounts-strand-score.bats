#!/usr/bin/env bats
# strand_score / --strand-score — the instrument that CAN fail (USAGE_TELEMETRY_100P §5.2 S5 /
# M3c), RED-proof cases RP-34..RP-37.
#
# WHY THIS EXISTS AND WHAT IT REPLACES. The synthesis published `4/4 recall, 0 FP, median ~20 h
# lead` for the strand rule. That harness evaluated the projection at the window's LAST sample,
# where `100 - weekly_pct` has already converged to the true strand — so it agreed with the
# IDENTITY FUNCTION on 8 of 8 windows and could not have disagreed. Eight binary cells, all
# tautological.
#
# This scores ~45 (window, horizon) cells at FIXED DISTANCES from the reset — 96 / 48 / 24 / 12 /
# 6 h out — where the projection has NOT converged and can be, and demonstrably is, wrong.
# RP-35 is the case that makes that claim falsifiable: a decelerating window where the 96 h cell
# is off by ~22 pp and the 6 h cell is not. A harness whose every cell reads 0.0 is the tautology
# all over again, which is why RP-34 (bias ≈ 0 on a truthful series) and RP-35 (bias ≪ 0 on a
# deceptive one) must BOTH hold: either alone is satisfied by a constant.
#
# ACCEPTANCE IS NOT "IT IS ACCURATE." §5.4 is literal: acceptance is that the table has non-zero
# `n` in at least the 24 / 12 / 6 h buckets and reports a bias that COULD have been non-zero.
# Whether the bias is small enough to ship S6's alarm is a question for the live series, not for
# a fixture — and S6 stays unbuilt until that has been run and read.
#
# Hermetic: $HOME, $CLAUDE_CONFIG_DIR and CC_UTIL_LOG into BATS_TEST_TMPDIR.

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
STEP_H = 0.2
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def window(reset_ago_h, segments, acct="next3", start_h=168.0, tail_gap_h=0.4):
    """One WEEKLY window observed to its close. `segments` = [(hours, pp_per_h), ...] walked
    forward from the window opening; sampling stops `tail_gap_h` before the reset so that
    completed_weekly_windows sees it close (its rule is a sample within WEEKLY_TAIL_GAP_H)."""
    reset_t = NOW - reset_ago_h * 3600.0
    open_t = reset_t - start_h * 3600.0
    out, t, wp = [], 0.0, 0.0
    for hours, rate in segments:
        n = int(round(hours / STEP_H))
        for _ in range(n):
            st = open_t + t * 3600.0
            if st > reset_t - tail_gap_h * 3600.0:
                break
            out.append({"acct": acct, "weekly_pct": round(wp, 4), "session_pct": 10.0,
                        "_t": st, "ts": iso(st),
                        "weekly_reset_at": iso(reset_t),
                        "session_reset_at": iso(st + 3 * 3600.0)})
            wp += rate * STEP_H
            t += STEP_H
    return out
def bucket(res, h):
    for b in res["buckets"]:
        if abs(b["h"] - h) < 1e-9:
            return b
    raise AssertionError("no bucket " + str(h) + " in " + str(res["buckets"]))
'

@test "RP-34: strand_score scores completed windows at FIXED horizons, and a truthful series reads ~0" {
  # A window burned at a dead-constant 0.4167 %/h closes at 70% and strands 30 pp. At EVERY
  # horizon the nowcast is exactly right — 100 - (rate*elapsed + rate*reset_h) = 100 - rate*168 —
  # so a correct harness reports a bias near zero with non-zero n in every bucket. This is the
  # arm that pins the ARITHMETIC; RP-35 is the arm that pins that it can be non-zero at all.
  run python3 -c "$LOAD"'
sam = window(20.0, [(168.0, 70.0 / 168.0)]) + window(200.0, [(168.0, 70.0 / 168.0)])
res = ca.strand_score(sam)
assert res["n_windows"] == 2, res["n_windows"]
for h in (96.0, 48.0, 24.0, 12.0, 6.0):
    b = bucket(res, h)
    assert b["n"] == 2, (h, b)
    assert abs(b["bias"]) < 1.0, (h, b)          # the realised strand IS what it nowcast
    assert b["mae"] < 1.0, (h, b)
    assert b["sign_agree"] == 1.0, (h, b)
assert abs(res["overall"]["bias"]) < 1.0, res["overall"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-35: the harness CAN be wrong — a decelerating window is off at 96h and right at 6h" {
  # THE ANTI-TAUTOLOGY CASE, and the one the refuted score could not have produced. 120 h at
  # 0.5 %/h then 48 h at 0.05 %/h: the window closes at 62.4% and strands 37.6 pp.
  #   at the 96 h horizon (72 h elapsed, wp 36, pace 0.5) it nowcasts 100 - (36 + 48) = 16 pp
  #     -> signed error about -21.6 pp: it UNDER-predicts the loss by two thirds.
  #   at the 6 h horizon (162 h elapsed, wp 62.1, pace 0.05) it nowcasts 37.6 pp -> ~0 error.
  # That gradient is the estimator being sold as what it is: a good NOWCASTER precisely because
  # it converges as the horizon closes, which is what makes it a bad forecaster (§5.1 LB-2).
  run python3 -c "$LOAD"'
sam = window(20.0, [(120.0, 0.5), (48.0, 0.05)])
res = ca.strand_score(sam)
far, near = bucket(res, 96.0), bucket(res, 6.0)
assert far["n"] == 1 and near["n"] == 1, (far, near)
assert far["bias"] < -15.0, far                 # NOT zero: the projection has not converged
assert abs(near["bias"]) < 2.0, near            # ...and by 6 h out it has
assert far["mae"] > 15.0 and near["mae"] < 2.0, (far, near)
# the CONVERGENCE is monotone across the grid, which no constant-bias stub reproduces
errs = [abs(bucket(res, h)["bias"]) for h in (96.0, 48.0, 24.0, 12.0, 6.0)]
assert errs == sorted(errs, reverse=True), errs
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-36 CONTROL: a cell with no evaluable sample reports n=0 and is EXCLUDED, never imputed" {
  # §5.2 S5's abstain, and it is the difference between a score and a scoreboard. A window the
  # series only picked up 30 h before its reset has NOTHING to say at the 96 h and 48 h
  # horizons. Counting those as hits — or as zero-error cells — inflates every aggregate above
  # them, which is precisely the failure mode the refuted score had.
  run python3 -c "$LOAD"'
short = window(20.0, [(30.0, 1.0)], start_h=30.0)      # opens 30 h before its own reset
full = window(200.0, [(168.0, 70.0 / 168.0)], acct="next2")
res = ca.strand_score(short + full)
assert res["n_windows"] == 2, res
assert bucket(res, 96.0)["n"] == 1, res  # no SAMPLE that far out: only the full window scores
assert bucket(res, 24.0)["n"] == 1, res  # a sample exists, but M3a cannot SPEAK on 6 h of
                                         # history — the two reasons a cell is non-evaluable are
                                         # different, and both must exclude rather than impute
assert bucket(res, 12.0)["n"] == 2, res  # 18 h of history clears M3a floor: both score
# n=0 is renderable as a state and contributes nothing to the aggregate
lone = ca.strand_score(short)
assert bucket(lone, 96.0)["n"] == 0, lone
assert bucket(lone, 96.0)["bias"] is None, lone       # never 0.0 — abstain, never impute
assert bucket(lone, 96.0)["mae"] is None, lone
assert bucket(lone, 96.0)["sign_agree"] is None, lone
assert bucket(lone, 12.0)["n"] == 1, lone
assert lone["overall"]["n"] == bucket(lone, 12.0)["n"] + bucket(lone, 6.0)["n"], lone
# a LIVE window is not scoreable at all: completed_weekly_windows excludes it, and a harness
# that scored it would be reading its own input back (the identity tautology, again)
assert ca.strand_score(window(-40.0, [(128.0, 0.5)]))["n_windows"] == 0
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-37: --strand-score answers with NO config, NO keychain and NO sweep, and renders the table" {
  # PLACED BEFORE load_cfg(), exactly like --agents. Two reasons and the second is the one that
  # bit --agents: a history question must never block behind (or force) a 4-account sweep, and it
  # must not require a Claude accounts.json to exist at all. $HOME here is an empty tmpdir with
  # no accounts.json, so a branch placed after load_cfg() exits non-zero on this fixture.
  python3 - <<'PY'
import json, os, time
from datetime import datetime, timezone
NOW = time.time()
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
rows = []
for reset_ago_h, acct in ((20.0, "next3"), (190.0, "next3"), (44.0, "next4")):
    reset_t = NOW - reset_ago_h * 3600.0
    open_t = reset_t - 168 * 3600.0
    t, wp = 0.0, 0.0
    while t <= 168.0 - 0.4:
        st = open_t + t * 3600.0
        rows.append({"acct": acct, "weekly_pct": round(wp, 4), "session_pct": 10.0,
                     "ts": iso(st), "weekly_reset_at": iso(reset_t),
                     "session_reset_at": iso(st + 3 * 3600.0)})
        wp += (70.0 / 168.0) * 0.2
        t += 0.2
with open(os.environ["CC_UTIL_LOG"], "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
PY
  [ ! -e "$HOME/.claude/accounts.json" ]
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  [[ "$output" == *"strand nowcast"* ]] || { echo "$output"; false; }
  [[ "$output" == *"96h"* && "$output" == *"24h"* && "$output" == *"6h"* ]] || { echo "$output"; false; }
  [[ "$output" == *"bias"* && "$output" == *"MAE"* ]] || { echo "$output"; false; }
  # §5.4 acceptance 2: non-zero n in at least the 24 / 12 / 6 h buckets
  run python3 "$CA_BIN" --strand-score --json
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  run python3 -c '
import json, sys
d = json.loads(sys.argv[1])
assert d["n_windows"] == 3, d["n_windows"]
by = {b["h"]: b for b in d["buckets"]}
for h in (24.0, 12.0, 6.0):
    assert by[h]["n"] >= 3, (h, by[h])
    assert by[h]["bias"] is not None, (h, by[h])
print("OK")' "$output"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
