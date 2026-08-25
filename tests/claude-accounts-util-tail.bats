#!/usr/bin/env bats
# _util_tail — the utilization series is selected by TIME, and it reports the span it ACHIEVED
# (USAGE_TELEMETRY_100P §5.2 S1b, RED-proof cases RP-6..RP-8 plus the regression control RP-8b).
#
# THE DEFECT. `_util_tail(path=None, max_bytes=131072)` was called argument-less by apply_burn,
# so the lookback was whatever 128 KiB happened to buy. Against the live file (3,675,531 B, mean
# record 292.4 B) that is 407 rows spanning 12.16 h, while the docstring claimed 48 h — so M2's
# 48 h lookback was unreachable and every metric fitted on it was fitted on a window that does
# not exist. The coupling is also INVERTED: adding one field to the record shortens the window.
#
# RP-8b IS THE LOAD-BEARING CASE and it is why the reader fix could not land alone. At a TRUE
# 48 h span the incumbent widest-pair weekly estimator anchors on a sample from BEFORE the
# weekly reset, reads `d < 0`, and leaves the field absent for the whole first stretch of every
# weekly window — the estimator goes blind exactly when the week's plan is set. Restoring the
# span without making the anchor roll-aware is a REGRESSION, not a fix (§5.5). A green suite
# that does not prove this is a vacuous suite.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; every case passes `path=`.

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
from datetime import datetime, timedelta, timezone
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
TMP = os.environ["BATS_TEST_TMPDIR"]
NOW = datetime.now(timezone.utc)
def rec(mins_ago, sp=10, wp=40, acct="next3", sra=None, wra=None):
    # padded to ~292 B, the live mean record size, so the byte pre-filter faces the real regime
    e = {"ts": (NOW - timedelta(minutes=mins_ago)).isoformat(), "acct": acct, "k": 2,
         "k_work": 1, "k_src": "work", "session_pct": sp, "weekly_pct": wp, "fable_pct": 5,
         "session_reset_at": sra, "weekly_reset_at": wra, "credits_on": False, "auth": "ok"}
    s = json.dumps(e)
    e["pad"] = "x" * max(0, 291 - len(s) - 10)
    return json.dumps(e) + "\n"
'

@test "RP-6: _util_tail honours a TIME span, not a byte cap (128 KiB buys 12 h of the live series)" {
  # 4,400 records at 6 min spacing = 440 h, ~1.29 MB, i.e. ~9x the old 128 KiB cap. A byte-capped
  # reader returns ~45 h of THIS fixture only because its record is small; against the live file
  # the same cap buys 12.16 h. The span assertion is what makes the case regime-independent.
  run python3 -c "$LOAD"'
p = os.path.join(TMP, "util.jsonl")
with open(p, "w") as f:
    for i in range(4400, 0, -1):
        f.write(rec(i * 6))
assert os.path.getsize(p) > 9 * 131072, os.path.getsize(p)
rows, span = ca._util_tail(path=p, hours=48.0)
assert span >= 47.0, span
assert min(r["_t"] for r in rows) <= time.time() - 47 * 3600, span
assert max(r["_t"] for r in rows) >= time.time() - 3600, span
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-7 CONTROL: a genuinely short series reports its SHORT span and does not lie" {
  # Every downstream abstain rule is written against the ACHIEVED span. An implementation that
  # returns the REQUESTED 48.0 passes RP-6 and fails here, and every consumer below it then
  # abstains on a span it never had — L2 inverted.
  run python3 -c "$LOAD"'
p = os.path.join(TMP, "short.jsonl")
with open(p, "w") as f:
    for i in range(20, 0, -1):
        f.write(rec(i * 6))
rows, span = ca._util_tail(path=p, hours=48.0)
assert len(rows) == 20, len(rows)
assert span < 3.0, span
assert span > 1.5, span
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-8 CONTROL: rotation — a .gz sibling is read when the live file is short" {
  # config/store-bounds.manifest:47 rotates this store at 25 MiB; at 237 KiB/day that lands
  # ~2026-12-11. Readers that open only the live path drop to a series of length ~0 that day.
  run python3 -c "$LOAD"'
import gzip
p = os.path.join(TMP, "rot.jsonl")
with open(p, "w") as f:
    for i in range(30, 0, -1):
        f.write(rec(i * 6))                      # newest 3 h only
with gzip.open(p + ".20260801T000000Z.gz", "wt") as f:
    for i in range(630, 30, -1):
        f.write(rec(i * 6))                      # the prior 60 h
rows, span = ca._util_tail(path=p, hours=48.0)
assert span >= 47.0, span
assert min(r["_t"] for r in rows) <= time.time() - 47 * 3600, span
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-8b: at a TRUE 48 h span the weekly anchor is roll-aware, so restoring the span is not a regression" {
  # The pairing this whole commit exists to keep together. 48 h of samples with the weekly window
  # rolling 30 h ago (96 -> 2 pp, reset stamp +168 h). The incumbent anchors on wk[0] — pre-roll,
  # 96 pp — reads d = 20 - 96 < 0, and leaves burn_wk_ppd ABSENT. Roll-aware, the anchor walks
  # forward to the post-roll segment and the same estimator measures 18 pp over 30 h = 14.4 %/d.
  run python3 -c "$LOAD"'
p = os.path.join(TMP, "roll48.jsonl")
OLD = (NOW + timedelta(hours=2)).isoformat()
NEW = (NOW + timedelta(hours=170)).isoformat()
with open(p, "w") as f:
    for i in range(48 * 10, 30 * 10, -1):        # 48 h .. 30 h ago: pre-roll, climbing to 96
        f.write(rec(i * 6, wp=96 - (i - 300) // 20, wra=OLD))
    for i in range(30 * 10, 0, -1):              # 30 h .. now: post-roll, 2 -> 20
        f.write(rec(i * 6, wp=2 + (300 - i) * 18 // 300, wra=NEW))
rows, span = ca._util_tail(path=p, hours=48.0)
assert span >= 47.0, span
r = {"acct": "next3"}
ca.apply_burn([r], {}, samples=rows)
assert "burn_wk_ppd" in r, r
assert 12.0 < r["burn_wk_ppd"] < 17.0, r
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-8c CONTROL: with NO roll in the span the anchor stays at the oldest sample" {
  # Without this, RP-8b is satisfied by an implementation that always anchors on the newest few
  # samples — which would silently shorten every measurement window to nothing.
  run python3 -c "$LOAD"'
p = os.path.join(TMP, "noroll48.jsonl")
WRA = (NOW + timedelta(hours=100)).isoformat()
with open(p, "w") as f:
    for i in range(48 * 10, 0, -1):
        f.write(rec(i * 6, wp=20 + (480 - i) * 24 // 480, wra=WRA))
rows, span = ca._util_tail(path=p, hours=48.0)
r = {"acct": "next3"}
ca.apply_burn([r], {}, samples=rows)
assert "burn_wk_ppd" in r, r
assert 11.0 < r["burn_wk_ppd"] < 13.0, r      # 24 pp over 48 h = 12 %/d, the FULL span
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
