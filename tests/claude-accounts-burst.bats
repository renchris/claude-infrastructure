#!/usr/bin/env bats
# burst_percentile — is the required weekly rate ROUTINE for this account, or a stunt it has
# never pulled off? USAGE_TELEMETRY_100P §5.2 S2 (M5), RED-proof cases RP-17..RP-20.
# burst_start_by  — by WHEN must the endgame burst begin for the demand to still fit inside the
# weekly window? USAGE_TELEMETRY_100P §5.2 S4 (M4'), RED-proof cases RP-21..RP-24.
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
# WHY M4' AND NOT THE SYNTHESIS'S M4 (RP-21's comment carries the proof). M4 asked a CAPACITY
# question — `wk_reach_pp` vs `need` — which is near-algebraically fixed: recomputed over the whole
# series it read REACHABLE on 99.37% of samples and on 100% of the 74 samples inside the five wall
# episodes it existed to detect. M4' asks a RATE-AND-FREEZE-AGAINST-THE-CLOCK question, which can
# come out either way, and on the one account that in fact stranded it comes out the other way.
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

# ---- S4 · M4' · burst_start_by — the START-TIME constraint --------------------------------------
#
# The primitive is a START TIME, not a capacity verdict. All 8 measured burst windows delivered
# 13-20 weekly pp whether or not they walled (§5.1 LB-3), so the loss is not inside the window —
# it is the frozen tail that follows one. The shippable constraint is therefore: begin the endgame
# burst early enough that the burn PLUS the expected freeze PLUS the 5h grid still fit before the
# weekly reset.
#
# These cases pass K explicitly. burst_start_by is the FIRST consumer of exchange_rate (S1c built
# it and nothing read it), and the pairing is pinned at the render layer in
# tests/claude-accounts-core.bats, not here.

@test "RP-21: burst_start_by returns LATE for next3's live shape, where M4 said REACHABLE" {
  # The measured live row at 2026-08-25T09:47:41Z, the account that in fact stranded.
  #   deficit 8 pp -> 8/0.192 = 41.67 session-pp; one window buys it at 22.87 session-pp/h
  #   = 1.822 h of burn; expected freeze 1 x 0.625 x 1.653 = 1.033 h; t_needed = 2.855 h
  #   against 2.21 h of window left  =>  -0.645 h, i.e. LATE.
  #
  # THE DELETION THIS CASE RECORDS. The synthesis's M4 (`wk_reach_pp`) scored this SAME row as
  # `16.9 pp reach vs 8 needed — REACHABLE, 2.1x margin`: the opposite verdict, on the account
  # that stranded. M4 is deleted, not weakened, and RP-22 below is what stops M4' degenerating
  # into the mirror-image always-LATE stub.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
bs = ca.burst_start_by(r, 0.192)
assert bs is not None, bs
assert -1.0 < bs["h"] < 0.0, bs
assert abs(bs["h"] - -0.645) < 0.01, bs
assert bs["verdict"] == "LATE", bs
assert bs["windows"] == 1, bs
assert abs(bs["freeze_h"] - 1.033) < 0.01, bs
assert abs(bs["t_needed_h"] - 2.855) < 0.01, bs
# ...and it reports the FLOOR, which is the number a reader acts on: freezing 1.03 h of the
# 2.21 h remaining leaves 1.18 h of usable burn = K x 22.87 x 1.18 = 5.17 weekly pp of the 8.
assert abs(bs["unrecoverable_pp"] - 2.83) < 0.02, bs
assert ca.fmt_start_by(bs) == "⚠ LATE by 0.6h — 2.8pp already unrecoverable", ca.fmt_start_by(bs)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway returns SLACK — the anti-degeneracy arm" {
  # next2's live shape. Without this, RP-21 is satisfied by a function that returns LATE always,
  # which is exactly the degeneracy that killed M4 in the other direction (REACHABLE always).
  #   deficit 83 -> 432.3 session-pp. The OPEN window has 92 pp of room but only 0.54 h left, so
  #   it contributes 12.3 pp and the walk then waits out the roll; five more windows finish it.
  #   6 windows, 21.41 h of burn, 6.20 h of freeze, t_needed 27.61 against 97.2 h left.
  run python3 -c "$LOAD"'
r = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2,
     "session_pct": 8, "session_reset_h": 0.54}
bs = ca.burst_start_by(r, 0.192)
assert bs is not None, bs
assert bs["h"] > 60.0, bs
assert abs(bs["h"] - 69.59) < 0.05, bs
assert bs["verdict"] == "SLACK", bs
assert bs["windows"] == 6, bs
assert abs(bs["t_needed_h"] - 27.61) < 0.05, bs
assert bs["unrecoverable_pp"] == 0.0, bs      # nothing is lost yet, so the floor is zero
assert ca.fmt_start_by(bs) == "start by T−28h (70h slack)", ca.fmt_start_by(bs)
# The 5h GRID is what makes this 27.6 h and not 21.4 h of pure burn: you cannot open window N+1
# before window N resets. A formula that divides the demand by the rate and stops passes RP-21
# and reads ~19 h here.
assert bs["t_needed_h"] > (432.3 / ca.BURST_SPPH) + 1.0, bs
# ...and the START SOON band exists between the two verdicts. Same demand, 20 h of window left.
soon = ca.burst_start_by(dict(r, weekly_reset_h=32.0), 0.192)
assert soon["verdict"] == "START SOON", soon
assert 0.0 < soon["h"] <= 12.0, soon
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the wall-freeze term is LIVE, not decorative" {
  # THE MUTANT A PURELY ARITHMETIC IMPLEMENTATION WOULD SURVIVE. P_WALL = 5/8 and MEAN_WALL_H =
  # 1.653 come from the 8 measured burst windows, and the whole M4' claim is that the loss is the
  # FROZEN TAIL rather than the burn. Drop the freeze term and RP-21's row reads -0.645 + 1.033 =
  # +0.388, i.e. SLACK — the wrong verdict on the account that stranded. Run the same fixture at
  # P_WALL = 0.625 and at P_WALL = 0.0 and assert the executed difference, not a guess.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
