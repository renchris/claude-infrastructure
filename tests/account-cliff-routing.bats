#!/usr/bin/env bats
# account-cliff-routing — the login-cliff routing term (ACCOUNT_ROUTING_V2 M1, row 7).
#
# WHAT THIS EXISTS TO PIN. Before M1, every login_expires_* read in bin/claude-accounts lived in a
# producer, a re-deriver or a RENDERER, and the four functions that decide which account works
# (_excluded / score_general / score_fable / ranked) never mentioned the cliff once — measured 0
# references, positive-controlled against session_pct in the same region. So the subsystem whose
# whole job is "which account works" treated the one fact deciding whether an account will STILL
# work as a display string, while the only mechanism that acts on the cliff (cc-relogin) needs
# k == 0 on a fleet that sits at k = 5-6 and was therefore 0-BY-CONSTRUCTION.
#
# The three properties here that are NOT "does the feature work" — they are the reasons it is safe:
#   · YIELD (R11): a drained account still WORKS, so a drain must never be reported as "no account
#     has headroom". Un-yielded, this term converts a survivable 4-account cliff calendar into a
#     dispatch OUTAGE via cc-route's exit 4, which row 5 consumes as a hard stop.
#   · FAIL-OPEN (R9): login_expires_h is not on every build; reading its ABSENCE as "cliff
#     imminent" would exclude the entire fleet on an older binary.
#   · R3 NON-REGRESSION: missing live quota must still exclude a row. The cliff term is layered
#     ON a design that already bars remembered quota from routing; that must survive.
#
# Hermetic, in the companion suites' style: scratch SSOT + cache in BATS_TEST_TMPDIR, unreachable
# endpoints, a config_dir that hashes to a nonexistent keychain service. Router constants are
# DERIVED from the repo accounts.json, never hand-copied.

