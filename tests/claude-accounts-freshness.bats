#!/usr/bin/env bats
# claude-accounts — quota-cache freshness (docs/plans/QUOTA_CACHE_FRESHNESS.md).
#
# The 2026-10-01 incident: next4's banked reset was redeemed, every usage poll for five minutes was
# a 429, and every reader replayed "weekly 100%, server rejected" off the ledger, so a freshly reset
# account was treated as capped. Measured (docs/research/quota-cache-freshness-2026-10-01/): the 429
# budget is per token and sticky, so these tests pin (1) no in-call 429 retry, (2) one shared
# per-account backoff, (3) the wire as the substitute read, (4) only positive evidence clearing a
# stored rejection, and (5) a readout that never shows a pre-reset reading as current.
#
# Hermetic: the same scratch SSOT/ledger/cache harness as claude-accounts-throttle-admit.bats; the
# usage endpoint and the wire are stubbed, so nothing here touches the network.

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
  export CLAUDE_ACCOUNTS_LOG="$BATS_TEST_TMPDIR/claude-accounts.log"
  export YAML="$BATS_TEST_TMPDIR/model-config.yaml"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
  export CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
  export CC_ROUTE_RECORDS_DIR="$BATS_TEST_TMPDIR/route-records"
  unset CLAUDE_ACCOUNTS_THROTTLE_ADMIT_S CC_ACCOUNTS_USAGE_BACKOFF_S CC_ACCOUNTS_USAGE_429_RETRIES
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
import importlib.machinery, importlib.util, os, json, time, io, contextlib
from datetime import datetime, timedelta, timezone
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
cfg = json.load(open(os.environ["CA_CFG"]))
R = cfg["router"]
SCOPED = cfg["frontier"]["scoped_display_name"]
CALLS = {"usage": 0, "wire": 0}
def iso(dt_s):
    return (datetime.now(timezone.utc) + timedelta(seconds=dt_s)).isoformat()
def limits(session=5, weekly=30, fable=7, s_reset=None, w_reset=None):
    return [{"kind": "session", "percent": session, "resets_at": s_reset},
            {"kind": "weekly_all", "percent": weekly, "resets_at": w_reset},
            {"kind": "weekly_scoped", "percent": fable, "resets_at": None,
             "scope": {"model": {"display_name": SCOPED}}}]
def probe(status, lim=None, wire=None):
    """One collect(): the usage endpoint answers `status`, the wire answers `wire`. Counts calls."""
    ca.concurrency = lambda c: {"next3": 0}
    ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 9e12}, "present")
    def fu(*a, **k):
        CALLS["usage"] += 1
        return status, ({"limits": lim} if lim is not None else None)
    def fw(*a, **k):
        CALLS["wire"] += 1
        return wire
    ca.fetch_usage = fu
    ca.fetch_wire_limits = fw
    return ca.collect(cfg, no_heal=True)[0]
def ledger():
    return json.load(open(os.environ["CA_LEDGER"]))
def edit_ledger(**kv):
    led = ledger()
    led["next3"].update(kv)
    json.dump(led, open(os.environ["CA_LEDGER"], "w"))
def pollstate():
    try:
        return json.load(open(ca._sidecar(".pollstate.json")))
    except OSError:
        return {}
def log():
    try:
        return open(os.environ["CLAUDE_ACCOUNTS_LOG"]).read()
    except OSError:
        return ""
WALL = {"7d_util": 1.0, "7d_status": "rejected", "5h_util": 0.02, "5h_status": "allowed",
        "status": "rejected", "http": 429}
RESET = {"7d_util": 0.0, "7d_status": "allowed", "5h_util": 0.01, "5h_status": "allowed",
         "status": "allowed", "http": 200}
def at_wall_good_read():
    """The last good read before the incident: weekly 100, server rejects 7d (stored)."""
    ca.WIRE_FORCE = True
    g = probe(200, limits(session=2, weekly=100, fable=10, w_reset=iso(2.5 * 86400)), WALL)
    ca.WIRE_FORCE = False
    assert ledger()["next3"].get("wire_rejects") == ["7d"], ledger()
    return g
'

