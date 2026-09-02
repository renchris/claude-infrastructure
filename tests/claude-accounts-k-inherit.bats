#!/usr/bin/env bats
# claude-accounts — inherit_k: a starved `ps` census must not exclude the WHOLE FLEET
# (backlog 1f6208064577 · docs/research/desk-router-abstention-2026-09-01.md §4).
#
# THE DEFECT THIS SUITE PINS. `k_src()` reads 'unmeasured' iff `row["k"] is None`, whose sole
# producer is the `ps` census, and `_excluded()` refuses an unmeasured row ahead of every quota
# rule. The census does not fail per-account — it fails per-SWEEP (starved under
# ProcessType Background + LowPriorityIO: sweep p50 10.2s, p90 34.0s, against a hardcoded
# timeout=10), so one failure removed all four accounts at once: 68 of 230 recorded interactive
# decisions abstained on `concurrency-unmeasured`, every one excluding the entire fleet. And the
# abstention does not stop the launch — `claude()` falls through to `_claude_pinned` — so a
# mechanism built to SPREAD load concentrated every one of those launches onto `next`, the
# most-drained account of the four.
#
# The fix inherits the previous sweep's pane census, bounded by the same cache_grace_s (600s)
# the quota numbers already ride, onto its own field.
#
# 🚨 THE HALF THAT MUST NOT WEAKEN, and why half this file is about it. `row["k"]` is read as a
# LIVE liveness fact by three token-lifecycle gates — heal()'s rotation gate, handoff-fire.sh's
# Phase-1 headless relogin (`.k == 0` authorises a refresh-token redeem), and cc-relogin-poll's
# skipped-busy gate — and all three treat it as an AUTHORIZATION whose None case must refuse. An
# inherited count written into `k` would re-key them onto a value up to 10 minutes old in the
# fail-OPEN direction: a session started inside that window is invisible to a census taken before
# it, so `k` would read 0 and a headless redeem would proceed underneath a running CC. So the
# cases below assert not only that eligibility is restored but that `k` itself is untouched.
#
# Every case carries its MUTANT — the one-line edit to the fixed tree that reproduces the
# pre-fix behaviour — and each mutant was executed and confirmed RED before this file landed.
#
# Technique matches claude-accounts-parallel-collect.bats: import the module extensionless (it is
# __main__-guarded, so importing runs no CLI) and stub the world as module attributes.
#
# HERMETICITY: LOG_PATH, the ledger paths and CFG_PATH all resolve from $HOME at IMPORT time, so
# $HOME is fixtured before anything imports. The cache file is redirected per-case through cfg,
# never through the /tmp default, so a run cannot read or clobber the live fleet's sweep.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_LOG="$BATS_TEST_TMPDIR/claude-accounts.log"
  export CA_LEDGER="$BATS_TEST_TMPDIR/lastgood.json"
  export CA_CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CA_UTIL="$BATS_TEST_TMPDIR/account-utilization.jsonl"
  # The two kill switches this suite's subject sits behind. Pinned ON explicitly rather than
  # left to the default: a test that passes only because nobody exported the switch is a test
  # of the operator's environment.
  export CC_ROUTE_K_INHERIT=on
  export CC_ROUTE_KWORK=on
}

