#!/usr/bin/env bats
# burst_start_by / fmt_start_by / pace_head — M4', the START-TIME constraint.
# USAGE_TELEMETRY_100P §5.2 S4, RED-proof cases RP-21..RP-24 (+ controls).
#
# WHAT THIS SUITE IS FOR, AND WHY THE METRIC IT PINS REPLACED ITS OWN PREDECESSOR. The synthesis
# shipped M4 `wk_reach_pp`, a CAPACITY question — "could a burst deliver the deficit at all" —
# which is nearly algebraically fixed and read next3 as `16.9 pp reach vs 8 needed, REACHABLE,
# 2.1x margin`. next3 stranded. M4' asks a rate-and-freeze-against-the-clock question instead and
# reads the same row LATE by 0.65 h with 2.83 pp already unrecoverable. A metric that cannot come
# out badly is not measuring anything, and that is the class this suite protects against.
#
# THE THREE FAILURE MODES IT PINS, each of which returns a PLAUSIBLE number:
#
#   * THE 5h GRID COLLAPSING INTO A RATE. `need_spp / BURST_SPPH` is a defensible-looking
#     one-liner and it is wrong by hours: you cannot open window N+1 before window N resets, so
#     six windows of work carry five inter-roll waits that no division reproduces. RP-21 is the
#     multi-window walk, RP-21b its single-window control.
#   * THE NULL SESSION STAMP READ AS AN EMPTY WINDOW. `avail = 100 - (session_pct or 0)` gives a
#     brand-new 5h window to an account that has NO window open, which is the most optimistic
#     possible reading of a missing measurement. RP-23 pins that arm; a null stamp is a STATE.
#   * THE FLOOR GOING UNSAID. `LATE` alone reads as "hurry and you are fine". The freeze comes out
#     of the runway whatever you do, so part of the deficit is gone before anyone acts. RP-22
#     pins that the LATE render carries the unrecoverable pp, not just the verb.
#
# AND ONE THAT RETURNS A PLAUSIBLE STRING: pace_head has THREE states, not two. `K unfitted` is
# exchange_rate REFUSING (the trailing fit left K_SANE); `apply_burn never ran` is a different
# fact, and rendering it as a refusal reports an abstention no estimator issued. RP-24 + controls.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; K passed explicitly.

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
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
K = 0.192
def row(**kw):
    r = {"acct": "next3", "weekly_pct": 92.0, "weekly_reset_h": 2.21,
         "session_pct": 50.0, "session_reset_h": 2.0, "session_reset_at": "2026-08-25T11:47:00Z"}
    r.update(kw)
    return r
'

