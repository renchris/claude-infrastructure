#!/usr/bin/env bats
# inherit_k — the last sweep's pane census carried through a STARVED `ps`, so that a measurement
# failure stops excluding the whole fleet from routing.
#
# WHY THIS FILE EXISTS. desk-router-abstention-2026-09-01 §4 measured the defect, and that doc's
# "NOT shipped" section named the reason it was filed rather than fixed: "it is a routing-
# ELIGIBILITY policy change and needs its own mutant-proven suite." This is that suite.
#
# THE DEFECT. `concurrency()` returns None for the WHOLE fleet when its `ps` census blows its 10s
# budget — 501/501 recorded failures are that one TimeoutExpired, and the only sweeper runs at
# ProcessType Background + LowPriorityIO, where sweep p90 is 34s against a 1.85-2.53s foreground
# bench. Every row then reads `k: None`, `k_src` reads "unmeasured", and `_excluded` refuses all
# four accounts with `concurrency-unmeasured` (68 of 230 recorded interactive decisions — the
# single largest cause of desk-router abstention). The refusal does not stop the launch: `claude()`
# falls through to `_claude_pinned`, so a mechanism built to SPREAD load concentrates every launch
# on the most-drained account (73.0% mean weekly, against 33-52% for the other three). ABSTAINING
# IS THE WORSE OUTCOME — which is why the fix inherits rather than raising the timeout.
#
# THE HALF THAT MAY NEVER WEAKEN. `k is None` also gates ROTATION SAFETY: heal() refuses to redeem
# a refresh token it cannot prove is unowned, and handoff-fire re-spells the same gate for its
# Phase-1 headless relogin. An inherited count is up to cache_grace_s (600s) old and proves
# nothing about now. So the cases below come in pairs — routing must ADMIT on an inherited census,
# and the rotation gate must still REFUSE. A suite that proved only the first would be certifying
# the exact fail-open the None contract was written to close.
#
# Every assertion that could pass vacuously carries a MUTANT reproducing the pre-fix (or
# post-regression) behaviour, and the mutant is asserted to FIRE. A detector that cannot fire is a
# green light — which is the defect class this whole subsystem keeps re-growing.
#
# Hermetic: scratch SSOT + cache + ledger + logs in BATS_TEST_TMPDIR, unreachable endpoints, no
# real ps, no real keychain, no network.

setup() {
  # M11 — a test's environment is PINNED, not ambient (see claude-accounts-core.bats).
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_SSOT="$REPO/accounts.json"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CA_LEDGER="$BATS_TEST_TMPDIR/lastgood.json"
  export CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$CA_LEDGER"
  export YAML="$BATS_TEST_TMPDIR/model-config.yaml"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
  export CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
  export CC_ROUTE_RECORDS_DIR="$BATS_TEST_TMPDIR/route-records"
  rm -f "$CA_LEDGER" "$CACHE"
  # FOUR accounts, because the defect IS fleet-wide: a one-account fixture cannot tell "this row
  # was excluded" apart from "the router had nothing left to route to".
  python3 - "$CA_CFG" "$CACHE" "$CA_SSOT" "$YAML" <<'PY'
import json, sys
cfg_path, cache, real, yaml = sys.argv[1:5]
r = json.load(open(real))
def acct(n):
    return {"name": n, "config_dir": "/tmp/ca-test-nonexistent-" + n,
            "launcher": "claude-" + n, "email": n + "@example.com",
            "mailbox": n + "@example.com", "dia_profile": n.upper()}
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": yaml, "dia_local_state": "/nonexistent/LS",
  "cache_file": cache,
  # DERIVED from the real SSOT — never hand-copied. cache_grace_s is the bound inherit_k reads,
  # so a literal here would assert against a number production does not use.
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [acct(n) for n in ("next", "next2", "next3", "next4")],
}, open(cfg_path, "w"))
PY
}

# Load the module without running the CLI (extensionless + __main__-guarded), with LOG_PATH and
# LASTGOOD_PATH redirected into the sandbox — both resolve at import from $HOME.
LOAD='
import importlib.machinery, importlib.util, os, json, time
from datetime import datetime, timezone
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
cfg = json.load(open(os.environ["CA_CFG"]))
R = cfg["router"]
GRACE = cfg["cache_grace_s"]
NAMES = [a["name"] for a in cfg["accounts"]]
WIN_OPEN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat()
def healthy():
    """A sweep that succeeds at everything EXCEPT the census — creds readable, usage 200."""
    ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 9e12}, "present")
    ca.fetch_usage = lambda *a, **k: (200, {"limits": [
        {"kind": "session", "percent": 5, "resets_at": None},
        {"kind": "weekly_all", "percent": 20, "resets_at": None}]})
