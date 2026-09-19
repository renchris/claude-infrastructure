#!/usr/bin/env bats
# claude-accounts — the WIRE truth vs the endpoint integer.
#
# WHAT THIS SUITE IS FOR. `/api/oauth/usage` reports each window as an INTEGER `percent` that
# ROUNDS UP and CLAMPS at 100. So `weekly 100%` is a THREE-WAY COLLAPSE — "99% used, server says
# allowed", "exactly full", and "102% used, server says rejected" — and the router read the first
# of those as `weekly-exhausted`. Measured live on 2026-09-19: `next` read `percent: 100` from the
# endpoint while `anthropic-ratelimit-unified-7d-utilization: 0.99` / `7d-status: allowed_warning`
# rode a real HTTP 200, i.e. the fleet was refusing a WORKING account; `next4` read `percent: 100`
# on its 5h window against a wire `1.02` / `rejected`, which is the same collapse at the other end.
#
# THE DIRECTION THAT MUST HOLD. The wire may only ever ADD precision or ADD a refusal. An absent
# wire (probe not wanted, transport failed, header set missing) must leave every verdict byte-
# identical to the endpoint-only behaviour — `predicate-refusal-is-not-a-negative`: a read that
# could not happen is not a permissive answer. W-3 and W-7 are the arms that pin that.
#
# Hermetic: scratch SSOT + ledger + cache in BATS_TEST_TMPDIR, unreachable endpoints, LOG_PATH
# redirected. fetch_wire_limits is ALWAYS stubbed — this suite never touches the network, and a
# test that did would be spending the operator's quota to assert a rendering.

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
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
cfg = json.load(open(os.environ["CA_CFG"]))
R = cfg["router"]
SCOPED = cfg["frontier"]["scoped_display_name"]
CALLS = []
def limits(session=5, weekly=11, fable=7):
    return [{"kind": "session", "percent": session, "resets_at": None},
            {"kind": "weekly_all", "percent": weekly, "resets_at": None},
            {"kind": "weekly_scoped", "percent": fable, "resets_at": None,
             "scope": {"model": {"display_name": SCOPED}}}]
def probe(lim, wire=None):
    """One collect() with the usage endpoint stubbed and the wire stubbed to `wire` (None = the
    probe returns nothing, i.e. a MISS). Every call is recorded so a test can assert the GATE."""
    ca.concurrency = lambda c: {"next3": 0}
    ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 9e12}, "present")
    ca.fetch_usage = lambda *a, **k: (200, {"limits": lim})
    def _wire(*a, **k):
        CALLS.append(1)
        return wire
    ca.fetch_wire_limits = _wire
    del CALLS[:]
    return ca.collect(cfg, no_heal=True)[0]
'

# ---- W-1: the live defect ----------------------------------------------------------------------
# The endpoint says 100; the server says 0.99 and `allowed_warning`. Pre-fix this row scored
# `weekly-exhausted` and was refused by every lane. FAILS PRE-FIX on the routability assert.

