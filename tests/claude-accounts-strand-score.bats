#!/usr/bin/env bats
# strand_score — the mutation test of the weekly planner. USAGE_TELEMETRY_100P §5.2 S5 (M3c),
# RED-proof cases RP-28..RP-32.
#
# WHY THIS EXISTS AT ALL. The synthesis's original score produced 8 binary cells, each evaluated
# at its horizon's CLOSE, where M3a's projection has already converged to `100 - weekly_pct` —
# i.e. to the answer. It agreed with the identity function on 8/8 windows and could not have
# done otherwise. That is a tautology wearing a validation's clothes. This scores (window,
# horizon) cells at FIXED distances from the reset, where the estimator has not converged and
# CAN be wrong. RP-28 is the case that proves it can: one bucket reads +72 pp of bias on a
# fixture the 6 h bucket nails.
#
# CAUSALITY IS THE TRAP AND RP-29 IS THE GUARD. `burn_wk_ewma_ph` filters its lookback as
# `now - _t <= 48h`, which a sample from AFTER `now` also satisfies. Hand it the whole series
# with a past `now` and every horizon scores as well as the last one — the harness would report
# a clean bias at T−96h and S6 would ship on it.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; the series is passed explicitly
# to the function, and written to CC_UTIL_LOG only for the CLI case.

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
STEP_H = 0.1                      # 6 min, the series cadence
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def window(acct, reset_ago_h, segments, tail_gap_h=0.1):
    """One CLOSED weekly window. `segments` = [(hours, pp_per_h), ...] walked forward from the
    windows first sample; the last sample lands `tail_gap_h` before the reset, which is what
    makes completed_weekly_windows accept it. Returns (rows, final_pct)."""
    reset_t = NOW - reset_ago_h * 3600.0
    reset_t = round(reset_t / 60.0) * 60.0        # land the stamp on a whole minute
    span_h = sum(s[0] for s in segments)
    t0 = reset_t - (span_h + tail_gap_h) * 3600.0
    out, t, wp = [], 0.0, 0.0
    for hours, rate in segments:
        for _ in range(int(round(hours / STEP_H))):
            out.append({"acct": acct, "weekly_pct": round(wp, 6), "session_pct": 10,
                        "_t": t0 + t * 3600.0,
                        "weekly_reset_at": iso(reset_t),
                        "session_reset_at": iso(NOW + 3 * 3600.0)})
            wp += rate * STEP_H
            t += STEP_H
    return out, out[-1]["weekly_pct"]
def bucket(sc, h):
    return next(b for b in sc["buckets"] if b["h"] == h)
'

