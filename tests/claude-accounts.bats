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
  # M7: CLI invocations read the utilization series + assignment ledger (apply_burn /
  # apply_assignments); the fixture reuses real account names, so unpinned paths inherit the
  # REAL fleet's rates. Same pins as claude-accounts-core.bats setup().
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
  export CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
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
                "launcher": "claude3",
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
# HERMETICITY: LOG_PATH resolves at import from $HOME, so any case reaching a log_event() call
# appends to the REAL ~/.claude/logs/claude-accounts.log. That stayed invisible only because
# every case stubbed ca.heal, which was the sole log_event caller on these paths; the moment a
# log line was added OUTSIDE that stub, three fabricated "heal next3: UNPROVEN" entries landed
# in the production log and read there as genuine fleet events. Redirect once, for every case.
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")

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
# HERMETICITY: LOG_PATH resolves at import from $HOME, so any case reaching a log_event() call
# appends to the REAL ~/.claude/logs/claude-accounts.log. That stayed invisible only because
# every case stubbed ca.heal, which was the sole log_event caller on these paths; the moment a
# log line was added OUTSIDE that stub, three fabricated "heal next3: UNPROVEN" entries landed
# in the production log and read there as genuine fleet events. Redirect once, for every case.
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")

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
# HERMETICITY: LOG_PATH resolves at import from $HOME, so any case reaching a log_event() call
# appends to the REAL ~/.claude/logs/claude-accounts.log. That stayed invisible only because
# every case stubbed ca.heal, which was the sole log_event caller on these paths; the moment a
# log line was added OUTSIDE that stub, three fabricated "heal next3: UNPROVEN" entries landed
# in the production log and read there as genuine fleet events. Redirect once, for every case.
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")

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

# ---- unit: inherit_k (the CONCURRENCY inheritance) --------------------------------------------
# Same shape as inherit_lastgood, different instrument. `concurrency()` returns None whenever
# `ps -wwEo command=` blows its timeout, and that is fleet-wide by construction — one census for
# all four accounts — so `_excluded` charged `concurrency-unmeasured` on every row at once and the
# router abstained: 23 of 230 recorded desk decisions, and this is the largest reason inside them
# (68 of their 92 exclusion records — docs/research/desk-router-abstention-2026-09-01.md §2, §4).
# The launcher's answer to an abstention
# is `_claude_pinned`, so a mechanism built to SPREAD load concentrated every launch on the
# most-drained account. The census that could not be taken this sweep was taken 90s ago and is on
# disk; these cases pin that it is inherited, stamped, bounded — and that `row["k"]` stays None,
# which is the half that keeps heal() and handoff-fire's relogin gate refusing.

@test "inherit_k: an unmeasurable ps inherits the last sweep's census, stamped, k untouched" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, time
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")