@test "W-1: endpoint 100 + wire 0.99 allowed => routable, with the last ~1pp of headroom" {
  run python3 -c "$LOAD"'
r = probe(limits(weekly=100),
          {"7d_util": 0.99, "7d_status": "allowed_warning", "5h_util": 0.05,
           "5h_status": "allowed", "status": "allowed_warning", "http": 200})
assert r["weekly_pct"] == 100, "the ENDPOINT meter is recorded untouched: the series keys window "\
                               "rolls on a meter going backwards, so a provenance switch mid-"\
                               "series would read as a reset"
assert r["wire"]["7d_util"] == 0.99, r
assert abs(ca.weekly_headroom(r) - 0.01) < 1e-9, ca.weekly_headroom(r)
assert ca._excluded(r, R) is None, ca._excluded(r, R)
score, reason = ca.score_general(r, cfg)
assert reason is None and score > 0, (score, reason)
assert ca.score_interactive(r, cfg)[1] is None, ca.score_interactive(r, cfg)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-2: the other end of the same collapse ---------------------------------------------------
# A server `rejected` is a FACT, and it outranks a comfortable-looking integer. The endpoint here
# reads a routable 97; only the wire knows the account is refused.

@test "W-2: a wire 7d 'rejected' excludes even when the endpoint integer looks routable" {
  run python3 -c "$LOAD"'
# WIRE_FORCE, and the reason is a REAL PROPERTY of the gate rather than test scaffolding. The
# endpoint integer here reads a comfortable 97, so wire_wanted() declines to spend the call and
# there is no wire to reject with — this state is reachable ONLY under `--wire`. That is not a
# contrivance: the endpoint LAGS the wire (measured 2026-09-19, next3 read 28 against a wire
# 0.30), so a fast burn genuinely can cross the wall between sweeps while the integer still looks
# fine, and the default gate will not probe it. The residual is named in the research doc; what
# this test pins is the half that IS in our hands — once a `rejected` verdict is in the row, it
# outranks the integer.
ca.WIRE_FORCE = True
r = probe(limits(weekly=97),
          {"7d_util": 1.0, "7d_status": "rejected", "5h_util": 0.1,
           "5h_status": "allowed", "status": "rejected", "http": 429})
assert CALLS == [1], "with --wire the probe must fire even away from the wall"
assert ca._excluded(r, R) == "weekly-exhausted", ca._excluded(r, R)
assert ca.score_general(r, cfg)[1] == "weekly-exhausted", ca.score_general(r, cfg)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-3: the control, and the cost gate -------------------------------------------------------
# Away from the wall the probe must not fire AT ALL — the whole cost argument rests on it. Passes
# pre-fix on the verdict and post-fix on both; the CALLS assert is what gives it power.

@test "W-3: away from the wall the wire is never called and every verdict is unchanged" {
  run python3 -c "$LOAD"'
import json as J
r = probe(limits(session=5, weekly=11))
assert CALLS == [], "a probe fired below WIRE_NEAR_WALL — the cost gate is open"
assert "wire" not in r and "wire_miss" not in r, r
assert ca._excluded(r, R) is None
assert abs(ca.weekly_headroom(r) - 0.89) < 1e-9, ca.weekly_headroom(r)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-4: the gate itself ----------------------------------------------------------------------
# WIRE_NEAR_WALL is the band where the integer is AMBIGUOUS, and nothing else earns the call.

@test "W-4: wire_wanted fires only at/above the wall, on --wire, and never under the kill switch" {
  run python3 -c "$LOAD"'
W = ca.WIRE_NEAR_WALL
assert ca.wire_wanted(5, 11) is False
assert ca.wire_wanted(5, W) is True,  "the weekly meter at the wall must earn the read"
assert ca.wire_wanted(W, 11) is True, "the 5h meter at the wall must too — it clamps the same way"
assert ca.wire_wanted(None, None) is False, "no reading is not a reason to spend a call"
assert ca.wire_wanted(5, 11, force=True) is True
os.environ["CC_ACCOUNTS_WIRE"] = "off"
assert ca.wire_wanted(5, 100) is False and ca.wire_wanted(5, 100, force=True) is False, \
    "the kill switch must outrank --wire"
del os.environ["CC_ACCOUNTS_WIRE"]
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-5: overage the integer cannot represent -------------------------------------------------
# `percent` maxes at 100, so a 5h window measured at 1.02 and a 5h window at exactly 1.00 are the
# same cell. The unclamped fraction is what the 5h cutoff should be reading.

@test "W-5: a wire 5h above 1.0 is carried unclamped and refuses the row" {
  run python3 -c "$LOAD"'
r = probe(limits(session=100, weekly=50),
          {"5h_util": 1.02, "5h_status": "rejected", "7d_util": 0.5,
           "7d_status": "allowed", "status": "rejected", "http": 429})
assert r["session_pct"] == 100, "the endpoint clamp is preserved in the recorded meter"
assert r["wire"]["5h_util"] == 1.02, r
assert ca._excluded(r, R) == "5h-cutoff", ca._excluded(r, R)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-6: the renderer says WHICH of the three states it is ------------------------------------
# The bullet used to read `weekly **LIMITED** (100%)` for all three. Each now names its own state,
# and the `ʷ` suffix is what tells a reader that a bare `100%` is a rounded ceiling.

@test "W-6: the three 100%-states render as three different bullets, and ʷ marks a wire cell" {
  run python3 -c "$LOAD"'
import io, contextlib
WIN_OPEN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
def readout(wire):
    r = probe(limits(weekly=100), wire)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ca.render_readout([r], cfg, WIN_OPEN, False)
    return buf.getvalue(), r
allowed, r1 = readout({"7d_util": 0.99, "7d_status": "allowed_warning", "5h_util": 0.05,
                       "5h_status": "allowed", "status": "allowed_warning", "http": 200})
assert "◐" in allowed and "99%" in allowed and "still routable" in allowed, allowed
assert "99%ʷ" in allowed, "the table cell must carry the wire value and its marker"
rejected, _ = readout({"7d_util": 1.0, "7d_status": "rejected", "5h_util": 0.05,
                       "5h_status": "allowed", "status": "rejected", "http": 429})
assert "EXHAUSTED" in rejected and "the server is refusing it" in rejected, rejected
blind, r3 = readout(None)
assert "rounded and clamped" in blind and "unverified" in blind, blind
assert "ʷ" not in blind, "a cell with no wire reading must never carry the wire marker"
assert allowed != rejected != blind, "three states, three renderings"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-7: a MISS is not a permissive answer ----------------------------------------------------
# Transport failure / missing header set. The verdict must be exactly what the endpoint alone
# would have given — never softer, because "we could not read it" is not "the server allows it".

@test "W-7: a wire miss at 100 degrades to the endpoint verdict, not to routable" {
  run python3 -c "$LOAD"'
r = probe(limits(weekly=100), None)
assert CALLS == [1], "the probe was wanted at 100 and must have been attempted"
assert r.get("wire_miss") is True and "wire" not in r, r
assert ca.weekly_headroom(r) == 0.0, ca.weekly_headroom(r)
assert ca.score_general(r, cfg)[1] == "weekly-exhausted", ca.score_general(r, cfg)
assert ca.wire_rejects(r, "7d") is False, "an unread wire must not manufacture a refusal either"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-8: the series records the wire BESIDE the meters, never in place of them -----------------
# `_rolled` calls any meter decrease a window reset. Writing a wire 99 into weekly_pct where the
# prior row holds an endpoint 100 would fabricate a roll and corrupt every burn fit downstream.

@test "W-8: the utilization series keeps weekly_pct endpoint-sourced and adds wire_* beside it" {
  run python3 -c "$LOAD"'
r = probe(limits(weekly=100),
          {"7d_util": 0.99, "7d_status": "allowed_warning", "5h_util": 0.05,
           "5h_status": "allowed", "status": "allowed_warning", "http": 200})
p = os.environ["CC_UTIL_LOG"]
ca.record_utilization([r], path=p, min_interval_s=0)
rec = json.loads(open(p).read().strip().splitlines()[-1])
assert rec["weekly_pct"] == 100, rec
assert rec["wire_7d_util"] == 0.99 and rec["wire_7d_status"] == "allowed_warning", rec
assert rec["wire_5h_util"] == 0.05, rec
prev = dict(rec); prev["weekly_pct"] = 100
assert ca._rolled(prev, rec, "weekly_reset_at", "weekly_pct") is False, \
    "two adjacent rows at the same endpoint meter must never read as a window roll"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
