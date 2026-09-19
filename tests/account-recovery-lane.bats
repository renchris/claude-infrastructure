#!/usr/bin/env bats
# account-recovery-lane — the ranker's RECOVERY modifier (LIMIT_RECOVER_100P W6a, research U13).
#
# WHAT THIS EXISTS TO PIN. `--rank` answers "which account should take a NEW unit of work". A
# limit recovery asks a different question — "which account will still be ALIVE in an hour" —
# and nothing in the eligibility gate asked it. Measured 2026-09-19 (U13 §0-§1): `next` at
# weekly 98 % scored 0.000068 against `next3` at weekly 11 % scoring 0.000071, because the
# urgency denominator T**2 paid a 40x bonus for `next`'s bucket resetting in 11 h and that almost
# exactly cancelled next3's 24x headroom lead. `next` was rank[0] of the fable lane at 17:04 Z
# and hit weekly 100 % at 18:58 Z — 1 h 54 m later. Two Fable sessions transplanted onto it would
# both have re-limited inside two hours.
#
# It survived the one weekly guard that exists in that lane by a FLOATING-POINT ULP:
# `FABLE_FLOOR = 0.02` is tested as `f_eff <= 0.02`, and `1.0 - 98/100` is 0.020000000000000018.
#
# So: `--recovery` is a MODIFIER on the existing lanes (never a fourth lane — a `recovery` kind
# would need a recovery-general and a recovery-fable twin, and the doubling is the tell). It adds
# three SURVIVAL floors to eligibility and leaves the objective alone: the strand-avoidance score
# is correct AMONG accounts that can host the session; only the eligible SET was wrong.
#
# The properties here that are not "does the feature work" — they are the reasons it is safe:
#   · DERIVED, never retyped: every floor is read from the repo accounts.json in the test, so a
#     constant that moves in the SSOT cannot leave a suite certifying math production never runs.
#   · KILL SWITCH: CC_ROUTE_RECOVERY=off must be BYTE-IDENTICAL to pre-U13 routing, asserted at
#     the module AND through the CLI's stdout.
#   · NON-REGRESSION: `--rank <lane>` WITHOUT `--recovery` is untouched. The incident account is
#     still rank[0] for dispatch; that is the correct dispatch answer and this wave does not
#     relitigate it.
#   · POLICY, not data: the recovery reasons must NOT join DATA_UNAVAILABLE, so an all-thin fleet
#     exits 2 (callers must not fire blind) rather than 3 (degrade to a proxy) — and never a
#     silent empty rank.
#
# Hermetic, in the companion suites' style (tests/account-cliff-routing.bats:25-72): fixture
# $HOME, scratch SSOT + cache in BATS_TEST_TMPDIR, unreachable endpoints, a config_dir that
# hashes to a nonexistent keychain service, and the burn/assignment/route stores pinned into the
# sandbox — every CLI invocation READS those (apply_burn / apply_assignments), so an unpinned run
# inherits the real fleet's burn rates and the projected-5h assertions below become ambient.

