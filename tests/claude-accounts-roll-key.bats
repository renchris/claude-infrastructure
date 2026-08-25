#!/usr/bin/env bats
# _reset_key / _rolled — window-ROLL detection on the utilization series
# (USAGE_TELEMETRY_100P §5.2 S1a, RED-proof cases RP-1..RP-5).
#
# THE DEFECT THESE PIN. The reset stamp jitters sub-second and STRADDLES the minute boundary:
# measured second-of-minute over 4,000 records is 00:1880 · 59:1427 · 01:13 · 17:1. So a key
# built by string-truncating the stamp to 16 chars ("2026-08-25T11:59") splits ONE window into
# two on 46.0% of adjacent session pairs (4,498 of 9,777) and 45.4% of weekly pairs, against a
# ground truth (reset stamp moved > 1 h) of 1.0%. Every one of those 4,399 spurious flips makes
# the roll branch inject an ABSOLUTE level where a DELTA belongs. In one axis analysis it
# fragmented 53 real windows into 2,341 ids and produced a wrong exchange rate; wired into the
# 5h EWMA it degrades MAE 0.0282 -> 0.2110, i.e. 5.4x worse than the incumbent it replaces.
#
# round(epoch/60) flips on 1.0% and agrees with ground truth on 99 of 99. The fix is one line;
# the reason it is not obvious is the entire content of these cases.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR, no series on disk — every case
# passes its samples to the function directly.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
}

# Load the module without running the CLI. Inputs arrive by env, never by argv: the subject
# parses sys.argv at import, so any argv we passed would be read by IT.
LOAD='
import importlib.machinery, importlib.util, os, sys
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
'

@test "RP-1: a sub-second stamp jitter across a minute boundary is NOT a roll" {
  # The live shape exactly: two samples 6 min apart, the meter RISING 40 -> 44, and reset stamps
  # 200 ms apart that land either side of 12:00. Truncation reads "11:59" vs "12:00" and calls
  # this a reset; it is the same window, 200 ms later.
  run python3 -c "$LOAD"'
a = {"session_pct": 40, "session_reset_at": "2026-08-25T11:59:59.900Z"}
b = {"session_pct": 44, "session_reset_at": "2026-08-25T12:00:00.100Z"}
assert ca._rolled(a, b, "session_reset_at", "session_pct") is False
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-2 CONTROL: a real roll IS detected, so RP-1 is not satisfied by a False stub" {
  run python3 -c "$LOAD"'
a = {"session_pct": 40, "session_reset_at": "2026-08-25T11:59:59.900Z"}
b = {"session_pct": 3,  "session_reset_at": "2026-08-25T16:59:59.900Z"}
assert ca._rolled(a, b, "session_reset_at", "session_pct") is True
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-3 CONTROL: a same-key reset is caught by the SECOND witness (the OR has two live arms)" {
  # Identical stamps, meter 40 -> 3. A key-only implementation passes RP-1 and RP-2 and fails
  # here — which is the point: the key comparison is blind to a reset inside one minute.
  run python3 -c "$LOAD"'
a = {"session_pct": 40, "session_reset_at": "2026-08-25T11:59:59.900Z"}
b = {"session_pct": 3,  "session_reset_at": "2026-08-25T11:59:59.900Z"}
assert ca._rolled(a, b, "session_reset_at", "session_pct") is True
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-4: a null stamp is NOT a roll — no window open is a STATE, not missing data" {
  run python3 -c "$LOAD"'
assert ca._reset_key(None) is None
assert ca._reset_key("") is None
assert ca._reset_key("not-a-timestamp") is None
a = {"session_pct": 40, "session_reset_at": "2026-08-25T11:59:59.900Z"}
b = {"session_pct": 44, "session_reset_at": None}
assert ca._rolled(a, b, "session_reset_at", "session_pct") is False
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-5: corpus — the rounded key agrees with ground truth on 200 pairs (truncation reads ~100)" {
  # 196 pairs jittering +-0.4 s across a minute boundary + 4 genuine rolls (reset moves 5 h,
  # meter drops). This is the case that would have caught the live defect: under truncation the
  # count comes out near 100 and the test is RED by a factor of 25.
  run python3 -c "$LOAD"'
from datetime import datetime, timedelta, timezone
base = datetime(2026, 8, 25, 12, 0, 0, tzinfo=timezone.utc)
pairs = []
for i in range(196):
    off = -0.4 if i % 2 == 0 else 0.4
    a = {"session_pct": 10, "session_reset_at": (base + timedelta(seconds=-0.4)).isoformat()}
    b = {"session_pct": 11, "session_reset_at": (base + timedelta(seconds=off)).isoformat()}
    pairs.append((a, b))
for i in range(4):
    a = {"session_pct": 90, "session_reset_at": (base + timedelta(seconds=-0.4)).isoformat()}
    b = {"session_pct": 2,  "session_reset_at": (base + timedelta(hours=5)).isoformat()}
    pairs.append((a, b))
n = sum(1 for a, b in pairs if ca._rolled(a, b, "session_reset_at", "session_pct"))
assert n == 4, n
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
