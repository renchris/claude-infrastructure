#!/usr/bin/env bats
# claude-accounts — usage-schema drift: what the probe says when the endpoint's `limits` array
# stops matching the five fields pick() reads.
#
# WHAT THIS SUITE IS FOR. `pick()` returns (None, None) for a kind the payload does not carry, and
# that value is byte-identical to "this account genuinely has no such cap". So a RENAMED kind read
# as a clean exclusion — `_excluded` answered "no-session-data", which is the symptom, while the
# cause (the endpoint renamed the field) appeared nowhere — and a per-model sub-cap switched on
# under a name we do not model produced no signal at all. `lookup-miss-is-not-absence`: a name
# looked up in a list of ids can only ever MISS, so the miss has to be told apart from the absence.
#
# The eligibility set is the thing that must NOT move. Erroring on every drift would empty the
# fleet the day the endpoint renames `weekly_all` on all four accounts — worse than the silence.
# So D-2 and D-4 pin the fail-OPEN direction as hard as D-1 pins the loud one.
#
# Hermetic: scratch SSOT + ledger + cache in BATS_TEST_TMPDIR, unreachable endpoints, LOG_PATH
# redirected (log_event fires on this path now, and the real fleet log must not see fixtures).

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # $HOME is fixtured BEFORE anything imports the module: LOG_PATH and LASTGOOD_PATH resolve from
  # $HOME at import, so an ambient one would have these cases read and write the operator's live
  # fleet state. Both are redirected again in $LOAD; this is the belt that makes the suite
  # hermetic even for a path added later that nobody thought to redirect.
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
def probe(limits):
    ca.concurrency = lambda c: {"next3": 0}
    ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 9e12}, "present")
    ca.fetch_usage = lambda *a, **k: (200, {"limits": limits})
    return ca.collect(cfg, no_heal=True)[0]
def healthy():
    return [{"kind": "session", "percent": 5, "resets_at": None},
            {"kind": "weekly_all", "percent": 11, "resets_at": None},
            {"kind": "weekly_scoped", "percent": 7, "resets_at": None,
             "scope": {"model": {"display_name": SCOPED}}}]
'

# ---- D-1: the loud half ------------------------------------------------------------------------
# The endpoint renames `session` to `five_hour`. Pre-fix the row carried session_pct None and
# NOTHING else: _excluded said "no-session-data" — true, and silent about why. FAILS PRE-FIX on the
# absent `error` key.

@test "D-1: a renamed session kind is an ERROR that names the kinds the payload did carry" {
  run python3 -c "$LOAD"'
lim = healthy()
lim[0] = {"kind": "five_hour", "percent": 5, "resets_at": None}   # renamed under us
r = probe(lim)
assert r["session_pct"] is None, r
assert "error" in r, r
assert "schema drift" in r["error"] and "no session limit" in r["error"], r["error"]
assert "five_hour" in r["error"] and "weekly_all" in r["error"], r["error"]
assert r["limits_missing"] == ["session"], r
assert r["limits_unmodeled"] == ["five_hour"], r
# The exclusion REASON changes; the exclusion itself, and its class, do not.
assert ca._excluded(r, R) == r["error"], ca._excluded(r, R)
assert ca.reason_class(r, ca._excluded(r, R)) == "data", "a drift is a DATA gap, never policy"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- D-2: the quiet half, and the direction it must fail in ------------------------------------
# A per-model sub-cap switched on under a name we do not model. It must be NAMED (row field + log)
# and must NOT move the row: the account still has a session and a weekly, so it is still routable.
# FAILS PRE-FIX on the absent `limits_unmodeled` key.

@test "D-2: an unmodeled sub-cap is named in the row and the log, and routing is unchanged" {
  run python3 -c "$LOAD"'
lim = healthy() + [{"kind": "weekly_scoped_opus", "percent": 63, "resets_at": None}]
r = probe(lim)
assert r["limits_unmodeled"] == ["weekly_scoped_opus"], r
assert r["limits_missing"] == [], r
assert "error" not in r, r                       # a new kind must never strand an account
assert r["session_pct"] == 5 and r["weekly_pct"] == 11, r
assert ca._excluded(r, R) is None, ca._excluded(r, R)
log = open(ca.LOG_PATH).read()
assert "weekly_scoped_opus" in log and "unmodeled limit kind" in log, log
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- D-3: the control --------------------------------------------------------------------------
# Passes pre-fix AND post-fix, on purpose: it is what proves the detector is silent on the modal
# payload rather than always-firing. An alarm that fires on every row says as much as one that
# cannot fire (alarm-polarity-and-attention-budget).

@test "D-3: a payload carrying exactly the modeled kinds sets neither field" {
  run python3 -c "$LOAD"'
r = probe(healthy())
assert "limits_unmodeled" not in r and "limits_missing" not in r, r
assert "error" not in r, r
assert (r["session_pct"], r["weekly_pct"], r["fable_pct"]) == (5, 11, 7), r
assert not os.path.exists(ca.LOG_PATH) or "schema drift" not in open(ca.LOG_PATH).read()
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- D-4: fail-OPEN where erroring would empty the fleet ---------------------------------------
# `weekly_all` renamed hits all four accounts at once. Recorded, but the row stays routable —
# the opposite choice turns one endpoint rename into a fleet with no eligible account.
# FAILS PRE-FIX on the absent `limits_missing` key.

@test "D-4: a missing weekly_all is recorded but does NOT error the row out of routing" {
  run python3 -c "$LOAD"'
lim = [l for l in healthy() if l["kind"] != "weekly_all"]
r = probe(lim)
assert r["limits_missing"] == ["weekly_all"], r
assert "error" not in r, "erroring here would empty the fleet on a single rename"
assert r["session_pct"] == 5 and r["weekly_pct"] is None, r
assert ca._excluded(r, R) is None, ca._excluded(r, R)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