live = ca.burst_start_by(r, 0.192)
assert ca.P_WALL == 0.625, ca.P_WALL          # 5 of the 8 measured burst windows walled
assert abs(ca.MEAN_WALL_H - 1.653) < 1e-9, ca.MEAN_WALL_H
ca.P_WALL = 0.0
try:
    off = ca.burst_start_by(r, 0.192)
finally:
    ca.P_WALL = 0.625
assert abs((off["h"] - live["h"]) - 1.033) < 0.01, (live, off)
assert off["freeze_h"] == 0.0, off
# ...and the VERDICT flips, which is the term being load-bearing rather than merely present:
# 2.21 h of window against 1.82 h of burn leaves +0.39 h, so with no freeze this row is still
# rescuable and the operator would be told to act. With the measured freeze it is not.
assert live["verdict"] == "LATE", live
assert off["verdict"] == "START SOON", off
assert live["unrecoverable_pp"] > 2.8 and off["unrecoverable_pp"] == 0.0, (live, off)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24 CONTROL: every abstain is a null, never a zero — no window, no K, no deficit" {
  # L2. Each arm is a DISTINCT state that must not collapse to 0.0, because a rendered
  # `start by T−0h` reads as "start now" and three of these four mean the opposite or nothing.
  run python3 -c "$LOAD"'
base = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
        "session_pct": 13, "session_reset_h": 3.37}
assert ca.burst_start_by(base, 0.192) is not None, "the live shape must still report"
# (a) NO WINDOW OPEN. A null session stamp is a state, not a zero: reading it as session_pct=0
# would grant a full 100 pp of imaginary room and turn every LATE into SLACK.
assert ca.burst_start_by(dict(base, session_pct=None), 0.192) is None
assert ca.burst_start_by(dict(base, session_reset_h=None), 0.192) is None
# (b) K ABSTAINED (S1c left the sane band). Without the exchange rate there is no session-pp
# demand at all, so there is nothing to schedule.
assert ca.burst_start_by(base, None) is None
# (c) NOTHING LEFT TO BUY — the window is already full.
assert ca.burst_start_by(dict(base, weekly_pct=100), 0.192) is None
assert ca.burst_start_by(dict(base, weekly_pct=None), 0.192) is None
# (d) the weekly countdown is outside (0, 168]: a rolled or corrupt stamp, not a deadline.
assert ca.burst_start_by(dict(base, weekly_reset_h=0.0), 0.192) is None
assert ca.burst_start_by(dict(base, weekly_reset_h=-3.0), 0.192) is None
assert ca.burst_start_by(dict(base, weekly_reset_h=200.0), 0.192) is None
assert ca.fmt_start_by(None) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24b CONTROL: a WALLED open window buys nothing and blocks the start until it rolls" {
  # 5 of the 8 measured burst windows walled (§5.1 LB-3), so session_pct = 100 is not a corner
  # case — it is the state the planner CREATES. A walk that falls straight into the 5h grid here
  # starts burning at t=0 inside a window that cannot burn, understating t_needed by the whole
  # remaining 5h countdown and turning a LATE row into SLACK.
  run python3 -c "$LOAD"'
walled = {"acct": "next3", "weekly_pct": 60, "weekly_reset_h": 40.0,
          "session_pct": 100, "session_reset_h": 4.0}
bs = ca.burst_start_by(walled, 0.192)
assert bs is not None, bs
# The open window contributes NOTHING: 40 pp -> 208.3 session-pp is 3 full windows, not 3 windows
# plus a partial one, and the clock does not start for 4.0 h.
assert bs["windows"] == 3, bs
assert abs(bs["burn_h"] - (4.0 + 208.3333 / ca.BURST_SPPH + 2 * (5.0 - 100.0 / ca.BURST_SPPH))) < 0.02, bs
# ...and the dead time is EXACTLY the session countdown, which is provable only by holding every
# other term fixed. The comparison row is the same wall about to ROLL: identical demand, identical
# window count, identical freeze — the sole difference is the 4 h of waiting.
rolling = ca.burst_start_by(dict(walled, session_reset_h=0.0), 0.192)
assert rolling["windows"] == bs["windows"], (bs, rolling)
assert rolling["freeze_h"] == bs["freeze_h"], (bs, rolling)
assert abs((bs["t_needed_h"] - rolling["t_needed_h"]) - 4.0) < 1e-9, (bs, rolling)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
