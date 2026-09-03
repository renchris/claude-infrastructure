#!/usr/bin/env bats
# S4 / M4′ — burst_start_by and fmt_start_by. USAGE_TELEMETRY_100P §5.2 S4, cases RP-28..RP-33.
#
# WHAT THIS SUITE IS FOR. The weekly-drain block answers two of the goal's three questions —
# how much dies, and whether the demand is routine — and could not answer the third: is there
# still TIME. The metric that was supposed to answer it, M4 `wk_reach_pp`, was deleted for
# reading REACHABLE on 99.37% of the series and on 100% of the 74 samples inside the five wall
# episodes it was written to catch: `reach_pp` and `need` are both monotone in
# (weekly_pct, hours-remaining), so it was an algebraic restatement of the thing it supplemented.
#
# M4′ is not monotone in that pair, and everything that makes it not monotone is a place a
# plausible wrong number can be produced:
#
#   * THE 5 h GRID. `need_spp / BURST_SPPH` is a division anyone would write and it omits both
#     the roll waits and the expected freeze. On the live next2 row it reads 18.90 h against a
#     true 27.61 h — 8.7 h early, on an account the block would then call SLACK. RP-28.
#   * THE EXHAUSTED OPEN WINDOW. §5.2's own pseudocode has no `else` arm: with `session_pct` at
#     100 the walk starts burning at t = 0, inside a window that cannot be opened yet, and
#     understates t_needed by exactly `session_reset_h` — ONLY when the account is walled, i.e.
#     only in the regime this metric exists to call. RP-30.
#   * THE FOUR ABSTAINS. A null K, a full window, a null session stamp and a junk weekly stamp
#     are four different silences. A null session stamp means NO WINDOW IS OPEN; collapsing it
#     to `avail = 100` hands the account a free window and reads hours of false slack. RP-31.
#
# The live table in §5.2 S4 (2026-08-25T09:47:41Z, K = 0.192) is the fixture for RP-28/RP-29:
# next2 → 6 windows / 21.41 h burn / 6.20 h freeze / t_needed 27.61 / +69.59 SLACK, and
# next3 → 1 window / 1.82 h burn / 1.03 h freeze / t_needed 2.86 / −0.65 LATE, floor 2.83 pp.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; rows passed explicitly.

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
def r(acct="next3", wp=92.0, wrh=2.21, sp=10.0, srh=2.0, **kw):
    d = {"acct": acct, "weekly_pct": wp, "weekly_reset_h": wrh,
         "session_pct": sp, "session_reset_h": srh}
    d.update(kw)
    return d
'

