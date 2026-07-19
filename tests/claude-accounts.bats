#!/usr/bin/env bats
# claude-accounts — last-good quota ledger (Part A1, desk-anti-hitl Part A rec 1).
# The oauth/usage endpoint yields quota only on a 200; every other outcome (logged-out /
# token-invalid / keychain-error / expired-stale-401 / no-data / 429 poll-throttle) leaves the
# row quota-blank and _excluded() drops it from routing. A durable, TTL-free per-account ledger
# (~/.claude/logs/claude-accounts-lastgood.json) records the last good numbers so --json / the
# table / a handoff successor can still SEE the stranded quota, while the router STILL excludes
# the row (its error field is untouched — no policy change).
#
# Two techniques: (a) import the module (extensionless, __main__-guarded, so no CLI runs) and
# exercise the pure helpers + collect() with network/keychain stubbed; (b) drive the real binary
# end-to-end with a scratch config whose account has no keychain item ⇒ logged-out path.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CA_LEDGER="$BATS_TEST_TMPDIR/lastgood.json"
  export CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$CA_LEDGER"
  rm -f "$CA_LEDGER" "$CACHE"
  # scratch SSOT: one account whose config_dir hashes to a keychain service that does not exist
  # ⇒ read_creds returns no-keychain-item ⇒ logged-out, fully offline + deterministic.
  python3 - "$CA_CFG" "$CACHE" <<'PY'
import json, sys
cfg_path, cache = sys.argv[1], sys.argv[2]
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": "/nonexistent/model-config.yaml", "dia_local_state": "/nonexistent/LS",
  "cache_file": cache, "cache_ttl_s": 90,
  "frontier": {"scoped_display_name": "Fable", "coupling": 0.5, "deadline_margin_h": 2.0,
               "end_date_inclusive": True, "credits_authorized": False},
  "router": {"S_CUT": 0.85, "S_SOFT": 0.5, "SF_FLOOR": 0.05, "KMAX": 8, "KFLOOR": 0.1,
             "MARGIN_H": 0.5, "EPS_H": 0.25, "WEEKLY_FLOOR": 0.005, "FABLE_FLOOR": 0.02,
             "JB_BONUS": 1.25},
  "accounts": [{"name": "next3", "config_dir": "/tmp/ca-test-nonexistent-xyz",
                "launcher": "claude-next3", "fable_launcher": "claude-fable3",
                "email": "test@example.com", "mailbox": "test@example.com", "dia_profile": "T"}],
}, open(cfg_path, "w"))
PY
}

# ---- unit: inherit_lastgood (the generalized inheritance) -------------------------------------

@test "inherit_lastgood: merges ledger, re-derives *_reset_h, stamps stale, preserves error" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, json
from datetime import datetime, timezone, timedelta
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)

future = (datetime.now(timezone.utc) + timedelta(hours=5)).isoformat()
# weekly=20% is well under any cutoff — a LIVE account would route; the stale row must NOT.
ledger = {"next3": {"session_pct": 12, "session_reset_at": future,
                    "weekly_pct": 20, "weekly_reset_at": future,
                    "fable_pct": 40, "fable_reset_at": future,
                    "credits_on": False, "credits_used": 0.0,
                    "quota_as_of": "2026-07-19T09:40:00+00:00"}}
row = {"acct": "next3", "auth": "logged-out", "error": "logged-out"}
assert ca.inherit_lastgood(row, ledger, None) is True
assert row["weekly_pct"] == 20
assert row["stale_quota"] is True
assert row["quota_as_of"] == "2026-07-19T09:40:00+00:00"
assert 4.8 < row["weekly_reset_h"] < 5.1, row["weekly_reset_h"]   # re-derived, not frozen
assert row["error"] == "logged-out"                              # router-exclusion field intact

cfg = json.load(open(os.environ["CA_CFG"]))
# NO POLICY CHANGE: excluded despite 20% weekly headroom, purely because error is set.
assert ca._excluded(row, cfg["router"]) == "logged-out"
s, why = ca.score_general(row, cfg)
assert s is None and why == "logged-out", (s, why)
print("OK")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]]
}

@test "inherit_lastgood: falls back to the in-memory prev snapshot when the ledger is empty" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)

prev = {"ts": 1752918000.0, "rows": {"next3": {"session_pct": 5, "weekly_pct": 22, "fable_pct": 10}}}
row = {"acct": "next3", "poll_throttled": True, "error": "poll throttled"}
assert ca.inherit_lastgood(row, {}, prev) is True
assert row["weekly_pct"] == 22
assert row["stale_quota"] is True
assert "T" in row["quota_as_of"]          # derived from prev ts
assert row["error"] == "poll throttled"   # untouched
print("OK")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]]
}

@test "inherit_lastgood: no ledger + no prev ⇒ returns False and mutates nothing" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)

row = {"acct": "next3", "error": "logged-out"}
assert ca.inherit_lastgood(row, {}, None) is False
assert "weekly_pct" not in row
assert "stale_quota" not in row
assert row == {"acct": "next3", "error": "logged-out"}
print("OK")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]]
}

# ---- unit: capture on the good path (collect writes the ledger) ------------------------------

