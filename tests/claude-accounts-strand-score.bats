#!/usr/bin/env bats
# strand_score / --strand-score — the planner's own mutation test.
# USAGE_TELEMETRY_100P §5.2 S5 (M3c), acceptance §5.4 command 2.
#
# WHAT IT REPLACES, AND WHY THE REPLACEMENT IS THE WHOLE POINT. The synthesis scored the strand
# fire-rule at the horizon's CLOSE, where the projection has already converged to
# `100 - weekly_pct` — i.e. to the true strand — so it agreed with the identity function on 8/8
# windows and published `4/4 recall, 0 FP, median ~20 h lead`. Eight binary cells, every one of
# them evaluated where being wrong was arithmetically impossible. That is a tautology wearing a
# validation's clothes, and it is the single reason S6's alarm is still unbuilt.
#
# SO THE CASES BELOW ARE ABOUT FALSIFIABILITY, NOT ACCURACY. SS-1 pins that the harness reports a
# NON-ZERO error on a window whose pace changed after the evaluation instant; SS-2 pins that the
# estimator is replayed CAUSALLY, since a scorer handed the whole window re-derives the tautology
# at a new spelling and its only symptom is a table of small errors — which reads as success.
#
# Hermetic: $HOME, $CLAUDE_CONFIG_DIR and $CC_UTIL_LOG into BATS_TEST_TMPDIR.

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
STEP_H = 0.1                     # 6 min, the live series cadence
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def window(reset_ago_h, segments, acct="next3"):
    """One weekly window that CLOSED reset_ago_h hours ago. segments = [(hours, pp_per_h), ...]
    walked forward, ending just before the reset — completed_weekly_windows counts a window only
    when its last sample lands within WEEKLY_TAIL_GAP_H of the close.

    THE RESET IS SNAPPED TO A WHOLE MINUTE, and that is not cosmetic. _reset_key ROUNDS to the
    minute and completed_weekly_windows rebuilds the reset instant as `key * 60`, so a fixture
    whose reset falls mid-minute produces a gap anywhere in [-30 s, +30 s) against its own last
    sample — and the rule requires gap >= 0. A fixture built on a bare time.time() therefore
    passes or fails on the second the suite happens to run. Caught here as a real intermittent."""
    reset_t = float(int((NOW - reset_ago_h * 3600.0) / 60.0) * 60)
    total = sum(s[0] for s in segments)
    out, t, wp = [], 0.0, 0.0
    for hours, rate in segments:
        for _ in range(int(round(hours / STEP_H))):
            out.append({"acct": acct, "weekly_pct": round(wp, 4), "session_pct": 10,
                        "_t": reset_t - (total - t) * 3600.0,
                        "weekly_reset_at": iso(reset_t),
                        "session_reset_at": iso(reset_t)})
            wp += rate * STEP_H
            t += STEP_H
    out.append({"acct": acct, "weekly_pct": round(wp, 4), "session_pct": 10, "_t": reset_t - 60.0,
                "weekly_reset_at": iso(reset_t), "session_reset_at": iso(reset_t)})
    return out
def bucket(sc, h):
    return [b for b in sc["buckets"] if b["h"] == h][0]
'

