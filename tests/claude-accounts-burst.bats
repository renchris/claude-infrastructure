#!/usr/bin/env bats
# burst_percentile — is the required weekly rate ROUTINE for this account, or a stunt it has
# never pulled off? USAGE_TELEMETRY_100P §5.2 S2 (M5), RED-proof cases RP-17..RP-20.
#
# THE DEFECT. The footer said `needs 88%/d over 2.2h`: a rate quoted in a unit ELEVEN TIMES
# longer than the window it has to happen in, with nothing on the line saying whether 88%/day is
# a Tuesday for that account or a personal record. The percentile is that missing fact, ranked
# against the account's OWN realised history at the horizon the demand actually lives on.
#
# THE ABSTAIN THAT MATTERS MOST IS RP-19. Above the account's observed maximum there is no
# evidence at all, and a rendered "p100" reads as a rate that HAS been achieved. The sentinel
# says the true thing instead: it has never once done this.
#
# H IS CHOSEN ON A LOG SCALE. The grid {1,3,6,12,24} is geometric; a linear nearest sends a
# 2.55 h deadline to the 1 h bucket, which is the wrong distribution by a factor of three.
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
def series(segments, acct="next3", t0_ago_h=None):
    """segments = [(hours, pp_per_h, weekly_window_id), ...] walked forward from oldest to newest.
    A change of window id is a weekly ROLL: the meter goes back to 0 and the stamp jumps."""
    total = sum(s[0] for s in segments)
    t0 = NOW - (t0_ago_h if t0_ago_h is not None else total) * 3600.0
    out, t, wp, cur = [], 0.0, 0.0, None
    for hours, rate, wid in segments:
        if wid != cur:
            cur, wp = wid, 0.0
        n = int(round(hours / STEP_H))
        for _ in range(n):
            out.append({"acct": acct, "weekly_pct": wp, "session_pct": 10,
                        "_t": t0 + t * 3600.0,
                        "weekly_reset_at": iso(NOW + 1000 * 3600.0 + wid * 3600.0),
                        "session_reset_at": iso(NOW + 3 * 3600.0)})
            wp += rate * STEP_H
            t += STEP_H
    return out
'

@test "RP-17: burst_percentile reports a p95 demand as a p95, and picks H on a LOG scale" {
  # A 250 h history at 0.30 weekly pp/h with a 13 h burst at 5.0 pp/h on the end, split across
  # two weekly windows. The demand -- 8 pp in 2.55 h = 3.14 pp/h -- sits above every routine 3 h
  # window and below the burst, i.e. up in the mid-90s of the account's own distribution.
  # H: log|2.55 - 3| = 0.163 against log|2.55 - 1| = 0.936, so the 3 h bucket. A LINEAR nearest
  # would pick 1 h -- a different distribution, and the wrong answer.
  run python3 -c "$LOAD"'
sam = series([(131.0, 0.30, 1), (119.0, 0.30, 2), (13.0, 5.0, 2)])
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.55}
bp = ca.burst_percentile(r, sam)
assert bp is not None, bp
assert bp["h"] == 3.0, bp
assert bp["n"] >= 2000, bp
assert bp["never"] is False, bp
assert 93.0 <= bp["pct"] <= 98.0, bp
assert abs(bp["need_pph"] - 8.0 / 2.55) < 1e-6, bp
assert ca.fmt_burst(bp) == "p%.0f of its own 3h burns" % bp["pct"], ca.fmt_burst(bp)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-18 CONTROL: a routine demand reports LOW, and at the 24h horizon" {
  # The discriminating arm: a constant-p95 stub passes RP-17 and fails here. 96 h of runway to
  # close 83 pp is 0.86 pp/h, which this account clears on most of its own days.
  # H: log|97 - 24| beats log|97 - 12|, so the 24 h bucket, not the 3 h one.
  run python3 -c "$LOAD"'
BLOCKS = [0.15, 0.45, 1.55, 0.95, 0.50, 0.55]     # sums to 99.6 pp per weekly window: realistic
sam = series([(24.0, b, w) for w in (1, 2) for b in BLOCKS])
r = {"acct": "next3", "weekly_pct": 17, "weekly_reset_h": 97.0}
bp = ca.burst_percentile(r, sam)
assert bp is not None, bp
assert bp["h"] == 24.0, bp
assert bp["never"] is False, bp
assert 5.0 < bp["pct"] < 75.0, bp
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-19 CONTROL: above the observed maximum it says NEVER, not an extrapolated p100" {
  # There is no evidence above the maximum, and a rendered p100 reads as a rate that HAS been
  # achieved -- the exact inversion this metric exists to remove. pct must be None, not 100.0.
  run python3 -c "$LOAD"'