def starved():
    """The measured failure: concurrency() returns None for the WHOLE fleet, not per row — and
    the transcript walk is over budget too. §4 records that this pairing is not a contrivance:
    across 17,059 utilization rows, ZERO have `k is None` with `k_work` measured. Both censuses
    read the same starved box, so they starve together, which is why `concurrency-unmeasured`
    (whose condition is textually "both instruments failed") fires at all."""
    ca.concurrency = lambda c: None
    ca.working_concurrency = lambda c: None
def measured(k):
    """A live PANE census with the walk still over budget — the charge k_cap calls RESIDENT, and
    the only shape in which `k` is what routing reads."""
    ca.concurrency = lambda c: {n: k for n in NAMES}
    ca.working_concurrency = lambda c: None
'

# ── 1. the abstention closes ───────────────────────────────────────────────────────────────────

@test "a starved ps no longer excludes the whole fleet: the previous census is inherited" {
  run python3 -c "$LOAD"'
healthy(); measured(2)
live = ca.collect(cfg, no_heal=True)                        # sweep 1: the census works
assert [r["k"] for r in live] == [2, 2, 2, 2], live
assert all(not r.get("k_stale") for r in live), "a LIVE census must never be marked stale"
prev = {"ts": time.time(), "rows": {r["acct"]: r for r in live}}

starved()                                                   # sweep 2: ps blows its budget
rows = ca.collect(cfg, no_heal=True, prev=prev)
assert [r["k"] for r in rows] == [2, 2, 2, 2], rows
assert all(r["k_stale"] is True for r in rows), rows
assert all(ca.k_src(r) == "panes" for r in rows), [ca.k_src(r) for r in rows]
# THE POINT: every account is routable again, so --route yields an account instead of `none`
# and the launcher stops falling through to the pinned (most-drained) one.
assert all(ca._excluded(r, R, cliff=False) is None for r in rows), \
    [(r["acct"], ca._excluded(r, R, cliff=False)) for r in rows]
cand, reasons = ca.ranked(rows, cfg, WIN_OPEN, "general")
assert cand, ("the router still abstains", reasons)

# MUTANT — the pre-fix producer: _prev_snapshot did not project `k`, so nothing was inheritable.
prev_nok = {"ts": time.time(),
            "rows": {n: {"session_pct": 5, "weekly_pct": 20} for n in NAMES}}
mut = ca.collect(cfg, no_heal=True, prev=prev_nok)
assert all(r["k"] is None for r in mut), mut
assert all(ca._excluded(r, R, cliff=False) == "concurrency-unmeasured" for r in mut), \
    "MUTANT DID NOT FIRE: the fleet-wide exclusion is unreproducible, so this case proves nothing"
assert not ca.ranked(mut, cfg, WIN_OPEN, "general")[0], "MUTANT DID NOT FIRE: the router still routed"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "_prev_snapshot projects the census and its provenance out of the cache" {
  run python3 -c "$LOAD"'
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg),
           "rows": [{"acct": "next3", "session_pct": 5, "weekly_pct": 20,
                     "k": 4, "k_stale": True, "k_as_of": iso(time.time() - 100)}]},
          open(cfg["cache_file"], "w"))
pr = ca._prev_snapshot(cfg)["rows"]["next3"]
for f in ("k", "k_as_of", "k_stale"):
    assert f in pr, ("%s is not projected, so inherit_k can never fire" % f)
assert pr["k"] == 4 and pr["k_stale"] is True
# The burn-delta consumer, which shares this projection, keeps its own fields.
for f in ("session_pct", "weekly_pct", "fable_pct", "quota_as_of", "stale_quota"):
    assert f in pr, f
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ── 2. the bound binds, and carried provenance is what makes it bind ───────────────────────────