setup() {
  # A suite that tests a wrapper must not inherit that wrapper's env: bin/cc-bats exports
  # CC_BATS_ACTIVE=1, and anything under test that short-circuits on it would be exercised in a
  # mode no production caller ever runs (measured elsewhere on this campaign: 16/16 green plain,
  # 14/16 through the shim, with nothing naming the harness).
  unset CC_BATS_ACTIVE
  # The cliff term's own knobs must never leak in from the invoking shell either — a session that
  # exported CC_ROUTE_CLIFF_TERM=off would turn every assertion below vacuous.
  unset CC_ROUTE_CLIFF_TERM CC_ROUTE_CLIFF_SOFT_H CC_ROUTE_CLIFF_DRAIN_H CC_ROUTE_CLIFF_SOFT_FACTOR

  # Fixture $HOME before anything else. Overriding CLAUDE_ACCOUNTS_JSON / _LASTGOOD / cache_file is
  # not sufficient: bin/claude-accounts derives several other paths from $HOME (the relogin-poll
  # log it reads for LAST ATTEMPT, the CLAUDE_CONFIG_DIR fallback), so an unfixtured run reads —
  # and could write — the operator's live ~/.claude. ship-land's hermeticity ratchet blocks on
  # exactly this, and it blocked THIS suite before it landed.
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
  export YAML="$BATS_TEST_TMPDIR/model-config.yaml"
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
  "accounts": [{"name": "next3", "config_dir": "/tmp/ca-cliff-test-nonexistent-xyz",
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
# HERMETICITY: LOG_PATH resolves at import from $HOME, so any case reaching a log_event() call
# appends to the REAL ~/.claude/logs/claude-accounts.log. That stayed invisible only because
# every case stubbed ca.heal, which was the sole log_event caller on these paths; the moment a
# log line was added OUTSIDE that stub, three fabricated "heal next3: UNPROVEN" entries landed
# in the production log and read there as genuine fleet events. Redirect once, for every case.
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
R = cfg["router"]
WIN_OPEN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
def row(**kw):
    base = dict(acct="a", session_pct=10, session_reset_h=3.0, weekly_pct=40,
                weekly_reset_h=24.0, fable_pct=20, fable_reset_h=24.0, k=2, credits_on=False)
    base.update(kw); return base
'

# Seed the shared cache with N rows so the CLI runs with no network and no keychain.
# `login_expires_h` is passed through per row so a band can be dialed exactly.
seed() { python3 - "$@" <<'PY'
import json, os, time, importlib.machinery, importlib.util
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
import sys
rows = []
for spec in sys.argv[1:]:
    acct, lxh, wk = spec.split(":")
    r = {"acct": acct, "auth": "ok", "k": 0, "session_pct": 10, "session_reset_h": 3.0,
         "weekly_pct": float(wk), "weekly_reset_h": 20.0, "fable_pct": 20, "fable_reset_h": 20.0,
         "credits_on": False}
    if lxh != "none":
        r["login_expires_h"] = float(lxh)
    rows.append(r)
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None, "rows": rows}, open(os.environ["CACHE"], "w"))
PY
}

# ── the band classifier ─────────────────────────────────────────────────────────────────────────

@test "cliff_band: drain <= 48h, soft <= 168h, none beyond — off the DERIVED poller constants" {
  run python3 -c "$LOAD"'
assert ca.CLIFF_DRAIN_H == 48.0, ca.CLIFF_DRAIN_H
assert ca.CLIFF_SOFT_H == 168.0, ca.CLIFF_SOFT_H
assert ca.cliff_band(row(login_expires_h=0.0))    == "drain"
assert ca.cliff_band(row(login_expires_h=47.9))   == "drain"
assert ca.cliff_band(row(login_expires_h=48.0))   == "drain"   # boundary is INCLUSIVE
assert ca.cliff_band(row(login_expires_h=48.1))   == "soft"
assert ca.cliff_band(row(login_expires_h=168.0))  == "soft"    # boundary is INCLUSIVE
assert ca.cliff_band(row(login_expires_h=168.1))  == "none"
assert ca.cliff_band(row(login_expires_h=-5.0))   == "drain"   # past the wall is still drain
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

@test "FAIL-OPEN (R9): an ABSENT or unparseable cliff disables the term, and the control proves it is not vacuous" {
  run python3 -c "$LOAD"'
# absent / null / garbage ⇒ no band at all
assert ca.cliff_band(row())                        == "none"
assert ca.cliff_band(row(login_expires_h=None))    == "none"
assert ca.cliff_band(row(login_expires_h="soon"))  == "none"
# ...and such a row still RANKS (the whole point: an older build must not lose its fleet)
assert ca._excluded(row(login_expires_h=None), R) is None
assert ca.score_general(row(login_expires_h=None), cfg)[0] > 0
# POSITIVE CONTROL beside the absence assertion: with the field PRESENT and inside the drain
# band the same row IS excluded, so "None ⇒ routable" is a real branch, not a no-op suite.
assert ca._excluded(row(login_expires_h=1.0), R) == "login-cliff-drain"
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

# ── the exclusion, and its ORDER ────────────────────────────────────────────────────────────────

@test "_excluded: the drain band excludes with a NAMED policy reason, classified policy not data" {
  run python3 -c "$LOAD"'
assert ca._excluded(row(login_expires_h=10.0), R) == "login-cliff-drain"
assert ca.CLIFF_DRAIN_REASON not in ca.DATA_UNAVAILABLE
# policy, not data: a drain is a decision we made, never a gap in what we could see. Getting
# this wrong sends --route to exit 3 (degrade to a proxy) instead of 2.
assert ca.reason_class(row(login_expires_h=10.0), ca.CLIFF_DRAIN_REASON) == "policy"
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

@test "_excluded: the cliff is checked LAST, so a data gap and a real cap keep their own reasons" {
  run python3 -c "$LOAD"'
# every one of these rows is ALSO inside the drain band; each must still report its own cause.
assert ca._excluded(dict(acct="a", error="logged-out", login_expires_h=1.0), R) == "logged-out"
assert ca._excluded(row(session_pct=None, login_expires_h=1.0), R) == "no-session-data"
assert ca._excluded(row(session_pct=86, session_reset_h=2.0, login_expires_h=1.0), R) == "5h-cutoff"
assert ca._excluded(row(k=R["KMAX"], login_expires_h=1.0), R) == "kmax-concurrency"
# ...and with none of those causes present, the cliff is what speaks.
assert ca._excluded(row(login_expires_h=1.0), R) == "login-cliff-drain"
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

@test "R3 NON-REGRESSION: a row with no live quota is excluded even when a cliff is known" {
  run python3 -c "$LOAD"'
# The last-good ledger may supply a cliff for a broken account (M3a). That must NOT make it
# routable: every inheritance path leaves row["error"], and _excluded bails on error FIRST.
r = dict(acct="a", error="poll throttled", login_expires_h=500.0, weekly_pct=10,
         session_pct=10, session_reset_h=3.0, k=0)
assert ca._excluded(r, R) == "poll throttled"
assert ca.score_general(r, cfg) == (None, "poll throttled")
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

# ── the soft band ───────────────────────────────────────────────────────────────────────────────

@test "soft band multiplies BOTH scores by exactly CLIFF_SOFT_FACTOR, and leaves none-band untouched" {
  run python3 -c "$LOAD"'
base_g = ca.score_general(row(login_expires_h=500.0), cfg)[0]
soft_g = ca.score_general(row(login_expires_h=100.0), cfg)[0]
base_f = ca.score_fable(row(login_expires_h=500.0), cfg, WIN_OPEN)[0]
soft_f = ca.score_fable(row(login_expires_h=100.0), cfg, WIN_OPEN)[0]
assert abs(soft_g - base_g * ca.CLIFF_SOFT_FACTOR) < 1e-12, (soft_g, base_g)
assert abs(soft_f - base_f * ca.CLIFF_SOFT_FACTOR) < 1e-12, (soft_f, base_f)
# a soft-band account is DEPRIORITIZED, never excluded — capacity is not discarded a week early
assert soft_g > 0 and soft_f > 0
# and a row outside every band scores exactly as it did before the term existed
assert ca.score_general(row(), cfg)[0] == base_g
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

# ── R11: the YIELD, and its discriminating control ──────────────────────────────────────────────

@test "YIELD (R11): when the cliff term empties the fleet, ranked() re-admits and MARKS it" {
  run python3 -c "$LOAD"'
rows = [row(acct="a", login_expires_h=10.0), row(acct="b", login_expires_h=5.0)]
out, reasons = ca.ranked(rows, cfg, WIN_OPEN, "general")
# a drained account STILL WORKS — the cliff has not passed — so a candidate MUST come back
assert out, (out, reasons)
assert [r["acct"] for _s, r in out]
# the override is recorded on the ROW, never as a synthetic key in the account-keyed reasons map
# (route_line renders len(reasons) as "N excluded", so a non-account key inflates a rendered count)
assert all(r.get("cliff_yielded") for _s, r in out), out
assert not any(k.startswith("_") for k in reasons), reasons
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

@test "YIELD does NOT fire for a NON-cliff emptiness — exhausted stays exhausted (discriminating control)" {
  run python3 -c "$LOAD"'
# Same shape as the yield test, but the fleet is empty because quota is GONE, not because of a
# cliff. Yielding here would fabricate headroom, which is the opposite failure.
rows = [row(acct="a", weekly_pct=100, login_expires_h=10.0),
        row(acct="b", weekly_pct=100, login_expires_h=5.0)]
out, reasons = ca.ranked(rows, cfg, WIN_OPEN, "general")
assert out == [], out
assert set(reasons.values()) == {"weekly-exhausted"}, reasons
# ...and with NO cliff anywhere, an exhausted fleet is still empty (the term added nothing)
rows2 = [row(acct="a", weekly_pct=100), row(acct="b", weekly_pct=100)]
assert ca.ranked(rows2, cfg, WIN_OPEN, "general")[0] == []
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

@test "YIELD: a drain must not MASK the binding reason — found by this suite, and it flips an exit code" {
  run python3 -c "$LOAD"'
# _excluded returns the drain BEFORE score_general can reach "no-weekly-data", so a fleet that is
# really DATA-BLIND would have reported the drain instead. The data-vs-policy split drives the
# exit code: policy ⇒ 2 (do NOT fire blind), data ⇒ 3 (callers may degrade to a proxy). Reporting
# the drain here turns a data outage into a policy refusal — the wrong verdict, in the direction
# that HIDES the outage.
rows = [row(acct="a", weekly_pct=None, login_expires_h=10.0),
        row(acct="b", weekly_pct=None, login_expires_h=5.0)]
out, reasons = ca.ranked(rows, cfg, WIN_OPEN, "general")
assert out == [], out
assert set(reasons.values()) == {"no-weekly-data"}, reasons
assert all(ca.reason_class(r, reasons[r["acct"]]) == "data" for r in rows), reasons
# POSITIVE CONTROL: the same masking check for a POLICY cause reports that cause, not the drain
p = [row(acct="a", weekly_pct=100, login_expires_h=10.0)]
assert ca.ranked(p, cfg, WIN_OPEN, "general")[1] == {"a": "weekly-exhausted"}
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

@test "--route: a data-blind fleet that is ALSO drained still exits 3, not the policy 2" {
  seed "next3:5.0:40" "next2:9.0:40"
  # blank the weekly figure on both rows: data-unavailable, and both inside the drain band
  python3 -c '
import json, os
c = json.load(open(os.environ["CACHE"]))
for r in c["rows"]: r["weekly_pct"] = None
json.dump(c, open(os.environ["CACHE"], "w"))'
  run bash -c "python3 '$CA_BIN' --route general 2>/dev/null"
  [ "$status" -eq 3 ] || false
  [ "${lines[0]}" = "none" ] || false
  run bash -c "python3 '$CA_BIN' --route general 2>&1 >/dev/null"
  [[ "$output" == *"no-weekly-data"* ]] || false
  [[ "$output" != *"login-cliff-drain"* ]] || false
}

@test "YIELD prefers a NON-drained account and does not mark it — the drain is a real preference" {
  run python3 -c "$LOAD"'
rows = [row(acct="drained", login_expires_h=5.0), row(acct="healthy", login_expires_h=500.0)]
out, reasons = ca.ranked(rows, cfg, WIN_OPEN, "general")
assert out[0][1]["acct"] == "healthy", out
assert reasons.get("drained") == "login-cliff-drain", reasons
assert not out[0][1].get("cliff_yielded")     # nothing was yielded; the drain simply held
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

# ── the CLI contract: exit codes row 5 consumes ─────────────────────────────────────────────────

@test "--route: a wholly cliff-drained fleet exits 0 with an ACCOUNT, never the exit-2 policy-none that becomes a fleet QUOTA CLIFF" {
  seed "next3:5.0:40" "next2:9.0:40"
  run bash -c "python3 '$CA_BIN' --route general 2>/dev/null"
  [ "$status" -eq 0 ] || false
  [ "${lines[0]}" != "none" ] || false
  run bash -c "python3 '$CA_BIN' --route general 2>&1 >/dev/null"
  [[ "$output" == *"login-cliff drain YIELDED"* ]] || false
  [[ "$output" == *"cc-relogin"* ]] || false
}

@test "--route: a PARTIALLY drained fleet routes to the healthy account and names the drain on stderr" {
  seed "next3:5.0:40" "next2:500.0:40"
  run bash -c "python3 '$CA_BIN' --route general 2>/dev/null"
  [ "$status" -eq 0 ] || false
  [ "${lines[0]}" = "next2" ] || false
  run bash -c "python3 '$CA_BIN' --route general 2>&1 >/dev/null"
  [[ "$output" == *"next3=login-cliff-drain"* ]] || false
  # a held drain is NOT a yield — the loud yield notice must be absent here
  [[ "$output" != *"YIELDED"* ]] || false
}

@test "--route: an exhausted fleet still exits 2 even when every account is also drained" {
  seed "next3:5.0:100" "next2:9.0:100"
  run bash -c "python3 '$CA_BIN' --route general 2>/dev/null"
  [ "$status" -eq 2 ] || false
  [ "${lines[0]}" = "none" ] || false
}

@test "--json exposes cliff_band per row so a routing decision's INPUT is recordable" {
  seed "next3:5.0:40" "next2:100.0:40" "next4:500.0:40"
  run bash -c "python3 '$CA_BIN' --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin)
b={r[\"acct\"]: r.get(\"cliff_band\") for r in d[\"rows\"]}
assert b == {\"next3\":\"drain\",\"next2\":\"soft\",\"next4\":\"none\"}, b
print(\"OK\")'"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

# ── R8: the kill switch, and knob robustness ────────────────────────────────────────────────────

@test "R8 kill switch: CC_ROUTE_CLIFF_TERM=off restores pre-term scoring exactly" {
  run python3 -c "$LOAD"'
import os
drained = row(login_expires_h=1.0); softened = row(login_expires_h=100.0)
os.environ["CC_ROUTE_CLIFF_TERM"] = "off"
assert ca.cliff_band(drained) == "none"
assert ca._excluded(drained, R) is None
assert ca.score_general(softened, cfg)[0] == ca.score_general(row(login_expires_h=500.0), cfg)[0]
del os.environ["CC_ROUTE_CLIFF_TERM"]
# and the control: with the switch absent the term is BACK ON, so "off" was doing the work
assert ca._excluded(drained, R) == "login-cliff-drain"
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}

@test "knobs: the bands are env-tunable, and a MALFORMED value is ignored rather than silently disabling the term" {
  run python3 -c "$LOAD"'
import os
r = row(login_expires_h=100.0)
assert ca.cliff_band(r) == "soft"
os.environ["CC_ROUTE_CLIFF_DRAIN_H"] = "200"      # widen the drain band over it
assert ca.cliff_band(r) == "drain"
os.environ["CC_ROUTE_CLIFF_DRAIN_H"] = "not-a-number"
# a typo in a tuning knob must fall back to the DEFAULT, never to 0 (which would disable the
# safety term) and never raise inside the router.
assert ca.cliff_band(r) == "soft", "malformed knob must fall back to the default"
os.environ["CC_ROUTE_CLIFF_DRAIN_H"] = "-1"
assert ca.cliff_band(r) == "soft", "a negative knob must fall back to the default"
del os.environ["CC_ROUTE_CLIFF_DRAIN_H"]
os.environ["CC_ROUTE_CLIFF_SOFT_FACTOR"] = "1.0"
assert ca.score_general(r, cfg)[0] == ca.score_general(row(login_expires_h=500.0), cfg)[0]
del os.environ["CC_ROUTE_CLIFF_SOFT_FACTOR"]
print("OK")'
  [ "$status" -eq 0 ] || false
  [[ "$output" == *OK* ]] || false
}