sam = series([(131.0, 0.30, 1), (119.0, 0.30, 2), (13.0, 5.0, 2)])
r = {"acct": "next3", "weekly_pct": 25, "weekly_reset_h": 3.0}   # 75 pp in 3 h = 25 pp/h, 5x max
bp = ca.burst_percentile(r, sam)
assert bp is not None, bp
assert bp["never"] is True, bp
assert bp["pct"] is None, bp
assert ca.fmt_burst(bp) == "needs more than it has EVER burned in 3h", ca.fmt_burst(bp)
# ...and the refusal holds AT THE STRING, which is the half that shipped broken. A demand
# sitting exactly at the observed maximum is not `never` — it scores 99.96 — and %.0f rounds
# that to the literal "p100". Live on 2026-08-25 next3 rendered exactly that. A reader cannot
# tell that string from the extrapolation this abstain exists to prevent.
atmax = {"pct": 99.96, "h": 3.0, "n": 2576, "need_pph": 5.0, "never": False}
assert ca.fmt_burst(atmax) == "p99 of its own 3h burns", ca.fmt_burst(atmax)
assert "p100" not in ca.fmt_burst(atmax), ca.fmt_burst(atmax)
assert ca.fmt_burst({"pct": 95.6, "h": 3.0, "n": 9, "need_pph": 1.0,
                     "never": False}) == "p96 of its own 3h burns"   # the cap does NOT bind here
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-20 CONTROL: abstains below 200 qualifying windows — a thin history cannot RANK anything" {
  # 20 h of history yields ~170 three-hour windows. A percentile over that is a number, not a
  # measurement, and L2 says a missing denominator is null and never a value.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.55}
assert ca.burst_percentile(r, series([(20.0, 0.30, 1)])) is None      # ~171 windows
# ...and the BOUNDARY is the count, not "short series return None for some other reason":
# five more hours of the same history crosses 200 and the metric reports.
over = ca.burst_percentile(r, series([(25.0, 0.30, 1)]))
assert over is not None and over["n"] >= 200, over
assert ca.fmt_burst(None) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-20b CONTROL: inside the last half hour it abstains, and it ranks the account's OWN history" {
  # Two arms of the same rule. (a) below BURST_MIN_RESET_H a rate is quantization, not pace.
  # (b) a sibling account's samples must not enter the distribution -- the whole claim is
  # "routine FOR THIS ACCOUNT", and pooling would rank next3's demand against next4's habits.
  run python3 -c "$LOAD"'
sam = series([(131.0, 0.30, 1), (119.0, 0.30, 2), (13.0, 5.0, 2)])
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 0.3}
assert ca.burst_percentile(r, sam) is None, "did not abstain inside the last half hour"
other = {"acct": "next4", "weekly_pct": 92, "weekly_reset_h": 2.55}
assert ca.burst_percentile(other, sam) is None, "ranked next4 against next3 history"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---------------------------------------------------------------------------------------------
# S4 · M4' · burst_start_by — the START-TIME constraint (USAGE_TELEMETRY_100P §5.2 S4, RP-21..24)
#
# WHY A START TIME AND NOT A CAPACITY VERDICT. All 8 measured burst windows delivered 13-20 weekly
# pp whether or not they walled, so the wall is not loss WITHIN the window -- the loss is the
# frozen tail. The synthesis's M4 `wk_reach_pp` asked the capacity question, which is nearly
# algebraically fixed: it read next3 as `16.9 pp reach vs 8 needed -- REACHABLE, 2.1x margin` on
# the account that in fact STRANDED. M4' asks a rate-and-freeze-against-the-clock question, which
# can come out either way, and reads the same row as LATE by 0.65 h with 2.83 pp already
# unrecoverable. RP-21 and RP-22 are that pair: a degenerate always-LATE function passes RP-21 and
# fails RP-22, which is exactly the degeneracy that killed M4.
# ---------------------------------------------------------------------------------------------

