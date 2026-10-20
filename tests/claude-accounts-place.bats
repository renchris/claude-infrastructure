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
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
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
  # KMAX pinned: these cases test the cap's mechanics (overflow at 8), not the operator's tuning of it.
  "frontier": r["frontier"], "router": dict(r["router"], KMAX=8), "accounts": [],
}, open(cfg_path, "w"))
PY
}

# place(rows, kwork, movers, facts=[], stores={}, lane="general") -> (rc, plan)
# rows: {acct: overrides}; every row acct becomes a cfg account with a sandbox config_dir.
# facts: [(acct, scope, overrides)]; stores: {acct: [sid, ...]} seeds projects/p/<sid>.jsonl.
LOAD='
import importlib.machinery, importlib.util, os, json, time, io, contextlib
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
def hmap(**kw):  # B4 C1: the {acct: [config_dir, bool]} holds map, over the fixture stores
    return {a: [os.path.join(T, "cfg-" + a), v] for a, v in kw.items()}
GLOBS = []
_glob = ca.glob.glob
ca.glob.glob = lambda p, *a, **k: (GLOBS.append(p) if "/projects/" in p else None, _glob(p, *a, **k))[1]
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

@test "(d2) gap-3 E4.3: a mover's own live phantom does not charge its own re-placement; others still pay it" {
  run python3 -c "$LOAD"'
t = time.time()
with open(os.environ["CC_ASSIGN_LOG"], "w") as fh:
    fh.write(json.dumps({"t": t - 60, "acct": "a", "id": "recon:c:db755a94:1", "sid": "db",
                         "w": 6, "ttl_s": 1200}) + "\n")
mv = {"sid": "db", "src": "x", "kind": "limited", "w": 6, "burn_ph": 1, "death_ts": 1}
# control: the same mover WITHOUT its id is refused by its own 6 seats (KMAX 8 - 6 = 2 < 6)
rc, plan = place({"a": {}}, {"a": 0}, [mv])
assert plan["db"]["acct"] is None and plan["db"]["reason"] == "kmax-concurrency", plan
rc, plan = place({"a": {}}, {"a": 0}, [dict(mv, assign_id="recon:c:db755a94:1")])
assert plan["db"]["acct"] == "a", plan
# the exemption is the mover s own, on that account only: a stranger still pays the phantom
other = {"sid": "s9", "src": "x", "kind": "limited", "w": 3, "burn_ph": 1, "death_ts": 2,
         "assign_id": "recon:c:s9:1"}
rc, plan = place({"a": {}}, {"a": 0}, [other])
assert plan["s9"]["acct"] is None, plan
# a voided phantom is no longer charged, so it is no longer refunded either
with open(os.environ["CC_ASSIGN_LOG"], "a") as fh:
    fh.write(json.dumps({"t": t - 30, "void": "recon:c:db755a94:1"}) + "\n")
rc, plan = place({"a": {}}, {"a": 0}, [dict(mv, w=8, assign_id="recon:c:db755a94:1")])
assert plan["db"]["acct"] == "a", plan
rc, plan = place({"a": {}}, {"a": 0}, [dict(mv, w=9, assign_id="recon:c:db755a94:1")])
assert plan["db"]["acct"] is None, plan
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

@test "(k) a contradicted auth fact never zeroes capacity; a live auth fact and a contradicted 5h fact still do" {
  run python3 -c "$LOAD"'
dead = {"resets_at": None, "contradicted": True}
rc, plan = place({"a": {}}, {"a": 0}, movers(1), facts=[("a", "auth", dead)])
assert rc == 0 and plan["s00"]["acct"] == "a", plan
rc, plan = place({"a": {}}, {"a": 0}, movers(1), facts=[("a", "auth", {"resets_at": None})])
assert plan["s00"]["acct"] is None and plan["s00"]["reason"] == "fact:auth", plan
rc, plan = place({"a": {}}, {"a": 0}, movers(1), facts=[("a", "5h", {"contradicted": True})])
assert plan["s00"]["reason"] == "fact:5h", plan
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

# ── the v2 assignment ledger (W1 T-ledger): cases (i)-(j) plus the ledger contract ──────────────
# These run on their own two-account sandbox SSOT, written by ledger_setup over the file's setup().
ledger_setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_SSOT="$REPO/accounts.json"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CA_LEDGER="$BATS_TEST_TMPDIR/lastgood.json"
  export CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$CA_LEDGER"
  export CLAUDE_ACCOUNTS_LOG="$BATS_TEST_TMPDIR/claude-accounts.log"
  export YAML="$BATS_TEST_TMPDIR/model-config.yaml"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
  export CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
  export CC_ROUTE_RECORDS_DIR="$BATS_TEST_TMPDIR/route-records"
  unset CC_ROUTE_ASSIGN CC_ROUTE_ASSIGN_TTL_MIN
  rm -f "$CA_LEDGER" "$CACHE" "$CC_ASSIGN_LOG"
  python3 - "$CA_CFG" "$CACHE" "$CA_SSOT" "$YAML" <<'PY'
import json, sys
cfg_path, cache, real, yaml = sys.argv[1:5]
r = json.load(open(real))
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": yaml, "dia_local_state": "/nonexistent/LS",
  "cache_file": cache,
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [{"name": "next3", "config_dir": "/tmp/ca-test-nonexistent-xyz",
                "launcher": "claude3",
                "email": "test@example.com", "mailbox": "test@example.com", "dia_profile": "T"},
               {"name": "next2", "config_dir": "/tmp/ca-test-nonexistent-xyz2",
                "launcher": "claude2",
                "email": "test2@example.com", "mailbox": "test2@example.com", "dia_profile": "U"}],
}, open(cfg_path, "w"))
PY
}

