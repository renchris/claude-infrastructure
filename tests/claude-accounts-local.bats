#!/usr/bin/env bats
# claude-accounts — the local pass (`--local-refresh`), its overlay, and the write coordination
# that lets it share the cache with the sweep. docs/plans/ACCOUNTS_BOARD_FRESHNESS.md D3-D8.
#
# THE INCIDENT (2026-10-11 22:33Z). next3's /login created its keychain item at 22:33:24, but auth
# and live counts refreshed only on a full network sweep (keepwarm every 180 s, each sweep 20-527 s),
# so the board said logged-out and the router routed around it for minutes. The local pass reads
# the keychain's ATTRIBUTES every 20 s and folds what changed into the cache — without ever bumping
# `ts` (which would silence keepwarm), without a model token, and without routing on old quota.
#
# Hermetic: scratch SSOT, cache, ledger, logs, local dir and board under BATS_TEST_TMPDIR. Every
# network and keychain function is monkeypatched (fetch_usage, fetch_wire_limits, _kc_attrs,
# read_creds, native_census); nothing here touches the real keychain, the endpoint or /tmp.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  mkdir -p "$HOME/.claude/logs" "$T/local"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_SSOT="$REPO/accounts.json"
  export CA_CFG="$T/accounts.json"
  export CA_LEDGER="$T/lastgood.json"
  export CACHE="$T/claude-accounts-cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$CA_LEDGER"
  export CLAUDE_ACCOUNTS_LOG="$T/claude-accounts.log"
  export CC_UTIL_LOG="$T/util-series.jsonl"
  export CC_ASSIGN_LOG="$T/assign-ledger.jsonl"
  export CC_ROUTE_RECORDS_DIR="$T/route-records"
  export CC_ACCOUNTS_LOCAL_DIR="$T/local"
  export CC_ACCOUNTS_LOCAL_STAMP="$T/accounts-local.stamp"
  unset CC_ACCOUNTS_CENSUS CC_ACCOUNTS_LOCAL CC_ACCOUNTS_FIRST_READ CC_ACCOUNTS_BOARD
  unset CLAUDE_ACCOUNTS_THROTTLE_ADMIT_S CC_ACCOUNTS_USAGE_BACKOFF_S CC_ACCOUNTS_REPOLL_MIN_S
  python3 - <<'PY'
import json, os
T, r = os.environ["T"], json.load(open(os.environ["CA_SSOT"]))
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "messages_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": os.path.join(T, "mc.yaml"), "dia_local_state": "/nonexistent/LS",
  "cache_file": os.environ["CACHE"],
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [{"name": "next3", "config_dir": os.path.join(T, "cfg-next3"), "launcher": "claude3"},
               {"name": "next4", "config_dir": os.path.join(T, "cfg-next4"), "launcher": "claude4"}],
}, open(os.environ["CA_CFG"], "w"))
PY
}

LOAD='
import importlib.machinery, importlib.util, os, json, time, threading, fcntl, subprocess, sys
from datetime import datetime, timedelta, timezone
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
cfg = ca.load_cfg(need_claude_bin=False)
SCOPED = cfg["frontier"]["scoped_display_name"]
CALLS = {"usage": 0, "wire": 0}
def iso(dt_s=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=dt_s)).isoformat()
def limits(session=5, weekly=30, fable=7):
    return [{"kind": "session", "percent": session, "resets_at": iso(3 * 3600)},
            {"kind": "weekly_all", "percent": weekly, "resets_at": iso(3 * 86400)},
            {"kind": "weekly_scoped", "percent": fable, "resets_at": iso(3 * 86400),
             "scope": {"model": {"display_name": SCOPED}}}]
def stub_net(status=200, lim=None):
    def fu(*a, **k):
        CALLS["usage"] += 1
        return status, ({"limits": lim if lim is not None else limits()} if status == 200 else None)
    def fw(*a, **k):
        CALLS["wire"] += 1
        return None
    ca.fetch_usage, ca.fetch_wire_limits = fu, fw
CREDS = {"accessToken": "at-1", "refreshToken": "rt-1", "expiresAt": 9e12,
         "refreshTokenExpiresAt": 9e12}
def acct(name="next3"):
    return next(a for a in cfg["accounts"] if a["name"] == name)
def log():
    try:
        return open(os.environ["CLAUDE_ACCOUNTS_LOG"]).read()
    except OSError:
        return ""
'

# ---- W2: provenance stamps and write coordination (D3-D4) -----------------------------------------