now = time.time()
prev = {"ts": now - 90, "rows": {"next3": {"k": 3, "weekly_pct": 22}}}
row = {"acct": "next3", "k": None}
assert ca.inherit_k(row, prev, now=now) is True
assert row["k"] is None, "row['k'] was overwritten — heal()/handoff-fire read that field"
assert row["k_stale"] == 3
assert "T" in row["k_stale_as_of"]                 # provenance, not a bare bool
assert ca.k_src(row) == "panes-stale"
assert ca.k_panes(row) == 3 and ca.k_eff(row) == 3
assert ca.k_shown(row) == "3*"                     # the operator sees the staleness
assert 85 <= ca._k_stale_s(row, now=now) <= 95
# a measured census is never overwritten by an older one
live = {"acct": "next3", "k": 0}
assert ca.inherit_k(live, prev, now=now) is False
assert live == {"acct": "next3", "k": 0}
assert ca.k_src(live) == "panes"
print("OK")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "inherit_k: provenance is carried, so the grace expires from the MEASUREMENT" {
  # The trap inherit_lastgood's quota_as_of block already documents, in its concurrency spelling:
  # get_data writes the inherited row back into the cache and _prev_snapshot reads rows back out,
  # so a permanently-starved `ps` re-inherits its OWN inherited count every sweep. Re-stamping the
  # age each pass makes the 600s bound unreachable — the count would be carried forever.
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, time
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")

now = time.time()
measured_at = None
row = {"acct": "next3", "k": None}
assert ca.inherit_k(row, {"ts": now - 60, "rows": {"next3": {"k": 5}}}, now=now) is True
measured_at = row["k_stale_as_of"]
# five more sweeps, each 100s later, each re-inheriting the PREVIOUS (already stale) row
for hop in range(1, 6):
    t = now + 100 * hop
    nxt = {"acct": "next3", "k": None}
    got = ca.inherit_k(nxt, {"ts": t, "rows": {"next3": dict(row)}}, now=t)
    age = 60 + 100 * hop
    if age <= 600:
        assert got is True, (hop, age)
        assert nxt["k_stale"] == 5
        assert nxt["k_stale_as_of"] == measured_at, "re-dated: the grace can never expire"
        row = nxt
    else:
        assert got is False, (hop, age)          # past the grace ⇒ back to unmeasured
        assert "k_stale" not in nxt
        assert ca.k_src(nxt) == "unmeasured"
print("OK")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "inherit_k: no prev, no census, past the grace, and clock skew all fail CLOSED" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, time
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")

now = time.time()
def fresh():
    return {"acct": "next3", "k": None}
cases = {
    "no prev at all":        (None, None),
    "prev has no such acct": ({"ts": now - 30, "rows": {"other": {"k": 4}}}, None),
    "prev row never had k":  ({"ts": now - 30, "rows": {"next3": {"weekly_pct": 9}}}, None),
    "past the 600s grace":   ({"ts": now - 601, "rows": {"next3": {"k": 4}}}, None),
    "clock skew (future)":   ({"ts": now + 300, "rows": {"next3": {"k": 4}}}, None),
    "stamp unparseable":     ({"ts": now, "rows": {"next3": {"k": None, "k_stale": 4,
                                                             "k_stale_as_of": "not-a-date"}}}, None),
}
for name, (prev, _) in cases.items():
    row = fresh()
    assert ca.inherit_k(row, prev, now=now) is False, name
    assert row == {"acct": "next3", "k": None}, (name, row)
    assert ca.k_src(row) == "unmeasured", name
    scored = dict(row, session_pct=5.0, session_reset_h=3.0)
    assert ca._excluded(scored, {"S_CUT": 0.85, "EPS_H": 0.25, "KMAX": 8, "KMAX_RESIDENT": 40},
                        cliff=False) == "concurrency-unmeasured", name

# ...but SUB-SECOND negative is ROUNDING, not skew: the stamp is an ISO string with microsecond
# resolution, so a freshly-written one can read a hair ahead of the clock that wrote it. A strict
# `0 <=` floor made the refusal depend on the fractional part of time.time() — a 2-in-3 flake when
# a sweep inherits within the same instant, which is precisely the re-inheritance case.
edge = fresh()
assert ca.inherit_k(edge, {"ts": now + 0.4, "rows": {"next3": {"k": 4}}}, now=now) is True
assert edge["k_stale"] == 4
assert ca.inherit_k(fresh(), {"ts": now + 5, "rows": {"next3": {"k": 4}}}, now=now) is False
print("OK")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "collect: a fleet-wide ps failure routes on the inherited census, and heal still sees None" {
  # The whole defect end to end: concurrency() None, a prev snapshot on disk, and the row must come
  # out ROUTABLE. The second assertion is the safety one — heal()'s k_live argument is what decides
  # whether a refresh token may be redeemed, and it must NEVER see the inherited number.
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, json, time
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]

cfg = json.load(open(os.environ["CA_CFG"]))
for a in cfg["accounts"]:
    a["config_dir"] = os.path.expanduser(a["config_dir"])
R = cfg["router"]; R.setdefault("KMAX_RESIDENT", 40)
ca.read_creds = lambda cd, kc: ({"accessToken": "t",
                                 "expiresAt": (time.time() + 3600) * 1000}, "present")
ca.fetch_usage = lambda cfg, token, retries=2: (200, {"limits": [
    {"kind": "session", "percent": 7}, {"kind": "weekly_all", "percent": 20}],
    "extra_usage": {}})
# heal() reads its k_live ARGUMENT, never the row, so the seam that keeps the rotation gate honest
# is what collect PASSES the probe. Record it rather than stubbing heal: no fixture can then make
# the gate look refused while the argument was in fact fabricated.
seen_k_live, _probe = [], ca.probe_account
def _spy(cfg, acct, kc, k_live, ledger, prev, no_heal):
    seen_k_live.append(k_live)
    return _probe(cfg, acct, kc, k_live, ledger, prev, no_heal)
ca.probe_account = _spy

# sweep 1: ps healthy, 2 live sessions
ca.concurrency = lambda _cfg: {a["name"]: 2 for a in _cfg["accounts"]}
rows1 = ca.collect(cfg, no_heal=True)
assert rows1[0]["k"] == 2 and "k_stale" not in rows1[0]
prev = {"ts": time.time() - 30, "rows": {r["acct"]: dict(r) for r in rows1}}

# sweep 2: BOTH instruments starved — ps returns None and the transcript walk goes over budget.
# That pairing is not a contrived worst case: it is the only shape the abstention has ever had
# (17,059 utilization rows, 0 with `k is None` while k_work was measured — §4), because one
# starved box is what fails both, and `k_src` reads 'work' whenever k_work survives.
ca.concurrency = lambda _cfg: None
ca.working_concurrency = lambda _cfg, **kw: None
del seen_k_live[:]                                  # sweep 1's honest 2 is not the claim here
rows2 = ca.collect(cfg, no_heal=True, prev=prev)
r = rows2[0]
assert r["k"] is None, "the measured field must stay unmeasured"
assert r["k_stale"] == 2 and r["k_stale_as_of"]
assert ca.k_src(r) == "panes-stale"
assert ca._excluded(r, R, cliff=False) is None, \
    "THE ABSTENTION IS BACK: a starved ps still excludes the whole fleet"
assert ca.score_general(r, cfg, cliff=False)[0] is not None
# the rotation-safety gate never sees the inherited number: heal(cfg, acct, rt, k_live) is called
# with THIS, and `k_live is None` is its refusal (tests/account-fact-derivation.bats case 13).
assert seen_k_live == [None], seen_k_live
print("OK")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "MUTANT: a _prev_snapshot that drops the census cannot inherit — all four excluded again" {
  # Control-can-fail, aimed at the exact projection line that carries the value. Without `k` in the
  # snapshot there is nothing to inherit, and the suite above must go red rather than pass anyway.
  mutant="$BATS_TEST_TMPDIR/mutant-prevsnap"
  sed 's/^                                      "k", "k_stale", "k_stale_as_of")}$/                                      "k_stale_as_of")}/' "$CA_BIN" > "$mutant"
  run bash -c "grep -c '\"k\", \"k_stale\", \"k_stale_as_of\")}' \"\$1\"" _ "$mutant"
  [ "$output" = 0 ]                                # the projection really was mutated
  CA_MUTANT="$mutant" run python3 - <<'PY'
import importlib.machinery, importlib.util, os, json, time
src = os.environ["CA_MUTANT"]
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", src)))
importlib.machinery.SourceFileLoader("ca", src).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]

cfg = json.load(open(os.environ["CA_CFG"]))
cfg["cache_file"] = os.path.join(os.environ["BATS_TEST_TMPDIR"], "mutant-cache.json")
for a in cfg["accounts"]:
    a["config_dir"] = os.path.expanduser(a["config_dir"])
R = cfg["router"]; R.setdefault("KMAX_RESIDENT", 40)
ca.read_creds = lambda cd, kc: ({"accessToken": "t",
                                 "expiresAt": (time.time() + 3600) * 1000}, "present")
ca.fetch_usage = lambda cfg, token, retries=2: (200, {"limits": [
    {"kind": "session", "percent": 7}, {"kind": "weekly_all", "percent": 20}],
    "extra_usage": {}})
ca.concurrency = lambda _cfg: {a["name"]: 2 for a in _cfg["accounts"]}
rows1 = ca.collect(cfg, no_heal=True)
ca.cache_write(cfg, {"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "rows": rows1})

ca.concurrency = lambda _cfg: None
ca.working_concurrency = lambda _cfg, **kw: None
rows2 = ca.collect(cfg, no_heal=True, prev=ca._prev_snapshot(cfg))
r = rows2[0]
assert "k_stale" not in r, "the mutant inherited anyway — the projection is not the seam"
assert ca._excluded(r, R, cliff=False) == "concurrency-unmeasured"
print("MUTANT-RED-AS-EXPECTED")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *MUTANT-RED-AS-EXPECTED* ]] || false
}

