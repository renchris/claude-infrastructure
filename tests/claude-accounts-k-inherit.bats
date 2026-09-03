#!/usr/bin/env bats
# claude-accounts-k-inherit — the desk router inherits the last sweep's pane census, and the
# token-rotation gates do NOT.
#
# WHY THIS FILE EXISTS (docs/research/desk-router-abstention-2026-09-01.md §4, §7).
# `bin/claude-accounts`'s `ps` census is the SOLE producer of `k` for all four accounts, and it
# runs under `com.claude.accounts-keepwarm`'s `ProcessType: Background` + `LowPriorityIO`. Starved
# there, it blows its hardcoded 10s timeout on 501/501 recorded failures while the same walk
# measures 0.054s in the foreground. One instrument, four accounts ⇒ its failure excluded the
# WHOLE FLEET at once: `concurrency-unmeasured` was the single largest exclusion reason in the
# record, 68 of 230 desk decisions. And the refusal does not stop the launch — `claude()` falls
# through to `_claude_pinned`, so a mechanism built to SPREAD load concentrated every launch on
# the most-drained account (`next`, 73.0% weekly, against next3's 33.2%) for up to 600s at a time.
#
# THE SPLIT THIS SUITE PINS. `k is None` feeds two gates and only ONE may weaken:
#
#   · ROUTING eligibility — an instrument failure says nothing about whether an account is
#     usable, so abstaining there is the defect. It inherits.
#   · TOKEN ROTATION — `heal()`'s `k_live > 0` gate and `scripts/handoff-fire.sh`'s Phase-1
#     headless relogin gate. A redeem under N live sessions retires the token the losers hold
#     (400 invalid_grant — a logout manufactured by an unmeasured `ps`). It needs a PROVEN zero,
#     and a remembered zero is not one. It does NOT inherit.
#
# The filing note proposed stamping `row["k"]` itself. That would make every consumer not updated
# in the same diff fail OPEN, in exactly the rotation direction. The shipped shape puts the
# inherited count in a SEPARATE field (`k_stale`/`k_as_of`) so an un-updated reader keeps seeing
# `k = None` and keeps refusing — the un-updated case is the safe case. Three tests below are the
# assertions that the split still holds; each mutant is aimed at the one line that carries it.
#
# Hermetic: no network, no keychain, no real `ps`, no cache file. Every row is a literal dict and
# every clock is a fixture, because the whole subject here is what happens when the instruments
# are unavailable.

setup() {
  # handoff-fire's capacity_gate() refuses a net-new fire above 2.0/core and this box lives well
  # above that — a suite that leaves it live goes red BY LOAD, not by its subject.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO
  export CA_BIN="$REPO/bin/claude-accounts"
  export HF="$REPO/scripts/handoff-fire.sh"
  export REAL_HOME="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # The seams fixturing $HOME does NOT redirect: an ABSOLUTE /tmp default is not under $HOME,
  # and a BARE NAME is executed off the operator's PATH. tests/cc-relogin-status.bats fixtured
  # $HOME from birth and still counted the operator's live pending approvals and ran their
  # deployed claude-accounts once per test. An ABSENT path is the right pin here — this suite
  # never fires, never heals and never shells out to the CLI, so every sensor should fail open.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
}

# Load the extensionless tool as a module without running its CLI (it is __main__-guarded).
# Takes the source path from $1 so a mutant can be substituted for $CA_BIN unchanged.
LOADCA='
import importlib.machinery, importlib.util, os, sys, time
from datetime import datetime, timezone
_src = sys.argv[1] if len(sys.argv) > 1 else os.environ["CA_BIN"]
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", _src)))
importlib.machinery.SourceFileLoader("ca", _src).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "ca.log")
NOW = time.time()
R = {"KMAX": 8, "KMAX_RESIDENT": 40, "S_CUT": 0.80, "S_SOFT": 0.50, "SF_FLOOR": 0.25,
     "EPS_H": 0.25, "MARGIN_H": 0.0, "NO_RESET_H": 168.0, "KFLOOR": 0.05,
     "WEEKLY_FLOOR": 0.02}