_pre() {
  cat <<'PY'
import importlib.machinery, importlib.util, json, os, time
_ld = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", _ld))
_ld.exec_module(ca)
ca.LOG_PATH = os.environ["CA_LOG"]
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca._rejected_path = lambda: os.environ["CA_REJECTED"] if "CA_REJECTED" in os.environ else "/dev/null"

GRACE = 600

def mkcfg(n=4):
    return {"keychain_account": "test", "usage_endpoint": "http://127.0.0.1:9/never",
            "user_agent": "test", "cache_file": os.environ["CA_CACHE"],
            "cache_ttl_s": 90, "cache_grace_s": GRACE,
            "frontier": {"scoped_display_name": "Fable"},
            "router": {"S_CUT": 0.95, "S_SOFT": 0.70, "EPS_H": 0.25, "MARGIN_H": 0.0,
                       "SF_FLOOR": 0.1, "KFLOOR": 0.1, "WEEKLY_FLOOR": 0.02,
                       "KMAX": 8, "KMAX_RESIDENT": 40, "NO_RESET_H": 168.0,
                       "URGENCY_EXP": 2.0},
            "accounts": [{"name": f"a{i}", "config_dir": f"/tmp/ca-nonexistent-{i}",
                          "launcher": f"l{i}", "email": f"a{i}@example.com",
                          "dia_profile": f"P{i}"} for i in range(n)]}

def healthy(acct, **kw):
    """A row that is routable on every axis EXCEPT whatever the case is testing."""
    r = {"acct": acct, "session_pct": 10.0, "weekly_pct": 20.0, "fable_pct": 5.0,
         "session_reset_h": 4.0, "weekly_reset_h": 100.0, "k": 0, "k_work": None}
    r.update(kw)
    return r

def snap(ts, rows):
    """A _prev_snapshot-shaped value: {"ts": epoch, "rows": {acct: projected-fields}}."""
    return {"ts": ts, "rows": rows}
PY
}

# ---- 1. the fleet-wide exclusion, and that inheritance ends it -------------------------------

