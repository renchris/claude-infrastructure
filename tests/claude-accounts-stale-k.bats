#!/usr/bin/env bats
# inherit_k — the desk router stops excluding the WHOLE FLEET on one starved `ps` census.
#
# THE DEFECT (docs/research/desk-router-abstention-2026-09-01.md §4, backlog 1f6208064577).
# `concurrency()` returns None for the BOX, not per account, when its `ps` census blows its 10s
# budget. `k_src` reads that as 'unmeasured' and `_excluded` refuses on it FIRST, ahead of every
# other rule — so one starved census excluded all four accounts simultaneously and `--route`
# answered `none`. 68 of 230 recorded interactive decisions died exactly this way. And the refusal
# does not stop the launch: `claude()` falls through to `_claude_pinned`, so a mechanism built to
# SPREAD load concentrated every launch on `next` — the most-drained account in the fleet (73.0%
# weekly against 33.2% for the account the router would have picked).
#
# The census failure is starvation, not size: the only sweeper runs at ProcessType Background +
# LowPriorityIO, sweep p90 34s against a 1.9-2.5s foreground bench, while the walk itself measures
# 0.054s warm. That makes it TRANSIENT by construction — which is what licenses inheriting the last
# sweep's count instead of abstaining on it.
#
# WHAT THIS SUITE PINS, and it is three separate claims, not one:
#   1. ELIGIBILITY — an inheritable count admits the row, and a row with nothing to inherit still
#      refuses. This is the fix.
#   2. THE BOUND — inheritance is bounded by when the count was MEASURED, never by when it was last
#      COPIED. get_data writes inherited rows back into the cache and _prev_snapshot reads them back
#      out, so an account re-inherits its own inherited value every sweep; dating each copy "now"
#      would make a count of any age read as fresh forever. That is not hypothetical — it is the
#      exact bug inherit_lastgood's quota_as_of clause was written to fix, on the same store.
#   3. THE HALF OF THE None CONTRACT THAT MUST NOT WEAKEN — heal()'s rotation gate reads `k_live`
#      from probe_account's ARGUMENT. Inheritance runs after the probes and touches only row["k"],
#      so that gate still sees None and still refuses to redeem a token under sessions it cannot
#      count. Asserted by EXECUTION (the argument is recorded), never by reading the source order.
#
# Every case carries the mutant that reproduces the pre-fix behaviour, so a green here cannot be an
# accident of the assertion never firing.
#
# Hermetic: no network, no keychain, no real `ps`, no real cache. LOG_PATH is redirected in LOADCA.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO
  export CA_BIN="$REPO/bin/claude-accounts"
  export REAL_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  # The pane census is the ONLY census this suite is about. Leaving the transcript walk on would let
  # k_work answer for rows whose whole point is that no instrument did.
  export CC_ROUTE_KWORK=off
}

# Load the extensionless tool as a module without running its CLI (it is __main__-guarded), and
# point its log at the fixture so a sweep note never appends to the operator's live log.
LOADCA='
import importlib.machinery, importlib.util, os
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "ca.log")
import datetime as _dt

R = {"S_CUT": 0.85, "S_SOFT": 0.5, "SF_FLOOR": 0.05, "KMAX": 8, "KMAX_RESIDENT": 40,
     "KFLOOR": 0.1, "MARGIN_H": 0.5, "EPS_H": 0.25, "WEEKLY_FLOOR": 0.005,
     "FABLE_FLOOR": 0.02, "JB_BONUS": 1.25}

def row(**kw):
    """A routable row in every respect EXCEPT the concurrency charge under test."""
    r = {"acct": "next3", "session_pct": 10.0, "session_reset_h": 3.0, "weekly_pct": 20.0,
         "k": None, "k_work": None}
    r.update(kw)
    return r

def _iso(age_s):
    return (_dt.datetime.now(_dt.timezone.utc) - _dt.timedelta(seconds=age_s)).isoformat()

def prev(k=2, ts_age_s=60.0, stale=False, as_of_age_s=None, acct="next3"):
    """A _prev_snapshot-shaped dict. `ts_age_s` ages the SNAPSHOT (= a live count measured then);
    `stale`+`as_of_age_s` build a row that was ITSELF inherited, which is the re-inheritance case."""
    pr = {"k": k}
    if stale:
        pr["k_stale"] = True
        pr["k_as_of"] = _iso(as_of_age_s if as_of_age_s is not None else 60.0)
    ts = (_dt.datetime.now(_dt.timezone.utc)
          - _dt.timedelta(seconds=ts_age_s)).timestamp()
    return {"ts": ts, "rows": {acct: pr}}
