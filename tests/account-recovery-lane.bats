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
        CC_ROUTE_CLIFF_TERM CC_ROUTE_KWORK CC_ROUTE_DISPATCH_W_FLOOR \
        CC_ROUTE_DISPATCH_STRAND CC_ROUTE_DISPATCH_STRAND_FIRST CC_ROUTE_DISPATCH_STRAND_PP \
        CC_ROUTE_DISPATCH_FIRE_BURN_PPH CC_ROUTE_DISPATCH_CLAIM_TTL_MIN CC_ROUTE_ASSIGN \
        CC_ROUTE_ASSIGN_TTL_MIN

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

# ── the DISPATCH floor: a thin account is DEMOTED, never excluded (2026-09-27) ──────────────────
# `handoff-fire.sh --account auto` takes `--rank general | head -1`. On 2026-09-26 it put a
# code-writing fire on next4 at weekly 96-99 %, which hit its weekly limit before closing. The
# only general-lane weekly bar is WEEKLY_FLOOR (0.5pp), and the T**2 urgency term paid next4's
# ~12 h reset a ~180x bonus over next2's ~158 h one, so next4 outscored an almost-empty next2 4-6x.
# The rule: an account under DISPATCH_W_FLOOR of weekly headroom ranks BELOW every account above
# it, but stays in the list, so it is still picked when it is the only routable one. Scores are
# untouched (the strand objective still orders each group), so THE INCIDENT case above holds.
# Since 2026-10-09 "ranks below" is conditional: see the STRAND RESCUE block after these four.
# Their rows carry no pace stamps, which the rescue reads as unknown, so they hold unchanged.