@test "RP-21: burst_start_by returns LATE for next3's live shape, with the unrecoverable floor" {
  # The measured live row at 2026-08-25T09:47:41Z, K = 0.192. Walked by hand in §5.2 S4:
  #   deficit 8 pp -> need 41.67 session pp -> 1.822 h of burn in the OPEN window (87 pp of room,
  #   3.37 h before it rolls, so the window does not bind) -> 1 window -> freeze 1.033 h ->
  #   t_needed 2.855 h against 2.21 h of weekly runway -> -0.645 h.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
b = ca.burst_start_by(r, 0.192)
assert b is not None, "burst_start_by did not answer on a fully-populated row"
assert -1.0 < b["h"] < 0.0, b
assert abs(b["h"] - (-0.645)) < 0.02, b
assert b["verdict"] == "LATE", b
# the floor is REPORTED, not implied: freeze 1.033 h of the 2.21 h remaining leaves 1.177 h of
# usable burn = K * BURST_SPPH * 1.177 = 5.17 weekly pp of the 8 needed.
assert abs(b["unrecoverable_pp"] - 2.83) < 0.05, b
assert b["windows"] == 1, b
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway returns SLACK, and nothing is unrecoverable" {
  # next2's live shape. 83 pp of deficit is SIX bursts across the 5h grid -- 21.41 h of burn plus
  # 6.20 h of expected freeze -- and it still fits inside 97.2 h with 69.59 h to spare. Without
  # this arm RP-21 is satisfied by `return {"h": -0.65, "verdict": "LATE"}`.
  run python3 -c "$LOAD"'
r = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2,
     "session_pct": 8, "session_reset_h": 0.54}
b = ca.burst_start_by(r, 0.192)
assert b is not None, b
assert b["h"] > 60.0, b
assert abs(b["h"] - 69.59) < 0.1, b
assert b["verdict"] == "SLACK", b
assert b["unrecoverable_pp"] == 0.0, b
assert b["windows"] == 6, b          # the 5h grid is WALKED, not divided: 6 windows, not 4.3
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22b CONTROL: the middle rung EXISTS — a two-window burst inside 12h reads START SOON" {
  # A two-verdict ladder is a boolean wearing three names. This pins the rung between them:
  # deficit 20 pp -> 104.17 session pp -> the open window (100 pp of room) is consumed in 4.37 h,
  # 4.17 pp remain, so the plan WAITS for the roll at 10 h and finishes at 10.18 h; freeze over
  # 2 windows is 2.066 h; t_needed 12.25 h against 20 h of weekly runway = 7.75 h of slack.
  run python3 -c "$LOAD"'
r = {"acct": "next4", "weekly_pct": 80, "weekly_reset_h": 20.0,
     "session_pct": 0, "session_reset_h": 10.0}
b = ca.burst_start_by(r, 0.192)
assert b is not None, b
assert 0.0 < b["h"] <= 12.0, b
assert abs(b["h"] - 7.75) < 0.1, b
assert b["verdict"] == "START SOON", b
assert b["windows"] == 2, b
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the wall-FREEZE term is live, not decorative — P_WALL=0 moves it 1.033h" {
  # THE MUTANT A PURELY ARITHMETIC IMPLEMENTATION SURVIVES. Every other case here is satisfied by
  # a function that walks the 5h grid and forgets the freeze entirely; on next3's shape that
  # returns +0.388 h -- SLACK -- on the account that stranded. Running the same fixture twice
  # with the module constant swapped is the only assertion that can see the term participate.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
with_freeze = ca.burst_start_by(r, 0.192)["h"]
saved = ca.P_WALL
try:
    ca.P_WALL = 0.0
    without = ca.burst_start_by(r, 0.192)["h"]
finally:
    ca.P_WALL = saved
assert abs((without - with_freeze) - 1.033) < 0.01, (with_freeze, without)
assert with_freeze < 0.0 < without, (with_freeze, without)   # and it FLIPS the verdict
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24 CONTROL: no window open ⇒ ABSTAIN, not zero; and every other abstain arm is live" {
  # A null session stamp means NO WINDOW IS OPEN -- a distinct state (15.0% of rows, _reset_key's
  # own docstring) that must not collapse to `session_pct = 0`, which would read as a FULL window
  # of free room and manufacture the most optimistic start time the function can produce.
  run python3 -c "$LOAD"'
base = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
        "session_pct": 13, "session_reset_h": 3.37}
def var(**kw):
    d = dict(base); d.update(kw); return d
assert ca.burst_start_by(var(session_pct=None, session_reset_h=None), 0.192) is None
assert ca.burst_start_by(var(session_reset_h=None), 0.192) is None
assert ca.burst_start_by(base, None) is None                  # K abstained (S1c) -> no verdict
assert ca.burst_start_by(var(weekly_pct=100), 0.192) is None   # deficit <= 0: nothing to plan
assert ca.burst_start_by(var(weekly_reset_h=0.0), 0.192) is None
assert ca.burst_start_by(var(weekly_reset_h=200.0), 0.192) is None
assert ca.burst_start_by(var(weekly_pct=None), 0.192) is None
# ...and the CONTROL that keeps the six above from being an unconditional None:
assert ca.burst_start_by(base, 0.192) is not None
assert ca.fmt_start_by(None) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
