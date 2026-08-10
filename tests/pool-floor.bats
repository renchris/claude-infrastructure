#!/usr/bin/env bats
# pool-floor — the measured floor under fleet concurrency, and the recorder that makes the
# subscription-pool half of it computable at all.
#
# WHY. docs/plans/CONCURRENCY_PROGRAM.md targets ~100 concurrent sessions against a measured ~14,
# and every attempt to price that has reached for a CEILING the data cannot supply: the OAuth
# usage endpoint returns `percent` and `resets_at` and no entitlement, and the one experiment
# that probed the pool boundary is void (an account at 100% weekly created cloud sessions
# normally, so weekly quota does not gate create). A FLOOR is obtainable and falsifiable, and it
# is what a scheduler needs.
#
# The pool half was not merely unmeasured, it was UNMEASURABLE: every live sweep computed
# per-account utilization and threw it away (a single-slot /tmp cache with depth one, plus a
# per-account last-good ledger that overwrites). record_utilization stops discarding it.
#
# Hermetic: fixture stores in BATS_TEST_TMPDIR, no network, no real ~/.claude write.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO
  export CA_BIN="$REPO/bin/claude-accounts"
  export FLOOR="$REPO/scripts/pool-floor.sh"
  export REAL_HOME="$HOME"          # captured before the override; test 12 reads the real stores
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CC_CAP_LOG="$BATS_TEST_TMPDIR/cap.jsonl"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util.jsonl"
}

LOAD='
import importlib.machinery, importlib.util, os
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "ca.log")
'

# ---- the recorder --------------------------------------------------------------------------------

