#!/usr/bin/env bats
# burst_start_by — the START-TIME constraint. USAGE_TELEMETRY_100P §5.2 S4 (M4′), RED-proof
# cases RP-21..RP-24 plus the controls the spec's own house rule 3 requires for the two
# branches it does not name.
#
# WHAT M4′ REPLACED, AND WHY THE REPLACEMENT IS NOT COSMETIC. The synthesis's M4 asked a
# CAPACITY question — `wk_reach_pp` vs `need` — and both sides of that comparison are monotone
# in the same two variables (weekly_pct, hours remaining), so it is very nearly an algebraic
# restatement of what it was supposed to supplement. Measured, it read REACHABLE on 99.37% of
# the series and on 100% of the 74 samples inside the 5 wall episodes it was written to catch.
# On next3's live shape (RP-21 below) M4 read `16.9 pp reach vs 8 needed — REACHABLE, 2.1×
# margin`; next3 in fact stranded. M4′ asks a RATE-AND-FREEZE-AGAINST-THE-CLOCK question, which
# can come out either way, and on the same shape reads LATE by 0.65 h with 2.83 pp already
# unrecoverable. RP-22 is the control that pins "can come out either way": without it, RP-21 is
# satisfied by a function that returns LATE always — which is the mirror image of the degeneracy
# that killed M4.
#
# RP-23 IS THE MUTANT KILLER. Three constants (BURST_SPPH, P_WALL, MEAN_WALL_H) are fitted on
# n = 8 burst windows, and P_WALL is a lower bound. A purely arithmetic implementation that
# dropped the freeze term entirely would survive RP-21, RP-22 and RP-24. RP-23 executes the
# subject twice with P_WALL injected at 0.625 and 0.0 and asserts the two answers differ by the
# executed 1.033 h, so the weakest number in the spec at least has its PARTICIPATION pinned.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; every row passed explicitly, so
# no case touches the live series, the keychain or a config.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
}

LOAD='
import importlib.machinery, importlib.util, os, sys
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
K = 0.192
def row(**kw):
    """A row with a 5h window OPEN. session_reset_at is a STAMP, not an hour count: its
    presence is what says a window exists at all, and RP-24 turns it off."""
    r = {"acct": "next3", "weekly_pct": 92, "weekly_reset_h": 2.21,
         "session_pct": 13, "session_reset_h": 3.37,
         "session_reset_at": "2026-08-25T13:09:00Z"}
    r.update(kw)
    return r
'

