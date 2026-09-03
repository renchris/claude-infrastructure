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

# ── S4 · M4′ · burst_start_by — the start-time constraint ──────────────────────────────────────
#
# WHY THIS FUNCTION AND NOT THE SYNTHESIS'S M4. `wk_reach_pp` asked a CAPACITY question — "can
# the remaining hours reach the deficit?" — and `reach_pp` and `need` are both monotone in
# (weekly_pct, hours-remaining), so it is an algebraic restatement of what it supplements. It
# read REACHABLE on 99.37% of the series and on 100% of the 74 samples inside the 5 wall
# episodes it was written to catch. DELETED (USAGE_TELEMETRY_100P §5.5).
#
# RP-21 IS THE CASE THAT RECORDS THE DELETION. On next3's live shape M4 reads
# `16.9 pp reach vs 8 needed → REACHABLE, 2.1× margin`; M4′ reads LATE by 0.65 h with 2.83 pp
# already unrecoverable. next3 in fact stranded. Restoring a capacity form to satisfy an older
# assertion re-introduces a metric that cannot be wrong.

@test "RP-21: burst_start_by returns LATE for next3's live shape" {
  # The measured live row, 2026-08-25T09:47:41Z, K = 0.192.
  #   deficit 8 pp → 41.67 session pp → 1.822 h of burn inside the OPEN window (87 pp of room,
  #   3.37 h before it rolls, so the grid never binds) → one window opened → freeze 1.033 h →
  #   t_needed 2.855 h against 2.21 h remaining → −0.645 h.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": iso(NOW + 3.37 * 3600)}
bs = ca.burst_start_by(r, 0.192)
assert bs is not None, bs
assert -1.0 < bs["h"] < 0.0, bs
assert abs(bs["h"] - (-0.645)) < 0.01, bs
assert bs["verdict"] == "LATE", bs
assert bs["windows"] == 1, bs
assert abs(bs["need_spp"] - 41.667) < 0.01, bs
assert abs(bs["unrecoverable_pp"] - 2.83) < 0.01, bs
# the ONE rendering, and it leads with the floor: "late by X" is actionable only beside
# "and this much can no longer be saved at all".
assert ca.fmt_start_by(bs) == "⚠ LATE by 0.6h — 2.8pp already unrecoverable", ca.fmt_start_by(bs)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway returns SLACK" {
  # next2's live shape. Without this, RP-21 is satisfied by a function that returns LATE always
  # — which is exactly the degeneracy, in the other direction, that killed M4.
  #   deficit 83 pp → 432.3 session pp; the open window has 0.54 h left so it contributes 12.4 pp
  #   and the walk then takes 5 more windows on the 5 h grid → 21.41 h of elapsed burn, freeze
  #   6.20 h, t_needed 27.61 h against 97.2 h remaining.
  run python3 -c "$LOAD"'
r = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2,
     "session_pct": 8, "session_reset_h": 0.54, "session_reset_at": iso(NOW + 0.54 * 3600)}
bs = ca.burst_start_by(r, 0.192)
assert bs is not None, bs
assert bs["h"] > 60.0, bs
assert abs(bs["h"] - 69.59) < 0.05, bs
assert bs["verdict"] == "SLACK", bs
assert bs["windows"] == 6, bs
assert abs(bs["t_needed_h"] - 27.61) < 0.05, bs
assert bs["unrecoverable_pp"] == 0.0, bs
assert ca.fmt_start_by(bs) == "start by T−28h (70h slack)", ca.fmt_start_by(bs)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22b CONTROL: the middle verdict exists and is flagged — START SOON is not SLACK" {
  # A two-arm verdict (LATE / not-LATE) passes RP-21 and RP-22 and says nothing at the only
  # moment a start time is actionable. next3's deficit against a 10 h horizon: t_needed 2.855 h,
  # slack 7.1 h — inside START_BY_SOON_H, so it must carry the warning glyph, not read SLACK.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 10.0,
     "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": iso(NOW + 3.37 * 3600)}
bs = ca.burst_start_by(r, 0.192)
assert bs["verdict"] == "START SOON", bs
assert 7.0 < bs["h"] < 7.2, bs
assert ca.fmt_start_by(bs).startswith("⚠ START SOON — start by T−3h"), ca.fmt_start_by(bs)
# ...and the boundary itself belongs to SLACK, so the two arms cannot both claim it.
far = dict(r, weekly_reset_h=40.0)
assert ca.burst_start_by(far, 0.192)["verdict"] == "SLACK", ca.burst_start_by(far, 0.192)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the freeze term is LIVE, not decorative" {
  # RP-21's fixture run twice, P_WALL = 0.625 and P_WALL = 0.0, injected on the module. The two
  # start-by values must differ by exactly one window's expected freeze, 0.625 * 1.653 = 1.033 h.
  # This is the mutant a purely arithmetic implementation — one that computes the burn walk and
  # drops the freeze — survives, and it survives every other case in this file.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": iso(NOW + 3.37 * 3600)}
with_wall = ca.burst_start_by(r, 0.192)["h"]
ca.P_WALL = 0.0
without = ca.burst_start_by(r, 0.192)["h"]
assert abs((without - with_wall) - 1.033) < 0.01, (with_wall, without)
# and with no freeze the same row is no longer late at all — the term decides the verdict
assert ca.burst_start_by(r, 0.192)["verdict"] == "START SOON", ca.burst_start_by(r, 0.192)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24 CONTROL: no window open, and a null K, each ABSTAIN rather than reading zero" {
  # Four arms, and the first is the one that would read plausibly. A null session_reset_at means
  # NO 5h WINDOW IS OPEN (15.0% of rows) — a state, not an empty window. Collapsing it to
  # session_pct = 0 would hand the walk a free 100 pp of room and report SLACK on an account
  # that cannot start at all. Nulls: no window · no K · deficit closed · reset out of band.
  run python3 -c "$LOAD"'
base = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
        "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": iso(NOW + 3.37 * 3600)}
assert ca.burst_start_by(dict(base, session_reset_at=None, session_pct=None), 0.192) is None
assert ca.burst_start_by(dict(base, session_reset_at=None), 0.192) is None
assert ca.burst_start_by(base, None) is None, "a null K did not abstain"
assert ca.burst_start_by(dict(base, weekly_pct=100), 0.192) is None, "closed deficit"
assert ca.burst_start_by(dict(base, weekly_reset_h=0.0), 0.192) is None
assert ca.burst_start_by(dict(base, weekly_reset_h=200.0), 0.192) is None
assert ca.fmt_start_by(None) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
