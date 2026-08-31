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

# ---- S4 · M4′ `burst_start_by` — the start-time constraint --------------------------------------
#
# WHY A START TIME AND NOT A CAPACITY VERDICT. M4 `wk_reach_pp` — "can this account still reach
# 100%?" — is DELETED (USAGE_TELEMETRY_100P §5.5). It read REACHABLE on 99.37% of the series and on
# 100% of the 74 samples inside the 5 wall episodes it was written to catch, because reach_pp and
# need are both monotone in (weekly_pct, hours-remaining): it was an algebraic restatement of what
# it supplemented. RP-21 is the case that records the deletion where an implementer reads it — on
# next3's live shape M4 read `16.9 pp reach vs 8 needed → REACHABLE, 2.1× margin`, M4′ reads LATE,
# and next3 in fact stranded.
#
# ALL THREE CONSTANTS COME FROM n = 8 BURST WINDOWS and the metric ships ON PROBATION. The
# threshold is sized on the BURST denominator (5 of 8 walled), never the all-windows one (5/252),
# because the thing being planned IS a burst. P_WALL is a lower bound: a wall shorter than the
# ~13 min sweep interval is invisible to the detector.

@test "RP-21: burst_start_by reads LATE on next3's live shape — the verdict M4 got backwards" {
  # The measured live row at 2026-08-25T09:47:41Z, K = 0.192. 8 weekly pp of deficit costs 41.67
  # session pp, which the OPEN window can supply (87 pp free) in 1.82 h — but one window carries
  # one expected freeze of P_WALL × MEAN_WALL_H = 1.033 h, so the endgame needs 2.86 h and only
  # 2.21 h remain. The start time is 0.65 h in the PAST.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
sb = ca.burst_start_by(r, 0.192)
assert sb is not None, sb
assert -1.0 < sb["h"] < 0.0, sb                  # measured -0.645
assert sb["verdict"] == "LATE", sb
assert sb["windows"] == 1, sb
assert abs(sb["t_needed"] - 2.855) < 0.01, sb
# THE FLOOR IS WHAT MAKES `LATE` ACTIONABLE. Freezing 1.03 h of the 2.21 h left leaves 1.18 h of
# usable burn = K × BURST_SPPH × 1.18 = 5.17 weekly pp of the 8 needed, so 2.83 pp cannot be
# saved even by a perfect burst starting this instant. "You are late" alone does not say that.
assert abs(sb["unrecoverable_pp"] - 2.83) < 0.05, sb
assert "LATE" in ca.fmt_start_by(sb) and "unrecoverable" in ca.fmt_start_by(sb), ca.fmt_start_by(sb)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway reads SLACK — the degeneracy that killed M4" {
  # Without this arm RP-21 is satisfied by a function that returns LATE always, which is exactly
  # the always-one-answer degeneracy M4 died of, with the sign flipped. next2 live: 83 pp of
  # deficit = 432.3 session pp = 6 windows walked across the 5h grid, 21.41 h of burn plus 6.20 h
  # of expected freeze = 27.61 h needed against 97.2 h left.
  run python3 -c "$LOAD"'
r = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2,
     "session_pct": 8, "session_reset_h": 0.54}
sb = ca.burst_start_by(r, 0.192)
assert sb["verdict"] == "SLACK", sb
assert sb["h"] > 60.0, sb                        # measured +69.59
assert sb["windows"] == 6, sb                    # the 5h grid is walked, not divided out
assert abs(sb["t_needed"] - 27.61) < 0.05, sb
assert sb["unrecoverable_pp"] == 0.0, sb         # nothing is lost yet, so the floor is silent
assert ca.fmt_start_by(sb) == "start by T−28h (70h slack)", ca.fmt_start_by(sb)
# ...and the third verdict is REACHED, not dead code: the same shape inside the 12 h band.
soon = ca.burst_start_by({"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 35.0,
                          "session_pct": 8, "session_reset_h": 0.54}, 0.192)
assert soon["verdict"] == "START SOON", soon
assert 0.0 < soon["h"] <= 12.0, soon
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the wall-freeze term is LIVE, not decorative" {
  # THE MUTANT A PURELY ARITHMETIC IMPLEMENTATION SURVIVES. Everything else in RP-21/RP-22 is
  # satisfied by burn-time alone; only this pins that the freeze participates. Run the same
  # fixture with P_WALL at its measured 0.625 and at 0, and the two start times must differ by
  # exactly one window''s expected freeze — 1 × 0.625 × 1.653 = 1.033 h. The executed value, not
  # a guess: the freeze is 47% of next3''s entire remaining window and it is why the row is LATE.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
live = ca.burst_start_by(r, 0.192)["h"]
ca.P_WALL = 0.0
none_ = ca.burst_start_by(r, 0.192)["h"]
assert abs((none_ - live) - 1.033) < 0.01, (live, none_)
assert none_ > 0.0 and live < 0.0, (live, none_)   # and it is the term that flips the verdict
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24 CONTROL: every abstain arm is null, and NO WINDOW OPEN is not zero" {
  # L2. The second arm is the one that must not collapse: a null session stamp means no 5h window
  # is OPEN, which is a different state from "the open window is empty". Reading it as
  # session_pct = 0 hands the plan a free 100 pp of capacity that does not exist, and the whole
  # metric is a claim about capacity against a clock.
  run python3 -c "$LOAD"'
base = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
        "session_pct": 13, "session_reset_h": 3.37}
def w(**kw):
    d = dict(base); d.update(kw); return d
assert ca.burst_start_by(w(), None) is None, "K abstained (S1c) and this answered anyway"
assert ca.burst_start_by(w(session_pct=None), 0.192) is None, "no window open read as zero"
assert ca.burst_start_by(w(session_reset_h=None), 0.192) is None, "no window open read as zero"
assert ca.burst_start_by(w(weekly_pct=100), 0.192) is None, "no deficit, nothing to start"
assert ca.burst_start_by(w(weekly_reset_h=0), 0.192) is None
assert ca.burst_start_by(w(weekly_reset_h=169.0), 0.192) is None
assert ca.burst_start_by(w(weekly_pct=None), 0.192) is None
assert ca.fmt_start_by(None) is None
# ...and a session window with NOTHING left is a value, not an abstain: it just waits out the roll.
full = ca.burst_start_by(w(session_pct=100), 0.192)
assert full is not None and full["windows"] >= 1, full
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
