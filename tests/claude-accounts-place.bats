#!/usr/bin/env bats
# claude-accounts --place — batch recovery placement (LIMIT_RECOVER_FLEET_V2 C5/§5).
#
# cmd_place is called through a module import, never through main(): the CLI dispatch line is
# wired separately, and these cases pin the placement math itself. Hermetic by the same rules as
# claude-accounts-core.bats — scratch SSOT, cache, util series and assignment ledger all live in
# BATS_TEST_TMPDIR, and the router constants are DERIVED from the repo accounts.json so the
# fixture cannot silently disagree with production.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$BATS_TEST_TMPDIR/lastgood.json"
  export CLAUDE_ACCOUNTS_LOG="$BATS_TEST_TMPDIR/claude-accounts.log"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
  export CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
  export CC_ROUTE_RECORDS_DIR="$BATS_TEST_TMPDIR/route-records"
  unset CC_PLACE_B_SESS_DEFAULT CC_ROUTE_RECOVERY_R_W_WORST CC_ROUTE_RECOVERY CC_ROUTE_KWORK
  python3 - "$CA_CFG" "$CACHE" "$REPO/accounts.json" <<'PY'
import json, sys
cfg_path, cache, real = sys.argv[1:4]
r = json.load(open(real))
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": "/nonexistent/model-config.yaml", "dia_local_state": "/nonexistent/LS",
  "cache_file": cache,
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"], "accounts": [],
}, open(cfg_path, "w"))
PY
}

# place(rows, kwork, movers, facts=[], stores={}, lane="general") -> (rc, plan)
# rows: {acct: overrides}; every row acct becomes a cfg account with a sandbox config_dir.
# facts: [(acct, scope, overrides)]; stores: {acct: [sid, ...]} seeds projects/p/<sid>.jsonl.
LOAD='
import importlib.machinery, os, json, time, io, contextlib
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
T = os.environ["BATS_TEST_TMPDIR"]
ca.LOG_PATH = os.path.join(T, "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
KMAX = cfg["router"]["KMAX"]
WIN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
def row(acct, **kw):
    b = dict(acct=acct, auth="ok", session_pct=0, session_reset_h=3.0, weekly_pct=0,
             weekly_reset_h=24.0, fable_pct=0, fable_reset_h=24.0, k=0, k_work=0, credits_on=False)
    b.update(kw); return b
def place(rows, kwork, movers, facts=(), stores=None, lane="general", extra=(), cache=True):
    cfg["accounts"] = [{"name": a, "config_dir": os.path.join(T, "cfg-" + a)} for a in rows]
    if cache:
        json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
                   "rows": [row(a, **o) for a, o in rows.items()], "window": WIN, "prev": None},
                  open(os.environ["CACHE"], "w"))
    fd = os.path.join(T, "facts"); os.makedirs(fd, exist_ok=True)
    for f in os.listdir(fd): os.remove(os.path.join(fd, f))
    for acct, scope, o in facts:
        json.dump(dict({"status": "rejected", "scope": scope, "observed_at": time.time() - 30,
                        "resets_at": time.time() + 3600}, **o),
                  open(os.path.join(fd, f"{acct}.{scope}.json"), "w"))
    for acct, sids in (stores or {}).items():
        p = os.path.join(T, "cfg-" + acct, "projects", "p"); os.makedirs(p, exist_ok=True)
        for s in sids: open(os.path.join(p, s + ".jsonl"), "w").close()
    mv = os.path.join(T, "movers.jsonl")
    with open(mv, "w") as fh:
        for m in movers: fh.write(json.dumps(m) + "\n")
    kf = os.path.join(T, "kwork.json"); json.dump(kwork, open(kf, "w"))
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = ca.cmd_place(["--place", "--lane", lane, "--recovery", "--movers", mv,
                           "--facts", fd, "--kwork", kf, "--json", *extra], cfg)
    return rc, (json.loads(buf.getvalue()) if buf.getvalue().strip() else None)
