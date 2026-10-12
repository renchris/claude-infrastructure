#!/usr/bin/env bats
# claude-accounts — the native (libproc) live-session census and the router charge that reads it.
# docs/plans/ACCOUNTS_BOARD_FRESHNESS.md D1-D2 (W1).
#
# THE INCIDENT (2026-10-11 22:32-22:34Z). `ps -wwEo` (2.43 MB of argv+env) timed out three sweeps
# running at load 400-780, inherit_k's carried census aged past its 600 s grace, every row went
# `concurrency-unmeasured`, and the launcher fell back to its pinned account. One census serves all
# four accounts, so a starved ps is fleet-wide by construction. The native census reads argv only
# for claude-shaped processes (354 ms against ps's 9,285 ms, same pid set) and the router may charge
# it as k_src=panes-native — while row["k"] and heal's k_live stay ps-only until the Phase 3 soak.
#
# Hermetic: scratch SSOT, HOME, logs, util/assign/route stores and local dir under BATS_TEST_TMPDIR.
# The libproc lister, argv reader and path reader are stubbed through their seams in every case
# that asserts a verdict, so nothing here depends on what is running on the box.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_SSOT="$REPO/accounts.json"
  export T="$BATS_TEST_TMPDIR"
  export H="$T/home"
  export HOME="$H"
  mkdir -p "$H/.claude-a1" "$H/.claude-a2" "$H/.claude/logs" "$T/local" "$T/route"
  export CA_CFG="$T/accounts.json"
  export CACHE="$T/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$T/lastgood.json"
  export CLAUDE_ACCOUNTS_LOG="$T/claude-accounts.log"
  export CC_UTIL_LOG="$T/util.jsonl"
  export CC_ASSIGN_LOG="$T/assign.jsonl"
  export CC_ROUTE_RECORDS_DIR="$T/route"
  export CC_ACCOUNTS_LOCAL_DIR="$T/local"
  unset CC_ACCOUNTS_CENSUS
  python3 - <<'PY'
import json, os
T, r = os.environ["T"], json.load(open(os.environ["CA_SSOT"]))
H = os.environ["H"]
# DERIVED from the real SSOT, never hand-copied — and deliberately WITHOUT the top-level `census`
# key, so the fixture runs the code default ('ps') unless a case opts in.
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": os.path.join(T, "mc.yaml"), "dia_local_state": "/nonexistent/LS",
  "cache_file": os.path.join(T, "cache.json"),
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [{"name": "a1", "config_dir": os.path.join(H, ".claude-a1"), "launcher": "c1"},
               {"name": "a2", "config_dir": os.path.join(H, ".claude-a2") + "/", "launcher": "c2"},
               {"name": "next", "config_dir": os.path.join(H, ".claude-next"), "launcher": "c"}],
}, open(os.path.join(T, "accounts.json"), "w"))
PY
}

LOAD='
import importlib.machinery, importlib.util, os, json, time, subprocess
from datetime import datetime, timezone
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.environ["CLAUDE_ACCOUNTS_LOG"]
ca.HOME = os.environ["H"]
os.environ["HOME"] = os.environ["H"]
cfg = ca.load_cfg(need_claude_bin=False)
H = os.environ["H"]
def proc_world(procs, argv):
    """Stub the three libproc seams: procs = [{pid, comm, start}], argv = {pid: (argv, env)}."""
    ca._native_proc_entries = lambda: (len(procs) + 100, procs)
    ca._native_procargs = lambda pid: argv.get(pid)
    ca._native_pidpath = lambda pid: ""
'

