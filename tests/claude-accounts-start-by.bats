#!/usr/bin/env bats
# burst_start_by — the START-TIME constraint. USAGE_TELEMETRY_100P §5.2 S4 (M4′), RED-proof cases
# RP-21..RP-24.
#
# THE DEFECT IT CURES. The drain block says how much dies and whether the demand is routine, and
# then stops. It never says WHEN the spending has to begin — so an account reading `strand ~5pp of
# 8 · p96 of its own 3h burns` looks like a live rescue when the burn plus the expected 5h freeze
# plus the grid no longer fit before the reset. next3 on 2026-08-25 was LATE by 0.65 h with 2.83 pp
# already unrecoverable, and the surface showed nothing that could have said so.
#
# IT IS A START TIME, NOT A CAPACITY VERDICT, and RP-22 is that distinction as an assertion. The
# synthesis's M4 asked "is the deficit reachable" — nearly algebraically fixed — and read next3
# `16.9 pp reach vs 8 needed, REACHABLE, 2.1x margin` on a window that in fact stranded.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; nothing here reads the live series.

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
def row(**kw):
    base = dict(acct="next3", session_pct=10, session_reset_h=4.0,
                weekly_pct=40, weekly_reset_h=100.0)
    base.update(kw); return base
'

@test "RP-21: the live LATE row reproduces exactly — start_by, the freeze, and the unrecoverable floor" {
  # USAGE_TELEMETRY_100P §5.2 S4's live table, next3 at 2026-08-25T09:47:41Z with K=0.192:
  # deficit 8 pp -> 41.67 session pp -> 1.82 h of burn in ONE window, freeze 1*0.625*1.653 = 1.033,
  # t_needed 2.86 against 2.21 h of runway => LATE by 0.65 h. The floor is computed on the runway
  # MINUS the freeze: 2.21 - 1.033 = 1.18 usable hours buy K*BURST_SPPH*1.18 = 5.17 weekly pp of
  # the 8 needed, so 2.83 pp cannot be saved even by a perfect burst starting this instant.
  run python3 -c "$LOAD"'
r = row(weekly_pct=92, weekly_reset_h=2.21, session_pct=10, session_reset_h=4.0)
sb = ca.burst_start_by(r, 0.192)
assert sb is not None, sb
assert sb["windows"] == 1, sb
assert abs(sb["need_spp"] - 41.6667) < 0.01, sb
assert abs(sb["freeze_h"] - 1.0331) < 0.001, sb
assert abs(sb["t_needed_h"] - 2.855) < 0.01, sb
assert abs(sb["start_by_h"] + 0.645) < 0.01, sb
assert sb["verdict"] == "LATE", sb
assert abs(sb["unrecoverable_pp"] - 2.832) < 0.01, sb
s = ca.fmt_start_by(sb)
assert "LATE" in s and "unrecoverable" in s, s
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-22 CONTROL: the SLACK row reproduces too — six windows and the 5h grid it has to walk" {
  # The arm that makes RP-21 a control rather than a LATE-shaped stub. Same table, next2: an 83 pp
  # deficit is 432.3 session pp, which no single 5h window can hold — the walk therefore opens six
  # of them, pays 5*0.6275 h of dead time waiting for rolls it cannot open early, and freezes
  # 6*1.033 h. t_needed 27.61 h against 97.2 h of runway. §5.4's mock renders exactly this row.
  run python3 -c "$LOAD"'
r = row(acct="next2", weekly_pct=17, weekly_reset_h=97.2, session_pct=77, session_reset_h=1.0)
sb = ca.burst_start_by(r, 0.192)
assert sb["windows"] == 6, sb
assert abs(sb["need_spp"] - 432.29) < 0.05, sb
assert abs(sb["freeze_h"] - 6.199) < 0.01, sb
assert abs(sb["t_needed_h"] - 27.61) < 0.05, sb
assert sb["verdict"] == "SLACK", sb
assert sb["unrecoverable_pp"] is None, sb          # a floor is only meaningful once it is LATE
assert ca.fmt_start_by(sb) == "start by T−28h (70h slack)", ca.fmt_start_by(sb)
# ...and the grid is REAL, not decoration: without the 5.0 - 100/22.87 wait between full windows
# the six of them would cost 3.1 h less and the metric would under-state every multi-window burst.
assert abs(5.0 - 100.0 / ca.BURST_SPPH - 0.6275) < 0.001
# THE MIDDLE VERDICT EXISTS. A two-verdict implementation passes both cases above.
soon = ca.burst_start_by(row(weekly_pct=92, weekly_reset_h=8.0), 0.192)
assert soon["verdict"] == "START SOON", soon
assert "START SOON" in ca.fmt_start_by(soon), ca.fmt_start_by(soon)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-23: an EXHAUSTED 5h window must wait out its roll — the spec's own pseudocode does not" {
  # §5.2 S4 guards the whole first-window step on `avail > 0`, so at session_pct = 100 — a meter
  # that cannot burn one more pp right now — t stays 0 and the walk starts burning immediately.
  # The error is FAIL-DANGEROUS in exactly one direction: t_needed comes out short, start_by comes
  # out LONG, and the verdict reads SLACK on the one state where the burst is provably blocked.
  run python3 -c "$LOAD"'
blocked = row(weekly_pct=50, weekly_reset_h=30.0, session_pct=100, session_reset_h=4.9)
open_ = row(weekly_pct=50, weekly_reset_h=30.0, session_pct=0,   session_reset_h=4.9)
b, o = ca.burst_start_by(blocked, 0.192), ca.burst_start_by(open_, 0.192)
# the blocked account needs STRICTLY more clock than the identical open one, by ~ its own roll
assert b["t_needed_h"] > o["t_needed_h"] + 4.0, (b, o)
assert b["start_by_h"] < o["start_by_h"] - 4.0, (b, o)
# and the wait is the roll itself, not a constant someone guessed
half = row(weekly_pct=50, weekly_reset_h=30.0, session_pct=100, session_reset_h=1.0)
h = ca.burst_start_by(half, 0.192)
assert abs((b["t_needed_h"] - h["t_needed_h"]) - 3.9) < 0.01, (b, h)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24 CONTROL: every L2 abstain is a None, and a null session stamp does NOT collapse to zero" {
  # Four abstains, and the second is the one that must not become a number. A null session stamp
  # means NO WINDOW IS OPEN — a distinct state. Read as session_pct=0 it claims a full 100 pp of
  # open capacity that does not exist; read as 100 it claims a freeze that is not happening. Both
  # readings are confident and wrong, which is why L2 says the answer is nothing at all.
  run python3 -c "$LOAD"'
r = row(weekly_pct=92, weekly_reset_h=2.21)
assert ca.burst_start_by(r, None) is None                       # S1c abstained -> no conversion
assert ca.burst_start_by(r, 0.0) is None
assert ca.burst_start_by(row(session_pct=None), 0.192) is None   # no window open is a STATE
assert ca.burst_start_by(row(session_reset_h=None), 0.192) is None
assert ca.burst_start_by(row(weekly_pct=100), 0.192) is None     # nothing left to buy
assert ca.burst_start_by(row(weekly_reset_h=0), 0.192) is None   # outside the bucket = bad data
assert ca.burst_start_by(row(weekly_reset_h=200.0), 0.192) is None
assert ca.burst_start_by(row(weekly_pct=None), 0.192) is None
assert ca.fmt_start_by(None) is None
# ...and the CONTROL on the whole block: the same row with everything present DOES report, so the
# assertions above are refusals and not an always-None stub.
assert ca.burst_start_by(r, 0.192) is not None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24b: the block renders the start-by clause, the header names K, and BOTH gate on strand" {
  # The renderer half, and it has three separate failure modes.
  #  (a) the clause must reach the row -- an unrendered metric changes no decision;
  #  (b) it must ride the SAME gate as M5, because a start time is an instruction to SPEND and an
  #      account with no strand has nothing to rescue (`next` was on a wall trajectory and would
  #      have been told to start bursting);
  #  (c) the header must name K only when a row actually consumed one. S3 shipped deliberately
  #      without the clause -- M3a consumes no K at all -- and a header advertising a coefficient
  #      nothing on the block used is the metric shape §3.2 forbids.
  run python3 -c "$LOAD"'
n3 = row(acct="next3", weekly_pct=92, weekly_reset_h=2.21, burn_wk_ewma_ph=1.140,
         session_pct=10, session_reset_h=4.0, exch_k=0.192, exch_k_src="live")
n1 = row(acct="next", weekly_pct=52, weekly_reset_h=114.21, burn_wk_ewma_ph=1.725,
         session_pct=10, session_reset_h=4.0, exch_k=0.192, exch_k_src="live")
line = ca.pace_line([n3, n1])
assert "K=0.192 live" in line, line
assert "LATE by" in line and "unrecoverable" in line, line
assert "next3 strand ~5pp of 8 · ⚠ LATE by" in line, line
# (b) the zero-strand row keeps its countdown and is NOT handed a start time
nxt = [l for l in line.split(chr(10)) if l.strip().startswith("next ")][0]
assert "no strand" in nxt and "start by" not in nxt and "LATE" not in nxt, nxt
# (c) no K stamped => no K clause and no start-by clause, i.e. exactly M4′ abstaining
bare = ca.pace_line([row(acct="next3", weekly_pct=92, weekly_reset_h=2.21,
                         burn_wk_ewma_ph=1.140)])
assert bare.startswith("weekly drain — pp that DIE at reset (nowcast"), bare
assert "K=" not in bare and "start by" not in bare and "LATE" not in bare, bare
assert "2h left" in bare or "left" in bare, bare
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-24c: apply_burn fits K ONCE per sweep and stamps it, so the renderer has one to read" {
  # exchange_rate has been built, tested and green since S1 and NOTHING consumed it — M4′ is its
  # first consumer, and a coefficient no code path reads is an instrument that changes no decision.
  # ONE fit per sweep, not one per account: K is a fleet-level ratio, and re-fitting it per row
  # would turn a pooled estimate into four thin ones, each below K_MIN_SDS and each therefore
  # silently falling back to the frozen literal.
  run python3 -c "$LOAD"'
import time
NOW = time.time()
from datetime import datetime, timezone
def iso(t): return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
WRA, SRA = iso(NOW + 100 * 3600), iso(NOW + 4 * 3600)
sam = []
sp = wp = 0.0
for i in range(1200):                      # 0.1 h cadence; dw/ds held at exactly 0.2
    sam.append({"acct": "next3", "_t": NOW - (1200 - i) * 0.1 * 3600,
                "session_pct": sp, "weekly_pct": wp,
                "session_reset_at": SRA, "weekly_reset_at": WRA})
    sp += 1.0; wp += 0.2
    if sp > 100: sp = 0.0                  # the 5h meter rolls; the fit skips rolled pairs
rows = [row(acct="next3", weekly_pct=92, weekly_reset_h=2.21, session_pct=10,
            session_reset_h=4.0)]
ca.apply_burn(rows, {}, samples=sam)
r = rows[0]
assert abs(r["exch_k"] - 0.2) < 0.005, r["exch_k"]
assert r["exch_k_src"] == "live", r
assert "burst_start_by_h" in r and r["burst_start_by_h"] < 0, r["burst_start_by_h"]
assert r["burst_start_by"]["verdict"] == "LATE", r["burst_start_by"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
