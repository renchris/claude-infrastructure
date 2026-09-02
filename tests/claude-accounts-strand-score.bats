#!/usr/bin/env bats
# strand_score / --strand-score — the planner's own mutation test.
# USAGE_TELEMETRY_100P §5.2 S5 (M3c), RED-proof cases RP-30..RP-34.
#
# WHAT IT REPLACES, AND WHY THAT IS THE WHOLE POINT. The synthesis published
# `4/4 recall · 0 false positives · median ~20 h lead` for the strand projection. That score
# evaluated the projection at the horizon's CLOSE, where it has already converged to
# `100 - weekly_pct` — i.e. to the true strand — so it was scoring the identity function against
# itself and agreed on 8 of 8 windows BY CONSTRUCTION. Eight binary cells, every one pre-decided.
# A harness that cannot come out badly is not a harness; it is the claim restated.
#
# So the cases below are not "does it compute a number". They are: can it report a WRONG
# estimator as wrong (RP-30), does it report a RIGHT one as right (RP-31), and does it refuse
# rather than impute when a horizon has no evidence (RP-32). RP-33 pins that the live window —
# whose realised strand is not yet a fact — is never graded. RP-34 pins the CLI contract.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; the series is passed explicitly
# to the function, and via CC_UTIL_LOG to the CLI.

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
NOW = int(time.time() // 60) * 60.0        # minute-aligned, so reset keys round exactly
STEP_H = 0.1                               # 6 min, the live series cadence
WEEK_H = 168.0
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def window(acct, reset_ago_h, final, shape="linear", observed_h=WEEK_H):
    """One weekly window that CLOSED reset_ago_h ago at `final` pct.
    shape=linear   -> constant rate, so the nowcast is exactly right at every horizon
    shape=accel    -> 0.62x for the first 70% of the window and 1.43x after, the measured
                      2.3x end-of-window acceleration; the nowcast must read this as optimistic
    observed_h     -> how much of the window the series actually covers, counting back from
                      the reset (the rest is a hole, and a hole is an ABSTAIN, not a zero)."""
    reset_t = NOW - reset_ago_h * 3600.0
    start = reset_t - WEEK_H * 3600.0
    out, t, wp = [], start, 0.0
    while t <= reset_t - 60:
        phase = (t - start) / (WEEK_H * 3600.0)
        rate = final / WEEK_H * (1.0 if shape == "linear" else (0.62 if phase < 0.7 else 1.43))
        if reset_t - t <= observed_h * 3600.0:
            out.append({"acct": acct, "ts": iso(t), "_t": t,
                        "weekly_pct": min(final, round(wp, 3)), "session_pct": 10,
                        "weekly_reset_at": iso(reset_t), "session_reset_at": iso(t + 3600.0)})
        wp += rate * STEP_H
        t += STEP_H * 3600.0
    out.append({"acct": acct, "ts": iso(reset_t - 60), "_t": reset_t - 60.0,
                "weekly_pct": final, "session_pct": 10,
                "weekly_reset_at": iso(reset_t), "session_reset_at": iso(reset_t)})
    return out
def write(path, samples):
    with open(path, "w") as f:
        for e in sorted(samples, key=lambda x: x["_t"]):
            f.write(json.dumps({k: v for k, v in e.items() if k != "_t"}) + "\n")
'

@test "RP-30: the harness reports a WRONG nowcast as wrong, and the error DECAYS toward the reset" {
  # THE ANTI-TAUTOLOGY CASE. Two windows whose burn accelerates 2.3x in the last 30% — the shape
  # measured across 12 window instances. Early in such a window the trailing pace is low, so the
  # nowcast projects far more strand than actually dies: a large POSITIVE bias at 96 h that
  # shrinks as the reset approaches and the estimator converges on the truth.
  #
  # Both halves are asserted. A non-zero bias alone would be satisfied by a broken function; the
  # DECAY is the signature of an estimator that is a good nowcaster precisely because it is a bad
  # forecaster, which is the finding S6 is gated on.
  run python3 -c "$LOAD"'
sam = window("next2", 4.0, 88, "accel") + window("next4", 8.0, 61, "accel")
sc = ca.strand_score(sam)
assert len(sc["windows"]) == 2, sc["windows"]
b = sc["buckets"]
for h in (96.0, 48.0, 24.0, 12.0, 6.0):
    assert b[h]["n"] == 2, (h, b[h])
assert b[96.0]["bias"] > 5.0, b            # optimistic about the strand, by a lot, early
assert b[96.0]["bias"] > b[24.0]["bias"] > 0.0, b
assert b[96.0]["mae"] > b[6.0]["mae"], b   # and it CONVERGES: this is the nowcast/forecast split
assert b[96.0]["mae"] == abs(b[96.0]["bias"]), b   # signed and absolute agree when all cells lean one way
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-31 CONTROL: a nowcast that is RIGHT scores near zero at every horizon" {
  # Without this, RP-30 is satisfied by a scorer that reports a large bias unconditionally —
  # which is the same defect as the old score, just with the sign flipped. Under a constant burn
  # the projection `weekly_pct + rate * hours_left` IS the final value at every instant, so a
  # correct harness must read ~0 at 96 h as readily as at 6 h.
  run python3 -c "$LOAD"'
sam = window("next2", 4.0, 88, "linear") + window("next4", 8.0, 61, "linear")
sc = ca.strand_score(sam)
b = sc["buckets"]
for h in (96.0, 48.0, 24.0, 12.0, 6.0):
    assert b[h]["n"] == 2, (h, b[h])
    assert abs(b[h]["bias"]) < 2.0, (h, b[h])
    assert b[h]["mae"] < 2.0, (h, b[h])
    assert b[h]["sign_agree"] == 1.0, (h, b[h])
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-32 CONTROL: a horizon with no evaluable sample reports n=0 and is EXCLUDED, never imputed" {
  # THE OTHER WAY TO MINT A TAUTOLOGY. A 96 h bucket that quietly fell back to the 48 h sample
  # would score the same estimator twice and publish the borrowed short-horizon skill as
  # long-horizon skill — the exact claim S6 is gated on. So a cell with no sample at
  # `weekly_reset_h >= H` contributes NOTHING: not a zero error, not an agreement, not an n.
  #
  # Fixture: a window the series only covers for its last 20 h. The 24/48/96 h horizons have no
  # sample at all; 12 h and 6 h do, and still aggregate over the windows that DO have one.
  run python3 -c "$LOAD"'
sam = window("next2", 4.0, 88, "linear", observed_h=20.0)
sc = ca.strand_score(sam)
b = sc["buckets"]
for h in (96.0, 48.0, 24.0):
    assert b[h]["n"] == 0, (h, b[h])
    assert b[h]["bias"] is None and b[h]["mae"] is None, (h, b[h])
    assert b[h]["sign_agree"] is None, (h, b[h])
for h in (12.0, 6.0):
    assert b[h]["n"] == 1, (h, b[h])
    assert b[h]["bias"] is not None, (h, b[h])
# and the window itself IS reported, with its realised strand — the hole is in the horizons,
# not in the window
assert len(sc["windows"]) == 1, sc["windows"]
assert abs(sc["windows"][0]["realised"] - 12.0) < 1e-6, sc["windows"]
rendered = ca.render_strand_score(sc, sam)
assert "EXCLUDED, not imputed" in rendered, rendered
assert "96h" in rendered, rendered
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-33 CONTROL: the LIVE window is never graded — its realised strand is not yet a fact" {
  # completed_weekly_windows already refuses the live window (its reset is in the FUTURE), and
  # this pins that the scorer inherits that refusal rather than re-deriving a looser rule. The
  # naive gap-only rule admits the live window and grades the nowcast against a number the
  # nowcast is itself still producing — an inflated agreement rate with no way to notice.
  run python3 -c "$LOAD"'
done_ = window("next2", 4.0, 88, "linear")
live = [dict(e, acct="next4", weekly_reset_at=iso(NOW + 40 * 3600.0)) for e in done_]
sc = ca.strand_score(done_ + live)
assert len(sc["windows"]) == 1, sc["windows"]
assert sc["windows"][0]["acct"] == "next2", sc["windows"]
for h, v in sc["buckets"].items():
    assert v["n"] <= 1, (h, v)
# CONTROL: once that same window has CLOSED it is graded, so the refusal above is about the
# reset being in the future and not about the account.
closed = [dict(e, acct="next4") for e in window("next4", 6.0, 61, "linear")]
sc2 = ca.strand_score(done_ + closed)
assert len(sc2["windows"]) == 2, sc2["windows"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-34: --strand-score answers with NO config, NO keychain and NO sweep, and --json matches" {
  # The branch sits before load_cfg() for the same reason --agents does, and one of the two
  # reasons is load-bearing here: the box whose windows stranded is frequently the box whose
  # logins have lapsed. A scoring harness that needs a working account to report on a window
  # that already closed is unavailable exactly when it is wanted. $HOME is an empty fixture
  # directory — there is no accounts.json anywhere on this path.
  python3 -c "$LOAD"'
write(os.environ["CC_UTIL_LOG"],
      window("next2", 4.0, 88, "accel") + window("next4", 8.0, 61, "accel"))
print("OK")'
  run timeout 120 python3 "$CA_BIN" --strand-score
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  [[ "$output" == *"strand nowcast score"* ]] || { echo "$output"; false; }
  [[ "$output" == *"2 completed account-week(s)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"horizon"* ]] || { echo "$output"; false; }
  [[ "$output" == *"96h"* && "$output" == *"6h"* ]] || { echo "$output"; false; }
  # the acceptance in §5.4: non-zero n in at least the 24/12/6 buckets, i.e. NOT a table of
  # abstentions wearing a table's shape
  [[ "$output" != *"ABSTAIN"* ]] || { echo "$output"; false; }
  run timeout 120 python3 "$CA_BIN" --strand-score --json
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  run python3 - <<'PY'
import json, os, subprocess
j = json.loads(subprocess.run(["python3", os.environ["CA_BIN"], "--strand-score", "--json"],
                              capture_output=True, text=True, check=True).stdout)
assert len(j["windows"]) == 2, j["windows"]
for h in ("96", "48", "24", "12", "6"):
    assert j["buckets"][h]["n"] == 2, (h, j["buckets"][h])
assert j["buckets"]["96"]["bias"] > j["buckets"]["24"]["bias"] > 0, j["buckets"]
assert all("at" not in w for w in j["windows"]), j["windows"]
print("OK")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
