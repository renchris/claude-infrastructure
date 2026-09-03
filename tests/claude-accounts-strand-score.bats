#!/usr/bin/env bats
# S5 / M3c — strand_score, render_strand_score and the --strand-score flag.
# USAGE_TELEMETRY_100P §5.2 S5 / §5.4, cases RP-34..RP-38.
#
# WHAT THIS SUITE IS FOR, AND IT IS NOT "IS THE NOWCAST ACCURATE". §5.4 is explicit that the
# acceptance for this flag is that the bias COULD have been non-zero — never that it was small.
# The thing being guarded against is the harness this one replaces:
#
#   The synthesis scored the same arithmetic at 4/4 recall, 0 false positives, ~20 h median
#   lead. That score came out of a rule that was non-empty only at each window's LAST sample,
#   where the projection has already converged to `100 - weekly_pct` — i.e. to the true strand.
#   It agreed with the identity function on 8 of 8 windows. Eight binary cells evaluated at the
#   horizon's own close is a tautology wearing a validation's clothes.
#
# So the load-bearing property is that this harness evaluates at FIXED DISTANCES from the reset,
# where the projection is free to be wrong — and the fixture is built so that it IS wrong, badly,
# at the long horizons and nearly right at the short ones. A harness whose every cell reads 0.0
# is the tautology all over again, and RP-34 is the case that would catch it.
#
# THE FIXTURE. One account, one weekly window that closed 10 h ago. Its meter climbs at 1.0 %/h
# until 24 h before the reset and at 0.1 %/h after it — a burst that stopped. It closes at
# 78.35%, so 21.65 pp really died. At 24 h out the nowcast sees 76% and a 1.0 %/h pace, projects
# the window full, and says NO STRAND. At 6 h out it sees the collapsed pace and lands within
# 0.3 pp. That spread across horizons is the entire product of this flag, and it is why S6 is
# gated on READING this table rather than on running it (§5.2 S6).
#
# Hermetic: $HOME, $CLAUDE_CONFIG_DIR and $CC_UTIL_LOG into BATS_TEST_TMPDIR; samples built in
# the test. RP-38 runs the real binary under that fixtured $HOME with no accounts.json at all.

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
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
RESET = round((NOW - 10 * 3600) / 60.0) * 60.0        # minute-aligned, closed 10 h ago

def burst_then_stall(acct="next3", reset=RESET, span_h=100.0, tail_gap_h=0.5,
                     fast=1.0, slow=0.1, knee_h=24.0, start=0.0):
    """100 h of 6-min samples ending tail_gap_h before `reset`: `fast` %/h until knee_h before
    the reset, `slow` after. The knee is the whole point — a pace the nowcast cannot see coming
    down."""
    out, t, wp = [], reset - span_h * 3600.0, start
    while t <= reset - tail_gap_h * 3600.0 + 1:
        out.append({"acct": acct, "session_pct": 10, "weekly_pct": round(wp, 3),
                    "session_reset_at": None, "weekly_reset_at": iso(reset), "_t": t})
        wp += (fast if (reset - t) / 3600.0 > knee_h else slow) * 0.1
        t += 360.0
    return out

def cell(sc, h):
    cs = [c for c in sc["cells"] if abs(c["h"] - h) < 1e-9]
    return cs[0] if cs else None

def bucket(sc, h):
    return [b for b in sc["buckets"] if abs(b["h"] - h) < 1e-9][0]
'