@test "MUTANT: an inherit_k that re-stamps provenance carries a census forever" {
  # The second seam: the bound is only real because the stamp is the MEASUREMENT's. A mutant that
  # re-dates on every re-inheritance keeps a 10-hour-old census alive inside a 600s grace.
  mutant="$BATS_TEST_TMPDIR/mutant-restamp"
  sed 's/pr.get("k_stale"), pr.get("k_stale_as_of")/pr.get("k_stale"), datetime.fromtimestamp(prev["ts"], timezone.utc).isoformat()/' \
    "$CA_BIN" > "$mutant"
  run bash -c "grep -c 'pr.get(\"k_stale\"), datetime.fromtimestamp' \"\$1\"" _ "$mutant"
  [ "$output" = 1 ]                                # the provenance line really was mutated
  CA_MUTANT="$mutant" run python3 - <<'PY'
import importlib.machinery, importlib.util, os, time
src = os.environ["CA_MUTANT"]
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", src)))
importlib.machinery.SourceFileLoader("ca", src).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")

now = time.time()
row = {"acct": "next3", "k": None}
assert ca.inherit_k(row, {"ts": now - 60, "rows": {"next3": {"k": 5}}}, now=now) is True
for hop in range(1, 40):                            # ~65 minutes of 100s sweeps
    t = now + 100 * hop
    nxt = {"acct": "next3", "k": None}
    if not ca.inherit_k(nxt, {"ts": t, "rows": {"next3": dict(row)}}, now=t):
        break
    row = nxt
else:
    print("MUTANT-RED-AS-EXPECTED")                 # never expired: the bound was unreachable
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *MUTANT-RED-AS-EXPECTED* ]] || false
}

