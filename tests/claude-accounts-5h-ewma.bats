#!/usr/bin/env bats
# burn_5h_ewma_ph — the roll-aware 5h burn rate (USAGE_TELEMETRY_100P §5.2 S7 / M1),
# RED-proof cases RP-29..RP-33.
#
# WHAT S7 IS AND IS NOT. It ships on CORRECTNESS AND AVAILABILITY, never on accuracy. The
# incumbent `burn_5h_ph` is a single adjacent pair: one sample lost to a stale sweep and the rate
# is gone, and a pair that straddles the 5h roll reads `d < 0` and is discarded outright — so the
# metric goes blind exactly at the reset it exists to project across. Here a roll is not a
# discard: the new window's level IS the accrual, as a lower bound.
#
# 🚨 THE TWO HAZARDS ARE BOTH SILENT, and each produces a plausible wrong number rather than an
# error, which is why they are cases and not comments:
#
#   1. UNIT (RP-29 + core's RP-28). This emits %/h. `burn_5h_ph` is consumed by `_su_projected`
#      as FRACTION/h (`su + b * ahead`, su ∈ [0,1]). A %/h value written onto the old key
#      saturates the projection to 1.0 on every row and reads as "every account is under 5h
#      pressure" — a 100× error wearing a plausible face. Hence a NEW key, and a ÷100 at the one
#      consumer.
#   2. ROLL SPELLING (RP-32). Must be `_reset_key`, which ROUNDS. Under truncation the roll
#      branch fires on 46.0% of adjacent pairs — the stamp straddles the minute boundary — and
#      each false roll injects an ABSOLUTE level where a delta belongs: measured MAE degrades
#      0.0282 → 0.2110, i.e. 5.4× worse than the incumbent it replaces.
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
def s(ago_h, sp, sra_t, acct="next3"):
    return {"acct": acct, "session_pct": sp, "weekly_pct": 40.0,
            "_t": NOW - ago_h * 3600.0, "session_reset_at": iso(sra_t),
            "weekly_reset_at": iso(NOW + 100 * 3600.0)}
def ramp(span_h, rate_pph, step_h=0.5, sp0=5.0, sra_t=None):
    """samples walked forward to NOW at a constant %/h, one open session window throughout."""
    sra_t = NOW + 3 * 3600.0 if sra_t is None else sra_t
    n = int(round(span_h / step_h))
    return [s(span_h - i * step_h, sp0 + i * step_h * rate_pph, sra_t) for i in range(n + 1)]
'