@test "F-1: a 429 is not retried in-call by default; the knob restores retries" {
  run python3 -c "$LOAD"'
import urllib.error
n = {"c": 0}
def boom(*a, **k):
    n["c"] += 1
    raise urllib.error.HTTPError("u", 429, "throttled", {}, io.BytesIO(b"{}"))
ca.urllib.request.urlopen = boom
ca.time.sleep = lambda s: None
assert ca.fetch_usage({"usage_endpoint": "http://x"}, "t")[0] == 429
assert n["c"] == 1, n
os.environ["CC_ACCOUNTS_USAGE_429_RETRIES"] = "2"
n["c"] = 0
ca.fetch_usage({"usage_endpoint": "http://x"}, "t")
assert n["c"] == 3, n
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "F-2: one shared backoff — a 429 holds every later poll of that account, doubles, and clears on success" {
  run python3 -c "$LOAD"'
probe(200, limits(weekly=30))
r = probe(429)
st = pollstate()["next3"]
assert st["streak"] == 1 and 170 <= st["until"] - time.time() <= 181, st
assert CALLS["usage"] == 2
r = probe(200, limits(weekly=31))                  # inside the backoff: NOT polled
assert CALLS["usage"] == 2, CALLS
assert r.get("poll_throttled") and r.get("usage_held_s", 0) > 0 and r["weekly_pct"] == 30, r
assert "usage poll held" in log()
d = pollstate(); d["next3"]["until"] = time.time() - 1
json.dump(d, open(ca._sidecar(".pollstate.json"), "w"))
probe(429)                                         # expired, polled again, 429 again
st = pollstate()["next3"]
assert CALLS["usage"] == 3 and st["streak"] == 2 and 350 <= st["until"] - time.time() <= 361, st
assert ca.usage_backoff_s(9) == 600, "capped"
d = pollstate(); d["next3"]["until"] = time.time() - 1
json.dump(d, open(ca._sidecar(".pollstate.json"), "w"))
r = probe(200, limits(weekly=32))
assert "next3" not in pollstate() and r["weekly_pct"] == 32 and not r.get("stale_quota"), r
os.environ["CC_ACCOUNTS_USAGE_BACKOFF_S"] = "0"     # off: every call polls
probe(429); probe(429)
assert CALLS["usage"] == 6, CALLS
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "F-3: the incident — throttled after a redemption, the wire says allowed: post-reset figures, rejection dropped, routable" {
  run python3 -c "$LOAD"'
at_wall_good_read()
edit_ledger(quota_as_of=iso(-166))                 # 20:14:06 → 20:16:52
r = probe(429, wire=RESET)
assert CALLS["wire"] == 2, CALLS                   # one in the good read, one substitute
assert r.get("wire_substitute") and "lastgood_wire_rejects" not in r, r
assert r["weekly_pct"] == 0 and "weekly" in r["rolled_since"], r
assert any("server now allows 7d" in e for e in r["reset_evidence"]), r["reset_evidence"]
assert any("server reads weekly at 0%" in e for e in r["reset_evidence"]), r["reset_evidence"]
assert r["fable_pct"] is None and r.get("fable_unread"), "a 166 s-old Fable figure is withheld"
assert ca._excluded(r, R) is None, ca._excluded(r, R)
score, reason = ca.score_general(r, cfg)
assert reason is None and score > 0, (score, reason)
assert "wire-admitted" in log() and "wire substitute" in log(), log()
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "F-4: fail-safe — the wire still rejects, misses, or is stale: the row stays refused" {
  run python3 -c "$LOAD"'
at_wall_good_read()
edit_ledger(quota_as_of=iso(-166))
r = probe(429, wire=WALL)                          # still rejected
assert r.get("lastgood_wire_rejects") == ["7d"], r
assert (ca._excluded(r, R) or "").startswith("poll throttled"), ca._excluded(r, R)
r = probe(429, wire=None)                          # held + wire miss
assert r.get("wire_miss") and r.get("lastgood_wire_rejects") == ["7d"], r
assert (ca._excluded(r, R) or "").startswith("poll throttled")
r = probe(429, wire=RESET)
assert ca.wire_admissible(r)
r["wire_at"] = iso(-200)                           # a served cache aged past the bound
assert not ca.wire_admissible(r) and (ca._excluded(r, R) or "").startswith("poll throttled")
r = probe(429, wire=dict(RESET, **{"5h_status": None}))
assert not ca.wire_admissible(r), "a missing status is not an allowed one"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "F-5: a passed weekly stamp drops the stored 7d rejection, but with no new read the meter stays unknown and refused" {
  run python3 -c "$LOAD"'
at_wall_good_read()
edit_ledger(weekly_reset_at=iso(-60), quota_as_of=iso(-3600))
r = probe(429, wire=None)
assert r["weekly_pct"] is None and r["rolled_since"] == ["weekly"], r
assert "lastgood_wire_rejects" not in r, "the reset voided the verdict"
assert "weekly window reset at" in r["reset_evidence"][0], r["reset_evidence"]
assert CALLS["wire"] == 2, "a reset since the reading is worth a substitute read"
assert ca._excluded(r, R) is not None, "unknown is refused, not admitted"
assert ca.reset_evidence_pending(cfg) == ["next3"], "no cache: the evidence is pending"
json.dump({"ts": time.time() - 120}, open(cfg["cache_file"], "w"))
assert ca.reset_evidence_pending(cfg) == ["next3"], "a cache written BEFORE the reset is stale"
json.dump({"ts": time.time()}, open(cfg["cache_file"], "w"))
assert ca.reset_evidence_pending(cfg) == [], "a cache written after it already carries it"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "F-6: no flag — a banked reset under a throttled usage poll is detected by the wire, routes on ~0, and is logged once; --reset-report summarises" {
  run python3 -c "$LOAD"'
import subprocess
at_wall_good_read()                                # usage reads weekly 100: the watch arms
edit_ledger(quota_as_of=iso(-166))
r = probe(429, wire=RESET)                         # usage 429 + wire HTTP 200, 7d_util 0, allowed
assert r["weekly_pct"] == 0 and "lastgood_wire_rejects" not in r, r
assert ca._excluded(r, R) is None, ca._excluded(r, R)
score, reason = ca.score_general(r, cfg)
assert reason is None and score > 0, (score, reason)
def events():
    try:
        return [json.loads(l) for l in open(ca.RESET_LOG_PATH)]
    except OSError:
        return []
ev = events()
assert len(ev) == 1, ev
e = ev[0]
assert (e["acct"], e["window"], e["kind"], e["channel"]) == ("next3", "7d", "unscheduled", "wire"), e
assert e["from_pct"] == 100 and e["to_pct"] == 0 and 0 <= e["lag_s"] < 60, e
assert e["throttled_polls_between"] == 1 and e["wire_attempts_between"] == 1, e
for k in ("ts", "stale_since", "detected_at"):
    assert e.get(k), (k, e)
probe(429, wire=RESET)                             # the same reset, read again: no second line
probe(429, wire=None)                              # an inherited figure is not a reading either
assert len(events()) == 1, events()
# A scheduled reset read by the usage endpoint: the 5h sits at 100 until its stamp passes.
d = ca._load_pollstate(); d.pop("next3", None); ca._save_pollstate(d)
probe(200, limits(session=100, weekly=0, s_reset=iso(3600), w_reset=iso(2.5 * 86400)))
st = json.load(open(ca._sidecar(".resetwatch.json")))
st["next3"]["5h"].update(reset_at=iso(-30), stale_since=iso(-90))
json.dump(st, open(ca._sidecar(".resetwatch.json"), "w"))
probe(200, limits(session=1, weekly=0, w_reset=iso(2.5 * 86400)))
ev = events()
assert len(ev) == 2, ev
e = ev[1]
assert (e["window"], e["kind"], e["channel"]) == ("5h", "scheduled", "usage"), e
assert 25 <= e["lag_s"] <= 45, ("lag counts from the stamp, not the last high reading", e)
out = subprocess.run([os.environ["CA_BIN"], "--reset-report", "--days", "1"],
                     capture_output=True, text=True, timeout=60)
assert out.returncode == 0, (out.stdout, out.stderr)
assert "summary: 2 event(s)" in out.stdout, out.stdout
assert "unscheduled/wire n=1" in out.stdout and "scheduled/usage n=1" in out.stdout, out.stdout
assert "100% → 0%" in out.stdout, out.stdout
bad = subprocess.run([os.environ["CA_BIN"], "--reset-report", "--days", "0"],
                     capture_output=True, text=True, timeout=60)
assert bad.returncode == 64, (bad.returncode, bad.stderr)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "F-7: the readouts say RESET since the reading, name the evidence, and give the backoff instead of --fresh" {
  run python3 -c "$LOAD"'
at_wall_good_read()
edit_ledger(quota_as_of=iso(-166))
r = probe(429, wire=RESET)
win = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ca.render_table([r], cfg, win, False, None)
t = buf.getvalue()
assert "RESET since that reading" in t and "server now allows 7d" in t, t
assert "routed on a fresh wire read" in t and "--fresh to retry" not in t, t
assert "429 backoff" in t, t
board = "\n".join(ca.readout_lines([r], cfg, win, False, narrow=True))
assert "RESET since that reading" in board and "server reads 5-hour 1% (accepting work), weekly 0% (accepting work)" \
    in " ".join(board.split()), board
assert "--fresh" not in board, board
row = [l for l in board.splitlines() if "next3" in l][0]
assert "100%" not in row and " 0%" in row, ("the weekly cell is the post-reset figure", row)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
