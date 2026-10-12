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
# ---- the local-pass world: a fake keychain, a fake census, a seeded cache ----------------------
KCDB = os.path.join(os.environ["T"], "login.keychain-db")
os.environ["CC_ACCOUNTS_KEYCHAIN_DB"] = KCDB
open(KCDB, "a").close()
def creds(rt="rt-1", at="at-1", exp=9e12):
    return {"accessToken": at, "refreshToken": rt, "expiresAt": exp, "refreshTokenExpiresAt": 9e12}
KC = {"next3": {"cdat": "20261011000000Z", "mdat": "20261011000000Z", "creds": creds()},
      "next4": {"cdat": "20261011000000Z", "mdat": "20261011000000Z", "creds": creds("rt-4", "at-4")}}
KCALLS = {"attrs": 0, "secret": 0}
def kc_world():
    svc = {ca.keychain_service(a["config_dir"]): a["name"] for a in cfg["accounts"]}
    byd = {a["config_dir"]: a["name"] for a in cfg["accounts"]}
    def attrs(s, k):
        KCALLS["attrs"] += 1
        it = KC[svc[s]]
        return ("absent", None) if it is None else ("present", {"cdat": it["cdat"], "mdat": it["mdat"]})
    def secret(d, k):
        KCALLS["secret"] += 1
        it = KC[byd[d]]
        return (None, "no-keychain-item") if it is None else (dict(it["creds"]), "present")
    ca._kc_attrs, ca.read_creds = attrs, secret
NAT = {"next3": 3, "next4": 1}
def nat_world():
    def n(c):
        x = ca._Census(dict(NAT), headless={}, live_sids={}, unknown={}, attributed=set())
        x.as_of = time.time()
        x.meta = {"as_of": x.as_of, "ms": 5, "cpu_ms": 2, "reason": None, "tty_pop": 9, "reads": 2}
        ca._NATIVE_META = x.meta
        return x
    ca.native_census = n
def kc_moved(item=None, **kv):
    if item:
        KC[item].update(kv)
    st = os.stat(KCDB)
    os.utime(KCDB, ns=(st.st_atime_ns, st.st_mtime_ns + 1_000_000_000))
def okrow(name, **kv):
    r = {"acct": name, "auth": "ok", "k": 1, "k_as_of": time.time() - 100, "session_pct": 10,
         "session_reset_h": 3.0, "session_reset_at": iso(3 * 3600), "weekly_pct": 40,
         "weekly_reset_h": 72.0, "weekly_reset_at": iso(3 * 86400), "fable_pct": 5,
         "fable_reset_h": 72.0, "fable_reset_at": iso(3 * 86400), "credits_on": False,
         "rt_fp": ca._rt_fingerprint("rt-4" if name == "next4" else "rt-1"),
         "auth_as_of": time.time() - 120, "quota_read_at": time.time() - 120}
    r.update(kv)
    return r
def seed(rows, age=120, no_heal=False):
    c = {"ts": time.time() - age, "cfg_key": ca._cfg_key(cfg), "no_heal": no_heal,
         "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
         "prev": {"ts": time.time() - 400, "rows": {}}, "rows": rows}
    json.dump(c, open(cfg["cache_file"], "w"))
    return c
def cache():
    return json.load(open(cfg["cache_file"]))
def row_of(name):
    return next(r for r in cache()["rows"] if r["acct"] == name)
def overlay():
    return json.load(open(ca.local_overlay_path(cfg)))
def run_pass():
    import io, contextlib
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ca.local_refresh(cfg)
    return buf.getvalue()
def world():
    os.environ["CC_ACCOUNTS_CENSUS"] = "ab"
    kc_world(); nat_world(); stub_net(200)
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
  [[ "$output" == *OK* ]] || false
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

# ---- W3: the local overlay, --local-refresh and the first read (D5-D7) ----------------------------

