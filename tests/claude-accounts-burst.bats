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

# ---- S4 · M4′ · burst_start_by — the START-TIME constraint (RP-21..RP-24) ---------------------
#
# WHAT THIS HALF OF THE SUITE IS FOR. M5 above says whether the required rate is routine for the
# account. It does NOT say whether there is still TIME to run it. All 8 observed burst windows
# delivered 13–20 weekly pp whether or not they walled, so the loss is never burn capacity WITHIN
# a window — it is the frozen tail plus the 5h grid, i.e. a START TIME.
#
# THE DELETED M4 IS THE REASON THIS SHAPE IS PINNED, NOT JUST ITS ARITHMETIC. The synthesis's
# `wk_reach_pp` asked a CAPACITY question — "could a perfect burst reach 100?" — and both sides of
# it are monotone in (weekly_pct, hours-remaining), so it read REACHABLE on 99.37% of the series
# and on 100% of the 74 samples inside the 5 wall episodes it was written to catch. On next3's
# live shape it read `16.9 pp reach vs 8 needed — REACHABLE, 2.1× margin`, and next3 in fact
# stranded. M4′ asks a rate-and-freeze-against-the-clock question, which can come out either way:
# RP-21 is the LATE verdict on that same row, and RP-22 is the control that proves the metric is
# not the constant LATE that a degenerate implementation would ship.
#
# RETURN SHAPE — a dict, not the bare float §5.3 RP-21 sketches, for S2's reason: the verdict and
# the unrecoverable floor are different facts from the hours, and a float cannot carry them.

@test "RP-21: burst_start_by returns LATE for next3's live shape, with the unrecoverable floor" {
  # The measured row at 2026-08-25T09:47:41Z. deficit 8 pp -> 41.67 session pp at K=0.192 ->
  # 1.82 h of burn in the OPEN window (87 pp of room, 3.37 h before it rolls), + one expected
  # wall freeze of 1.03 h = 2.86 h needed against 2.21 h left.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": iso(NOW + 3.37 * 3600.0)}
sb = ca.burst_start_by(r, 0.192)
assert sb is not None, sb
assert -1.0 < sb["h"] < 0.0, sb                       # measured -0.645
assert abs(sb["h"] - -0.645) < 0.01, sb
assert sb["verdict"] == "LATE", sb
assert sb["windows"] == 1, sb                          # the open window alone carries the burn
assert abs(sb["freeze_h"] - 1.033) < 0.01, sb
assert abs(sb["unrecoverable_pp"] - 2.83) < 0.02, sb   # a PERFECT burst starting now loses 2.83 pp
assert "LATE" in ca.fmt_start_by(sb) and "unrecoverable" in ca.fmt_start_by(sb), ca.fmt_start_by(sb)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway returns SLACK, and a mid-band row START SOON" {
  # Without this arm RP-21 is satisfied by a function that returns LATE always — which is exactly
  # the degeneracy that killed M4, in the opposite direction. next2's live shape needs 432 session
  # pp = 6 windows = 21.4 h of burn + 6.2 h of expected freeze against 97.2 h of runway.
  #
  # The THIRD verdict is pinned in the same case deliberately: a two-branch implementation passes
  # both RP-21 and the SLACK arm and never renders START SOON at all.
  run python3 -c "$LOAD"'
n2 = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2,
      "session_pct": 8, "session_reset_h": 0.54, "session_reset_at": iso(NOW + 0.54 * 3600.0)}
sb = ca.burst_start_by(n2, 0.192)
assert sb is not None, sb
assert sb["h"] > 60.0, sb                              # measured +69.59
assert abs(sb["h"] - 69.59) < 0.05, sb
assert sb["verdict"] == "SLACK", sb
assert sb["windows"] == 6, sb                          # the 5h grid, walked
assert sb["unrecoverable_pp"] == 0.0, sb               # nothing is lost yet, and a negative floor
                                                       # is not a negative loss — it clamps to 0
assert "start by T" in ca.fmt_start_by(sb), ca.fmt_start_by(sb)
assert "slack" in ca.fmt_start_by(sb), ca.fmt_start_by(sb)
# mid band: 20 pp deficit, a full open window and 14 h of runway -> 8.25 h needed, 5.75 h spare
soon = {"acct": "next", "weekly_pct": 80, "weekly_reset_h": 14.0,
        "session_pct": 0, "session_reset_h": 6.0, "session_reset_at": iso(NOW + 6.0 * 3600.0)}
