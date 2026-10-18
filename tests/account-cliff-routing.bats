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
# RED-proof (reset-first, post-mortem 2026-10-18 §4 item 3): with the reset-first arm of
# _strand_cliff_factor replaced by `False`, the reset-first unit, the 2026-10-17T22:54Z replay and
# the _dispatch_first case go red, and the 2026-10-16 replay stays green (at that instant next's
# login was 144h out, so it pins the earlier DESK_LIFE_H lift; its in-test control reproduces the
# logged last place). Reverting _dispatch_first to `cliff_band(r) != "none"` reds its own case.
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
  unset CC_ROUTE_DESK_CLIFF_WINDOW CC_ROUTE_DESK_LIFE_H CC_ROUTE_DESK_CLIFF_STRAND_PP CC_ROUTE_DESK_HYST
  unset CC_ROUTE_DISPATCH_CLIFF_WINDOW CC_ROUTE_CLIFF_RESET_FIRST

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
# The cap is derived from the INSTRUMENT that charged the row (k_cap, §5 P2), so the cause this
# case needs is spelled per-instrument. `row()` sets `k` and no `k_work`, i.e. the PANE census —
# whose cap is KMAX_RESIDENT. Asserting KMAX here would be asserting the conflation that item
# removed: 4 accounts x KMAX 8 refused the 33rd RESIDENT session fleet-wide.
assert ca._excluded(row(k=ca.k_cap(row(), R), login_expires_h=1.0), R) == "kmax-concurrency"
assert ca._excluded(row(k=0, k_work=R["KMAX"], login_expires_h=1.0), R) == "kmax-concurrency"
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

# ── the desk lane: the soft factor is lifted only for a stranding week, drain past desk life ─────