@test "no network on a quiet pass; ts/window/prev/no_heal/cfg_key byte-identical; keepwarm still sweeps (with the ts-bump mutant)" {
  run python3 -c "$LOAD"'
world()
c0 = seed([okrow("next3"), okrow("next4")])
out = run_pass()
out += run_pass()
assert CALLS == {"usage": 0, "wire": 0}, CALLS
c1 = cache()
for k in ("ts", "window", "prev", "no_heal", "cfg_key"):
    assert json.dumps(c1[k]) == json.dumps(c0[k]), k
assert [r["k_native"] for r in c1["rows"]] == [3, 1] and all(r["k"] == 1 for r in c1["rows"])
# keepwarm --max-age 90 on a cache older than 90 s must still SWEEP: the pass did not re-date it
ca.collect = lambda c, no_heal=False, prev=None: [okrow("next3"), okrow("next4")]
ca.record_utilization = lambda rows: 0
_, _, cached, _ = ca.get_data(cfg, max_age=90)
assert cached is False, "keepwarm would log served-cache"
# MUTANT: a pass that bumps ts makes keepwarm serve the cache — the silence C5 forbids
src = open(os.environ["CA_BIN"]).read()
needle = "        blob = json.dumps(c)\n        try:\n            st2 = os.stat(path)"
assert src.count(needle) == 1
mut = importlib.util.module_from_spec(importlib.util.spec_from_loader("mut", loader=None))
exec(compile(src.replace(needle, "        c[\"ts\"] = time.time()\n" + needle), "mut", "exec"), mut.__dict__)
ca = mut
cfg = ca.load_cfg(need_claude_bin=False)
world()
seed([okrow("next3"), okrow("next4")])
NAT["next3"] = 4                      # a census change forces the pass to write
run_pass()
ca.collect = lambda c, no_heal=False, prev=None: [okrow("next3"), okrow("next4")]
ca.record_utilization = lambda rows: 0
_, _, cached, _ = ca.get_data(cfg, max_age=90)
assert cached is True, "the mutant should have silenced keepwarm"
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "simulated login: ONE pass flips logged-out -> pending -> routable via one usage GET, 0 wire" {
  run python3 -c "$LOAD"'
world()
KC["next3"] = None
seed([okrow("next3", auth="logged-out", error="logged-out", stale_quota=True,
            quota_as_of=iso(-3600), rt_fp=None), okrow("next4")])
run_pass()
assert row_of("next3")["auth"] == "logged-out"
# the /login: the item reappears with a NEW grant. First reads off: the row must be PENDING.
KC["next3"] = {"cdat": "20261011223324Z", "mdat": "20261011223324Z", "creds": creds("rt-new", "at-new")}
kc_moved()
os.environ["CC_ACCOUNTS_FIRST_READ"] = "off"
out = run_pass()
r = row_of("next3")
assert "local: T2 next3" in out, out
assert ca.PENDING_RE.match(r["error"]) and r["auth"] == "ok", r
assert r["rt_fp"] == ca._rt_fingerprint("rt-new") and r.get("stale_quota") is True, r
assert ca._excluded(r, cfg["router"]) is not None
assert CALLS["usage"] == 0
# first reads on: the next pass reads quota once and the row routes
del os.environ["CC_ACCOUNTS_FIRST_READ"]
stub_net(200, limits(weekly=12))
out = run_pass()
r = row_of("next3")
assert "local: first-read next3 200" in out, out
assert "error" not in r and r["weekly_pct"] == 12 and r["quota_src"] == "first-read", r
assert ca._excluded(r, cfg["router"]) is None, ca._excluded(r, cfg["router"])
assert CALLS == {"usage": 1, "wire": 0}, CALLS
led = json.load(open(os.environ["CA_LEDGER"]))["next3"]
fr = overlay()["first_read"]["next3"]
assert abs(ca._as_epoch(led["quota_as_of"]) - fr["read_at"]) < 1e-3, (led, fr)
assert r["quota_read_at"] == fr["read_at"]
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "simulated login with first reads on: logged-out to routable inside ONE pass" {
  run python3 -c "$LOAD"'
world()
seed([okrow("next3", auth="logged-out", error="logged-out", stale_quota=True,
            quota_as_of=iso(-3600), rt_fp=None, auth_as_of=time.time() - 300), okrow("next4")])
KC["next3"]["creds"] = creds("rt-new", "at-new")
out = run_pass()
r = row_of("next3")
assert "local: T2 next3" in out and "local: first-read next3 200" in out, out
assert "error" not in r and ca._excluded(r, cfg["router"]) is None, r
assert CALLS == {"usage": 1, "wire": 0}, CALLS
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "T1 logout: one pass makes the row logged-out and excluded, even on a no_heal payload a cache-only read serves" {
  run python3 -c "$LOAD"'
world()
seed([okrow("next3"), okrow("next4")], no_heal=True)
run_pass()
KC["next3"] = None
kc_moved()
out = run_pass()
r = row_of("next3")
assert "local: T1 next3" in out, out
assert r["auth"] == "logged-out" and r["error"] == "logged-out" and r["stale_quota"] is True, r
assert abs(ca._as_epoch(r["quota_as_of"]) - r["quota_read_at"]) < 1, r      # dated by its REAL read
assert ca._excluded(r, cfg["router"]) is not None
rows, _, cached, _ = ca.get_data(cfg, max_wait=0, max_age=600)
assert cached and rows[0]["auth"] == "logged-out"
assert CALLS == {"usage": 0, "wire": 0}
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "rule table: T2 needs a NEW grant from token-invalid; T4 refreshes login_*; error rows never recover; T2 clears poll_throttled" {
  run python3 -c "$LOAD"'
now = time.time()
fp1, fp2 = ca._rt_fingerprint("rt-1"), ca._rt_fingerprint("rt-2")
def ov(**au):
    return {"auth": {"next3": dict({"as_of": now, "kstate": "present", "verdict": "ok", "rt_fp": fp1}, **au)}}
r = {"acct": "next3", "auth": "token-invalid", "error": "token-invalid", "rt_fp": fp1, "auth_as_of": now - 50}
assert ca.apply_local_overlay([r], ov(), now - 60, "local") == [] and r["auth"] == "token-invalid"
r = {"acct": "next3", "auth": "token-invalid", "error": "x", "rt_fp": fp1, "auth_as_of": now - 50, "poll_throttled": True}
assert ca.apply_local_overlay([r], ov(rt_fp=fp2), now - 60, "local") == [("next3", "T2")]
assert ca.PENDING_RE.match(r["error"]) and "poll_throttled" not in r and r["auth_actionable"] is False, r
r = {"acct": "next3", "auth": "ok", "rt_fp": fp1, "auth_as_of": now - 50, "login_expires_at": "old"}
assert ca.apply_local_overlay([r], ov(rt_fp=fp2, login_expires_at=iso(86400)), now - 60, "local") == [("next3", "T4")]
assert r["rt_fp"] == fp2 and r["login_expires_at"] != "old" and r["login_expires_h"] > 20, r
for bad in ("keychain-error", "probe-error"):
    r = {"acct": "next3", "auth": bad, "error": bad, "auth_as_of": now - 50}
    assert ca.apply_local_overlay([r], ov(rt_fp=fp2), now - 60, "local") == [] and r["auth"] == bad
# an overlay OLDER than the row read changes nothing (a newer sweep stamp wins)
r = {"acct": "next3", "auth": "logged-out", "error": "logged-out", "auth_as_of": now + 5}
assert ca.apply_local_overlay([r], ov(rt_fp=fp2), now - 60, "local") == []
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "rule (f): local writer only, pending marker only, read_at >= payload ts; re-derives countdowns (with its mutant)" {
  run python3 -c "$LOAD"'
now = time.time()
fp = ca._rt_fingerprint("rt-1")
fields = {"weekly_pct": 9, "weekly_reset_at": iso(2 * 86400), "session_pct": 1, "session_reset_at": iso(3600)}
ovl = {"first_read": {"next3": {"read_at": now - 10, "rt_fp": fp, "fields": fields}}}
def pend(**kv):
    r = {"acct": "next3", "auth": "ok", "rt_fp": fp, "error": ca._pending_marker(now - 30),
         "stale_quota": True, "quota_as_of": iso(-3600), "weekly_reset_h": 0.5,
         "rolled_since": ["weekly"], "reset_evidence": ["x"], "lastgood_age_s": 3600,
         "lastgood_wire_rejects": ["7d"], "wire": {"7d_status": "rejected"}}
    r.update(kv)
    return r
def apply(mod, r, ts, writer):
    return mod.apply_local_overlay([r], ovl, ts, writer)
r = pend()
assert apply(ca, r, now - 60, "sweep") == [] and ca.PENDING_RE.match(r["error"])   # never in cache_commit
r = pend(error="poll throttled ↻ (cached usage)", poll_throttled=True)
assert apply(ca, r, now - 60, "local") == [] and r["poll_throttled"]                # never without the marker
r = pend()
assert apply(ca, r, now - 5, "local") == []                                          # read_at < payload ts
r = pend()
assert apply(ca, r, now - 60, "local") == [("next3", "first-read")]
assert "error" not in r and "stale_quota" not in r and "quota_as_of" not in r and "lastgood_age_s" not in r, r
assert r["weekly_pct"] == 9 and r["weekly_reset_h"] > 40 and "rolled_since" not in r, r
assert r["lastgood_wire_rejects"] == ["7d"] and r["wire"] == {"7d_status": "rejected"}, r
# MUTANT: drop the marker restriction and a 429-throttled row is laundered as fresh
src = open(os.environ["CA_BIN"]).read()
needle = "PENDING_RE.match(str(r.get(\"error\") or \"\"))\n                and fr.get(\"rt_fp\")"
assert src.count(needle) == 1, src.count(needle)
mut = importlib.util.module_from_spec(importlib.util.spec_from_loader("mut", loader=None))
exec(compile(src.replace(needle, "True\n                and fr.get(\"rt_fp\")"), "mut", "exec"), mut.__dict__)
r = pend(error="poll throttled ↻ (cached usage)", poll_throttled=True)
assert apply(mut, r, now - 60, "local") == [("next3", "first-read")], "mutant should launder"
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "lost updates: an older sweep keeps the recovery and census through cache_commit; the local CAS aborts; the single-flight lock never blocks a pass" {
  run python3 -c "$LOAD"'
world()
seed([okrow("next3", auth="logged-out", error="logged-out", rt_fp=None, auth_as_of=time.time() - 300),
      okrow("next4")])
os.environ["CC_ACCOUNTS_FIRST_READ"] = "off"
fd = os.open(cfg["cache_file"] + ".lock", os.O_RDWR | os.O_CREAT)
fcntl.flock(fd, fcntl.LOCK_EX)                         # a sweep in flight holds single-flight
t0 = time.monotonic()
run_pass()
assert time.monotonic() - t0 < 5 and ca.PENDING_RE.match(row_of("next3")["error"])
# that sweep read the keychain BEFORE the login and commits now: the overlay re-applies
stale = okrow("next3", auth="logged-out", error="logged-out", rt_fp=None, auth_as_of=time.time() - 200)
ca.cache_commit(cfg, {"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
                      "window": {}, "prev": None, "rows": [stale, okrow("next4", k_native=None)]})
c = cache()
assert ca.PENDING_RE.match(c["rows"][0]["error"]) and c["rows"][1]["k_native"] == 1, c["rows"]
assert stale["auth"] == "logged-out"                   # the caller keeps its own measurement
# a sweep that read AFTER the overlay wins
newer = okrow("next3", auth="logged-out", error="logged-out", auth_as_of=time.time() + 1)
ca.cache_commit(cfg, {"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
                      "window": {}, "prev": None, "rows": [newer, okrow("next4")]})
assert row_of("next3")["error"] == "logged-out"
# CAS: a writer that ignores the wlock replaces the file mid-pass -> the pass aborts its write
real = ca.apply_local_overlay
def racing(rows, ov, ts, writer):
    out = real(rows, ov, ts, writer)
    if writer == "local" and rows is not None:
        c = cache(); c["rows"][1]["weekly_pct"] = 77
        tmp = cfg["cache_file"] + ".x"; json.dump(c, open(tmp, "w")); os.replace(tmp, cfg["cache_file"])
    return out
ca.apply_local_overlay = racing
NAT["next4"] = 5
assert ca._local_commit(cfg, overlay()) is None and "CAS abort" in log()
assert row_of("next4")["weekly_pct"] == 77
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "first-read guards: a timeout then a pass within 90 s, a stale verdict, a held poll lock, first-read-off: 0 calls" {
  run python3 -c "$LOAD"'
world()
def login(rt, exp=9e12):
    KC["next3"]["creds"] = creds(rt, "at-" + rt, exp=exp)
    KC["next3"]["mdat"] = "2026101123%04dZ" % (len(rt) * 100 + ord(rt[-1]) % 60)
    kc_moved()
seed([okrow("next3", auth="logged-out", error="logged-out", rt_fp=None, auth_as_of=time.time() - 300), okrow("next4")])
stub_net(None)                                          # a timeout / URLError
login("rt-a")
assert "local: first-read next3 None" in run_pass() and CALLS["usage"] == 1
run_pass()
assert CALLS["usage"] == 1                              # memo: next attempt >= 90 s later
assert ca.PENDING_RE.match(row_of("next3")["error"])
# stale: an expired access token would 401 — left to the sweep heal
seed([okrow("next3", auth="logged-out", error="logged-out", rt_fp=None, auth_as_of=time.time() - 300), okrow("next4")])
login("rt-b", exp=0)
run_pass()
assert row_of("next3")["auth"] == "stale" and CALLS["usage"] == 1
# held poll lock (a sweep is polling this token right now): stays pending, 0 calls
seed([okrow("next3", auth="logged-out", error="logged-out", rt_fp=None, auth_as_of=time.time() - 300), okrow("next4")])
login("rt-c")
fd = os.open(ca._poll_lock_path(cfg, "next3"), os.O_RDWR | os.O_CREAT)
fcntl.flock(fd, fcntl.LOCK_EX)
run_pass()
assert CALLS["usage"] == 1 and ca.PENDING_RE.match(row_of("next3")["error"])
fcntl.flock(fd, fcntl.LOCK_UN)
open(os.path.join(os.environ["CC_ACCOUNTS_LOCAL_DIR"], "first-read-off"), "w").close()
login("rt-d")
run_pass()
assert CALLS["usage"] == 1
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "sweep reuse guard: a first read <= 90 s old on this grant is reused (no fetch, stale sample); at 91 s or another grant the sweep polls" {
  run python3 -c "$LOAD"'
fp = ca._rt_fingerprint("rt-1")
fields = {"weekly_pct": 21, "weekly_reset_at": iso(86400), "session_pct": 3, "session_reset_at": iso(3600)}
ca.read_creds = lambda d, k: (creds(), "present")
stub_net(200)
for age, rt_fp, polls in ((30, fp, 0), (91, fp, 1), (30, "other", 1)):
    CALLS["usage"] = 0
    ra = time.time() - age
    row, entry = ca.probe_account(cfg, acct(), "test", 0, {}, None, True,
                                  first_reads={"next3": {"read_at": ra, "rt_fp": rt_fp, "fields": fields}})
    assert CALLS["usage"] == polls, (age, rt_fp, CALLS)
    if polls == 0:
        assert row["quota_reused"] and row["quota_read_at"] == ra and row["weekly_pct"] == 21, row
        assert abs(ca._as_epoch(entry["quota_as_of"]) - ra) < 1e-3, entry
        p = os.environ["CC_UTIL_LOG"]
        ca.record_utilization([row], path=p, min_interval_s=0)
        assert json.loads(open(p).read().splitlines()[-1])["stale"] is True
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "keychain stall: the census still lands in the overlay and the cache; the stalled item is re-read next pass" {
  run python3 -c "$LOAD"'
world()
seed([okrow("next3"), okrow("next4")])
ca.LOCAL_KC_DEADLINE_S = 0.3
fast = ca._kc_attrs
def slow(s, k):
    time.sleep(2)
    return fast(s, k)
ca._kc_attrs = slow
t0 = time.monotonic()
out = run_pass()
assert time.monotonic() - t0 < 2, time.monotonic() - t0
assert "local: keychain" in out and "timeout" in out, out
assert overlay()["census"]["counts"] == NAT and row_of("next3")["k_native"] == 3
ca._kc_attrs = fast
n0 = KCALLS["attrs"]
run_pass()
assert KCALLS["attrs"] > n0                           # no 300 s reuse after a failed read
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "kill switches: off prints local: disabled and touches the stamp; a held pass prints local: busy and touches it" {
  CC_ACCOUNTS_LOCAL=off run "$CA_BIN" --local-refresh
  [ "$status" -eq 0 ] && [ "$output" = "local: disabled" ] || false
  [ -f "$CC_ACCOUNTS_LOCAL_STAMP" ]
  rm -f "$CC_ACCOUNTS_LOCAL_STAMP"
  touch "$CC_ACCOUNTS_LOCAL_DIR/off"
  run "$CA_BIN" --local-refresh
  [ "$output" = "local: disabled" ] && [ -f "$CC_ACCOUNTS_LOCAL_STAMP" ] || false
  rm -f "$CC_ACCOUNTS_LOCAL_DIR/off" "$CC_ACCOUNTS_LOCAL_STAMP"
  python3 -c 'import fcntl,os,sys,time; fd=os.open(sys.argv[1], os.O_RDWR|os.O_CREAT); fcntl.flock(fd, fcntl.LOCK_EX); time.sleep(20)' "$CACHE.local.lock" &
  holder=$!
  sleep 1
  run "$CA_BIN" --local-refresh
  kill "$holder" 2>/dev/null || true
  [ "$output" = "local: busy" ] || { echo "$output"; false; }
  [ -f "$CC_ACCOUNTS_LOCAL_STAMP" ]
}

# ---- W4: the board (D8) ---------------------------------------------------------------------------

@test "board: a local render keeps the mtime and never creates a board; sig gates; clock-only footer; render-time fields stay out of the cache" {
  run python3 -c "$LOAD"'
import re
world()
os.environ["CC_ACCOUNTS_FIRST_READ"] = "off"
os.getloadavg = lambda: (0.0, 0.0, 0.0)
seed([okrow("next3"), okrow("next4")])
bp = ca.board_path(cfg)
run_pass()
assert not os.path.exists(bp)                                   # never creates a board
open(bp, "w").write("keepwarm board\n")
os.utime(bp, (1000, 1000))
out = run_pass()
assert "local: board re-rendered (auth)" in out, out           # no meta yet: re-render at once
assert os.stat(bp).st_mtime == 1000                             # the producer-liveness signal kept
txt = open(bp).read()
assert re.search(r"^auth/live \d\d:\d\d:\d\d · quota \d\d:\d\d:\d\d$", re.sub(r"\x1b\[[0-9;]*m", "", txt), re.M), txt
assert not any(k == "k_phantom" or k.startswith("burn_") for r in cache()["rows"] for k in r)
assert "board" not in run_pass()                                # same signature: no render
# a cc-relogin-style write flips auth: re-render at once
rows = cache()["rows"]
rows[1].update(auth="token-invalid", error="token-invalid", auth_as_of=time.time() + 1)
ca.cache_commit(cfg, dict(cache(), ts=time.time(), rows=rows))
assert "local: board re-rendered (auth)" in run_pass()
# a live-count-only change: once, then not again inside 60 s; never under load
def chk(want, absent=False):
    out = run_pass()
    meta = json.load(open(bp + ".meta.json"))
    assert (want not in out) if absent else (want in out), (want, out, meta["sig"], ca._board_sig(cache()["rows"]))
NAT["next3"] = 7
chk("local: board re-rendered (live counts)")
NAT["next3"] = 8
chk("board", absent=True)
ca.LOCAL_K_RENDER_MIN_S = 0
os.getloadavg = lambda: (1e6, 1e6, 1e6)
NAT["next3"] = 9
chk("board", absent=True)
os.getloadavg = lambda: (0.0, 0.0, 0.0)
chk("local: board re-rendered (live counts)")
assert os.stat(bp).st_mtime == 1000, os.stat(bp).st_mtime
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "board: a simulated login shows the pending note in ONE pass, and keepwarm keeps it (renders the committed, overlay-merged rows)" {
  run python3 -c "$LOAD"'
import io, contextlib
world()
os.environ["CC_ACCOUNTS_FIRST_READ"] = "off"
os.getloadavg = lambda: (0.0, 0.0, 0.0)
seed([okrow("next3", auth="logged-out", error="logged-out", rt_fp=None, auth_as_of=time.time() - 300), okrow("next4")])
bp = ca.board_path(cfg)
open(bp, "w").write("old\n")
KC["next3"]["creds"] = creds("rt-new", "at-new")
out = run_pass()
assert "local: T2 next3" in out and "local: board re-rendered (auth)" in out, out
txt = open(bp).read()
assert "logged in " in txt and "quota read pending, excluded from routing" in txt, txt
# keepwarm sweeps a cache older than 90 s with a sweep that did NOT see the login
stale = [okrow("next3", auth="logged-out", error="logged-out", rt_fp=None, auth_as_of=time.time() - 200),
         okrow("next4")]
ca.collect = lambda c, no_heal=False, prev=None: json.loads(json.dumps(stale))
ca.record_utilization = lambda rows: 0
os.environ["CC_KEEPWARM_DEADLINE_S"] = "0"
sys.argv = ["claude-accounts", "--keepwarm", "--max-age", "90"]
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ca.main()
assert "keepwarm: swept" in buf.getvalue(), buf.getvalue()
txt = open(bp).read()
assert "quota read pending" in txt, txt                         # the recovery survived the sweep
meta = json.load(open(bp + ".meta.json"))
assert meta["producer"] == "keepwarm" and meta["rendered_from_ts"] == cache()["ts"], meta
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}
