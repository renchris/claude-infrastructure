#!/usr/bin/env bats
# strand_score / --strand-score — the instrument that CAN fail. USAGE_TELEMETRY_100P §5.2 S5
# (M3c), RED-proof cases RP-29..RP-33.
#
# WHAT IT REPLACES. The synthesis scored the strand rule at the horizon's CLOSE, where the
# projection has already converged to `100 - weekly_pct` — i.e. to the realised strand itself.
# That produced 8 binary cells on which the rule agreed with the IDENTITY FUNCTION 8/8, and was
# published as `4/4 recall / 0 FP / ~20 h median lead`. A harness that cannot fail measures
# nothing. This one evaluates at FIXED DISTANCES from the reset, where the estimator must
# commit, and reports a signed error that can be — and here demonstrably is — non-zero.
#
# THE CASE THAT MATTERS MOST IS RP-30, AND IT IS NOT ABOUT ACCURACY. A scoring harness that
# feeds the estimator the whole window is scoring hindsight: it will report a small bias no
# matter how bad the estimator is, which is the same vacuous pass the old score minted wearing
# different clothes. RP-30 truncates the series at the horizon and asserts the cell is BYTE-FOR-
# BYTE the same, so a lookahead leak of any size fails it. RP-29's own construction is built so
# that a leaking implementation would score CLOSER to truth, not further from it — a leak is
# therefore not detectable by "the numbers look worse", only by this control.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; samples passed explicitly except
# in RP-33, which writes a fixture series to $CC_UTIL_LOG to exercise the flag end to end.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
}

LOAD='
import importlib.machinery, importlib.util, json, os, sys, time
from datetime import datetime, timezone
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
NOW = time.time()
STEP_H = 0.1                      # 6 min, the live series cadence

def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")

def window(reset_t, segments, acct="next3", tail_gap_h=0.05):
    """One weekly window, walked forward to `tail_gap_h` before its reset.

    segments = [(hours, weekly pp per hour), ...] from the window OPEN. The last sample lands
    inside completed_weekly_windows WEEKLY_TAIL_GAP_H of the reset, which is what makes the
    window observed-to-its-close and therefore scoreable at all."""
    total = sum(s[0] for s in segments)
    t0 = reset_t - (total + tail_gap_h) * 3600.0
    out, t, wp = [], 0.0, 0.0
    for hours, rate in segments:
        for _ in range(int(round(hours / STEP_H))):
            out.append({"acct": acct, "weekly_pct": round(wp, 6), "session_pct": 10,
                        "_t": t0 + t * 3600.0, "ts": iso(t0 + t * 3600.0),
                        "weekly_reset_at": iso(reset_t),
                        "session_reset_at": iso(reset_t)})
            wp += rate * STEP_H
            t += STEP_H
    return out

def cell(res, h):
    b = [x for x in res["buckets"] if x["h"] == h]
    assert len(b) == 1, (h, res["buckets"])
    return b[0]
'