'

# ---- 1. eligibility: the fleet-wide exclusion is what actually goes away ------------------------

@test "a starved ps census no longer excludes the row — the last sweep's k is inherited and routes" {
  run python3 -c "$LOADCA"'
# THE MUTANT: the pre-fix state. Same row, no inheritance applied — refused, and refused for a
# reason that fires on every account at once because concurrency() failed for the BOX.
bare = row()
assert ca.k_src(bare) == "unmeasured", ca.k_src(bare)
assert ca._excluded(bare, R, cliff=False) == "concurrency-unmeasured"

# THE FIX: a count measured 60s ago is inherited, and the row is routable again.
r = row()
assert ca.inherit_k(r, prev(k=2, ts_age_s=60.0), 600) is True
assert r["k"] == 2
assert r["k_stale"] is True
assert r["k_as_of"], "an inherited count MUST carry the stamp it was measured at"
assert ca.k_src(r) == "panes-stale", ca.k_src(r)
assert ca._excluded(r, R, cliff=False) is None, "THE FLEET-WIDE ABSTENTION IS BACK"

# ...and it is still a PANE count, so it is measured against the resident cap, not the active one.
assert ca.k_cap(r, R) == 40, ca.k_cap(r, R)
assert ca.k_eff(r) == 2, ca.k_eff(r)
over = row(); ca.inherit_k(over, prev(k=40, ts_age_s=60.0), 600)
assert ca._excluded(over, R, cliff=False) == "kmax-concurrency", "the cap must still bite"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "nothing to inherit still refuses — an outage is not laundered into a routable zero" {
  run python3 -c "$LOADCA"'
for label, p in (("no snapshot at all", None),
                 ("snapshot with no row for this account", {"ts": 0, "rows": {}}),
                 ("previous sweep also unmeasured", prev(k=None)),
                 ("previous k is not an integer", prev(k="2")),
                 ("snapshot carries no ts to date the count by", {"rows": {"next3": {"k": 2}}})):
    r = row()
    assert ca.inherit_k(r, p, 600) is False, label
    assert r["k"] is None, label
    assert "k_stale" not in r, label
    assert ca._excluded(r, R, cliff=False) == "concurrency-unmeasured", label

# A count from BEYOND the grace is an outage, not a slow sweep: back to unmeasured, and it must be
# the DATA class so callers degrade to a proxy instead of reading it as a fleet at capacity.
r = row()
assert ca.inherit_k(r, prev(k=2, ts_age_s=601.0), 600) is False
assert ca.reason_class(r, ca._excluded(r, R, cliff=False)) == "data"

# Clock skew fails CLOSED. A stamp far in the FUTURE dates to a negative age, which a bare
# `age <= grace` test reads as maximally fresh — admitting the row on a number nothing can date.
r = row()
assert ca.inherit_k(r, prev(k=2, ts_age_s=-4000.0), 600) is False, "future stamp must not admit"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "a MEASURED count is never overwritten by an inherited one" {
  run python3 -c "$LOADCA"'
r = row(k=3)
assert ca.inherit_k(r, prev(k=9, ts_age_s=1.0), 600) is False
assert r["k"] == 3
assert "k_stale" not in r, "a live count must never be marked stale"
assert ca.k_src(r) == "panes"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ---- 2. the bound is on MEASUREMENT age, not copy age -------------------------------------------

@test "re-inheritance self-terminates: the bound follows the measurement, not the copy" {
  run python3 -c "$LOADCA"'
# The store is a loop. get_data writes the inherited row back into the cache, _prev_snapshot reads
# it back out, so under a sustained census outage an account re-inherits its OWN inherited value
# every sweep. `ts` is refreshed by each of those sweeps, so a bound applied to `ts` never expires.
#
# THE MUTANT, stated as the two inputs that differ only in the field the bound must read: both
# snapshots are BRAND NEW (ts 0s old); their counts were measured 590s and 610s ago.
fresh_copy_old_count = prev(k=2, ts_age_s=0.0, stale=True, as_of_age_s=610.0)
fresh_copy_new_count = prev(k=2, ts_age_s=0.0, stale=True, as_of_age_s=590.0)

a = row()
assert ca.inherit_k(a, fresh_copy_new_count, 600) is True, "590s < grace — still inheritable"
assert a["k_stale"] is True

b = row()
assert ca.inherit_k(b, fresh_copy_old_count, 600) is False, \
    "A BOUND ON COPY AGE: a 610s-old count rode a 0s-old copy and read as fresh"
assert ca._excluded(b, R, cliff=False) == "concurrency-unmeasured"

# Provenance is CARRIED, never re-dated: the inherited row keeps the original stamp, so the next
# hop measures against the same instant and the chain converges on expiry rather than diverging.
assert a["k_as_of"] == fresh_copy_new_count["rows"]["next3"]["k_as_of"]

# Walk the loop for real. Twenty generations of pure re-inheritance, each writing a BRAND NEW
# snapshot exactly as get_data does: the stamp must come out the far end unchanged. A single
# re-dating hop anywhere in the chain is all it takes to make the count immortal.
gen = fresh_copy_new_count
first = gen["rows"]["next3"]["k_as_of"]
for hop in range(20):
    r = row()
    assert ca.inherit_k(r, gen, 600) is True, hop
    assert r["k_as_of"] == first, "hop %d RE-DATED the stamp — the count is now immortal" % hop
    gen = {"ts": _dt.datetime.now(_dt.timezone.utc).timestamp(),
           "rows": {"next3": {"k": r["k"], "k_stale": True, "k_as_of": r["k_as_of"]}}}

# ...and the chain in that state ends the moment its ORIGINAL measurement ages out, however new
# the copy carrying it is. Run it as elapsed wall-clock rather than a hand-written stamp, so what
# terminates the loop is time passing, which is the only thing that terminates it in production.
import time
live = {"ts": _dt.datetime.now(_dt.timezone.utc).timestamp(), "rows": {"next3": {"k": 2}}}
warm = row()
assert ca.inherit_k(warm, live, 5.0) is True
time.sleep(0.15)
chain = {"ts": _dt.datetime.now(_dt.timezone.utc).timestamp(),
         "rows": {"next3": {"k": warm["k"], "k_stale": True, "k_as_of": warm["k_as_of"]}}}
cold = row()
assert ca.inherit_k(cold, chain, 0.1) is False, "the chain outlived its own measurement"
assert ca._excluded(cold, R, cliff=False) == "concurrency-unmeasured"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "_prev_snapshot projects the three fields inherit_k needs, through a real cache file" {
  run python3 -c "$LOADCA"'
import json, os
cache = os.path.join(os.environ["BATS_TEST_TMPDIR"], "cache.json")
cfg = {"cache_file": cache, "accounts": [{"name": "next3"}], "cache_grace_s": 600}
payload = {"cfg_key": ca._cfg_key(cfg), "ts": _dt.datetime.now(_dt.timezone.utc).timestamp(),
           "rows": [{"acct": "next3", "k": 5, "k_stale": True, "k_as_of": _iso(30.0),
                     "session_pct": 10.0, "weekly_pct": 20.0}]}
with open(cache, "w") as f:
    json.dump(payload, f)

snap = ca._prev_snapshot(cfg)
pr = snap["rows"]["next3"]
# THE MUTANT: before the fix the projection was a fixed tuple of quota fields only, so every one of
# these read None and inherit_k could not have been written at all.
for field in ("k", "k_stale", "k_as_of"):
    assert field in pr, field
    assert pr[field] is not None, field

r = row()
assert ca.inherit_k(r, snap, cfg["cache_grace_s"]) is True
assert r["k"] == 5
assert r["k_as_of"] == payload["rows"][0]["k_as_of"], "the disk stamp must survive the round trip"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ---- 3. the half of the None contract that must NOT weaken --------------------------------------

@test "heal()'s rotation gate still sees None: inheritance runs AFTER the probes, on row[k] only" {
  run python3 -c "$LOADCA"'
seen = []
def fake_probe(cfg, acct, kc, k_live, ledger, prev_, no_heal):
    # THE ASSERTION SUBJECT: whatever collect hands this argument is what heal() gates on. A token
    # redeem under N live sessions retires the token the loser is holding — a logout manufactured
    # by a missing measurement — so this must stay None even though ROUTING is being given a number.
    seen.append(k_live)
    return ({"acct": acct["name"], "auth": "ok", "k": k_live,
             "session_pct": 10.0, "session_reset_h": 3.0, "weekly_pct": 20.0}, None)

ca.concurrency = lambda cfg: None          # the starved census: None for the BOX, not per account
ca.probe_account = fake_probe
ca._ssl_warm = lambda: None
ca.load_lastgood = lambda: {}
ca.save_lastgood = lambda ledger: None

cfg = {"keychain_account": "tester", "cache_grace_s": 600,
       "accounts": [{"name": "next3", "email": "e", "dia_profile": "d", "launcher": "l",
                     "config_dir": "/x"}]}
rows = ca.collect(cfg, prev=prev(k=4, ts_age_s=45.0))

assert seen == [None], "collect handed the heal gate an INHERITED count: %r" % (seen,)
assert rows[0]["k"] == 4, "routing did not get the inherited count"
assert rows[0]["k_stale"] is True
assert ca._excluded(rows[0], R, cliff=False) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ---- 4. the fact reaches the consumers that already switch on k_src -----------------------------

@test "an inherited charge is MARKED everywhere it is reported — never rendered as a measurement" {
  run python3 -c "$LOADCA"'
import json, os
r = row()
ca.inherit_k(r, prev(k=7, ts_age_s=30.0), 600)

# The utilization series: a replay must be able to tell which instrument charged a row, or it
# cannot attribute an exclusion afterwards (the W2 replay had to ASSUME, and so settled nothing).
path = os.path.join(os.environ["BATS_TEST_TMPDIR"], "util.jsonl")
assert ca.record_utilization([r], path=path, min_interval_s=0) == 1
rec = json.loads(open(path).read().strip().splitlines()[-1])
assert rec["k"] == 7
assert rec["k_src"] == "panes-stale", rec["k_src"]

# The readout marks it with `*`, the file s one staleness glyph (pctc uses it for inherited
# quota). THE MUTANT: an unmarked cell renders identically to a count this sweep actually took.
cfg = json.load(open(os.path.join(os.environ["REPO"], "accounts.json")))
cfg["accounts"] = [{"name": "next3"}]
lines = ca.readout_lines([dict(r, auth="ok", email="e")], cfg, {"active": None}, False)
assert any("| 7* |" in ln for ln in lines), "\n".join(lines)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "END TO END: the desk lane picks the account instead of abstaining onto the pinned one" {
  # The claim the whole item is about, run through the real ranker rather than _excluded alone.
  # The pre-fix path is the mutant: identical rows, nothing to inherit, and the desk answers
  # `none` — at which point `claude()` falls through to `_claude_pinned` and every launch in the
  # window lands on `next`, the most-drained account in the fleet.
  run python3 -c "$LOADCA"'
import json, os
cfg = json.load(open(os.path.join(os.environ["REPO"], "accounts.json")))
names = ["next", "next2", "next3", "next4"]
cfg["accounts"] = [{"name": n} for n in names]

def fleet(inherit):
    out = []
    for i, n in enumerate(names):
        r = row(acct=n, session_pct=10.0 + i, weekly_pct=20.0 + i, auth="ok", email="e")
        if inherit:
            ca.inherit_k(r, prev(k=1, ts_age_s=45.0, acct=n), 600)
        out.append(r)
    return out

# THE MUTANT — the recorded 2026-09-01 04:43:05Z shape: every account excluded, one shared reason.
starved = fleet(False)
whys = {r["acct"]: ca._excluded(r, cfg["router"], cliff=False) for r in starved}
assert set(whys.values()) == {"concurrency-unmeasured"}, whys
pick, _ = ca.ranked(starved, cfg, {"active": None}, "interactive")
assert not pick, "expected the recorded fleet-wide abstention, got %r" % (pick,)

# THE FIX — the same starved census, one sweep of inheritance, and the desk has a winner again.
healed = fleet(True)
assert all(ca._excluded(r, cfg["router"], cliff=False) is None for r in healed)
pick, _ = ca.ranked(healed, cfg, {"active": None}, "interactive")
assert pick, "the desk lane still abstains with an inheritable count on every row"
assert pick[0][1]["acct"] in names
assert pick[0][1]["k_stale"] is True
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}
