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
# S4 · M4′ · burst_start_by — RP-21..RP-24. USAGE_TELEMETRY_100P §5.2 S4, §5.3.
#
# THE PRIMITIVE IS A START TIME, NOT A CAPACITY VERDICT, and RP-21 is the case that records why.
# The synthesis's M4 (`wk_reach_pp`) asked "can this account still reach 100%" — a question that
# is nearly algebraically fixed — and answered `16.9 pp reach vs 8 needed → REACHABLE, 2.1×
# margin` for next3 on the day next3 in fact stranded. M4′ asks a rate-and-freeze-against-the-
# clock question, which can come out either way, and reads the same row LATE by 0.65 h with
# 2.83 pp already unrecoverable. M4 is DELETED; this comment is where an implementer reads that.
#
# RP-22 is what makes RP-21 a test rather than a tautology: a function returning LATE
# unconditionally passes RP-21 and is exactly the degeneracy that killed M4.
# ---------------------------------------------------------------------------------------------

@test "RP-21: burst_start_by returns LATE for next3's live shape — the verdict M4 got backwards" {
  # The measured live row, 2026-08-25T09:47:41Z, at the frozen K. Every intermediate is pinned,
  # not just the answer, because the answer is a difference of two numbers either of which can be
  # wrong in a way the difference hides: need 8/0.192 = 41.67 session pp · one window at
  # BURST_SPPH = 1.822 h · freeze 1 × 0.625 × 1.653 = 1.033 h · t_needed 2.855 h against 2.21 h
  # of runway = −0.645 h. The floor: 8 − 0.192 × 22.87 × (2.21 − 1.033) = 2.83 pp.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
sb = ca.burst_start_by(r, 0.192)
assert sb is not None, sb
assert sb["verdict"] == "LATE", sb
assert -1.0 < sb["h"] < 0.0, sb
assert abs(sb["h"] - (-0.645)) < 0.01, sb
assert sb["windows"] == 1, sb
assert abs(sb["need_spp"] - 41.667) < 0.01, sb
assert abs(sb["freeze_h"] - 1.0331) < 0.001, sb
assert abs(sb["t_needed_h"] - 2.855) < 0.01, sb
assert abs(sb["unrecoverable_pp"] - 2.83) < 0.01, sb
# the RENDER names the floor: "you are late" without "and this much is already gone" invites
# the reader to burst anyway and lose the same pp with the tokens spent.
out = ca.fmt_start_by(sb)
assert out.startswith("⚠ LATE by "), out
assert "pp already unrecoverable" in out, out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway returns SLACK — LATE-always fails here" {
  # next2's live shape. Six windows because the deficit needs 432.3 session pp and one window
  # buys at most 100, so the walk pays four roll waits as well as the burn — 21.41 h of walk
  # plus 6.20 h of expected freeze against 97.2 h of runway = +69.59 h. Without this case,
  # RP-21 is satisfied by `return {"verdict": "LATE", ...}`.
  run python3 -c "$LOAD"'
r = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2,
     "session_pct": 8, "session_reset_h": 0.54}
sb = ca.burst_start_by(r, 0.192)
assert sb is not None, sb
assert sb["verdict"] == "SLACK", sb
assert sb["h"] > 60.0, sb
assert abs(sb["h"] - 69.59) < 0.05, sb
assert sb["windows"] == 6, sb
assert sb["unrecoverable_pp"] == 0.0, sb
assert ca.fmt_start_by(sb) == "start by T−28h (70h slack)", ca.fmt_start_by(sb)
# ...and the THIRD verdict is live too, so the ladder is not two-valued. Same shape, moved so
# that only ~8 h of slack remains: START SOON, and NOT rendered with the LATE clause.
soon = ca.burst_start_by({"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 36.0,
                          "session_pct": 8, "session_reset_h": 0.54}, 0.192)
assert soon["verdict"] == "START SOON", soon
assert 0 < soon["h"] <= ca.START_SOON_H, soon
assert "unrecoverable" not in ca.fmt_start_by(soon), ca.fmt_start_by(soon)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the wall-freeze term is LIVE, not decorative — the arithmetic-only mutant" {
  # Run RP-21's fixture twice, once at the measured P_WALL and once with it forced to 0, and
  # assert the two start times differ by exactly one window's expected freeze: 1 × 0.625 × 1.653
  # = 1.033 h. An implementation that computes the 5h walk correctly and drops the freeze
  # survives RP-21 and RP-22 (both keep their verdicts) and dies here.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
with_wall = ca.burst_start_by(r, 0.192)["h"]
saved = ca.P_WALL
try:
    ca.P_WALL = 0.0
    without = ca.burst_start_by(r, 0.192)["h"]
finally:
    ca.P_WALL = saved
assert abs((without - with_wall) - 1.033) < 0.01, (with_wall, without)
# and with no freeze at all the same row is no longer late — the term is what makes the verdict
assert ca.burst_start_by(r, 0.192)["verdict"] == "LATE"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24: no window open ⇒ ABSTAIN, not zero; and every other abstain arm is live" {
  # A null session stamp means NO 5h WINDOW IS OPEN. Collapsing that to "0% used" would hand the
  # walk a full 100 pp of free burn in the current window and produce the most optimistic start
  # time on the row with the least information — an abstain-shaped input answered confidently.
  run python3 -c "$LOAD"'
base = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
        "session_pct": 13, "session_reset_h": 3.37}
def d(**kw):
    x = dict(base); x.update(kw); return x
assert ca.burst_start_by(d(session_pct=None, session_reset_h=None,
                           session_reset_at=None), 0.192) is None, "null window not abstained"
assert ca.burst_start_by(d(session_reset_at=None), 0.192) is None, "null reset stamp"
assert ca.burst_start_by(base, None) is None, "null K not abstained"        # S1c abstained
assert ca.burst_start_by(d(weekly_pct=100), 0.192) is None, "deficit <= 0"
assert ca.burst_start_by(d(weekly_reset_h=0.0), 0.192) is None, "reset_h outside (0,168]"
assert ca.burst_start_by(d(weekly_reset_h=200.0), 0.192) is None, "reset_h outside (0,168]"
assert ca.fmt_start_by(None) is None
# CONTROL for all five: the same base row, unmutated, still ANSWERS. Without this an
# unconditional `return None` passes every assertion above.
assert ca.burst_start_by(base, 0.192) is not None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24b: an account already AT the 5h wall waits out the roll — §5.2's pseudocode does not" {
  # DEVIATION, PINNED. §5.2 S4's pseudocode guards the open window with `if avail > 0:` and has
  # no else, so an account at session_pct = 100 leaves t at 0 and the walk opens its first full
  # window IMMEDIATELY — free burn out of a window that is exhausted. That is the one shape
  # where M4′ would under-report the start time for the account under the MOST pressure, which
  # is the fail-open direction. The wait is the same one the `rem > 0` arm already performs.
  run python3 -c "$LOAD"'
walled = {"acct": "next3", "weekly_pct": 60, "weekly_reset_h": 40.0,
          "session_pct": 100, "session_reset_h": 4.4}
open_w = dict(walled); open_w["session_pct"] = 0
w, o = ca.burst_start_by(walled, 0.192), ca.burst_start_by(open_w, 0.192)
assert w is not None and o is not None, (w, o)
# the walled row must need MORE time, by roughly the roll it has to sit out
assert w["t_needed_h"] > o["t_needed_h"], (w["t_needed_h"], o["t_needed_h"])
assert w["burn_h"] >= walled["session_reset_h"], w        # the wait is actually in the walk
assert w["h"] < o["h"], (w["h"], o["h"])
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