# ---- unit: capture on the good path (collect writes the ledger) ------------------------------

@test "collect: a 200 sweep captures last-good (absolute resets + quota_as_of) to the ledger" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, json, time
from datetime import datetime, timezone, timedelta
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
# HERMETICITY: LOG_PATH resolves at import from $HOME, so any case reaching a log_event() call
# appends to the REAL ~/.claude/logs/claude-accounts.log. That stayed invisible only because
# every case stubbed ca.heal, which was the sole log_event caller on these paths; the moment a
# log line was added OUTSIDE that stub, three fabricated "heal next3: UNPROVEN" entries landed
# in the production log and read there as genuine fleet events. Redirect once, for every case.
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
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
  [[ "$output" == *OK* ]] || false
}

@test "collect: capture round-trips into inherit (persist then re-read as a broken sweep)" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, json, time
from datetime import datetime, timezone, timedelta
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
# HERMETICITY: LOG_PATH resolves at import from $HOME, so any case reaching a log_event() call
# appends to the REAL ~/.claude/logs/claude-accounts.log. That stayed invisible only because
# every case stubbed ca.heal, which was the sole log_event caller on these paths; the moment a
# log line was added OUTSIDE that stub, three fabricated "heal next3: UNPROVEN" entries landed
# in the production log and read there as genuine fleet events. Redirect once, for every case.
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
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
  [[ "$output" == *OK* ]] || false
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