@test "[RED] DISPATCH FLOOR: the 2026-09-26 21:19Z snapshot ranks next2 above a next4 at weekly 99" {
  run python3 -c "$LOAD"'
n4 = row(acct="next4", weekly_pct=99, weekly_reset_h=11.7, fable_pct=40, fable_reset_h=11.7, session_pct=5, k=1, k_work=1)
n2 = row(acct="next2", weekly_pct=3, weekly_reset_h=157.7, fable_pct=2, fable_reset_h=157.7, session_pct=2, k=0, k_work=0)
# the incident still reproduces at the SCORE level, so this can only go green through the order
assert ca.score_general(n4, CFG2)[0] > ca.score_general(n2, CFG2)[0]
out, _ = ca.ranked([n4, n2], CFG2, WIN_OPEN, "general")
order = [r["acct"] for _s, r in out]
assert order == ["next2", "next4"], order
assert out[1][1].get("thin_demoted") is True, out[1][1]
# The fable lane at the 19:23Z snapshot (weekly 96, reset 13.6 h), where its own floor still admits.
n4f = row(acct="next4", weekly_pct=96, weekly_reset_h=13.6, fable_pct=30, fable_reset_h=13.6, session_pct=5, k=1, k_work=1)
n2f = row(acct="next2", weekly_pct=0, weekly_reset_h=159.6, fable_pct=0, fable_reset_h=159.6, session_pct=2, k=0, k_work=0)
assert ca.score_fable(n4f, CFG2, WIN_OPEN)[0] > ca.score_fable(n2f, CFG2, WIN_OPEN)[0]
out, _ = ca.ranked([n4f, n2f], CFG2, WIN_OPEN, "fable")
assert [r["acct"] for _s, r in out] == ["next2", "next4"], out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "DISPATCH FLOOR: a thin account that is the ONLY routable one is still rank[0]" {
  run python3 -c "$LOAD"'
n4 = row(acct="next4", weekly_pct=99, weekly_reset_h=11.7, fable_pct=40, fable_reset_h=11.7, session_pct=5, k=1, k_work=1)
cap = row(acct="next", weekly_pct=100, weekly_reset_h=5.0)
out, reasons = ca.ranked([n4, cap], CFG2, WIN_OPEN, "general")
assert [r["acct"] for _s, r in out] == ["next4"], out
assert "next" in reasons
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "DISPATCH FLOOR: the floor is DERIVED from the SSOT, range-validated, and the kill switch restores the score order" {
  run python3 -c "$LOAD"'
import os
assert "DISPATCH_W_FLOOR" in R and 0.0 < R["DISPATCH_W_FLOOR"] < 1.0, R.get("DISPATCH_W_FLOOR")
assert "DISPATCH_W_FLOOR" in ca.ROUTER_OPTIONAL_RANGES
assert ca.dispatch_w_floor(R) == R["DISPATCH_W_FLOOR"]
assert "_dispatch" in R and "DISPATCH_W_FLOOR" in R["_dispatch"]
n4 = row(acct="next4", weekly_pct=99, weekly_reset_h=11.7, session_pct=5, k=1, k_work=1)
n2 = row(acct="next2", weekly_pct=3, weekly_reset_h=157.7, session_pct=2, k=0, k_work=0)
os.environ["CC_ROUTE_DISPATCH_W_FLOOR"] = "off"
out, _ = ca.ranked([n4, n2], CFG2, WIN_OPEN, "general")
assert [r["acct"] for _s, r in out] == ["next4", "next2"], out
assert not any(r.get("thin_demoted") for _s, r in out)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "DISPATCH FLOOR: accounts above the floor keep their score order; the interactive lane is untouched" {
  run python3 -c "$LOAD"'
a = row(acct="a", weekly_pct=60, weekly_reset_h=10.0, session_pct=5, k=0, k_work=0)
b = row(acct="b", weekly_pct=10, weekly_reset_h=150.0, session_pct=5, k=0, k_work=0)
out, _ = ca.ranked([b, a], CFG2, WIN_OPEN, "general")
assert [r["acct"] for _s, r in out] == ["a", "b"], out     # urgency still wins above the floor
assert not any(r.get("thin_demoted") for _s, r in out)
t = row(acct="t", weekly_pct=99, weekly_reset_h=11.7, session_pct=5, k=0, k_work=0)
out_i, _ = ca.ranked([t, b], CFG2, WIN_OPEN, "interactive")
assert not any(r.get("thin_demoted") for _s, r in out_i)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# ── the STRAND RESCUE: a thin account that will strand is LIFTED, and in the general lane goes
#    FIRST (2026-10-09) ─────────────────────────────────────────────────────────────────────────
# The flat floor above could not tell an account about to wall from one about to waste its week.
# On 2026-10-09 next2 sat at weekly 94 % with 13 h to its reset, burning 0.05 pp/h, and ranked
# LAST for every new fire. The rule (bin/claude-accounts, dispatch_floor_row): a thin row is HELD
# unless its forecast-dead quota covers a whole new fire, and every missing, stale or malformed
# input holds it. SNAP is that fleet, rebuilt from the utilization ledger at 21:46Z; the thin row
# is OUT-scored in it, so nothing below can go green by un-parking alone. (fable_pct is not from
# the ledger: it is set so the thin row is out-scored in the fable lane as well.)
SNAP='
import copy, os
DROP = object()
def snap(**n2):
    thin = dict(acct="next2", weekly_pct=94, weekly_reset_h=13.2, fable_pct=90, fable_reset_h=13.2,
                session_pct=0, k=7, wk_strand_pp=5.38, burn_wk_ewma_ph=0.047, burn_wk_flat_ph=0.0,
                k_phantom=0, k_placed=0)
    thin.update(n2)
    thin = {k: v for k, v in thin.items() if v is not DROP}
    return [row(**thin),
            row(acct="next", weekly_pct=55, weekly_reset_h=30.2, fable_pct=30, fable_reset_h=30.2,
                session_pct=1, k=10, k_phantom=0, k_placed=5),
            row(acct="next4", weekly_pct=38, weekly_reset_h=35.2, fable_pct=20, fable_reset_h=35.2,
                session_pct=9, k=4, k_phantom=0, k_placed=1),
            row(acct="next3", weekly_pct=1, weekly_reset_h=86.2, fable_pct=1, fable_reset_h=86.2,
                session_pct=0, k=0, k_phantom=0, k_placed=1)]
def order(out):
    return [r["acct"] for _s, r in out]
def tok(out, acct="next2"):
    return [r.get("dispatch_floor") for _s, r in out if r["acct"] == acct][0]
def view(out):
    return [(r["acct"], s, bool(r.get("thin_demoted"))) for s, r in out]
def flat_floor(rows, lane):
    """The 2026-09-27 rule restated from its definition, as view(): roomy rows, then thin ones."""
    raw, _ = ca._ranked(rows, CFG2, WIN_OPEN, lane)
    f = ca.dispatch_w_floor(R)
    thin = lambda r: ca.weekly_headroom(r) is not None and ca.weekly_headroom(r) < f
    return [(r["acct"], s, False) for s, r in raw if not thin(r)] \
        + [(r["acct"], s, True) for s, r in raw if thin(r)]
'

@test "[RED] STRAND RESCUE: the 2026-10-09 21:46Z snapshot puts an out-scored next2 on line 1" {
  run python3 -c "$LOAD$SNAP"'
rows = snap()
sc = {r["acct"]: ca.score_general(r, CFG2)[0] for r in rows}
# the defect at the SCORE level: two roomy accounts outscore the one about to strand, so score
# order alone can never pick it and this goes green only through the promotion
assert sc["next4"] > sc["next"] > sc["next2"] > sc["next3"], sc
out, reasons = ca.ranked(rows, CFG2, WIN_OPEN, "general")
assert order(out)[0] == "next2", order(out)
assert order(out) == ["next2", "next4", "next", "next3"], order(out)   # the rest keep score order
assert tok(out) == "lifted-first", tok(out)
assert not any(r.get("thin_demoted") for _s, r in out), out
assert not reasons and {r["acct"]: s for s, r in out} == sc            # no row dropped, no score moved
tk, spare, need = ca.dispatch_floor_row(rows[0], R)
assert (tk, round(spare, 2), round(need, 2)) == ("lifted", 5.38, 5.33), (tk, spare, need)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "STRAND RESCUE kill switches: STRAND=off is the 2026-09-27 floor exactly, STRAND_FIRST=off is pure score order" {
  run python3 -c "$LOAD$SNAP"'
# five fleets: the snapshot, the snapshot claimed, the pinned incident, a liftable 96 %, all-thin
fleets = [snap(), snap(k_placed=1),
          [row(acct="next4", weekly_pct=99, weekly_reset_h=11.7, session_pct=5, k=1, k_work=1),
           row(acct="next2", weekly_pct=3, weekly_reset_h=157.7, session_pct=2, k=0, k_work=0)],
          [row(acct="next4", weekly_pct=96, weekly_reset_h=9.0, session_pct=5, k=1, wk_strand_pp=4.0,
               burn_wk_ewma_ph=0.0, burn_wk_flat_ph=0.0, k_placed=0),
           row(acct="next2", weekly_pct=0, weekly_reset_h=159.6, session_pct=2, k=0)],
          [row(acct="a", weekly_pct=93, weekly_reset_h=8.0, wk_strand_pp=7.0, burn_wk_ewma_ph=0.0,
               burn_wk_flat_ph=0.0, k_placed=0, k=0),
           row(acct="b", weekly_pct=95, weekly_reset_h=30.0, k=0)]]
moved = 0
for lane in ("general", "fable"):
    for i, fleet in enumerate(fleets):
        want = flat_floor(copy.deepcopy(fleet), lane)
        assert want, (lane, i)
        os.environ.pop("CC_ROUTE_DISPATCH_STRAND", None)
        moved += view(ca.ranked(copy.deepcopy(fleet), CFG2, WIN_OPEN, lane)[0]) != want
        for off in ("off", "0", "false", "OFF"):
            os.environ["CC_ROUTE_DISPATCH_STRAND"] = off
            got = ca.ranked(copy.deepcopy(fleet), CFG2, WIN_OPEN, lane)[0]
            assert view(got) == want, (lane, i, off, view(got), want)       # order, scores, flags
            assert all(r["dispatch_floor"] in ("roomy", "flat") for _s, r in got), got
assert moved >= 6, moved        # ...and the switch is not vacuous: the rule moves these fleets
os.environ.pop("CC_ROUTE_DISPATCH_STRAND")
assert [a for a, _s, _d in flat_floor(snap(), "general")] == ["next4", "next", "next3", "next2"]
# promotion alone off: the lifted row rejoins the score order, unflagged
os.environ["CC_ROUTE_DISPATCH_STRAND_FIRST"] = "off"
out, _ = ca.ranked(snap(), CFG2, WIN_OPEN, "general")
assert order(out) == order(ca._ranked(snap(), CFG2, WIN_OPEN, "general")[0]) \
    == ["next4", "next", "next2", "next3"], order(out)
assert tok(out) == "lifted" and not any(r.get("thin_demoted") for _s, r in out), out
os.environ.pop("CC_ROUTE_DISPATCH_STRAND_FIRST")
# the older switch still outranks both: no floor, no verdict, no flag
os.environ["CC_ROUTE_DISPATCH_W_FLOOR"] = "off"
out, _ = ca.ranked(snap(), CFG2, WIN_OPEN, "general")
assert order(out) == ["next4", "next", "next2", "next3"], order(out)
assert not any("dispatch_floor" in r or r.get("thin_demoted") for _s, r in out), out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "STRAND RESCUE: the 2026-09-26 next4 incident stays HELD, and so does weekly 96 at zero pace" {
  run python3 -c "$LOAD$SNAP"'
n2 = lambda: row(acct="next2", weekly_pct=3, weekly_reset_h=157.7, fable_pct=2, fable_reset_h=157.7,
                 session_pct=2, k=0, k_work=0, k_placed=0)
def judge(**kw):
    base = dict(acct="next4", fable_pct=40, session_pct=5, k=1, k_work=1, k_phantom=0, k_placed=0)
    base.update(kw)
    n4 = row(**base); n4["fable_reset_h"] = n4["weekly_reset_h"]
    out, _ = ca.ranked([n4, n2()], CFG2, WIN_OPEN, "general")
    return order(out)[0], ca.dispatch_floor_row(n4, R), ca.score_general(n4, CFG2)[0]
s2 = ca.score_general(n2(), CFG2)[0]
# the incident with its stamps present: 96 % / 13.6 h burning 0.68 pp/h, then 99 % / 11.7 h
for wp, wrh in ((96, 13.6), (99, 11.7)):
    first, (tk, spare, _n), s4 = judge(weekly_pct=wp, weekly_reset_h=wrh, burn_wk_ewma_ph=0.68,
                                       burn_wk_flat_ph=0.6, wk_strand_pp=max(0.0, 100 - wp - 0.68 * wrh))
    assert s4 > s2                                              # it still OUTSCORES, as it did then
    assert (first, tk, spare) == ("next2", "on-pace", 0.0), (wp, first, tk, spare)
# weekly 96 / 13.6 h and perfectly QUIET: 4pp spare against the 4pp base, and 1.00 - 0.96 is
# 0.040000000000000036, so a bare 4.0 threshold lifts it. The fire budget is what holds it.
quiet = dict(weekly_pct=96, weekly_reset_h=13.6, wk_strand_pp=4.0, burn_wk_ewma_ph=0.0, burn_wk_flat_ph=0.0)
first, (tk, spare, need), s4 = judge(**quiet)
assert s4 > s2 and (first, tk) == ("next2", "on-pace"), (first, tk)
assert spare >= ca.dispatch_strand_pp(R) and round(need, 1) == 5.5, (spare, need)
os.environ["CC_ROUTE_DISPATCH_FIRE_BURN_PPH"] = "0.05"          # control: without the budget it lifts
assert judge(**quiet)[:2] == ("next4", ("lifted", spare, ca.dispatch_strand_pp(R))), judge(**quiet)
os.environ.pop("CC_ROUTE_DISPATCH_FIRE_BURN_PPH")
# the edge, pinned as a fact rather than discovered later: weekly 96 lifts only inside ~10 h
assert judge(**dict(quiet, weekly_reset_h=9.0))[1][0] == "lifted"
assert judge(**dict(quiet, weekly_reset_h=10.2))[1][0] == "on-pace"
# 97-99 % never lifts, at any horizon, with no pace at all
for wp in (97, 98, 99):
    for wrh in (0.3, 2.0, 9.0, 24.0):
        tk = judge(weekly_pct=wp, weekly_reset_h=wrh, wk_strand_pp=100.0 - wp, burn_wk_ewma_ph=0.0,
                   burn_wk_flat_ph=0.0)[1][0]
        assert tk == "on-pace", (wp, wrh, tk)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "STRAND RESCUE: every verdict branch HOLDS on its own input — one control per token" {
  run python3 -c "$LOAD$SNAP"'
nan = float("nan")
cases = [
    ("level-stale",  dict(stale_quota=True)),
    ("hold-credits", dict(credits_on=True, weekly_pct=92)),
    ("pace-unknown", dict(wk_strand_pp=DROP)),
    ("pace-unknown", dict(burn_wk_ewma_ph=DROP)),
    ("pace-unknown", dict(wk_strand_pp=True)),
    ("pace-unknown", dict(burn_wk_ewma_ph="0.0")),
    ("pace-stale",   dict(burn_wk_flat_ph=DROP)),
    ("pace-stale",   dict(burn_wk_flat_ph=None)),
    ("on-pace",      dict(burn_wk_ewma_ph=0.2)),             # 6 - 0.2 x 13.2 = 3.4 spare
    ("on-pace",      dict(burn_wk_flat_ph=0.2)),             # the cross-check alone vetoes
    ("on-pace",      dict(wk_strand_pp=5.0)),                # under the 5.33 fire budget
    ("on-pace",      dict(wk_strand_pp=nan)),
    ("on-pace",      dict(burn_wk_ewma_ph=nan)),
    ("on-pace",      dict(burn_wk_flat_ph=nan)),
    ("claimed",      dict(k_placed=1)),
    ("claimed",      dict(k_phantom=1)),
    ("claimed",      dict(k_placed=nan)),
]
assert ca.dispatch_floor_row(snap()[0], R)[0] == "lifted"    # the base every case departs from
for want, change in cases:
    rows = snap(**change)
    tk, spare, need = ca.dispatch_floor_row(rows[0], R)
    assert tk == want, (want, change, tk, spare, need)
    out, _ = ca.ranked(rows, CFG2, WIN_OPEN, "general")
    assert order(out) == ["next4", "next", "next3", "next2"], (want, change, order(out))
    assert out[-1][1].get("thin_demoted") is True and tok(out) == want, (want, out[-1][1])
# an errored row is cut by eligibility before the floor sees it; asked directly, it is level-stale
assert ca.dispatch_floor_row(snap(error="usage 429")[0], R)[0] == "level-stale"
# the reset horizon is read RAW: absent, elapsed, past a week, NaN — each is unknown, never "far"
for wrh in (None, 0, -1.0, 168.5, nan, "13.2", True):
    r = snap()[0]; r["weekly_reset_h"] = wrh
    assert ca.dispatch_floor_row(r, R)[0] == "pace-unknown", wrh
# roomy is roomy whatever else the row says
assert ca.dispatch_floor_row(snap(weekly_pct=89)[0], R) == ("roomy", None, None)
assert ca.dispatch_floor_row(row(weekly_pct=None), R)[0] == "roomy"
# the claim scales: 2 placed needs 3 x the budget, and the spare is clipped by headroom not strand
big = dict(weekly_pct=91, weekly_reset_h=8.0, wk_strand_pp=9.0, burn_wk_ewma_ph=0.0)
assert ca.dispatch_floor_row(snap(k_placed=1, **big)[0], R)[0] == "lifted"        # 9 >= 2 x 4
assert ca.dispatch_floor_row(snap(k_placed=2, **big)[0], R)[0] == "claimed"       # 9 <  3 x 4
assert ca.dispatch_floor_row(snap(wk_strand_pp=50.0, burn_wk_ewma_ph=0.0)[0], R)[1] < 6.01
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "STRAND RESCUE promotion guards: a lifted row that may not go first rejoins the score order" {
  run python3 -c "$LOAD$SNAP"'
unparked = ["next4", "next", "next2", "next3"]
def general(rows):
    out, _ = ca.ranked(rows, CFG2, WIN_OPEN, "general")
    assert "thin_demoted" not in rows[0], rows[0]
    return order(out), tok(out)
assert general(snap()) == (["next2", "next4", "next", "next3"], "lifted-first")
# placement memory absent (CC_ROUTE_ASSIGN off, or a row that never met apply_assignments)
assert general(snap(k_placed=DROP)) == (unparked, "lifted")
assert general(snap(k_placed=True)) == (unparked, "lifted")
# a login cliff in play: soft, with the factor still on its score — the drain point (6.6h) is
# inside DESK_LIFE_H and before the 13.2h weekly reset, so neither strand-lift arm takes it off
soft = ca._cliff_env("CC_ROUTE_CLIFF_SOFT_H", ca.CLIFF_SOFT_H)
drain = ca._cliff_env("CC_ROUTE_CLIFF_DRAIN_H", ca.CLIFF_DRAIN_H)
life = ca._cliff_env("CC_ROUTE_DESK_LIFE_H", ca.DESK_LIFE_H)
got = general(snap(login_expires_h=drain + 6.6))
assert got[1] == "lifted" and got[0][0] != "next2", got
# ...but a soft cliff the strand lift has taken off the score is not in play (2196228fc): the
# DESK_LIFE_H arm (drain point past the life of any session), then the reset-first arm (the weekly
# reset lands before the drain point), whose kill switch puts the refusal back
assert general(snap(login_expires_h=soft - 1.0))[1] == "lifted-first"
assert general(snap(login_expires_h=drain + life - 1.0))[1] == "lifted-first"
os.environ["CC_ROUTE_CLIFF_RESET_FIRST"] = "off"
got = general(snap(login_expires_h=drain + life - 1.0))
assert got[1] == "lifted" and got[0][0] != "next2", got
os.environ.pop("CC_ROUTE_CLIFF_RESET_FIRST")
# 5h-hot: projected 5h utilisation at S_SOFT, measured and then by projection alone
hot = general(snap(session_pct=100.0 * R["S_SOFT"]))
assert hot[1] == "lifted" and hot[0][0] != "next2", hot
assert general(snap(session_pct=100.0 * R["S_SOFT"] - 1))[1] == "lifted-first"
assert general(snap(session_pct=10, burn_5h_ewma_ph=100.0 * R["S_SOFT"]))[1] == "lifted"
# a roomy rival that BOTH outscores it and resets sooner is the more urgent strand
rows = snap(); rows[1].update(weekly_reset_h=12.0, fable_reset_h=12.0)
assert ca.score_general(rows[1], CFG2)[0] > ca.score_general(rows[0], CFG2)[0]
assert general(rows) == (["next", "next4", "next2", "next3"], "lifted")
rows = snap(); rows[1].update(weekly_reset_h=12.0, fable_reset_h=12.0, session_pct=84)
assert 0 < ca.score_general(rows[1], CFG2)[0] < ca.score_general(rows[0], CFG2)[0]
assert general(rows)[1] == "lifted-first"                              # sooner, but out-scored
rows = snap(); rows[3].update(weekly_reset_h=12.0, weekly_pct=97)      # sooner, but THIN: not a rival
assert general(rows)[1] == "lifted-first"
# the fable lane lifts and never promotes: the snapshot row is out-scored there too
rows = snap()
fs = {r["acct"]: ca.score_fable(r, CFG2, WIN_OPEN)[0] for r in rows}
assert min(fs["next4"], fs["next"]) > fs["next2"] > 0, fs
out, _ = ca.ranked(rows, CFG2, WIN_OPEN, "fable")
assert order(out) == order(ca._ranked(snap(), CFG2, WIN_OPEN, "fable")[0]), order(out)
assert order(out)[0] != "next2" and tok(out) == "lifted", out
assert not any(r.get("thin_demoted") for _s, r in out), out
out, _ = ca.ranked(snap(k_placed=1), CFG2, WIN_OPEN, "fable")
assert order(out)[-1] == "next2" and out[-1][1]["thin_demoted"] is True and tok(out) == "claimed", out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "STRAND RESCUE invariants: nothing is excluded, no score moves, three ordered groups, no sticky flag" {
  run python3 -c "$LOAD$SNAP"'
def fleet():
    lift = dict(wk_strand_pp=8.0, burn_wk_ewma_ph=0.0, burn_wk_flat_ph=0.0, k=0, session_pct=3)
    return [row(acct="f1", weekly_pct=92, weekly_reset_h=7.0, k_placed=0, **lift),
            row(acct="f2", weekly_pct=93, weekly_reset_h=9.0, k_placed=0, **lift),
            row(acct="k1", weekly_pct=30, weekly_reset_h=60.0, k=0),
            row(acct="k2", weekly_pct=10, weekly_reset_h=150.0, k=0),
            row(acct="k3", weekly_pct=92, weekly_reset_h=5.0, **lift),          # lifted, no memory
            row(acct="h1", weekly_pct=95, weekly_reset_h=20.0, k=0),
            row(acct="h2", weekly_pct=99, weekly_reset_h=3.0, k=0)]
rows = fleet()
out, reasons = ca.ranked(rows, CFG2, WIN_OPEN, "general")
raw, _ = ca._ranked(fleet(), CFG2, WIN_OPEN, "general")
assert not reasons and sorted((r["acct"], s) for s, r in out) == sorted((r["acct"], s) for s, r in raw)
group = {"lifted-first": 0, "roomy": 1, "lifted": 1}
g = [group.get(r["dispatch_floor"], 2) for _s, r in out]
assert g == sorted(g) and set(g) == {0, 1, 2}, [(r["acct"], r["dispatch_floor"]) for _s, r in out]
for n in (0, 1, 2):
    ss = [s for (s, _r), gi in zip(out, g) if gi == n]
    assert len(ss) >= 2 and ss == sorted(ss, reverse=True), (n, ss)
assert sorted(r["acct"] for (_s, r), gi in zip(out, g) if gi == 0) == ["f1", "f2"]
assert sorted(r["acct"] for (_s, r), gi in zip(out, g) if gi == 1) == ["k1", "k2", "k3"]
assert all((r.get("thin_demoted") is True) == (gi == 2) for (_s, r), gi in zip(out, g))
# recovery and interactive never see the rule
for lane, kw in (("general", dict(recovery=True)), ("fable", dict(recovery=True)), ("interactive", {})):
    o, _ = ca.ranked(fleet(), CFG2, WIN_OPEN, lane, **kw)
    assert o and not any("dispatch_floor" in r or "thin_demoted" in r for _s, r in o), (lane, o)
# one shared set of dicts, re-ranked as a readout does (interactive, general, fable) and again
# after its facts change: each call speaks only for itself
rows = snap()
ca.ranked(rows, CFG2, WIN_OPEN, "interactive")
assert tok(ca.ranked(rows, CFG2, WIN_OPEN, "general")[0]) == "lifted-first"
assert tok(ca.ranked(rows, CFG2, WIN_OPEN, "fable")[0]) == "lifted" and "thin_demoted" not in rows[0]
rows[0]["k_placed"] = 1
assert tok(ca.ranked(rows, CFG2, WIN_OPEN, "general")[0]) == "claimed" and rows[0]["thin_demoted"] is True
rows[0]["weekly_pct"] = 50
assert tok(ca.ranked(rows, CFG2, WIN_OPEN, "general")[0]) == "roomy"
assert "thin_demoted" not in rows[0] and "dispatch_spare_pp" not in rows[0], rows[0]
# and a thin account that is the only routable one is line 1 under every verdict
for change in (dict(), dict(k_placed=1), dict(burn_wk_flat_ph=DROP)):
    out, _ = ca.ranked(snap(**change)[:1], CFG2, WIN_OPEN, "general")
    assert order(out) == ["next2"], (change, out)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "STRAND RESCUE constants: optional in the SSOT, range-validated, code default equals the SSOT, env falls back" {
  run python3 -c "$LOAD$SNAP"'
keys = {"DISPATCH_STRAND_PP": (ca.dispatch_strand_pp, ca.DISPATCH_STRAND_PP_DEFAULT),
        "DISPATCH_FIRE_BURN_PPH": (ca.dispatch_fire_burn_pph, ca.DISPATCH_FIRE_BURN_PPH_DEFAULT),
        "DISPATCH_CLAIM_TTL_MIN": (ca.dispatch_claim_ttl_min, ca.DISPATCH_CLAIM_TTL_MIN_DEFAULT)}
bare = {k: v for k, v in R.items() if k not in keys}
ca._validate_router({"router": bare})                                              # optional presence
for key, (fn, default) in keys.items():
    env = "CC_ROUTE_" + key
    lo, hi = ca.ROUTER_OPTIONAL_RANGES[key]
    assert key not in ca.ROUTER_KEYS and key in R and key in R["_dispatch"], key
    assert fn(R) == R[key] == default == fn(bare), (key, fn(R), R[key], default)   # absent => default
    for bad in (lo / 10.0, hi * 2.0, True, "4"):
        try:
            ca._validate_router({"router": dict(R, **{key: bad})})
        except SystemExit as e:
            assert key in str(e), e
        else:
            raise AssertionError((key, bad, "accepted"))
    mid = (lo + hi) / 2.0
    os.environ[env] = str(mid)
    assert fn(R) == mid, (key, fn(R))                                              # a number overrides
    for junk in ("not-a-number", "-3", ""):
        os.environ[env] = junk
        assert fn(R) == R[key], (key, junk, fn(R))                                 # malformed => SSOT
    os.environ[env] = str(lo / 10.0)
    assert fn(R) == lo, (key, fn(R))                                               # clamped, never 0
    os.environ[env] = str(hi * 10.0)
    assert fn(R) == hi, (key, fn(R))
    os.environ.pop(env)
# the typo the lower bounds exist for: a fraction typed for pp must not lift everything
os.environ["CC_ROUTE_DISPATCH_STRAND_PP"] = "0.04"
os.environ["CC_ROUTE_DISPATCH_FIRE_BURN_PPH"] = "0.0042"
thin1 = snap(weekly_pct=99, weekly_reset_h=1.0, wk_strand_pp=0.9, burn_wk_ewma_ph=0.0)[0]
assert ca.dispatch_floor_row(thin1, R)[0] == "on-pace"
# the threshold is live in both directions on the snapshot row (5.38 spare)
os.environ["CC_ROUTE_DISPATCH_FIRE_BURN_PPH"] = "0.05"
os.environ["CC_ROUTE_DISPATCH_STRAND_PP"] = "5.4"
assert ca.dispatch_floor_row(snap()[0], R)[0] == "on-pace"
os.environ["CC_ROUTE_DISPATCH_STRAND_PP"] = "5.3"
assert ca.dispatch_floor_row(snap()[0], R)[0] == "lifted"
os.environ.pop("CC_ROUTE_DISPATCH_STRAND_PP"); os.environ.pop("CC_ROUTE_DISPATCH_FIRE_BURN_PPH")
# CC_ROUTE_DISPATCH_STRAND is a switch, not a threshold: only off/0/false disable it
for v, want in (("7", "lifted"), ("on", "lifted"), ("off", "flat"), ("0", "flat"), ("false", "flat")):
    os.environ["CC_ROUTE_DISPATCH_STRAND"] = v
    assert ca.dispatch_floor_row(snap()[0], R)[0] == want, (v, want)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "STRAND RESCUE stamps: the flat pace sees a ledger hole and abstains on a stale ledger" {
  run python3 -c "$LOAD$SNAP"'
import time
from datetime import datetime, timezone
NOW = time.time()
iso = lambda t: datetime.fromtimestamp(t, timezone.utc).isoformat()
def series(reset_h, level, newest_h=0.0, span_h=30.0):
    """6-minute samples; level(h_ago) -> weekly_pct, or None to leave a hole."""
    out = []
    for i in range(int(span_h * 10), -1, -1):
        h = newest_h + i / 10.0
        wp = level(h)
        if wp is not None:
            out.append({"acct": "next2", "session_pct": 0, "weekly_pct": wp, "_t": NOW - h * 3600.0,
                        "session_reset_at": None, "weekly_reset_at": iso(NOW + reset_h * 3600.0)})
    return out
def stamped(reset_h, level, **kw):
    r = row(acct="next2", weekly_pct=94, weekly_reset_h=reset_h, session_pct=0, k=0, k_phantom=0, k_placed=0)
    ca.apply_burn([r], cfg, samples=series(reset_h, level, **kw))
    return r, ca.dispatch_floor_row(r, R)[0]
# quiet for 30 h: both paces read 0 and the row is lifted on what apply_burn itself stamped
r, tk = stamped(9.0, lambda h: 94)
assert (r["burn_wk_ewma_ph"], r["burn_wk_flat_ph"], r["wk_strand_pp"], tk) == (0.0, 0.0, 6.0, "lifted"), (r, tk)
# 5pp burned inside a 3 h hole, 4-7 h ago: the EWMA skips the >1 h pair and still reads 0
hole = lambda h: None if 4.0 < h < 7.0 else (94 if h <= 4.0 else 89)
r, tk = stamped(9.0, hole)
assert r["burn_wk_ewma_ph"] == 0.0 and r["wk_strand_pp"] == 6.0, r      # the nowcast alone would lift
assert r["burn_wk_flat_ph"] > 0.4 and tk == "on-pace", (r["burn_wk_flat_ph"], tk)
# ...and this close to the reset it is the 12 h span that catches it: over 24 h it is diluted
# to a pace that still leaves 4pp spare
f24 = ca.burn_wk_flat_ph(series(9.0, hole), NOW, ca.WK_FLAT_LOOKBACK_H)
f12 = ca.burn_wk_flat_ph(series(9.0, hole), NOW, ca.WK_FLAT_NEAR_LOOKBACK_H)
assert f12 > f24 > 0 and abs(r["burn_wk_flat_ph"] - f12) < 0.02, (f24, f12)   # own clock, one sample of slack
need = ca.dispatch_floor_row(r, R)[2]
assert 100 * ca.weekly_headroom(r) - f24 * 9.0 >= need > 100 * ca.weekly_headroom(r) - f12 * 9.0, (f24, f12, need)
r20, tk20 = stamped(20.0, hole)                     # beyond 12 h of the reset only 24 h is asked
assert abs(r20["burn_wk_flat_ph"] - f24) < 0.02 and tk20 == "on-pace", (r20, tk20)
# newest sample 2 h old: the flat pace abstains, the key is ABSENT, the row is held as stale
r, tk = stamped(9.0, lambda h: 94, newest_h=2.0)
assert "burn_wk_flat_ph" not in r and tk == "pace-stale", (r, tk)
assert ca.burn_wk_flat_ph(series(9.0, lambda h: 94, newest_h=0.9), NOW) == 0.0       # inside the bound
# under 6.8 h of roll-free span: abstain, as the EWMA does
assert ca.burn_wk_flat_ph(series(9.0, lambda h: 94, span_h=6.0), NOW) is None
assert ca.burn_wk_flat_ph(series(9.0, lambda h: 94, span_h=7.0), NOW) == 0.0
assert ca.burn_wk_flat_ph([], NOW) is None and ca.burn_wk_flat_ph(None, NOW) is None
# a weekly roll inside the span restarts it: 3 h since the roll is under the minimum
rolled = series(9.0, lambda h: 94)
for e in rolled:
    if NOW - e["_t"] > 3.0 * 3600.0:
        e["weekly_reset_at"] = iso(NOW - 3.0 * 3600.0); e["weekly_pct"] = 99
assert ca.burn_wk_flat_ph(rolled, NOW) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

@test "STRAND RESCUE stamps: k_placed remembers a placement for five hours, and is ABSENT with the term off" {
  run python3 -c "$LOAD$SNAP"'
import time
NOW = time.time()
P = os.environ["CC_ASSIGN_LOG"]
with open(P, "w") as f:
    for e in ({"t": NOW - 100 * 60, "acct": "next2", "src": "fire"},
              {"t": NOW - 360 * 60, "acct": "next2", "src": "fire"},
              {"t": NOW - 5 * 60, "acct": "next", "src": "fire"}):
        f.write(json.dumps(e) + "\n")
# ttl_min=None is every existing caller: a fire 100 min old is long past the 15-minute phantom...
assert ca.assignment_counts(cfg) == ca.assignment_counts(cfg, ttl_min=None) == {"next": 1}
# ...and still holds its claim; the one 6 h old does not
assert ca.assignment_counts(cfg, ttl_min=ca.dispatch_claim_ttl_min(R)) == {"next": 1, "next2": 1}
rows = snap(k_placed=DROP, k_phantom=DROP)
ca.apply_assignments(rows, cfg)
assert [(r["k_phantom"], r["k_placed"]) for r in rows] == [(0, 1), (1, 1), (0, 0), (0, 0)], rows
out, _ = ca.ranked(rows, CFG2, WIN_OPEN, "general")
assert tok(out) == "claimed" and order(out)[-1] == "next2", out
os.environ["CC_ROUTE_DISPATCH_CLAIM_TTL_MIN"] = "90"         # the knob reaches the ledger read
ca.apply_assignments(rows, cfg)
assert rows[0]["k_placed"] == 0 and tok(ca.ranked(rows, CFG2, WIN_OPEN, "general")[0]) == "lifted-first"
os.environ.pop("CC_ROUTE_DISPATCH_CLAIM_TTL_MIN")
# CC_ROUTE_ASSIGN=off: the key is REMOVED, not zeroed, so "not tracked" cannot read as "nothing
# placed" — the row is lifted into score order and never promoted
os.environ["CC_ROUTE_ASSIGN"] = "off"
ca.apply_assignments(rows, cfg)
assert all("k_placed" not in r and r["k_phantom"] == 0 for r in rows), rows
out, _ = ca.ranked(rows, CFG2, WIN_OPEN, "general")
assert tok(out) == "lifted" and order(out) == ["next4", "next", "next2", "next3"], out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}

# The same fleet through the CLI, with nothing stamped by hand: the cache holds the four rows and
# the verdict has to come from the utilization and assignment ledgers that apply_burn and
# apply_assignments read on every invocation. Arguments are `acct:minutes-ago` placements.
seed_snapshot() { python3 - "$@" <<'PY'
import json, os, sys, time, importlib.machinery, importlib.util
from datetime import datetime, timezone
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
now = time.time()
fleet = (("next2", 94.0, 13.2, 0.0, 7), ("next", 55.0, 30.2, 1.0, 10),
         ("next4", 38.0, 35.2, 9.0, 4), ("next3", 1.0, 86.2, 0.0, 0))
rows = [{"acct": a, "auth": "ok", "k": k, "session_pct": sp, "session_reset_h": 3.0,
         "weekly_pct": wk, "weekly_reset_h": wrh, "fable_pct": 7, "fable_reset_h": wrh,
         "credits_on": False} for a, wk, wrh, sp, k in fleet]
json.dump({"ts": now, "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None, "rows": rows}, open(os.environ["CACHE"], "w"))
iso = lambda t: datetime.fromtimestamp(t, timezone.utc).isoformat()
with open(os.environ["CC_UTIL_LOG"], "w") as f:           # 30 h of a QUIET next2, 6-minute sweeps
    for i in range(300, -1, -1):
        f.write(json.dumps({"ts": iso(now - i * 360.0), "acct": "next2", "session_pct": 0,
                            "weekly_pct": 94, "weekly_reset_at": iso(now + 13.2 * 3600.0)}) + "\n")
with open(os.environ["CC_ASSIGN_LOG"], "w") as f:
    for spec in sys.argv[1:]:
        acct, ago = spec.split(":")
        f.write(json.dumps({"t": now - float(ago) * 60.0, "acct": acct, "src": "fire"}) + "\n")
PY
}
# stdout account order on one line; stderr only. --max-age keeps a slow box on the seeded cache.
rank_order() { python3 "$CA_BIN" --rank "$@" --max-age 600 2>/dev/null | awk '{printf "%s ", $1}'; }
rank_meta() { { python3 "$CA_BIN" --rank "$@" --max-age 600 >/dev/null; } 2>&1; }

@test "STRAND RESCUE through the CLI: line 1 is the stranding account on a LOWER score, and route-meta says why" {
  seed_snapshot
  run bash -c "python3 '$CA_BIN' --rank general --max-age 600 2>/dev/null"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${#lines[@]}" -eq 4 ] || { echo "$output"; false; }
  [ "${lines[0]%% *}" = "next2" ] || { echo "$output"; false; }
  # line 1 carries a lower score than line 2: the order is the rule's, the scores are untouched
  python3 -c 'import sys; a, b = (float(x.split()[1]) for x in sys.argv[1:3]); sys.exit(0 if 0 < a < b else 1)' \
    "${lines[0]}" "${lines[1]}" || { echo "$output"; false; }
  run bash -c "python3 '$CA_BIN' --route general --max-age 600 2>/dev/null"
  [ "$output" = "next2" ] || { echo "$output"; false; }
  run rank_meta general
  [[ "$output" == *" repick_ratio=4 dispatch_floor=next2:lifted-first:6.0"* ]] || { echo "$output"; false; }
  # the fable lane lifts without promoting; --recovery carries no token at all
  run rank_meta fable
  [[ "$output" == *" dispatch_floor=next2:lifted:6.0"* ]] || { echo "$output"; false; }
  run rank_meta general --recovery
  [[ "$output" == *"route-meta:"* ]] || { echo "$output"; false; }
  [[ "$output" != *"dispatch_floor="* ]] || { echo "$output"; false; }
}

@test "STRAND RESCUE through the CLI: the kill switches, a placement's claim, and a fleet with no ledger" {
  seed_snapshot
  # the kill switch: the 2026-09-27 order with the same four `acct score` lines, reason in the token
  run bash -c "python3 '$CA_BIN' --rank general --max-age 600 2>/dev/null | sort"
  local promoted="$output"
  run bash -c "CC_ROUTE_DISPATCH_STRAND=off python3 '$CA_BIN' --rank general --max-age 600 2>/dev/null"
  [ "$(printf '%s\n' "$output" | awk '{printf "%s ", $1}')" = "next4 next next3 next2 " ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | sort)" = "$promoted" ] || { echo "$output / $promoted"; false; }
  run bash -c "CC_ROUTE_DISPATCH_STRAND=off python3 '$CA_BIN' --rank general --max-age 600 2>&1 >/dev/null"
  [[ "$output" == *" dispatch_floor=next2:flat:-"* ]] || { echo "$output"; false; }
  run bash -c "CC_ROUTE_DISPATCH_STRAND_FIRST=off python3 '$CA_BIN' --rank general --max-age 600 2>/dev/null"
  [ "$(printf '%s\n' "$output" | awk '{printf "%s ", $1}')" = "next4 next next2 next3 " ] || { echo "$output"; false; }

  # one fire placed there 100 minutes ago: the 15-minute phantom is long gone, the claim is not
  seed_snapshot "next2:100"
  run rank_order general
  [ "$output" = "next4 next next3 next2 " ] || { echo "$output"; false; }
  run rank_meta general
  [[ "$output" == *" dispatch_floor=next2:claimed:6.0"* ]] || { echo "$output"; false; }

  # a thin account with no ledger behind it is held, as before 2026-10-09, and says so; with no
  # thin candidate at all the token is a bare dash, never absent
  rm -f "$CC_UTIL_LOG" "$CC_ASSIGN_LOG"
  seed "a98:98:10" "a11:11:10"
  run rank_meta general
  [[ "$output" == *" dispatch_floor=a98:pace-unknown:-"* ]] || { echo "$output"; false; }
  seed "fat:5:10" "mid:50:10"
  run rank_meta general
  grep -Eq ' dispatch_floor=-( |$)' <<<"$output" || { echo "$output"; false; }
}

@test "STRAND RESCUE drain line: the soonest-reset account says why new fires skip it, or that it is first in line" {
  run python3 -c "$LOAD$SNAP"'
def line(rows):
    for r in rows:
        r["auth"] = "ok"
    return ca.soonest_reset_line(rows, cfg)
base = line(snap())
assert base.startswith("next reset: next2 in ") and base.endswith(
    " · ~5pp dies at 48h pace · first in line for new work"), base
assert line(snap(k_placed=DROP)).endswith(" · open to new work")
assert line(snap(k_placed=1)).endswith(
    " · held for new work: a recent fire already claims that spare quota")
assert line(snap(burn_wk_ewma_ph=0.2, wk_strand_pp=3.4)).endswith(
    " · held for new work: 3.4pp would die unused, a new task needs 5.3")
assert line(snap(burn_wk_flat_ph=DROP)).endswith(" · held for new work: its pace reading is stale")
assert line(snap(wk_strand_pp=DROP, burn_wk_ewma_ph=DROP)).endswith(" · held for new work: no pace reading yet")
assert line(snap(stale_quota=True)).endswith(" · held for new work: its quota reading is stale")
os.environ["CC_ROUTE_DISPATCH_STRAND"] = "off"
assert line(snap()).endswith(" · held for new work: under 10% of the week left")
os.environ.pop("CC_ROUTE_DISPATCH_STRAND")
# recomputed, never read off a stamp: a row another lane left flagged still reports its own verdict
rows = snap(); rows[0].update(thin_demoted=True, dispatch_floor="claimed")
assert line(rows) == base, line(rows)
# a roomy soonest-reset account gets no clause, and an excluded one keeps its routing reason
assert "new work" not in line(snap(weekly_pct=60, wk_strand_pp=30.0))
assert "not routed: " in line(snap(k=10 ** 6)) and "new work" not in line(snap(k=10 ** 6))
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || false
}