setup() {
  # A suite that tests a wrapper must not inherit that wrapper's env (bin/cc-bats exports this).
  unset CC_BATS_ACTIVE
  # The recovery lane's own knobs must never leak in from the invoking shell: a session that
  # exported CC_ROUTE_RECOVERY=off would turn every assertion below vacuous.
  unset CC_ROUTE_RECOVERY CC_ROUTE_RECOVERY_W_FLOOR CC_ROUTE_RECOVERY_S_CEIL \
        CC_ROUTE_RECOVERY_F_FLOOR CC_ROUTE_PROJ CC_ROUTE_PROJ_LOOKAHEAD_H \
        CC_ROUTE_CLIFF_TERM CC_ROUTE_KWORK

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_SSOT="$REPO/accounts.json"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CA_LEDGER="$BATS_TEST_TMPDIR/lastgood.json"
  export CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$CA_LEDGER"
  export CLAUDE_ACCOUNTS_LOG="$BATS_TEST_TMPDIR/claude-accounts.log"
  export YAML="$BATS_TEST_TMPDIR/model-config.yaml"
  # apply_burn / apply_assignments run on EVERY CLI invocation. Unpinned, the projected-5h
  # ceiling below would be computed from the operator's live burn series.
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
  # DERIVED from the real SSOT — never hand-copied.
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [{"name": "next3", "config_dir": "/tmp/ca-recovery-test-nonexistent-xyz",
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
# HERMETICITY: LOG_PATH resolves at import from $HOME; redirect once, for every case.
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
R = cfg["router"]
CFG2 = {"router": R, "frontier": cfg["frontier"]}
WIN_OPEN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
def row(**kw):
    base = dict(acct="a", session_pct=10, session_reset_h=3.0, weekly_pct=40,
                weekly_reset_h=24.0, fable_pct=20, fable_reset_h=24.0, k=2, credits_on=False)
    base.update(kw); return base
'

# Seed the shared cache from `acct:weekly:session` triples so the CLI runs with no network and
# no keychain. fable_pct is held low so the FABLE lane is decided by the weekly coupling — which
# is the incident's own shape.
seed() { python3 - "$@" <<'PY'
import json, os, sys, time, importlib.machinery, importlib.util
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
rows = []
for spec in sys.argv[1:]:
    acct, wk, sp = spec.split(":")
    rows.append({"acct": acct, "auth": "ok", "k": 0, "session_pct": float(sp),
                 "session_reset_h": 3.0, "weekly_pct": float(wk), "weekly_reset_h": 20.0,
                 "fable_pct": 7, "fable_reset_h": 20.0, "credits_on": False})
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None, "rows": rows}, open(os.environ["CACHE"], "w"))
PY
}

# ── the constants, DERIVED ──────────────────────────────────────────────────────────────────────

@test "floors are DERIVED from the repo SSOT, never hand-copied, and range-validated there" {
  run python3 -c "$LOAD"'
# The SSOT carries all three, each a fraction (the plausible typo is 60 for 0.60 — a floor
# written as a percentage would silently delete the guard while reading as a configured one).
for k in ("RECOVERY_W_FLOOR", "RECOVERY_S_CEIL", "RECOVERY_F_FLOOR"):
    assert k in R, k
    assert isinstance(R[k], (int, float)) and not isinstance(R[k], bool), (k, R[k])
    assert 0.0 < R[k] < 1.0, (k, R[k])
    assert k in ca.ROUTER_OPTIONAL_RANGES, k        # range-checked when present
# and recovery_floors READS them — it does not carry a second copy of the numbers.
assert ca.recovery_floors(R) == (R["RECOVERY_W_FLOOR"], R["RECOVERY_S_CEIL"],
                                 R["RECOVERY_F_FLOOR"]), ca.recovery_floors(R)
# the SSOT block states WHY, in the file the operator tunes
assert "_recovery" in R and "RECOVERY_W_FLOOR" in R["_recovery"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ── THE INCIDENT ────────────────────────────────────────────────────────────────────────────────

@test "THE INCIDENT: weekly 98 / fable 7 / reset 11h is rank[0] for DISPATCH and recovery-weekly-thin for RECOVERY" {
  run python3 -c "$LOAD"'
# U13 §0 — the 17:00Z snapshot, reproduced against the real scorer.
nxt  = row(acct="next",  weekly_pct=98, weekly_reset_h=11.0, fable_pct=7, fable_reset_h=11.0,
           session_pct=3, k_work=4, k=4)
nxt3 = row(acct="next3", weekly_pct=11, weekly_reset_h=67.0, fable_pct=0, fable_reset_h=67.0,
           session_pct=2, k_work=2, k=2)
# The DISPATCH lane is unchanged, and it is asserted FIRST so this case can only go green by the
# fix and not by a fixture that stopped reproducing the incident.
s_n, _ = ca.score_fable(nxt,  CFG2, WIN_OPEN)
s_3, _ = ca.score_fable(nxt3, CFG2, WIN_OPEN)
assert s_n is not None and s_3 is not None, (s_n, s_3)
assert s_n > s_3, ("the incident no longer reproduces", s_n, s_3)
# The RECOVERY lane refuses it by the WEEKLY floor — the survival fact, checked in eligibility.
assert ca.score_fable(nxt, CFG2, WIN_OPEN, recovery=True) == (None, "recovery-weekly-thin"), \
    ca.score_fable(nxt, CFG2, WIN_OPEN, recovery=True)
# ...and the survivor still scores, so no recovery is parked for want of a target.
assert ca.score_fable(nxt3, CFG2, WIN_OPEN, recovery=True)[0] is not None
# the general lane answers the same way about the same account
assert ca.score_general(nxt, CFG2, recovery=True) == (None, "recovery-weekly-thin")
assert ca.score_general(nxt3, CFG2, recovery=True)[0] is not None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "the float ULP at weekly 98 cannot admit a thin account any more" {
  run python3 -c "$LOAD"'
# The ULP is REAL — pin it, so the case is honest about what it is guarding.
assert (1.0 - 98/100.0) > R["FABLE_FLOOR"], (1.0 - 98/100.0, R["FABLE_FLOOR"])
r = row(weekly_pct=98, fable_pct=7)
assert ca._excluded(r, R) is None                       # dispatch: routable, by a rounding error
assert ca._excluded(r, R, recovery=True) == "recovery-weekly-thin"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ── the 5h ceiling ──────────────────────────────────────────────────────────────────────────────

@test "the 5h ceiling is TIGHTER than S_CUT, in the direction the guard needs" {
  run python3 -c "$LOAD"'
# ⚠️ A recovery 5h floor at or above S_CUT would be a LOOSENING, not a guard: _excluded already
# cuts at S_CUT. Asserted against the SSOT, so a hand-tune cannot invert the guard silently.
assert R["RECOVERY_S_CEIL"] < R["S_CUT"], (R["RECOVERY_S_CEIL"], R["S_CUT"])
r = row(session_pct=70, session_reset_h=4.0)            # routable for dispatch, thin for recovery
assert ca._excluded(r, R) is None
assert ca._excluded(r, R, recovery=True) == "recovery-5h-thin"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "the 5h ceiling boundary is INCLUSIVE, at exactly the SSOT value" {
  run python3 -c "$LOAD"'
# DERIVED from the constant, never retyped: the case pins the COMPARISON, so it stays a
# red-proof for >= vs > whatever the operator tunes the ceiling to.
sp = round(R["RECOVERY_S_CEIL"] * 100)
assert sp / 100.0 == R["RECOVERY_S_CEIL"], (sp, R["RECOVERY_S_CEIL"])   # exactness, stated
r = row(session_pct=sp, session_reset_h=4.0)
assert ca._su_projected(r, R) == R["RECOVERY_S_CEIL"], ca._su_projected(r, R)
assert ca._excluded(r, R, recovery=True) == "recovery-5h-thin"
# one step under the ceiling is admitted — the floor is a boundary, not a blanket
assert ca._excluded(row(session_pct=sp - 1, session_reset_h=4.0), R, recovery=True) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "the ceiling reads the PROJECTED 5h, not the measured one: a burning account is refused early" {
  run python3 -c "$LOAD"'
# A recovered session resumes burning AT ONCE, so what matters is where the window is HEADING.
# Same input the desk lane and _soft already use.
sp = round(R["RECOVERY_S_CEIL"] * 100)
r = row(session_pct=sp - 20, session_reset_h=4.0, burn_5h_ewma_ph=25.0)
assert ca._excluded(r, R) is None
assert ca._su_projected(r, R) > R["RECOVERY_S_CEIL"]
assert ca._excluded(r, R, recovery=True) == "recovery-5h-thin"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ── the fable floor ─────────────────────────────────────────────────────────────────────────────

@test "fable-lane floor bites at fable 91 while weekly is fat" {
  run python3 -c "$LOAD"'
r = row(weekly_pct=5, fable_pct=91, fable_reset_h=40.0, weekly_reset_h=40.0)
assert ca.score_fable(r, CFG2, WIN_OPEN)[0] is not None            # dispatch: fine
assert ca.score_fable(r, CFG2, WIN_OPEN, recovery=True) == (None, "recovery-fable-thin"), \
    ca.score_fable(r, CFG2, WIN_OPEN, recovery=True)
# and a genuinely exhausted bucket keeps its OWN reason — the recovery floor does not rename it
assert ca.score_fable(row(weekly_pct=5, fable_pct=99), CFG2, WIN_OPEN,
                      recovery=True) == (None, "fable-exhausted")
# the floor is max(FABLE_FLOOR, RECOVERY_F_FLOOR), so it can only ever be STRICTER
assert R["RECOVERY_F_FLOOR"] > R["FABLE_FLOOR"], (R["RECOVERY_F_FLOOR"], R["FABLE_FLOOR"])
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ── absence is not headroom ─────────────────────────────────────────────────────────────────────

@test "an account with NO weekly data is EXCLUDED as no-weekly-data — never admitted on absence" {
  run python3 -c "$LOAD"'
r = row(weekly_pct=None)
assert ca._excluded(r, R, recovery=True) == "no-weekly-data"
# DATA, not policy: we could not SEE the headroom. That drives exit 3 (callers may degrade to a
# proxy) rather than exit 2 (policy refused).
assert ca.reason_class(r, "no-weekly-data") == "data"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "the three recovery reasons are POLICY, so an all-thin fleet refuses instead of degrading" {
  run python3 -c "$LOAD"'
for why in ("recovery-weekly-thin", "recovery-5h-thin", "recovery-fable-thin"):
    assert why not in ca.DATA_UNAVAILABLE, why
    assert ca.reason_class(row(), why) == "policy", why
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ── the kill switch ─────────────────────────────────────────────────────────────────────────────

@test "KILL SWITCH: CC_ROUTE_RECOVERY=off makes --recovery identical to pre-U13, at the module" {
  run env CC_ROUTE_RECOVERY=off python3 -c "$LOAD"'
assert ca.recovery_floors(R)[0] == 0.0                  # neutral: no weekly floor
assert ca.recovery_floors(R)[2] == 0.0                  # neutral: no extra fable floor
for wp in (0, 50, 98, 99):
    for sp in (10, 70, 100):
        r = row(weekly_pct=wp, fable_pct=7, session_pct=sp)
        assert ca._excluded(r, R, recovery=True) == ca._excluded(r, R), (wp, sp)
        assert ca.score_fable(r, CFG2, WIN_OPEN, recovery=True) \
            == ca.score_fable(r, CFG2, WIN_OPEN), (wp, sp)
        assert ca.score_general(r, CFG2, recovery=True) == ca.score_general(r, CFG2), (wp, sp)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "KILL SWITCH: CC_ROUTE_RECOVERY=off is BYTE-IDENTICAL through the CLI on weekly 0/50/98/99" {
  seed "a0:0:10" "a50:50:10" "a98:98:10" "a99:99:10"
  for lane in general fable; do
    run bash -c "python3 '$CA_BIN' --rank $lane 2>/dev/null"
    [ "$status" -eq 0 ] || { echo "base $lane: $output"; false; }
    local base="$output"
    run bash -c "CC_ROUTE_RECOVERY=off python3 '$CA_BIN' --rank $lane --recovery 2>/dev/null"
    [ "$status" -eq 0 ] || { echo "off $lane: $output"; false; }
    [ "$output" = "$base" ] || { echo "lane=$lane base=[$base] off=[$output]"; false; }
  done
}

# ── the refusal is loud ─────────────────────────────────────────────────────────────────────────

@test "an ALL-THIN fleet exits 2 with the reasons on stderr and 'none' on stdout — never a silent empty rank" {
  seed "a98:98:10" "a99:99:10"
  run bash -c "python3 '$CA_BIN' --rank general --recovery 2>/dev/null"
  [ "$status" -eq 2 ] || { echo "status=$status out=$output"; false; }   # POLICY, not data (3)
  [ "${lines[0]}" = "none" ]
  run bash -c "python3 '$CA_BIN' --rank general --recovery 2>&1 >/dev/null"
  [[ "$output" == *"recovery-weekly-thin"* ]] || { echo "$output"; false; }
  [[ "$output" == *"no routable account for general"* ]] || { echo "$output"; false; }
}

@test "route-meta carries recovery=1 under the modifier and recovery=0 without it" {
  seed "fat:5:10"
  run bash -c "python3 '$CA_BIN' --rank general --recovery 2>&1 >/dev/null"
  [[ "$output" == *"route-meta:"* ]] || { echo "$output"; false; }
  [[ "$output" == *"recovery=1"* ]] || { echo "$output"; false; }
  run bash -c "python3 '$CA_BIN' --rank general 2>&1 >/dev/null"
  [[ "$output" == *"recovery=0"* ]] || { echo "$output"; false; }
}

# ── non-regression ──────────────────────────────────────────────────────────────────────────────

@test "NON-REGRESSION: --rank fable WITHOUT --recovery still ranks the thin account" {
  # EQUIVALENCE GUARD, stated as one: this case is green in both arms by construction. Its job is
  # to fail if the recovery floors ever leak into the default path — the mutant it guards against
  # is `recovery=True` as the default kwarg, which no pre/post arm can exercise.
  seed "a98:98:10" "a11:11:10"
  run bash -c "python3 '$CA_BIN' --rank fable 2>/dev/null"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${#lines[@]}" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *a98* ]] || { echo "$output"; false; }
  run bash -c "python3 '$CA_BIN' --rank general 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *a98* ]] || { echo "$output"; false; }
}

@test "NON-REGRESSION: every existing caller's signature is unchanged — recovery defaults to False" {
  run python3 -c "$LOAD"'
import inspect
for fn in (ca._excluded, ca.score_general, ca.score_fable, ca._rank_pass, ca.ranked):
    p = inspect.signature(fn).parameters
    assert "recovery" in p, fn.__name__
    assert p["recovery"].default is False, (fn.__name__, p["recovery"].default)
# the desk lane is NOT a recovery lane and does not pretend to be one
assert "recovery" not in inspect.signature(ca.score_interactive).parameters
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}