@test "desk 2026-10-03T02:22Z regression: a stranding soft account whose drain is past any desk lifetime ranks by earliest reset" {
  run python3 -c "$LOAD"'
import os
# wk_strand_pp 62 = the readout nowcast for next4 that night ("strand ~62pp of 75")
n4 = row(acct="next4", weekly_pct=25, weekly_reset_h=30.6529, login_expires_h=128.36,
         wk_strand_pp=62.0)
n3 = row(acct="next3", weekly_pct=32, weekly_reset_h=81.6529, login_expires_h=518.29)
assert ca.cliff_band(n4) == "soft"
out, _ = ca.ranked([n3, n4], cfg, WIN_OPEN, "interactive")
assert [r["acct"] for _s, r in out][0] == "next4", out
key4 = ca.score_interactive(n4, cfg)[0] - ca.desk_keys(n4, cfg)[2]
assert abs(key4 - 1.0 / (1.0 + ca.horizon(30.6529, R))) < 1e-12, key4
n3["desk_incumbent"] = True
out, _ = ca.ranked([n3, n4], cfg, WIN_OPEN, "interactive")
assert [r["acct"] for _s, r in out][0] == "next4", out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "desk soft factor stays when the week is NOT stranding: relogin poll ticks are kept" {
  run python3 -c "$LOAD"'
import os
# the same next4-shaped row on pace to use its week (the September next2 case, 0pp stranded)
n3 = row(acct="next3", weekly_pct=32, weekly_reset_h=81.6529, login_expires_h=518.29)
def n4(**kw):
    return row(acct="next4", weekly_pct=25, weekly_reset_h=30.6529, login_expires_h=128.36, **kw)
for kw in ({}, {"wk_strand_pp": None}, {"wk_strand_pp": 0.0}, {"wk_strand_pp": 3.99}):
    assert ca._desk_cliff_factor(n4(**kw)) == ca.CLIFF_SOFT_FACTOR, kw    # unknown => keep it
    out, _ = ca.ranked([n3, n4(**kw)], cfg, WIN_OPEN, "interactive")
    assert [r["acct"] for _s, r in out][0] == "next3", (kw, out)
assert ca._desk_cliff_factor(n4(wk_strand_pp=4.0)) == 1.0                  # the floor is inclusive
os.environ["CC_ROUTE_DESK_CLIFF_STRAND_PP"] = "70"
assert ca._desk_cliff_factor(n4(wk_strand_pp=62.0)) == ca.CLIFF_SOFT_FACTOR
for bad in ("abc", "-1"):                                                  # malformed => default 4
    os.environ["CC_ROUTE_DESK_CLIFF_STRAND_PP"] = bad
    assert ca._desk_cliff_factor(n4(wk_strand_pp=4.0)) == 1.0, bad
    assert ca._desk_cliff_factor(n4(wk_strand_pp=3.0)) == ca.CLIFF_SOFT_FACTOR, bad
del os.environ["CC_ROUTE_DESK_CLIFF_STRAND_PP"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "desk soft band still demotes by exactly CLIFF_SOFT_FACTOR once drain is within DESK_LIFE_H" {
  run python3 -c "$LOAD"'
# a stranding week throughout, so this case isolates the drain-overlap condition; the 125h reset
# falls after every drain point below, so the reset-first arm stays out of it
clear = row(weekly_reset_h=125.0)
ck = ca.score_interactive(clear, cfg)[0] - ca.desk_keys(clear, cfg)[2]
def key(lx):
    r = row(weekly_reset_h=125.0, login_expires_h=lx, wk_strand_pp=50.0)
    return ca.score_interactive(r, cfg)[0] - ca.desk_keys(r, cfg)[2]
assert ca.DESK_LIFE_H == 60.0
assert abs(key(80.0) - ck * ca.CLIFF_SOFT_FACTOR) < 1e-12
assert abs(key(108.0) - ck * ca.CLIFF_SOFT_FACTOR) < 1e-12     # drain_in == 60: still demoted
assert key(108.01) == ck                                        # just past: lifted
assert key(168.0) == ck
# a near-drain account whose reset falls after its drain point (60h > 90-48) loses the desk
# exactly as before, even with the earlier reset
near = row(acct="near", weekly_reset_h=60.0, login_expires_h=90.0, wk_strand_pp=50.0)
rival = row(acct="rival", weekly_reset_h=81.0)
out, _ = ca.ranked([near, rival], cfg, WIN_OPEN, "interactive")
assert [r["acct"] for _s, r in out][0] == "rival", out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "desk kill switch: CC_ROUTE_DESK_CLIFF_WINDOW=off restores the x0.25 across the whole soft band" {
  run python3 -c "$LOAD"'
import os
n4 = row(acct="next4", weekly_pct=25, weekly_reset_h=30.6529, login_expires_h=128.36,
         wk_strand_pp=62.0)
n3 = row(acct="next3", weekly_pct=32, weekly_reset_h=81.6529, login_expires_h=518.29)
os.environ["CC_ROUTE_DESK_CLIFF_WINDOW"] = "off"
out, _ = ca.ranked([n3, n4], cfg, WIN_OPEN, "interactive")
assert [r["acct"] for _s, r in out][0] == "next3", out          # the old pick: the bug reproduces
assert ca._desk_cliff_factor(n4) == ca.CLIFF_SOFT_FACTOR
del os.environ["CC_ROUTE_DESK_CLIFF_WINDOW"]
out, _ = ca.ranked([n3, n4], cfg, WIN_OPEN, "interactive")
assert [r["acct"] for _s, r in out][0] == "next4", out          # control: off was doing the work
os.environ["CC_ROUTE_CLIFF_TERM"] = "off"
assert ca._desk_cliff_factor(row(login_expires_h=80.0)) == 1.0
del os.environ["CC_ROUTE_CLIFF_TERM"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "desk knob CC_ROUTE_DESK_LIFE_H: tunable, and malformed or negative falls back to 60" {
  run python3 -c "$LOAD"'
import os
S = 50.0                                   # a stranding week, so only the life knob is under test
W = 150.0                                  # reset after every drain point: reset-first stays out
r128 = row(login_expires_h=128.0, wk_strand_pp=S, weekly_reset_h=W)
assert ca._desk_cliff_factor(r128) == 1.0
for bad in ("abc", "-1"):
    os.environ["CC_ROUTE_DESK_LIFE_H"] = bad
    assert ca._desk_cliff_factor(r128) == 1.0, bad
    assert ca._desk_cliff_factor(row(login_expires_h=100.0, wk_strand_pp=S, weekly_reset_h=W)) \
        == ca.CLIFF_SOFT_FACTOR, bad
os.environ["CC_ROUTE_DESK_LIFE_H"] = "200"
assert ca._desk_cliff_factor(r128) == ca.CLIFF_SOFT_FACTOR
os.environ["CC_ROUTE_DESK_LIFE_H"] = "0"
assert ca._desk_cliff_factor(row(login_expires_h=60.0, wk_strand_pp=S, weekly_reset_h=W)) == 1.0
del os.environ["CC_ROUTE_DESK_LIFE_H"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "with no strand forecast, dispatch and fable keep exactly x0.25, and the drain band is unchanged" {
  run python3 -c "$LOAD"'
soft = row(weekly_reset_h=30.0, login_expires_h=128.0)
base = row(weekly_reset_h=30.0, login_expires_h=500.0)
assert abs(ca.score_general(soft, cfg)[0] - ca.score_general(base, cfg)[0] * ca.CLIFF_SOFT_FACTOR) < 1e-12
assert abs(ca.score_fable(soft, cfg, WIN_OPEN)[0] - ca.score_fable(base, cfg, WIN_OPEN)[0] * ca.CLIFF_SOFT_FACTOR) < 1e-12
assert ca.score_interactive(row(weekly_reset_h=5.0, login_expires_h=40.0), cfg) == (None, ca.CLIFF_DRAIN_REASON)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ── the dispatch lanes (general, fable): the desk's lift, so handoff spends the dying week first ──

@test "dispatch 2026-10-17T07:25Z regression: a stranding soft account with the earliest reset leads general AND fable" {
  run python3 -c "$LOAD"'
import os
# the live rows that night: next 44% used, reset 20.5h, login 116.7h, ~45pp forecast to strand;
# next4 67% used, reset 25.5h, login 393h. handoff-fire --account auto took next4 18 times of 25.
nx = row(acct="next", weekly_pct=44, weekly_reset_h=20.53, fable_pct=0, fable_reset_h=20.53,
         k=7, login_expires_h=116.7, wk_strand_pp=45.3)
n4 = row(acct="next4", weekly_pct=67, weekly_reset_h=25.53, fable_pct=0, fable_reset_h=25.53,
         k=16, login_expires_h=393.3, wk_strand_pp=11.8)
assert ca.cliff_band(nx) == "soft" and ca._dispatch_cliff_factor(nx) == 1.0
def top(kind):
    out, _ = ca.ranked([n4, nx], cfg, WIN_OPEN, kind)
    return [r["acct"] for _s, r in out][0]
assert top("general") == "next" and top("fable") == "next"
os.environ["CC_ROUTE_DISPATCH_CLIFF_WINDOW"] = "off"
assert top("general") == "next4" and top("fable") == "next4"     # the old pick: the bug reproduces
assert ca._desk_cliff_factor(nx) == 1.0                             # and the desk is not switched
del os.environ["CC_ROUTE_DISPATCH_CLIFF_WINDOW"]
os.environ["CC_ROUTE_DESK_CLIFF_WINDOW"] = "off"
assert top("general") == "next" and ca._desk_cliff_factor(nx) == ca.CLIFF_SOFT_FACTOR
del os.environ["CC_ROUTE_DESK_CLIFF_WINDOW"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "dispatch keeps x0.25 when the week is not stranding or the drain is within DESK_LIFE_H" {
  run python3 -c "$LOAD"'
# the 80h reset falls after the drain point of a 108h login (60h), so reset-first stays out of it
base = row(weekly_reset_h=80.0, login_expires_h=500.0)
g0, f0 = ca.score_general(base, cfg)[0], ca.score_fable(base, cfg, WIN_OPEN)[0]
def demoted(**kw):
    r = row(weekly_reset_h=80.0, **kw)
    return (abs(ca.score_general(r, cfg)[0] - g0 * ca.CLIFF_SOFT_FACTOR) < 1e-12 and
            abs(ca.score_fable(r, cfg, WIN_OPEN)[0] - f0 * ca.CLIFF_SOFT_FACTOR) < 1e-12)
for kw in ({}, {"wk_strand_pp": None}, {"wk_strand_pp": 3.99}):              # not stranding
    assert demoted(login_expires_h=128.0, **kw), kw
assert demoted(login_expires_h=108.0, wk_strand_pp=50.0)                     # drain_in == 60
lifted = row(weekly_reset_h=80.0, login_expires_h=108.01, wk_strand_pp=50.0)
assert ca.score_general(lifted, cfg)[0] == g0 and ca.score_fable(lifted, cfg, WIN_OPEN)[0] == f0
assert ca.score_general(row(weekly_reset_h=5.0, login_expires_h=40.0, wk_strand_pp=50.0), cfg) \
    == (None, ca.CLIFF_DRAIN_REASON)                                          # drain still excludes
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ── reset-first: a stranding week whose reset precedes its drain point (post-mortem 2026-10-18 §4.3)

@test "reset-first: a stranding week resetting before its drain point is lifted in every lane, whatever DESK_LIFE_H says" {
  run python3 -c "$LOAD"'
import os
# login 100h: drain 52h out, INSIDE the 60h desk life, so the DESK_LIFE_H arm alone keeps x0.25
def r(**kw):
    base = dict(login_expires_h=100.0, wk_strand_pp=30.0, weekly_reset_h=20.0)
    base.update(kw); return row(**base)
F = ca.CLIFF_SOFT_FACTOR
lanes = (ca._desk_cliff_factor, ca._dispatch_cliff_factor)
assert all(f(r()) == 1.0 for f in lanes)
assert all(f(r(weekly_reset_h=51.99)) == 1.0 for f in lanes)
assert all(f(r(weekly_reset_h=52.0)) == F for f in lanes)              # reset AT the drain point
for kw in ({"weekly_reset_h": None}, {"weekly_reset_h": 0.0},          # unknown reset: no lift
           {"wk_strand_pp": None}, {"wk_strand_pp": 3.99}):            # not stranding: no lift
    assert all(f(r(**kw)) == F for f in lanes), kw
# the recovery lane scores through score_general, so it carries the same factor
base = row(weekly_reset_h=20.0, login_expires_h=500.0, wk_strand_pp=30.0)
assert ca.score_general(r(), cfg, recovery=True)[0] == ca.score_general(base, cfg, recovery=True)[0]
os.environ["CC_ROUTE_CLIFF_RESET_FIRST"] = "off"
assert all(f(r()) == F for f in lanes)                                 # kill: DESK_LIFE_H only
assert all(f(r(login_expires_h=108.01, weekly_reset_h=200.0)) == 1.0 for f in lanes)
del os.environ["CC_ROUTE_CLIFF_RESET_FIRST"]
os.environ["CC_ROUTE_DISPATCH_CLIFF_WINDOW"] = "off"                   # a lane kill still wins
assert ca._dispatch_cliff_factor(r()) == F and ca._desk_cliff_factor(r()) == 1.0
del os.environ["CC_ROUTE_DISPATCH_CLIFF_WINDOW"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "replay 2026-10-16T04:11:41Z: next leads general and recovery; the pre-lift rule ranked it last, as handoffs.jsonl logged" {
  # Inputs measured at that instant: weekly/session/k off account-utilization.jsonl (04:05:36Z),
  # login off auth-timeseries.jsonl refreshTokenExpiresAt (04:08:20Z), wk_strand_pp recomputed
  # with burn_wk_ewma_ph over the util history. handoffs.jsonl:149 logged
  # "next4 0.000205 > next2 0.000145 > next3 0.000094 > next 0.000046" and fired on next4.
  run python3 -c "$LOAD"'
import os
def rows():
    return [row(acct="next", weekly_pct=30, weekly_reset_h=47.81, session_pct=2, session_reset_h=0.81,
                k=3, fable_pct=0, fable_reset_h=47.81, login_expires_h=144.02, wk_strand_pp=65.05),
            row(acct="next2", weekly_pct=68, weekly_reset_h=30.81, session_pct=19, session_reset_h=4.14,
                k=12, fable_pct=14, fable_reset_h=30.81, login_expires_h=367.36, wk_strand_pp=12.81),
            row(acct="next3", weekly_pct=0, weekly_reset_h=103.81, session_pct=0, session_reset_h=5.0,
                k=0, fable_pct=0, fable_reset_h=103.81, login_expires_h=598.84, wk_strand_pp=100.0),
            row(acct="next4", weekly_pct=44, weekly_reset_h=52.81, session_pct=0, session_reset_h=0.31,
                k=4, fable_pct=0, fable_reset_h=52.81, login_expires_h=420.61, wk_strand_pp=48.13)]
def order(**kw):
    out, _ = ca.ranked(rows(), cfg, WIN_OPEN, "general", **kw)
    return [r["acct"] for _s, r in out]
assert order()[0] == "next", order()
assert order(recovery=True)[0] == "next", order(recovery=True)
os.environ["CC_ROUTE_DISPATCH_CLIFF_WINDOW"] = "off"
assert order()[-1] == "next", order()                    # control: the logged ranking reproduces
del os.environ["CC_ROUTE_DISPATCH_CLIFF_WINDOW"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "replay 2026-10-17T22:54Z: past the DESK_LIFE_H lapse next still leads the desk and general; reset-first off reproduces route.jsonl" {
  # route.jsonl:5158 logged desk -> next4 2.094175, runner-up next 2.044496 at factor 0.25: next
  # had ~38pp to strand and reset in 5.1h, login 101.3h (drain 53.3h, inside the 60h desk life).
  run python3 -c "$LOAD"'
import os
def rows():
    return [row(acct="next", weekly_pct=58, weekly_reset_h=5.1, session_pct=20, session_reset_h=0.1,
                k=13, fable_pct=0, fable_reset_h=5.1, login_expires_h=101.31, wk_strand_pp=38.05),
            row(acct="next2", weekly_pct=0, weekly_reset_h=156.1, session_pct=0, session_reset_h=3.77,
                k=4, fable_pct=0, fable_reset_h=156.1, login_expires_h=324.65, wk_strand_pp=61.47),
            row(acct="next3", weekly_pct=10, weekly_reset_h=61.1, session_pct=1, session_reset_h=2.6,
                k=3, fable_pct=0, fable_reset_h=61.1, login_expires_h=556.14, wk_strand_pp=71.88),
            row(acct="next4", weekly_pct=83, weekly_reset_h=10.1, session_pct=1, session_reset_h=2.6,
                k=11, fable_pct=0, fable_reset_h=10.1, login_expires_h=377.91, wk_strand_pp=7.38)]
def ranking(kind):
    out, _ = ca.ranked(rows(), cfg, WIN_OPEN, kind)
    return [(r["acct"], s) for s, r in out]
assert ranking("interactive")[0][0] == "next" and ranking("general")[0][0] == "next"
os.environ["CC_ROUTE_CLIFF_RESET_FIRST"] = "off"
d = ranking("interactive")
assert [a for a, _s in d][:2] == ["next4", "next"], d
assert abs(d[0][1] - 2.094175) < 1e-3 and abs(d[1][1] - 2.044496) < 1e-3, d
del os.environ["CC_ROUTE_CLIFF_RESET_FIRST"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "_dispatch_first: a soft-band row the reset-first arm lifted may be promoted; a still-demoted one may not" {
  run python3 -c "$LOAD"'
import os
lifted = row(session_pct=0, k_placed=0, login_expires_h=100.0, wk_strand_pp=30.0, weekly_reset_h=20.0)
assert ca.cliff_band(lifted) == "soft"
assert ca._dispatch_first(1.0, lifted, R, []) is True
assert ca._dispatch_first(1.0, dict(lifted, weekly_reset_h=60.0), R, []) is False
assert ca._dispatch_first(1.0, dict(lifted, login_expires_h=40.0), R, []) is False   # drain
os.environ["CC_ROUTE_CLIFF_RESET_FIRST"] = "off"
assert ca._dispatch_first(1.0, lifted, R, []) is False
del os.environ["CC_ROUTE_CLIFF_RESET_FIRST"]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