@test "RP-29: strand_score scores at FIXED horizons and can be WRONG — the bias is not a tautology" {
  # A window that DECELERATES: 100 h at 0.75 weekly pp/h, then a 30 h coast at 0.05. At the 24 h
  # horizon the EWMA has only just started to see the coast, so the nowcast under-predicts the
  # strand and the signed error is materially NEGATIVE — the direction that matters, because it
  # is the one that lets pp die unannounced. At the 6 h horizon the estimator has converged and
  # the error is small. A harness scoring at the window's close (the refuted one) reports ~0 at
  # every horizon by construction, which is exactly what this asserts is NOT happening.
  run python3 -c "$LOAD"'
reset_t = NOW - 6 * 3600.0
sam = window(reset_t, [(100.0, 0.75), (30.0, 0.05)])
res = ca.strand_score(sam, now=NOW)
assert res["windows"] == 1, res["windows"]
for h in (24.0, 12.0, 6.0):
    assert cell(res, h)["n"] == 1, (h, cell(res, h))
far, near = cell(res, 24.0), cell(res, 6.0)
# realised: the last sample sits at 100*0.75 + 30*0.05 = 76.5 pp, so 23.5 pp stranded
assert abs(far["cells"][0]["realised"] - 23.5) < 0.6, far["cells"][0]
# and the nowcast at T-24h, still carrying the fast segment in its EWMA, says far less will die
assert far["bias"] < -3.0, far
assert abs(near["bias"]) < abs(far["bias"]), (near["bias"], far["bias"])
assert far["mae"] >= abs(far["bias"]) - 1e-9, far
assert far["agree"] == 1, far          # both called a strand; it is the SIZE that is wrong
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-30 CONTROL: causality — rewriting the post-horizon future may not move the T−24h cell" {
  # THE VACUOUS-PASS TRAP, killed directly and without reproducing any of the subject's internal
  # arithmetic. Two series that are BYTE-IDENTICAL up to the 24 h horizon and then diverge
  # completely: one coasts to 76.5%, the other bursts to 96.9%. The 24 h cell's projection must
  # be EXACTLY equal across the pair, because every input it is entitled to see is the same
  # object. Any lookahead — feeding the EWMA the whole window, letting `now` drift forward,
  # anchoring on the window's last sample — moves it, at any leak size.
  #
  # NOTE THE POLARITY, WHICH IS WHY NO ACCURACY ASSERTION CAN SUBSTITUTE FOR THIS ONE. In a
  # decelerating window a leak makes the harness look BETTER: the projection converges toward
  # the truth it was not supposed to know. A leaking implementation therefore reports a SMALLER
  # bias and a higher sign-agreement, i.e. it looks like a better instrument.
  run python3 -c "$LOAD"'
reset_t = NOW - 6 * 3600.0
coast = window(reset_t, [(100.0, 0.75), (30.0, 0.05)])
burst = window(reset_t, [(100.0, 0.75), (6.0, 0.05), (24.0, 0.9)])
assert [e["_t"] for e in coast] == [e["_t"] for e in burst]          # same clock, same cadence
pre = [(a["_t"], a["weekly_pct"]) == (b["_t"], b["weekly_pct"])
       for a, b in zip(coast, burst) if (reset_t - a["_t"]) / 3600.0 >= 24.0]
assert pre and all(pre), "the two series must be identical up to the horizon"
a24, b24 = cell(ca.strand_score(coast, now=NOW), 24.0), cell(ca.strand_score(burst, now=NOW), 24.0)
assert a24["n"] == b24["n"] == 1, (a24, b24)
assert a24["cells"][0]["projected"] == b24["cells"][0]["projected"], (a24, b24)
assert a24["cells"][0]["at_h"] == b24["cells"][0]["at_h"], (a24, b24)
# ...and the futures really did diverge, so the equality above is a constraint and not a tautology
assert abs(a24["cells"][0]["realised"] - b24["cells"][0]["realised"]) > 15.0, (a24, b24)
assert a24["bias"] != b24["bias"], (a24["bias"], b24["bias"])
# CONTROL on the control: at the 6 h horizon the divergence IS inside what the cell may see, so
# there the two projections must differ. Without this, an always-constant projector passes.
a6, b6 = cell(ca.strand_score(coast, now=NOW), 6.0), cell(ca.strand_score(burst, now=NOW), 6.0)
assert abs(a6["cells"][0]["projected"] - b6["cells"][0]["projected"]) > 3.0, (a6, b6)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31 CONTROL: a horizon with no evaluable sample reports n=0 and is EXCLUDED, not imputed" {
  # A window the series only picked up 40 h before its reset. The 96 h and 48 h horizons have no
  # sample at all; the 24/12/6 ones do. An imputing harness would silently count the empty cells
  # as hits and publish `sign-agree 5/5` over two horizons it never scored.
  #
  # 40 h IS CHOSEN, NOT ARBITRARY: it must be under 48 so the two long horizons are genuinely
  # empty, and over 24 + WK_EWMA_MIN_SPAN_H (6.8) so the 24 h horizon has enough history behind
  # it for the EWMA to speak. A 30 h window makes the 24 h cell empty too — for the OTHER reason
  # (the span floor), which is a different abstain and would let this case pass vacuously.
  run python3 -c "$LOAD"'
reset_t = NOW - 6 * 3600.0
res = ca.strand_score(window(reset_t, [(40.0, 0.6)]), now=NOW)
for h in (96.0, 48.0):
    c = cell(res, h)
    assert c["n"] == 0 and c["bias"] is None and c["mae"] is None and c["agree"] is None, c
    assert c["cells"] == [], c
for h in (24.0, 12.0, 6.0):
    assert cell(res, h)["n"] == 1, (h, cell(res, h))
lines = ca.render_strand_score(res)
assert any("no evaluable sample at this horizon" in l for l in lines), lines
assert any("EXCLUDED, never imputed" in l for l in lines), lines
# the empty rows must not render a number that could be read as a bias of zero
assert not any("+0.00" in l and "96h" in l for l in lines), lines
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32 CONTROL: the LIVE window is never scored — S1d's rule is inherited, not re-decided" {
  # A window whose reset is in the FUTURE has no realised strand to score against; admitting it
  # scores a projection against a number that has not happened yet. This is the same `gap-IS-the-
  # mechanism` defect completed_weekly_windows was written to kill, and it must not be reopened
  # one layer up.
  run python3 -c "$LOAD"'
live = window(NOW + 40 * 3600.0, [(60.0, 0.6)], acct="next2", tail_gap_h=40.0)
res = ca.strand_score(live, now=NOW)
assert res["windows"] == 0, res["windows"]
assert all(c["n"] == 0 for c in res["buckets"]), res["buckets"]
lines = ca.render_strand_score(res)
assert any("nothing scored" in l for l in lines), lines
# CONTROL: the SAME shape, once its reset is in the past and it was observed to the close, IS
# scored — so RP-32 is not satisfied by a harness that scores nothing at all.
closed = window(NOW - 6 * 3600.0, [(60.0, 0.6)], acct="next2")
res2 = ca.strand_score(closed, now=NOW)
assert res2["windows"] == 1, res2["windows"]
assert sum(c["n"] for c in res2["buckets"]) >= 3, res2["buckets"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33: --strand-score answers with NO keychain, NO sweep and NO accounts config" {
  # The deployment property, not the arithmetic one: the branch sits before load_cfg(), like
  # --agents, so a fixtured $HOME with no accounts.json is enough. Placed after load_cfg() this
  # exits non-zero the moment $HOME is fixtured — which is exactly how the same bug was found on
  # --agents. Two windows across two accounts, written to $CC_UTIL_LOG as the real record shape.
  cat > /dev/null <<'EOF'
EOF
  run python3 -c "$LOAD"'
import io
reset_a, reset_b = NOW - 6 * 3600.0, NOW - 30 * 3600.0
sam = window(reset_a, [(100.0, 0.75), (30.0, 0.05)], acct="next3")
sam += window(reset_b, [(120.0, 0.5)], acct="next2")
with open(os.environ["CC_UTIL_LOG"], "w") as f:
    for e in sam:
        f.write(json.dumps({k: v for k, v in e.items() if k != "_t"}) + "\n")
print("WROTE %d" % len(sam))'
  [ "$status" -eq 0 ] || { echo "$output"; false; }

  [ ! -e "$HOME/.claude/accounts.json" ]
  run "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"strand nowcast scored against 2 completed weekly window"* ]] || { echo "$output"; false; }
  [[ "$output" == *"sign-agree"* ]] || { echo "$output"; false; }
  # §5.4 acceptance 2: non-zero n in at least the 24h, 12h and 6h buckets. A table whose every
  # cell reads 0.0 is the tautology all over again, so the acceptance is that it SCORED, not
  # that it was accurate.
  run bash -c '"$CA_BIN" --strand-score | grep -Ec "^ +(24|12|6)h +[1-9]"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" -eq 3 ] || { echo "$output"; false; }
  # ...and it reports a bias that COULD have been non-zero — here it is
  run bash -c '"$CA_BIN" --strand-score | grep -Eq "^ +24h +[0-9]+ +-[0-9]"'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "RP-33b CONTROL: --strand-score with an EMPTY series says so, and still exits 0" {
  # The fail-soft arm. A flag that stack-traces on a cold box is a flag nobody runs twice, and
  # an empty series is the ordinary state on a fresh machine — not an error.
  : > "$CC_UTIL_LOG"
  run "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"0 completed weekly window"* ]] || { echo "$output"; false; }
  [[ "$output" == *"nothing scored"* ]] || { echo "$output"; false; }
}