@test "parity: ps-form and procargs-form lines classify to the identical census" {
  run python3 -c "$LOAD"'
A1, A2 = os.path.join(H, ".claude-a1"), os.path.join(H, ".claude-a2")
procs = [
  (101, ["/x/claude.exe", "--agent-id", "tm@team"], ["HOME=" + H, "CLAUDE_CONFIG_DIR=" + A1]),
  (102, ["claude", "bg-spare"], ["HOME=" + H, "CLAUDE_CONFIG_DIR=" + A1]),
  (103, ["claude", "-p", "hello"], ["HOME=" + H, "CLAUDE_CONFIG_DIR=" + A1]),
  (104, ["claude", "--version"], ["HOME=" + H, "CLAUDE_CONFIG_DIR=" + A1]),
  (105, ["/u/.local/bin/claude"], ["HOME=" + H]),                          # no config dir -> next
  (106, ["claude", "--resume", "679b6547-65ed-4a8d-9735-067e250f935b"],
        ["HOME=" + H, "CLAUDE_CONFIG_DIR=" + A2]),                         # trailing-slash key
  (107, ["claude"], ["HOME=" + H, "CLAUDE_CONFIG_DIR=~/.claude-a2"]),      # ~ vs process HOME
  (108, ["zsh"], ["HOME=" + H, "CLAUDE_CONFIG_DIR=" + A1]),                # not claude-shaped
]
ps_lines = [(f"{p} " + " ".join(a + e), None) for p, a, e in procs]
native = [(f"{p} " + " ".join(a + e), H) for p, a, e in procs]
c1 = ca._census_from_lines(cfg, ps_lines, reg={})
c2 = ca._census_from_lines(cfg, native, reg={})
for f in ("headless", "live_sids", "unknown", "attributed"):
    assert getattr(c1, f) == getattr(c2, f), (f, getattr(c1, f), getattr(c2, f))
assert dict(c1) == dict(c2) == {"a1": 2, "a2": 2, "next": 1}, (dict(c1), dict(c2))
assert c1.headless == {"a1": 1, "a2": 0, "next": 0}, c1.headless
assert c1.live_sids["a2"] == {"679b6547-65ed-4a8d-9735-067e250f935b"}, c1.live_sids
assert 104 not in c1.attributed and 108 not in c1.attributed
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "hermeticity: a process whose own HOME differs is never attributed through the ~/.claude mirror" {
  run python3 -c "$LOAD"'
other = os.path.join(os.environ["T"], "elsewhere")
c = ca._census_from_lines(cfg, [("201 claude", other), ("202 claude", H),
                                ("203 claude CLAUDE_CONFIG_DIR=~/.claude-a1", other)], reg={})
assert dict(c) == {"a1": 0, "a2": 0, "next": 1}, dict(c)
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "native census: counts via the seams, per-process HOME, meta carries as_of and timings" {
  run python3 -c "$LOAD"'
A1 = os.path.join(H, ".claude-a1")
proc_world([{"pid": 301, "comm": "claude", "start": 1000}, {"pid": 302, "comm": "zsh", "start": 1000},
            {"pid": 303, "comm": "node", "start": 1000}],
           {301: (["claude"], ["HOME=" + H, "CLAUDE_CONFIG_DIR=" + A1]),
            303: (["node", "/x/cli.js"], ["HOME=" + H])})
t0 = time.time()
n = ca.native_census(cfg)
assert n is not None, ca._NATIVE_META
# 303 is READ (node passes the prefilter) but not counted: argv[0] `node` is rejected by the
# shared classifier exactly as ps rejects it — parity, not a native-only rule
assert dict(n) == {"a1": 1, "a2": 0, "next": 0}, dict(n)
m = n.meta
assert m["reason"] is None and m["tty_pop"] == 3 and m["reads"] == 2, m
assert t0 - 1 <= n.as_of <= time.time(), (t0, n.as_of)
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "native census fails CLOSED with a named reason on every unproven population" {
  run python3 -c "$LOAD"'
def why():
    return ca._NATIVE_META["reason"]
def boom():
    raise ca._NativeUnavailable("libproc-load:OSError")
ca._native_proc_entries = boom
assert ca.native_census(cfg) is None and why() == "libproc-load:OSError", why()
ca._native_proc_entries = lambda: (0, [])
assert ca.native_census(cfg) is None and why() == "listallpids-empty", why()
ca._native_proc_entries = lambda: (400, [])
assert ca.native_census(cfg) is None and why() == "tty-pop-0", why()
# CPU over budget: a clock that advances 2 s per read
proc_world([{"pid": 401, "comm": "claude", "start": 1}], {401: (["claude"], ["HOME=" + H])})
tick = iter(range(0, 1000, 2))
ca._native_cpu_clock = lambda: float(next(tick))
assert ca.native_census(cfg) is None and why() == "cpu-budget", why()
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "registry: a pid the prefilter misses is gap-filled; an unattributed live one trips the canary" {
  run python3 -c "$LOAD"'
A1 = os.path.join(H, ".claude-a1")
me, start = os.getpid(), 5000            # a pid that is genuinely alive, so os.kill(pid, 0) passes
os.makedirs(os.path.join(A1, "sessions"), exist_ok=True)
json.dump({"pid": me, "sessionId": "s-1", "entrypoint": "cli", "startedAt": (start + 3) * 1000},
          open(os.path.join(A1, "sessions", f"{me}.json"), "w"))
# comm is a version string and the path names no claude: only the registry can find it
procs = [{"pid": me, "comm": "2.1.293", "start": start}]
# invoked through the `claude` symlink, so argv[0] is claude while comm is the version file
proc_world(procs, {me: (["claude", "--resume", "s-1"], ["HOME=" + H, "CLAUDE_CONFIG_DIR=" + A1])})
n = ca.native_census(cfg)
assert n is not None and n["a1"] == 1, (ca._NATIVE_META, n)
# the same live registered session, but its argv is not claude-shaped: the scan is blind to it
proc_world(procs, {me: (["/v/2.1.293"], ["HOME=" + H])})
assert ca.native_census(cfg) is None and ca._NATIVE_META["reason"] == "registry-canary"
assert "registry canary" in open(ca.LOG_PATH).read()
# start time not matching (pid reused) or sdk-cli: not the canary business
proc_world([{"pid": me, "comm": "2.1.293", "start": start + 5000}], {me: (["/v/x"], ["HOME=" + H])})
assert ca.native_census(cfg) is not None, ca._NATIVE_META
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "mode: ps by default; the census-ps sentinel and CC_ACCOUNTS_CENSUS=ps force ps; ab runs both" {
  run python3 -c "$LOAD"'
calls = []
ca._native_census = lambda c: (calls.append(1), (None, {"reason": "stub"}))[1]
class R:
    stdout = "501 claude CLAUDE_CONFIG_DIR=" + os.path.join(H, ".claude-a1") + "\n"
ca.subprocess.run = lambda *a, **k: R()
assert ca._census_mode(cfg) == "ps"
ca._NATIVE_LAST = None
assert dict(ca.concurrency(cfg))["a1"] == 1 and calls == [] and ca._NATIVE_LAST is None
cfg["census"] = "ab"
assert ca._census_mode(cfg) == "ab"
ca.concurrency(cfg)
assert calls == [1], calls
assert "census-ab: ps={a1:1,a2:0,next:0} native=None(stub) agree=n/a" in open(ca.LOG_PATH).read()
open(os.path.join(os.environ["CC_ACCOUNTS_LOCAL_DIR"], "census-ps"), "w").close()
assert ca._census_mode(cfg) == "ps"
os.remove(os.path.join(os.environ["CC_ACCOUNTS_LOCAL_DIR"], "census-ps"))
os.environ["CC_ACCOUNTS_CENSUS"] = "ps"
assert ca._census_mode(cfg) == "ps"
# the READER rollback: with the env set, a fresh cached k_native is never charged
r = {"acct": "a1", "k": None, "k_work": None, "k_native": 3, "k_native_as_of": time.time()}
assert ca.k_src(r) == "unmeasured" and ca.k_panes(r) is None
del os.environ["CC_ACCOUNTS_CENSUS"]
assert ca.k_src(r) == "panes-native" and ca.k_panes(r) == 3 and ca.k_shown(r) == "3"
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "k_panes: native displaces ps only when ps is absent or native is 60 s newer, and only in grace" {
  run python3 -c "$LOAD"'
now = time.time()
r = {"acct": "a1", "k": 2, "k_as_of": now - 30, "k_native": 5, "k_native_as_of": now - 10}
assert ca.k_panes(r) == 2 and ca.k_src(r) == "panes"            # 20 s newer: ps stands
r["k_as_of"] = now - 100
assert ca.k_panes(r) == 5 and ca.k_src(r) == "panes-native"     # 90 s newer: native
r["k_as_of"] = None
assert ca.k_panes(r) == 2                                       # ps with no stamp: ps stands
r = {"acct": "a1", "k": None, "k_native": 4, "k_native_as_of": now - 700}
assert ca.k_panes(r) is None and ca.k_src(r) == "unmeasured" and ca.k_shown(r) == "?"
r["k_native_as_of"] = now + 30                                  # future stamp = skew, refused
assert ca.k_panes(r) is None
# a native count beats an inherited one, and is shown unstarred
r = {"acct": "a1", "k": None, "k_stale": 9, "k_stale_as_of": datetime.fromtimestamp(
     now - 60, timezone.utc).isoformat(), "k_native": 4, "k_native_as_of": now - 5}
assert ca.k_panes(r) == 4 and ca.k_shown(r) == "4"
assert ca.k_cap(r, cfg["router"]) == cfg["router"].get("KMAX_RESIDENT", ca.KMAX_RESIDENT_DEFAULT)
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "inherit_k dates a measured previous k by k_as_of, not by the sweep ts (with its mutant)" {
  run python3 -c "$LOAD"'
src = open(os.environ["CA_BIN"]).read()
needle = "elif _as_epoch(pr.get(\"k_as_of\")) is not None:"
assert src.count(needle) == 1
mut = importlib.util.module_from_spec(importlib.util.spec_from_loader("mut", loader=None))
exec(compile(src.replace(needle, "elif False:"), "mut", "exec"), mut.__dict__)
now = time.time()
prev = {"ts": now - 100, "rows": {"a1": {"k": 3, "k_as_of": now - 700}}}
for mod, want in ((ca, False), (mut, True)):
    row = {"acct": "a1", "k": None}
    assert mod.inherit_k(row, prev, now=now) is want, (mod.__name__, row)
prev["rows"]["a1"]["k_as_of"] = now - 100
row = {"acct": "a1", "k": None}
assert ca.inherit_k(row, prev, now=now) and row["k_stale"] == 3
assert abs(ca._as_epoch(row["k_stale_as_of"]) - (now - 100)) < 1, row
# the snapshot carries the stamp inherit_k now needs
json.dump({"ts": now, "cfg_key": ca._cfg_key(cfg), "rows": [{"acct": "a1", "k": 1, "k_as_of": now - 5}]},
          open(cfg["cache_file"], "w"))
assert ca._prev_snapshot(cfg)["rows"]["a1"]["k_as_of"] == now - 5
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "collect: a stubbed concurrency leaves _NATIVE_LAST None, so no k_native appears" {
  run python3 -c "$LOAD"'
ca.concurrency = lambda c: {"a1": 1, "a2": 0, "next": 0}
ca.working_concurrency = lambda c, **k: None
ca.watch_resets = lambda rows: None
ca._ssl_warm = lambda: None
ca.probe_account = lambda c, acct, kc, k_live, ledger, prev, no_heal: (
    {"acct": acct["name"], "k": k_live, "auth": "ok"}, None)
rows = ca.collect(cfg)
assert all("k_native" not in r for r in rows) and ca._NATIVE_LAST is None, rows
assert all(isinstance(r.get("k_as_of"), float) for r in rows), rows
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "17:33 shape: ps times out, no k_stale, native counts — the fleet routes on panes-native" {
  # The incident end to end, through the real binary for the route. ps TimeoutExpired + no
  # inheritable census used to be concurrency-unmeasured on every row and a DATA exit 3.
  python3 -c "$LOAD"'
os.environ["CC_ACCOUNTS_CENSUS"] = "ab"
real_run = subprocess.run
def fake_run(argv, *a, **k):
    if argv and argv[0] == "ps":
        raise subprocess.TimeoutExpired(argv, 10)
    return real_run(argv, *a, **k)
ca.subprocess.run = fake_run
nat = ca._Census({"a1": 1, "a2": 2, "next": 0}, headless={"a1": 0, "a2": 0, "next": 0},
                 live_sids={"a1": set(), "a2": set(), "next": set()},
                 unknown={"a1": 1, "a2": 2, "next": 0}, attributed=set())
nat.as_of = time.time()
nat.meta = {"as_of": nat.as_of, "ms": 40, "cpu_ms": 30, "reason": None, "tty_pop": 9, "reads": 3}
ca._native_census = lambda c: (nat, nat.meta)
ca.working_concurrency = lambda c, **k: None
ca.watch_resets = lambda rows: None
ca._ssl_warm = lambda: None
seen = {}
def probe(c, acct, kc, k_live, ledger, prev, no_heal):
    seen[acct["name"]] = k_live
    wk = {"a1": 3, "a2": 40, "next": 60}[acct["name"]]
    return ({"acct": acct["name"], "k": k_live, "auth": "ok", "session_pct": 10,
             "session_reset_h": 3.0, "weekly_pct": wk, "weekly_reset_h": 50.0, "fable_pct": 10,
             "fable_reset_h": 24.0, "credits_on": False}, None)
ca.probe_account = probe
rows = ca.collect(cfg)
assert seen == {"a1": None, "a2": None, "next": None}, seen          # heal sees k_live None
assert all(r["k"] is None and "k_stale" not in r for r in rows), rows
assert [r["k_native"] for r in rows] == [1, 2, 0], rows
assert all(ca.k_src(r) == "panes-native" for r in rows)
log = open(ca.LOG_PATH).read()
assert "census-ab: ps=UNAVAILABLE native={a1:1,a2:2,next:0} agree=n/a" in log, log
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None, "rows": rows}, open(cfg["cache_file"], "w"))
'
  run bash -c "python3 '$CA_BIN' --route interactive --max-wait 0 --max-age 600 2>/dev/null"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = a1 ]
  run bash -c "python3 '$CA_BIN' --route interactive --max-wait 0 --max-age 600 2>&1 >/dev/null"
  [[ "$output" == *"k_src=panes-native"* ]] || { echo "$output"; false; }
  [[ "$output" == *"k_native_s="[0-9]* ]] || { echo "$output"; false; }
  [[ "$output" == *"k=-"* ]] || { echo "$output"; false; }
  run bash -c "python3 '$CA_BIN' --json --max-wait 0 --max-age 600 | jq -c '[.rows[].k]'"
  [ "$output" = "[null,null,null]" ] || { echo "$output"; false; }
  # MUTANT: without the native pick every row is unmeasured again — the abstention this closes.
  sed 's/^    kn = r.get("k_native")$/    kn = None/' "$CA_BIN" > "$T/mutant-ca"
  ! cmp -s "$CA_BIN" "$T/mutant-ca" || false
  run bash -c "python3 '$T/mutant-ca' --route interactive --max-wait 0 --max-age 600 2>&1"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *concurrency-unmeasured* ]] || { echo "$output"; false; }
}

@test "launch path: --rank/--route cache-only never import ctypes and open only the known set" {
  python3 -c "$LOAD"'
def r(n, wk):
    return {"acct": n, "auth": "ok", "k": 1, "k_as_of": time.time(), "k_work": None,
            "k_native": 1, "k_native_as_of": time.time(), "session_pct": 10,
            "session_reset_h": 3.0, "weekly_pct": wk, "weekly_reset_h": 50.0, "fable_pct": 10,
            "fable_reset_h": 24.0, "credits_on": False}
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None, "rows": [r("a1", 3), r("a2", 40), r("next", 50)]},
          open(cfg["cache_file"], "w"))
'
  printf '%s\n' '{"ts":"2026-10-11T00:00:00+00:00","acct":"a1","weekly_pct":1}' > "$CC_UTIL_LOG"
  cat > "$T/audit.py" <<'PY'
import sys, os, runpy, json
binp, args = sys.argv[1], sys.argv[2:]
opens, imports = set(), []
skip = tuple(p for p in {sys.prefix, sys.base_prefix, sys.exec_prefix} if p)
def hook(ev, a):
    if ev == "open" and isinstance(a[0], str):
        p = a[0]
        if not p.startswith(skip) and not p.endswith((".pyc", ".py", ".so")) \
                and os.path.realpath(p) != os.path.realpath(binp):
            opens.add(os.path.basename(p))
    elif ev == "import":
        imports.append(a[0])
sys.addaudithook(hook)
sys.argv = [binp] + args
try:
    runpy.run_path(binp, run_name="__main__")
except SystemExit:
    pass
sys.stdout.flush()
print("AUDIT " + json.dumps({"opens": sorted(opens),
                             "ctypes": "ctypes" in sys.modules or "ctypes" in imports}),
      file=sys.stderr)
PY
  run bash -c "python3 '$T/audit.py' '$CA_BIN' --rank interactive --max-wait 0 --max-age 600 2>&1 >/dev/null | grep AUDIT"
  [ "$output" = 'AUDIT {"opens": ["accounts.json", "assign.jsonl", "cache.json", "util.jsonl"], "ctypes": false}' ] || { echo "$output"; false; }
  run bash -c "python3 '$T/audit.py' '$CA_BIN' --route interactive --max-wait 0 --max-age 600 2>&1 >/dev/null | grep AUDIT"
  [ "$output" = 'AUDIT {"opens": ["accounts.json", "assign.jsonl", "cache.json", "route.jsonl", "util.jsonl"], "ctypes": false}' ] || { echo "$output"; false; }
}

@test "--census-ab-report: PASS, NOT-YET with the failing criterion, and the denominator" {
  python3 - <<'PY'
import os
from datetime import datetime, timedelta, timezone
T = os.environ["T"]
t0 = datetime(2026, 10, 1, tzinfo=timezone.utc)
ok = "census-ab: ps={a1:1,a2:2} native={a1:1,a2:2} agree=yes ps_ms=900 native_ms=40 native_cpu_ms=20"
with open(os.path.join(T, "pass.log"), "w") as f:
    for i in range(600):
        f.write(f"{(t0 + timedelta(minutes=20 * i)).isoformat()} {ok}\n")
    f.write(f"{(t0 + timedelta(days=8)).isoformat()} census-ab: ps=UNAVAILABLE native=None(tty-pop-0) agree=n/a ps_ms=10000 native_ms=5 native_cpu_ms=1\n")
    f.write(f"{(t0 + timedelta(days=8)).isoformat()} unrelated line\n")
with open(os.path.join(T, "short.log"), "w") as f:
    f.write(f"{t0.isoformat()} {ok}\n")
    f.write(f"{t0.isoformat()} census-ab: ps={{a1:1,a2:5}} native={{a1:1,a2:2}} agree=no ps_ms=1 native_ms=1 native_cpu_ms=1\n")
PY
  CLAUDE_ACCOUNTS_LOG="$T/pass.log" run "$CA_BIN" --census-ab-report
  [ "$status" -eq 0 ]
  [[ "$output" == *"ps-OK 600"* ]] || { echo "$output"; false; }
  [[ "$output" == *"600/600 ps-OK"* ]] || { echo "$output"; false; }
  [[ "$output" == *"tty-pop-0 1"* ]] || { echo "$output"; false; }
  [[ "${lines[-1]}" == "soak: PASS" ]] || { echo "$output"; false; }
  CLAUDE_ACCOUNTS_LOG="$T/short.log" run "$CA_BIN" --census-ab-report
  [[ "$output" == *"1/2 ps-OK"* ]] || { echo "$output"; false; }
  [[ "${lines[-1]}" == "soak: NOT-YET (window 0.0 d < 7 d; ps-OK 2 < 500; agreement 50.0% < 99%; max diff 3 > 1)" ]] || { echo "$output"; false; }
}

@test "record_utilization carries k_native; the replay re-dates it so panes-native replays as charged" {
  run python3 -c "$LOAD"'
p = os.environ["CC_UTIL_LOG"]
now = time.time()
ca.record_utilization([{"acct": "a1", "k": None, "k_work": None, "k_native": 2,
                        "k_native_as_of": now - 30, "session_pct": 5, "weekly_pct": 5}],
                      path=p, min_interval_s=0)
d = json.loads(open(p).read().splitlines()[-1])
assert d["k_native"] == 2 and d["k_native_as_of"] == now - 30 and d["k_src"] == "panes-native", d
import sys
sys.argv = ["x"]
rp = importlib.util.module_from_spec(importlib.util.spec_from_loader("rp",
     importlib.machinery.SourceFileLoader("rp", os.path.join(os.path.dirname(os.environ["CA_BIN"]),
                                                             "..", "scripts", "desk-strand-replay.py"))))
rp.__spec__.loader.exec_module(rp)
at = datetime.fromtimestamp(now - 20, timezone.utc)
row = rp.to_row(d, at)
assert row["k_native"] == 2 and ca.k_src(row) == "panes-native", row
assert abs((time.time() - row["k_native_as_of"]) - 10) < 2, row
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}

@test "ps: a killed ps that is never reaped cannot hold the sweep past PS_JOIN_S" {
  # Measured 2026-10-12: "timed out after 10 seconds", and the call returned after 1,226 s —
  # subprocess.run's post-kill wait() is unbounded. A run() that blocks stands in for that ps.
  run python3 -c "$LOAD"'
ca.PS_JOIN_S = 0.5
ca.subprocess.run = lambda *a, **k: time.sleep(5)
t0 = time.monotonic()
assert ca.concurrency(cfg) is None
assert time.monotonic() - t0 < 3, time.monotonic() - t0
assert "concurrency: ps UNAVAILABLE (TimeoutExpired" in open(ca.LOG_PATH).read()
print("OK")
'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]]
}
