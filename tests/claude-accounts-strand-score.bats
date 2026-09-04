#!/usr/bin/env bats
# strand_score / render_strand_score / --strand-score — M3c, the instrument that CAN fail.
# USAGE_TELEMETRY_100P §5.2 S5, RED-proof cases RP-28..RP-31.
#
# WHAT IT REPLACES, AND WHY THE REPLACEMENT IS THE POINT. The synthesis published
# `4/4 recall, 0 FP` for M3a's fire rule. That score evaluated the rule at each window's LAST
# sample — where the projection has already converged to `100 - weekly_pct`, i.e. to the true
# strand — so it agreed with the IDENTITY FUNCTION on 8 of 8 windows. Eight binary cells that
# could not come out wrong. A harness that cannot fail is not evidence, it is decoration, and it
# is why S6 (the rescue alarm) is gated behind this file rather than behind that claim.
#
# THE HARNESS MUST DISCRIMINATE, AND RP-28/28b IS THAT PROOF, MEASURED. On a DECELERATING window —
# 85 pp burned in the first three days, then flat — M3a at T−96h projects 0.0 pp of strand against
# a realised 15.0 pp: bias −15, sign agreement 0%. On a LINEAR window of the same length it reads
# −0.05 at every bucket. Same code, same buckets, opposite verdicts: the grade is a property of
# the data, not of the scorer. It also MEASURES what §5.1 LB-2 could previously only assert — the
# estimator converges as the horizon closes (−15.0 → −0.01 → 0.00 across T−96h → T−48h → T−24h),
# which is exactly what makes it a good nowcaster and a bad forecaster.
#
# 🚨 THE TRAP THAT MAKES A SCORER LIE, AND IT IS SILENT — RP-30. `burn_wk_ewma_ph` selects on
# `now - e["_t"] <= LOOKBACK`; for a sample AFTER `now` that value is NEGATIVE and therefore
# passes. Handed the whole series, the scorer fits on the future of the instant it is grading.
# Measured on the decelerating fixture at T−96h: the causal fit projects 0.000 (bias −15.0), the
# peeking fit projects 14.973 against a realised 15.0 — bias −0.03, MAE 0.03, a PERFECT GRADE
# earned entirely by reading the answer. A 15 pp failure renders as a flawless nowcaster, with no
# error, no warning, and every number on the page internally consistent.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; series passed explicitly.

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
def window(final, reset_ago_h, shape, acct="next3", from_h=168.0):
    """One weekly window at 6 min cadence. `shape(elapsed_frac) -> burned frac of `final``.
    `from_h` truncates the OLD end of the series, which is how a bucket is starved."""
    reset = NOW - reset_ago_h * 3600.0
    start = reset - 168 * 3600.0
    out, t = [], reset - from_h * 3600.0
    while t <= reset - 60:
        out.append({"acct": acct, "_t": t, "session_pct": 10.0,
                    "weekly_pct": round(final * shape((t - start) / (168 * 3600.0)), 3),
                    "session_reset_at": None, "weekly_reset_at": iso(reset)})
        t += 360.0
    return out
LIN = lambda f: f
def DECEL(f):                      # 85 pp in the first 3/7 of the week, then flat
    return min(1.0, f / (3.0 / 7.0))
def bucket(sc, h):
    return [b for b in sc["buckets"] if b["h"] == h][0]
'