@test "_excluded: a starved ps census excludes EVERY account — the fleet-wide abstention" {
  # The pre-fix state, asserted directly so the rest of the file has a control. This is not a
  # regression guard, it is the DEFECT: k=None on all four (one starved sweep) and all four are
  # refused, which is what makes `claude` fall through to the pinned account.
  run python3 -c "$(_pre)"'
cfg = mkcfg(4)
rows = [healthy(f"a{i}", k=None) for i in range(4)]
reasons = [ca._excluded(r, cfg["router"]) for r in rows]
assert reasons == ["concurrency-unmeasured"] * 4, reasons
assert all(ca.k_src(r) == "unmeasured" for r in rows)
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "inherit_k: the previous sweep's census restores eligibility for the whole fleet" {
  # MUTANT (confirmed RED): drop the k_stale rung from k_src — `return "unmeasured"` in place of
  # the panes-stale test. Every row goes back to concurrency-unmeasured and the fleet is excluded
  # again, which is exactly the state case 1 pins.
  run python3 -c "$(_pre)"'
cfg = mkcfg(4)
now = time.time()
prev = snap(now - 120, {f"a{i}": {"k": 3} for i in range(4)})
rows = [healthy(f"a{i}", k=None) for i in range(4)]
for r in rows:
    assert ca.inherit_k(r, prev, GRACE, now=now) is True

assert [ca.k_src(r) for r in rows] == ["panes-stale"] * 4
assert [ca._excluded(r, cfg["router"]) for r in rows] == [None] * 4
# The charge is the inherited count, not a fabricated zero — a 0 here would be the fail-open
# direction the None contract exists to abolish.
assert [ca.k_eff(r) for r in rows] == [3] * 4
# A resident census gets the RESIDENT cap, never the ACTIVE one (k_cap keys off k_src, and 8 vs
# 40 is a 5x difference in the exclusion threshold).
assert [ca.k_cap(r, cfg["router"]) for r in rows] == [40] * 4
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

# ---- 2. the safety half: `k` keeps meaning "live, or refuse" ---------------------------------

@test "inherit_k: row['k'] is NEVER written — the three liveness gates read a starved census as None" {
  # THE case this suite exists for. MUTANT (confirmed RED): make inherit_k assign row["k"] = val
  # (the filing's own sketch). `.k` then reads 0 for a 120s-old census and handoff-fire's Phase-1
  # gate — `[ "${k:-0}" = 0 ]` — authorises a headless refresh-token redeem underneath whatever
  # started in that window.
  run python3 -c "$(_pre)"'
now = time.time()
prev = snap(now - 120, {"a0": {"k": 0}})
row = healthy("a0", k=None)
assert ca.inherit_k(row, prev, GRACE, now=now) is True

# The inherited value lands in its OWN field...
assert row["k_stale"] == 0, row
assert row["k_stale_as_of"] == now - 120
# ...and `k` is still absent-as-None, which is what every consumer of the live census reads.
assert row["k"] is None, row["k"]

# The exact expression handoff-fire.sh:5986 evaluates over the --json row. It must still spell
# the word, because the word is what its `[ "$k" = unmeasured ]` arm refuses on.
k_as_shell = row["k"] if isinstance(row["k"], (int, float)) and not isinstance(row["k"], bool) \
             else "unmeasured"
assert k_as_shell == "unmeasured", k_as_shell

# The rotation gate inside heal() reads its k_live ARGUMENT, so an inherited row cannot reach it at all
# — but assert the refusal directly rather than trusting the call graph to stay that shape.
ok, detail = ca.heal(mkcfg(1), {"name": "a0"}, "rt", None)
assert ok is False and "unmeasured" in detail.lower() or ok is False, detail
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "collect: the inherited stamp lands AFTER the probes, so heal still sees k_live=None" {
  # The placement claim, executed. probe_account receives k_live from concurrency(); when that
  # returns None every probe must be called with None even though the finalisation loop is about
  # to stamp an inherited count on the same rows.
  # MUTANT (confirmed RED): move the inherit_k call above `ex.map` / into probe_account's row
  # construction — the recorded k_live arguments become [3,3,3,3] and the rotation gate opens.
  run python3 -c "$(_pre)"'
cfg = mkcfg(2)
now = time.time()
prev = snap(now - 60, {"a0": {"k": 3}, "a1": {"k": 5}})
seen = []
def fake_probe(cfg, acct, kc, k, ledger, prev, no_heal):
    seen.append((acct["name"], k))
    return {"acct": acct["name"], "auth": "ok", "k": k}, None
ca.probe_account = fake_probe
ca.concurrency = lambda cfg: None                 # the starved census
ca.working_concurrency = lambda cfg, window_min=None, budget_s=None: None

rows = ca.collect(cfg, no_heal=True, prev=prev)
assert sorted(seen) == [("a0", None), ("a1", None)], seen      # heal saw NO count
assert [r["k"] for r in rows] == [None, None], rows            # and the field stayed None
assert [r["k_stale"] for r in rows] == [3, 5], rows            # while eligibility was restored
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "collect: a LIVE census is never overwritten by an inherited one" {
  # Precedence, in the direction that matters: a measured 0 must beat a stale 4, or the fix would
  # replace a good instrument with a worse one whenever the previous sweep read higher.
  run python3 -c "$(_pre)"'
cfg = mkcfg(1)
now = time.time()
prev = snap(now - 60, {"a0": {"k": 4}})
ca.probe_account = lambda cfg, acct, kc, k, ledger, prev, no_heal: (
    {"acct": acct["name"], "auth": "ok", "k": k}, None)
ca.concurrency = lambda cfg: {"a0": 0}
ca.working_concurrency = lambda cfg, window_min=None, budget_s=None: None

rows = ca.collect(cfg, no_heal=True, prev=prev)
assert rows[0]["k"] == 0, rows
assert "k_stale" not in rows[0], rows              # nothing inherited, nothing stamped
assert ca.k_src(rows[0]) == "panes"
assert ca.k_eff(rows[0]) == 0
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

# ---- 3. the bound, and that it is reachable --------------------------------------------------

@test "inherit_k: a census older than cache_grace_s is REFUSED, not clamped" {
  # MUTANT (confirmed RED): delete the `age > grace_s` test. A census of any age is inherited and
  # the 600s bound — the whole basis for calling this safe — stops existing.
  run python3 -c "$(_pre)"'
now = time.time()
for age, want in ((0, True), (599, True), (600, True), (601, False), (86400, False)):
    row = healthy("a0", k=None)
    got = ca.inherit_k(row, snap(now - age, {"a0": {"k": 2}}), GRACE, now=now)
    assert got is want, (age, got, want)
    assert ("k_stale" in row) is want, (age, row)
    assert ca.k_src(row) == ("panes-stale" if want else "unmeasured"), age
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "inherit_k: a FUTURE stamp fails closed — an unknown age is not a young one" {
  # Clock step, or a cache written by a skewed box. A negative age passes `<= grace_s` on any
  # naive bound, so it would inherit a census of genuinely unknown age.
  # MUTANT (confirmed RED): drop the `age < 0` test — the future-stamped row inherits.
  run python3 -c "$(_pre)"'
now = time.time()
row = healthy("a0", k=None)
assert ca.inherit_k(row, snap(now + 3600, {"a0": {"k": 2}}), GRACE, now=now) is False
assert "k_stale" not in row
assert ca.k_src(row) == "unmeasured"
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "inherit_k: the chain ages off the ORIGINAL measurement, so an inherited k cannot become immortal" {
  # The defect inherit_lastgood already had to fix for quota_as_of: get_data writes the collected
  # rows back into the cache, _prev_snapshot reads them back out, so a row with no live census
  # re-inherits its OWN previously-inherited value every sweep. Re-dating each hop to that
  # ts of that snapshot would make the 600s bound unreachable and the count immortal.
  # MUTANT (confirmed RED): stamp `as_of = prev["ts"]` on the chained branch too — the loop below
  # never terminates and the assertion on the final age fails.
  run python3 -c "$(_pre)"'
now = time.time()
measured_at = now
# Sweep 0 measured k=6 live. Then 12 consecutive sweeps, 90s apart, all starved.
prev = snap(measured_at, {"a0": {"k": 6}})
inherited = 0
for i in range(1, 13):
    t = measured_at + 90 * i
    row = healthy("a0", k=None)
    if ca.inherit_k(row, prev, GRACE, now=t):
        inherited += 1
        assert row["k_stale"] == 6, row
        assert row["k_stale_as_of"] == measured_at, row   # the ORIGINAL stamp, every hop
    else:
        assert t - measured_at > GRACE, (i, t - measured_at)
        break
    # what the next sweep would read back out of the cache
    prev = snap(t, {"a0": {"k": None, "k_stale": row["k_stale"],
                           "k_stale_as_of": row["k_stale_as_of"]}})
# 90..600s inclusive is sweeps 1..6; sweep 7 (630s) is the first refusal.
assert inherited == 6, inherited
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "_prev_snapshot: the cache projection carries k, k_stale and k_stale_as_of" {
  # The chain above is only reachable if the projection actually forwards all three. Projecting
  # `k` alone terminates it after one hop; projecting `k_stale` alone loses the live seed.
  # MUTANT (confirmed RED): remove any one of the three names from the projection tuple.
  run python3 -c "$(_pre)"'
cfg = mkcfg(1)
with open(cfg["cache_file"], "w") as f:
    json.dump({"ts": 1000.0, "cfg_key": ca._cfg_key(cfg),
               "rows": [{"acct": "a0", "session_pct": 1.0, "weekly_pct": 2.0, "fable_pct": 3.0,
                         "k": None, "k_stale": 9, "k_stale_as_of": 900.0}]}, f)
p = ca._prev_snapshot(cfg)
assert p["ts"] == 1000.0, p
r = p["rows"]["a0"]
assert r["k"] is None and r["k_stale"] == 9 and r["k_stale_as_of"] == 900.0, r
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

# ---- 4. the kill switch, and the observability the filing required ---------------------------

@test "CC_ROUTE_K_INHERIT=off restores the pre-fix exclusion exactly" {
  # An eligibility POLICY change gets a switch that reverts it from the environment, per the R8
  # pattern every other M7/W1 term follows. Off must reach BOTH the stamping site and the
  # derivation — a switch that only stops new stamps would still admit rows from a cache written
  # while it was on.
  run python3 -c "$(_pre)"'
cfg = mkcfg(1)
now = time.time()
prev = snap(now - 60, {"a0": {"k": 3}})
ca.probe_account = lambda cfg, acct, kc, k, ledger, prev, no_heal: (
    {"acct": acct["name"], "auth": "ok", "k": k, "session_pct": 10.0, "weekly_pct": 20.0,
     "session_reset_h": 4.0, "weekly_reset_h": 100.0}, None)
ca.concurrency = lambda cfg: None
ca.working_concurrency = lambda cfg, window_min=None, budget_s=None: None

os.environ["CC_ROUTE_K_INHERIT"] = "off"
rows = ca.collect(cfg, no_heal=True, prev=prev)
assert "k_stale" not in rows[0], rows                       # not stamped
assert ca.k_src(rows[0]) == "unmeasured"
assert ca._excluded(rows[0], cfg["router"]) == "concurrency-unmeasured"

# ...and a row that WAS stamped (an older cache) is still not admitted while the switch is off.
stamped = healthy("a0", k=None, k_stale=3, k_stale_as_of=now - 60)
assert ca.k_src(stamped) == "unmeasured"
assert ca._excluded(stamped, cfg["router"]) == "concurrency-unmeasured"

os.environ["CC_ROUTE_K_INHERIT"] = "on"
assert ca.k_src(stamped) == "panes-stale"
assert ca._excluded(stamped, cfg["router"]) is None
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "record_utilization: an inherited charge is recorded WITH its value and its stamp" {
  # §6 of the filing: the policy change was withheld because the instrument that would let anyone
  # evaluate it did not exist. k_src alone says THAT the charge was inherited but never what it
  # was or how old — so a replay could not separate a decision made on a live census from one
  # made at the far end of the grace.
  # MUTANT (confirmed RED): drop k_stale/k_stale_as_of from the row dict the recorder writes.
  run python3 -c "$(_pre)"'
now = time.time()
path = os.environ["CA_UTIL"]
row = healthy("a0", k=None, k_stale=4, k_stale_as_of=now - 300)
assert ca.record_utilization([row], path=path) == 1
e = json.loads(open(path).read().strip())
assert e["k"] is None and e["k_stale"] == 4, e
assert e["k_src"] == "panes-stale", e
assert abs(e["k_stale_as_of"] - (now - 300)) < 1.0, e
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

@test "_k_stale_age: reports the age of the MEASUREMENT, and '-' on a live charge" {
  # The falsifiable number on the route-meta line. It must read off k_stale_as_of (which survives
  # every chain hop), not off the sweep that last copied the value.
  run python3 -c "$(_pre)"'
now = time.time()
live = healthy("a0", k=2)
assert ca._k_stale_age(live, now=now) == "-", ca._k_stale_age(live, now=now)
stale = healthy("a0", k=None, k_stale=2, k_stale_as_of=now - 450)
assert ca._k_stale_age(stale, now=now) == 450, ca._k_stale_age(stale, now=now)
# k_work present ⇒ the charge is ACTIVE, so the stale age is not the age of this decision.
both = healthy("a0", k=None, k_work=1, k_stale=2, k_stale_as_of=now - 450)
assert ca.k_src(both) == "work"
assert ca._k_stale_age(both, now=now) == "-"
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}

# ---- 5. the one derivation ------------------------------------------------------------------

@test "_k_base: k_eff, k_eff_desk and k_src agree about which instrument charged the row" {
  # The subject of account-fact-derivation.bats, applied to the third rung: the first two were already
  # spelled identically in k_eff and k_eff_desk, and a rung written twice is how every drift in
  # this file started. Asserted by EXECUTING all three over the same rows.
  run python3 -c "$(_pre)"'
now = time.time()
cases = [
    (healthy("a", k=2, k_work=1),                              "work",        1),
    (healthy("a", k=2),                                        "panes",       2),
    (healthy("a", k=None, k_stale=7, k_stale_as_of=now - 60),  "panes-stale", 7),
    (healthy("a", k=None),                                     "unmeasured",  0),
]
for row, want_src, want_eff in cases:
    assert ca.k_src(row) == want_src, (row, ca.k_src(row))
    assert ca.k_eff(row) == want_eff, (row, ca.k_eff(row))
    assert ca.k_eff_desk(row) == want_eff, (row, ca.k_eff_desk(row))
    # and the exemption on the desk lane still only ever REMOVES a phantom, never the charge
    row2 = dict(row, k_phantom=3, k_phantom_desk=0)
    assert ca.k_eff(row2) == want_eff + 3, row2
    assert ca.k_eff_desk(row2) == want_eff, row2
print("OK")
'
  [ "$status" -eq 0 ]
  [[ "$output" == *OK* ]] || false
}
