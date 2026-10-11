#!/usr/bin/env bats
# claude-accounts --stranded — "how much weekly limit did we leave on the table for account N?"
# in one command. Operator ruling 2026-10-11: answering it took 8 tool calls, the last of them raw
# jq over account-utilization.jsonl, because the answer only existed as `realised`, a by-product of
# --strand-score's forecast scoring.
#
# It REUSES completed_weekly_windows (no second window detector) and adds one field, full_at: the
# first sample in the window at weekly_pct >= 100. So a live window must never appear here — the
# detector's own rule — and these cases drive the CLI against a fixture series, end to end.
#
# Hermetic: $HOME, $CLAUDE_CONFIG_DIR and the series path all inside BATS_TEST_TMPDIR, and no
# accounts.json exists, which is the point: the verb answers from history alone.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
  export TZ=UTC
  # Three windows, 0.5h cadence, each observed to its close:
  #   next4 closed 10h ago at 100%, reaching 100% ~37 min before its reset   -> 0 pp, full_at set
  #   next4 closed 178h ago at 63%                                           -> 37 pp, full_at null
  #   next3 closed 30h ago at 80%                                            -> 20 pp (filter target)
  # plus next4's LIVE window (reset 158h ahead), which must never appear.
  python3 - <<'PY'
import json, os, time
from datetime import datetime, timezone
NOW = time.time()
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def window(acct, reset_ago_h, pcts, step_h=0.5):
    """pcts[-1] is the sample AT the reset; earlier ones step back step_h each."""
    reset_t = round((NOW - reset_ago_h * 3600.0) / 60.0) * 60.0
    out = []
    for i, p in enumerate(reversed(pcts)):
        t = reset_t - i * step_h * 3600.0
        if t > NOW:
            continue
        out.append({"ts": iso(t), "acct": acct, "weekly_pct": p, "session_pct": 10,
                    "weekly_reset_at": iso(reset_t), "session_reset_at": iso(t + 3 * 3600.0)})
    return out
rows = []
# full at the sample 1.0h before the reset (two 0.5h steps back), ~matching the live 37-min case
rows += window("next4", 10.0, [90.0, 95.0, 99.0, 100.0, 100.0, 100.0])
rows += window("next4", 178.0, [55.0, 58.0, 61.0, 63.0])
rows += window("next3", 30.0, [70.0, 75.0, 80.0])
live_reset = round((NOW + 158 * 3600.0) / 60.0) * 60.0  # live: reset in the future, sampled
for i in range(18):                                    # over the last 9h, newest 1 min ago
    t = NOW - 60.0 - i * 1800.0
    rows.append({"ts": iso(t), "acct": "next4", "weekly_pct": 5.0, "session_pct": 10,
                 "weekly_reset_at": iso(live_reset), "session_reset_at": iso(t + 3 * 3600.0)})
rows.sort(key=lambda r: r["ts"])
with open(os.environ["CC_UTIL_LOG"], "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
PY
}

@test "--json: every closed window with acct/reset/final/strand/full_at; the live window is absent" {
  run "$CA_BIN" --stranded --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run python3 -c '
import json, sys
d = json.loads(sys.argv[1])
ws = d["windows"]
assert len(ws) == 3, ws                                   # live next4 window NOT admitted
for w in ws:
    assert set(w) >= {"acct", "reset_t", "reset_at", "final_pct", "strand", "full_at"}, w
ts = [w["reset_t"] for w in ws]
assert ts == sorted(ts, reverse=True), ts                 # newest first
full = [w for w in ws if w["acct"] == "next4" and w["final_pct"] == 100.0]
assert len(full) == 1 and full[0]["strand"] == 0.0, full
assert full[0]["full_at"] is not None, full                # reached 100% before the reset...
assert 0 < full[0]["reset_t"] - full[0]["full_at_t"] <= 3700, full   # ...one hour before it
part = [w for w in ws if w["acct"] == "next4" and w["final_pct"] == 63.0]
assert len(part) == 1 and part[0]["strand"] == 37.0 and part[0]["full_at"] is None, part
print("OK")' "$output"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "human output: 0 pp + reached-at for the full window, 37 pp for the 63% one, a per-account total" {
  run "$CA_BIN" --stranded
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"next4"* && "$output" == *"next3"* ]] || { echo "$output"; false; }
  grep -E 'next4 .*100%.* 0pp .*before reset' <<<"$output" || { echo "$output"; false; }
  grep -E 'next4 .* 63%.* 37pp .*never' <<<"$output" || { echo "$output"; false; }
  grep -E 'next4 total: 37pp stranded over 2 window' <<<"$output" || { echo "$output"; false; }
}

@test "positional ACCT filters to one account, and 4 is an alias for next4" {
  for a in next4 4; do
    run "$CA_BIN" --stranded "$a" --json
    [ "$status" -eq 0 ] || { echo "$output"; false; }
    run python3 -c '
import json, sys
ws = json.loads(sys.argv[1])["windows"]
assert len(ws) == 2 and {w["acct"] for w in ws} == {"next4"}, ws
print("OK")' "$output"
    [ "$status" -eq 0 ] || { echo "$a: $output"; false; }
  done
  run "$CA_BIN" --stranded 3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"next3 total: 20pp"* && "$output" != *"next4"* ]] || { echo "$output"; false; }
}

@test "an unknown ACCT is a usage error (64), never a silently empty answer" {
  run "$CA_BIN" --stranded next9
  [ "$status" -eq 64 ] || { echo "status=$status $output"; false; }
}
