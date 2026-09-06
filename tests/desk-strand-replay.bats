#!/usr/bin/env bats
# scripts/desk-strand-replay.py — the repo's ONLY reader of the weekly-strand retrospective.
#
# WHY THIS SUITE EXISTS. The reader is hand-run: no hook, no daemon and no close-time surface calls
# it (weekly-reset-utilization-2026-08-25 §5.3). A hand-run reader that crashes is indistinguishable
# from one nobody happened to run, and that is exactly what happened — two quota-blank sweeps on
# 2026-08-30 made `int - None` a TypeError, and the retrospective was unreadable from then until
# 2026-09-05, across the worst-utilization week the series has recorded.
#
# Each case pins one claim that a plausible-looking implementation gets wrong:
#   1. a quota-blank sweep is DATA, not a crash
#   2. a mid-window zeroing (2026-09-01 onwards) is not a reset
#   3. ...and the usage it discards is added back, not published as a loss
#   4. a window the series did not watch from its start is never summed
#
# Hermetic: $HOME and the series into $BATS_TEST_TMPDIR; the config is the tracked example file.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CLAUDE_ACCOUNTS_JSON="$REPO/accounts.json.example"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/series.jsonl"
  python3 - "$CC_UTIL_LOG" <<'PY'
import json, sys
W1 = "2026-01-08T00:00:00.100000+00:00"
W2 = "2026-01-15T00:00:00.200000+00:00"
W3 = "2026-01-22T00:00:00.300000+00:00"
def row(ts, w, res):
    return json.dumps({"ts": ts, "acct": "next", "k": 0, "k_work": 0, "k_src": "work",
                       "session_pct": 1, "weekly_pct": w, "fable_pct": 0,
                       "session_reset_at": None, "weekly_reset_at": res,
                       "credits_on": False, "credits_used": 0.0, "auth": "ok", "stale": False})
series = [
    # The ledger opens MID-window and its first samples flap (the real one read 58% then lower on
    # 2026-08-10). Summed, this window would publish 78% used; it must report the meter instead.
    row("2026-01-07T19:00:00+00:00", 58, W1),
    row("2026-01-07T20:00:00+00:00", 10, W1),
    row("2026-01-07T21:00:00+00:00", 20, W1),
    row("2026-01-08T00:05:00+00:00",  0, None),   # GENUINE reset: the emptied bucket has no close
    row("2026-01-08T01:00:00+00:00",  5, W2),
    row("2026-01-11T00:00:00+00:00", 40, W2),
    row("2026-01-11T06:00:00+00:00",  0, W2),     # zeroing INSIDE the window: same close, so not a reset
    row("2026-01-13T00:00:00+00:00", 30, W2),
    row("2026-01-14T00:00:00+00:00", None, None), # quota-blank sweep (logged-out / keychain / stale)
    row("2026-01-15T00:05:00+00:00",  0, None),   # GENUINE reset
    row("2026-01-15T01:00:00+00:00",  5, W3),
]
open(sys.argv[1], "w").write("\n".join(series) + "\n")
PY
}

replay() { run python3 "$REPO/scripts/desk-strand-replay.py"; }

@test "a quota-blank sweep is skipped, not a crash" {
  replay
  [ "$status" -eq 0 ]
  [[ "$output" != *"TypeError"* ]]
}

@test "a mid-window zeroing is not counted as a weekly reset" {
  replay
  [[ "$output" == *"2 weekly resets observed"* ]]
}

@test "a zeroed window reports the usage it actually took, not the meter" {
  replay
  [[ "$output" == *"reset at  70% used  -> 30pp stranded"* ]] || false
  [[ "$output" == *"meter read 30%; zeroed mid-window"* ]]
}

@test "a window not observed from its start is reported off the meter, never summed" {
  replay
  [[ "$output" == *"reset at  20% used  -> 80pp stranded"* ]] || false
  [[ "$output" != *"78% used"* ]]
}