def row(**kw):
    r = {"acct": "next3", "session_pct": 10.0, "session_reset_h": 3.0, "weekly_pct": 20.0,
         "k": None, "k_work": None}
    r.update(kw); return r
def prev(age_s, **fields):
    """A _prev_snapshot-shaped memory whose sweep ran age_s seconds ago."""
    return {"ts": NOW - age_s, "rows": {"next3": fields}}
def iso(age_s):
    return datetime.fromtimestamp(NOW - age_s, timezone.utc).isoformat()
'

# ---- 1. the routing half: a starved ps no longer excludes the fleet --------------------------

@test "k-inherit: a row whose ps failed inherits the last sweep's census and becomes ROUTABLE" {
  # The whole point. Before this, k=None ⇒ k_src 'unmeasured' ⇒ _excluded 'concurrency-unmeasured'
  # ⇒ the desk lane answered `none` while holding a census 30 seconds old.
  run python3 -c "$LOADCA"'
r = row()
assert ca._excluded(r, R, cliff=False) == "concurrency-unmeasured", "premise moved"
assert ca.inherit_k(r, prev(30, k=3), 600, ts=NOW - 30) is True
assert r["k_stale"] == 3, r
assert ca.k_src(r) == "panes-stale", ca.k_src(r)
assert ca._excluded(r, R, cliff=False) is None, "STILL ABSTAINING on an inherited census"
assert ca.k_eff(r) == 3, ca.k_eff(r)
assert ca.k_eff_desk(r) == 3, ca.k_eff_desk(r)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "k-inherit: the inherited census is CHARGED, not waived — kmax still binds on it" {
  # The fallback it replaces was `r.get("k", 0)` → 0, i.e. an unmeasured row charged NOTHING.
  # Inheriting must not become a second way to admit a pile-on: the count is charged in full,
  # against the RESIDENT cap (it is the pane census remembered, so it answers the resident
  # question — charging it against KMAX=8 would refuse the 9th resident session fleet-wide for
  # as long as ps stayed starved, reinstating the 33rd-session wall on the least-defensible rows).
  run python3 -c "$LOADCA"'
r = row()
ca.inherit_k(r, prev(30, k=R["KMAX_RESIDENT"]), 600, ts=NOW - 30)
assert ca.k_cap(r, R) == 40, ca.k_cap(r, R)
assert ca._excluded(r, R, cliff=False) == "kmax-concurrency"
r2 = row()
ca.inherit_k(r2, prev(30, k=R["KMAX_RESIDENT"] - 1), 600, ts=NOW - 30)
assert ca._excluded(r2, R, cliff=False) is None
# phantoms still add on top of an inherited base, exactly as on a live one
r3 = row(k_phantom=2)
ca.inherit_k(r3, prev(30, k=5), 600, ts=NOW - 30)
assert ca.k_eff(r3) == 7, ca.k_eff(r3)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "k-inherit: the 600s grace is measured on the MEASUREMENT, and survives re-inheritance" {
  # The inherited row is written back into the cache with k=None, so a `k`-only memory would
  # expire after exactly ONE sweep — useless against the dominant failure, which is a RUN of
  # starved sweeps (p90 34s against a 90s TTL). k_as_of is carried forward UNCHANGED, so the
  # bound is 600s from the last real ps, never 600s from the last attempt (the same re-dating
  # defect inherit_lastgood was fixed for).
  run python3 -c "$LOADCA"'
first = row()
ca.inherit_k(first, prev(30, k=3), 600, ts=NOW - 30)
stamp = first["k_as_of"]
# sweep 2 reads sweep 1s inherited row back: same value, same stamp, NOT re-dated to now
second = row()
assert ca.inherit_k(second, prev(5, k=None, k_stale=3, k_as_of=stamp), 600, ts=NOW - 5) is True
assert second["k_stale"] == 3 and second["k_as_of"] == stamp, second
# past the grace the memory stops being evidence about now, and the honest answer is refusal
late = row()
assert ca.inherit_k(late, prev(5, k=None, k_stale=3, k_as_of=iso(900)), 600, ts=NOW - 5) is False
assert ca.k_src(late) == "unmeasured"
assert ca._excluded(late, R, cliff=False) == "concurrency-unmeasured"
assert ca.reason_class(late, "concurrency-unmeasured") == "data", "must stay exit 3, not a HALT"
# an unparseable/absent stamp is UNKNOWN age, and unknown is out of grace
blind = row()
assert ca.inherit_k(blind, prev(5, k=None, k_stale=3, k_as_of=None), 600, ts=NOW - 5) is False
assert ca.inherit_k(row(), prev(5, k=None, k_stale=3, k_as_of="not-a-date"), 600,
                    ts=NOW - 5) is False
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "k-inherit: a MEASURED census is never overwritten, and absence of memory is not a zero" {
  run python3 -c "$LOADCA"'
live = row(k=7)
assert ca.inherit_k(live, prev(5, k=99), 600, ts=NOW - 5) is False
assert live["k"] == 7 and "k_stale" not in live
assert ca.k_src(live) == "panes"
# no prev, an empty prev, and a prev whose own k was unmeasured all inherit NOTHING — and the
# row stays unmeasured rather than degrading to the fabricated 0 the None contract abolished.
for p in (None, {"ts": NOW, "rows": {}}, prev(5, k=None), prev(5, k=None, k_stale=None)):
    r = row()
    assert ca.inherit_k(r, p, 600, ts=NOW) is False, p
    assert ca.k_src(r) == "unmeasured"
    assert ca._excluded(r, R, cliff=False) == "concurrency-unmeasured"
# a genuinely idle fleet still inherits its ZERO — 0 is a measurement, not an absence
z = row()
assert ca.inherit_k(z, prev(30, k=0), 600, ts=NOW - 30) is True
assert z["k_stale"] == 0 and ca.k_src(z) == "panes-stale"
assert ca._excluded(z, R, cliff=False) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ---- 2. the rotation half: the half of the None contract that must NEVER weaken ---------------

@test "k-inherit: an inherited census NEVER reaches heal()'s rotation gate" {
  # heal() refuses on k_live is None. The inheritance must leave row["k"] alone, so the argument
  # collect() passes down (k_of_name(name), None when ps failed) still carries the refusal — and
  # a row that inherited a ZERO must not become a redeem authorisation.
  run python3 -c "$LOADCA"'
r = row()
ca.inherit_k(r, prev(30, k=0), 600, ts=NOW - 30)
assert r["k"] is None, "STAMPED row[k] — every unupdated .k consumer now fails OPEN"
ok, detail = ca.heal({}, {"name": "next3"}, "rt", None)
assert ok is False, (ok, detail)
assert "unmeasurable" in detail.lower(), detail
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "k-inherit: handoff-fire's Phase-1 relogin gate reads .k only, so it still refuses" {
  # The gate compares `$k` for EQUALITY to 0 after jq maps a null .k to the word "unmeasured".
  # An inherited row emits k=null, so the word still reaches it. Two assertions, because the
  # danger is a future edit ADDING the field: the jq producer must not read .k_stale at all.
  run python3 -c "$LOADCA"'
import json
r = row(acct="next3", auth="token-invalid", auth_actionable=True)
ca.inherit_k(r, prev(30, k=0), 600, ts=NOW - 30)
print(json.dumps({"rows": [r]}))'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # the exact jq expression handoff-fire.sh uses on the sweep document
  k="$(printf '%s' "$output" | jq -r '.rows[] | select(.auth_actionable == true)
        | (if (.k | type) == "number" then .k else "unmeasured" end)')"
  [ "$k" = unmeasured ] || { echo "inherited row presented k=$k to the relogin gate"; false; }
  # And the producer never learned to look at the inherited field. EXECUTABLE lines only — the
  # file carries a comment at that jq site saying why `.k_stale` must never be added there, and
  # a test that forbade the word outright would forbid its own explanation. grep -c, never
  # grep -q: an early-exiting -q SIGPIPEs its own producer under pipefail and can invert the
  # verdict (MEMORY.md grep-q-under-pipefail-inverts-the-verdict).
  run bash -c "grep -v '^[[:space:]]*#' \"\$HF\" | grep -c 'k_stale' || true"
  [ "$output" = 0 ] || { echo "handoff-fire.sh now reads k_stale — see this suite's header"; false; }
}

# ---- 3. mutants: each control aimed at the one line that carries the property -----------------

@test "MUTANT: an inherit_k that stamps row[k] must fail the rotation-gate test" {
  mutant="$BATS_TEST_TMPDIR/mutant-stamp"
  sed 's/^    row\["k_stale"\] = val$/    row["k"] = val/' "$CA_BIN" > "$mutant"
  run bash -c "grep -c '^    row\\[\"k\"\\] = val\$' \"\$1\"" _ "$mutant"
  [ "$output" = 1 ] || { echo "mutant did not apply"; false; }
  # it still routes (the property the fix adds survives) ...
  run python3 -c "$LOADCA"'
r = row()
ca.inherit_k(r, prev(30, k=3), 600, ts=NOW - 30)
assert ca._excluded(r, R, cliff=False) is None
print("ROUTES")' "$mutant"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *ROUTES* ]] || false
  # ... and the rotation gate is now OPEN on a remembered zero, which is the regression.
  run python3 -c "$LOADCA"'
r = row()
ca.inherit_k(r, prev(30, k=0), 600, ts=NOW - 30)
print("K=" + repr(r["k"]))' "$mutant"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"K=0"* ]] || { echo "$output"; false; }
}

@test "MUTANT: an unbounded grace must fail the staleness test" {
  mutant="$BATS_TEST_TMPDIR/mutant-grace"
  sed 's/^    if age is None or age < 0 or age > grace_s:$/    if False:/' "$CA_BIN" > "$mutant"
  run bash -c "grep -c '^    if False:\$' \"\$1\"" _ "$mutant"
  [ "$output" = 1 ] || { echo "mutant did not apply"; false; }
  run python3 -c "$LOADCA"'
r = row()
ca.inherit_k(r, prev(5, k=None, k_stale=3, k_as_of=iso(86400)), 600, ts=NOW - 5)
print("SRC=" + ca.k_src(r))' "$mutant"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"SRC=panes-stale"* ]] || { echo "$output"; false; }   # a DAY-old census routed
}

@test "MUTANT: a _prev_snapshot that drops k_as_of must fail the re-inheritance test" {
  # The projection is the whole memory. Dropping the provenance keys re-creates the one-sweep
  # horizon: sweep 2 reads back a row whose k is null and whose k_stale it never carried.
  mutant="$BATS_TEST_TMPDIR/mutant-proj"
  sed 's/^\( *\)"k", "k_stale", "k_as_of")}$/\1"k")}/' "$CA_BIN" > "$mutant"
  run bash -c "grep -c '\"k_stale\", \"k_as_of\")}' \"\$1\" || true" _ "$mutant"
  [ "$output" = 0 ] || { echo "mutant did not apply"; false; }
  run python3 -c "$LOADCA"'
import json, os, time
cache = os.path.join(os.environ["BATS_TEST_TMPDIR"], "cache.json")
cfg = {"cache_file": cache, "accounts": [{"name": "next3"}]}
key = ca._cfg_key(cfg)
# an already-inherited row, exactly as get_data writes one back
json.dump({"ts": time.time() - 5, "cfg_key": key,
           "rows": [{"acct": "next3", "k": None, "k_stale": 3,
                     "k_as_of": ca.datetime.now(ca.timezone.utc).isoformat()}]},
          open(cache, "w"))
p = ca._prev_snapshot(cfg)
r = row()
print("INHERITED=" + str(ca.inherit_k(r, p, 600, ts=p["ts"])))' "$mutant"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"INHERITED=False"* ]] || { echo "$output"; false; }
}

# ---- 4. the recorder and the board still describe what the router did -------------------------

@test "k-inherit: the utilization row and route-meta can tell a memory from a measurement" {
  # A replay reading only k/k_work on a panes-stale row computes k_eff = 0 for a row the router
  # charged a real census — the one arithmetic error that makes an admitted row unexplainable.
  run python3 -c "$LOADCA"'
import json, os, time
r = row(session_pct=10.0, weekly_pct=20.0, acct="next3")
ca.inherit_k(r, prev(30, k=3), 600, ts=NOW - 30)
path = os.path.join(os.environ["BATS_TEST_TMPDIR"], "util.jsonl")
assert ca.record_utilization([r], path=path, min_interval_s=0) == 1
d = json.loads(open(path).read().splitlines()[-1])
assert d["k"] is None and d["k_stale"] == 3 and d["k_src"] == "panes-stale", d
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "k-inherit: desk-strand-replay reconstructs a panes-stale sweep as ROUTED, not abstained" {
  # The recorder and the replay are the two halves of one claim about a past decision, and the
  # inheritance is exactly where they can disagree: the recorded `k` is null on an inherited row
  # by contract, so a replay reading only k/k_work re-derives 'unmeasured' and re-EXCLUDES a row
  # the router admitted and charged 3 against. That turns a routed decision into a phantom
  # abstention in every strand analysis drawn from the series.
  # desk-strand-replay resolves the SSOT at import (ca.load_cfg) — point it at the CHECKED-IN
  # accounts.json, never the operator's. Reading the repo's own SSOT is the claim, not a leak.
  export CLAUDE_ACCOUNTS_JSON="$REPO/accounts.json"
  run python3 -c "$LOADCA"'
import importlib.machinery, importlib.util, json, os
from datetime import datetime, timezone
r = row(acct="next3", session_pct=10.0, weekly_pct=20.0)
ca.inherit_k(r, prev(30, k=3), 600, ts=NOW - 30)
path = os.path.join(os.environ["BATS_TEST_TMPDIR"], "util.jsonl")
assert ca.record_utilization([r], path=path, min_interval_s=0) == 1
d = json.loads(open(path).read().splitlines()[-1])
rp = os.path.join(os.environ["REPO"], "scripts", "desk-strand-replay.py")
spec = importlib.util.spec_from_file_location("dsr", rp)
dsr = importlib.util.module_from_spec(spec); spec.loader.exec_module(dsr)
back = dsr.to_row(d, datetime.now(timezone.utc))
assert ca.k_src(back) == "panes-stale", ca.k_src(back)
assert ca.k_eff(back) == 3, ca.k_eff(back)
assert ca.k_cap(back, R) == 40, ca.k_cap(back, R)
assert ca._excluded(back, R, cliff=False) is None, ca._excluded(back, R, cliff=False)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "k-inherit: the board renders an inherited count as STALE, never as a measurement" {
  run python3 -c "$LOADCA"'
assert ca._fmt_k({"k": 3}) == "3"
assert ca._fmt_k({"k": 0}) == "0"
assert ca._fmt_k({"k": None}) == "?", "an unmeasured cell must stay ?, never a fabricated 0"
assert ca._fmt_k({"k": None, "k_stale": 3}) == "3*"
assert ca._fmt_k({"k": None, "k_stale": 0}) == "0*", "a REMEMBERED idle is not a proven one"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}