@test "RP-21: burst_start_by reads next3's live shape as LATE, with a named unrecoverable floor" {
  # The measured live row at 2026-08-25T09:47:41Z. The walk: 8 weekly pp deficit / K = 41.67
  # session pp, all of which fit in the OPEN window's 87 pp remainder, so one window and
  # 41.67/22.87 = 1.822 h of burn; freeze = 1 x 0.625 x 1.653 = 1.033 h; t_needed = 2.855 h
  # against 2.21 h of runway => -0.65 h.
  #
  # THE DELETED M4 ANSWERS THE OPPOSITE ON THIS EXACT ROW: `wk_reach_pp` = 16.9 pp against 8
  # needed => REACHABLE with 2.1x margin. next3 stranded. That inversion is the whole reason
  # M4 is deleted rather than kept as a second opinion, and it is recorded here because this
  # is where an implementer tempted to "restore the capacity check" will be reading.
  run python3 -c "$LOAD"'
sb = ca.burst_start_by(row(), K)
assert sb is not None, sb
assert -1.0 < sb["h"] < 0.0, sb
assert abs(sb["h"] - -0.645) < 0.01, sb
assert sb["verdict"] == "LATE", sb
assert sb["windows"] == 1, sb
assert abs(sb["need_spp"] - 41.667) < 0.01, sb
assert abs(sb["freeze_h"] - 1.033) < 0.01, sb
assert abs(sb["unrecoverable_pp"] - 2.83) < 0.02, sb
assert ca.fmt_start_by(sb) == "⚠ LATE by 0.6h — 2.8pp already unrecoverable", \
    ca.fmt_start_by(sb)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: an account with days of runway reads SLACK — the verdict is not a constant" {
  # next2's live shape. 83 pp deficit = 432.3 session pp, which does NOT fit the open window:
  # 0.54 h of it, then wait out the roll, then five more windows on the 5 h grid => 21.41 h of
  # burn + 6.20 h of expected freeze = 27.61 h against 97.2 h of runway => +69.59 h.
  #
  # Without this case RP-21 is satisfied by `return {"h": -0.65, "verdict": "LATE"}`.
  run python3 -c "$LOAD"'
sb = ca.burst_start_by(row(acct="next2", weekly_pct=17, weekly_reset_h=97.2,
                           session_pct=8, session_reset_h=0.54), K)
assert sb is not None, sb
assert sb["h"] > 60.0, sb
assert abs(sb["h"] - 69.59) < 0.05, sb
assert sb["verdict"] == "SLACK", sb
assert sb["windows"] == 6, sb
assert abs(sb["t_needed"] - 27.61) < 0.02, sb
assert sb["unrecoverable_pp"] == 0.0, sb          # the floor is clamped, never rendered negative
assert ca.fmt_start_by(sb) == "start by T−28h (70h slack)", ca.fmt_start_by(sb)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22b CONTROL: the middle verdict exists — START SOON is reachable, and is flagged" {
  # next3's shape with 8 h of runway instead of 2.21: t_needed is unchanged at 2.855 h, so
  # h = +5.15 — inside the 12 h band. An implementation with only two verdicts (the two the
  # spec's live table happened to contain) passes RP-21 and RP-22 and fails here.
  run python3 -c "$LOAD"'
sb = ca.burst_start_by(row(weekly_reset_h=8.0), K)
assert sb is not None, sb
assert 0.0 < sb["h"] <= ca.START_BY_SLACK_H, sb
assert abs(sb["h"] - 5.145) < 0.01, sb
assert sb["verdict"] == "START SOON", sb
out = ca.fmt_start_by(sb)
assert out == "⚠ START SOON — start by T−3h (5.1h slack)", out
# ...and the boundary is the SLACK side of 12, not the START SOON side.
edge = ca.burst_start_by(row(weekly_reset_h=2.855 + 12.0001), K)
assert edge["verdict"] == "SLACK", edge
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23 CONTROL: the freeze term is LIVE, not decorative — P_WALL 0.625 vs 0.0 moves it 1.033h" {
  # The mutant a purely arithmetic implementation would survive: drop the wall-freeze entirely
  # and RP-21, RP-22 and RP-24 all still pass. Injected via the module constant and restored, so
  # the two calls differ in exactly one term. 1 window x 1.653 h x (0.625 - 0.0) = 1.033 h.
  run python3 -c "$LOAD"'
a = ca.burst_start_by(row(), K)["h"]
ca.P_WALL = 0.0
try:
    b = ca.burst_start_by(row(), K)["h"]
finally:
    ca.P_WALL = 0.625
assert abs((b - a) - 1.033) < 0.01, (a, b, b - a)
# CONTROL on the control: with the freeze gone the SAME row is no longer late, which is what
# makes the term load-bearing rather than a constant offset nobody would notice.
assert ca.burst_start_by(row(), K)["verdict"] == "LATE"
ca.P_WALL = 0.0
try:
    assert ca.burst_start_by(row(), K)["verdict"] == "START SOON"
finally:
    ca.P_WALL = 0.625
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24: no 5h window open => ABSTAIN, not a zero — and every other abstain arm is live" {
  # A null session_reset_at means NO WINDOW IS OPEN (15.0% of rows in the live series; 1,789 of
  # 1,790 of them read session_pct == 0). Collapsing that to `avail = 100` hands the walk a free
  # full window it does not have and returns an answer that is too optimistic by up to 4.4 h;
  # collapsing it to 0 invents a wait. The honest answer is that the question cannot be asked.
  run python3 -c "$LOAD"'
assert ca.burst_start_by(row(session_reset_at=None, session_pct=None), K) is None
assert ca.burst_start_by(row(session_pct=None), K) is None
# K abstained (S1c left the sane band) => every K consumer abstains. Without this the planner
# would silently fall back to whatever `None` coerces to.
assert ca.burst_start_by(row(), None) is None
assert ca.burst_start_by(row(), 0.0) is None
# nothing to start: the window is already full
assert ca.burst_start_by(row(weekly_pct=100), K) is None
assert ca.burst_start_by(row(weekly_pct=101), K) is None
# a weekly stamp outside the bucket is bad data, not a signal
assert ca.burst_start_by(row(weekly_reset_h=0), K) is None
assert ca.burst_start_by(row(weekly_reset_h=169.0), K) is None
assert ca.burst_start_by(row(weekly_reset_h=None), K) is None
# ...and the renderer speaks the same abstention rather than a second spelling of it
assert ca.fmt_start_by(None) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24b CONTROL: the abstains are not an always-None stub — the same rows answer when valid" {
  # House rule 3: every red-proof is paired with a control that pins the opposite branch. RP-24
  # asserts nine Nones; a `return None` body satisfies all nine.
  run python3 -c "$LOAD"'
assert ca.burst_start_by(row(), K) is not None
assert ca.burst_start_by(row(session_pct=0), K) is not None
assert ca.burst_start_by(row(weekly_pct=99.9), K) is not None
assert ca.burst_start_by(row(weekly_reset_h=168.0), K) is not None
assert ca.fmt_start_by(ca.burst_start_by(row(), K)) is not None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24c: the open window can DIE mid-burn — its reset caps the burn, it does not extend it" {
  # The one place the walk can silently over-credit: the open window contributes only what it
  # can drain BEFORE its own reset. next3's row with 0.5 h left on the 5h window can only buy
  # 0.5 x 22.87 = 11.4 of the 41.67 session pp needed, so the remainder waits for a second
  # window — and the freeze is charged twice, not once.
  run python3 -c "$LOAD"'
sb = ca.burst_start_by(row(session_reset_h=0.5), K)
assert sb["windows"] == 2, sb
assert abs(sb["freeze_h"] - 2 * 0.625 * 1.653) < 1e-9, sb
# 0.5h of the open window, then wait out the roll to 0.5h, then 30.24 session pp at 22.87/h
assert abs(sb["burn_h"] - (0.5 + (41.6667 - 0.5 * 22.87) / 22.87)) < 0.01, sb
assert sb["verdict"] == "LATE", sb
# CONTROL: give the same row a full window and it needs strictly less time and one less freeze
full = ca.burst_start_by(row(session_reset_h=3.37), K)
assert full["windows"] == 1 and full["t_needed"] < sb["t_needed"], (full, sb)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
