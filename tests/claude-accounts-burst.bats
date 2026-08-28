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
# S4 · M4′ · burst_start_by — USAGE_TELEMETRY_100P §5.2 S4, RED-proof cases RP-21..RP-24.
#
# WHAT M4′ IS FOR, AND WHY M4 WAS DELETED. All 8 measured burst windows delivered 13-20 weekly pp
# whether or not they walled, so the loss is not capacity INSIDE the window — it is the frozen
# tail plus the 5h grid. The synthesis's M4 asked a CAPACITY question (`wk_reach_pp`), which is
# nearly algebraically fixed: on next3's live shape it read `16.9 pp reach vs 8 needed —
# REACHABLE, 2.1× margin`, on the account that in fact stranded. M4′ asks a
# rate-and-freeze-against-the-clock question, which can come out either way. RP-21 and RP-22 are
# the pair that pins it: a function returning LATE always passes RP-21 and fails RP-22, which is
# exactly the degeneracy that killed M4.
#
# The fixtures are the live shapes measured at 2026-08-25T09:47:41Z with K = 0.192.

@test "RP-21: burst_start_by returns LATE for next3's live shape, with the unrecoverable floor" {
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
bs = ca.burst_start_by(r, 0.192)
assert bs is not None, bs
assert bs["verdict"] == "LATE", bs
assert -1.0 < bs["h"] < 0.0, bs                       # measured -0.65
assert abs(bs["h"] - (-0.6449)) < 0.01, bs
assert bs["windows"] == 1, bs                         # 41.7 session pp fits the open window
assert abs(bs["t_needed"] - 2.855) < 0.01, bs         # 1.822 h burn + 1.033 h expected freeze
# THE FLOOR, computed as §5.2 states it: freeze 1.033 h of the 2.21 h remaining leaves 1.177 h of
# usable burn = K x BURST_SPPH x 1.177 = 5.17 weekly pp of the 8 needed, so 2.83 pp cannot be
# saved even by a perfect burst starting this instant.
assert abs(bs["unrecoverable_pp"] - 2.832) < 0.01, bs
assert ca.fmt_burst_start(bs) == "⚠ LATE by 0.6h — 2.8pp already unrecoverable", ca.fmt_burst_start(bs)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway returns SLACK — not LATE always" {
  # Without this arm RP-21 is satisfied by `return LATE`, which is the degeneracy that killed M4.
  run python3 -c "$LOAD"'
r = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2,
     "session_pct": 8, "session_reset_h": 0.54}
bs = ca.burst_start_by(r, 0.192)
assert bs is not None, bs
assert bs["verdict"] == "SLACK", bs
assert bs["h"] > 60.0, bs                             # measured +69.59
assert abs(bs["h"] - 69.589) < 0.02, bs
assert bs["windows"] == 6, bs                         # 432.3 session pp needs six 5h windows
assert bs["unrecoverable_pp"] == 0.0, bs              # nothing is lost yet
assert ca.fmt_burst_start(bs) == "start by T−28h (70h slack)", ca.fmt_burst_start(bs)
# ...and the THIRD verdict exists: slack inside the 12 h band is START SOON, not SLACK. Without
# this the band collapses to a binary and the whole point of a start TIME is lost.
soon = ca.burst_start_by({"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 33.0,
                          "session_pct": 8, "session_reset_h": 0.54}, 0.192)
assert soon["verdict"] == "START SOON", soon
assert 0 < soon["h"] <= 12.0, soon
assert ca.fmt_burst_start(soon).startswith("⚠ START SOON — start by T−28h ("), ca.fmt_burst_start(soon)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the wall-freeze term is LIVE, not decorative" {
  # The mutant a purely arithmetic implementation survives: drop the freeze and every verdict
  # still looks plausible. Setting P_WALL to 0 must move next3 by exactly one window's expected
  # freeze -- 1 x 0.625 x 1.653 = 1.033 h -- and must flip the verdict off LATE, because the
  # freeze is the entire reason that account is late.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37}
with_wall = ca.burst_start_by(r, 0.192)
ca.P_WALL = 0.0
without = ca.burst_start_by(r, 0.192)
assert abs((without["h"] - with_wall["h"]) - 1.033) < 0.01, (with_wall, without)
assert with_wall["verdict"] == "LATE" and without["verdict"] == "START SOON", (with_wall, without)
assert without["freeze_h"] == 0.0, without
# the floor moves with it too — it is the same freeze term, not a second constant
assert without["unrecoverable_pp"] == 0.0, without
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24 CONTROL: no window open ⇒ abstain, and a null K abstains rather than fabricating" {
  # A null session stamp means NO WINDOW IS OPEN — a distinct state that must not collapse to
  # `session_pct = 0`, which would hand the walk a free full window it does not have. 15.0% of
  # series rows carry it. And a null K is S1c refusing: every session→weekly conversion below
  # would be a fabricated number, so the metric says nothing rather than something.
  run python3 -c "$LOAD"'
base = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
        "session_pct": 13, "session_reset_h": 3.37}
assert ca.burst_start_by(dict(base, session_pct=None, session_reset_h=None), 0.192) is None
assert ca.burst_start_by(dict(base, session_reset_h=None), 0.192) is None
assert ca.burst_start_by(base, None) is None                    # S1c abstained
assert ca.burst_start_by(base, 0.0) is None
assert ca.burst_start_by(dict(base, weekly_pct=100), 0.192) is None   # nothing left to start for
assert ca.burst_start_by(dict(base, weekly_reset_h=0.0), 0.192) is None
assert ca.burst_start_by(dict(base, weekly_reset_h=200.0), 0.192) is None
assert ca.fmt_burst_start(None) is None
# ...and a `session_pct = 0` row is NOT the same abstain — an OPEN and empty window is a real
# state with a real full window in it. Collapsing the two is the defect this case pins.
open_empty = ca.burst_start_by(dict(base, session_pct=0), 0.192)
assert open_empty is not None and open_empty["windows"] == 1, open_empty
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