LEDGER_LOAD='
import importlib.machinery, importlib.util, os, json
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
P = os.environ["CC_ASSIGN_LOG"]
def put(*rows):
    with open(P, "a") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
'

@test "(i) void rows survive _assignment_rows and ttl_s expiry works" {
  ledger_setup
  run python3 -c "$LEDGER_LOAD"'
t = 1_000_000.0
put({"t": t, "acct": "next3", "id": "gone", "w": 3},
    {"t": t + 1, "void": "gone"},
    {"t": t, "acct": "next2", "id": "heavy", "w": 5},
    {"t": t, "acct": "next3", "id": "short", "ttl_s": 30},
    {"t": t, "acct": "next2"})                                        # legacy: 15 min TTL
rows = ca._assignment_rows(P)
assert any(r.get("void") == "gone" for r in rows), rows
c = ca.assignment_counts(cfg, path=P, now=t + 10)
assert c == {"next2": 6, "next3": 1}, c                   # voided id 0 · w=5 · ttl row · legacy
c = ca.assignment_counts(cfg, path=P, now=t + 40)
assert c == {"next2": 6}, c                               # the ttl_s=30 row expired, legacy did not
assert ca.assignment_counts(cfg, path=P, now=t + 14 * 60) == {"next2": 6}
assert ca.assignment_counts(cfg, path=P, now=t + 16 * 60) == {}      # legacy keeps 15 min
# duplicate id: a re-plan REPLACES — counted once, and the newest row (acct + w) wins
put({"t": t + 2, "acct": "next3", "id": "dup", "w": 2},
    {"t": t + 3, "acct": "next2", "id": "dup", "w": 4})
c = ca.assignment_counts(cfg, path=P, now=t + 10)
assert c == {"next2": 10, "next3": 1}, c
# a void row is never a charge for desk_incumbent either
assert ca.desk_incumbent(cfg, path=P, now=t + 10) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "(j) --max-wait 2 on a held lock returns within 2.5 s with exit 3" {
  ledger_setup
  python3 - "$CACHE.lock" <<'PY' &
import fcntl, sys, time
f = open(sys.argv[1], "w")
fcntl.flock(f, fcntl.LOCK_EX)
open(sys.argv[1] + ".held", "w").close()
time.sleep(6)
PY
  holder=$!
  for _ in $(seq 50); do [ -e "$CACHE.lock.held" ] && break; python3 -c 'import time; time.sleep(0.1)'; done
  [ -e "$CACHE.lock.held" ]
  # Timed around the child alone, in one interpreter: bats' `run` and a second python startup
  # are not the command's wall clock. The 2.5 s is asserted NET of a same-sandbox run that waits
  # for nothing (`--max-wait 0`, no cache => exit 3 at once): interpreter start plus compiling this
  # 7,000-line script happens before any code of ours runs, and measured 0.7-1.2 s at load 40-130
  # (2026-09-29). What this case proves is that the LOCK WAIT is bounded (unbounded, it is 240 s).
  run python3 -c '
import os, subprocess, sys, time
def timed(*a):
    t = time.monotonic()
    r = subprocess.run([os.environ["CA_BIN"], "--json", *a], capture_output=True)
    return r.returncode, time.monotonic() - t
_, base = timed("--max-wait", "0")
rc, el = timed("--max-wait", "2")
print(rc, round(el - base, 3))'
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  read -r rc elapsed <<<"$output"
  [ "$rc" -eq 3 ] || { echo "$output"; false; }
  python3 -c "import sys; sys.exit(0 if $elapsed < 2.5 else 1)" || { echo "elapsed=$elapsed"; false; }
  [ ! -e "$CACHE" ]                                   # nothing swept, nothing cached
}

@test "--assign-many is all-or-nothing: one bad line exits 64 and the ledger is unchanged" {
  ledger_setup
  printf '%s\n' '{"t":1,"ts":"x","acct":"next3"}' > "$CC_ASSIGN_LOG"
  before="$(cat "$CC_ASSIGN_LOG")"
  f="$BATS_TEST_TMPDIR/plan.jsonl"
  printf '%s\n' '{"acct":"next3","id":"a1","sid":"s-1","w":2,"ttl_s":60}' \
                '{"acct":"next2","id":"a2","w":0}' > "$f"
  run "$CA_BIN" --assign-many "$f"
  [ "$status" -eq 64 ] || { echo "$output"; false; }
  [[ "$output" == *"line 2"* ]] || false
  [ "$(cat "$CC_ASSIGN_LOG")" = "$before" ]
  # the good batch lands whole, with one shared t
  printf '%s\n' '{"acct":"next3","id":"a1","sid":"s-1","w":2,"ttl_s":60}' '' \
                '{"acct":"next2","id":"a2"}' > "$f"
  run "$CA_BIN" --assign-many "$f"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run python3 -c '
import json, os, sys
rows = [json.loads(l) for l in open(os.environ["CC_ASSIGN_LOG"])][1:]
assert len(rows) == 2 and rows[0]["t"] == rows[1]["t"], rows
assert list(rows[0]) == ["t", "ts", "acct", "id", "sid", "w", "ttl_s"], rows[0]
assert list(rows[1]) == ["t", "ts", "acct", "id"], rows[1]
print("OK")'
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
  # an empty file writes nothing
  : > "$f"
  n0=$(wc -l < "$CC_ASSIGN_LOG")
  run "$CA_BIN" --assign-many "$f"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CC_ASSIGN_LOG")" -eq "$n0" ]
}

