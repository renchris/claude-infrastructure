#!/usr/bin/env bats
# claude-accounts — collect() sweeps the accounts CONCURRENTLY (backlog a5b39138e098).
#
# collect() used to walk cfg["accounts"] in a serial for-loop, so a sweep cost the SUM of four
# network round trips plus a transcript-mtime walk. The fan-out is a ThreadPoolExecutor over
# probe_account plus working_concurrency as an independent 5th task. Every case below pins one
# thing the fan-out either wins or would have BROKEN — the second kind is the point: three of
# these five are latent-race fixes that were harmless only while the loop was serial.
#
# Technique: import the module extensionless (it is __main__-guarded, so importing runs no CLI)
# and stub the world as module attributes — they resolve through module globals at call time, so
# worker threads see the stubs exactly as the main thread does.
#
# HERMETICITY: LOG_PATH and the two ledger paths resolve at import from $HOME. Every case
# redirects all three into BATS_TEST_TMPDIR before touching a code path that writes — the 429
# case exists precisely to add a log_event() call site, and an unredirected one would append
# fabricated "429 poll-throttled" lines to the REAL fleet log.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # $HOME is fixtured BEFORE anything imports the module: CFG_PATH, LASTGOOD_PATH and LOG_PATH
  # all resolve from it at import time, so an unfixtured run reads the live fleet's accounts.json
  # and writes the live log. The three explicit pins below are belt-and-braces on top, not a
  # substitute — CFG_PATH is bound at import and cannot be re-pointed afterwards.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_LOG="$BATS_TEST_TMPDIR/claude-accounts.log"
  export CA_LEDGER="$BATS_TEST_TMPDIR/lastgood.json"
  export CA_REJECTED="$BATS_TEST_TMPDIR/rejected.json"
}

# The shared preamble: import + pin every path that would otherwise reach $HOME.
_pre() {
  cat <<'PY'
import importlib.machinery, importlib.util, json, os, threading, time
_ld = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", _ld))
_ld.exec_module(ca)
ca.LOG_PATH = os.environ["CA_LOG"]
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca._rejected_path = lambda: os.environ["CA_REJECTED"]

def mkcfg(n=4):
    return {"keychain_account": "test", "usage_endpoint": "http://127.0.0.1:9/never",
            "user_agent": "test",
            "frontier": {"scoped_display_name": "Fable"},
            "accounts": [{"name": f"a{i}", "config_dir": f"/tmp/ca-nonexistent-{i}",
                          "launcher": f"l{i}", "email": f"a{i}@example.com",
                          "dia_profile": f"P{i}"} for i in range(n)]}
PY
}

# ---- the win: the probes actually run at the same time, and order survives -------------------