@test "provenance is carried, never re-dated — so re-inheritance cannot outlive the grace" {
  run python3 -c "$LOAD"'
r1 = {"acct": "next3", "k": None}
assert ca.inherit_k(r1, {"ts": time.time() - 300, "rows": {"next3": {"k": 3}}}, GRACE) is True
assert r1["k"] == 3 and r1["k_stale"] is True
# Sweep N+1 reads the INHERITED row back out of the cache (get_data writes it there and
# _prev_snapshot reads it back), so this is the ORDINARY path under sustained starvation.
r2 = {"acct": "next3", "k": None}
assert ca.inherit_k(r2, {"ts": time.time(), "rows": {"next3": r1}}, GRACE) is True
assert r2["k_as_of"] == r1["k_as_of"], \
    "RE-DATED: the stamp moved to now, so a census of any age would report fresh forever"
# ...and once the ORIGINAL measurement is past the grace, inheritance stops. The carried stamp is
# what makes that reachable at all: a re-dated one would keep this row alive indefinitely.
old = {"acct": "next3", "k": 3, "k_stale": True, "k_as_of": iso(time.time() - GRACE - 1)}
r3 = {"acct": "next3", "k": None}
assert ca.inherit_k(r3, {"ts": time.time(), "rows": {"next3": old}}, GRACE) is False
assert r3["k"] is None and ca.k_src(r3) == "unmeasured"
assert ca._excluded(dict(r3, session_pct=10, session_reset_h=3.0, weekly_pct=20), R,
                    cliff=False) == "concurrency-unmeasured"
# ...and one second inside the grace still inherits, so the bound is a bound and not an off switch.
fresh = dict(old, k_as_of=iso(time.time() - GRACE + 30))
r4 = {"acct": "next3", "k": None}
assert ca.inherit_k(r4, {"ts": time.time(), "rows": {"next3": fresh}}, GRACE) is True

# MUTANT — stamp `now` on every pass (the re-dating defect inherit_lastgood documents for quota).
def mutant(row, prev, grace_s):
    pr = (prev or {}).get("rows", {}).get(row["acct"])
    if row.get("k") is not None or not pr or pr.get("k") is None:
        return False
    row["k"], row["k_stale"], row["k_as_of"] = pr["k"], True, iso(time.time())
    return True
m = {"acct": "next3", "k": None}
assert mutant(m, {"ts": time.time(), "rows": {"next3": old}}, GRACE) is True, \
    "MUTANT DID NOT FIRE: an unbounded inheritance is unreproducible here"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "an undateable, absent or already-unmeasured previous census is refused, never assumed" {
  run python3 -c "$LOAD"'
cases = [
    ({"ts": None, "rows": {"next3": {"k": 3}}},                     "no snapshot ts"),
    ({"ts": time.time(), "rows": {"next3": {"k": None}}},           "prev census also unmeasured"),
    ({"ts": time.time(), "rows": {}},                               "account absent from prev"),
    (None,                                                          "no prev at all"),
    ({"ts": time.time(),
      "rows": {"next3": {"k": 3, "k_stale": True, "k_as_of": "not-a-date"}}}, "unparseable stamp"),
    ({"ts": time.time(),
      "rows": {"next3": {"k": 3, "k_stale": True, "k_as_of": None}}}, "stale with no stamp"),
]
for prev, why in cases:
    r = {"acct": "next3", "k": None}
    assert ca.inherit_k(r, prev, GRACE) is False, why
    assert r.get("k") is None and r.get("k_stale") is None, (why, r)
# A LIVE census is never overwritten — inheritance only ever fills an absence, including k == 0,
# which is a measurement (an idle account) and not a gap.
r = {"acct": "next3", "k": 0}
assert ca.inherit_k(r, {"ts": time.time(), "rows": {"next3": {"k": 3}}}, GRACE) is False
assert r["k"] == 0 and r.get("k_stale") is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ── 3. the rotation-safety half, which may never weaken ────────────────────────────────────────

@test "ROTATION SAFETY: heal() still receives an UNMEASURED census and refuses to redeem" {
  run python3 -c "$LOAD"'
healthy(); starved()
# A stale token that 401s is the shape that reaches the heal branch.
ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 1000,
                               "refreshToken": "rt"}, "present")
ca.fetch_usage = lambda *a, **k: (401, {})
real_heal = ca.heal
seen = []
def spy(cfg_, acct, rt, k_live):
    seen.append(k_live)
    return real_heal(cfg_, acct, rt, k_live)      # the REAL gate decides; the spy only records
ca.heal = spy
prev = {"ts": time.time(), "rows": {n: {"k": 1} for n in NAMES}}
rows = ca.collect(cfg, no_heal=False, prev=prev)
# The rows carry the inherited census — routing gets its number...
assert all(r["k"] == 1 and r["k_stale"] is True for r in rows), rows
# ...and heal() was handed None anyway, because inherit_k stamps AFTER the probes return.
assert seen and all(k is None for k in seen), \
    ("FAIL-OPEN: heal() received an INHERITED count as k_live (%r). An inherited count is up to "
     "cache_grace_s old and cannot prove a rotation race is not in flight." % (seen,))
# And the real gate did what the None contract says: refused, naming the reason.
assert all("UNMEASURABLE" in (r.get("heal_note") or "") for r in rows), \
    [r.get("heal_note") for r in rows]

# MUTANT — stamping the inherited value INSIDE probe_account would hand heal() the number
# instead of None. That the gate DISCRIMINATES on it (a k_live of 0 is refused for an entirely
# different reason, never as UNMEASURABLE) is what makes the two assertions above meaningful
# rather than vacuously true of any refusal.
ok0, why0 = real_heal(cfg, cfg["accounts"][0], "rt", 0)
assert "UNMEASURABLE" not in why0, \
    ("MUTANT DID NOT FIRE: k_live=0 also reads UNMEASURABLE (%r), so the gate does not "
     "discriminate and this case proves nothing about placement" % why0)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ── 4. an inherited number never presents as a measurement ─────────────────────────────────────

@test "the utilization series flags an inherited census so a replay cannot re-count it" {
  run python3 -c "$LOAD"'
path = os.path.join(os.environ["BATS_TEST_TMPDIR"], "util.jsonl")
live = {"acct": "next3", "k": 2, "session_pct": 5, "weekly_pct": 20}
inh = {"acct": "next2", "k": 2, "k_stale": True, "k_as_of": iso(time.time() - 60),
       "session_pct": 5, "weekly_pct": 20}
assert ca.record_utilization([live, inh], path=path, min_interval_s=0) == 2
recs = {json.loads(l)["acct"]: json.loads(l) for l in open(path)}
assert recs["next3"]["k_stale"] is False, recs["next3"]
assert recs["next3"]["k_as_of"] is None, recs["next3"]
assert recs["next2"]["k_stale"] is True and recs["next2"]["k_as_of"], recs["next2"]
# Both rows are KEPT — the series must never gap, or "we could not measure" becomes
# indistinguishable from "nothing was happening" (record_utilization own rule).
assert set(recs) == {"next3", "next2"}, recs
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "pool-floor.sh skips an inherited census — an inherited number is not a measurement" {
  # The floor is a MAX over OBSERVATIONS. Under sustained starvation one live census would be
  # re-counted on every sweep that re-inherited it, freezing the fleet figure at whatever that
  # sweep happened to catch and presenting a replay of it as an ongoing observation.
  local util="$BATS_TEST_TMPDIR/pf-util.jsonl" cap="$BATS_TEST_TMPDIR/pf-cap.jsonl" out
  python3 - "$util" "$cap" <<'PY'
import json, sys
from datetime import datetime, timezone, timedelta
util_path, cap_path = sys.argv[1], sys.argv[2]
now = datetime.now(timezone.utc)
with open(util_path, "w") as u, open(cap_path, "w") as c:
    for i in range(40):
        ts = (now - timedelta(hours=40 - i)).isoformat()
        c.write(json.dumps({"ts": ts, "sessions": 5, "verdict": "OK", "swap_used_mb": 0}) + "\n")
        u.write(json.dumps({"ts": ts, "acct": "next3", "k": 1, "weekly_pct": 10,
                            "stale": False, "k_stale": False}) + "\n")
        # the inherited row claims a much larger census; only the k_stale arm can reject it
        u.write(json.dumps({"ts": ts, "acct": "next2", "k": 9, "weekly_pct": 10,
                            "stale": False, "k_stale": True}) + "\n")
PY
  run env CC_UTIL_LOG="$util" CC_CAP_LOG="$cap" CC_POOL_FLOOR_SPAN_H=1 \
      bash "$REPO/scripts/pool-floor.sh" --json
  [ "$status" -eq 0 ] || { echo "pool-floor exited $status: $output"; false; }
  echo "$output" | python3 -c '
import json, sys
pf = json.load(sys.stdin).get("pool_floor") or {}
per = pf.get("per_account") or {}
assert "next3" in per, ("the LIVE census was dropped too — the filter is over-wide: %r" % per)
assert "next2" not in per, ("INHERITED CENSUS COUNTED AS AN OBSERVATION: %r" % per)
' || { echo "$output"; false; }

  # MUTANT — drop the k_stale arm and the inherited row is counted. Proves the case can go red.
  local mut="$BATS_TEST_TMPDIR/pool-floor-mutant.sh"
  sed 's/if r.get("stale") or r.get("k_stale"):/if r.get("stale"):/' \
      "$REPO/scripts/pool-floor.sh" > "$mut"
  ! cmp -s "$mut" "$REPO/scripts/pool-floor.sh" || {
    echo "MUTANT NOT APPLIED: the k_stale arm is not where this test expects it"; false; }
  run env CC_UTIL_LOG="$util" CC_CAP_LOG="$cap" CC_POOL_FLOOR_SPAN_H=1 bash "$mut" --json
  [ "$status" -eq 0 ] || { echo "mutant exited $status: $output"; false; }
  echo "$output" | python3 -c '
import json, sys
pf = json.load(sys.stdin).get("pool_floor") or {}
per = pf.get("per_account") or {}
assert "next2" in per, ("MUTANT DID NOT FIRE: the fixture cannot distinguish the two arms, so "
                        "the assertion above proves nothing")
' || { echo "$output"; false; }
}

# ── 5. the instrument that can falsify the policy ──────────────────────────────────────────────

@test "route-meta carries k_age_s, so a decision made on an inherited census is auditable" {
  # §6's lesson applied to its own fix. The launcher's grace-band claim ("the band has never once
  # been entered") was unfalsifiable: the desk row schema carried no age at all, and the 931 rows
  # it quoted came from a different code path whose ages are bounded under 90s BY CONSTRUCTION.
  # A policy change that ships without the instrument that could refute it repeats exactly that.
  python3 - <<'PY'
import json, os, time, importlib.machinery, importlib.util
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
from datetime import datetime, timezone
as_of = datetime.fromtimestamp(time.time() - 240, timezone.utc).isoformat()
row = {"acct": "next3", "auth": "ok", "k": 2, "k_work": None, "k_stale": True, "k_as_of": as_of,
       "session_pct": 10, "session_reset_h": 3.0, "weekly_pct": 20, "weekly_reset_h": 100.0,
       "fable_pct": 10, "fable_reset_h": 24.0, "credits_on": False}
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None, "rows": [row]},
          open(os.environ["CACHE"], "w"))
PY
  run bash -c "python3 '$CA_BIN' --route general 2>&1 >/dev/null"
  [[ "$output" == *"route-meta: "* ]] || { echo "$output"; false; }
  # A NUMBER, not `-`: this decision stood on a census it did not take, and the age says how old.
  echo "$output" | grep -qE 'k_age_s=2[0-9][0-9]\b' || {
    echo "route-meta did not report the inherited census age:"; echo "$output"; false; }
  # ...and a LIVE census reports `-`, or the field would carry no information at all.
  python3 - <<'PY'
import json, os, time
c = json.load(open(os.environ["CACHE"]))
c["ts"] = time.time()
c["rows"][0].pop("k_stale"); c["rows"][0].pop("k_as_of")
json.dump(c, open(os.environ["CACHE"], "w"))
PY
  run bash -c "python3 '$CA_BIN' --route general 2>&1 >/dev/null"
  [[ "$output" == *"k_age_s=-"* ]] || { echo "$output"; false; }
}

@test "the board marks an inherited census with the SAME * it already gives inherited quota" {
  # Nothing branches on this — but the board is where the operator reads the fleet, and a
  # rendering that shows an inherited count identically to an observed one asserts a measurement
  # this sweep did not take. Same rule, same glyph, as inherited quota.
  run python3 -c "$LOAD"'
assert ca.k_cell({"k": None}) == "?"                 # unmeasured is NEVER a fabricated 0
assert ca.k_cell({"k": 0}) == "0"
assert ca.k_cell({"k": 0, "k_stale": True}) == "0*"  # an inherited zero is still not an observed one
assert ca.k_cell({"k": 3}) == "3"
assert ca.k_cell({"k": 3, "k_stale": True}) == "3*", \
    "an inherited census renders identically to an observed one"
# ONE derivation: both renderers must call it, or the rule is a copy nothing compares. Counted
# against the two known call sites plus the definition.
src = open(os.environ["CA_BIN"]).read()
assert src.count("k_cell(") >= 3, \
    ("a renderer re-spells the census cell instead of calling k_cell (%d sites)"
     % src.count("k_cell("))
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}
