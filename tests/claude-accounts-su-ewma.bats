#!/usr/bin/env bats
# burn_5h_ewma_ph — the roll-aware 5h burn rate that replaces the newest-adjacent-pair
# `burn_5h_ph`. USAGE_TELEMETRY_100P §5.2 S7 (M1), RED-proof cases RP-34..RP-37.
#
# WHAT IT REPLACES AND WHY. The incumbent reads ONE adjacent pair inside a 2 h window and calls
# it the burn rate; a single 6-minute sample gap therefore decides the number, and a pair that
# straddles a window roll reads `d < 0` and leaves the field absent entirely. This form is an
# EWMA over a 6 h lookback, and a roll is reconstructed rather than discarded.
#
# BOTH OF S7'S NAMED HAZARDS SILENTLY PRODUCE A PLAUSIBLE WRONG NUMBER, which is why each has its
# own case rather than a shared one:
#
#   * UNIT (RP-27/RP-28, in claude-accounts-core.bats). This emits %/h; `burn_5h_ph` is consumed
#     by _su_projected as FRACTION/h. Shipping %/h onto the old key saturates the projection to
#     1.0 on every row and reads as "every account is under 5h pressure" — a 100x error wearing a
#     plausible face.
#   * ROLL SPELLING (RP-37). It must be _reset_key's ROUNDING. Under truncation the roll branch
#     fires on 46.0% of adjacent pairs and injects an absolute LEVEL as a delta: measured MAE
#     degrades 0.0282 -> 0.2110, i.e. 5.4x WORSE than the incumbent it replaces. A metric that
#     ships 5x worse than what it replaced, while looking like a refinement, is the failure this
#     suite exists to make impossible.
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
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def burn(segments, step_h=0.25, acct="next3", reset_at=None):
    """segments = [(hours, pct_per_h), ...] oldest first, ending AT NOW. One 5h window
    throughout unless reset_at is a callable(t) -> stamp."""
    total = sum(s[0] for s in segments)
    t0 = NOW - total * 3600.0
    fixed = iso(NOW + 3 * 3600.0)
    out, t, sp = [], 0.0, 0.0
    for hours, rate in segments:
        n = int(round(hours / step_h))
        for _ in range(n):
            ts = t0 + t * 3600.0
            out.append({"acct": acct, "_t": ts, "session_pct": sp, "weekly_pct": 40,
                        "session_reset_at": reset_at(ts) if reset_at else fixed,
                        "weekly_reset_at": iso(NOW + 100 * 3600.0)})
            sp += rate * step_h
            t += step_h
    return out
'