@test "RP-28: burst_start_by WALKS the 5h grid — a plain divide reads 8.7h early" {
  # The live next2 row. need_spp = 83/0.192 = 432.3 session pp, which is 18.90 h of burn at
  # BURST_SPPH. The true answer is 27.61 h, because the walk also pays four inter-window waits
  # (5 h grid minus the 4.37 h a full window takes to burn) and six windows of expected freeze
  # (P_WALL x MEAN_WALL_H). A `need_spp / BURST_SPPH` implementation passes any test that only
  # checks the sign of the slack, and is 8.7 h optimistic on exactly the account being planned.
  run python3 -c "$LOAD"'
sb = ca.burst_start_by(r(acct="next2", wp=17.0, wrh=97.20, sp=67.71, srh=1.41), K)
assert sb is not None
assert sb["windows"] == 6, sb                       # 1 partial open window + 5 full ones
burn = sb["t_needed"] - sb["freeze_h"]
assert abs(burn - 21.41) < 0.01, sb                 # NOT 18.90 — the roll waits are 2.51 h of it
assert abs(sb["freeze_h"] - 6.20) < 0.01, sb        # 6 x 0.625 x 1.653
assert abs(sb["t_needed"] - 27.61) < 0.01, sb
assert abs(sb["h"] - 69.59) < 0.01, sb
assert sb["verdict"] == "SLACK", sb
assert sb["unrecoverable_pp"] is None, sb           # a floor is reported only where it is real
# ...and the naive form it must not be
assert abs((100.0 - 17.0) / K / ca.BURST_SPPH - 18.90) < 0.02
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-29 CONTROL: the LATE arm fires, and reports the pp a perfect burst can no longer buy" {
  # Without this case RP-28 is satisfied by an implementation whose slack is never negative —
  # i.e. by the capacity question M4 already answered wrongly. next3 on 2026-08-25: M4 read
  # `16.9 pp reach vs 8 needed — REACHABLE, 2.1x margin`; M4′ reads LATE by 0.65 h with 2.83 pp
  # already gone, and next3 in fact stranded. The floor is `deficit - K*SPPH*(reset_h - freeze)`:
  # charging the 1.03 h freeze against the 2.21 h of runway leaves 1.18 h of usable burn, worth
  # 5.17 weekly pp of the 8 needed.
  run python3 -c "$LOAD"'
sb = ca.burst_start_by(r(), K)                      # next3: 92%, 2.21 h to reset
assert sb["windows"] == 1, sb
assert abs(sb["t_needed"] - sb["freeze_h"] - 1.82) < 0.01, sb
assert abs(sb["freeze_h"] - 1.033) < 0.01, sb
assert abs(sb["h"] + 0.65) < 0.01, sb               # NEGATIVE — already late
assert sb["verdict"] == "LATE", sb
assert abs(sb["unrecoverable_pp"] - 2.83) < 0.01, sb
# the floor is bounded by the deficit and is never negative
assert 0 < sb["unrecoverable_pp"] <= 8.0, sb
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-30: an EXHAUSTED open window still costs its reset — §5.2's pseudocode omits this" {
  # §5.2 S4 guards the open window with `if avail > 0:` and writes no else. Under that reading an
  # account at session_pct 100 starts burning at t = 0, inside a window that has no headroom and
  # cannot be reopened for `session_reset_h`. The error is exactly session_reset_h, it is always
  # in the optimistic direction, and it appears ONLY when the account is walled — which is the
  # one state M4′ exists to call.
  #
  # THE COMPARISON IS AGAINST THE SAME WALL AT A DIFFERENT RESET, never against a nearly-full
  # window. A `session_pct = 99` row is NOT the control it looks like: 1 pp of headroom enters a
  # window for 0.044 h of burn and is charged a whole window of expected freeze, so it comes out
  # WORSE than the wall — a real property of the per-window freeze model, and one that would let
  # a t = 0 implementation pass a `walled > open` assertion for the wrong reason.
  run python3 -c "$LOAD"'
a = ca.burst_start_by(r(wp=60.0, wrh=40.0, sp=100.0, srh=4.0), K)
b = ca.burst_start_by(r(wp=60.0, wrh=40.0, sp=100.0, srh=1.0), K)
assert a is not None and b is not None
assert a["windows"] == b["windows"] == 3, (a, b)          # identical walks, different waits
assert abs(a["freeze_h"] - b["freeze_h"]) < 1e-9, (a, b)
# THE ARM ITSELF: the only thing that differs is the wait, and it is paid in full.
assert abs((a["t_needed"] - b["t_needed"]) - 3.0) < 1e-6, (a, b)
assert abs((b["h"] - a["h"]) - 3.0) < 1e-6, (a, b)
# ABSOLUTE FORM, so a t = 0 implementation cannot pass by being uniformly early: the walk is
# 208.33 session pp = 3 windows (4.372 h each) + 2 roll waits (0.628 h) = 10.364 h of walking,
# and the walled row must carry session_reset_h ON TOP of it.
walk = a["t_needed"] - a["freeze_h"]
assert abs(walk - (10.364 + 4.0)) < 0.01, a
assert walk > (100.0 - 60.0) / K / ca.BURST_SPPH, a       # and never the bare divide
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31 CONTROL: all FOUR abstain arms are live, and a good row still speaks" {
  # A two-arm abstain is how a refusal becomes an always-None stub, and an always-None stub
  # passes every case above by returning nothing. Each arm is a DIFFERENT silence:
  #   K None        — S1c left K_SANE; M4′ is K's first consumer, so it goes quiet alone.
  #   deficit <= 0  — the window is already full; there is no burst to start.
  #   session null  — NO WINDOW IS OPEN. Collapsing it to avail=100 invents a free window.
  #   wrh outside (0,168] — no weekly window, or a stamp this program cannot trust.
  run python3 -c "$LOAD"'
assert ca.burst_start_by(r(), None) is None                       # K abstained
assert ca.burst_start_by(r(), 0.0) is None                        # and a zero K is not a divisor
assert ca.burst_start_by(r(wp=100.0), K) is None                  # no deficit
assert ca.burst_start_by(r(sp=None), K) is None                   # no session pct
assert ca.burst_start_by(r(srh=None), K) is None                  # no window open
assert ca.burst_start_by(r(wrh=0.0), K) is None                   # no weekly window
assert ca.burst_start_by(r(wrh=169.0), K) is None                 # untrustable stamp
assert ca.burst_start_by(r(wp=None), K) is None
# THE CONTROL — without it every assertion above is satisfied by `return None`
good = ca.burst_start_by(r(wp=60.0, wrh=40.0, sp=10.0, srh=3.0), K)
assert good is not None and good["verdict"] in ("SLACK", "START SOON", "LATE"), good
assert good["windows"] >= 1 and good["t_needed"] > 0, good
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32: fmt_start_by leads a LATE row with the LOSS, never with a schedule" {
  # The rendering half of the refusal, and it is the half S2 lost: `burst_percentile` refused to
  # extrapolate a p100 at the NUMBER and shipped `p100` at the STRING for nine days. A LATE row
  # rendered as `start by T-0h` is arithmetically true and reads as an instruction that can still
  # be followed. The reader's action on a LATE account is to route the work elsewhere, so the
  # unrecoverable pp is what the row must say. All three verdict arms are pinned, because one
  # spelling shared between two verdicts is the same defect in the other direction.
  run python3 -c "$LOAD"'
late = ca.fmt_start_by(ca.burst_start_by(r(), K))
assert late.startswith("⚠ LATE by"), late
assert "unrecoverable" in late, late
assert "start by" not in late, late                       # never a schedule on a LATE row
soon = ca.fmt_start_by(ca.burst_start_by(r(wp=60.0, wrh=13.5, sp=10.0, srh=1.0), K))
assert soon.startswith("⚠ START SOON"), soon
assert "slack" in soon, soon
slack = ca.fmt_start_by(ca.burst_start_by(r(acct="next4", wp=14.0, wrh=119.20, sp=67.71, srh=1.41), K))
assert slack == "start by T−28h (91h slack)", slack       # the §5.4 mock, to the character
assert "⚠" not in slack, slack                            # a warning glyph only on a warning
assert ca.fmt_start_by(None) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33: pace_line carries the clause, and the header carries K only when K is REAL" {
  # L3 — one renderer. The start-by clause joins the strand and the percentile on the SAME row
  # rather than opening a second block, and it is COMPUTED here rather than read off the stamp
  # for the reason `_strand` is: a renderer that reads a stamp renders nothing at all when
  # apply_burn has not run, which is a silent failure. K is the one exception — it needs the
  # series — so it rides a stamp, and its ABSENCE must silence this clause and the header clause
  # together. §5.4s mock header reads `(K=0.192 live · nowcast ...)`; S3 shipped without it
  # deliberately, because M3a consumes no K and a number nothing on the line consumes is the
  # metric shape §3.2 forbids. S4 is the first consumer, so the clause enters with it.
  run python3 -c "$LOAD"'
def row(**kw):
    d = {"acct": "next3", "weekly_pct": 92.0, "weekly_reset_h": 2.21, "session_pct": 10.0,
         "session_reset_h": 2.0, "burn_wk_ewma_ph": 1.140}
    d.update(kw); return d
# WITHOUT K: the strand still renders (it is computed, not stamped), the start-by clause does not
bare = ca.pace_line([row()])
assert bare.startswith("weekly drain — pp that DIE at reset ("), bare
assert "K=" not in bare, bare
assert "start by" not in bare and "LATE" not in bare, bare
assert "next3 strand ~" in bare, bare
# WITH K: both clauses appear, on the one row and in the one header
k = ca.pace_line([row(exchange_rate_k=0.1969, exchange_rate_src="live")])
assert k.startswith("weekly drain — pp that DIE at reset (K=0.197 live · nowcast at the last 48h of pace):"), k
assert "⚠ LATE by" in k, k
assert "unrecoverable" in k, k
# the stem the burn-ratio suite greps as the invariant survives a caption that GREW
assert "pp that DIE at reset" in k and "nowcast at the last 48h of pace" in k, k
# and the row is still ONE row: strand, then percentile-or-nothing, then start-by
body = [ln for ln in k.split(chr(10)) if ln.strip().startswith("next3")]
assert len(body) == 1, k
assert body[0].index("strand ~") < body[0].index("⚠ LATE by"), body
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