# --- extra-usage spend surfacing (2026-07-26 incident) ------------------------------------
# An account carried $176.91 of metered extra-usage spend while the endpoint reported
# is_enabled=false. The ¢ alert keyed on that toggle, so the money was invisible on every
# /accounts readout; and used_credits is CENTS, so any surface printing it raw reported 100x.
# These pin both halves. Mutation-proved: reverting the alert to `if r.get("credits_on")`
# makes the first test RED, and dropping the /100 makes the second RED.

@test "credits: used_credits is CENTS ⇒ credits_used_usd is the dollar figure" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
# HERMETICITY: LOG_PATH resolves at import from $HOME, so any case reaching a log_event() call
# appends to the REAL ~/.claude/logs/claude-accounts.log. That stayed invisible only because
# every case stubbed ca.heal, which was the sole log_event caller on these paths; the moment a
# log line was added OUTSIDE that stub, three fabricated "heal next3: UNPROVEN" entries landed
# in the production log and read there as genuine fleet events. Redirect once, for every case.
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")

r = {}
ca.set_credits(r, False, 17691)          # the live 2026-07-26 reading
assert r["credits_used"] == 17691, r     # raw field preserved, still cents
assert abs(r["credits_used_usd"] - 176.91) < 1e-9, r
assert r["credits_on"] is False, r       # toggle is reported independently of spend

z = {}
ca.set_credits(z, None, None)            # no-data path must not invent spend
assert z == {"credits_on": False, "credits_used": 0.0, "credits_used_usd": 0.0}, z
print("OK")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "credits: the ¢ alert fires on SPEND with the toggle off, and stays silent at zero" {
  run python3 - <<'PY'
import importlib.machinery, importlib.util, os, json
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
# HERMETICITY: LOG_PATH resolves at import from $HOME, so any case reaching a log_event() call
# appends to the REAL ~/.claude/logs/claude-accounts.log. That stayed invisible only because
# every case stubbed ca.heal, which was the sole log_event caller on these paths; the moment a
# log line was added OUTSIDE that stub, three fabricated "heal next3: UNPROVEN" entries landed
# in the production log and read there as genuine fleet events. Redirect once, for every case.
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))

def row(acct, on, cents, stale=False):
    r = {"acct": acct, "k": 0, "auth": "ok", "session_pct": 1, "session_reset_h": 3.0,
         "session_reset_at": None, "weekly_pct": 10, "weekly_reset_h": 40.0,
         "weekly_reset_at": None, "fable_pct": 0, "fable_reset_h": None,
         "fable_reset_at": None, "login_expires_h": 400.0, "login_expires_at": None,
         "is_self": False}
    ca.set_credits(r, on, cents)
    if stale:
        r["stale_quota"] = True
    return r

import io, contextlib
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ca.render_table([row("spend_off", False, 17691),   # the incident shape
                     row("on_zero", True, 0),
                     row("clean", False, 0),
                     row("stale", False, 50000, stale=True)],
                    cfg, {"active": True, "end": "2099-12-31", "permanent": True,
                          "deadline": None}, True)
out = buf.getvalue()
cent = [l for l in out.splitlines() if "¢" in l]

# the load-bearing one: spend visible despite the toggle reading off, and in DOLLARS
assert any("spend_off" in l and "$176.91" in l for l in cent), cent
assert not any("17691" in l for l in cent), cent          # never the raw cents figure
# a positive control — an unfired alert would also satisfy the negatives below
assert any("on_zero" in l for l in cent), cent            # toggle ON still surfaces
assert not any("clean" in l for l in cent), cent          # no toggle, no spend ⇒ silent
assert not any("stale" in l for l in cent), cent          # stale rows never assert money
print("OK")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}
