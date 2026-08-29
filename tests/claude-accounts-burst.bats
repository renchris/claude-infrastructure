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

@test "RP-21: burst_start_by returns LATE for next3's live shape, with the unrecoverable floor" {
  # USAGE_TELEMETRY_100P §5.2 S4 (M4'), §5.3 RP-21. The measured live row at 2026-08-25T09:47:41Z.
  #
  # THIS IS THE CASE THAT SEPARATES M4' FROM THE DELETED M4, and the deletion is recorded here
  # because this is where an implementer reads it. The synthesis's `wk_reach_pp` asked a CAPACITY
  # question — K * BURST_SPPH * weekly_reset_h = 0.192 * 22.87 * 2.21 = 9.70 pp of reach against
  # 8 pp needed — and answered REACHABLE with a 1.2x margin (the synthesis published 16.9 pp on a
  # wider reach term, i.e. 2.1x). next3 in fact stranded. Capacity is nearly algebraically fixed:
  # a metric that cannot return the unwelcome answer is not a measurement. M4' asks a
  # rate-and-freeze-against-the-clock question and reads LATE by 0.65 h.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
sb = ca.burst_start_by(r, 0.192)
assert sb is not None, sb
assert -1.0 < sb["h"] < 0.0, sb                       # measured -0.65
assert abs(sb["h"] + 0.645) < 0.02, sb
assert sb["verdict"] == "LATE", sb
assert sb["windows"] == 1, sb                         # the OPEN window alone can carry the burn
assert abs(sb["burn_h"] - 1.822) < 0.01, sb
assert abs(sb["freeze_h"] - 1.033) < 0.01, sb
assert abs(sb["t_needed_h"] - 2.855) < 0.02, sb
# the floor: freeze eats 1.03 h of the 2.21 h left, so only 1.18 h converts at K -> 5.17 pp of
# the 8 needed. 2.83 pp cannot be saved even by a perfect burst starting this instant.
assert abs(sb["unrecoverable_pp"] - 2.83) < 0.05, sb
# CONTROL on the DELETED metric, inline, so the fixture provably discriminates the two QUESTIONS
# and not merely two numbers. The old code is gone; its answer must not be.
reach = 0.192 * ca.BURST_SPPH * r["weekly_reset_h"]
assert reach > 8.0, reach                             # M4 said REACHABLE on the account that stranded
assert ca.fmt_start_by(sb) == "⚠ LATE by 0.6h — 2.8pp already unrecoverable", ca.fmt_start_by(sb)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway returns SLACK, and pays the 5h grid" {
  # RP-21 is satisfied by a function that returns LATE always — the exact degeneracy that killed
  # M4. next2's live shape needs 432 session pp, i.e. six 5h windows, and the grid's dead time is
  # what makes that 27.6 h rather than the 21.4 h of pure burn. Without this arm the grid walk
  # could be deleted and RP-21 would stay green.
  run python3 -c "$LOAD"'
r = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2,
     "session_pct": 8, "session_reset_h": 0.54}
sb = ca.burst_start_by(r, 0.192)
assert sb is not None, sb
assert sb["h"] > 60.0, sb                             # measured +69.59
assert abs(sb["h"] - 69.59) < 0.3, sb
assert sb["verdict"] == "SLACK", sb
assert sb["windows"] == 6, sb
assert abs(sb["freeze_h"] - 6.199) < 0.02, sb
# the grid is LIVE: pure burn of 432.3 session pp at 22.87 pp/h is 18.90 h; the walk reads 21.41
# because the open window dies at 0.54 h and five roll-waits of 0.63 h are paid after it.
assert abs(sb["burn_h"] - 21.41) < 0.05, sb
assert sb["burn_h"] > 432.3 / ca.BURST_SPPH + 2.0, sb
assert sb["unrecoverable_pp"] == 0.0, sb              # nothing is lost yet
assert ca.fmt_start_by(sb) == "start by T−28h (70h slack)", ca.fmt_start_by(sb)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the freeze term is LIVE, not decorative" {
  # The mutant a purely arithmetic implementation survives: drop the wall-freeze term entirely
  # and every OTHER case here still passes, because the burn walk alone already discriminates.
  # P_WALL is injected through the module constant, so this pins that the shipped value is the
  # one the shipped code reads — a hard-coded 1.033 h inside the function fails here.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
with_wall = ca.burst_start_by(r, 0.192)["h"]
ca.P_WALL = 0.0
without = ca.burst_start_by(r, 0.192)["h"]
assert abs((without - with_wall) - 1.033) < 0.01, (with_wall, without)
# ...and the freeze is what FLIPS the verdict, which is why it is not decorative: with no wall
# next3 is not late at all.
assert ca.burst_start_by(r, 0.192)["verdict"] == "START SOON", "freeze does not change the verdict"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24 CONTROL: every abstain arm returns None, never a zero" {
  # RP-24 proper is the null session stamp: a null stamp means NO WINDOW IS OPEN, a distinct
  # state (15.0% of rows) that must not collapse to "0% used, go ahead" — which is what a
  # `session_pct or 0` would do, and it would read as the most permissive possible input.
  run python3 -c "$LOAD"'
base = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
        "session_pct": 13, "session_reset_h": 3.37}
def v(**kw):
    r = dict(base); r.update(kw); return r
assert ca.burst_start_by(v(session_pct=None, session_reset_at=None,
                           session_reset_h=None), 0.192) is None    # RP-24
assert ca.burst_start_by(base, None) is None            # K abstained (S1c) — no fallback rate
assert ca.burst_start_by(base, 0.0) is None
assert ca.burst_start_by(v(weekly_pct=100), 0.192) is None          # deficit already closed
assert ca.burst_start_by(v(weekly_pct=None), 0.192) is None
assert ca.burst_start_by(v(weekly_reset_h=0.0), 0.192) is None      # outside (0, 168]
assert ca.burst_start_by(v(weekly_reset_h=200.0), 0.192) is None
assert ca.fmt_start_by(None) is None
# CONTROL: the base row itself is NOT None, so the arms above are abstains and not a stub.
assert ca.burst_start_by(base, 0.192) is not None
# an EXHAUSTED open window waits for its own roll rather than opening the next one instantly:
# §5.2 pseudocode leaves t at 0 here, which violates the grid constraint it states one line up.
full = ca.burst_start_by(v(session_pct=100, session_reset_h=2.0), 0.192)
assert full["burn_h"] >= 2.0, full
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