@test "RP-28: the score is NOT a tautology — a far horizon is wrong where the near one is right" {
  # The fixture is a window that starts slow and finishes fast: 30 h at 0.10 weekly pp/h, then
  # 90 h at 0.90, closing at 84% for a REALISED strand of 16 pp.
  #   * At T−96h the estimator has seen only the slow stretch, so it projects 100 − (2.4 + 0.1×96)
  #     = ~88 pp of strand against 16 realised — a signed error near +72.
  #   * At T−6h it has seen 48 h of the fast stretch and lands on ~16, error near 0.
  # A harness that evaluates at the horizon's CLOSE (the refuted design) reports ~0 at BOTH and
  # calls the planner validated. This case is the difference between the two designs, in one
  # number.
  run python3 -c "$LOAD"'
sam, final = window("next3", 5.0, [(30.0, 0.10), (90.0, 0.90)])
assert abs(final - 83.9) < 0.5, final
sc = ca.strand_score(sam)
assert sc["windows"] == 1, sc["windows"]
far, near = bucket(sc, 96.0), bucket(sc, 6.0)
assert far["n"] == 1 and near["n"] == 1, (far["n"], near["n"])
assert far["bias"] > 40.0, far           # badly, measurably wrong four days out
assert abs(near["bias"]) < 4.0, near     # and right at the end, which is the whole shape
assert far["mae"] > near["mae"] * 5, (far["mae"], near["mae"])
# the cells carry their own evidence, not just the aggregate
c = far["cells"][0]
assert abs(c["at_h"] - 96.0) < 0.2, c
assert abs(c["realised"] - 16.1) < 0.5, c
assert c["signed_error"] == c["projected"] - c["realised"], c
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-29 CONTROL: causality — a T−96h cell cannot see the burst that happened at T−20h" {
  # THE LEAK THIS PINS. burn_wk_ewma_ph selects on `now - _t <= LOOKBACK`, a one-sided filter: a
  # sample from the FUTURE of the evaluation instant passes it. Feed the function the whole
  # account series with a past `now` and the T−96h cell reads the 0.90 pp/h endgame rate instead
  # of the 0.10 pp/h it could actually have measured — and every horizon then scores as well as
  # the last one, which is the tautology RP-28 exists to kill, re-entering through the back door.
  #
  # This asserts on the cell's OWN ewma, not on the bias, because the bias is a difference and a
  # leak of the right size hides inside it.
  run python3 -c "$LOAD"'
sam, _ = window("next3", 5.0, [(30.0, 0.10), (90.0, 0.90)])
sc = ca.strand_score(sam)
far = bucket(sc, 96.0)["cells"][0]
near = bucket(sc, 6.0)["cells"][0]
assert abs(far["ewma_ph"] - 0.10) < 0.03, far["ewma_ph"]    # a leak reads ~0.90 here
assert abs(near["ewma_ph"] - 0.90) < 0.05, near["ewma_ph"]  # CONTROL: the late cell DOES see it
# and the weekly_pct each cell scored is the level AT its own instant, not the final level
assert far["weekly_pct"] < 5.0, far
assert near["weekly_pct"] > 70.0, near
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-30 CONTROL: a bucket with no evaluable sample reports n=0 and is EXCLUDED, not imputed" {
  # A window observed for only 50 h has nothing to read at T−96h. Reporting that cell as a hit,
  # or as a zero-error, is how a harness reports its best number on the horizon it could not
  # read at all — and S6 is gated on exactly this table.
  run python3 -c "$LOAD"'
a, _ = window("next3", 5.0, [(30.0, 0.10), (90.0, 0.90)])
b, _ = window("next4", 7.0, [(50.0, 0.60)])
sc = ca.strand_score(a + b)
assert sc["windows"] == 2, sc["windows"]
assert sc["accounts"] == 2, sc["accounts"]
far = bucket(sc, 96.0)
assert far["n"] == 1, far["n"]                       # only next3 reaches back 96 h
assert all(c["acct"] == "next3" for c in far["cells"]), far["cells"]
# ...and the SECOND abstain arm, which is not the same one: next4 HAS a sample 48 h before its
# reset, but at that instant only ~2 h of its own history precedes it, so M2 abstains on its own
# 6.8 h measured-span floor and the cell is excluded for a different reason than "no sample".
# Both exclusions are silent in the aggregate and visible in `excluded`.
assert bucket(sc, 48.0)["n"] == 1, sc
assert bucket(sc, 24.0)["n"] == 2, sc
assert bucket(sc, 6.0)["n"] == 2, sc
assert sc["excluded"] == 2, sc["excluded"]
# a bucket nothing reaches reports NOTHING, never a zero
empty = ca.strand_score(b, buckets=(96.0,))
assert empty["buckets"][0]["n"] == 0, empty
assert empty["buckets"][0]["bias"] is None, empty
assert empty["buckets"][0]["mae"] is None, empty
assert empty["buckets"][0]["sign_agree"] is None, empty
rendered = ca.render_strand_score(empty)
assert "no evaluable sample" in rendered, rendered
assert "0.00" not in rendered.split(chr(10))[3], rendered
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31: the LIVE window is never scored, and sign-agreement is scored at the render floor" {
  # completed_weekly_windows is the gate, and the gap-IS-the-mechanism defect it was built for
  # bites hardest here: scoring the currently-open window would compare a projection against a
  # "realised" strand that is really just `100 - current_pct`, i.e. against the projection's own
  # input. Every cell would agree, and the harness would report perfect accuracy from a series
  # in which nothing has finished.
  run python3 -c "$LOAD"'
closed, _ = window("next3", 5.0, [(30.0, 0.10), (90.0, 0.90)])
live, _ = window("next2", -100.0, [(60.0, 0.50)])      # reset 100 h in the FUTURE
sc = ca.strand_score(closed + live)
assert sc["windows"] == 1, sc["windows"]
assert sc["accounts"] == 1, sc
assert all(c["acct"] == "next3" for b in sc["buckets"] for c in b["cells"]), sc
# SIGN AGREEMENT IS A THRESHOLD, because M3a clamps at zero and a literal sign() of a clamped
# quantity has two reachable values. It is scored at the same 0.5 pp the renderer uses to decide
# a row has something to lose, so the harness scores the question the surface asks. Both cells
# here have a real strand and a projected one, so they agree.
for h in (96.0, 6.0):
    b = bucket(sc, h)
    assert b["sign_agree"] == 1.0, (h, b)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32: --strand-score answers with NO accounts.json, no keychain and no sweep" {
  # Placed before load_cfg() for the same two reasons as --agents, and the second is the one
  # that bit that flag: a history question that depends on a live Claude config is a coupling,
  # not a convenience. $HOME here is an empty fixture — there is no accounts.json at all, and
  # the usage endpoint is unreachable. If this branch ran after load_cfg() it would exit
  # non-zero, exactly as --agents once did.
  python3 - <<'PY'
import json, os, time
from datetime import datetime, timezone
now = time.time()
reset_t = round((now - 5 * 3600.0) / 60.0) * 60.0
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
with open(os.environ["CC_UTIL_LOG"], "w") as f:
    t, wp = reset_t - 120.1 * 3600.0, 0.0
    while t < reset_t - 60:
        f.write(json.dumps({"ts": iso(t), "acct": "next3", "weekly_pct": round(wp, 4),
                            "session_pct": 10, "weekly_reset_at": iso(reset_t),
                            "session_reset_at": iso(now + 3 * 3600.0)}) + "\n")
        wp += 0.7 * 0.1
        t += 360.0
PY
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"scored against realised strand"* ]] || { echo "$output"; false; }
  [[ "$output" == *"T− 96h"* ]] || { echo "$output"; false; }
  [[ "$output" == *"T−  6h"* ]] || { echo "$output"; false; }
  [[ "$output" == *"sign-agree"* ]] || { echo "$output"; false; }
  # the same answer as data, and the cells are in it
  run python3 "$CA_BIN" --strand-score --json
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  run python3 -c '
import json, sys
sc = json.loads(sys.stdin.read())
assert sc["windows"] == 1, sc["windows"]
b = {x["h"]: x for x in sc["buckets"]}
assert set(b) == {96.0, 48.0, 24.0, 12.0, 6.0}, sorted(b)
assert b[6.0]["n"] == 1, b[6.0]
assert b[6.0]["cells"][0]["acct"] == "next3", b[6.0]
print("OK")' <<<"$output"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
