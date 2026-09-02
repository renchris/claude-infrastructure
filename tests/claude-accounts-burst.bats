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

# ---- S4 / M4' : burst_start_by -- the START-TIME constraint (RP-21..RP-24) --------------------
#
# WHAT MAKES THIS DIFFERENT FROM THE DELETED M4, stated here because a future implementer reads
# the test before the plan. M4 (`wk_reach_pp`) asked a CAPACITY question -- "is the remaining
# deficit reachable?" -- and both sides of that comparison are monotone in
# (weekly_pct, hours-remaining), so it is near-algebraically fixed: it read REACHABLE on 99.37%
# of the whole series and on 100% of the 74 samples inside the 5 wall episodes it was written to
# catch. On the very fixture in RP-21 below it reads `16.9 pp reach vs 8 needed -> REACHABLE,
# 2.1x margin`, on the account that in fact stranded. M4' asks a rate-and-freeze-against-the-clock
# question instead, and RP-21/RP-22 are the pair that proves it can come out BOTH ways.

@test "RP-21: burst_start_by returns LATE for next3's live shape, where the deleted M4 read REACHABLE" {
  # The measured live row at 2026-08-25T09:47:41Z. Arithmetic, walked by hand:
  #   deficit 8 pp -> 8/0.192 = 41.667 session pp; the OPEN window has 87 left, so one window
  #   does it: 41.667/22.87 = 1.822 h (under the 3.37 h the window has left, so not capped).
  #   freeze = 1 * 0.625 * 1.653 = 1.033 h.  t_needed = 2.855.  2.21 - 2.855 = -0.645.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21, "session_pct": 13,
     "session_reset_h": 3.37, "session_reset_at": "2026-08-25T13:07:00Z"}
sb = ca.burst_start_by(r, 0.192)
assert sb is not None, sb
assert -1.0 < sb["h"] < 0.0, sb
assert abs(sb["h"] - (-0.645)) < 0.01, sb
assert sb["verdict"] == "LATE", sb
assert sb["windows"] == 1, sb
assert abs(sb["unrecoverable_pp"] - 2.83) < 0.02, sb
assert ca.fmt_start_by(sb).startswith("⚠ LATE by"), ca.fmt_start_by(sb)
assert "unrecoverable" in ca.fmt_start_by(sb), ca.fmt_start_by(sb)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway returns SLACK, and walks the 5h grid to get there" {
  # next2's live shape. WITHOUT THIS, RP-21 is satisfied by a function that returns LATE always
  # -- which is exactly the degeneracy that killed M4, in the opposite direction.
  #
  # The window count is the load-bearing assertion: 83 pp -> 432.3 session pp, and the open
  # window dies in 0.54 h having bought only 12.3 of them, so SIX windows are needed. A function
  # that divided the deficit by a rate would report ~18.9 h of burn and no grid at all.
  run python3 -c "$LOAD"'
r = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2, "session_pct": 8,
     "session_reset_h": 0.54, "session_reset_at": "2026-08-25T10:20:00Z"}
sb = ca.burst_start_by(r, 0.192)
assert sb is not None, sb
assert sb["h"] > 60.0, sb
assert abs(sb["h"] - 69.59) < 0.05, sb
assert sb["verdict"] == "SLACK", sb
assert sb["windows"] == 6, sb
assert abs(sb["t_needed"] - 27.61) < 0.05, sb
assert sb["unrecoverable_pp"] == 0.0, sb
assert ca.fmt_start_by(sb) == "start by T−28h (70h slack)", ca.fmt_start_by(sb)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the freeze term is LIVE, not decorative" {
  # THE MUTANT A PURELY ARITHMETIC IMPLEMENTATION WOULD SURVIVE. P_WALL is the weakest number in
  # the spec (n = 8, and it is a LOWER bound -- the >=2-sample detector cannot see a freeze under
  # ~13 min at the 6.4 min median cadence), so the one thing that must be pinned is that it
  # PARTICIPATES. Run RP-21's fixture twice, once with the shipped 0.625 and once with 0.0, and
  # assert the executed difference: 1 window * 0.625 * 1.653 = 1.0331 h, not a guess.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21, "session_pct": 13,
     "session_reset_h": 3.37, "session_reset_at": "2026-08-25T13:07:00Z"}
live = ca.burst_start_by(r, 0.192)
ca.P_WALL = 0.0
mutant = ca.burst_start_by(r, 0.192)
assert abs((mutant["h"] - live["h"]) - 1.033) < 0.01, (live, mutant)
# and the freeze is what flips the verdict on this row -- without it next3 is merely tight
assert live["verdict"] == "LATE" and mutant["verdict"] == "START SOON", (live, mutant)
assert mutant["unrecoverable_pp"] == 0.0, mutant
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24 CONTROL: no window open, no fit, no deficit -- abstain, never zero" {
  # Three abstains, and the FIRST is the one with a wrong answer available. A null session stamp
  # means NO WINDOW IS OPEN. Collapsing that to session_pct = 0 would read as "the window is
  # empty, burn away" -- the most favourable reading of a missing measurement, which is exactly
  # what L2 forbids. The other two pin that a refused K fit and an already-closed deficit are
  # states, not zeros.
  run python3 -c "$LOAD"'
base = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21, "session_pct": 13,
        "session_reset_h": 3.37, "session_reset_at": "2026-08-25T13:07:00Z"}
no_window = dict(base, session_pct=None, session_reset_at=None)
assert ca.burst_start_by(no_window, 0.192) is None, ca.burst_start_by(no_window, 0.192)
assert ca.burst_start_by(dict(base, session_reset_at=None), 0.192) is None
assert ca.burst_start_by(base, None) is None            # S1c abstained: K is outside K_SANE
assert ca.burst_start_by(dict(base, weekly_pct=100), 0.192) is None   # nothing left to buy
assert ca.burst_start_by(dict(base, weekly_reset_h=0.0), 0.192) is None
assert ca.burst_start_by(dict(base, weekly_reset_h=200.0), 0.192) is None
assert ca.fmt_start_by(None) is None
# CONTROL: the same row WITH a window open and a live K does NOT abstain, so the asserts above
# are pinning the abstain rule rather than a function that returns None unconditionally.
assert ca.burst_start_by(base, 0.192) is not None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
