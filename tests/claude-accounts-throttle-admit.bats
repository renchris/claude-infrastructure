#!/usr/bin/env bats
# claude-accounts — routing through a transient 429 on the last-good read (backlog 1c20dc1e92db).
#
# A 429 from /api/oauth/usage is a POLL THROTTLE, never a cap, yet `_excluded` returned the row's
# `error` first and dropped an account holding a seconds-old good read. Measured over 1,643 throttle
# events (docs/research/quota-429-drift-2026-09-30/): p90 drift 2pp when the last good read is ≤ the
# 90 s cache TTL old, under the 5pp admission rule. So such a row routes on its inherited percents —
# and only such a row: an older read, or one whose last good sweep carried a REJECTED wire verdict,
# stays excluded exactly as before.
#
# Hermetic: same scratch SSOT/ledger/cache harness as claude-accounts-wire-truth.bats; the usage
# endpoint and the wire are stubbed, so nothing here touches the network.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_SSOT="$REPO/accounts.json"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CA_LEDGER="$BATS_TEST_TMPDIR/lastgood.json"
  export CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$CA_LEDGER"
  export YAML="$BATS_TEST_TMPDIR/model-config.yaml"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
  export CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
  export CC_ROUTE_RECORDS_DIR="$BATS_TEST_TMPDIR/route-records"
  unset CLAUDE_ACCOUNTS_THROTTLE_ADMIT_S
  rm -f "$CA_LEDGER" "$CACHE"
  python3 - "$CA_CFG" "$CACHE" "$CA_SSOT" "$YAML" <<'PY'
import json, sys
cfg_path, cache, real, yaml = sys.argv[1:5]
r = json.load(open(real))
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "messages_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": yaml, "dia_local_state": "/nonexistent/LS",
  "cache_file": cache,
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [{"name": "next3", "config_dir": "/tmp/ca-test-nonexistent-xyz",
                "launcher": "claude3",
                "email": "test@example.com", "mailbox": "test@example.com", "dia_profile": "T"}],
}, open(cfg_path, "w"))
PY
}

LOAD='
import importlib.machinery, importlib.util, os, json
from datetime import datetime, timedelta, timezone
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
cfg = json.load(open(os.environ["CA_CFG"]))
R = cfg["router"]
SCOPED = cfg["frontier"]["scoped_display_name"]
def limits(session=5, weekly=30, fable=7):
    return [{"kind": "session", "percent": session, "resets_at": None},
            {"kind": "weekly_all", "percent": weekly, "resets_at": None},
            {"kind": "weekly_scoped", "percent": fable, "resets_at": None,
             "scope": {"model": {"display_name": SCOPED}}}]
def probe(status, lim=None, wire=None):
    """One collect() with the usage endpoint answering `status` and the wire stubbed to `wire`."""
    ca.concurrency = lambda c: {"next3": 0}
    ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 9e12}, "present")
    ca.fetch_usage = lambda *a, **k: (status, {"limits": lim} if lim is not None else None)
    ca.fetch_wire_limits = lambda *a, **k: wire
    return ca.collect(cfg, no_heal=True)[0]
def age_ledger(seconds):
    led = json.load(open(os.environ["CA_LEDGER"]))
    led["next3"]["quota_as_of"] = (datetime.now(timezone.utc)
                                   - timedelta(seconds=seconds)).isoformat()
    json.dump(led, open(os.environ["CA_LEDGER"], "w"))
def admitted_lines():
    try:
        return [l for l in open(ca.LOG_PATH) if "throttle-admitted" in l]
    except OSError:
        return []
'

@test "TA-1: throttled + fresh last-good + uncapped => routable on the inherited percents, logged once" {
  run python3 -c "$LOAD"'
good = probe(200, limits(weekly=30))
assert "error" not in good and ca._excluded(good, R) is None, good
r = probe(429)
assert r.get("poll_throttled") and r.get("stale_quota"), r
assert r["error"].startswith("poll throttled"), "the row still SAYS it was throttled (render glyph)"
assert r["weekly_pct"] == 30 and r["lastgood_age_s"] is not None and r["lastgood_age_s"] < 90, r
assert ca._excluded(r, R) is None, ca._excluded(r, R)
score, reason = ca.score_general(r, cfg)
assert reason is None and score > 0, (score, reason)
ca._excluded(r, R)                      # a second scoring call must not log a second line
assert len(admitted_lines()) == 1, admitted_lines()
# the board must not call an admitted row "excluded from routing", and must still mark it ↻
import io, contextlib
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ca.render_table([r], cfg, {"active": True, "end": "2099-12-31", "deadline": None,
                               "permanent": True}, False, None)
out = buf.getvalue()
assert "routed on it" in out and "excluded from routing" not in out and "↻" in out, out
assert len(admitted_lines()) == 1, "rendering must not log a route admission"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "TA-2: throttled + wire 7d rejected => excluded (from the row, and from the last good sweep)" {
  run python3 -c "$LOAD"'
# (a) a wire verdict ON the row still vetoes after admission
r = probe(200, limits(weekly=30))
r = probe(429)
r["wire"] = {"7d_status": "rejected", "7d_util": 1.0}
assert ca._excluded(r, R) == "weekly-exhausted", ca._excluded(r, R)
# (b) the last GOOD sweep was wire-rejected: the ledger carries that verdict, and it blocks
# admission, so the row keeps its throttle error exactly as before this change
os.remove(os.environ["CA_LEDGER"])
os.remove(ca.LOG_PATH)                  # (a) was admitted, then vetoed by the wire — fresh log
ca._THROTTLE_ADMIT_LOGGED.clear()
ca.WIRE_FORCE = True
g = probe(200, limits(weekly=97),
          {"7d_util": 1.0, "7d_status": "rejected", "5h_util": 0.1, "5h_status": "allowed",
           "status": "rejected", "http": 429})
assert ca._excluded(g, R) == "weekly-exhausted", ca._excluded(g, R)
assert json.load(open(os.environ["CA_LEDGER"]))["next3"].get("wire_rejects") == ["7d"]
ca.WIRE_FORCE = False
r = probe(429)
assert r.get("lastgood_wire_rejects") == ["7d"], r
assert (ca._excluded(r, R) or "").startswith("poll throttled"), ca._excluded(r, R)
assert not admitted_lines(), admitted_lines()
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "TA-3: throttled + last-good older than the bound => excluded; the knob moves the bound, 0 disables" {
  run python3 -c "$LOAD"'
probe(200, limits(weekly=30))
age_ledger(200)
r = probe(429)
assert r["lastgood_age_s"] >= 199, r
assert (ca._excluded(r, R) or "").startswith("poll throttled"), ca._excluded(r, R)
os.environ["CLAUDE_ACCOUNTS_THROTTLE_ADMIT_S"] = "300"
assert ca._excluded(r, R) is None, ca._excluded(r, R)
os.environ["CLAUDE_ACCOUNTS_THROTTLE_ADMIT_S"] = "0"
age_ledger(5)
r = probe(429)
assert (ca._excluded(r, R) or "").startswith("poll throttled"), "0 must restore the old exclusion"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