@test "--unassign appends {t, ts, void} and is idempotent; a bad id exits 64" {
  ledger_setup
  run "$CA_BIN" --unassign plan:w1.a
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$CA_BIN" --unassign plan:w1.a
  [ "$status" -eq 0 ]
  run python3 -c '
import json, os
rows = [json.loads(l) for l in open(os.environ["CC_ASSIGN_LOG"])]
assert len(rows) == 2 and all(list(r) == ["t", "ts", "void"] for r in rows), rows
assert rows[0]["void"] == "plan:w1.a", rows
print("OK")'
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
  run "$CA_BIN" --unassign 'bad id!'
  [ "$status" -eq 64 ]
  run "$CA_BIN" --assign next3 --w 0
  [ "$status" -eq 64 ]
  run "$CA_BIN" --assign next3 --sid 'a b'
  [ "$status" -eq 64 ]
  [ "$(wc -l < "$CC_ASSIGN_LOG")" -eq 2 ]
}

@test "legacy --assign next3 --src x writes the byte-identical {t,ts,acct,src} row" {
  ledger_setup
  run "$CA_BIN" --assign next3 --src x
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$CA_BIN" --assign next2
  [ "$status" -eq 0 ]
  run python3 -c '
import json, os
from datetime import datetime, timezone
lines = open(os.environ["CC_ASSIGN_LOG"]).read().splitlines()
a, b = (json.loads(l) for l in lines)
assert list(a) == ["t", "ts", "acct", "src"] and a["acct"] == "next3" and a["src"] == "x", a
assert list(b) == ["t", "ts", "acct"], b
# the exact serialisation the pre-v2 writer produced for the same values
want = json.dumps({"t": a["t"], "ts": a["ts"], "acct": "next3", "src": "x"}, separators=(",", ":"))
assert lines[0] == want, (lines[0], want)
assert datetime.fromisoformat(a["ts"]).tzinfo is not None and a["ts"].endswith("+00:00"), a
print("OK")'
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "apply_assignments skips a sid phantom the same account's sweep already counts" {
  ledger_setup
  run python3 -c "$LEDGER_LOAD"'
import time
t = time.time() - 60
put({"t": t, "acct": "next3", "id": "p1", "sid": "sess-a", "w": 2},   # swept by next3 → skipped
    {"t": t, "acct": "next3", "id": "p2", "sid": "sess-b"},           # not in the sweep → 1
    {"t": t, "acct": "next2", "id": "p3", "sid": "sess-a"},           # other acct swept it → 1
    {"t": t, "acct": "next3"})                                        # no sid → 1
ca.ASSIGN_PATH = P
rows = [dict(acct="next3", k_sids=["sess-a"], k_sids_at=t + 5), dict(acct="next2")]
ca.apply_assignments(rows, cfg)
assert [r["k_phantom"] for r in rows] == [2, 1], rows
# a sweep OLDER than the phantom does not know that session yet: the charge stands
rows = [dict(acct="next3", k_sids=["sess-a"], k_sids_at=t - 5), dict(acct="next2")]
ca.apply_assignments(rows, cfg)
assert [r["k_phantom"] for r in rows] == [4, 1], rows
# an unmeasured sweep (k_sids_at None) skips nothing
rows = [dict(acct="next3", k_sids=None, k_sids_at=None)]
ca.apply_assignments(rows, cfg)
assert rows[0]["k_phantom"] == 4, rows
# the census carries the top-level sids it counted, and only those
import os
base = os.path.join(os.environ["BATS_TEST_TMPDIR"], "kw")
sub = os.path.join(base, "projects", "slug", "sess-x", "subagents")
os.makedirs(sub)
open(os.path.join(base, "projects", "slug", "sess-x.jsonl"), "w").close()
open(os.path.join(sub, "agent-1.jsonl"), "w").close()
got = ca.working_concurrency({"accounts": [{"name": "a", "config_dir": base}]},
                             window_min=10, budget_s=5.0)
assert got == {"a": 2} and got.sids == {"a": {"sess-x"}} and got.at is not None, (got, got.sids)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "CLI: --place is dispatched by main and returns WAIT_DATA (exit 3) with no servable cache" {
  printf '{"sid":"s00","src":"elsewhere","kind":"limited"}\n' > "$BATS_TEST_TMPDIR/movers.jsonl"
  mkdir -p "$BATS_TEST_TMPDIR/facts"; printf '{}' > "$BATS_TEST_TMPDIR/kwork.json"
  run "$CA_BIN" --place --lane general --recovery --movers "$BATS_TEST_TMPDIR/movers.jsonl" \
    --facts "$BATS_TEST_TMPDIR/facts" --kwork "$BATS_TEST_TMPDIR/kwork.json" --json
  [ "$status" -eq 3 ]
  [[ "$output" == *'"wait-data"'* ]]
}

# ---- FLEET_V2 W6 (operator rulings 2026-09-30) ---------------------------------------------------

# D3.2, router half. Decision 3 ruled WAIT when no account passes the floors. The reconciler keeps a
# waiting mover re-offered only while `wait.eta` is STRICTLY before the source reset (plan.apply),
# and that holds because this router FLOORS eta_s. A ceil here turns the record into WAIT_RESET,
# which stops re-checking until the source's own reset — up to 36.6 h away for a weekly cap.
@test "W6 D3.2: all candidates thin + a live source fact => no account, eta_s is the FLOOR of the source reset" {
  run python3 -c "$LOAD"'
resets = time.time() + 3600.7
t0 = time.time()
rc, plan = place({"a": {}, "b": {"weekly_pct": 95}, "c": {"weekly_pct": 95}},
                 {"a": 0, "b": 0, "c": 0}, movers(1, src="a"),
                 facts=[("a", "5h", {"resets_at": resets})])
assert rc == 0, rc
p = plan["s00"]
assert p["acct"] is None, p
assert set(p["reason"].split(",")) == {"fact:5h", "recovery-weekly-thin"}, p
assert isinstance(p["eta_s"], int), p
assert p["eta_s"] <= resets - t0, (p, resets - t0)          # floored, never rounded up
assert p["eta_s"] >= int(resets - time.time()) , p          # and within the call, not stale
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

# D3.6(a). No caller supplies burn_ph today; when one does, a raw pre-death burn below the fleet
# default must not undercharge (it bounded the post-move burn for 19 of 56 transplant pairs;
# max(pre, default) bounded 51). Same geometry as case (e): 0.45 used, reset in 20 min.
@test "W6 D3.6a: a supplied burn below the default is charged the default; one above it is kept" {
  run python3 -c "$LOAD"'
geo = {"a": {"session_pct": 45, "session_reset_h": 1/3, "weekly_reset_h": 2.0}}
rc, plan = place(geo, {"a": 0}, movers(7, burn_ph=1))
assert tally(plan).get("a") == 6, plan                     # 1 pp/h is charged as 7
assert plan["s06"]["reason"] == "recovery-5h-thin", plan
rc, plan = place(geo, {"a": 0}, movers(7, burn_ph=20))
assert tally(plan).get("a") == 2, plan                     # 20 pp/h stays 20
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

# Resolution 11 (D1.3 router half). A cache swept BEFORE a mover source's reset is a picture of a
# capped source that has since rolled; on 2026-09-30 such a cache moved a cohort off its source 5 s
# after the 06:30Z reset. --place (cache-only) must refuse it as WAIT_DATA, on every path.
@test "W6 res11: --place refuses a cache that predates a mover source's reset; a post-reset cache serves" {
  run python3 -c "$LOAD"'
from datetime import datetime, timezone
iso = lambda t: datetime.fromtimestamp(t, timezone.utc).isoformat()
now = time.time()
def seed(cache_age, src_reset_ago):
    rows = {"a": {"session_pct": 100, "session_reset_at": iso(now - src_reset_ago)}, "b": {}}
    rc, plan = place(rows, {"a": 0, "b": 0}, movers(1, src="a"), cache=False)
    cfg["accounts"] = [{"name": x, "config_dir": os.path.join(T, "cfg-" + x)} for x in rows]
    json.dump({"ts": now - cache_age, "cfg_key": ca._cfg_key(cfg), "no_heal": False,
               "rows": [row(x, **o) for x, o in rows.items()], "window": WIN, "prev": None},
              open(os.environ["CACHE"], "w"))
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = ca.cmd_place(["--place", "--lane", "general", "--recovery", "--movers",
                           os.path.join(T, "movers.jsonl"), "--facts", os.path.join(T, "facts"),
                           "--kwork", os.path.join(T, "kwork.json")], cfg)
    return rc, json.loads(buf.getvalue())
rc, plan = seed(cache_age=120, src_reset_ago=60)           # swept 2 min ago, source rolled 1 min ago
assert rc == 3 and plan["s00"]["reason"] == "wait-data", (rc, plan)
rc, plan = seed(cache_age=30, src_reset_ago=60)            # swept AFTER the roll: served
assert rc == 0 and plan["s00"]["reason"] != "wait-data", (rc, plan)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "W6 res11: CLI --rank --src refuses a pre-reset cache even at --max-wait 0; without --src it serves" {
  run python3 -c "$LOAD"'
from datetime import datetime, timezone
import subprocess
iso = lambda t: datetime.fromtimestamp(t, timezone.utc).isoformat()
now = time.time()
cfg["accounts"] = [{"name": x, "config_dir": os.path.join(T, "cfg-" + x), "launcher": "c",
                    "email": "t@example.com", "mailbox": "t@example.com", "dia_profile": "T"}
                   for x in ("a", "b")]
json.dump(cfg, open(os.environ["CA_CFG"], "w"))
json.dump({"ts": now - 120, "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "rows": [row("a", session_pct=100, session_reset_at=iso(now - 60)), row("b")],
           "window": WIN, "prev": None}, open(os.environ["CACHE"], "w"))
def rank(*extra):
    return subprocess.run([os.environ["CA_BIN"], "--rank", "general", "--recovery",
                           "--max-wait", "0", "--max-age", "600", *extra],
                          capture_output=True, text=True)
p = rank("--src", "a")
assert p.returncode == 3 and p.stdout.strip() == "none", (p.returncode, p.stdout, p.stderr)
assert "predates a" in p.stderr and "session reset" in p.stderr, p.stderr
p = rank("--src", os.path.join(T, "cfg-a") + "/")           # a config dir names the same account
assert p.returncode == 3, (p.returncode, p.stderr)
p = rank()
assert p.returncode == 0 and p.stdout.split()[0] == "b", (p.returncode, p.stdout, p.stderr)
p = rank("--src", "b")                                      # b has not reset: served
assert p.returncode == 0, (p.returncode, p.stderr)
p = rank("--src", "ghost")
assert p.returncode == 64, (p.returncode, p.stderr)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ---- cheap --place (LR_SUSTAINED_LOAD W3, B4 C1-C2) ------------------------------------------------
# --place cost 4.75-11.7 s and 4.3-4.9 CPU-s at PRI 31 with 9 movers, from two corpus scans: a
# projects/*/<sid>.jsonl glob per mover x account (~18.3k lstat each) and a 336 h utilization read
# that parsed the whole file twice on ~85% of calls. C1 trusts a caller's holds map, C2 reads 49 h.
# Design: docs/research/lr-sustained-load-2026-10-20/impl/B4-cheap-place.md §2, §6.

@test "P1 RED: a complete holds map answers the store check, so --place globs no project dir" {
  run python3 -c "$LOAD"'
rows = {"a": {}, "b": {}, "c": {}}
mv = [dict(m, holds=hmap(a=False, b=False, c=False)) for m in movers(3, src="a")]
rc, plan = place(rows, {"a": 0, "b": 0, "c": 0}, mv, stores={"b": ["s00"]})
assert rc == 0, rc
assert GLOBS == [], GLOBS                  # before C1: 3 movers x 2 non-source accounts = 6 globs
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "P2 RED: the map is the answer, not decoration — false over a disk copy places, true over none refuses" {
  run python3 -c "$LOAD"'
f7 = [("a", "7d", {})]
rc, plan = place({"a": {}, "b": {}}, {"a": 0, "b": 0},
                 movers(1, src="a", holds=hmap(a=False, b=False)), facts=f7, stores={"b": ["s00"]})
assert plan["s00"]["acct"] == "b" and plan["s00"]["reason"] == "placed", plan
os.remove(os.path.join(T, "cfg-b", "projects", "p", "s00.jsonl"))      # the store no longer holds it
rc, plan = place({"a": {}, "b": {}}, {"a": 0, "b": 0},
                 movers(1, src="a", holds=hmap(a=False, b=True)), facts=f7)
assert plan["s00"]["acct"] is None and plan["s00"]["reason"] == "fact:7d,store-holds-sid", plan
assert plan["s00"]["eta_s"] is not None, plan
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "P2c: an entry is trusted only when its config_dir resolves to the account's own store (realpath)" {
  # The mutant "trust any cfg" turns this red: a map computed over a DIFFERENT accounts.json
  # (B4 correctness review F5) must never answer for the store --place itself resolves.
  run python3 -c "$LOAD"'
f7 = [("a", "7d", {})]
fix = dict(facts=f7, stores={"b": ["s00"]})
stranger = {"b": [os.path.join(T, "elsewhere"), False]}
rc, plan = place({"a": {}, "b": {}}, {"a": 0, "b": 0}, movers(1, src="a", holds=stranger), **fix)
assert plan["s00"]["reason"] == "fact:7d,store-holds-sid", plan          # globbed, not trusted
os.symlink(os.path.join(T, "cfg-b"), os.path.join(T, "link-b"))
for alias in (os.path.join(T, "link-b"), os.path.join(T, "cfg-b") + "/"):
    rc, plan = place({"a": {}, "b": {}}, {"a": 0, "b": 0},
                     movers(1, src="a", holds={"b": [alias, False]}), **fix)
    assert plan["s00"]["acct"] == "b", (alias, plan)                     # same store: trusted
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "P3: an account the map omits, or a malformed entry, is globbed exactly as before" {
  # Mutant: holds() reading a missing key as False turns the first arm red.
  run python3 -c "$LOAD"'
f7 = [("a", "7d", {})]
rc, plan = place({"a": {}, "b": {}}, {"a": 0, "b": 0},
                 movers(1, src="a", holds=hmap(a=False)), facts=f7, stores={"b": ["s00"]})
assert plan["s00"]["reason"] == "fact:7d,store-holds-sid", plan
for bad in ({"b": True}, {"b": [os.path.join(T, "cfg-b"), "yes"]}, {"b": [None, False]},
            {"b": [os.path.join(T, "cfg-b"), False, 1]}, ["b"]):
    rc, plan = place({"a": {}, "b": {}}, {"a": 0, "b": 0},
                     movers(1, src="a", holds=bad), facts=f7, stores={"b": ["s00"]})
    assert rc == 0 and plan["s00"]["reason"] == "fact:7d,store-holds-sid", (bad, plan)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "P4: CC_PLACE_HOLDS_MAP=off and ~/.claude/state/place-holds-map.off each ignore the map, read per call" {
  run python3 -c "$LOAD"'
f7 = [("a", "7d", {})]
def go():
    return place({"a": {}, "b": {}}, {"a": 0, "b": 0},
                 movers(1, src="a", holds=hmap(a=False, b=False)), facts=f7, stores={"b": ["s00"]})[1]
assert go()["s00"]["acct"] == "b"
os.environ["CC_PLACE_HOLDS_MAP"] = "off"
assert go()["s00"]["reason"] == "fact:7d,store-holds-sid"
del os.environ["CC_PLACE_HOLDS_MAP"]
off = os.path.join(os.environ["HOME"], ".claude", "state", "place-holds-map.off")
os.makedirs(os.path.dirname(off), exist_ok=True)
open(off, "w").close()                                  # same process: the switch is read per call
assert go()["s00"]["reason"] == "fact:7d,store-holds-sid"
os.remove(off)
assert go()["s00"]["acct"] == "b"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "P5 RED: --place reads PLACE_BURN_LOOKBACK_H (49) hours of the series, not 336; the switches restore 336" {
  run python3 -c "$LOAD"'
HOURS, real = [], ca._util_tail
def spy(path=None, hours=48.0, max_bytes=None):
    HOURS.append(hours); return real(path, hours, max_bytes)
ca._util_tail = spy
def go():
    del HOURS[:]
    place({"a": {}, "b": {}}, {"a": 0, "b": 0}, movers(1, src="a"))
    return list(HOURS)
assert ca.PLACE_BURN_LOOKBACK_H == 49.0, ca.PLACE_BURN_LOOKBACK_H
assert go() == [49.0], HOURS
os.environ["CC_PLACE_BURN_NARROW"] = "off"
assert go() == [ca.BURST_LOOKBACK_H], HOURS
del os.environ["CC_PLACE_BURN_NARROW"]
off = os.path.join(os.environ["HOME"], ".claude", "state", "place-burn-narrow.off")
os.makedirs(os.path.dirname(off), exist_ok=True)
open(off, "w").close()
assert go() == [ca.BURST_LOOKBACK_H], HOURS
os.remove(off)
assert go() == [49.0], HOURS
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "P6: the burn fields --place reads are bit-identical under the 49 h read, and a 24 h read is not (power)" {
  # EQUIVALENCE GUARD with power. Mutant PLACE_BURN_LOOKBACK_H = 24.0 turns it red; the in-test
  # 24 h arm is the positive control that this fixture can tell a narrower window apart at all.
  run python3 -c "$LOAD"'
import random
from datetime import datetime, timezone
iso = lambda t: datetime.fromtimestamp(t, timezone.utc).isoformat()
rnd, T0 = random.Random(7), time.time()
t = T0 - 20 * 86400
A = "abcd"
sp, wp = dict.fromkeys(A, 0.0), dict.fromkeys(A, 0.0)
sra = {a: t + rnd.uniform(0, 5 * 3600) for a in A}
wra = {a: t + rnd.uniform(0, 7 * 86400) for a in A}
p = os.path.join(T, "util-p6.jsonl")
with open(p, "w") as fh:
    while t < T0 - 60:
        t += rnd.choice((60, 120, 300, 300, 600, 900, 1800, 3600))   # bursty sweeps, shared stamp
        for a in A:
            if t >= sra[a]: sp[a], sra[a] = 0.0, sra[a] + 5 * 3600
            if t >= wra[a]: wp[a], wra[a] = 0.0, wra[a] + 7 * 86400
            sp[a] = min(100.0, sp[a] + rnd.uniform(0, 3)); wp[a] = min(100.0, wp[a] + rnd.uniform(0, .4))
            e = {"ts": iso(t), "acct": a, "session_pct": round(sp[a]), "weekly_pct": round(wp[a]),
                 "session_reset_at": iso(sra[a]), "weekly_reset_at": iso(wra[a])}
            if rnd.random() < 0.03: e["stale"] = True
            fh.write(json.dumps(e) + "\n")
F = ("burn_5h_ph", "burn_5h_ewma_ph", "burn_wk_ewma_ph", "wk_strand_pp")
real_time, seen, diff24 = time.time, dict.fromkeys(F, 0), 0
def burn(M, h):
    ss = [e for e in ca._util_tail_read(p, h)[0] if e["_t"] <= M]
    out = []
    for a in A:
        last = [e for e in ss if e["acct"] == a][-1]
        wr = datetime.fromisoformat(last["weekly_reset_at"]).timestamp()
        out.append({"acct": a, "weekly_pct": last["weekly_pct"], "weekly_reset_h": (wr - M) / 3600})
    ca.apply_burn(out, {}, samples=ss)
    return out
for j in range(20):
    M = T0 - 3600 - j * 7.2 * 3600
    ca.time.time = lambda: M
    wide, narrow, n24 = burn(M, ca.BURST_LOOKBACK_H), burn(M, ca.PLACE_BURN_LOOKBACK_H), burn(M, 24.0)
    for w_, n_, x_ in zip(wide, narrow, n24):
        for f in F:
            assert w_.get(f) == n_.get(f), (j, w_["acct"], f, w_.get(f), n_.get(f))
            seen[f] += f in w_
            diff24 += w_.get(f) != x_.get(f)
ca.time.time = real_time
assert all(seen.values()), seen                  # every field is present somewhere: not vacuous
assert diff24 > 0, diff24                        # the fixture has the power to see a narrower read
print("OK", seen, diff24)'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "P6b: of apply_burn's outputs, cmd_place's call graph reads only the three fields 49 h covers (ast)" {
  # A future reader of a wider field (burst, exchange_k, burn_ratio ...) on the --place path would
  # silently see a 49 h window. Mutant: add r.get("burst") to floors_ok -> red.
  run python3 - "$CA_BIN" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
funcs = {n.name: n for n in tree.body if isinstance(n, ast.FunctionDef)}
def key(s):
    s = getattr(s, "value", s) if type(s).__name__ == "Index" else s
    return s.value if isinstance(s, ast.Constant) and isinstance(s.value, str) else None
W = set()
for n in ast.walk(funcs["apply_burn"]):
    for t in (n.targets if isinstance(n, ast.Assign) else []):
        if isinstance(t, ast.Subscript) and key(t.slice):
            W.add(key(t.slice))
R, seen, todo = set(), set(), ["cmd_place"]
while todo:
    f = todo.pop()
    if f in seen or f not in funcs or f == "apply_burn":
        continue
    seen.add(f)
    for n in ast.walk(funcs[f]):
        if isinstance(n, ast.Call):
            if isinstance(n.func, ast.Attribute) and n.func.attr == "get" and n.args and key(n.args[0]):
                R.add(key(n.args[0]))
            todo += [x.id for x in [n.func] + list(n.args) if isinstance(x, ast.Name)]
        if isinstance(n, ast.Subscript) and isinstance(n.ctx, ast.Load) and key(n.slice):
            R.add(key(n.slice))
assert len(W) >= 10 and len(seen) >= 50, (len(W), len(seen))          # the walk is not vacuous
got = W & R
assert got and got <= {"burn_5h_ph", "burn_5h_ewma_ph", "wk_strand_pp"}, sorted(got)
print("OK", sorted(got))
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "P7: differential — 40 seeded frozen fixtures place byte-identically with glob-computed maps and with none" {
  # EQUIVALENCE GUARD with power: flipping one map bit must change at least one answer, and real
  # store-holds-sid walls must be exercised, or the comparison proves nothing.
  run python3 -c "$LOAD"'
import random, shutil
T0, real_time = time.time(), time.time
ca.time.time = lambda: T0
def wipe():
    for d in os.listdir(T):
        if d.startswith("cfg-"): shutil.rmtree(os.path.join(T, d))
mism, flips, walls = 0, 0, 0
for seed in range(40):
    rnd = random.Random(seed)
    accts = ["a", "b", "c", "d"][:rnd.randint(2, 4)]
    rows = {a: {"session_pct": rnd.randint(0, 60), "weekly_pct": rnd.randint(0, 80)} for a in accts}
    kwork = {a: rnd.choice([None, 0, 1, 3, 6, 7, 8]) for a in accts}
    facts = [(rnd.choice(accts), rnd.choice(["7d", "5h", "model:opus"]), {})
             for _ in range(rnd.randint(0, 2))]
    mv = [{"sid": "s%02d" % i, "src": rnd.choice(accts), "kind": rnd.choice(["limited", "idle"]),
           "w": rnd.randint(1, 12), "model": rnd.choice(["claude-opus-5-5", "claude-sonnet-5-5"])}
          for i in range(rnd.randint(1, 9))]
    stores = {}
    for m in mv:
        for a in rnd.sample(accts, rnd.randint(0, min(3, len(accts)))):
            stores.setdefault(a, []).append(m["sid"])
    wipe()
    rc0, bare = place(rows, kwork, mv, facts=facts, stores=stores)
    hm = lambda m: {a: [os.path.join(T, "cfg-" + a), m["sid"] in stores.get(a, [])] for a in accts}
    rc1, mapped = place(rows, kwork, [dict(m, holds=hm(m)) for m in mv], facts=facts, stores=stores)
    mism += (rc0, json.dumps(bare, sort_keys=True)) != (rc1, json.dumps(mapped, sort_keys=True))
    walls += sum("store-holds-sid" in (v["reason"] or "") for v in bare.values())
    flip = [dict(m, holds={a: [c, not b] for a, (c, b) in hm(m).items()}) for m in mv]
    rc2, flipped = place(rows, kwork, flip, facts=facts, stores=stores)
    flips += json.dumps(flipped, sort_keys=True) != json.dumps(bare, sort_keys=True)
ca.time.time = real_time
print("mismatches=%d flips_that_changed=%d store_walls=%d" % (mism, flips, walls))
assert mism == 0 and flips > 0 and walls > 0
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
  [[ "$output" == *"mismatches=0 "* ]] || false
}

@test "E1 RED: a 9-mover batch with complete maps globs nothing, and its parse count does not grow with history" {
  # The scaling form of the end-to-end contract (B4 reviews F1/F6: the absolute 5,000 bound was
  # unreachable, the prototype measured 11,880-13,865). A 20-day and a 60-day series with the same
  # newest 20 days must cost the same json.loads; before C2+C3 the whole file was parsed twice.
  run python3 -c "$LOAD"'
from datetime import datetime, timezone
now = time.time()
lines = []
for k in range(int(60 * 86400 / 300), -1, -1):      # one 3-row burst every 5 min; the 49 h cutoff
    ts = datetime.fromtimestamp(now - 150 - k * 300, timezone.utc).isoformat()   # falls 150 s off
    lines += [json.dumps({"ts": ts, "acct": a, "session_pct": (k * 7) % 100, "weekly_pct": 40,
                          "pad": "x" * 120}) + "\n" for a in "abc"]
short = lines[-int(20 * 86400 / 300) * 3:]
mv = [dict(m, holds=hmap(a=False, b=False, c=False)) for m in movers(9, src="a")]
real, counts = ca.json.loads, []
for ls in (short, lines):
    open(os.environ["CC_UTIL_LOG"], "w").writelines(ls)
    n = [0]
    ca.json.loads = lambda *a, **k: (n.__setitem__(0, n[0] + 1), real(*a, **k))[1]
    del GLOBS[:]
    rc, plan = place({"a": {}, "b": {}, "c": {}}, {"a": 0, "b": 0, "c": 0}, mv)
    ca.json.loads = real
    assert rc == 0 and GLOBS == [], (rc, GLOBS[:3])
    counts.append(n[0])
print("json.loads 20d=%d 60d=%d lines=%d/%d" % (counts[0], counts[1], len(short), len(lines)))
assert counts[0] == counts[1], counts
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}