def movers(n, src="elsewhere", **kw):
    return [dict({"sid": f"s{i:02d}", "src": src, "kind": "limited", "burn_ph": 1}, **kw)
            for i in range(n)]
def tally(plan):
    t = {}
    for v in plan.values(): t[v["acct"]] = t.get(v["acct"], 0) + v["weight"]
    return t
'

@test "(a) a panes-charged snapshot (row k_work null) never yields more than KMAX - live seats per account, never 40-k" {
  run python3 -c "$LOAD"'
open(os.environ["CC_ASSIGN_LOG"], "w").write(json.dumps({"t": time.time(), "acct": "a"}) + "\n")
rc, plan = place({"a": {"k_work": None, "k": 3}}, {"a": 2}, movers(20))
assert rc == 0, rc
# KMAX 8 - kwork 2 - 1 live phantom = 5; the resident cap would have said 40 - 3.
assert tally(plan).get("a") == KMAX - 2 - 1, tally(plan)
assert {v["reason"] for v in plan.values() if v["acct"] is None} == {"kmax-concurrency"}, plan
print("OK")'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "(b) kwork null gives 0 seats and reason k-unmeasured" {
  run python3 -c "$LOAD"'
rc, plan = place({"a": {}, "b": {}}, {"a": None}, movers(2))
assert rc == 0 and all(v["acct"] is None for v in plan.values()), plan
assert plan["s00"]["reason"] == "k-unmeasured", plan
print("OK")'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "(c) a fact sets capacity 0 for its scope only (a model:opus fact leaves fable-lane movers unaffected)" {
  run python3 -c "$LOAD"'
f = [("a", "model:opus", {})]
rc, plan = place({"a": {}}, {"a": 0}, movers(1, model="claude-opus-5-5"), facts=f)
assert plan["s00"]["acct"] is None and plan["s00"]["reason"] == "fact:model:opus", plan
assert 3500 < plan["s00"]["eta_s"] <= 3600, plan
rc, plan = place({"a": {}}, {"a": 0}, movers(1, model="claude-fable-5-1"), facts=f, lane="fable")
assert plan["s00"]["acct"] == "a", plan
# an account-level 5h fact zeroes the account in every lane
rc, plan = place({"a": {}}, {"a": 0}, movers(1), facts=[("a", "5h", {})], lane="fable")
assert plan["s00"]["reason"] == "fact:5h", plan
# ...and a fable fact only the fable lane
rc, plan = place({"a": {}}, {"a": 0}, movers(1), facts=[("a", "fable", {})])
assert plan["s00"]["acct"] == "a", plan
print("OK")'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "(d) weights: a w=5 mover consumes 5 seats" {
  run python3 -c "$LOAD"'
m = [{"sid": "big", "src": "x", "kind": "limited", "w": 5, "burn_ph": 1, "death_ts": 1},
     {"sid": "s1", "src": "x", "kind": "limited", "w": 4, "burn_ph": 1, "death_ts": 2}]
rc, plan = place({"a": {}}, {"a": 0}, m)
assert plan["big"] == {"acct": "a", "reason": "placed", "eta_s": None, "weight": 5}, plan
assert plan["s1"]["acct"] is None, plan          # 5 + 4 > KMAX 8
print("OK")'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "(e) per-pick floors: the 7th mover onto a 0.45-5h account with b_sess 7 pp/h is refused recovery-5h-thin" {
  run python3 -c "$LOAD"'
rc, plan = place({"a": {"session_pct": 45, "session_reset_h": 1/3, "weekly_reset_h": 2.0}},
                 {"a": 0}, movers(7, burn_ph=7))
assert tally(plan).get("a") == 6, plan
assert plan["s06"] == {"acct": None, "reason": "recovery-5h-thin", "eta_s": None, "weight": 1}, plan
print("OK")'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "(f) spread: 12 equal movers over 3 equal accounts give 4/4/4" {
  run python3 -c "$LOAD"'
rc, plan = place({"a": {}, "b": {}, "c": {}}, {"a": 0, "b": 0, "c": 0}, movers(12))
assert tally(plan) == {"a": 4, "b": 4, "c": 4}, tally(plan)
print("OK")'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "(g) a source whose fact has expired is chosen (stay)" {
  run python3 -c "$LOAD"'
exp = [("a", "5h", {"resets_at": time.time() - 120})]
rows = {"a": {"weekly_pct": 60}, "b": {}}       # b outscores a on headroom
rc, plan = place(rows, {"a": 0, "b": 0}, movers(1, src="a"), facts=exp, stores={"a": ["s00"]})
assert plan["s00"] == {"acct": "a", "reason": "stay", "eta_s": None, "weight": 1}, plan
# the src given as a config-dir path resolves to the same account
rc, plan = place(rows, {"a": 0, "b": 0}, movers(1, src=os.path.join(T, "cfg-a") + "/"), facts=exp)
assert plan["s00"]["reason"] == "stay", plan
# a live fact on the src sends it elsewhere, and the eta is the src fact reset
rc, plan = place(rows, {"a": 0, "b": 0}, movers(1, src="a"), facts=[("a", "5h", {})])
assert plan["s00"]["acct"] == "b" and plan["s00"]["reason"] == "placed", plan
# a 5h fact dies once the wire reads allowed AFTER it was observed
wired = {"a": {"wire": {"5h_status": "allowed", "read_at": time.time()}}, "b": {"weekly_pct": 60}}
rc, plan = place(wired, {"a": 0, "b": 0}, movers(1, src="a"), facts=[("a", "5h", {"observed_at": time.time() - 600})])
assert plan["s00"]["reason"] == "stay", plan
print("OK")'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "(h) walk-past: the source, none, unmapped names, and stores holding the sid are all skipped" {
  run python3 -c "$LOAD"'
rows = {"a": {}, "b": {}, "c": {"weekly_pct": 50}}
rc, plan = place(rows, {"a": 0, "b": 0, "c": 0, "none": 0, "ghost": 0}, movers(1, src="a"),
                 facts=[("a", "7d", {})], stores={"b": ["s00"]})
assert plan["s00"]["acct"] == "c", plan
# "none" and an unmapped snapshot row are never candidates, even if they would score best
c = json.load(open(os.environ["CACHE"]))
c["rows"] += [row("none"), row("ghost")]
json.dump(c, open(os.environ["CACHE"], "w"))
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = ca.cmd_place(["--place", "--lane", "general", "--movers", os.path.join(T, "movers.jsonl"),
                       "--facts", os.path.join(T, "facts"), "--kwork", os.path.join(T, "kwork.json")], cfg)
p = json.loads(buf.getvalue())
assert rc == 0 and p["s00"]["acct"] == "c", p
# with c gone too, nothing is left: the reasons name every wall
rc, plan = place({"a": {}, "b": {}}, {"a": 0, "b": 0}, movers(1, src="a"),
                 facts=[("a", "7d", {})], stores={"b": ["s00"]})
assert plan["s00"]["acct"] is None and plan["s00"]["reason"] == "fact:7d,store-holds-sid", plan
assert plan["s00"]["eta_s"] is not None, plan
print("OK")'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "no servable cache: exit 3 and every mover wait-data" {
  run python3 -c "$LOAD"'
rc, plan = place({"a": {}}, {"a": 0}, movers(2), cache=False)
assert rc == 3, rc
assert plan == {s: {"acct": None, "reason": "wait-data", "eta_s": None, "weight": 1}
                for s in ("s00", "s01")}, plan
print("OK")'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "a missing movers file exits 64" {
  run python3 -c "$LOAD"'
os.makedirs(os.path.join(T, "facts"), exist_ok=True)
json.dump({}, open(os.path.join(T, "kwork.json"), "w"))
rc = ca.cmd_place(["--place", "--lane", "general", "--movers", os.path.join(T, "nope.jsonl"),
                   "--facts", os.path.join(T, "facts"), "--kwork", os.path.join(T, "kwork.json")], cfg)
assert rc == 64, rc
rc = ca.cmd_place(["--place", "--lane", "sideways"], cfg)
assert rc == 64, rc
print("OK")'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}