sb2 = ca.burst_start_by(soon, 0.192)
assert 5.5 < sb2["h"] < 6.0, sb2
assert sb2["verdict"] == "START SOON", sb2
assert "START SOON" in ca.fmt_start_by(sb2), ca.fmt_start_by(sb2)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the wall-freeze term is LIVE, not decorative" {
  # The mutant a purely arithmetic implementation survives. Run RP-21's fixture twice, once with
  # P_WALL at its shipped 0.625 and once at 0.0, and assert the two answers differ by exactly the
  # freeze this row expects: 1 window x 0.625 x 1.653 h = 1.033 h. If the freeze were dropped the
  # verdict on next3 flips from LATE to START SOON, i.e. the freeze is the whole finding.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": iso(NOW + 3.37 * 3600.0)}
with_wall = ca.burst_start_by(r, 0.192)
ca.P_WALL = 0.0
try:
    no_wall = ca.burst_start_by(r, 0.192)
finally:
    ca.P_WALL = 0.625
assert abs((no_wall["h"] - with_wall["h"]) - 1.033) < 0.01, (with_wall, no_wall)
assert no_wall["freeze_h"] == 0.0, no_wall
assert no_wall["verdict"] == "START SOON" and with_wall["verdict"] == "LATE", (with_wall, no_wall)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24 CONTROL: every abstain arm — no window open, no K, no deficit, a stamp out of band" {
  # L2. A null session stamp means NO WINDOW IS OPEN — a distinct state that must not collapse to
  # "a window with zero room", which is what a `.get(..., 0)` would silently make of it. And the
  # K arm is the one this metric genuinely depends on (the strand does NOT, §5.7 Deviation 1):
  # start-time arithmetic is the FIRST consumer of the exchange rate, so when exchange_rate
  # abstains this must abstain with it rather than substituting the frozen literal itself.
  run python3 -c "$LOAD"'
base = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
        "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": iso(NOW + 3.37 * 3600.0)}
def var(**kw):
    d = dict(base); d.update(kw); return d
assert ca.burst_start_by(var(session_reset_at=None, session_pct=None), 0.192) is None
assert ca.burst_start_by(var(session_reset_at=None), 0.192) is None
assert ca.burst_start_by(var(session_pct=None), 0.192) is None
assert ca.burst_start_by(base, None) is None            # exchange_rate abstained
assert ca.burst_start_by(base, 0.0) is None             # a zero rate is a division, not a fact
assert ca.burst_start_by(var(weekly_pct=100), 0.192) is None    # nothing left to buy
assert ca.burst_start_by(var(weekly_pct=None), 0.192) is None
assert ca.burst_start_by(var(weekly_reset_h=0.0), 0.192) is None
assert ca.burst_start_by(var(weekly_reset_h=200.0), 0.192) is None   # outside the weekly bucket
assert ca.fmt_start_by(None) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24b: the drain block carries K in its header and the start-time clause on its rows" {
  # THE HEADER CLAUSE ENTERS HERE, not with S3. §5.7 Deviation 1 held it back because M3a is pure
  # weekly-space arithmetic and consumes no K at all; rendering a coefficient nothing on the line
  # consumed is the metric shape §3.2 forbids. S4 is its first consumer, so it renders now.
  #
  # K IS READ OFF THE ROW, unlike the strand, which pace_line recomputes. That is not an
  # inconsistency: the strand is a per-row derivation the renderer can redo, and K is a FLEET fit
  # over the utilization series, which the renderer does not hold. When it is absent the header
  # keeps its S3 spelling and every start-time clause abstains with it — the CONTROL arm below.
  run python3 -c "$LOAD"'
n3 = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21, "burn_wk_ewma_ph": 1.140,
      "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": iso(NOW + 3.37 * 3600.0),
      "k_exch": 0.192, "k_exch_src": "live"}
n2 = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2, "burn_wk_ewma_ph": 0.281,
      "session_pct": 8, "session_reset_h": 0.54, "session_reset_at": iso(NOW + 0.54 * 3600.0),
      "k_exch": 0.192, "k_exch_src": "live"}
line = ca.pace_line([n3, n2])
assert line.startswith("weekly drain — pp that DIE at reset"), line   # the invariant is unmoved
assert "K=0.192 live" in line, line
assert "nowcast at the last 48h of pace" in line, line
assert "next2 strand ~56pp of 83 · start by T−28h (70h slack)" in line, line
assert "next3 strand ~5pp of 8 · ⚠ LATE by 0.6h — 2.8pp already unrecoverable" in line, line
# CONTROL — no K stamped: the S3 header, and NO start-time clause anywhere. An implementation
# that falls back to K_FROZEN here would render a start time off a coefficient that abstained.
bare = ca.pace_line([dict(n3, k_exch=None, k_exch_src=None),
                     dict(n2, k_exch=None, k_exch_src=None)])
assert bare.startswith("weekly drain — pp that DIE at reset (nowcast"), bare
assert "K=" not in bare, bare
assert "start by" not in bare and "LATE" not in bare, bare
assert "next3 strand ~5pp of 8" in bare, bare          # the strand does NOT gate on K
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