@test "D3: probe_account stamps auth_as_of, rt_fp, and quota_read_at on an HTTP-200 read only" {
  run python3 -c "$LOAD"'
ca.read_creds = lambda d, k: (dict(CREDS), "present")
stub_net(200)
t0 = time.time()
row, entry = ca.probe_account(cfg, acct(), "test", 0, {}, None, True)
assert t0 <= row["auth_as_of"] <= row["quota_read_at"] <= time.time(), row
assert row["rt_fp"] == ca._rt_fingerprint("rt-1"), row
assert entry and entry["quota_as_of"], entry
stub_net(429)
row, entry = ca.probe_account(cfg, acct("next4"), "test", 0, {}, None, True)
assert "quota_read_at" not in row and row.get("poll_throttled"), row
ca.read_creds = lambda d, k: (None, "no-keychain-item")
row, _ = ca.probe_account(cfg, acct(), "test", 0, {}, None, True)
assert row["auth"] == "logged-out" and "rt_fp" not in row and row["auth_as_of"] > 0, row
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "D4: save_lastgood MERGES, keeping the newer quota_as_of per account" {
  run python3 -c "$LOAD"'
older, newer = iso(-600), iso(-10)
json.dump({"next3": {"weekly_pct": 50, "quota_as_of": newer},
           "next4": {"weekly_pct": 70, "quota_as_of": older},
           "gone": {"weekly_pct": 1, "quota_as_of": older}}, open(os.environ["CA_LEDGER"], "w"))
# a sweep that loaded the ledger long ago and read next4 fresh, but carries a STALE next3
ca.save_lastgood({"next3": {"weekly_pct": 40, "quota_as_of": older},
                  "next4": {"weekly_pct": 75, "quota_as_of": iso()}})
led = json.load(open(os.environ["CA_LEDGER"]))
assert led["next3"]["weekly_pct"] == 50, led          # the newer first read survives
assert led["next4"]["weekly_pct"] == 75, led          # the newer sweep read wins
assert led["gone"]["weekly_pct"] == 1, led            # an account the caller did not carry stays
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "D4: two processes racing note_usage_429 on different accounts both persist" {
  run python3 -c "$LOAD"'
code = """
import importlib.machinery, importlib.util, os, sys
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca",
     importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
for _ in range(40):
    ca.note_usage_429(sys.argv[1])
"""
ps = [subprocess.Popen([sys.executable, "-c", code, a]) for a in ("next3", "next4")]
assert all(p.wait() == 0 for p in ps)
d = json.load(open(ca._sidecar(".pollstate.json")))
assert d["next3"]["streak"] == 40 and d["next4"]["streak"] == 40, d
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "D4: a held per-account poll lock delays the sweep's fetch at most its bound, never skips it" {
  run python3 -c "$LOAD"'
ca.read_creds = lambda d, k: (dict(CREDS), "present")
stub_net(200)
ca.POLL_LOCK_WAIT_S = 0.4
fd = os.open(ca._poll_lock_path(cfg, "next3"), os.O_RDWR | os.O_CREAT)
fcntl.flock(fd, fcntl.LOCK_EX)
t0 = time.monotonic()
row, _ = ca.probe_account(cfg, acct(), "test", 0, {}, None, True)
assert time.monotonic() - t0 >= 0.4 and CALLS["usage"] == 1 and row.get("weekly_pct") == 30, row
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "D4: a stalled wlock holder delays a sweep commit but never reverts it; a wedge still writes" {
  run python3 -c "$LOAD"'
payload = {"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False, "window": {},
           "prev": None, "rows": [{"acct": "next3", "auth": "ok", "weekly_pct": 10}]}
fd = os.open(ca._wlock_path(cfg), os.O_RDWR | os.O_CREAT)
fcntl.flock(fd, fcntl.LOCK_EX)
threading.Timer(0.3, lambda: fcntl.flock(fd, fcntl.LOCK_UN)).start()
t0 = time.monotonic()
ca.cache_commit(cfg, payload)
assert time.monotonic() - t0 >= 0.3
assert json.load(open(cfg["cache_file"]))["rows"][0]["weekly_pct"] == 10
fcntl.flock(fd, fcntl.LOCK_EX)
ca.CACHE_WLOCK_SWEEP_S = 0.2
payload["rows"][0]["weekly_pct"] = 11
ca.cache_commit(cfg, payload)
assert json.load(open(cfg["cache_file"]))["rows"][0]["weekly_pct"] == 11
assert "wlock wedged" in log()
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "D4: a cache-only reader is served a no_heal cache with errored rows; a healer still is not" {
  run python3 -c "$LOAD"'
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": True,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None, "rows": [{"acct": "next3", "auth": "logged-out", "error": "logged-out"},
                                  {"acct": "next4", "auth": "ok", "weekly_pct": 5}]},
          open(cfg["cache_file"], "w"))
rows, wj, cached, prev = ca.get_data(cfg, max_wait=0, max_age=600)
assert cached and rows[0]["auth"] == "logged-out", rows
assert ca.cache_read(cfg, want_heal=True) is None
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}