@test "collect: N probes run CONCURRENTLY and executor.map preserves config row order" {
  run python3 -c "$(_pre)"'
cfg = mkcfg(4)
DELAY = 0.8
# Descending delays: under as_completed the fastest account would finish first and rows would
# come back REVERSED. This is what pins map() over as_completed, not just "it is parallel".
# They also set the serial floor, and it is the SUM of the descending delays — 2.5 x DELAY =
# 2.0s — NOT 4 x DELAY. Sized as 4 x DELAY this bound was 1.8s against a 1.5s serial arm, so
# the case passed against the pre-fix tree: a vacuous green that only the red-proof caught.
delays = {"a0": DELAY, "a1": DELAY * 0.75, "a2": DELAY * 0.5, "a3": DELAY * 0.25}
def fake_probe(cfg, acct, kc, k, ledger, prev, no_heal):
    time.sleep(delays[acct["name"]])
    return {"acct": acct["name"], "auth": "ok"}, None
ca.probe_account = fake_probe
ca.concurrency = lambda cfg: {a["name"]: 0 for a in cfg["accounts"]}
ca.working_concurrency = lambda cfg, window_min=None, budget_s=None: None

t = time.monotonic()
rows = ca.collect(cfg, no_heal=True)
wall = time.monotonic() - t

assert [r["acct"] for r in rows] == ["a0", "a1", "a2", "a3"], [r["acct"] for r in rows]
# The bound sits in the GAP, not on either bench: serial cannot beat 2.0s, concurrent is ~0.85s.
assert wall < 1.4, f"collect took {wall:.2f}s — serial floor is {2.5 * DELAY:.1f}s"
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "collect: working_concurrency is co-scheduled as a 5th task, not a serial prefix" {
  run python3 -c "$(_pre)"'
cfg = mkcfg(4)
DELAY = 0.6
def fake_probe(cfg, acct, kc, k, ledger, prev, no_heal):
    time.sleep(DELAY)
    return {"acct": acct["name"], "auth": "ok"}, None
ca.probe_account = fake_probe
ca.concurrency = lambda cfg: {a["name"]: 0 for a in cfg["accounts"]}
# The single largest term in the pre-fix sweep (865ms measured) and NOT consumed inside the
# loop — its result is attached after each probe returns. If it stays a prefix, the sweep costs
# DELAY + DELAY; co-scheduled it costs max(DELAY, DELAY).
def slow_walk(cfg, window_min=None, budget_s=None):
    time.sleep(DELAY)
    return {a["name"]: 7 for a in cfg["accounts"]}
ca.working_concurrency = slow_walk

t = time.monotonic()
rows = ca.collect(cfg, no_heal=True)
wall = time.monotonic() - t

assert all(r["k_work"] == 7 for r in rows), rows          # the census still lands on every row
assert wall < 1.1, f"collect took {wall:.2f}s — walk was serialised behind the probes"
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

# ---- the races the fan-out would otherwise have created --------------------------------------

@test "_save_rejected: two concurrent savers use DISTINCT temp files (pid alone is not unique)" {
  run python3 -c "$(_pre)"'
# Deterministic by construction, not by luck: os.replace is spied and BARRIERED, so both threads
# are provably inside the write window together. Pre-fix both compute the same "<path>.<pid>.tmp"
# — the second open(...,"w") truncates the first, one replace moves it and the other raises
# FileNotFoundError straight into _save_rejected"s OSError swallow, i.e. it corrupts SILENTLY.
seen, real_replace = [], os.replace
bar = threading.Barrier(2, timeout=10)
def spy(src, dst):
    seen.append(src)
    bar.wait()
    return real_replace(src, dst)
os.replace = spy
ths = [threading.Thread(target=ca._save_rejected, args=({f"a{i}": {"rt": str(i)}},))
       for i in range(2)]
for t in ths: t.start()
for t in ths: t.join(timeout=15)
os.replace = real_replace

assert len(seen) == 2, seen
assert len(set(seen)) == 2, f"both savers shared one temp path: {seen}"
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "_mark_rejected: the lock spans load->mutate->save, so a concurrent mark is not lost" {
  run python3 -c "$(_pre)"'
# The lost update lives in the GAP between the read and the write, so guarding only the save
# would still lose a record. Barriered inside _load_rejected: pre-fix both threads read the same
# empty ledger and the last writer replays it (final file holds 1 record); post-fix the lock
# means thread 2 cannot even reach the load until thread 1 has saved (its barrier wait simply
# times out), so it reads 1 record and writes 2.
real_load = ca._load_rejected
bar = threading.Barrier(2, timeout=1.0)
def slow_load():
    d = real_load()
    try:
        bar.wait()
    except threading.BrokenBarrierError:
        pass
    return d
ca._load_rejected = slow_load

ths = [threading.Thread(target=ca._mark_rejected, args=(f"a{i}", f"tok{i}", "invalid_grant"))
       for i in range(2)]
for t in ths: t.start()
for t in ths: t.join(timeout=15)

led = json.load(open(os.environ["CA_REJECTED"]))
assert sorted(led) == ["a0", "a1"], f"a concurrent mark was lost: {sorted(led)}"
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

# ---- the instrument the fan-out is unshippable without ----------------------------------------

@test "probe_account: a 429 emits a log_event — the throttle branch was previously silent" {
  run python3 -c "$(_pre)"'
# The fan-out does not raise the PER-TOKEN request rate, but it does compress four requests from
# ~1.35s of self-staggering into ~0ms — so if the endpoint throttles by IP or org rather than by
# token, this change is what discovers it. Pre-fix the 429 branch emitted nothing at all, and
# the production log held zero throttle lines in 5,413 — a null from a blind instrument, not an
# absence. This case is the instrument.
cfg = mkcfg(1)
acct = cfg["accounts"][0]
ca.read_creds = lambda cd, kc: ({"accessToken": "tok",
                                 "expiresAt": (time.time() + 3600) * 1000}, "present")
ca.fetch_usage = lambda cfg, token, retries=2: (429, {})

row, entry = ca.probe_account(cfg, acct, "kc", 0, {}, None, True)
assert row.get("poll_throttled") is True, row
assert entry is None
log = open(os.environ["CA_LOG"]).read()
assert "429 poll-throttled" in log, f"throttle branch is silent; log={log!r}"
assert acct["name"] in log, log
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

# ---- the lazy globals that must not be built by four threads at once --------------------------

@test "collect: _ssl_warm builds SSL_CTX + the urllib opener on the MAIN thread before fan-out" {
  run python3 -c "$(_pre)"'
# On macOS build_opener() reaches getproxies_macosx_sysconf (a SystemConfiguration FFI call);
# a concurrent FIRST build of it is the least-audited path in the fan-out, so it is never done
# concurrently. fetch_usage is stubbed here, so NOTHING but the pre-warm can set these — which
# is exactly what makes the assertion discriminating.
import urllib.request
cfg = mkcfg(2)
ca.SSL_CTX = None
urllib.request._opener = None
ca.probe_account = lambda *a, **k: ({"acct": a[1]["name"], "auth": "ok"}, None)
ca.concurrency = lambda cfg: {a["name"]: 0 for a in cfg["accounts"]}
ca.working_concurrency = lambda cfg, window_min=None, budget_s=None: None

ca.collect(cfg, no_heal=True)
assert ca.SSL_CTX is not None, "SSL_CTX was left for the worker threads to race"
assert urllib.request._opener is not None, "urllib opener was left for the worker threads"
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}