@test "RP-34: burn_5h_ewma_ph is %/h, and it weights the RECENT pairs hard" {
  # A uniform rate must come back exactly, or the weighting is doing something other than
  # weighting. Then the discrimination: 2 h at 2 %/h followed by 1 h at 10 %/h has a UNIFORM mean
  # of 4.67 %/h, and an hl=1h EWMA must land far above it -- the whole reason the incumbent's
  # single newest pair was worth replacing is that a rate has recent history, not just a last
  # reading.
  run python3 -c "$LOAD"'
v, span = ca.burn_5h_ewma_ph(burn([(3.0, 5.0)]), NOW)
assert v is not None, (v, span)
assert abs(v - 5.0) < 0.05, v                      # %/h, NOT 0.05 fraction/h
assert 2.5 < span <= 3.0, span
sam = burn([(2.0, 2.0), (1.0, 10.0)])
v2, span2 = ca.burn_5h_ewma_ph(sam, NOW)
# Compared against the UNWEIGHTED rate over the same samples, computed here, so the case pins
# discrimination rather than one arithmetic answer: an implementation that averages (or that
# reads only the newest pair) cannot land between the two.
flat = (sam[-1]["session_pct"] - sam[0]["session_pct"]) / ((sam[-1]["_t"] - sam[0]["_t"]) / 3600.0)
assert 4.0 < flat < 5.0, flat
assert v2 > flat * 1.15, (v2, flat)                # hl=1h leans on the recent 10 %/h
assert v2 < 10.0, v2                               # ...without becoming the newest pair alone
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-35 CONTROL: a session ROLL is reconstructed, never discarded and never an abstain" {
  # The incumbent leaves the field ABSENT across a roll (`d < 0` reads as unknown), so it goes
  # blind exactly at the window boundary — and the 5h boundary is where the router most needs a
  # rate. Here the post-roll LEVEL is the increment, a lower bound.
  #
  # THE MUTANT THIS KILLS: `d = max(0, b - a)` without the roll branch scores the newest pair —
  # the heaviest-weighted one — at 0 and pulls a true 30 %/h down to ~23.6. Not absent, not
  # obviously broken: 21% low, in the direction that under-states pressure.
  run python3 -c "$LOAD"'
sam = burn([(2.0, 30.0)], step_h=0.25)
roll_at = sam[-1]["_t"]
for e in sam:                                       # the newest sample is a fresh window
    if e["_t"] >= roll_at:
        e["session_reset_at"] = iso(NOW + 5 * 3600.0)
        e["session_pct"] = 7.5                      # 30 %/h x 0.25 h into the NEW window
v, span = ca.burn_5h_ewma_ph(sam, NOW)
assert v is not None, "abstained on a roll"
assert abs(v - 30.0) < 1.0, v                       # 23.6 is the non-roll-aware answer
assert span > 1.3, span
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-36 CONTROL: it abstains on the RAW measured span and on too few pairs" {
  # L2, and the floor is sized rather than chosen: below 1.3 h a +-1 pp quantization step exceeds
  # 25% of the 5h meter realised mean, so the number would be reading its own rounding. The span
  # returned is the RAW one — never the weighted span, which an EWMA makes arbitrarily short.
  run python3 -c "$LOAD"'
v, span = ca.burn_5h_ewma_ph(burn([(1.0, 5.0)]), NOW)
assert v is None, (v, span)                         # 0.75 h of pairs < 1.3 h
assert span < 1.3, span                             # ...and it SAYS how short, for the caller
v2, span2 = ca.burn_5h_ewma_ph(burn([(1.75, 5.0)]), NOW)
assert span2 >= 1.3, span2
assert v2 is not None, "the boundary is the SPAN, not some other short-series accident"
one = burn([(3.0, 5.0)])[-2:]                       # two samples = ONE pair
assert ca.burn_5h_ewma_ph(one, NOW)[0] is None
assert ca.burn_5h_ewma_ph([], NOW)[0] is None
# a sample older than the 6h lookback cannot rescue a thin recent series
stale = burn([(3.0, 5.0)])
for e in stale[:-4]:
    e["_t"] -= 20 * 3600.0
assert ca.burn_5h_ewma_ph(stale, NOW)[0] is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-37 CONTROL: the roll test is _reset_key ROUNDING — a minute-straddling stamp is no roll" {
  # HAZARD 2, as a test. The reset stamp jitters sub-second and STRADDLES the minute boundary
  # (measured second-of-minute over 4,000 records: 00:1880 · 59:1427). Under truncation the two
  # spellings below are different keys, every adjacent pair reads as a roll, and the roll branch
  # injects the absolute LEVEL as a delta — a true 5 %/h renders as tens of %/h. Under rounding
  # they are one window, which they are.
  run python3 -c "$LOAD"'
M = round((NOW + 4 * 3600.0) / 60.0)                # a whole-minute reset instant
flip = [0]
def straddle(ts):
    # alternate the two spellings of the SAME minute, as the live stamp does
    flip[0] += 1
    return iso(M * 60.0 + (0.4 if flip[0] % 2 else -0.3))
sam = burn([(2.0, 5.0)], step_h=0.25, reset_at=straddle)
keys = {ca._reset_key(e["session_reset_at"]) for e in sam}
assert len(keys) == 1, keys                         # the fixture really is one rounded window
assert len({e["session_reset_at"] for e in sam}) == 2, "fixture does not straddle the boundary"
v, _ = ca.burn_5h_ewma_ph(sam, NOW)
assert v is not None, v
assert abs(v - 5.0) < 0.2, v                        # truncation reads tens of %/h here
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
