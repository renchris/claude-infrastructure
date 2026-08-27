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

# ---- S4 · M4′ burst_start_by — RP-21..RP-24 ---------------------------------------------------
#
# THE DELETION THIS RECORDS. The synthesis shipped M4 `wk_reach_pp`, a CAPACITY question: is the
# remaining deficit reachable inside the window? Run against next3's measured live row it answers
# `16.9 pp reach vs 8 needed — REACHABLE, 2.1× margin` — and next3 in fact stranded that window.
# The question is nearly algebraically fixed, so it can only ever answer yes. M4′ asks a
# rate-and-freeze-against-the-clock question instead, reads the SAME row as LATE by 0.65 h with
# 2.83 pp already unrecoverable, and can come out either way (RP-22 is the proof that it does).

@test "RP-21: burst_start_by reads next3's live shape as LATE, with an unrecoverable floor" {
  # The measured row at 2026-08-25T09:47:41Z. deficit 8 pp / K 0.192 = 41.67 session pp; at
  # BURST_SPPH that is 1.82 h of burn inside the OPEN window (avail 87 pp, 3.37 h left, so the
  # window does not bind); one window ⇒ freeze 1.03 h; t_needed 2.86 h against 2.21 h of runway.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": "2026-08-25T13:09:41Z"}
bs = ca.burst_start_by(r, 0.192)
assert bs is not None, bs
assert bs["verdict"] == "LATE", bs
assert -1.0 < bs["h"] < 0.0, bs                      # measured -0.65
assert abs(bs["h"] - (-0.645)) < 0.02, bs
assert bs["windows"] == 1, bs
assert abs(bs["freeze_h"] - 1.033) < 0.01, bs
assert abs(bs["need_spp"] - 41.667) < 0.01, bs
assert abs(bs["unrecoverable_pp"] - 2.832) < 0.02, bs   # 8 - 0.192*22.87*(2.21-1.033)
# The floor, not the clock, leads the string: "LATE by 0.6h" alone reads as a scheduling slip.
assert ca.fmt_burst_start(bs) == "⚠ LATE by 0.6h — 2.8pp already unrecoverable", ca.fmt_burst_start(bs)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway returns SLACK — the metric is not LATE-always" {
  # Without this arm RP-21 is satisfied by `return LATE`, which is the mirror image of the
  # degeneracy that killed M4. next2 live: 83 pp deficit = 432.3 session pp = 6 windows,
  # 21.41 h of burn + 6.20 h of freeze = 27.61 h against 97.2 h of runway.
  run python3 -c "$LOAD"'
r = {"acct": "next2", "weekly_pct": 17, "weekly_reset_h": 97.2,
     "session_pct": 8, "session_reset_h": 0.54, "session_reset_at": "2026-08-25T10:20:00Z"}
bs = ca.burst_start_by(r, 0.192)
assert bs is not None and bs["verdict"] == "SLACK", bs
assert bs["h"] > 60.0, bs
assert abs(bs["h"] - 69.59) < 0.05, bs
assert bs["windows"] == 6, bs                        # the 5h GRID, not one long burn
assert abs(bs["t_needed_h"] - 27.61) < 0.05, bs
assert bs["unrecoverable_pp"] == 0.0, bs             # a slack account has no floor, not a negative one
assert ca.fmt_burst_start(bs) == "start by T−28h (70h slack)", ca.fmt_burst_start(bs)
# ...and the middle verdict exists and is reachable: same shape, 8 h of runway left.
soon = ca.burst_start_by({"acct": "n", "weekly_pct": 88, "weekly_reset_h": 8.0,
                          "session_pct": 8, "session_reset_h": 4.0,
                          "session_reset_at": "x"}, 0.192)
assert soon["verdict"] == "START SOON", soon
assert 0.0 < soon["h"] <= 12.0, soon
assert ca.fmt_burst_start(soon).startswith("⚠ START SOON — start by T−"), ca.fmt_burst_start(soon)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the wall-freeze term is LIVE, not decorative" {
  # The mutant a purely arithmetic implementation survives: drop the freeze and every verdict
  # shifts by exactly windows × P_WALL × MEAN_WALL_H. RP-21'"'"'s row is one window, so 1.033 h --
  # the EXECUTED value, and enough on its own to flip that row from LATE to START SOON.
  run python3 -c "$LOAD"'
r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
     "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": "2026-08-25T13:09:41Z"}