@test "recorder: a live sweep's per-account measurement is kept, not discarded" {
  run python3 -c "$LOAD"'
import json, os
p = os.path.join(os.environ["BATS_TEST_TMPDIR"], "u.jsonl")
rows = [{"acct": "next",  "k": 3, "session_pct": 10, "weekly_pct": 40, "fable_pct": 0,
         "credits_on": False, "credits_used": 0.0, "auth": "ok"},
        {"acct": "next3", "k": 7, "session_pct": 55, "weekly_pct": 58, "fable_pct": 13,
         "credits_on": False, "credits_used": 0.0, "auth": "ok"}]
n = ca.record_utilization(rows, path=p)
assert n == 2, n
got = [json.loads(l) for l in open(p)]
assert [g["acct"] for g in got] == ["next", "next3"], got
for k in ("ts","acct","k","session_pct","weekly_pct","fable_pct","credits_on","credits_used","auth","stale"):
    assert k in got[0], k
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "recorder: rate-limited, so a desk hammering --fresh cannot become a growth problem" {
  run python3 -c "$LOAD"'
import os
p = os.path.join(os.environ["BATS_TEST_TMPDIR"], "r.jsonl")
rows = [{"acct": "next", "k": 1, "session_pct": 1, "weekly_pct": 1}]
assert ca.record_utilization(rows, path=p) == 1
assert ca.record_utilization(rows, path=p) == 0, "second write inside the interval was not suppressed"
assert ca.record_utilization(rows, path=p, min_interval_s=0) == 1, "an elapsed interval must write"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "recorder: an unmeasurable row is skipped, an INHERITED one is kept and flagged" {
  # A gap in the series is indistinguishable from a quiet period, so a stale row must be
  # recorded-and-marked rather than dropped — but a row carrying no numbers at all is not a
  # measurement and would read as a genuine zero.
  run python3 -c "$LOAD"'
import json, os
p = os.path.join(os.environ["BATS_TEST_TMPDIR"], "s.jsonl")
rows = [{"acct": "dead", "k": 0, "session_pct": None, "weekly_pct": None, "error": "boom"},
        {"acct": "inherited", "k": 2, "session_pct": 9, "weekly_pct": 9, "stale_quota": True}]
assert ca.record_utilization(rows, path=p) == 1
got = [json.loads(l) for l in open(p)]
assert got[0]["acct"] == "inherited" and got[0]["stale"] is True, got
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "recorder: it can never break the tool it rides on" {
  # A side-car must fail no wider than itself. This one is bolted onto the binary the whole fleet
  # routes with; an unwritable store must cost the SERIES, never `claude-accounts --route`.
  run python3 -c "$LOAD"'
n = ca.record_utilization([{"acct": "x", "k": 1, "session_pct": 1, "weekly_pct": 1}],
                          path="/nonexistent-root-dir-xyz/deeper/u.jsonl")
assert n == 0, n
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "recorder: the store is registered in BOTH rotation mechanisms" {
  grep -q 'logs/account-utilization.jsonl' "$REPO/scripts/rotate-autonomy-logs.sh" || {
    echo "absent from DEFAULT_TARGETS — the store will grow unbounded"; false; }
  grep -qE '^logs/account-utilization\.jsonl\|' "$REPO/config/store-bounds.manifest" || {
    echo "absent from store-bounds.manifest — no cap, nothing pages"; false; }
}

# ---- the spend guard -----------------------------------------------------------------------------

@test "spend guard: the SSOT carries the authorization, so it can go red instead of be remembered" {
  run python3 -c '
import json, os, sys
d = json.load(open(os.environ["REPO"] + "/accounts.json"))
s = d.get("spend")
assert isinstance(s, dict), "accounts.json has no spend block"
assert "usage_credits_authorized" in s, s
assert isinstance(s["usage_credits_authorized"], bool), s
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "spend guard: UNAUTHORIZED spend renders as a breach, authorized spend as a stat" {
  # The defect was that both rendered identically — a number to read past rather than a guard.
  # Keys on SPEND, never on the toggle: an account read credits_on=false with $176.91 spent.
  run python3 -c "$LOAD"'
import io, contextlib, json as _j, os as _o
real = _j.load(open(_o.environ["REPO"] + "/accounts.json"))

def note(authorized):
    """render_readout PRINTS; capture stdout rather than reading a return value it has not got."""
    row = {"acct": "next3", "k": 0, "auth": "ok", "credits_used": 17691,
           "credits_used_usd": 176.91, "credits_on": False, "session_pct": 1, "weekly_pct": 1}
    # router/frontier/login_warn_h DERIVED from the real SSOT, never hand-copied: a hand-built
    # fixture silently diverges the moment a constant is added, and the case then certifies a
    # shape production never renders.
    cfg = {"spend": {"usage_credits_authorized": authorized},
           "login_warn_h": real["login_warn_h"], "frontier": real["frontier"],
           "router": real["router"], "accounts": []}
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ca.render_readout([row], cfg, {"active": False, "end": None, "deadline": None,
                                       "permanent": False}, False)
    return buf.getvalue()

breach = note(False)
assert "176.91" in breach, breach
assert "\U0001F6A8" in breach, "unauthorized spend must render as a breach, not a neutral bullet"
assert "NOT authorized" in breach, breach
ok = note(True)
assert "176.91" in ok, ok
assert "\U0001F6A8" not in ok, "authorized spend must NOT render as a breach: " + ok
assert "authorized in accounts.json" in ok, ok
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ---- the floor -----------------------------------------------------------------------------------

@test "floor: the machine floor is the SUSTAINED count, not the peak" {
  # One lucky sample at 40 proves the box briefly held 40, not that it sustains it. The floor is
  # the minimum across a run of consecutive healthy samples.
  : > "$CC_CAP_LOG"
  for i in $(seq 1 12); do
    printf '{"ts":"2026-08-01T00:%02d:00Z","verdict":"OK","sessions":20,"swap_used_mb":0}\n' "$i" >> "$CC_CAP_LOG"
  done
  printf '{"ts":"2026-08-01T01:00:00Z","verdict":"OK","sessions":40,"swap_used_mb":0}\n' >> "$CC_CAP_LOG"
  printf '{"ts":"2026-08-01T01:01:00Z","verdict":"ALARM","sessions":41,"swap_used_mb":900}\n' >> "$CC_CAP_LOG"
  run bash "$FLOOR" --json
  [ "$status" -eq 3 ] || { echo "expected INSUFFICIENT-DATA (no pool series): $status $output"; false; }
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["machine_floor_sessions"] == 20, d
assert d["machine_peak_observed"] == 41, d
print("OK")' || { echo "$output"; false; }
}

@test "floor: an unhealthy sample cannot raise the floor" {
  # The whole point of a floor: a 60-session sample taken while the box was ALARMing and swapping
  # is evidence against, not for.
  : > "$CC_CAP_LOG"
  for i in $(seq 1 12); do
    printf '{"ts":"2026-08-01T00:%02d:00Z","verdict":"ALARM","sessions":60,"swap_used_mb":2000}\n' "$i" >> "$CC_CAP_LOG"
  done
  run bash "$FLOOR" --json
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["machine_floor_sessions"] == 0, d
assert d["machine_peak_observed"] == 60, d
print("OK")' || { echo "$output"; false; }
}

@test "floor: a pool series too SHORT yields INSUFFICIENT-DATA, never a number with a caveat" {
  # A floor published from four days would be quoted for months after the caveat was lost.
  : > "$CC_CAP_LOG"
  for i in $(seq 1 12); do
    printf '{"ts":"2026-08-01T00:%02d:00Z","verdict":"OK","sessions":25,"swap_used_mb":0}\n' "$i" >> "$CC_CAP_LOG"
  done
  : > "$CC_UTIL_LOG"
  printf '{"ts":"2026-08-01T00:00:00+00:00","acct":"next","k":5,"weekly_pct":10,"stale":false}\n' >> "$CC_UTIL_LOG"
  printf '{"ts":"2026-08-01T06:00:00+00:00","acct":"next","k":9,"weekly_pct":11,"stale":false}\n' >> "$CC_UTIL_LOG"
  run bash "$FLOOR" --json
  [ "$status" -eq 3 ] || { echo "6h of data must not produce a verdict: $output"; false; }
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["pool_floor"] is None, d
assert d["verdict"] == "INSUFFICIENT-DATA", d
print("OK")' || { echo "$output"; false; }
}

@test "floor: with a full weekly span the pool floor computes, and excludes stale + saturated rows" {
  : > "$CC_CAP_LOG"
  for i in $(seq 1 12); do
    printf '{"ts":"2026-08-01T00:%02d:00Z","verdict":"OK","sessions":25,"swap_used_mb":0}\n' "$i" >> "$CC_CAP_LOG"
  done
  : > "$CC_UTIL_LOG"
  printf '{"ts":"2026-08-01T00:00:00+00:00","acct":"next","k":5,"weekly_pct":10,"stale":false}\n' >> "$CC_UTIL_LOG"
  # a bigger k, but the weekly window was SATURATED — not evidence the pool sustains it
  printf '{"ts":"2026-08-05T00:00:00+00:00","acct":"next","k":99,"weekly_pct":100,"stale":false}\n' >> "$CC_UTIL_LOG"
  # a bigger k, but the row is INHERITED — not a measurement
  printf '{"ts":"2026-08-06T00:00:00+00:00","acct":"next","k":50,"weekly_pct":20,"stale":true}\n' >> "$CC_UTIL_LOG"
  printf '{"ts":"2026-08-09T00:00:00+00:00","acct":"next","k":8,"weekly_pct":30,"stale":false}\n' >> "$CC_UTIL_LOG"
  printf '{"ts":"2026-08-09T00:00:00+00:00","acct":"next3","k":6,"weekly_pct":40,"stale":false}\n' >> "$CC_UTIL_LOG"
  run bash "$FLOOR" --json
  [ "$status" -eq 0 ] || { echo "a full span should produce a verdict: $output"; false; }
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["pool_floor"]["per_account"] == {"next": 8, "next3": 6}, d["pool_floor"]
assert d["pool_floor"]["total"] == 14, d["pool_floor"]
print("OK")' || { echo "$output"; false; }
}

@test "floor: it reads the REAL stores and produces a real machine floor on this box" {
  # The suite above proves the arithmetic on fixtures; this proves the thing actually answers on
  # the box's own data, which is the claim the plan record quotes.
  run env -u CC_CAP_LOG -u CC_UTIL_LOG HOME="$REAL_HOME" bash "$FLOOR" --json
  [ "$status" -eq 0 ] || [ "$status" -eq 3 ] || { echo "unexpected status $status: $output"; false; }
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["machine_samples"] > 1000, d["machine_samples"]
assert d["machine_floor_sessions"] > 0, d
print("OK")' || { echo "$output"; false; }
}