@test "SS-1: the harness reports a NON-ZERO error — it is scored where it CAN be wrong" {
  # A window that paced at 0.30 pp/h for 120 h (36 pp), then burst at 4.0 pp/h for the last 12 h
  # to close at ~84%. Evaluated 24 h before the reset the nowcast sees only the slow pace and
  # projects a large strand; the window in fact stranded ~16 pp. The error is the measurement.
  #
  # THE OLD SCORE CANNOT PRODUCE THIS NUMBER. At the window's last sample the projection is
  # `100 - weekly_pct` by construction, i.e. exactly the realised strand, and the error is 0.0
  # for any estimator whatsoever — including one that returns a constant.
  run python3 -c "$LOAD"'
sam = window(30.0, [(120.0, 0.30), (12.0, 4.0)])
sc = ca.strand_score(sam)
assert sc["windows"] == 1, sc["windows"]
b24 = bucket(sc, 24.0)
assert b24["n"] == 1, b24
c = b24["cells"][0]
assert c["eval_reset_h"] >= 24.0, c            # evaluated BEFORE the reset, at its horizon
assert c["eval_reset_h"] < 24.0 + STEP_H + 1e-6, c
assert abs(c["realised"] - 16.0) < 1.5, c      # 120*0.30 + 12*4.0 = 84 -> ~16 pp died
assert c["projected"] > 25.0, c                # the slow pace nowcasts a far bigger strand
assert b24["bias"] > 5.0, b24                  # ...and the harness SAYS SO
assert b24["mae"] > 5.0, b24
# CONTROL — the tautology, computed inline on the same window so the contrast is in this file
# and not only in the plan. Score at the LAST sample and the error is identically zero.
last = max(sam, key=lambda e: e["_t"])
assert abs((100.0 - last["weekly_pct"]) - c["realised"]) < 1e-6, last
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "SS-2 CONTROL: the estimator is replayed CAUSALLY — the burst after the horizon is unseen" {
  # THE MUTANT THIS KILLS: a scorer that hands burn_wk_ewma_ph the whole window. It still returns
  # a table, still has the right n, and its only symptom is smaller errors — which reads as
  # success. Here the pace after the 24 h horizon is 13x the pace before it, so a leak is not a
  # rounding difference: the projection collapses toward the truth and the bias with it.
  run python3 -c "$LOAD"'
sam = window(30.0, [(120.0, 0.30), (12.0, 4.0)])
c = bucket(ca.strand_score(sam), 24.0)["cells"][0]
t_eval = max(e["_t"] for e in sam if e["weekly_pct"] <= c["eval_weekly_pct"] + 1e-9)
# the causal projection, recomputed here from the shipped estimator over the PAST slice only
past = [e for e in sam if e["_t"] <= t_eval]
v_causal, _ = ca.burn_wk_ewma_ph(past, t_eval, c["eval_reset_h"])
# ...and the LEAKED one, over every sample in the window
v_leak, _ = ca.burn_wk_ewma_ph(sam, t_eval, c["eval_reset_h"])
assert v_leak > v_causal * 2.0, (v_causal, v_leak)   # the fixture DOES discriminate the two
p_leak = ca.wk_strand_pp({"weekly_pct": c["eval_weekly_pct"],
                          "weekly_reset_h": c["eval_reset_h"], "burn_wk_ewma_ph": v_leak})
assert abs(c["projected"] - ca.wk_strand_pp({"weekly_pct": c["eval_weekly_pct"],
           "weekly_reset_h": c["eval_reset_h"], "burn_wk_ewma_ph": v_causal})) < 1e-9, c
assert c["projected"] > p_leak + 5.0, (c["projected"], p_leak)   # the leak would flatter it
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "SS-3 CONTROL: an unevaluable cell is EXCLUDED and counted, never imputed as a zero error" {
  # L2, and it is the difference between "no evidence" and "no error". A window observed for only
  # its last 30 h cannot be evaluated at the 96 h or 48 h horizons at all; a harness that scores
  # those cells as 0.0 reports a perfect bias over cells it never measured.
  run python3 -c "$LOAD"'
sc = ca.strand_score(window(30.0, [(30.0, 1.0)]))
assert sc["windows"] == 1, sc
for h in (96.0, 48.0):
    b = bucket(sc, h)
    assert b["n"] == 0 and b["abstained"] == 1, b
    assert b["bias"] is None and b["mae"] is None, b     # NOT 0.0
b6 = bucket(sc, 6.0)
assert b6["n"] == 1 and b6["abstained"] == 0, b6         # the arm that makes the above a control
# the estimator ABSTAINING is an abstain too, not a hit: a window whose whole history is 4 h is
# under burn_wk_ewma_ph own span floor at every horizon it reaches.
thin = ca.strand_score(window(30.0, [(4.0, 1.0)]))
assert thin["windows"] == 1, thin
assert all(b["n"] == 0 for b in thin["buckets"]), thin
assert sum(b["abstained"] for b in thin["buckets"]) == len(thin["buckets"]), thin
# no completed window at all ⇒ every bucket empty, and the renderer SAYS so rather than
# printing a table of dashes that reads like a measurement
none = ca.strand_score([])
assert none["windows"] == 0 and all(b["n"] == 0 for b in none["buckets"]), none
assert "NO COMPLETED WINDOW" in ca.render_strand_score(none), ca.render_strand_score(none)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "SS-4: the LIVE window is never scored — it has not stranded anything yet" {
  # completed_weekly_windows (S1d) already refuses the live window; this pins that strand_score
  # inherits that refusal rather than re-deriving a looser rule. The naive gap-only rule admitted
  # next3 at 92% on 2026-08-25 and reported 51 pp over 9 account-weeks against the true 43/8.
  run python3 -c "$LOAD"'
live = []
reset_t = NOW + 40 * 3600.0                    # resets in 40 h: nothing has died yet
for i in range(300, -1, -1):
    live.append({"acct": "next3", "weekly_pct": (300 - i) * 0.1, "session_pct": 10,
                 "_t": NOW - i * 360.0, "weekly_reset_at": iso(reset_t),
                 "session_reset_at": iso(reset_t)})
sc = ca.strand_score(live)
assert sc["windows"] == 0, sc
assert all(b["n"] == 0 for b in sc["buckets"]), sc
# CONTROL: the same series with its reset in the PAST and observed to the close IS scored, so
# the refusal above is about liveness and not about the fixture being unreadable.
closed = ca.strand_score(window(30.0, [(120.0, 0.30), (12.0, 4.0)]))
assert closed["windows"] == 1, closed
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "SS-5 e2e --strand-score: answers with NO config, NO keychain and NO sweep" {
  # The --agents property, for the same reason it exists there: this branch returns before
  # load_cfg(), so scoring HISTORY never depends on a Claude accounts.json existing or on four
  # accounts being reachable. $HOME is fixtured to an empty dir — a branch placed after load_cfg()
  # exits non-zero here, which is exactly how that coupling was found the first time.
  python3 - "$CC_UTIL_LOG" <<'PY'
import json, sys, time
from datetime import datetime, timezone
# snapped to a whole minute: _reset_key rounds and completed_weekly_windows rebuilds the reset
# as key*60, so a mid-minute reset makes the tail-gap rule pass or fail on the second the suite
# happens to run. See the `window()` helper above.
reset_t = float(int((time.time() - 30 * 3600.0) / 60.0) * 60)
def iso(t): return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
rows, wp = [], 0.0
n = int(132 / 0.1)
for i in range(n + 1):
    t = reset_t - (132 - i * 0.1) * 3600.0 - (60.0 if i == n else 0.0)
    rows.append({"ts": iso(t), "acct": "next3", "weekly_pct": round(wp, 4), "session_pct": 10,
                 "weekly_reset_at": iso(reset_t), "session_reset_at": iso(reset_t)})
    wp += (0.30 if i * 0.1 < 120 else 4.0) * 0.1
open(sys.argv[1], "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  run python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"strand-score"* ]] || { echo "$output"; false; }
  [[ "$output" == *"1 completed weekly window"* ]] || { echo "$output"; false; }
  # the caption must carry the acceptance test beside the numbers: a table of small errors is
  # what a vacuous harness produces, and the reader has to be told which reading is which
  [[ "$output" == *"ACCEPTANCE IS NOT ACCURACY"* ]] || { echo "$output"; false; }
  # `python3 - <<'PY' <<< "$output"` would be a VACUOUS PASS and it is worth naming here: two
  # stdin redirections, the herestring wins, python reads the JSON body as its own program, and
  # `{"windows": 1, ...}` is a valid expression statement that exits 0 without running one
  # assertion. Use the -c form, which is how every other suite in this repo spells it.
  # --tail-h is in HOURS and its usage error must SAY hours. _num_flag hardcoded "seconds" for
  # --max-wait/--max-age, so the first hours-denominated caller turned that message into a lie —
  # one that sends the reader to fix the right flag with the wrong magnitude.
  run python3 "$CA_BIN" --strand-score --tail-h 2000
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  run python3 "$CA_BIN" --strand-score --tail-h abc
  [ "$status" -eq 64 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"requires a number of hours"* ]] || { echo "$output"; false; }
  # CONTROL: a seconds-denominated flag still says seconds, so the fix is a UNIT parameter and
  # not a blanket rename of the message.
  run python3 "$CA_BIN" --max-wait abc
  [ "$status" -eq 64 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"requires a number of seconds"* ]] || { echo "$output"; false; }
  run python3 "$CA_BIN" --strand-score --json
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  run python3 -c '
import json, sys
sc = json.load(sys.stdin)
assert sc["windows"] == 1, sc["windows"]
b = {x["h"]: x for x in sc["buckets"]}
assert b[24.0]["n"] == 1 and b[24.0]["bias"] > 5.0, b[24.0]
assert b[6.0]["n"] == 1, b[6.0]
assert b[96.0]["n"] == 1, b[96.0]        # 132 h of history reaches the widest horizon
assert b[96.0]["cells"][0]["eval_reset_h"] >= 96.0, b[96.0]
print("OK")' <<< "$output"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