@test "RP-21: the 5h grid is walked, so six windows of work carry five inter-roll waits" {
  # next2 as measured 2026-08-25T09:47:41Z: 83 pp of weekly deficit, K=0.192, so 432.3 session pp
  # of burst. At BURST_SPPH=22.87 that is 18.90 h of PURE BURN — the number a naive
  # `need_spp / BURST_SPPH` returns. The truth is 21.41 h, because 432.3 pp does not fit in one
  # 5h window: it needs six, and five of the gaps between them are dead time (5 h of wall clock
  # buys only 100/22.87 = 4.37 h of burn). Plus a freeze of 6 x P_WALL x MEAN_WALL_H = 6.20 h.
  # THE PUBLISHED FIGURES ARE THE ASSERTION: §5.2 S4's live table reads windows 6, burn 21.41,
  # freeze 6.20, t_needed 27.61, burst_start_by_h +69.59. A rate-division implementation lands at
  # 18.90/25.10/+72.10 — plausible, self-consistent, and 2.5 h optimistic on every burst it plans.
  run python3 -c "$LOAD"'
r = row(acct="next2", weekly_pct=17.0, weekly_reset_h=97.20,
        session_pct=68.0, session_reset_h=32.0 / 22.87)
sb = ca.burst_start_by(r, K)
assert sb is not None, sb
assert sb["windows"] == 6, sb
assert abs(sb["need_spp"] - 432.29) < 0.1, sb
burn = sb["t_needed"] - sb["freeze_h"]
assert abs(burn - 21.41) < 0.05, (burn, sb)      # NOT 18.90 — the grid, not a rate
assert abs(sb["freeze_h"] - 6.199) < 0.01, sb
assert abs(sb["t_needed"] - 27.61) < 0.05, sb
assert abs(sb["h"] - 69.59) < 0.05, sb
assert sb["verdict"] == "SLACK", sb
assert sb["unrecoverable_pp"] == 0.0, sb         # 97 h of runway buys far more than 83 pp
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-21b CONTROL: work that fits ONE open window takes exactly its burn time, no grid wait" {
  # Without this control RP-21 is satisfied by an implementation that adds a wait unconditionally.
  # 8 pp of deficit at K=0.192 is 41.67 session pp = 1.822 h of burn, and the open window holds
  # 50 pp with 2.0 h left, so it fits whole: ONE window, ONE freeze term, and no 0.628 h gap.
  run python3 -c "$LOAD"'
sb = ca.burst_start_by(row(), K)
assert sb is not None, sb
assert sb["windows"] == 1, sb
burn = sb["t_needed"] - sb["freeze_h"]
assert abs(burn - 1.822) < 0.01, (burn, sb)
assert abs(sb["freeze_h"] - 1.0331) < 0.001, sb      # 1 x 0.625 x 1.653
assert abs(sb["t_needed"] - 2.855) < 0.01, sb
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22: LATE carries the pp the freeze has ALREADY eaten, not just the verb" {
  # next3 live: 8 pp needed, 2.21 h of weekly runway, and 1.03 h of that is expected freeze. So a
  # PERFECT burst starting this instant burns 1.18 h = K x BURST_SPPH x 1.18 = 5.17 pp, and
  # 2.83 pp cannot be saved by any action at all. `LATE` on its own reads as "hurry"; the floor is
  # the part that says hurrying is not enough, and it is the whole reason M4' replaced M4.
  run python3 -c "$LOAD"'
sb = ca.burst_start_by(row(), K)
assert sb["verdict"] == "LATE", sb
assert abs(sb["h"] + 0.645) < 0.01, sb                    # NEGATIVE: the start time is in the past
assert abs(sb["unrecoverable_pp"] - 2.832) < 0.01, sb
s = ca.fmt_start_by(sb)
assert s.startswith("⚠ LATE by 0.6h"), s
assert "2.8pp already unrecoverable" in s, s
assert "slack" not in s, s
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22b CONTROL: the three verdicts are three renders — SLACK and START SOON are not LATE" {
  # An always-LATE stub passes RP-22. The boundary is START_SOON_H = 12 h of slack, and both arms
  # of it must render: SLACK is the quiet form (no glyph), START SOON warns and keeps the slack.
  run python3 -c "$LOAD"'
slack = ca.burst_start_by(row(weekly_pct=17.0, weekly_reset_h=97.20,
                              session_pct=68.0, session_reset_h=32.0 / 22.87), K)
assert slack["verdict"] == "SLACK", slack
s = ca.fmt_start_by(slack)
assert s == "start by T−28h (70h slack)", s
assert "⚠" not in s, s
# 60 pp of deficit with 30 h of runway: t_needed ~24.5 h, so ~5 h of slack — inside the 12 h band.
soon = ca.burst_start_by(row(weekly_pct=40.0, weekly_reset_h=30.0,
                             session_pct=100.0, session_reset_h=0.2), K)
assert soon["verdict"] == "START SOON", soon
assert 0 < soon["h"] <= ca.START_SOON_H, soon
t = ca.fmt_start_by(soon)
assert t.startswith("⚠ START SOON — T−"), t
assert "slack)" in t, t
assert "unrecoverable" not in t, t
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23: a NULL session stamp abstains — no window open is a STATE, not an empty window" {
  # `avail = 100 - (session_pct or 0)` hands a brand-new 5h window to an account that has none,
  # which is the most OPTIMISTIC possible reading of a missing measurement, on the one metric
  # whose entire job is to say "too late". All four abstain arms are pinned here because a
  # three-arm implementation is exactly how an abstain becomes decoration.
  run python3 -c "$LOAD"'
assert ca.burst_start_by(row(session_reset_at=None), K) is None      # no 5h window open
assert ca.burst_start_by(row(session_pct=None), K) is None
assert ca.burst_start_by(row(), None) is None                        # S1c exchange_rate abstained
assert ca.burst_start_by(row(weekly_pct=100.0), K) is None           # deficit <= 0
assert ca.burst_start_by(row(weekly_reset_h=0.0), K) is None
assert ca.burst_start_by(row(weekly_reset_h=200.0), K) is None       # outside (0, 168]
assert ca.burst_start_by(row(weekly_reset_h=None), K) is None
assert ca.fmt_start_by(None) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23b CONTROL: an OPEN window with zero remaining still plans — it waits for the roll" {
  # The distinction RP-23 is protecting: session_pct=100 with a live stamp is an EXHAUSTED window,
  # which is a measurement, and the planner must handle it by waiting out session_reset_h rather
  # than abstaining. Without this control RP-23 is satisfied by abstaining on both.
  run python3 -c "$LOAD"'
sb = ca.burst_start_by(row(session_pct=100.0, session_reset_h=3.0,
                           weekly_pct=60.0, weekly_reset_h=100.0), K)
assert sb is not None, sb
assert sb["windows"] == 3, sb                       # 208.3 spp -> 100 + 100 + 8.3
burn = sb["t_needed"] - sb["freeze_h"]
# 3.0 h waiting out the dead window, then 208.3/22.87 h of burn plus two 0.628 h inter-roll gaps
assert abs(burn - (3.0 + 208.333 / 22.87 + 2 * (5.0 - 100.0 / 22.87))) < 0.01, (burn, sb)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24: pace_head has THREE states — fitted, REFUSED, and never computed" {
  # `K unfitted` is exchange_rate refusing: the trailing fit left K_SANE, i.e. the plan or the
  # meter moved, and that is a MEASUREMENT worth rendering. `apply_burn never ran` is not a
  # refusal, and spelling it as one reports an abstention no estimator issued. A single absent key
  # collapses the two, and the collapsed form is the one that misinforms.
  run python3 -c "$LOAD"'
fitted = ca.pace_head([{"wk_k": 0.1969, "wk_k_src": "live"}])
assert fitted.startswith("weekly drain — pp that DIE at reset"), fitted
assert "K=0.197 live" in fitted, fitted
assert "nowcast at the last 48h of pace" in fitted, fitted
refused = ca.pace_head([{"wk_k": None, "wk_k_src": "unfitted"}])
assert "K unfitted" in refused, refused
assert "no start-by figures this sweep" in refused, refused
assert "K=" not in refused, refused
never = ca.pace_head([{"acct": "next3"}])
assert never == ca.PACE_HEAD, never
assert "K" not in never.replace("DIE", ""), never
frozen = ca.pace_head([{"wk_k": 0.192, "wk_k_src": "frozen"}])
assert "K=0.192 frozen" in frozen, frozen
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24b: apply_burn STAMPS K and its source, so the renderer never re-fits the fleet" {
  # K is the one figure on this surface pace_line cannot re-derive — it is fitted over the whole
  # fleet's series and the renderer holds only rows. Stamped in apply_burn (which holds both),
  # exactly like `burst`. Thin series => "frozen", which is a source, never a silent literal.
  run python3 -c "$LOAD"'
import json, time
now = time.time()
samples = []
for i in range(240, -1, -1):
    samples.append({"acct": "next3", "_t": now - i * 360.0,
                    "session_pct": 10.0, "weekly_pct": 26 + (240 - i) * 0.0583,
                    "session_reset_at": None, "weekly_reset_at": "2026-08-30T00:00:00Z"})
rows = [{"acct": "next3", "weekly_pct": 40.0, "weekly_reset_h": 100.0}]
ca.apply_burn(rows, {}, samples=samples)
r = rows[0]
assert "wk_k" in r and "wk_k_src" in r, r
assert r["wk_k_src"] == "frozen", r          # Sds far below K_MIN_SDS on this fixture
assert abs(r["wk_k"] - ca.K_FROZEN) < 1e-9, r
head = ca.pace_head(rows)
assert "K=0.192 frozen" in head, head
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24c: the start-by clause rides STRAND rows only, and never a row with no loss to price" {
  # A start time attached to a row with no strand prices a burst nobody needs; attached to a row
  # whose strand is UNKNOWN it prices a loss nobody measured. Both render a confident number over
  # an absent fact, which is the shape §3.2 forbids. The control is that a real strand row DOES
  # carry it — without that half, "never render it" passes.
  run python3 -c "$LOAD"'
strand = row(acct="next3", weekly_pct=92.0, weekly_reset_h=2.21, burn_wk_ewma_ph=1.140,
             wk_k=0.192, wk_k_src="live")
line = ca.pace_line([strand])
assert "next3 strand ~5pp of 8" in line, line
assert "⚠ LATE by" in line, line
assert "2.8pp already unrecoverable" in line, line
assert "K=0.192 live" in line, line
# no strand: on pace to fill the window, so nothing to plan a burst for
none_row = row(acct="next", weekly_pct=95.0, weekly_reset_h=20.0, burn_wk_ewma_ph=0.5,
               wk_k=0.192, wk_k_src="live")
nl = ca.pace_line([none_row])
assert "next no strand" in nl, nl
assert "start by" not in nl and "LATE" not in nl and "START SOON" not in nl, nl
# strand UNKNOWN (M3a abstained): still no start time
unk = row(acct="next2", weekly_pct=13.0, weekly_reset_h=122.8, burn_wk_span_h=4.1,
          wk_k=0.192, wk_k_src="live")
ul = ca.pace_line([unk])
assert "next2 strand unknown (span 4.1h < 6.8h)" in ul, ul
assert "start by" not in ul and "LATE" not in ul, ul
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