@test "RP-34: the projection is scored at a FIXED DISTANCE, where it can be — and is — wrong" {
  # THE TAUTOLOGY TEST. A harness that evaluates at the window's close scores the identity
  # function and reports ~0.0 everywhere; this fixture makes that outcome impossible to reach
  # honestly. At 24 h out the nowcast projects the window FULL (76% climbing at 1.0 %/h over
  # 24 h) and says no strand, while 21.65 pp actually died. At 6 h out it has seen the collapse
  # and lands inside 0.3 pp. Both halves are asserted: a stub returning zeros fails the first,
  # and a stub returning garbage fails the second.
  run python3 -c "$LOAD"'
sc = ca.strand_score(burst_then_stall(), now=NOW)
assert sc["windows"] == 1, sc["windows"]
far, near = cell(sc, 24.0), cell(sc, 6.0)
assert far is not None and near is not None, sc["cells"]
# the window really stranded 21.65 pp, and both cells are scored against THAT
assert abs(far["realised"] - 21.65) < 0.01, far
assert abs(near["realised"] - 21.65) < 0.01, near
# evaluated AT the horizon, not at the close
assert abs(far["at_wrh"] - 24.0) < 0.2, far
assert abs(near["at_wrh"] - 6.0) < 0.2, near
# ...and at 24 h out the nowcast said NO STRAND. This is the cell a tautological harness cannot
# produce: -21.65 pp of signed error on the metric it is scoring.
assert far["projected"] < 0.5, far
assert far["signed_error"] < -20.0, far
# ...while at 6 h it has converged. The estimator is a good NOWCASTER for exactly the reason it
# is a bad forecaster (§5.1 LB-2), and this pair is that sentence as a measurement.
assert abs(near["signed_error"]) < 1.0, near
assert abs(bucket(sc, 24.0)["mae"] - 21.65) < 0.05, sc["buckets"]
assert bucket(sc, 6.0)["mae"] < 1.0, sc["buckets"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-35 CONTROL: a horizon with no evaluable sample reports n=0 and is EXCLUDED" {
  # §5.2 S5s abstain. The 96 h bucket has candidate samples — the series starts 100 h before the
  # reset — but only 4 h of history sits behind them, below burn_wk_ewma_ph's own span floor, so
  # M3a refuses to speak there and so must this. Imputing a value (a zero, the realised strand,
  # the nearest bucket) is how a harness scores its own gaps as successes; the plan's whole
  # objection to the score this replaces is that it counted converged cells as hits.
  #
  # The CONTROL half is that the neighbouring 48 h bucket, which DOES have history, is scored.
  # Without it "excluded" is satisfied by a harness that excludes everything.
  run python3 -c "$LOAD"'
sc = ca.strand_score(burst_then_stall(), now=NOW)
b96 = bucket(sc, 96.0)
assert b96["n"] == 0, b96
assert b96["bias"] is None and b96["mae"] is None and b96["agree"] is None, b96
assert cell(sc, 96.0) is None, sc["cells"]        # not in the aggregate, not in the cells
# the empty bucket is still PRINTED — a bucket that vanishes silently is indistinguishable
# from one that scored perfectly
out = ca.render_strand_score(sc)
assert "96h" in out, out
assert "no evaluable sample" in out, out
# CONTROL: the buckets that do have evidence are scored
assert bucket(sc, 48.0)["n"] == 1, sc["buckets"]
assert bucket(sc, 24.0)["n"] == 1, sc["buckets"]
assert bucket(sc, 12.0)["n"] == 1, sc["buckets"]
assert bucket(sc, 6.0)["n"] == 1, sc["buckets"]
assert len(sc["cells"]) == 4, sc["cells"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-36 CONTROL: only the window's OWN samples score it, and a LIVE window is never scored" {
  # Two failures share this case because they share a cause — reading a sample's weekly_pct as
  # this window's level when it belongs to another window.
  #   * A NEIGHBOURING window's samples carry a different reset stamp and a level that restarted
  #     from zero. Selecting candidates by time alone pulls them in and reads the new window's
  #     level as the old one's, which is the same class as the roll bug _rolled exists to catch.
  #   * The currently-LIVE window must not be scored at all: its reset has not happened, so it
  #     has no realised strand, and `completed_weekly_windows` already refuses it (RP-9). If a
  #     live window leaked in here it would score as a 100%-minus-current-level "strand" and
  #     drag every aggregate toward a number that has not happened yet.
  run python3 -c "$LOAD"'
base = ca.strand_score(burst_then_stall(), now=NOW)
# the NEXT window: opens at the old one s reset, still live (reset 158 h in the future), and its
# meter restarts near zero — the level a leak would read as the closed window s.
live_reset = round((NOW + 158 * 3600) / 60.0) * 60.0
nxt = burst_then_stall(reset=live_reset, span_h=9.9, tail_gap_h=158.0, fast=0.5, slow=0.5,
                       knee_h=0.0, start=0.0)
mixed = ca.strand_score(burst_then_stall() + nxt, now=NOW)
assert mixed["windows"] == 1, mixed["windows"]                  # the live window is NOT a window
assert not any(c["reset_t"] > NOW for c in mixed["cells"]), mixed["cells"]
# and every scored cell is bit-identical to the single-window run: nothing leaked in
assert len(mixed["cells"]) == len(base["cells"]), (mixed["cells"], base["cells"])
for a, b in zip(sorted(mixed["cells"], key=lambda c: c["h"]),
                sorted(base["cells"], key=lambda c: c["h"])):
    assert abs(a["projected"] - b["projected"]) < 1e-9, (a, b)
    assert abs(a["realised"] - b["realised"]) < 1e-9, (a, b)
    assert abs(a["weekly_pct"] - b["weekly_pct"]) < 1e-9, (a, b)
# ANOTHER ACCOUNT s window is scored on its own, never pooled into this one
other = ca.strand_score(burst_then_stall() + burst_then_stall(acct="next4", fast=0.2, slow=0.2),
                        now=NOW)
assert other["windows"] == 2, other["windows"]
assert {c["acct"] for c in other["cells"]} == {"next3", "next4"}, other["cells"]
n3 = [c for c in other["cells"] if c["acct"] == "next3" and abs(c["h"] - 24.0) < 1e-9][0]
assert abs(n3["signed_error"] - cell(base, 24.0)["signed_error"]) < 1e-9, (n3, base)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-37: sign-agreement is scored against the SURFACE's own no-strand threshold" {
  # `agree` answers the only question the footer actually asks: did the block say "this account
  # is losing quota" when it was. So the threshold has to be the one `pace_line` renders on —
  # its `s < 0.5` arm — and not a bare `> 0`, under which a 0.02 pp projection counts as having
  # called a 21 pp loss. On this fixture the two long horizons say NO STRAND against a real 21.65
  # pp loss (0% agreement) and the two short ones call it (100%).
  run python3 -c "$LOAD"'
assert ca.STRAND_SIGN_EPS == 0.5, ca.STRAND_SIGN_EPS      # the same constant pace_line renders on
sc = ca.strand_score(burst_then_stall(), now=NOW)
assert bucket(sc, 24.0)["agree"] == 0.0, sc["buckets"]
assert bucket(sc, 48.0)["agree"] == 0.0, sc["buckets"]
assert bucket(sc, 12.0)["agree"] == 100.0, sc["buckets"]
assert bucket(sc, 6.0)["agree"] == 100.0, sc["buckets"]
# a window that FILLED: nothing stranded and the nowcast says so — agreement on the other arm,
# which is what stops `agree` being a synonym for "the projection was non-zero".
full = ca.strand_score(burst_then_stall(fast=1.0, slow=1.0, knee_h=24.0, start=20.0), now=NOW)
fc = cell(full, 24.0)
assert fc is not None and fc["realised"] < 0.5, fc
assert fc["projected"] < 0.5, fc
assert bucket(full, 24.0)["agree"] == 100.0, full["buckets"]
# bias keeps its SIGN — under-projection and over-projection are different decisions and a MAE
# cannot tell them apart
assert bucket(sc, 24.0)["bias"] < 0, sc["buckets"]
assert abs(bucket(sc, 24.0)["mae"] - abs(bucket(sc, 24.0)["bias"])) < 1e-9, sc["buckets"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-38: --strand-score answers with NO config, NO keychain and NO sweep" {
  # Placed before load_cfg() for the reason --agents is, and this is the case that proves it:
  # $HOME is fixtured, so there is no accounts.json at all. Asking "was the projection right"
  # must never require the accounts being scored to be reachable — that is a coupling, not a
  # convenience, and it is exactly how a hermetic test found the same defect in --agents.
  #
  # It also prints the ACHIEVED span rather than the requested one. Completed weekly windows are
  # 168 h apart, so a short tail is the whole explanation for an empty table, and _util_tail
  # returns the achieved span precisely so a consumer cannot report the one it asked for.
  run python3 - <<'PY'
import json, os, subprocess, sys, time
from datetime import datetime, timezone
now = time.time()
reset = round((now - 10 * 3600) / 60.0) * 60.0
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
rows, t, wp = [], reset - 100 * 3600, 0.0
while t <= reset - 0.5 * 3600 + 1:
    rows.append({"ts": iso(t), "acct": "next3", "session_pct": 10, "weekly_pct": round(wp, 3),
                 "session_reset_at": None, "weekly_reset_at": iso(reset)})
    wp += (1.0 if (reset - t) / 3600.0 > 24.0 else 0.1) * 0.1
    t += 360.0
with open(os.environ["CC_UTIL_LOG"], "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
assert not os.path.exists(os.path.join(os.environ["HOME"], ".claude", "accounts.json"))
p = subprocess.run([sys.executable, os.environ["CA_BIN"], "--strand-score"],
                   capture_output=True, text=True, timeout=90)
assert p.returncode == 0, (p.returncode, p.stdout, p.stderr)
out = p.stdout
assert "strand score" in out, out
assert "1 completed weekly window(s)" in out, out
assert "sign-agree" in out, out
assert "spanning 99." in out or "spanning 100." in out, out    # the ACHIEVED span, not 720
# §5.4 acceptance 2: non-zero n at 24h, 12h and 6h, and a bias that COULD have been non-zero
j = subprocess.run([sys.executable, os.environ["CA_BIN"], "--strand-score", "--json"],
                   capture_output=True, text=True, timeout=90)
assert j.returncode == 0, (j.returncode, j.stdout, j.stderr)
d = json.loads(j.stdout)
by = {b["h"]: b for b in d["buckets"]}
for h in (24.0, 12.0, 6.0):
    assert by[h]["n"] >= 1, d["buckets"]
assert abs(by[24.0]["bias"]) > 1.0, d["buckets"]               # NOT a table of zeros
assert by[96.0]["n"] == 0 and by[96.0]["bias"] is None, d["buckets"]
print("OK")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