@test "collect: a 200 sweep captures last-good (absolute resets + quota_as_of) to the ledger" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, json, time
from datetime import datetime, timezone, timedelta
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]

cfg = json.load(open(os.environ["CA_CFG"]))
for a in cfg["accounts"]:
    a["config_dir"] = os.path.expanduser(a["config_dir"])
future = (datetime.now(timezone.utc) + timedelta(hours=100)).isoformat()
# stub the world: fresh token, zero live sessions, a healthy 200 usage payload.
ca.read_creds = lambda cd, kc: ({"accessToken": "tok",
                                 "expiresAt": (time.time() + 3600) * 1000}, "present")
ca.concurrency = lambda cfg: {a["name"]: 0 for a in cfg["accounts"]}
ca.fetch_usage = lambda cfg, token, retries=2: (200, {"limits": [
    {"kind": "session", "percent": 12, "resets_at": future},
    {"kind": "weekly_all", "percent": 31, "resets_at": future},
    {"kind": "weekly_scoped", "percent": 40, "resets_at": future,
     "scope": {"model": {"display_name": "Fable"}}}],
    "extra_usage": {"is_enabled": False, "used_credits": 0}})

rows = ca.collect(cfg, no_heal=True)
assert "error" not in rows[0], rows[0]
assert rows[0].get("stale_quota") is None           # a live row is never stamped stale
assert rows[0]["weekly_pct"] == 31

led = json.load(open(os.environ["CA_LEDGER"]))
e = led["next3"]
assert e["weekly_pct"] == 31
assert e["session_pct"] == 12 and e["fable_pct"] == 40
assert e["weekly_reset_at"] == future               # ABSOLUTE stamp stored, not the derived _h
assert "session_reset_h" not in e                   # derived fields are NOT persisted
assert "T" in e["quota_as_of"]
print("OK")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]]
}

@test "collect: capture round-trips into inherit (persist then re-read as a broken sweep)" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, json, time
from datetime import datetime, timezone, timedelta
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]

cfg = json.load(open(os.environ["CA_CFG"]))
for a in cfg["accounts"]:
    a["config_dir"] = os.path.expanduser(a["config_dir"])
future = (datetime.now(timezone.utc) + timedelta(hours=50)).isoformat()
ca.concurrency = lambda cfg: {a["name"]: 0 for a in cfg["accounts"]}

# sweep 1: healthy 200 → captures
ca.read_creds = lambda cd, kc: ({"accessToken": "t", "expiresAt": (time.time() + 3600) * 1000}, "present")
ca.fetch_usage = lambda cfg, token, retries=2: (200, {"limits": [
    {"kind": "weekly_all", "percent": 44, "resets_at": future}], "extra_usage": {}})
ca.collect(cfg, no_heal=True)

# sweep 2: keychain now gone → logged-out → inherits the captured 44%
ca.read_creds = lambda cd, kc: (None, "no-keychain-item")
rows = ca.collect(cfg, no_heal=True)
assert rows[0]["auth"] == "logged-out"
assert rows[0]["error"] == "logged-out"
assert rows[0]["stale_quota"] is True
assert rows[0]["weekly_pct"] == 44
print("OK")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]]
}

# ---- e2e: the real binary, --json inheritance on a logged-out account ------------------------

@test "e2e --json: a logged-out account inherits the ledger AND stays router-excluded" {
  # seed the durable ledger with a low-usage last-good block (a live account would route at 18%)
  python3 - <<'PY'
import json, os
from datetime import datetime, timezone, timedelta
future = (datetime.now(timezone.utc) + timedelta(hours=8)).isoformat()
json.dump({"next3": {"session_pct": 4, "session_reset_at": future,
                     "weekly_pct": 18, "weekly_reset_at": future,
                     "fable_pct": 9, "fable_reset_at": future,
                     "credits_on": False, "credits_used": 0.0,
                     "quota_as_of": datetime.now(timezone.utc).isoformat()}},
          open(os.environ["CA_LEDGER"], "w"))
PY
  run python3 "$CA_BIN" --json --fresh --no-heal
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
r = next(x for x in d["rows"] if x["acct"] == "next3")
assert r["auth"] in ("logged-out", "keychain-error"), r["auth"]
assert r["stale_quota"] is True, r
assert r["weekly_pct"] == 18, r
assert "quota_as_of" in r and r["quota_as_of"], r
# router policy UNCHANGED: excluded despite 18% weekly headroom
assert r["score_general"] is None, r["score_general"]
assert r["route_reasons"]["general"] in ("logged-out", "keychain-error"), r["route_reasons"]
print("OK")
'
  [ "$status" -eq 0 ]
}

@test "e2e --json: no ledger + logged-out ⇒ no stale_quota, still excluded (unchanged behavior)" {
  run python3 "$CA_BIN" --json --fresh --no-heal
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
r = next(x for x in d["rows"] if x["acct"] == "next3")
assert r.get("stale_quota") is None, r          # nothing to inherit ⇒ no stamp
assert "weekly_pct" not in r, r
assert r["score_general"] is None, r
print("OK")
'
  [ "$status" -eq 0 ]
}