@test "RP-28: the score is ~5 cells PER WINDOW at fixed horizons, and it comes out WRONG" {
  # The refuted score produced 8 binary cells AT THE CLOSE, where the projection has converged to
  # the truth by construction. This produces one cell per (window, horizon) at fixed distances
  # from the reset, where the projection is genuinely extrapolating.
  # THE ASSERTION IS THAT IT FAILS: a decelerating window projects ZERO strand at T−96h against a
  # realised 15 pp. A scorer that cannot report that is grading the identity function again.
  run python3 -c "$LOAD"'
sc = ca.strand_score(window(85.0, 4.0, DECEL))
assert sc["windows"] == 1, sc
assert sc["cells"] == 5, sc                       # one per horizon bucket
far = bucket(sc, 96.0)
assert far["n"] == 1, far
assert abs(far["bias"] + 15.0) < 0.1, far         # NEGATIVE 15: it saw no loss coming
assert abs(far["mae"] - 15.0) < 0.1, far
assert far["sign_agree"] == 0.0, far              # projected "no strand", reality stranded 15 pp
assert abs(far["cells"][0]["projected"]) < 0.01, far["cells"][0]
assert abs(far["cells"][0]["realised"] - 15.0) < 0.01, far["cells"][0]
# ...and it CONVERGES as the horizon closes. §5.1 LB-2 asserted this; this measures it.
near = bucket(sc, 24.0)
assert abs(near["bias"]) < 0.1, near
assert near["sign_agree"] == 1.0, near
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-28b CONTROL: a LINEAR window scores near zero at every horizon" {
  # Without this, RP-28 is satisfied by a scorer that is always wrong by 15 pp. The grade has to
  # be a property of the DATA. Same code, same buckets, opposite verdict.
  run python3 -c "$LOAD"'
sc = ca.strand_score(window(90.0, 4.0, LIN))
assert sc["cells"] == 5, sc
for h in ca.STRAND_BUCKETS:
    b = bucket(sc, h)
    assert b["n"] == 1, b
    assert abs(b["bias"]) < 0.5, b
    assert b["mae"] < 0.5, b
    assert b["sign_agree"] == 1.0, b
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-29: an unevaluable cell is SKIPPED — never imputed, never scored as a hit" {
  # A window whose series only reaches back 30 h has NO sample at weekly_reset_h >= 96 or >= 48.
  # Counting those as agreeing is how a bias converges to zero with no evidence under it, and it
  # is the single cheapest way to fake this whole instrument. n must fall, `skipped` must rise,
  # and the aggregate must be NULL — never 0.0, which reads as "measured, and perfect".
  #
  # BOTH SKIP ARMS FIRE ON THIS ONE FIXTURE, which is why it is the fixture. T−96h and T−48h have
  # no candidate sample at all. T−24h HAS one, and is skipped anyway because its causal prefix is
  # only 6.0 h — below M3a's own 6.8 h span floor, so the nowcast abstains there. An
  # implementation that only checks the first arm scores that cell on a rate reading its own
  # quantization, which is precisely what the floor exists to refuse.
  run python3 -c "$LOAD"'
sc = ca.strand_score(window(85.0, 4.0, DECEL, from_h=30.0))
assert sc["windows"] == 1, sc
assert sc["cells"] == 2, sc                       # 12h and 6h only
for h in (96.0, 48.0, 24.0):
    b = bucket(sc, h)
    assert b["n"] == 0, b
    assert b["skipped"] == 1, b
    assert b["bias"] is None, b                   # NOT 0.0
    assert b["mae"] is None, b
    assert b["sign_agree"] is None, b
for h in (12.0, 6.0):
    b = bucket(sc, h)
    assert b["n"] == 1 and b["skipped"] == 0, b
# an abstained bucket renders the WORD, never a number that reads as a clean grade
out = chr(10).join(ca.render_strand_score(sc))
assert "no evaluable sample this far out" in out, out
assert "T−96h" in out, out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-30: the scorer NEVER fits on the future of the instant it grades" {
  # burn_wk_ewma_ph selects on `now - e[_t] <= LOOKBACK`; for a sample AFTER `now` that is
  # negative and therefore PASSES. Without the causal slice the T−96h cell is fitted across the
  # flat tail it is supposed to be blind to, and projects 14.973 against a realised 15.0 —
  # bias −0.03, a PERFECT GRADE for a 15 pp miss, with every number internally consistent.
  # The assertion re-derives both readings independently and pins that the shipped one is causal.
  run python3 -c "$LOAD"'
ss = window(85.0, 4.0, DECEL)
w = ca.completed_weekly_windows(ss)[0]
at = max((e for e in ss if (w["reset_t"] - e["_t"]) / 3600.0 >= 96.0), key=lambda e: e["_t"])
wrh = (w["reset_t"] - at["_t"]) / 3600.0
def proj(sl):
    b, _ = ca.burn_wk_ewma_ph(sl, at["_t"], wrh)
    return ca.wk_strand_pp({"weekly_pct": at["weekly_pct"], "weekly_reset_h": wrh,
                            "burn_wk_ewma_ph": b})
causal = proj([e for e in ss if e["_t"] <= at["_t"]])
peek = proj(ss)
assert abs(causal) < 0.01, causal
# the trap is REAL on this fixture, not theoretical: peeking reproduces the ANSWER (15.0 pp) to
# within a rounding step, so the 15 pp miss renders as a flawless nowcaster. Banded, not pinned:
# the fixture is anchored to wall-clock NOW, so the scored instant slides against the 6 min grid.
assert abs(peek - 15.0) < 0.6, peek
shipped = bucket(ca.strand_score(ss), 96.0)["cells"][0]["projected"]
assert abs(shipped - causal) < 1e-9, (shipped, causal, peek)
assert abs(shipped - peek) > 14.0, (shipped, peek)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-30b CONTROL: samples the instant DOES own are used — the slice is a cut, not a mute" {
  # A causal slice implemented as "use nothing" also passes RP-30. The T−6h cell of the LINEAR
  # window must carry a real fitted rate and a span above the M3a floor, i.e. the prefix is read.
  run python3 -c "$LOAD"'
sc = ca.strand_score(window(90.0, 4.0, LIN))
c = bucket(sc, 6.0)["cells"][0]
assert abs(c["at_h"] - 6.0) < 0.2, c            # scored at the horizon, not at the close
assert 9.0 < c["projected"] < 11.0, c           # 90% linear ⇒ ~10 pp still to die
assert abs(c["realised"] - 10.0) < 0.1, c
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31: --strand-score answers with NO accounts.json, no keychain and no sweep" {
  # Sited before load_cfg() for the --agents reasons: it grades PAST windows out of the series,
  # so requiring a live config to do it is a coupling, not a convenience — which is exactly how
  # the provider branch was found mis-sited. The fixture $HOME holds a series and nothing else;
  # a branch placed after load_cfg() exits non-zero here, and the endpoint is unreachable, so a
  # branch that swept would hang or fail loudly rather than print.
  python3 - <<'PY'
import json, os, time
from datetime import datetime, timezone
now = time.time()
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
reset = now - 4 * 3600.0
start = reset - 168 * 3600.0
with open(os.environ["CC_UTIL_LOG"], "w") as f:
    t = start
    while t <= reset - 60:
        f.write(json.dumps({"ts": iso(t), "acct": "next3", "session_pct": 10,
                            "weekly_pct": round(90.0 * (t - start) / (reset - start), 3),
                            "session_reset_at": None, "weekly_reset_at": iso(reset)}) + "\n")
        t += 360.0
PY
  [ ! -f "$HOME/.claude/accounts.json" ]
  CC_UTIL_LOG="$CC_UTIL_LOG" run python3 "$CA_BIN" --strand-score --hours 400
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  [[ "$output" == *"M3a strand nowcast"* ]] || { echo "$output"; false; }
  [[ "$output" == *"1 completed weekly window(s)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"T−12h"* ]] || { echo "$output"; false; }
  [[ "$output" == *"S6's rescue alarm is gated on the T−12h bias"* ]] || { echo "$output"; false; }
  CC_UTIL_LOG="$CC_UTIL_LOG" run python3 "$CA_BIN" --strand-score --hours 400 --json
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  echo "$output" > "$BATS_TEST_TMPDIR/sc.json"
  run python3 -c '
import json, sys
sc = json.load(open(sys.argv[1]))
assert sc["windows"] == 1, sc
assert [b["h"] for b in sc["buckets"]] == [96.0, 48.0, 24.0, 12.0, 6.0], sc
b12 = [b for b in sc["buckets"] if b["h"] == 12.0][0]
assert b12["n"] == 1 and abs(b12["bias"]) < 0.5, b12
print("OK")' "$BATS_TEST_TMPDIR/sc.json"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31b: --hours 0 is honoured as ZERO, never promoted to the 60d default" {
  # `_num_flag(...) or 1440.0` reads an explicit 0 as absent and silently hands back a 60-day
  # scan — the confident-wrong-answer class _num_flag's own docstring exists to refuse. A caller
  # asking for nothing must GET nothing, visibly.
  : > "$CC_UTIL_LOG"
  CC_UTIL_LOG="$CC_UTIL_LOG" run python3 "$CA_BIN" --strand-score --hours 0
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  [[ "$output" == *"scored on 0 completed weekly window(s)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"no evaluable sample this far out"* ]] || { echo "$output"; false; }
  CC_UTIL_LOG="$CC_UTIL_LOG" run python3 "$CA_BIN" --strand-score --hours banana
  [ "$status" -eq 64 ] || { echo "rc=$status out=$output"; false; }
}