@test "RP-29: burn_5h_ewma_ph is %/h, not fraction/h, and reports the RAW measured span" {
  # 30 pp per 30 min = 60 %/h. Every pair carries the same delta, so the weights cannot change
  # the answer — which is the point: this case pins the UNIT and the span contract, and the
  # weighting is pinned by RP-31 where the deltas differ.
  run python3 -c "$LOAD"'
sam = ramp(1.5, 60.0)
v, span = ca.burn_5h_ewma_ph(sam, NOW)
assert v is not None, "abstained on a 1.5 h span, above the 1.3 h floor"
assert abs(v - 60.0) < 0.5, v          # NOT 0.6 (fraction/h) and NOT 30 (per-step)
assert abs(span - 1.5) < 0.01, span    # the RAW measured span, never the 6 h lookback
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-30 CONTROL: below the 1.3h span floor it ABSTAINS, and just above it it REPORTS" {
  # THE FLOOR IS A MEASUREMENT, not a taste: below ~1.3 h a ±1 pp quantization step on the 5h
  # meter exceeds 25% of that meter's realised mean rate, so the number would be reading its own
  # rounding. Both arms are required — an unconditional None passes the first alone.
  run python3 -c "$LOAD"'
under, _ = ca.burn_5h_ewma_ph(ramp(1.0, 60.0), NOW)
assert under is None, under
over, span = ca.burn_5h_ewma_ph(ramp(1.5, 60.0), NOW)
assert over is not None and abs(over - 60.0) < 0.5, (over, span)
# fewer than 2 usable pairs is the OTHER abstain, and it is distinct from the span floor
one_pair = [s(4.0, 5.0, NOW + 3 * 3600.0), s(0.0, 65.0, NOW + 3 * 3600.0)]
v, _ = ca.burn_5h_ewma_ph(one_pair, NOW)
assert v is None, v                     # dt = 4 h > the 1 h pair cap: no usable pair at all
assert ca.burn_5h_ewma_ph([], NOW) == (None, 0.0)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31: a 5h ROLL is CROSSED, not discarded — and it never abstains because of one" {
  # THE INCUMBENT'S BLIND SPOT, as a case. `burn_5h_ph` takes the newest adjacent pair and drops
  # it when `d < 0`, so for the whole first stretch after every 5h reset the router's projection
  # input is simply absent. Here the post-roll level IS the accrual (a lower bound), so the rate
  # survives the reset.
  run python3 -c "$LOAD"'
SRA1 = NOW - 1.0 * 3600.0          # the OLD window reset 1 h ago
SRA2 = NOW + 4.0 * 3600.0          # the new one runs 4 h more
pre  = [s(2.0, 60.0, SRA1), s(1.5, 75.0, SRA1), s(1.2, 84.0, SRA1)]
post = [s(1.0, 6.0, SRA2), s(0.5, 21.0, SRA2), s(0.0, 36.0, SRA2)]
v, span = ca.burn_5h_ewma_ph(pre + post, NOW)
assert v is not None, "abstained on a roll — S7 must NEVER null on one"
assert v > 0, v
# the incumbent, on the same shape, has nothing to say: its newest pair straddles nothing but
# its OWN pair rule discards any crossing, and the crossing pair here reads 84 -> 6.
rows = [dict(acct="next3")]
ca.apply_burn(rows, {}, samples=pre + post)
assert "burn_5h_ewma_ph" in rows[0], rows[0]
assert abs(rows[0]["burn_5h_ewma_ph"] - v) < 1e-9, (rows[0], v)
# ...and the WEIGHTING is live: the same total accrual placed OLD weighs less than placed NEW.
front = ramp(2.0, 10.0)[:3] + [s(1.0, 25.0, NOW + 3 * 3600.0), s(0.5, 25.0, NOW + 3 * 3600.0),
                               s(0.0, 25.0, NOW + 3 * 3600.0)]
back  = [s(2.0, 5.0, NOW + 3 * 3600.0), s(1.5, 5.0, NOW + 3 * 3600.0),
         s(1.0, 5.0, NOW + 3 * 3600.0), s(0.5, 15.0, NOW + 3 * 3600.0),
         s(0.0, 25.0, NOW + 3 * 3600.0)]
fv, _ = ca.burn_5h_ewma_ph(front, NOW)
bv, _ = ca.burn_5h_ewma_ph(back, NOW)
assert bv > fv, (fv, bv)           # a flat mean would report these EQUAL
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32 CONTROL: the roll spelling is _reset_key — minute jitter is NOT a roll" {
  # THE 5.4x MUTANT. The reset stamp jitters sub-second and STRADDLES the minute boundary
  # (measured second-of-minute over 4,000 records: 00:1880 · 59:1427). Under truncation the two
  # spellings of one window differ, the roll branch fires, and `d = b.session_pct` injects an
  # absolute level where a 5 pp delta belongs. This fixture is a single window whose stamp
  # alternates 0.3 s either side of one minute boundary and whose true rate is 20 %/h.
  run python3 -c "$LOAD"'
M = (NOW + 3 * 3600.0) // 60.0 * 60.0 + 60.0        # an exact minute boundary, ~3 h out
lo, hi = M - 0.3, M + 0.3                            # round() -> same key; int() -> two keys
sam = [s(2.0 - i * 0.5, 5.0 + i * 0.5 * 20.0, lo if i % 2 == 0 else hi) for i in range(5)]
v, span = ca.burn_5h_ewma_ph(sam, NOW)
assert v is not None, (v, span)
assert abs(v - 20.0) < 0.5, v      # truncation reads ~2x-4x this: the LEVEL, not the delta
# the control that keeps this from passing on an implementation that never rolls at all
rolled = [s(2.0, 60.0, NOW - 3600.0), s(1.5, 75.0, NOW - 3600.0),
          s(1.0, 4.0, NOW + 4 * 3600.0), s(0.5, 14.0, NOW + 4 * 3600.0),
          s(0.0, 24.0, NOW + 4 * 3600.0)]
rv, _ = ca.burn_5h_ewma_ph(rolled, NOW)
assert rv is not None and rv > 0, rv
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33 CONTROL: burn_5h_ph stays POPULATED beside it — nothing reading it breaks silently" {
  # §5.2 S7 is literal: keep the old key for one release. A consumer that still reads
  # `burn_5h_ph` must keep getting the incumbent's fraction/h value, in its own unit, unchanged —
  # a rename dressed as an addition is how a silent consumer break ships.
  run python3 -c "$LOAD"'
sam = ramp(1.5, 60.0, step_h=0.5)
rows = [dict(acct="next3")]
ca.apply_burn(rows, {}, samples=sam)
r = rows[0]
assert "burn_5h_ph" in r, r
assert abs(r["burn_5h_ph"] - 0.6) < 0.02, r          # FRACTION/h, the incumbent unit
assert abs(r["burn_5h_ewma_ph"] - 60.0) < 0.5, r     # %/h, the new one
assert "burn_5h_ewma_span_h" in r, r
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