with_wall = ca.burst_start_by(r, 0.192)
ca.P_WALL = 0.0                                      # module constant, read at call time
without = ca.burst_start_by(r, 0.192)
ca.P_WALL = 0.625
assert abs((without["h"] - with_wall["h"]) - 1.033) < 0.01, (with_wall, without)
assert without["freeze_h"] == 0.0, without
assert with_wall["verdict"] == "LATE" and without["verdict"] == "START SOON", (with_wall, without)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24 CONTROL: no window open ⇒ abstain, and an unpriced session pp ⇒ abstain" {
  # A null session stamp is a STATE -- no 5h window is open -- and collapsing it to zero hours of
  # remaining window would silently report the tightest possible schedule for the emptiest row.
  # In production session_reset_h IS hrs_until(session_reset_at), so both spellings are one fact;
  # each is pinned separately so neither check can be dropped while the other still passes.
  run python3 -c "$LOAD"'
base = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
        "session_pct": 13, "session_reset_h": 3.37, "session_reset_at": "2026-08-25T13:09:41Z"}
assert ca.burst_start_by(base, 0.192) is not None                       # the positive control
assert ca.burst_start_by(dict(base, session_pct=None,
                              session_reset_h=None, session_reset_at=None), 0.192) is None
assert ca.burst_start_by(dict(base, session_pct=None), 0.192) is None
assert ca.burst_start_by(dict(base, session_reset_h=None), 0.192) is None
# K abstained (outside K_SANE, S1c): weekly pp cannot be bought at an unknown price.
assert ca.burst_start_by(base, None) is None
assert ca.burst_start_by(base, 0.0) is None
# the deficit is already closed, and a weekly stamp outside its own bucket is bad data
assert ca.burst_start_by(dict(base, weekly_pct=100), 0.192) is None
assert ca.burst_start_by(dict(base, weekly_reset_h=200.0), 0.192) is None
assert ca.burst_start_by(dict(base, weekly_reset_h=0.0), 0.192) is None
assert ca.fmt_burst_start(None) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24b: the drain block carries the start-by clause and names K — on strand rows only" {
  # The render half. Three properties: (a) the header names K AND its source, because `frozen`
  # and `live` are different claims; (b) the clause rides the strand rows beside M5; (c) it does
  # NOT ride the no-strand row -- a start time for a burst that rescues nothing is noise.
  run python3 -c "$LOAD"'
def row(**kw):
    base = dict(acct="a", session_pct=10, session_reset_h=3.0, session_reset_at="x",
                weekly_pct=40, weekly_reset_h=24.0, exchange_k=0.1969, exchange_k_src="live")
    base.update(kw); return base
n4 = row(acct="next4", weekly_pct=14, weekly_reset_h=119.2, burn_wk_ewma_ph=0.186)
n3 = row(acct="next3", weekly_pct=92, weekly_reset_h=2.21, session_pct=13, session_reset_h=3.37,
         burn_wk_ewma_ph=1.140)
n1 = row(acct="next", weekly_pct=52, weekly_reset_h=114.21, burn_wk_ewma_ph=1.725)
line = ca.pace_line([n3, n1, n4])
assert line.startswith("weekly drain — pp that DIE at reset (K=0.197 live · nowcast"), line
assert "nowcast at the last 48h of pace" in line, line     # the S3 caption is intact
assert "next4 strand ~64pp of 86 · start by T−" in line, line
assert "⚠ LATE by" in line and "pp already unrecoverable" in line, line
# (c) the zero-strand row keeps its wall read and gains NO start-by clause
tail = line.rstrip().split(chr(10))[-1]
assert tail.strip().startswith("next no strand"), line
assert "start by" not in tail and "LATE" not in tail, tail
# ...and with no K stamped the header falls back and every clause abstains -- the strand, which
# consumes no K at all, still renders. Gating it on K would be a fabricated dependency.
noK = ca.pace_line([{k: v for k, v in n4.items() if not k.startswith("exchange_k")}])
assert noK.startswith("weekly drain — pp that DIE at reset (nowcast"), noK
assert "start by" not in noK and "K=" not in noK, noK
assert "next4 strand ~64pp of 86" in noK, noK
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
