#!/usr/bin/env bats
# claude-accounts — router math, CLI contracts, SSOT parsing, and the crash-safety regressions.
#
# Companion to claude-accounts.bats (which covers the last-good quota ledger). That suite was
# the whole of the coverage, so the scoring math, the --route/--rank exit contract, the
# frontier_window parse and every degradation path were unpinned: an audit found 10 surviving
# mutants in the router alone, and the frontier_window parse — whose failure mode is the
# documented JUL7 regression that silently killed all Fable routing — was exercised only on
# its file-missing branch.
#
# Hermetic: scratch SSOT in BATS_TEST_TMPDIR, unreachable endpoints, a config_dir that hashes
# to a nonexistent keychain service. Nothing touches the real ledger, cache, or keychain.
# The router/frontier constants are DERIVED from the repo accounts.json rather than
# hand-copied, so a new constant cannot make the fixture silently disagree with production.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_SSOT="$REPO/accounts.json"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CA_LEDGER="$BATS_TEST_TMPDIR/lastgood.json"
  export CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$CA_LEDGER"
  export YAML="$BATS_TEST_TMPDIR/model-config.yaml"
  # M7 hermeticity: every CLI invocation now READS the utilization series (apply_burn) and the
  # assignment ledger (apply_assignments). The fixture uses real account names, so without these
  # pins a CLI test inherits the REAL fleet's burn rates and phantom fires — test 26's ordering
  # flipped exactly that way. Pin both into the sandbox; module-level cases pass path= explicitly.
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
  export CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
  # W2.6 — `--route interactive` now APPENDS a decision record, so an unpinned suite would write
  # fabricated fleet decisions into the operator's real ~/.claude/route/route.jsonl and they would
  # read there as genuine launches. Same hermeticity rule, and the same failure mode, as the
  # LOG_PATH redirect in $LOAD below. cc-route owns this variable's name; both producers honour it.
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
  # DERIVED from the real SSOT — never hand-copied (a hand-copied block silently diverges
  # the moment a constant is added, and the suite then certifies math production never runs;
  # cache_grace_s was added later and a hand-copied fixture missed it immediately).
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [{"name": "next3", "config_dir": "/tmp/ca-test-nonexistent-xyz",
                "launcher": "claude3",
                "email": "test@example.com", "mailbox": "test@example.com", "dia_profile": "T"}],
}, open(cfg_path, "w"))
PY
}

# Load the module without running the CLI (extensionless + __main__-guarded).
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

# ---- router: exclusion policy ----------------------------------------------------------------

@test "router: _excluded pins every exclusion branch and the EPS_H rollover grace" {
  run python3 -c "$LOAD"'
assert ca._excluded(row(), R) is None
assert ca._excluded(row(session_pct=86, session_reset_h=2.0), R) == "5h-cutoff"
# grace: over the cutoff but the window rolls within EPS_H ⇒ still routable
assert ca._excluded(row(session_pct=86, session_reset_h=0.1), R) is None
# The cap is per-INSTRUMENT (k_cap): `row()` sets `k` and no `k_work`, i.e. the PANE census,
# whose cap is KMAX_RESIDENT. KMAX is the ACTIVE cap and binds the k_work-charged row below.
assert ca._excluded(row(k=ca.k_cap(row(), R)), R) == "kmax-concurrency"
assert ca._excluded(row(k=0, k_work=R["KMAX"]), R) == "kmax-concurrency"
# NEITHER instrument measured (ps failed AND no k_work): refused, but as DATA not policy.
assert ca._excluded(row(k=None), R) == "concurrency-unmeasured"
assert ca._excluded(row(session_pct=None), R) == "no-session-data"
assert ca._excluded(dict(acct="a", error="logged-out"), R) == "logged-out"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "router: missing data is never treated as headroom" {
  run python3 -c "$LOAD"'
assert ca.score_general(row(weekly_pct=None), cfg) == (None, "no-weekly-data")
assert ca.score_fable(row(fable_pct=None), cfg, WIN_OPEN) == (None, "no-fable-limit")
assert ca.score_fable(row(weekly_pct=None), cfg, WIN_OPEN) == (None, "no-weekly-data")
# SSOT unreadable must fail loud — never read as open OR closed
assert ca.score_fable(row(), cfg, {"active": None, "deadline": None})[1] == "window-unknown"
assert ca.score_fable(row(), cfg, {"active": False, "deadline": None})[1] == "window-inactive"
assert ca.score_general(row(weekly_pct=100), cfg)[1] == "weekly-exhausted"
assert ca.score_fable(row(fable_pct=100), cfg, WIN_OPEN)[1] == "fable-exhausted"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

# ---- router: horizon (the urgency denominator) ------------------------------------------------

@test "router: an absent or elapsed reset reads as FAR AWAY, never imminent" {
  run python3 -c "$LOAD"'
live = ca.score_general(row(), cfg)[0]
none_ = ca.score_general(row(weekly_reset_h=None), cfg)[0]
zero  = ca.score_general(row(weekly_reset_h=0.0), cfg)[0]
neg   = ca.score_general(row(weekly_reset_h=-5.0), cfg)[0]
# all three degenerate cases collapse to the same LOW-urgency score...
assert none_ == zero == neg, (none_, zero, neg)
# ...and must never beat a row with a real, measured 24h horizon.
assert none_ < live, (none_, live)
# still ROUTABLE — excluding them would answer "none" right after a weekly reset,
# when every account is at 0% with a null resets_at, i.e. maximally available.
assert none_ > 0
# EPS_H remains the guard for a genuinely imminent MEASURED reset
assert ca.horizon(0.05, R) == R["EPS_H"]
assert ca.horizon(24.0, R) == 24.0 - R["MARGIN_H"]
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "router: ranked() orders strictly by score and reports every non-scoring row" {
  run python3 -c "$LOAD"'
rows = [row(acct="lo", weekly_pct=90), row(acct="hi", weekly_pct=10),
        row(acct="mid", weekly_pct=50), row(acct="out", error="logged-out")]
out, reasons = ca.ranked(rows, cfg, WIN_OPEN, "general")
assert [r["acct"] for _, r in out] == ["hi", "mid", "lo"], [r["acct"] for _, r in out]
assert [s for s, _ in out] == sorted([s for s, _ in out], reverse=True)
assert reasons == {"out": "logged-out"}, reasons
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "router: data-vs-policy classification drives the exit code, and no-fable-limit stays POLICY" {
  run python3 -c "$LOAD"'
assert ca.reason_class({"acct": "a"}, "no-weekly-data") == "data"
assert ca.reason_class({"acct": "a"}, "no-session-data") == "data"
assert ca.reason_class({"acct": "a"}, "window-unknown") == "data"
assert ca.reason_class({"acct": "a", "error": "poll throttled"}, None) == "data"
assert ca.reason_class({"acct": "a"}, "weekly-exhausted") == "policy"
assert ca.reason_class({"acct": "a"}, "5h-cutoff") == "policy"
# entitlement, not a gap in our knowledge — misclassifying it makes cc-route hard-refuse
# instead of taking its designed Opus down-tier.
assert ca.reason_class({"acct": "a"}, "no-fable-limit") == "policy"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

# ---- frontier window: the JUL7 regression class ------------------------------------------------

@test "frontier_window: parses active/end, honours end_date_inclusive, and never guesses" {
  run python3 -c "$LOAD"'
import datetime
def parse(text, inclusive=True):
    open(os.environ["YAML"], "w").write(text)
    c = dict(cfg); c["frontier"] = dict(cfg["frontier"], end_date_inclusive=inclusive)
    return ca.frontier_window(c)

w = parse("frontier_access:\n  active: true\n  end: \"2026-07-31\"\n")
assert w["active"] is True and w["end"] == "2026-07-31"
assert w["deadline"] == datetime.datetime(2026, 8, 1, tzinfo=datetime.timezone.utc), w["deadline"]
w = parse("frontier_access:\n  active: true\n  end: \"2026-07-31\"\n", inclusive=False)
assert w["deadline"] == datetime.datetime(2026, 7, 31, tzinfo=datetime.timezone.utc)

assert parse("frontier_access:\n  active: false\n")["active"] is False
# a file with no frontier_access block, and a non-boolean active, are both UNKNOWN — the
# caller must treat unknown as un-routable, never as open.
assert parse("other_key: 1\n")["active"] is None
assert parse("frontier_access:\n  active: yes\n")["active"] is None
# comments + blank lines inside the block, and a following top-level key, must not truncate it
assert parse("frontier_access:\n  # note\n  active: true\n\n  end: \"2026-07-31\"\n\nnext_key: 2\n")["end"] == "2026-07-31"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "frontier_window: permanent:true suppresses the sentinel deadline and is score-neutral" {
  run python3 -c "$LOAD"'
open(os.environ["YAML"], "w").write(
    "frontier_access:\n  permanent: true\n  active: true\n  end: \"2099-12-31\"\n")
w = ca.frontier_window(cfg)
assert w["permanent"] is True and w["active"] is True
# no deadline ⇒ no surface can derive a 73-year countdown from the sentinel
assert w["deadline"] is None
# and Fable still scores identically to the sentinel path
s_perm = ca.score_fable(row(), cfg, w)[0]
s_sent = ca.score_fable(row(), cfg, dict(w, permanent=False,
         deadline=__import__("datetime").datetime(2099,12,31,tzinfo=__import__("datetime").timezone.utc)))[0]
assert abs(s_perm - s_sent) < 1e-12, (s_perm, s_sent)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "frontier_window: an unreadable SSOT is UNKNOWN, and UNKNOWN blocks Fable routing" {
  run python3 -c "$LOAD"'
c = dict(cfg); c["model_config_ssot"] = "/nonexistent/nope.yaml"
w = ca.frontier_window(c)
assert w["active"] is None and w["deadline"] is None and w["permanent"] is False
assert ca.score_fable(row(), c, w) == (None, "window-unknown")
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "frontier_window: the REAL model-config.yaml parses to a definite state" {
  # The only test that would have caught the JUL7 class on the live SSOT: a parse regression
  # there silently kills all Fable routing, and every hermetic fixture would still be green.
  [ -f "$HOME/.claude/model-config.yaml" ] || skip "no live model-config.yaml"
  run python3 -c "$LOAD"'
c = dict(cfg); c["model_config_ssot"] = os.path.expanduser("~/.claude/model-config.yaml")
w = ca.frontier_window(c)
assert w["active"] is not None, "live frontier_access did not parse — Fable routing is dead"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

# ---- crash safety ------------------------------------------------------------------------------

@test "read_creds: a valid-JSON non-object keychain payload is an error, not a crash" {
  run python3 -c "$LOAD"'
class P: returncode = 0; stdout = "null"
for payload in ("null", "[1]", "\"s\"", "42"):
    P.stdout = payload
    ca.subprocess.run = lambda *a, **k: P()
    assert ca.read_creds("/x", "t") == (None, "keychain-error"), payload
P.stdout = "{\"claudeAiOauth\": {\"accessToken\": \"t\"}}"
assert ca.read_creds("/x", "t")[1] == "present"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

@test "collect: a keychain item with no OAuth blob degrades to one labelled row, not a traceback" {
  run python3 -c "$LOAD"'
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 0}
ca.read_creds = lambda d, k: (None, "present")     # item present, blob absent/empty
rows = ca.collect(cfg, no_heal=False)
assert rows[0]["auth"] == "no-oauth-blob", rows[0]
assert "error" in rows[0]
assert ca.score_general(rows[0], cfg)[0] is None   # excluded, not routed
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "collect: one account raising does not blank the others" {
  run python3 -c "$LOAD"'
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
c = dict(cfg); c["accounts"] = [dict(cfg["accounts"][0], name="bad", config_dir="/bad"),
                                dict(cfg["accounts"][0], name="good", config_dir="/good")]
ca.concurrency = lambda _: {"bad": 0, "good": 0}
def creds(d, k):
    if d == "/bad": raise RuntimeError("simulated keychain explosion")
    return ({"accessToken": "t", "expiresAt": 9e12}, "present")
ca.read_creds = creds
ca.fetch_usage = lambda *a, **k: (200, {"limits": [
    {"kind": "weekly_all", "percent": 11, "resets_at": None},
    {"kind": "session", "percent": 5, "resets_at": None}]})
rows = ca.collect(c, no_heal=True)
by = {r["acct"]: r for r in rows}
assert by["bad"]["auth"] == "probe-error" and "error" in by["bad"]
assert by["good"]["auth"] == "ok" and by["good"]["weekly_pct"] == 11
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

@test "cache_read: a valid-JSON non-dict cache degrades to a miss instead of wedging the tool" {
  open_cache() { :; }
  echo 'null' > "$CACHE"
  run python3 -c "$LOAD"'
assert ca.cache_read(cfg) is None
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
  echo '[]' > "$CACHE"
  run python3 -c "$LOAD"'
assert ca.cache_read(cfg) is None
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

# ---- inheritance integrity ---------------------------------------------------------------------

@test "inherit_lastgood: an elapsed bucket is withheld, flagged, and never negative" {
  run python3 -c "$LOAD"'
from datetime import datetime, timezone, timedelta
now = datetime.now(timezone.utc)
past, future = (now - timedelta(hours=9)).isoformat(), (now + timedelta(hours=5)).isoformat()
led = {"a": {"session_pct": 12, "session_reset_at": past, "weekly_pct": 20,
             "weekly_reset_at": past, "fable_pct": 40, "fable_reset_at": future,
             "quota_as_of": "2026-07-19T09:40:00+00:00"}}
r = {"acct": "a", "error": "logged-out"}
assert ca.inherit_lastgood(r, led, None) is True
assert r["weekly_pct"] is None and r["session_pct"] is None   # provably obsolete, not claimed
assert r["fable_pct"] == 40                                    # still in the future ⇒ kept
assert r["rolled_since"] == ["session", "weekly"]
assert r["weekly_reset_h"] is None and r["session_reset_h"] is None   # never negative
assert r["stale_quota"] is True and r["quota_as_of"] == "2026-07-19T09:40:00+00:00"
assert r["error"] == "logged-out"                              # router exclusion intact
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "inherit_lastgood: provenance is carried, not re-stamped, across repeated sweeps" {
  run python3 -c "$LOAD"'
from datetime import datetime, timezone
orig = "2026-07-18T06:00:00+00:00"
now_ts = datetime.now(timezone.utc).timestamp()
# a row that was itself inherited in the previous sweep keeps its ORIGINAL stamp
r = {"acct": "a", "error": "poll throttled"}
prev = {"ts": now_ts, "rows": {"a": {"weekly_pct": 22, "session_pct": 5, "fable_pct": 10,
                                     "quota_as_of": orig, "stale_quota": True}}}
ca.inherit_lastgood(r, {}, prev)
assert r["quota_as_of"] == orig, r["quota_as_of"]
# a row that was genuinely LIVE in that snapshot is dated by the snapshot itself
r2 = {"acct": "a", "error": "poll throttled"}
ca.inherit_lastgood(r2, {}, {"ts": now_ts, "rows": {"a": {"weekly_pct": 22}}})
assert r2["quota_as_of"].startswith(datetime.fromtimestamp(now_ts, timezone.utc).isoformat()[:16])
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

# ---- rendering ---------------------------------------------------------------------------------

@test "fmt_h: an elapsed countdown renders width-safely, never as negative minutes" {
  run python3 -c "$LOAD"'
assert ca.fmt_h(-41.0) == "now" and ca.fmt_h(-0.5) == "now"
assert ca.fmt_h(None) == "?" and ca.fmt_h(0.0) == "0m"
assert ca.fmt_h(0.5) == "30m" and ca.fmt_h(2.0) == "2.0h" and ca.fmt_h(96.0) == "4d"
# the MID-ROW 5h cell is fixed-width; an overflow there skews every column to its right.
# narrow=True is that contract, and it must hold for ANY input, not just realistic ones.
for h in (-41.0, None, 0.0, 0.5, 2.0, 96.0, 2399.0, 1e5):
    assert len("↻" + ca.fmt_h(h, narrow=True)) <= 5, (h, ca.fmt_h(h, narrow=True))
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

@test "fmt_h: anything past a day reads as days+hours, never a decimal day or 50+ hours" {
  run python3 -c "$LOAD"'
# Operator feedback 2026-07-30: "54.4h" / "2.3d" make the reader finish the arithmetic.
assert ca.fmt_h(54.4)  == "2d 6h",  ca.fmt_h(54.4)
assert ca.fmt_h(110.4) == "4d 14h", ca.fmt_h(110.4)
assert ca.fmt_h(605.8) == "25d 5h", ca.fmt_h(605.8)
assert ca.fmt_h(25.0)  == "1d 1h",  ca.fmt_h(25.0)     # just over the boundary
assert ca.fmt_h(96.0)  == "4d",     ca.fmt_h(96.0)     # exact multiple: no noise remainder
assert ca.fmt_h(23.9)  == "23.9h",  ca.fmt_h(23.9)     # still sub-day: hours
assert ca.fmt_h(2399.0).startswith("99d") and ca.fmt_h(2400.0) == "99d+"
# NO surviving decimal-day form anywhere past the boundary — the shape being retired.
import re
for h in (24.0, 25.0, 47.9, 54.4, 96.0, 110.4, 605.8, 2399.0):
    assert not re.fullmatch(r"[0-9]+\.[0-9]+d", ca.fmt_h(h)), (h, ca.fmt_h(h))
# narrow collapses to whole days — same value, width-safe, still parseable downstream
assert ca.fmt_h(54.4, narrow=True) == "2d"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

@test "fmt_h output round-trips through cc-relogin-poll hours_secs (producer/parser contract)" {
  # fmt_h is not just display: cc-relogin-poll reads it back out of the --login-status TSV to
  # derive a deadline. A shape the parser cannot read yields "" and an EXPIRING row with no ISO
  # stamp is dropped — silently, on exactly the accounts the poller exists to catch.
  local poll="${BATS_TEST_DIRNAME}/../bin/cc-relogin-poll"
  [ -f "$poll" ] || skip "cc-relogin-poll not present"
  # source only the helper, without running the poller body
  hours_secs() { sed -n "/^hours_secs()/,/^}/p" "$poll" > "$BATS_TEST_TMPDIR/hs.sh"; }
  hours_secs
  run bash -c ". '$BATS_TEST_TMPDIR/hs.sh'
    for v in '2d 6h' '4d 14h' '25d 5h' '4d' '23.9h' '30m' 'now'; do
      s=\"\$(hours_secs \"\$v\")\"
      [ -n \"\$s\" ] || { echo \"UNPARSED: \$v\"; exit 1; }
      echo \"\$v=\$s\"
    done
    # the exact values the table now emits must convert to the right magnitude, not 24x under
    [ \"\$(hours_secs '2d 6h')\" = 194400 ] || { echo BAD_2d6h; exit 1; }
    [ \"\$(hours_secs '4d 14h')\" = 396000 ] || { echo BAD_4d14h; exit 1; }
    [ \"\$(hours_secs '4d')\" = 345600 ] || { echo BAD_4d; exit 1; }
    # a display BOUND still refuses, rather than inventing a deadline
    [ -z \"\$(hours_secs '99d+')\" ] || { echo BAD_bound; exit 1; }
    echo OK"
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "render_table: the routed row is marked IN the table, not only in the footer" {
  # MOVED (W2.1): the assertions are unchanged in kind — exactly ONE ➤, on the row a footer line
  # names, with both rows keeping equal length — but the lane the ➤ answers for is now the DESK,
  # not general. On this fixture the two lanes agree, so this case pins the marker's EXISTENCE and
  # its alignment; the lane it points at is discriminated by the case below, on rows where the two
  # lanes disagree.
  run python3 -c "$LOAD"'
import io, contextlib, re
# two healthy rows; "win" has the headroom, so the router must pick it
rows = [{"acct": "loser", "auth": "ok", "k": 0, "session_pct": 5, "weekly_pct": 95,
         "fable_pct": 90, "email": "l@x.com", "dia_profile": "L", "launcher": "claude-loser",
         "weekly_reset_h": 40.0, "fable_reset_h": 40.0, "session_reset_h": 2.0},
        {"acct": "win", "auth": "ok", "k": 0, "session_pct": 2, "weekly_pct": 10,
         "fable_pct": 5, "email": "w@x.com", "dia_profile": "W", "launcher": "claude-win",
         "weekly_reset_h": 40.0, "fable_reset_h": 40.0, "session_reset_h": 2.0}]
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ca.render_table(rows, cfg, {"active": True, "end": "2099-12-31", "deadline": None,
                                "permanent": True}, False, None)
out = buf.getvalue()
plain = re.sub(r"\x1b\[[0-9;]*m", "", out)
tbl = [ln for ln in plain.splitlines() if re.match(r"^\s{2}(win|loser)\b", ln)]
assert len(tbl) == 2, tbl
picked = [ln for ln in tbl if "➤" in ln]
# exactly ONE row marked, and it is the row the footer route lines also name
assert len(picked) == 1, picked
assert picked[0].lstrip().startswith("win"), picked
assert "➤ desk    → win" in plain, plain
assert "➤ general → win" in plain, plain
# the marker must not cost the row its column alignment
assert len(tbl[0]) == len(tbl[1]), [len(x) for x in tbl]
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "render_table: the ➤ answers the DESK lane, on rows where desk and general disagree" {
  # THE DISCRIMINATING CASE (W2.1). The marker pointed at the GENERAL pick from 2026-07-30 until
  # this commit — not by decision, but because the desk lane did not exist for another 11 days and
  # the machine lane was the only answer available. The lanes are different objectives over the
  # same eligibility and they diverge on ordinary fleets: "roomy" has almost its whole week left
  # (general is headroom/T**2, so it wants that) but its 5h window sits at 70%, past the desk floor
  # — the exact pathology the two-key rule exists to keep an operator out of. "sooner" is 5h-safe
  # with 20% of its week left, so the desk takes it by a whole rung of the ladder.
  # A ➤ on "roomy" is the bug this case exists to catch, so the fixture asserts BOTH picks.
  run python3 -c "$LOAD"'
import io, contextlib, re
def rw(acct, wk, wrh, sp):
    return {"acct": acct, "auth": "ok", "k": 0, "k_work": 0, "session_pct": sp, "weekly_pct": wk,
            "fable_pct": 10, "email": acct + "@x.com", "dia_profile": acct.upper(),
            "launcher": "claude-" + acct, "weekly_reset_h": wrh, "fable_reset_h": 40.0,
            "session_reset_h": 3.0, "credits_on": False}
rows = [rw("roomy", 5, 20.0, 70), rw("sooner", 80, 20.0, 5)]
WIN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
# the lanes must genuinely disagree, or the assertion below is satisfied by a marker that never
# moved — the control that makes this case a discriminator rather than a restatement
g, _ = ca.ranked(rows, cfg, WIN, "general")
i, _ = ca.ranked(rows, cfg, WIN, "interactive")
gp, ip = g[0][1]["acct"], i[0][1]["acct"]
assert gp == "roomy" and ip == "sooner", (gp, ip)
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ca.render_table(rows, cfg, WIN, False, None)
plain = re.sub(r"\x1b\[[0-9;]*m", "", buf.getvalue())
tbl = [ln for ln in plain.splitlines() if re.match(r"^\s{2}(roomy|sooner)\b", ln)]
assert len(tbl) == 2, tbl
picked = [ln for ln in tbl if "➤" in ln]
assert len(picked) == 1, picked
assert picked[0].lstrip().startswith("sooner"), picked        # the DESK pick, not general s
assert len(tbl[0]) == len(tbl[1]), [len(x) for x in tbl]      # alignment survives either way
# ...and the footer names the desk FIRST, in the desk lane s own terms, with general still stated
lines = [ln.strip() for ln in plain.splitlines() if "→" in ln and "➤" in ln]
assert lines[0].startswith("➤ desk"), lines
assert "sooner" in lines[0] and "safe set" in lines[0], lines
assert any(ln.startswith("➤ general") and "roomy" in ln for ln in lines), lines
# every footer line stays inside the 82-col budget the table is built to (render_table W = 82)
assert all(len(ln) + 2 <= 82 for ln in lines), [(len(ln), ln) for ln in lines]
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "render_table: a desk-only pick with a dying login is warned about, not silently launched" {
  # W2.4 — the cliff-warning loop iterated (rank_g, rank_f) only, so a winner that ONLY the desk
  # lane names carried an expiring login with no warning anywhere: the per-row alert block fires on
  # the row, but the sentence that says "the account you are about to launch onto is the one whose
  # credentials die" lives here. And this is the lane it matters most for — the desk NEVER yields
  # the cliff term (ranked()), so its winner is the one most likely to be lane-specific.
  run python3 -c "$LOAD"'
import io, contextlib, datetime as dt, re
# SEEDED RELATIVE TO NOW, never an absolute stamp: the subject re-derives the remaining time from
# this field, so a hardcoded date silently changes meaning as the clock advances and the suite
# reds on a calendar boundary with no code change (the land gate walltime ratchet).
EXP = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(hours=60)).isoformat()
def rw(acct, wk, wrh, sp, fp, **kw):
    d = {"acct": acct, "auth": "ok", "k": 0, "k_work": 0, "session_pct": sp, "weekly_pct": wk,
         "fable_pct": fp, "email": acct + "@x.com", "dia_profile": acct.upper(),
         "launcher": "claude-" + acct, "weekly_reset_h": wrh, "fable_reset_h": 40.0,
         "session_reset_h": 3.0, "credits_on": False}
    d.update(kw); return d
# "sooner" wins the DESK lane ONLY — general prefers the roomier week, and an exhausted Fable
# bucket keeps the fable lane off it too — and its login expires inside the warn band (72h) but
# OUTSIDE the cliff drain band (48h), i.e. the account is still fully routable. That gap is the
# whole point: a drained account is excluded and needs no warning; a soft-band one is picked.
rows = [rw("roomy", 5, 20.0, 70, 10),
        rw("sooner", 80, 20.0, 5, 99, login_expires_h=60.0, login_expires_at=EXP)]
WIN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
g, _ = ca.ranked(rows, cfg, WIN, "general")
f, _ = ca.ranked(rows, cfg, WIN, "fable")
i, _ = ca.ranked(rows, cfg, WIN, "interactive")
# the CONTROL: only the desk lane names it, so a warning that fires is the desk lane s doing
assert g[0][1]["acct"] == "roomy" and f[0][1]["acct"] == "roomy", (g[0][1], f[0][1])
assert i[0][1]["acct"] == "sooner", i[0][1]
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ca.render_table(rows, cfg, WIN, False, None)
plain = re.sub(r"\x1b\[[0-9;]*m", "", buf.getvalue())
warn = [ln for ln in plain.splitlines() if "is the pick" in ln]
assert len(warn) == 1, plain
assert "sooner" in warn[0], warn
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "render_table: a /login instruction always names the mailbox it authenticates" {
  run python3 -c "$LOAD"'
import io, contextlib, re
# An account NUMBER is not an identity: the operator authenticates a MAILBOX, and pointing a
# /login at the wrong one silently pairs a credential with the wrong profile while the account
# you meant keeps expiring (operator directive 2026-07-30).
rows = [{"acct": "next", "auth": "ok", "k": 0, "session_pct": 2, "weekly_pct": 10,
         "fable_pct": 5, "email": "ichris96+claude@hotmail.com", "dia_profile": "Personaly",
         "launcher": "claude", "weekly_reset_h": 40.0, "fable_reset_h": 40.0,
         "session_reset_h": 2.0, "login_expires_h": 12.0,
         "login_expires_at": "2026-07-31T02:00:00+00:00"}]
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ca.render_table(rows, cfg, {"active": True, "end": "2099-12-31", "deadline": None,
                                "permanent": True}, False, None)
plain = re.sub(r"\x1b\[[0-9;]*m", "", buf.getvalue())
cliff = [ln for ln in plain.splitlines() if "login expires" in ln]
assert cliff, plain
# the identity travels ON the same line as the instruction, never a lookup away from it
assert "claude → /login" in cliff[0], cliff
assert "ichris96+claude@hotmail.com" in cliff[0], cliff
assert "Personaly" in cliff[0], cliff
# and when that same account is the pick, the route warning names the mailbox too
warn = [ln for ln in plain.splitlines() if "is the pick" in ln]
assert warn and "ichris96+claude@hotmail.com" in warn[0], warn
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "render_table: a stale row is glyph-marked and declared, never shown as live" {
  run python3 -c "$LOAD"'
import io, contextlib
rows = [{"acct": "a", "auth": "ok", "k": 1, "session_pct": 9, "weekly_pct": 3, "fable_pct": 0,
         "stale_quota": True, "poll_throttled": True, "error": "poll throttled ↻ (cached usage)",
         "quota_as_of": "2026-07-19T09:40:00+00:00", "rolled_since": ["session"]}]
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ca.render_table(rows, cfg, {"active": True, "end": "2099-12-31", "deadline": None,
                                "permanent": True}, False, None)
out = buf.getvalue()
assert "LAST-KNOWN" in out, out
assert "excluded from routing" in out
assert "RESET since" in out            # the rolled_since derived fact
assert "↻" in out
assert "26826" not in out              # no sentinel-derived countdown
assert "Fable permanent" in out
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "mark_self: resolves from the reader env on a cache HIT, never from the cached sweep" {
  run python3 -c "$LOAD"'
c = dict(cfg); c["accounts"] = [
    {"name": "next", "config_dir": os.path.expanduser("~/.claude-next")},
    {"name": "next2", "config_dir": os.path.expanduser("~/.claude-secondary")}]
rows = [{"acct": "next"}, {"acct": "next2"}]
os.environ["CLAUDE_CONFIG_DIR"] = os.path.expanduser("~/.claude-secondary")
ca.mark_self(rows, c)
assert [r["is_self"] for r in rows] == [False, True]
# same row objects, different reader ⇒ the answer must move
os.environ["CLAUDE_CONFIG_DIR"] = os.path.expanduser("~/.claude-next")
ca.mark_self(rows, c)
assert [r["is_self"] for r in rows] == [True, False]
# bare ~/.claude mirrors the next account
os.environ.pop("CLAUDE_CONFIG_DIR")
ca.mark_self(rows, c)
assert [r["is_self"] for r in rows] == [True, False]
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

# ---- CLI contracts (e2e against the real binary) -----------------------------------------------

@test "--route/--rank: the kind argument is validated, never silently defaulted" {
  for bad in fabel FABLE general_ ""; do
    run python3 "$CA_BIN" --route "$bad" --no-heal
    [ "$status" -eq 1 ]
    [[ "$output" == *"requires general|fable"* ]] || false
  done
  run python3 "$CA_BIN" --route --no-heal          # value missing entirely
  [ "$status" -eq 1 ]
  run python3 "$CA_BIN" --route general --rank general --no-heal
  [ "$status" -eq 1 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "--route: an all-errored fleet exits 3 (data unavailable) with 'none' on stdout" {
  run bash -c "python3 '$CA_BIN' --route general --fresh --no-heal 2>/dev/null"
  [ "$status" -eq 3 ]
  [ "${lines[0]}" = "none" ]
  run bash -c "python3 '$CA_BIN' --route general --fresh --no-heal 2>&1 >/dev/null"
  [[ "$output" == *"no routable account for general"* ]]
}

@test "--route: a policy-excluded fleet exits 2, distinct from the data-unavailable 3" {
  # seed the cache with a healthy-but-exhausted row: data was fine, policy refuses.
  python3 - <<'PY'
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
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None,
           "rows": [{"acct": "next3", "auth": "ok", "k": 0, "session_pct": 10,
                     "session_reset_h": 3.0, "weekly_pct": 100, "weekly_reset_h": 20.0,
                     "fable_pct": 100, "fable_reset_h": 20.0, "credits_on": False}]},
          open(os.environ["CACHE"], "w"))
PY
  run bash -c "python3 '$CA_BIN' --route general 2>/dev/null"
  [ "$status" -eq 2 ]
  [ "${lines[0]}" = "none" ]
  run bash -c "python3 '$CA_BIN' --route general 2>&1 >/dev/null"
  [[ "$output" == *"weekly-exhausted"* ]]
}

@test "--route/--rank: stdout contract holds and excluded accounts are named on stderr" {
  python3 - <<'PY'
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
def r(n, wk, **kw):
    d = {"acct": n, "auth": "ok", "k": 0, "session_pct": 10, "session_reset_h": 3.0,
         "weekly_pct": wk, "weekly_reset_h": 24.0, "fable_pct": 10, "fable_reset_h": 24.0,
         "credits_on": False}
    d.update(kw); return d
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None,
           "rows": [r("next3", 10), r("lo", 80), r("gone", 5, error="poll throttled ↻")]},
          open(os.environ["CACHE"], "w"))
PY
  # stdout ONLY: bats merges stderr into $output, and the excluded-accounts line now
  # rides stderr, so the stdout contract must be asserted with stderr discarded.
  run bash -c "python3 '$CA_BIN' --route general 2>/dev/null"
  [ "$status" -eq 0 ]
  # exactly the bare account name on stdout — handoff-fire consumes this verbatim
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "next3" ]
  run bash -c "python3 '$CA_BIN' --route general 2>&1 >/dev/null"
  [[ "$output" == *"excluded"* && "$output" == *"gone"* ]] || false

  run bash -c "python3 '$CA_BIN' --rank general 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]                       # the throttled row is absent from the ranking
  [[ "${lines[0]}" =~ ^[a-z0-9]+\ [0-9]+\.[0-9]{6}$ ]] || false
  [[ "${lines[0]}" == next3* ]] || false
  first=$(echo "${lines[0]}" | cut -d' ' -f2); second=$(echo "${lines[1]}" | cut -d' ' -f2)
  run python3 -c "import sys; sys.exit(0 if float('$first') >= float('$second') else 1)"
  [ "$status" -eq 0 ]
}

@test "--json: emits the contract fields the /accounts readout is required to render" {
  run bash -c "python3 '$CA_BIN' --json --fresh --no-heal"
  [ "$status" -eq 0 ]
  run python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert 's_cut' in d and 'window' in d and 'cached' in d
assert 'permanent' in d['window']
r = d['rows'][0]
for f in ('acct', 'auth', 'k', 'is_self', 'route_reasons', 'route_reason_class',
          'score_interactive', 'desk_tier'):
    assert f in r, f
# W2.3 — the DESK lane rides the machine surface too. A lane emitted by no machine surface is a
# lane no consumer can check, which is how a measured-false routing premise survived a day.
for m in ('route_reasons', 'route_reason_class'):
    assert set(r[m]) == {'general', 'fable', 'interactive'}, (m, r[m])
print('OK')" <<< "$output"
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

@test "--relogin-info: rejects a missing value and an unknown account" {
  run python3 "$CA_BIN" --relogin-info
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires an account name"* ]] || false
  run python3 "$CA_BIN" --relogin-info nosuch
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown account"* ]] || false
  run python3 "$CA_BIN" --relogin-info next3
  [ "$status" -eq 0 ]
  [[ "$output" == *keychain_service* ]]
}

# ---- single-flight lock ------------------------------------------------------------------------

@test "lock: a caller degrades to the grace cache instead of blocking behind a long sweep" {
  # A holder process owns the lock for far longer than the wait budget, standing in for a
  # real mid-sweep caller (4 accounts x keychain + a 90s heal + retry ladders = minutes).
  export HOLDER="$BATS_TEST_TMPDIR/holder.py"
  cat > "$HOLDER" <<'PY'
import fcntl, sys, time
f = open(sys.argv[1], "w")
fcntl.flock(f, fcntl.LOCK_EX)
sys.stdout.write("held\n"); sys.stdout.flush()
time.sleep(30)
PY
  run python3 -c "$LOAD"'
import time, subprocess, sys
lock_path = cfg["cache_file"] + ".lock"
# a cache that is EXPIRED for a normal read but still inside the grace window
json.dump({"ts": time.time() - (cfg["cache_ttl_s"] + 60), "cfg_key": ca._cfg_key(cfg),
           "no_heal": True, "prev": None,
           "window": {"active": True, "end": "x", "deadline": None, "permanent": True},
           "rows": [{"acct": "next3", "auth": "ok", "k": 0, "weekly_pct": 7}]},
          open(cfg["cache_file"], "w"))
assert ca.cache_read(cfg, want_heal=False) is None
assert ca.cache_read(cfg, want_heal=False, grace_s=cfg["cache_grace_s"]) is not None

holder = subprocess.Popen([sys.executable, os.environ["HOLDER"], lock_path],
                          stdout=subprocess.PIPE, text=True)
assert holder.stdout.readline().strip() == "held"
try:
    t0 = time.time()
    rows, win, cached, prev = ca.get_data(cfg, fresh=False, no_heal=True)
    waited = time.time() - t0
    # served the grace cache rather than waiting out the 30s hold
    assert cached is True, cached
    assert rows[0]["weekly_pct"] == 7, rows
    assert waited < cfg["lock_wait_s"] + 3, waited
    # --fresh must REFUSE to degrade (handoff-fire relies on it forcing a real heal), so
    # its acquire blocks. Assert the contract directly — calling get_data(fresh=True)
    # here would hang for the full hold.
    f = open(lock_path, "w")
    assert ca._acquire_lock(f, cfg, allow_degrade=True) is False
finally:
    holder.kill()
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "--json envelope: .rows[] is the accessor the consumer docs use" {
  # commands/limit-recover.md documented `.[] | select(.acct==…)`, which iterates the
  # top-level VALUES and dies on the `cached` boolean. Pin the envelope so a reshape breaks
  # loudly here instead of silently in a runbook the operator runs mid-incident.
  command -v jq >/dev/null || skip "jq not installed"
  run bash -c "python3 '$CA_BIN' --json --fresh --no-heal | jq -e '.rows[] | select(.acct==\"next3\") | .acct'"
  [ "$status" -eq 0 ]
  [[ "$output" == *next3* ]]
}

@test "load_cfg: a bad router constant fails with a message, never a traceback" {
  # The constants are documented as operator-tunable and are consumed unguarded: _soft
  # divides by (S_CUT - S_SOFT), so S_SOFT == S_CUT is a ZeroDivisionError inside every
  # consumer of this tool at once.
  python3 - "$CA_CFG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); c["router"]["S_SOFT"] = c["router"]["S_CUT"]
json.dump(c, open(sys.argv[1], "w"))
PY
  run python3 "$CA_BIN" --route general --no-heal
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid router constants"* ]] || false
  [[ "$output" != *Traceback* ]] || false

  python3 - "$CA_CFG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); c["router"].pop("EPS_H")
json.dump(c, open(sys.argv[1], "w"))
PY
  run python3 "$CA_BIN" --json --no-heal
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing or non-numeric"* ]] || false
  [[ "$output" == *EPS_H* ]]
}

@test "ledger: a scratch SSOT never reads or writes the real last-good ledger" {
  # CLAUDE_ACCOUNTS_LASTGOOD is an independent variable that CLAUDE_ACCOUNTS_JSON does not
  # imply, so overriding only the config used to fall through to the production ledger.
  run bash -c "unset CLAUDE_ACCOUNTS_LASTGOOD; CLAUDE_ACCOUNTS_JSON='$CA_CFG' python3 -c '
import importlib.machinery, importlib.util, os
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    \"ca\", importlib.machinery.SourceFileLoader(\"ca\", os.environ[\"CA_BIN\"])))
importlib.machinery.SourceFileLoader(\"ca\", os.environ[\"CA_BIN\"]).exec_module(ca)
real = os.path.join(os.path.expanduser(\"~\"), \".claude/logs/claude-accounts-lastgood.json\")
assert ca.LASTGOOD_PATH != real, ca.LASTGOOD_PATH
print(\"OK\")'"
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false

  # ...while the DEFAULT SSOT keeps the canonical path, so the accumulated ledger is never orphaned
  run bash -c "unset CLAUDE_ACCOUNTS_LASTGOOD CLAUDE_ACCOUNTS_JSON; python3 -c '
import importlib.machinery, importlib.util, os
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    \"ca\", importlib.machinery.SourceFileLoader(\"ca\", os.environ[\"CA_BIN\"])))
importlib.machinery.SourceFileLoader(\"ca\", os.environ[\"CA_BIN\"]).exec_module(ca)
assert ca.LASTGOOD_PATH.endswith(\"/claude-accounts-lastgood.json\"), ca.LASTGOOD_PATH
print(\"OK\")'"
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "collect: the 401 rotation retry re-reads the keychain once and recovers" {
  run python3 -c "$LOAD"'
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 1}
reads = {"n": 0}
def creds(d, k):
    reads["n"] += 1
    return ({"accessToken": "tok%d" % reads["n"], "expiresAt": 9e12}, "present")
ca.read_creds = creds
seen = []
def fetch(cfg_, token, retries=2):
    seen.append(token)
    # CC rotated the token between our keychain read and the call: first 401, then OK
    if len(seen) == 1: return 401, {}
    return 200, {"limits": [{"kind": "session", "percent": 3, "resets_at": None},
                            {"kind": "weekly_all", "percent": 9, "resets_at": None}]}
ca.fetch_usage = fetch
rows = ca.collect(cfg, no_heal=True)
assert reads["n"] == 2, reads          # exactly ONE fresh re-read, not a loop
assert seen == ["tok1", "tok2"], seen  # retried with the NEW token
assert rows[0]["weekly_pct"] == 9 and "error" not in rows[0], rows[0]
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

@test "collect: a persistent 401 on a stale token is reported as stale, not as token-invalid" {
  run python3 -c "$LOAD"'
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 2}
# expired token + live sessions ⇒ heal is skipped by design (CC owns the lifecycle)
ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 1000}, "present")
ca.fetch_usage = lambda *a, **k: (401, {})
rows = ca.collect(cfg, no_heal=True)
assert rows[0]["auth"] == "stale", rows[0]
assert "token-invalid" not in rows[0]["error"], rows[0]
assert "--no-heal" in rows[0]["error"], rows[0]
# a VALID (non-stale) token that 401s IS token-invalid — the revoked case
ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 9e12}, "present")
rows = ca.collect(cfg, no_heal=True)
assert rows[0]["auth"] == "token-invalid", rows[0]
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "collect: a 429 is a transient poll-throttle, never a cap, and falls back to last-good" {
  run python3 -c "$LOAD"'
from datetime import datetime, timezone, timedelta
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 0}
ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 9e12}, "present")
future = (datetime.now(timezone.utc) + timedelta(hours=6)).isoformat()
json.dump({"next3": {"session_pct": 4, "session_reset_at": future, "weekly_pct": 41,
                     "weekly_reset_at": future, "fable_pct": 8, "fable_reset_at": future,
                     "quota_as_of": "2026-07-19T09:40:00+00:00"}},
          open(os.environ["CA_LEDGER"], "w"))
ca.fetch_usage = lambda *a, **k: (429, {})
r = ca.collect(cfg, no_heal=True)[0]
assert r["poll_throttled"] is True
assert r["auth"] == "ok"                       # a throttle says nothing about auth
assert r["weekly_pct"] == 41 and r["stale_quota"] is True
assert "cached usage" in r["error"], r["error"]
# and it is NOT reported as a limit: the row is excluded for a DATA reason, not policy
assert ca.reason_class(r, ca.score_general(r, cfg)[1]) == "data"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "bar/cut_marker: the routing cutoff is visible at EVERY usage level, in monochrome" {
  run python3 -c "$LOAD"'
ca.COLOR = False
CUT = R["S_CUT"]
gaps, widths = [], set()
for i in range(0, 1001):
    p = i / 10.0
    rendered = ca.bar(p, cut=CUT) + ca.cut_marker(p, CUT)
    if "┆" not in rendered and "▲" not in rendered:
        gaps.append(p)
    widths.add(len(rendered + ca.pct(p)))
# the tick used to vanish once the fill covered its cell — i.e. across the whole
# 81-100% band, precisely where it decides routing
assert not gaps, gaps[:12]
# fixed-width column: an overflow skews every column to the right of it
assert widths == {15}, widths
# the crossing is an EXACT p >= S_CUT test, not cell arithmetic (a 10-cell track
# cannot resolve 85% by itself)
assert ca.cut_marker(CUT * 100 - 0.1, CUT) != "▲"
assert ca.cut_marker(CUT * 100, CUT) == "▲"
assert ca.cut_marker(100, CUT) == "▲"
# and it degrades cleanly with no data / no cutoff
assert ca.cut_marker(None, CUT) == " " and ca.cut_marker(50, None) == " "
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

@test "keychain_service: the CC 2.1.183 service-name contract, incl. NFC normalisation" {
  # If this derivation drifts, every account resolves to a nonexistent keychain item and the
  # whole fleet reads as logged-out — the highest-blast-radius pure function in the file, and
  # it was structurally uncovered (the fixture only exercises the item-not-found path).
  run python3 -c "$LOAD"'
import hashlib, unicodedata
for d in ("/Users/x/.claude-next", "/Users/x/.claude-secondary", "/tmp/ca-test-nonexistent-xyz"):
    want = "Claude Code-credentials-" + hashlib.sha256(d.encode()).hexdigest()[:8]
    assert ca.keychain_service(d) == want, (d, ca.keychain_service(d), want)
    assert len(ca.keychain_service(d).rsplit("-", 1)[1]) == 8
# NFC normalisation: the same path spelled decomposed must map to the SAME item, or an
# account whose dir carries an accent silently loses its credentials.
nfc = unicodedata.normalize("NFC", "/Users/x/.claude-café")
nfd = unicodedata.normalize("NFD", "/Users/x/.claude-café")
assert nfc != nfd                                   # genuinely different byte sequences
assert ca.keychain_service(nfc) == ca.keychain_service(nfd)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

# ---- the login cliff (refreshTokenExpiresAt) -------------------------------------------------
#
# The refresh token carries its OWN expiry, anchored to the last INTERACTIVE login and not
# extended by a refresh grant. Past it only /login recovers the account. These pin the two
# halves of the 2026-07-24 gap: the deadline was never read at all, and a heal the server had
# REJECTED was reported as benign "stale".

@test "_heal_rejected: classifies on the HTTP status, not on the words invalid/revoked" {
  run python3 -c "$LOAD"'
# the exact string the official binary emitted for next3, 2026-07-24 — no "invalid", no
# "revoked", and the substring hunt it replaced scored it as benign.
assert ca._heal_rejected("Login failed: Request failed with status code 400") is True
assert ca._heal_rejected("Login failed: Request failed with status code 401") is True
assert ca._heal_rejected("invalid_grant") is True
assert ca._heal_rejected("refresh token revoked") is True
# NOT a verdict on the credentials — transport, load, or a heal that never ran. Treating any
# of these as terminal would demand an interactive login the account does not need.
assert ca._heal_rejected("skipped: 2 live session(s) — CC owns the token lifecycle") is False
assert ca._heal_rejected("skipped: no refresh token in keychain") is False
assert ca._heal_rejected("heal timed out") is False
assert ca._heal_rejected("Request failed with status code 500") is False
assert ca._heal_rejected("Request failed with status code 429") is False
assert ca._heal_rejected("") is False
assert ca._heal_rejected(None) is False
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "collect: a REJECTED heal is login-required, never benign stale" {
  run python3 -c "$LOAD"'
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 0}                     # zero sessions ⇒ heal is attempted
ca.read_creds = lambda d, k: ({"accessToken": "t", "refreshToken": "r", "expiresAt": 1000},
                              "present")
ca.heal = lambda *a, **k: (False, "Login failed: Request failed with status code 400")
ca.fetch_usage = lambda *a, **k: (401, {})
r = ca.collect(cfg)[0]
assert r["auth"] == "login-required", r
assert "/login" in r["error"], r                            # names the ONE action that works
assert r["auth_actionable"] is True and r["login_fixable"] is True, r
# a heal that merely did not happen stays stale — the distinction is the whole point.
# The rejection above is now DURABLE, so this second scenario must start from a clean
# ledger: without the reset it short-circuits on the recorded 400 and never reaches the
# timeout branch at all. Two independent scenarios, not a sequence.
for _a in ("next", "next2", "next3", "next4"): ca._clear_rejected(_a)
ca.heal = lambda *a, **k: (False, "heal timed out")
r = ca.collect(cfg)[0]
assert r["auth"] == "stale", r
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

# ---- the rejection record: a dead grant must OUTLIVE the process that discovered it ----------
#
# 2026-08-03, next2: the refresh grant answered 400 for 95 minutes while the calendar cliff read
# 674h away, and `heal` re-attempted it 20 times. `_heal_rejected` had classified it correctly on
# the first try — the verdict just had nowhere to live. It went onto an in-memory row behind a 90s
# cache and died there, so (1) nothing suppressed the retry and (2) `cc-relogin`, which measures
# with --no-heal ON PURPOSE, never ran the code path that produces the verdict and therefore read
# the account as "healthy (auth=stale)" and refused to act. Twice, in the live log.

@test "_rejected_path: never collides with the ledger it is derived from" {
  run python3 -c "$LOAD"'
# The obvious derivation — LASTGOOD_PATH.replace("-lastgood","-rejected") — is a silent no-op
# for any basename without that hyphenated token, and the harness ledger is "lastgood.json".
# Both stores then resolve to ONE file and the rejection ledger overwrites the quota ledger.
for p in ("/t/lastgood.json", "/t/claude-accounts-lastgood.json", "/t/led", "/t/a.b/x.json"):
    ca.LASTGOOD_PATH = p
    assert ca._rejected_path() != p, p
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

@test "rejection record: survives the sweep and is visible to a --no-heal reader" {
  run python3 -c "$LOAD"'
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 0}
ca.read_creds = lambda d, k: ({"accessToken": "t", "refreshToken": "r", "expiresAt": 1000},
                              "present")
ca.fetch_usage = lambda *a, **k: (401, {})
ca.heal = lambda *a, **k: (False, "Login failed: Request failed with status code 400")
ca.collect(cfg)                                   # the sweep that DISCOVERS the dead grant
# A later reader that never heals — this is cc-relogin, cc-relogin-poll and cc-blockers.
tripped = []
ca.heal = lambda *a, **k: (tripped.append(1), (False, "x"))[1]
r = ca.collect(cfg, no_heal=True)[0]
assert not tripped, "a proven-dead grant was re-redeemed on a timer"
assert r["auth"] == "login-required", r            # NOT the benign "stale" that refused recovery
assert r["login_fixable"] is True, r               # ⇒ cc-relogin need_relogin() now acts
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "rejection record: self-clears when the grant is replaced, and does not pin a healthy account" {
  run python3 -c "$LOAD"'
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 0}
ca.fetch_usage = lambda *a, **k: (401, {})
ca.read_creds = lambda d, k: ({"accessToken": "t", "refreshToken": "DEAD", "expiresAt": 1000},
                              "present")
ca.heal = lambda *a, **k: (False, "Login failed: Request failed with status code 400")
ca.collect(cfg)
assert ca._rejected_for("next3", "DEAD"), "the dead grant was not recorded"
# A NEW grant arrives — operator /login, or a live session rotating it. The record is keyed on
# the token fingerprint, so it goes inert on its own. A plain boolean would have pinned a false
# login-required on an account that had already fixed itself (next2 did exactly that, in-session).
assert ca._rejected_for("next3", "FRESH") is None, "the record survived its own credential"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "heal: a reported success that did not move the token is UNPROVEN, never healed" {
  run python3 -c "$LOAD"'
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 0}
ca.fetch_usage = lambda *a, **k: (401, {})
ca.read_creds = lambda d, k: ({"accessToken": "t", "refreshToken": "SAME", "expiresAt": 1000},
                              "present")
# 2.1.220 prints "Login successful." and exits 0 even when the keychain write was lost: its
# persist helper returns {success:false}, the caller discards that verdict, and the auth-login
# path WIPES the stored credential before writing the replacement. Trusting the report would
# clear the rejection record and re-arm the retry loop this whole change exists to stop.
ca.heal = lambda *a, **k: (True, "Login successful.")
r = ca.collect(cfg)[0]
assert r["auth"] != "healed", r
assert "did not change" in (r.get("heal_note") or ""), r
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "concurrency: counts the claude.exe spelling the rotation-safety gate was blind to" {
  run python3 -c "$LOAD"'
ps_out = (
  "/Users/c/.claude-220/node_modules/.bin/claude --model x CLAUDE_CONFIG_DIR=/Users/c/.claude-tertiary\n"
  "/Users/c/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id w@s "
  "CLAUDE_CONFIG_DIR=/Users/c/.claude-tertiary\n"
  "/Users/c/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id v@s "
  "CLAUDE_CONFIG_DIR=/Users/c/.claude-tertiary\n"
  "node /some/mcp/server.js CLAUDE_CONFIG_DIR=/Users/c/.claude-tertiary\n")
import subprocess, collections
ca.subprocess = type("S", (), {
    "run": staticmethod(lambda *a, **k: type("P", (), {"stdout": ps_out})()),
    "TimeoutExpired": subprocess.TimeoutExpired})
ca.HOME = "/Users/c"
cfg2 = {"accounts": [{"name": "next3", "config_dir": "/Users/c/.claude-tertiary"},
                     {"name": "next", "config_dir": "/Users/c/.claude-next"}]}
n = ca.concurrency(cfg2)["next3"]
# 1 symlink-spelled + 2 claude.exe workers. The old matcher scored 1 and the k_live>0 gate is
# what stops a heal redeeming a refresh token alongside live sessions that rotate it.
assert n == 3, n
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

@test "collect: an EXPIRED refresh token skips the futile heal and keeps quota readable" {
  run python3 -c "$LOAD"'
import time
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 0}
tripped = []
ca.heal = lambda *a, **k: (tripped.append(1), (False, "should never run"))[1]
# access token stale AND the refresh token past its own expiry
ca.read_creds = lambda d, k: ({"accessToken": "t", "refreshToken": "r", "expiresAt": 1000,
                               "refreshTokenExpiresAt": (time.time() - 3600) * 1000}, "present")
ca.fetch_usage = lambda *a, **k: (200, {"limits": [
    {"kind": "session", "percent": 12, "resets_at": "2099-01-01T00:00:00Z"},
    {"kind": "weekly_all", "percent": 40, "resets_at": "2099-01-01T00:00:00Z"}]})
r = ca.collect(cfg)[0]
assert not tripped, "heal was attempted past the refresh-token expiry (cannot succeed)"
assert r["auth"] == "login-required", r
assert r["login_expired"] is True, r
# the account needs a login, but its quota is NOT blanked — that is a different claim
assert r["weekly_pct"] == 40, r
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "collect: the login deadline is recorded on HEALTHY rows — lead time is the point" {
  run python3 -c "$LOAD"'
import time
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 0}
ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 9e12,
                               "refreshTokenExpiresAt": (time.time() + 20 * 3600) * 1000},
                              "present")
ca.fetch_usage = lambda *a, **k: (200, {"limits": [
    {"kind": "weekly_all", "percent": 10, "resets_at": "2099-01-01T00:00:00Z"}]})
r = ca.collect(cfg)[0]
assert r["auth"] == "ok" and r["weekly_pct"] == 10, r          # fully healthy RIGHT NOW...
assert r["login_expired"] is False, r
assert 19 < r["login_expires_h"] < 21, r          # ...and 20h from needing an interactive login
assert r["login_expires_at"], r
# a payload with no such stamp (older CC / API-key blob) must not be read as never-expiring
ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 9e12}, "present")
r = ca.collect(cfg)[0]
assert "login_expires_h" not in r and "login_expired" not in r, r
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "auth predicates: the CLI owns them, so a consumer never re-derives the state list" {
  run python3 -c "$LOAD"'
# handoff-fire.sh hand-copied this list and matched 3 of 5. Every ACTIONABLE state must set
# the boolean, and every /login-fixable state must be a subset of it.
assert set(ca.LOGIN_FIXABLE) <= set(ca.ACTIONABLE_AUTH), (ca.LOGIN_FIXABLE, ca.ACTIONABLE_AUTH)
assert "login-required" in ca.ACTIONABLE_AUTH and "login-required" in ca.LOGIN_FIXABLE
# keychain-error and probe-error are NOT credential states — pointing the operator at /login
# would send them at the wrong problem
assert "keychain-error" not in ca.LOGIN_FIXABLE and "probe-error" not in ca.LOGIN_FIXABLE
# every actionable state renders with a glyph (an unmapped state falls back to a gray dot,
# which reads as a healthy row)
for s in ca.ACTIONABLE_AUTH:
    assert s in ca.AUTH_GLYPH, s
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
ca.concurrency = lambda c: {"next3": 0}
ca.read_creds = lambda d, k: (None, "no-keychain-item")
r = ca.collect(cfg)[0]
assert r["auth"] == "logged-out" and r["auth_actionable"] is True and r["login_fixable"] is True
ca.read_creds = lambda d, k: (None, "keychain-error")
r = ca.collect(cfg)[0]
assert r["auth_actionable"] is True and r["login_fixable"] is False, r
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || false
}

@test "_fmt_when: absolute local wall-clock, dated once a bare weekday turns ambiguous" {
  run python3 -c "$LOAD"'
from datetime import datetime, timezone, timedelta
now = datetime.now(timezone.utc)
soon = ca._fmt_when((now + timedelta(hours=20)).isoformat())
assert ":" in soon and len(soon.split()) == 2, soon           # "Sat 12:39"
far = ca._fmt_when((now + timedelta(days=14)).isoformat())
assert len(far.split()) == 3, far                             # "Sat Aug 08" — dated
assert ca._fmt_when(None) == "" and ca._fmt_when("not-a-date") == ""
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

# ---- --readout: the chat surface, as CODE rather than as prose in commands/accounts.md ------

READOUT='
import io, contextlib, re
from datetime import datetime, timedelta, timezone
def at(h):
    return (datetime.now(timezone.utc) + timedelta(hours=h)).isoformat()
def rd(rows, win=None, cached=False):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ca.render_readout(rows, cfg, win or WIN_OPEN, cached)
    return buf.getvalue()
def acctrow(out, name):
    for ln in out.splitlines():
        if ln.startswith("| ") and re.match(r"^\| \**" + name + r"\b", ln):
            return ln
    raise AssertionError((name, out))
'

@test "--readout: marks the routed accounts and the self row, without a second ranking pass" {
  # MOVED (W2.1-2): the mark scheme gained a third lane and the bare ➤ was re-pointed. It now
  # means the DESK pick in BOTH renderers — the readout used to spend it on general while
  # render_table spent it on general too, and re-pointing only one would have left one glyph
  # meaning two different things depending on which surface you were reading. General keeps a
  # mark, as its own superscript. Every assertion below is the same assertion as before, per lane.
  run python3 -c "$LOAD$READOUT"'
rows = [row(acct="poor", weekly_pct=95, fable_pct=95),
        row(acct="rich", weekly_pct=5,  fable_pct=90, is_self=True),
        row(acct="fab",  weekly_pct=40, fable_pct=1)]
out = rd(rows)
i, _ = ca.ranked(rows, cfg, WIN_OPEN, "interactive")
g, _ = ca.ranked(rows, cfg, WIN_OPEN, "general")
f, _ = ca.ranked(rows, cfg, WIN_OPEN, "fable")
ip, gp, fp = i[0][1]["acct"], g[0][1]["acct"], f[0][1]["acct"]
assert gp != fp, (gp, fp)                       # the case a single marker would collapse
assert "➤" in acctrow(out, ip) and f"**{ip}**" in acctrow(out, ip), out
assert "➤ᶠ" in acctrow(out, fp), out
assert "➤ᶠ" not in acctrow(out, gp), out        # general pick is not also flagged as fable
if gp != ip:
    assert "➤ᵍ" in acctrow(out, gp), out        # general keeps a mark — its own, never the desk s
    assert "➤ᵍ" not in acctrow(out, ip), out
assert "← you" in acctrow(out, "rich"), out
# the footer states the SAME answer as the marks — one router, not three opinions — and the DESK
# line comes FIRST, because it is the one that answers what bare `claude` will do
body = [ln for ln in out.splitlines() if ln.startswith("➤")]
assert body[0].startswith("➤ desk") and f"**{ip}**" in body[0], out
assert f"➤ general → **{gp}**" in out and f"➤ fable → **{fp}**" in out, out
print("OK")'
  # TWO statements, not `A && B || C`: an assertion in the LEFT element of an AND-OR list is
  # the [and-absorbed] class the liveness analyzer reports (scripts/bats-assert-liveness.py),
  # and the fixer DECLINES this three-part shape rather than guess. Split, each failure keeps
  # its own diagnostic, and each `[[ ]]` sits in condition position where errexit still binds.
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "--readout: an inherited row is starred and declared, never presented as a reading" {
  run python3 -c "$LOAD$READOUT"'
rows = [row(acct="stale", stale_quota=True, error="poll throttled ↻ (cached usage)",
            poll_throttled=True, quota_as_of="2026-07-19T09:40:00+00:00")]
out = rd(rows)
r = acctrow(out, "stale")
# EVERY percent on the row carries the provenance mark — one unmarked number reads as live
assert len(re.findall(r"\d+%\*", r)) >= 3, r
assert re.search(r"\d+%(?!\*)", r) is None, r
assert "throttle" in out and "NOT a usage cap" in out, out   # transient, never a limit
assert "--fresh" in out, out
# a non-throttled inherited row says the OTHER thing: excluded from routing
out2 = rd([row(acct="old", stale_quota=True, error="no data",
               quota_as_of="2026-07-19T09:40:00+00:00")])
assert "excluded from routing" in out2, out2
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "--readout: a login inside the warn band is loud; login-required shows state, not a date" {
  run python3 -c "$LOAD"'
import io, contextlib, re
from datetime import datetime, timedelta, timezone
def at(h): return (datetime.now(timezone.utc) + timedelta(hours=h)).isoformat()
def rd(rows):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf): ca.render_readout(rows, cfg, WIN_OPEN, False)
    return buf.getvalue()
# a routed row renders as "| **name** ➤" — match past the markers, never startswith
def arow(out, name):
    return [l for l in out.splitlines() if re.match(r"^\| \**" + name + r"\b", l)][0]
warn = float(cfg["login_warn_h"])
out = rd([row(acct="soon", auth="ok", launcher="claude-soon", email="s@x.com",
              dia_profile="S", login_expires_h=warn - 2, login_expires_at=at(warn - 2)),
          row(acct="far", auth="ok", login_expires_h=warn + 500,
              login_expires_at=at(warn + 500)),
          row(acct="dead", auth="login-required", launcher="claude-dead", email="d@x.com",
              dia_profile="D", login_expires_h=400.0, login_expires_at=at(400))])
soon = arow(out, "soon")
assert "⚠" in soon and "**" in soon, soon
far = arow(out, "far")
assert "⚠" not in far, far                     # only the band is marked, not every row
dead = arow(out, "dead")
# a future date beside a REJECTED grant reads as "fine until then" — state instead
assert "⊘ REQUIRED" in dead and "20" not in dead.split("|")[-2], dead
# the cliff bullet carries the identity that makes it safe to act on
cliff = [l for l in out.splitlines() if l.startswith("- ") and "login expires" in l][0]
assert "claude-soon" in cliff and "s@x.com" in cliff and "Dia" in cliff, cliff
# ...and login-required is NOT double-warned: its own auth bullet already says it
assert not [l for l in out.splitlines() if "`dead` login expires" in l], out
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "--readout: the two weekly buckets stay ONE column across a sub-second boundary straddle" {
  run python3 -c "$LOAD"'
import io, contextlib
def rd(rows):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf): ca.render_readout(rows, cfg, WIN_OPEN, False)
    return buf.getvalue()
# the real shape: stamped a fraction of a second apart, straddling a minute boundary.
# Truncating to the minute makes these two DIFFERENT — it printed a bogus divergence
# footnote on 2 of 4 live accounts the first time this ran for real.
straddle = row(acct="s", weekly_reset_at="2026-08-02T03:59:59.800747+00:00",
               fable_reset_at="2026-08-02T04:00:00.010000+00:00")
assert "different minutes" not in rd([straddle]), rd([straddle])
assert ca._same_instant("2026-08-02T03:59:59.800747+00:00", "2026-08-02T04:00:00.010000+00:00")
# a GENUINE split is still footnoted rather than silently merged into one column
real = row(acct="r", weekly_reset_at="2026-08-02T03:59:59+00:00",
           fable_reset_at="2026-08-04T12:00:00+00:00")
assert "different minutes" in rd([real]), rd([real])
assert not ca._same_instant("2026-08-02T03:59:59+00:00", "2026-08-04T12:00:00+00:00")
# unparseable on either side is NOT silently "same" — footnote what you cannot rule out
assert ca._same_instant("garbage", "2026-08-02T03:59:59+00:00") is False
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "--readout: spend is flagged in DOLLARS on spend, not on the toggle, and never in cents" {
  run python3 -c "$LOAD"'
import io, contextlib
def rd(rows):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf): ca.render_readout(rows, cfg, WIN_OPEN, False)
    return buf.getvalue()
# the 2026-07-26 shape: toggle OFF, 17691 CENTS already spent = $176.91 on the Usage panel.
# A toggle-keyed flag hides it; a raw-number flag misreports it 100x.
out = rd([row(acct="spent", credits_on=False, credits_used=17691.0, credits_used_usd=176.91)])
assert "$176.91" in out, out
assert "17691" not in out, out
assert "off" in out.lower(), out                       # toggle state said AFTER the amount
assert not rd([row(acct="none", credits_on=True, credits_used=0.0)]).count("¢"), "flagged on 0 spend"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "--readout: an unsanctioned extra-usage TOGGLE is surfaced before any money moves" {
  # THE LEADING INDICATOR. ¢ keys on spend, so the earliest a ¢ line can fire is after the money
  # is gone. The standing cost guard's ask is that the toggle stay OFF — with it on, hitting a
  # plan limit BILLS instead of stopping the session. render_table has surfaced this all along;
  # this readout said nothing and still routed the desk to that account.
  run python3 -c "$LOAD"'
import io, contextlib, json
def rd(rows, c=None):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf): ca.render_readout(rows, c or cfg, WIN_OPEN, False)
    return buf.getvalue()

# The fixture cfg carries no `spend` block at all, which is the ABSENT-config case — and it must
# read as unauthorized, so a missing standing answer warns rather than goes quiet about money.
on_zero = rd([row(acct="armed", credits_on=True, credits_used=0.0)])
assert "⚠" in on_zero, on_zero
assert "armed" in on_zero, on_zero
assert "ON" in on_zero, on_zero
assert not on_zero.count("¢"), on_zero          # still not a spend claim — no money has moved

# POSITIVE CONTROL x2: the line must be a function of the toggle AND of the standing answer, not
# something that renders for every account. Without these, an always-on line satisfies the above.
off_zero = rd([row(acct="quiet", credits_on=False, credits_used=0.0)])
assert "⚠" not in off_zero, off_zero            # toggle off ⇒ nothing to say

authorized = json.loads(json.dumps(cfg))
authorized["spend"] = {"usage_credits_authorized": True}
sanctioned = rd([row(acct="armed", credits_on=True, credits_used=0.0)], authorized)
assert "⚠" not in sanctioned, sanctioned        # operator said yes ⇒ not a breach
print("OK")'
  # Spelled as an `if` rather than the file's older `A && B || { …; false; }`: the liveness
  # analyzer classes that form and-absorbed, and its fixer DECLINES to rewrite it rather than
  # guess, so the correct shape is the caller's to write.
  if [ "$status" -ne 0 ] || [[ "$output" != *OK* ]]; then
    echo "$output" >&2
    return 1
  fi
}

@test "--readout: a SPENDING account gets the loud spend line and never also the toggle line" {
  # MUTANT-PROVEN, not pre-fix-proven: with no toggle line in the tree at all this passes
  # trivially. Its control is the `elif` demoted to `if`, under which a spending account with the
  # toggle on renders BOTH — the same breach reported twice, at two different severities, which
  # is how an operator learns to skim the quieter one.
  run python3 -c "$LOAD"'
import io, contextlib
def rd(rows):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf): ca.render_readout(rows, cfg, WIN_OPEN, False)
    return buf.getvalue()
out = rd([row(acct="spending", credits_on=True, credits_used=17691.0, credits_used_usd=176.91)])
assert "🚨" in out, out
assert "$176.91" in out, out
if "⚠" in out:
    raise AssertionError("spend line and toggle line both rendered for one account: " + out)
print("OK")'
  if [ "$status" -ne 0 ] || [[ "$output" != *OK* ]]; then
    echo "$output" >&2
    return 1
  fi
}

@test "--readout: a permanent Fable window is never given a countdown, and nulls read as —" {
  run python3 -c "$LOAD"'
import io, contextlib
import re
def rd(rows, win):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf): ca.render_readout(rows, cfg, win, False)
    return buf.getvalue()
def arow(out, name):
    return [l for l in out.splitlines() if re.match(r"^\| \**" + name + r"\b", l)][0]
out = rd([row(acct="a")], WIN_OPEN)
assert "permanent" in out and "2099" not in out, out    # no sentinel-derived time remaining
# a null stamp and an ELAPSED one both read as an em dash: a past absolute reads as a live
# deadline, and a negative relative reads as nonsense
gone = rd([row(acct="b", weekly_reset_at=None, weekly_reset_h=None,
               session_reset_at="2020-01-01T00:00:00+00:00", session_reset_h=-5.0)], WIN_OPEN)
r = arow(gone, "b")
assert r.count("—") >= 2, r
assert "2020" not in r and "-5" not in r, r
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "--login-status: the deadline fields are MACHINE forms, and iso_epoch can read them" {
  # The regression this pins: `when` used to carry _fmt_when's "Sun 13:21" and `hours` fmt_h's
  # "2.9d". iso_epoch("Sun 13:21") is 0, so cc-relogin-poll's preferred ISO branch was dead by
  # construction and its ONLY working deadline source was a regex over a DISPLAY string.
  CLAUDE_ACCOUNTS_JSON="$CA_CFG" run python3 - "$CA_BIN" <<'PY'
import re, subprocess, sys
from datetime import datetime, timedelta, timezone
# RELATIVE to now, deliberately: the countdown is re-derived from this stamp (see
# refresh_login_countdown), and a row outside login_warn_h is skipped entirely — so a
# hardcoded date would drift out of the window and silently stop testing anything.
due = datetime.now(timezone.utc) + timedelta(hours=50)
# microseconds + a +00:00 offset: the real row shape, and the one BSD date rejects
stamp = due.isoformat()
assert "." in stamp and stamp.endswith("+00:00"), stamp
src = open(sys.argv[1]).read().replace(
    'rows, wj, cached, prev = get_data(cfg, fresh, no_heal, max_wait, max_age)',
    'rows = [{"acct": "next3", "auth": "ok", "launcher": "claude3",\n'
    '         "login_expires_h": 50.0, "login_fixable": False,\n'
    '         "login_expires_at": "' + stamp + '"}]\n'
    '    wj, cached, prev = {}, False, None')
assert src != open(sys.argv[1]).read(), "source patch did not apply — the anchor moved"
p = subprocess.run([sys.executable, "-c", src, "--login-status"], capture_output=True, text=True)
f = p.stdout.strip().split("\t")
assert len(f) == 6, f
# normalised: no microseconds, Z not +00:00 — the exact form BSD `date -j -f` accepts
assert f[3] == due.strftime("%Y-%m-%dT%H:%M:%SZ"), (f[3], stamp)
assert re.fullmatch(r"\d+\.\d", f[4]), f[4]          # bare decimal hours, no unit
assert abs(float(f[4]) - 50.0) < 0.2, f[4]
# no RENDERED form survives in either field: no weekday name, no unit suffix
assert not re.search(r"[A-Za-z]", f[4]), f[4]
assert not re.match(r"^[A-Z][a-z]{2} ", f[3]), f[3]
print("OK")
PY
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "--login-status: its ISO stamp round-trips through cc-relogin-poll's iso_epoch" {
  # Cross-program contract: producer emits, the REAL consumer function parses. Asserting the
  # string shape alone would still pass if BSD date happened to reject it.
  local poll="${BATS_TEST_DIRNAME}/../bin/cc-relogin-poll"
  [ -f "$poll" ] || skip "cc-relogin-poll not present"
  sed -n "/^iso_epoch()/,/^}/p" "$poll" > "$BATS_TEST_TMPDIR/ie.sh"
  run bash -c ". '$BATS_TEST_TMPDIR/ie.sh'
    got=\"\$(iso_epoch '2026-08-02T20:21:49Z')\"
    [ \"\$got\" = 1785702109 ] || { echo \"ISO UNPARSED: \$got\"; exit 1; }
    # the shape it USED to be handed must still read as unparseable — that was the whole bug
    [ \"\$(iso_epoch 'Sun 13:21')\" = 0 ] || { echo 'rendered form parsed?!'; exit 1; }
    echo OK"
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "e2e --login-status: the exit code IS the answer, and 0 stays silent" {
  # the fixture account has no keychain item ⇒ logged-out ⇒ /login-fixable ⇒ action required
  run python3 "$CA_BIN" --login-status --fresh --no-heal
  [ "$status" -eq 2 ]
  [[ "${lines[0]}" == next3*REQUIRED* ]] || false
  # the deadline columns stay blank: this verdict is NOT driven by a deadline, and printing a
  # future expiry beside REQUIRED reads as "required, and it expires later"
  [[ "${lines[0]}" == *"—"*"—"* ]] || false
  [[ "${lines[0]}" == *claude3* ]] || false
  # all-clear is silent AND exit 0 — a check that always prints stops being read
  CLAUDE_ACCOUNTS_JSON="$CA_CFG" run python3 - "$CA_BIN" <<'PY'
import importlib.machinery, importlib.util, os, subprocess, sys, time
src = open(sys.argv[1]).read().replace(
    'rows, wj, cached, prev = get_data(cfg, fresh, no_heal, max_wait, max_age)',
    'rows = [{"acct": "next3", "auth": "ok", "launcher": "claude3",\n'
    '         "login_expires_h": 500.0, "login_expires_at": "2099-01-01T00:00:00+00:00",\n'
    '         "login_fixable": False}]\n    wj, cached, prev = {}, False, None')
assert src != open(sys.argv[1]).read(), "source patch did not apply — the anchor moved"
p = subprocess.run([sys.executable, "-c", src, "--login-status"], capture_output=True, text=True)
assert p.returncode == 0, (p.returncode, p.stdout, p.stderr)
assert p.stdout.strip() == "", p.stdout
print("OK")
PY
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "_heal_rejected: 'invalid' must qualify a CREDENTIAL, not any noun in a transport error" {
  run python3 -c "$LOAD"'
# the word appears, but about a RESPONSE — demanding an interactive login here would send the
# operator at a problem that does not exist
assert ca._heal_rejected("Invalid response from server") is False
assert ca._heal_rejected("invalid JSON in reply") is False
assert ca._heal_rejected("Login failed: invalid response, retrying") is False
# ...and it still catches the credential phrasings, in either word order
assert ca._heal_rejected("invalid_grant") is True
assert ca._heal_rejected("Invalid refresh token") is True
assert ca._heal_rejected("the refresh token is invalid") is True
assert ca._heal_rejected("invalid credentials") is True
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "refresh_login_countdown: a cached countdown is re-derived, never replayed" {
  run python3 -c "$LOAD"'
from datetime import datetime, timezone, timedelta
now = datetime.now(timezone.utc)
# what a cache round-trip serves: an absolute stamp (durable) beside an _h frozen at sweep
# time. The grace path serves this up to cache_grace_s old, and _prev_snapshot ignores the TTL.
rows = [{"acct": "a", "login_expires_at": (now + timedelta(hours=2)).isoformat(),
         "login_expires_h": 99.0, "login_expired": False},
        # lapsed DURING the TTL: the stale row still claims a positive countdown, which is the
        # boundary --login-status classifies REQUIRED vs EXPIRING on
        {"acct": "b", "login_expires_at": (now - timedelta(hours=1)).isoformat(),
         "login_expires_h": 5.0, "login_expired": False},
        {"acct": "c"}]                                  # no stamp ⇒ untouched, not invented
ca.refresh_login_countdown(rows)
assert 1.9 < rows[0]["login_expires_h"] < 2.1, rows[0]   # 99.0 discarded
assert rows[0]["login_expired"] is False
assert rows[1]["login_expires_h"] < 0, rows[1]
assert rows[1]["login_expired"] is True, rows[1]
assert "login_expires_h" not in rows[2] and "login_expired" not in rows[2], rows[2]
# the reset countdowns are deliberately NOT touched — they feed the verified router
rows = [{"acct": "a", "weekly_reset_at": (now + timedelta(hours=3)).isoformat(),
         "weekly_reset_h": 77.0}]
ca.refresh_login_countdown(rows)
assert rows[0]["weekly_reset_h"] == 77.0, rows[0]
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "e2e: a CACHED row has its login countdown re-derived, and --login-status re-classifies" {
  # The exact regression: login_expires_h is serialized into the shared cache and, replayed
  # verbatim, a login that lapsed DURING the TTL keeps reporting a positive countdown for the
  # rest of it. Seeded straight into the cache because that is the only hermetic way to reach
  # the real binary's post-cache path — the alternative needs a keychain this fixture cannot
  # own, which is why the first version of this test skipped every row and asserted nothing.
  python3 - "$CA_BIN" "$CA_CFG" <<'SEED'
import importlib.machinery, importlib.util, json, sys, time
from datetime import datetime, timezone, timedelta
loader = importlib.machinery.SourceFileLoader("ca", sys.argv[1])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
cfg = json.load(open(sys.argv[2]))
now = datetime.now(timezone.utc)
rows = [{"acct": "next3", "auth": "ok", "k": 0, "launcher": "claude3",
         "email": "t@e", "dia_profile": "T", "session_pct": 5, "weekly_pct": 10,
         "fable_pct": 5, "auth_actionable": False, "login_fixable": False,
         "login_expires_at": (now - timedelta(hours=1)).isoformat(),   # lapsed an hour ago...
         "login_expires_h": 5.0, "login_expired": False}]              # ...cache still says +5h
ca.cache_write(cfg, {"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "rows": rows,
                     "window": {"active": True, "end": "2099-12-31", "permanent": True,
                                "deadline": None}, "no_heal": False})
SEED
  run python3 "$CA_BIN" --json                     # cache HIT — no --fresh
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json, sys
r = json.load(sys.stdin)["rows"][0]
assert r["login_expires_h"] < 0, r["login_expires_h"]     # the replayed 5.0 was discarded
assert r["login_expired"] is True, r
print("OK")
'
  [ "$status" -eq 0 ]
  # ...and the verdict follows the corrected number: EXPIRING is what the replayed one gives
  run python3 "$CA_BIN" --login-status
  [ "$status" -eq 2 ]
  [[ "$output" == *REQUIRED* ]] || false
  ! [[ "$output" == *EXPIRING* ]]
}

@test "render: a login that lapsed INSIDE the cache TTL still surfaces (auth is still 'ok')" {
  run python3 -c "$LOAD"'
from datetime import datetime, timezone, timedelta
import io, contextlib
now = datetime.now(timezone.utc)
ca.COLOR = False
def render(h):
    r = row(acct="next4", auth="ok", launcher="claude4", email="e", dia_profile="D",
            login_expires_at=(now + timedelta(hours=h)).isoformat(), login_expires_h=h,
            login_expired=h <= 0)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ca.render_table([r], cfg, WIN_OPEN, False)
    return buf.getvalue()
# inside the warn window ⇒ a warning
assert "login expires" in render(20.0), render(20.0)
# LAPSED since the sweep: auth is still "ok" and there is no error, so this row has no other
# signal at all — the guard that required a POSITIVE countdown dropped precisely this case.
out = render(-1.0)
# assert the BULLET specifically, not just the substring: the routing footer below carries
# the same words, so a loose "login EXPIRED" in out passes even with the bullet suppressed —
# it did exactly that on the first attempt at this test.
assert "\u2298 next4 login EXPIRED" in out, out
assert "claude4 \u2192 /login" in out, out
# ...and it reaches the routing footer too: such a row is still fully routable, so it can WIN
assert "is the pick, but its login EXPIRED" in out, out
# comfortably outside the window ⇒ silence (a check that always fires stops being read)
assert "login exp" not in render(500.0).lower(), render(500.0)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

# ---- router M7: utilization-pressure terms (spread + exhaust-by-deadline) ---------------------
# Every fixture here is the FROZEN 2026-08-10 live snapshot that motivated M7: next3 held the
# fleet's soonest-expiring quota (weekly 81%, reset 27.8h) and was excluded on a 28-pane census
# while its 5h window sat at 60%; next2 (weekly 13%, reset 122.8h) won every fire.

@test "router M7: deadline-dominant urgency routes the strand case to the expiring account; γ=1 restores linear" {
  run python3 -c "$LOAD"'
import os
for v in ("CC_ROUTE_URGENCY_EXP", "CC_ROUTE_KWORK", "CC_ROUTE_ASSIGN", "CC_ROUTE_PROJ"):
    os.environ.pop(v, None)
n3 = row(acct="next3", session_pct=60, session_reset_h=4.1, weekly_pct=81,
         weekly_reset_h=27.8, k=28, k_work=2)
n2 = row(acct="next2", session_pct=18, session_reset_h=1.8, weekly_pct=13,
         weekly_reset_h=122.8, k=0, k_work=0)
s3, w3 = ca.score_general(n3, cfg); s2, w2 = ca.score_general(n2, cfg)
assert w3 is None and w2 is None, (w3, w2)
# the goal, as an ordering: the account whose quota strands TOMORROW outranks the one with
# 5 days of runway — even carrying 60% 5h usage and 2 working sessions
assert s3 > s2, (s3, s2)
# γ=1 is the exact pre-M7 linear form, and under it the ordering INVERTS — pinning both that
# the kill switch works and that the old math had the defect M7 names
os.environ["CC_ROUTE_URGENCY_EXP"] = "1"
l3 = ca.score_general(n3, cfg)[0]; l2 = ca.score_general(n2, cfg)[0]
assert l2 > l3, (l2, l3)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router M7: the router charges WORKING sessions, with the pane census as fail-closed fallback" {
  run python3 -c "$LOAD"'
import os
for v in ("CC_ROUTE_URGENCY_EXP", "CC_ROUTE_KWORK", "CC_ROUTE_ASSIGN", "CC_ROUTE_PROJ"):
    os.environ.pop(v, None)
# 28 idle panes are not burn: routable with 2 working sessions
assert ca._excluded(row(k=28, k_work=2), R) is None
# 8 WORKING sessions are the pile-up KMAX exists for
assert ca._excluded(row(k=2, k_work=R["KMAX"]), R) == "kmax-concurrency"
# An old cache row (no k_work) degrades to the census — the stricter COUNT, never to zero...
assert ca.k_eff(row(k=5, k_work=None)) == 5
# ...but the census is measured against KMAX_RESIDENT, not KMAX (§5 P2 / 07 §6.2). Charging a
# RESIDENT count against the ACTIVE integer is what capped the fleet at 4 x 8 = 32 sessions and
# refused the 33rd with rc 2, i.e. a dispatch HALT — reachable at any moment, since this is the
# branch every over-budget transcript walk takes.
assert ca._excluded(row(k=R["KMAX"], k_work=None), R) is None, "the 33rd-session wall is back"
assert ca._excluded(row(k=R.get("KMAX_RESIDENT", ca.KMAX_RESIDENT_DEFAULT), k_work=None), R) \
       == "kmax-concurrency"
# kill switch restores census charging even when k_work is present — and the census cap with it
os.environ["CC_ROUTE_KWORK"] = "off"
assert ca.k_src(row(k=2, k_work=0)) == "panes"
assert ca._excluded(row(k=R["KMAX"], k_work=0), R) is None
assert ca._excluded(row(k=ca.KMAX_RESIDENT_DEFAULT, k_work=0), R) == "kmax-concurrency"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router M7: fire-time phantoms demote inside the cache TTL and can exclude at KMAX" {
  run python3 -c "$LOAD"'
import os
for v in ("CC_ROUTE_URGENCY_EXP", "CC_ROUTE_KWORK", "CC_ROUTE_ASSIGN", "CC_ROUTE_PROJ"):
    os.environ.pop(v, None)
base = ca.score_general(row(k_work=0), cfg)[0]
burst = ca.score_general(row(k_work=0, k_phantom=3), cfg)[0]
assert burst < base, (burst, base)
# phantoms count toward the concurrency cap: a burst can fill an account to KMAX
assert ca._excluded(row(k_work=6, k_phantom=2), R) == "kmax-concurrency"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router M7: assignment ledger — record, TTL expiry, malformed lines, prune" {
  run python3 -c "$LOAD"'
import json, os, time
os.environ.pop("CC_ROUTE_ASSIGN", None); os.environ.pop("CC_ROUTE_ASSIGN_TTL_MIN", None)
p = os.path.join(os.environ["BATS_TEST_TMPDIR"], "assign.jsonl")
assert ca.record_assignment(cfg, "next3", src="test", path=p) is None
assert ca.record_assignment(cfg, "next3", path=p) is None
assert ca.record_assignment(cfg, "next2", path=p) is None
with open(p, "a") as f:
    f.write(json.dumps({"t": time.time() - 3600, "acct": "next3"}) + "\n")  # expired
    f.write("not json\n")                                                    # malformed
    f.write(json.dumps({"acct": "next3"}) + "\n")                            # no stamp
c = ca.assignment_counts(cfg, path=p)
assert c == {"next3": 2, "next2": 1}, c
# rows carry the live counts (apply_assignments is what main() runs per invocation)
rows = [dict(acct="next3"), dict(acct="next2"), dict(acct="next")]
ca.ASSIGN_PATH, keep = p, ca.ASSIGN_PATH
try:
    ca.apply_assignments(rows, cfg)
finally:
    ca.ASSIGN_PATH = keep
assert [r["k_phantom"] for r in rows] == [2, 1, 0], rows
# kill switch: the reader goes silent, spread degrades to pre-M7
os.environ["CC_ROUTE_ASSIGN"] = "off"
assert ca.assignment_counts(cfg, path=p) == {}
os.environ.pop("CC_ROUTE_ASSIGN")
# prune: crossing the threshold rewrites to the newest half, then growth resumes — so after
# threshold+1 more appends the file is far below the total ever written and never above the
# threshold by more than the appends since the last cut (exact-count assertions here would
# tripwire on their own growth — exact-count-assertion memo)
appended = ca.ASSIGN_PRUNE_LINES + 1
for i in range(appended):
    assert ca.record_assignment(cfg, "next2", path=p) is None
n = sum(1 for _ in open(p))
assert n < appended, (n, appended)                    # a prune happened
assert n <= ca.ASSIGN_PRUNE_LINES, (n, ca.ASSIGN_PRUNE_LINES)  # and the bound holds
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router M7: 5h projection softens at measured burn, capped at the window reset; soften-only" {
  run python3 -c "$LOAD"'
import os
for v in ("CC_ROUTE_URGENCY_EXP", "CC_ROUTE_KWORK", "CC_ROUTE_ASSIGN", "CC_ROUTE_PROJ",
          "CC_ROUTE_PROJ_LOOKAHEAD_H"):
    os.environ.pop(v, None)
# 18% now, burning 50%/h with 2h of window left: projects to 68% inside the 1h lookahead
soft = ca._soft(row(session_pct=18, session_reset_h=2.0, burn_5h_ph=0.5, k=0, k_work=0), R)
base = ca._soft(row(session_pct=18, session_reset_h=2.0, k=0, k_work=0), R)
assert soft < base <= 1.0, (soft, base)
# the reset caps the projection: 12min of runway accrues 0.1, not a full lookahead
capped = ca._soft(row(session_pct=18, session_reset_h=0.2, burn_5h_ph=0.5, k=0, k_work=0), R)
assert capped == base, (capped, base)
# soften-only BY CONSTRUCTION: projection must never trip the 5h-cutoff exclusion
assert ca._excluded(row(session_pct=50, session_reset_h=3.0, burn_5h_ph=5.0), R) is None
# kill switch
os.environ["CC_ROUTE_PROJ"] = "off"
assert ca._soft(row(session_pct=18, session_reset_h=2.0, burn_5h_ph=0.5, k=0, k_work=0), R) == base
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router M7: apply_burn derives rates from the utilization series; a rolled window reads as unknown" {
  run python3 -c "$LOAD"'
import json, os, time
from datetime import datetime, timezone, timedelta
p = os.path.join(os.environ["BATS_TEST_TMPDIR"], "util.jsonl")
now = datetime.now(timezone.utc)
def w(mins_ago, acct, sp, wp, stale=False):
    with open(p, "a") as f:
        f.write(json.dumps({"ts": (now - timedelta(minutes=mins_ago)).isoformat(),
                            "acct": acct, "session_pct": sp, "weekly_pct": wp,
                            "stale": stale}) + "\n")
w(24 * 60, "next3", 5, 10)          # 24h ago — weekly span anchor
w(30, "next3", 10, 24)              # 30min ago
w(0, "next3", 40, 25)               # now: 5h 10→40 over 30min = 0.6/h; weekly 10→25 over 24h
w(30, "next2", 80, 50)
w(0, "next2", 10, 50)               # 5h fell 80→10: the window ROLLED — no rate
w(30, "next4", 10, 10, stale=True)  # stale rows carry no measurement
w(0, "next4", 40, 10)
rows = [dict(acct="next3"), dict(acct="next2"), dict(acct="next4")]
samples, span = ca._util_tail(path=p, hours=48.0)   # S1b: (rows, ACHIEVED span), selected by
                                                    # TIME. The old byte-capped signature returned
                                                    # rows alone and its span was whatever 128 KiB
                                                    # bought — 12.16 h against the live file, under
                                                    # a docstring claiming 48. Every abstain rule
                                                    # below is written against the achieved span,
                                                    # so it has to be returned, not assumed.
assert span > 23.0, span
ca.apply_burn(rows, cfg, samples=samples)
r3, r2, r4 = rows
assert abs(r3["burn_5h_ph"] - 0.6) < 0.05, r3
assert abs(r3["burn_wk_ppd"] - 15.0) < 1.0, r3
assert "burn_5h_ph" not in r2, r2
assert "burn_5h_ph" not in r4, r4   # one sample after the stale drop = no pair
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router M7 + S3: apply_burn attaches the new weekly keys under their OWN names, in %/h" {
  # RP-27. THE UNIT IS THE HAZARD, and it is why this case exists separately from the assertions
  # on the incumbent keys above. burn_5h_ph is consumed by _su_projected as a FRACTION per hour
  # (su + b * ahead, su in [0,1]), so a %/h value written onto that key saturates the projection
  # to 1.0 on every row and reads as "every account is under 5h pressure" — a 100x error wearing
  # a plausible face. The weekly EWMA therefore ships under its OWN key, in %/h, and the
  # incumbent burn_wk_ppd stays populated beside it rather than being overwritten.
  run python3 -c "$LOAD"'
import json, os
from datetime import datetime, timezone, timedelta
p = os.path.join(os.environ["BATS_TEST_TMPDIR"], "util-ewma.jsonl")
now = datetime.now(timezone.utc)
wra = (now + timedelta(hours=100)).isoformat()
with open(p, "w") as f:
    for i in range(240, -1, -1):                  # 24 h at 6 min, weekly 26 -> 40 = 0.583 %/h
        f.write(json.dumps({"ts": (now - timedelta(minutes=i * 6)).isoformat(),
                            "acct": "next3", "session_pct": 10, "weekly_pct": 26 + (240 - i) * 0.0583,
                            "session_reset_at": None, "weekly_reset_at": wra}) + "\n")
rows = [row(acct="next3", weekly_pct=40, weekly_reset_h=100.0)]
samples, span = ca._util_tail(path=p, hours=48.0)
ca.apply_burn(rows, cfg, samples=samples)
r = rows[0]
assert "burn_wk_ewma_ph" in r, r
assert 0.45 < r["burn_wk_ewma_ph"] < 0.75, r      # ~0.583 %/h — NOT 0.0058 and NOT 14
assert "burn_wk_ppd" in r, r                      # the incumbent is NOT overwritten
assert 12.0 < r["burn_wk_ppd"] < 16.0, r          # ~14 %/day, i.e. the same rate in its own unit
assert "burn_wk_span_h" in r and r["burn_wk_span_h"] > 6.8, r
assert "wk_strand_pp" in r, r
assert 0.0 < r["wk_strand_pp"] < 5.0, r           # 40 + 0.583*100 = 98.3 -> ~1.7 pp die
# UPDATED IN PLACE (S7 landed). This line used to read `assert "burn_5h_ewma_ph" not in r` with
# the note "S7 is a LATER wave"; that wave is now built, so the assertion becomes the SAME
# invariant stated positively -- the 5h EWMA ships under its OWN key, in %/h, and the incumbent
# burn_5h_ph keeps its own key in its own unit beside it. The fixture holds session_pct pinned
# at 10, so the honest 5h rate here is exactly ZERO, and zero is a value: an implementation that
# left the key absent on a flat meter would be indistinguishable from one that abstained.
assert "burn_5h_ewma_ph" in r, r
assert r["burn_5h_ewma_ph"] == 0.0, r
assert r["burn_5h_span_h"] > 5.0, r
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router M7 + S3: the weekly-drain block sorts by pp AT RISK, and a zero-strand row still renders" {
  # UPDATED IN PLACE (USAGE_TELEMETRY_100P §5.3 RP-25/RP-26/RP-27), not rewritten. This case used
  # to assert `soonest-first` and the bare `needs N%/d` rate. BOTH were the defect:
  #   * soonest-first led with the 5 pp account and TRAILED the pair holding 119.5 pp with four
  #     days of runway. Reset proximity is urgency; pp at risk is the loss. The fleet stranded
  #     43 pp over 8 completed account-weeks and no surface named who was losing it.
  #   * `needs 17%/d over 5d` quotes a rate in a unit longer than its own window (S2/M5).
  # Restoring either spelling to satisfy an older assertion re-introduces what they cost.
  run python3 -c "$LOAD"'
# live shapes measured 2026-08-25T09:47:41Z; strand = 100 - (weekly_pct + ewma * reset_h)
n4 = row(acct="next4", weekly_pct=14, weekly_reset_h=119.2, burn_wk_ewma_ph=0.186)
n2 = row(acct="next2", weekly_pct=17, weekly_reset_h=97.2, burn_wk_ewma_ph=0.281)
n3 = row(acct="next3", weekly_pct=92, weekly_reset_h=2.21, burn_wk_ewma_ph=1.140,
         burst={"pct": 95.6, "h": 3.0, "n": 2576, "need_pph": 3.62, "never": False})
n1 = row(acct="next", weekly_pct=52, weekly_reset_h=114.21, burn_wk_ewma_ph=1.725)
line = ca.pace_line([n3, n1, n2, n4])          # deliberately NOT in the expected order
assert line.startswith("weekly drain — pp that DIE at reset"), line
assert "nowcast at the last 48h of pace" in line, line   # a NOWCAST: no lead-time claim, §5.1 LB-2
# RP-25 — sorted by pp at risk, descending: 64 / 56 / 5, then the zero-strand row
assert line.index("next4") < line.index("next2") < line.index("next3") < line.index("next "), line
assert "next4 strand ~64pp of 86" in line, line
assert "next2 strand ~56pp of 83" in line, line
assert "next3 strand ~5pp of 8" in line, line
# M5 rides the strand row: how much dies, and whether the demand is routine or a stunt
assert "next3 strand ~5pp of 8 · p96 of its own 3h burns" in line, line
# RP-26 — a zero-strand account still RENDERS, and renders LAST. A sorted() over a list filtered
# on strand > 0 passes RP-25 and drops this row silently.
assert "next no strand" in line, line
assert line.rstrip().split(chr(10))[-1].strip().startswith("next no strand"), line
# RP-26b, ADDED 2026-09-01 (backlog 70ed289c10fb) — this row is at phase 0.32, i.e. MID-WEEK, and
# the ratio it used to carry here was `1.62× burn, ⚠ WALL trajectory`. That is the false alarm
# itself: the backtest of this exact fixture (51% at day 3) projected 119% against a 99% actual,
# and the linear projector errs by a mean 46 pp across the whole mid-week regime. `wall_projection`
# now abstains below 6/7 elapsed, so the row keeps its place in the sort and loses only the number
# that was misinforming it. ASSERTION MOVED, NOT DELETED — the WALL flag is re-sited below, in the
# window where it is still true. Re-adding `1.62× burn` here restores the 46 pp error class.
assert "× burn" not in line, line
assert "⚠ WALL" not in line, line
assert "162" not in line and "163" not in line, line     # never the ~162% projection either
assert "BEHIND" not in line, line                        # 47ddbf47c DELETED it: on 2026-08-16 three freshly-reset windows each read
                                                         # BEHIND, which is correct and reads as gross under-utilisation.
# RP-26b re-sited: in the LAST DAY the projection speaks again, and the ⚠ WALL flag with it —
# at day 6 linear and empirical have converged (-17 pp, then -2 pp at day 7), so an account that
# will hit 100% and be DOWN until reset is still named. 95% with 20h left = 1.08× burn.
wall = ca.pace_line([row(acct="next", weekly_pct=95, weekly_reset_h=20.0, burn_wk_ewma_ph=0.5)])
assert "next no strand" in wall, wall
assert "1.08× burn" in wall, wall
assert "⚠ WALL trajectory" in wall, wall
assert "107" not in wall and "108" not in wall, wall     # the RATIO, never the >100 projection
# an abstention renders as the WORD plus its reason, never as a zero (L2)
ab = ca.pace_line([row(acct="next2", weekly_pct=13, weekly_reset_h=122.8, burn_wk_span_h=4.1)])
assert "next2 strand unknown (span 4.1h < 6.8h)" in ab, ab
# no data ⇒ no block (a drain block over nothing would render at every error state)
assert ca.pace_line([row(weekly_pct=None), row(weekly_reset_h=None)]) == ""
# ...and with NO exchange rate stamped, the row keeps its bare clock and the header stays the
# S3 spelling. This is the degrade path for RP-28 below and it must not render half a clause.
assert "start by" not in line, line
assert "K=" not in line, line
assert "next4 strand ~64pp of 86 · 4d left" in line, line
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router M7 + S4: the drain row answers the THIRD question — by when must the burst start" {
  # RP-28 (renderer arm of §5.2 S4). S3 shipped rows answering two of the goal's three questions
  # — how much dies, and whether the demand is routine — and closed each with a bare `4d left`.
  # The clock alone is not the answer to "by when": closing an 83 pp deficit costs six 5h
  # windows, four roll waits and an expected freeze, so the start time sits ~28 h before the
  # reset whatever the clock says. M4′ renders that, and ONLY on rows that have something to
  # lose: a zero-strand row has no burst to schedule and keeps its clock.
  run python3 -c "$LOAD"'
K = 0.192
n4 = row(acct="next4", weekly_pct=14, weekly_reset_h=119.2, burn_wk_ewma_ph=0.186,
         session_pct=8, session_reset_h=0.5, exch_k=K, exch_k_src="live")
n2 = row(acct="next2", weekly_pct=17, weekly_reset_h=97.2, burn_wk_ewma_ph=0.281,
         session_pct=8, session_reset_h=0.54, exch_k=K, exch_k_src="live")
n3 = row(acct="next3", weekly_pct=92, weekly_reset_h=2.21, burn_wk_ewma_ph=1.140,
         session_pct=13, session_reset_h=3.37, exch_k=K, exch_k_src="live",
         burst={"pct": 95.6, "h": 3.0, "n": 2576, "need_pph": 3.62, "never": False})
n1 = row(acct="next", weekly_pct=52, weekly_reset_h=114.21, burn_wk_ewma_ph=1.725,
         session_pct=50, session_reset_h=2.0, exch_k=K, exch_k_src="live")
line = ca.pace_line([n3, n1, n2, n4])
# the header names K — and ONLY now that something consumes it. S3 shipped this header without
# the clause deliberately, because rendering a coefficient nothing reads is the metric shape
# §3.2 forbids; M4′ is the first consumer.
assert line.startswith("weekly drain — pp that DIE at reset (K=0.192 live · "), line
assert "nowcast at the last 48h of pace" in line, line
# the two SLACK rows carry the start time and the slack, in §5.2s AFTER shape
assert "next4 strand ~64pp of 86 · start by T−28h (91h slack)" in line, line
assert "next2 strand ~56pp of 83 · start by T−28h (70h slack)" in line, line
# ...and the LATE row names the FLOOR. "You are late" without "and this much is already gone"
# invites the reader to burst anyway and lose the same pp with the tokens spent.
assert "next3 strand ~5pp of 8 · p96 of its own 3h burns · ⚠ LATE by 0.6h" in line, line
assert "2.8pp already unrecoverable" in line, line
# a ZERO-STRAND row keeps its bare clock: there is no burst to schedule on it
assert "next no strand — 1.62× burn, ⚠ WALL trajectory · 4d left" in line, line
# K UNFITTED (S1c abstained) costs the START-BY clause and NOTHING ELSE. §5.2s abstain text
# says a null K prints `no strand figures this sweep`; that was written before S3 established
# the strand is pure weekly-space arithmetic that consumes no K, and it is now false — saying
# it would tell a reader the strand figures are missing while they sit right there on the rows.
n2b = dict(n2); n2b["exch_k"] = None; n2b["exch_k_src"] = None
ab = ca.pace_line([n2b])
assert "K unfitted" in ab, ab
assert "no start-time figures this sweep" in ab, ab
assert "next2 strand ~56pp of 83" in ab, ab          # the strand is STILL THERE
assert "start by" not in ab, ab
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "--assign CLI: appends one ledger row and never sweeps; unknown account exits 64" {
  local ledger="$BATS_TEST_TMPDIR/assign-cli.jsonl"
  # the fixture endpoint is unreachable — if --assign tried a sweep this would hang/fail loudly
  CC_ASSIGN_LOG="$ledger" run python3 "$CA_BIN" --assign next3 --src harness
  [ "$status" -eq 0 ] || { echo "rc=$status out=$output"; false; }
  [ -z "$output" ] || { echo "rc=$status out=$output"; false; }
  run python3 - "$ledger" <<'PY'
import json, sys, time
rows = [json.loads(l) for l in open(sys.argv[1])]
assert len(rows) == 1, rows
r = rows[0]
assert r["acct"] == "next3" and r["src"] == "harness", r
assert isinstance(r["t"], float) and abs(time.time() - r["t"]) < 60, r
assert "ts" in r, r
print("OK")
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
  CC_ASSIGN_LOG="$ledger" run python3 "$CA_BIN" --assign nosuch
  [ "$status" -eq 64 ]
  [[ "$output" == *"--assign requires an account name"* ]] || { echo "$output"; false; }
  # the bad call must not have appended
  [ "$(wc -l < "$ledger")" -eq 1 ]
}

# ---- the DESK lane: the two-key rule (DESK_ROUTER_AND_STARTUP_V1 W1, docs/research/R2) ---------
# The `interactive` lane shipped 2026-08-10 with NO test coverage at all — not one case named it —
# which is how a score whose load-bearing premise was false landed and stayed. These cases pin the
# policy itself (not its arithmetic), the degradation ladder, both kill switches, hysteresis, the
# phantom exemption, and the one rule the reversal must NOT touch (cliff no-yield).

@test "router desk: the two-key rule takes the EARLIEST WEEKLY RESET among 5h-safe accounts" {
  run python3 -c "$LOAD"'
import os
for v in ("CC_ROUTE_DESK_5H_FLOOR", "CC_ROUTE_DESK_W_FLOOR", "CC_ROUTE_DESK_HYST",
          "CC_ROUTE_DESK_ASSIGN_EXEMPT", "CC_ROUTE_KWORK", "CC_ROUTE_ASSIGN", "CC_ROUTE_PROJ"):
    os.environ.pop(v, None)
# The 2026-08-11T20:05:28Z incident, verbatim from R1 §2: the shipped survival lane ranked next3
# 0.6334 over next 0.5402 (+17.2%) on weekly headroom 0.97 vs 0.56, while /accounts (general)
# ranked next3 LAST. next resets its week in 103h, next3 in 159h.
n3 = row(acct="next3", session_pct=15, session_reset_h=2.5, weekly_pct=3, weekly_reset_h=159.0,
         k=0, k_work=0)
n1 = row(acct="next", session_pct=3, session_reset_h=3.4, weekly_pct=44, weekly_reset_h=103.0,
         k=0, k_work=0)
s3, w3 = ca.score_interactive(n3, cfg); s1, w1 = ca.score_interactive(n1, cfg)
assert w3 is None and w1 is None, (w3, w1)
# CONTROL — the pre-W1 survival formula, inline, so the fixture provably discriminates the two
# POLICIES and not merely the two accounts. The old code is deleted; its answer must not be.
def survival(r):
    su = ca._su_projected(r, R)
    s_rem = ca.clamp((R["S_CUT"] - su) / R["S_CUT"], R["SF_FLOOR"], 1.0)
    w_rem = 1.0 - r["weekly_pct"] / 100.0
    KF = ca.clamp(1 - ca.k_eff(r) / R["KMAX"], R["KFLOOR"], 1.0)
    return w_rem * s_rem * KF
assert survival(n3) > survival(n1), "fixture no longer reproduces the incident"
# ...and the two-key rule inverts it: both accounts are in the SAFE SET, so the pick is decided
# purely by which week expires first. This assertion is RED on the pre-change scorer.
assert s1 > s3, (s1, s3)
assert ca.desk_keys(n3, cfg)[2] == ca.desk_keys(n1, cfg)[2] == ca.DESK_TIER_SAFE
# the SSOT constants ARE the code defaults (accounts.json claims it; nothing checked it)
assert R["DESK_5H_FLOOR"] == ca.DESK_5H_FLOOR, R["DESK_5H_FLOOR"]
assert R["DESK_W_FLOOR"] == ca.DESK_W_FLOOR, R["DESK_W_FLOOR"]
# lane isolation: general keeps its own objective, unchanged by any of this
g3 = ca.score_general(n3, cfg)[0]; g1 = ca.score_general(n1, cfg)[0]
assert g1 > g3, (g1, g3)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router desk: the degradation ladder never empties — safe-set, then 5h-safe, then eligible" {
  run python3 -c "$LOAD"'
import os
for v in ("CC_ROUTE_DESK_5H_FLOOR", "CC_ROUTE_DESK_W_FLOOR", "CC_ROUTE_DESK_HYST", "CC_ROUTE_PROJ"):
    os.environ.pop(v, None)
safe = row(acct="safe", session_pct=10, weekly_pct=40, weekly_reset_h=150.0)
thin = row(acct="thin", session_pct=10, weekly_pct=95, weekly_reset_h=10.0)   # 5h-safe, weekly-thin
hot  = row(acct="hot",  session_pct=70, weekly_pct=40, weekly_reset_h=1.0)    # over the 5h floor
assert ca.desk_keys(safe, cfg)[2] == ca.DESK_TIER_SAFE
assert ca.desk_keys(thin, cfg)[2] == ca.DESK_TIER_5H      # the WEEKLY key degrades first
assert ca.desk_keys(hot, cfg)[2] == ca.DESK_TIER_ANY
# TIER DOMINANCE: the ladder is lexicographic, so no weekly deadline however imminent can lift a
# row out of its rung — hot resets in 1h and still loses to safe, which resets in 150h.
ss = ca.score_interactive(safe, cfg)[0]
st = ca.score_interactive(thin, cfg)[0]
sh = ca.score_interactive(hot, cfg)[0]
assert ss > st > sh, (ss, st, sh)
# ...AND THE SET IS NEVER EMPTIED. A fleet where every account fails BOTH keys still returns a
# ranking — the failure mode most likely to ship is this one answering "none" and the launcher
# silently falling back to the pinned account.
allhot = [row(acct="h1", session_pct=70, weekly_pct=40, weekly_reset_h=100.0),
          row(acct="h2", session_pct=80, weekly_pct=95, weekly_reset_h=20.0)]
out, reasons = ca.ranked(allhot, cfg, WIN_OPEN, "interactive")
assert [r["acct"] for _s, r in out] == ["h2", "h1"], (out, reasons)   # earliest reset still wins
assert reasons == {}, reasons
# every returned score is strictly positive — _rank_pass drops s <= 0, so a zero-valued bottom
# rung would silently empty the set instead of ranking it
assert all(s > 0 for s, _r in out), out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router desk: both floors are kill-switched, and 0 is STRICTNESS, never off" {
  run python3 -c "$LOAD"'
import os
for v in ("CC_ROUTE_DESK_5H_FLOOR", "CC_ROUTE_DESK_W_FLOOR", "CC_ROUTE_PROJ"):
    os.environ.pop(v, None)
hot  = row(session_pct=70, weekly_pct=40)      # over the 0.60 floor
cool = row(session_pct=10, weekly_pct=40)
thin = row(session_pct=10, weekly_pct=95)      # weekly headroom 0.05 < 0.15
assert ca.desk_keys(hot, cfg)[2] == ca.DESK_TIER_ANY
os.environ["CC_ROUTE_DESK_5H_FLOOR"] = "off"
assert ca.desk_keys(hot, cfg)[2] == ca.DESK_TIER_SAFE          # key neutralised
os.environ["CC_ROUTE_DESK_5H_FLOOR"] = "0"
# POLARITY: 0 is not "no floor", it is "nothing is ever 5h-safe". _term_on would have read this
# as off and inverted the switch — the reason these knobs do not use it.
assert ca.desk_keys(cool, cfg)[2] == ca.DESK_TIER_ANY
os.environ["CC_ROUTE_DESK_5H_FLOOR"] = "0.75"
assert ca.desk_keys(hot, cfg)[2] == ca.DESK_TIER_SAFE          # a NUMBER moves the floor
os.environ["CC_ROUTE_DESK_5H_FLOOR"] = "not-a-number"
assert ca.desk_keys(hot, cfg)[2] == ca.DESK_TIER_ANY           # malformed ⇒ the default stands
os.environ.pop("CC_ROUTE_DESK_5H_FLOOR")
assert ca.desk_keys(thin, cfg)[2] == ca.DESK_TIER_5H
os.environ["CC_ROUTE_DESK_W_FLOOR"] = "off"
assert ca.desk_keys(thin, cfg)[2] == ca.DESK_TIER_SAFE
os.environ["CC_ROUTE_DESK_W_FLOOR"] = "0"                      # 0 headroom-floor IS neutral here
assert ca.desk_keys(thin, cfg)[2] == ca.DESK_TIER_SAFE
os.environ.pop("CC_ROUTE_DESK_W_FLOOR")
# with both keys off the rule degenerates to a pure earliest-weekly-reset sort — the documented
# degenerate form, and it must still never empty the set
os.environ["CC_ROUTE_DESK_5H_FLOOR"] = "off"; os.environ["CC_ROUTE_DESK_W_FLOOR"] = "off"
rows = [row(acct="far", session_pct=70, weekly_pct=95, weekly_reset_h=140.0),
        row(acct="soon", session_pct=70, weekly_pct=95, weekly_reset_h=4.0)]
out, _ = ca.ranked(rows, cfg, WIN_OPEN, "interactive")
assert [r["acct"] for _s, r in out] == ["soon", "far"], out
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router desk: the weekly floor RAMPS with the horizon — the tail is not abandoned (W2)" {
  run python3 -c "$LOAD"'
import os
for v in ("CC_ROUTE_DESK_5H_FLOOR", "CC_ROUTE_DESK_W_FLOOR", "CC_ROUTE_DESK_W_RAMP",
          "CC_ROUTE_DESK_W_FULL_H", "CC_ROUTE_DESK_HYST", "CC_ROUTE_PROJ"):
    os.environ.pop(v, None)
# THE MEASURED REGRESSION, replayed as a unit. `next` sat at 86% weekly (headroom 0.14) with 11.1h
# to its reset — ONE point under the flat 0.15 floor — fell to DESK_TIER_5H, and the desk left it
# for an account six days from its own reset. It expired with 9pp unused. The floor now scales to
# what the wall would COST, so 11h out that row is back in the safe set.
tail = row(acct="tail", session_pct=10, weekly_pct=86, weekly_reset_h=11.1)
assert ca.desk_keys(tail, cfg)[2] == ca.DESK_TIER_SAFE, ca.desk_keys(tail, cfg)
# ...and it is preferred over a roomy account whose reset is days away — the whole point.
roomy = row(acct="roomy", session_pct=10, weekly_pct=3, weekly_reset_h=160.0)
out, _ = ca.ranked([roomy, tail], cfg, WIN_OPEN, "interactive")
assert [r["acct"] for _s, r in out] == ["tail", "roomy"], out
# THE GUARD SURVIVES AT DISTANCE: the same headroom, days out, is still demoted. This is the case
# the floor exists for — a weekly wall there is unrecoverable for the rest of the week.
assert ca.desk_keys(row(weekly_pct=86, weekly_reset_h=160.0), cfg)[2] == ca.DESK_TIER_5H
# MONOTONE in the horizon, and never above the flat floor. The scale is HORIZON-hours, not raw
# reset_h — horizon() nets off MARGIN_H — so saturation lands at FULL_H + MARGIN_H, and the floor
# is a hair under the flat one at exactly FULL_H. That is the shared contract, not a rounding slip.
f = [ca.desk_w_floor_at(R, t) for t in (0.5, 6.0, 12.0, 24.0, 48.0, 168.0)]
assert f == sorted(f), f
assert f[-1] == f[-2] == ca.desk_w_floor(R), f          # saturates AT the full floor, never above
assert f[0] < 0.01, f                                   # at the reset itself ~nothing is reserved
assert f[3] < ca.desk_w_floor(R), f                     # FULL_H exactly ⇒ still ramping (MARGIN_H)
# UNKNOWN TIMING KEEPS THE FULL FLOOR — horizon() reads absent, zero and elapsed alike as FAR
# AWAY, so bad data can never talk the desk into draining an account. This is the fail-safe
# direction and it is inherited, not re-implemented.
assert ca.desk_w_floor_at(R, None) == ca.desk_w_floor(R)
assert ca.desk_w_floor_at(R, 0.0) == ca.desk_w_floor(R)
assert ca.desk_w_floor_at(R, -5.0) == ca.desk_w_floor(R)
# KILL SWITCH restores the flat floor at every horizon (the pre-W2 behaviour), and a NUMBER moves
# the ramp. Malformed ⇒ the default stands, like every other knob here.
os.environ["CC_ROUTE_DESK_W_RAMP"] = "off"
assert ca.desk_w_floor_at(R, 1.0) == ca.desk_w_floor(R)
assert ca.desk_keys(tail, cfg)[2] == ca.DESK_TIER_5H            # the regression, reproduced
os.environ.pop("CC_ROUTE_DESK_W_RAMP")
os.environ["CC_ROUTE_DESK_W_FULL_H"] = "4"
assert ca.desk_w_floor_at(R, 11.1) == ca.desk_w_floor(R)        # saturated well before 11.1h...
assert ca.desk_keys(tail, cfg)[2] == ca.DESK_TIER_5H            # ...so 0.14 < 0.15 demotes again
os.environ["CC_ROUTE_DESK_W_FULL_H"] = "not-a-number"
assert abs(ca.desk_w_floor_at(R, 12.0)
           - ca.desk_w_floor(R) * (12.0 - R["MARGIN_H"]) / ca.DESK_W_FLOOR_FULL_H) < 1e-9
os.environ.pop("CC_ROUTE_DESK_W_FULL_H")
# the SSOT constant is the one the code ships
assert R.get("DESK_W_FLOOR_FULL_H", ca.DESK_W_FLOOR_FULL_H) == ca.DESK_W_FLOOR_FULL_H
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router desk: hysteresis keeps the incumbent unless beaten by the margin, and is switchable" {
  run python3 -c "$LOAD"'
import json, os, time
for v in ("CC_ROUTE_DESK_HYST", "CC_ROUTE_DESK_HYST_MARGIN", "CC_ROUTE_DESK_HYST_TTL_MIN",
          "CC_ROUTE_DESK_5H_FLOOR", "CC_ROUTE_DESK_W_FLOOR", "CC_ROUTE_PROJ", "CC_ROUTE_ASSIGN"):
    os.environ.pop(v, None)
inc  = row(acct="inc", weekly_pct=40, weekly_reset_h=30.0, desk_incumbent=True)
near = row(acct="near", weekly_pct=40, weekly_reset_h=27.0)    # earlier reset, inside the margin
far  = row(acct="far", weekly_pct=40, weekly_reset_h=20.0)     # earlier reset, PAST the margin
si = ca.score_interactive(inc, cfg)[0]
assert si > ca.score_interactive(near, cfg)[0], "incumbent lost inside the margin"
assert si < ca.score_interactive(far, cfg)[0], "incumbent held past the margin"
# it is a WITHIN-TIER preference only: stickiness must never hold the desk on an account that has
# fallen out of the safe set, which is exactly when it should move.
hot_inc = row(acct="inc", session_pct=70, weekly_pct=40, weekly_reset_h=30.0, desk_incumbent=True)
assert ca.score_interactive(hot_inc, cfg)[0] < ca.score_interactive(near, cfg)[0]
os.environ["CC_ROUTE_DESK_HYST"] = "off"
assert ca.score_interactive(inc, cfg)[0] < ca.score_interactive(near, cfg)[0]
os.environ.pop("CC_ROUTE_DESK_HYST")
# the incumbent comes from the launcher`s own --assign rows and nothing else
p = os.path.join(os.environ["BATS_TEST_TMPDIR"], "hyst.jsonl")
now = time.time()
with open(p, "w") as f:
    f.write(json.dumps({"t": now - 60, "acct": "desk-acct", "src": "claude-launcher"}) + "\n")
    f.write(json.dumps({"t": now - 10, "acct": "fired-acct", "src": "handoff-fire"}) + "\n")
assert ca.desk_incumbent(cfg, path=p) == "desk-acct"           # a NEWER dispatch fire is not it
with open(p, "a") as f:
    f.write(json.dumps({"t": now - 5, "acct": "newer-desk", "src": "claude-launcher"}) + "\n")
assert ca.desk_incumbent(cfg, path=p) == "newer-desk"
os.environ["CC_ROUTE_DESK_HYST_TTL_MIN"] = "0.01"              # everything now out of window
assert ca.desk_incumbent(cfg, path=p) is None
os.environ.pop("CC_ROUTE_DESK_HYST_TTL_MIN")
os.environ["CC_ROUTE_DESK_HYST"] = "off"
assert ca.desk_incumbent(cfg, path=p) is None
os.environ.pop("CC_ROUTE_DESK_HYST")
assert ca.desk_incumbent(cfg, path="/nonexistent/ledger") is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router desk: the desk does not pay its OWN launcher phantom; dispatch still does" {
  run python3 -c "$LOAD"'
import json, os, time
for v in ("CC_ROUTE_ASSIGN", "CC_ROUTE_ASSIGN_TTL_MIN", "CC_ROUTE_DESK_ASSIGN_EXEMPT",
          "CC_ROUTE_KWORK", "CC_ROUTE_DESK_HYST", "CC_ROUTE_PROJ"):
    os.environ.pop(v, None)
p = os.path.join(os.environ["BATS_TEST_TMPDIR"], "exempt.jsonl")
now = time.time()
with open(p, "w") as f:
    f.write(json.dumps({"t": now - 30, "acct": "next3", "src": "claude-launcher"}) + "\n")
    f.write(json.dumps({"t": now - 20, "acct": "next3", "src": "handoff-fire"}) + "\n")
assert ca.assignment_counts(cfg, path=p) == {"next3": 2}
assert ca.assignment_counts(cfg, path=p, exempt_src=ca.DESK_EXEMPT_SRC) == {"next3": 1}
# the CHARGE, and the one gate it reaches: the desk lane has no KF term, so a launcher phantom can
# only ever act through _excluded`s KMAX cap — i.e. by locking the desk OUT of the account the
# operator is already sitting in.
r = row(k_work=R["KMAX"] - 1, k_phantom=1, k_phantom_desk=0)
assert ca.k_eff(r) == R["KMAX"] and ca.k_eff_desk(r) == R["KMAX"] - 1
assert ca.score_general(r, cfg) == (None, "kmax-concurrency")
assert ca.score_interactive(r, cfg)[1] is None, ca.score_interactive(r, cfg)
os.environ["CC_ROUTE_DESK_ASSIGN_EXEMPT"] = "off"
assert ca.score_interactive(r, cfg) == (None, "kmax-concurrency")
os.environ.pop("CC_ROUTE_DESK_ASSIGN_EXEMPT")
# ABSENCE fails toward CHARGING: a row with no k_phantom_desk (an older cache, a module caller)
# reads the shared count, never zero.
assert ca.k_eff_desk(row(k_work=2, k_phantom=3)) == 5
# apply_assignments stamps all three desk fields from ONE ledger read
os.environ["CC_ASSIGN_LOG"] = p
ca.ASSIGN_PATH = p
rows = [row(acct="next3"), row(acct="other")]
ca.apply_assignments(rows, cfg)
assert rows[0]["k_phantom"] == 2 and rows[0]["k_phantom_desk"] == 1, rows[0]
assert rows[0]["desk_incumbent"] is True and rows[1]["desk_incumbent"] is False, rows
assert rows[1]["k_phantom"] == 0 and rows[1]["k_phantom_desk"] == 0, rows[1]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "router desk: the cliff no-yield rule survives the objective change" {
  run python3 -c "$LOAD"'
import os
for v in ("CC_ROUTE_CLIFF_TERM", "CC_ROUTE_DESK_HYST", "CC_ROUTE_PROJ"):
    os.environ.pop(v, None)
# every account inside the DRAIN band ⇒ the cliff term is what emptied the candidate set
rows = [row(acct="a", login_expires_h=10.0), row(acct="b", login_expires_h=20.0)]
out, reasons = ca.ranked(rows, cfg, WIN_OPEN, "general")
assert [r["acct"] for _s, r in out] == ["a", "b"], out          # dispatch YIELDS and re-ranks
assert all(r.get("cliff_yielded") for _s, r in out), out
# the desk lane does NOT: past the cliff invalid_grant has no reset to wait for, so abstaining and
# letting the launcher fall back to its pinned account beats a desk that dies on auth mid-session.
out_i, reasons_i = ca.ranked(rows, cfg, WIN_OPEN, "interactive")
assert out_i == [], out_i
assert set(reasons_i.values()) == {ca.CLIFF_DRAIN_REASON}, reasons_i
# the SOFT band still demotes inside the lane, and only inside its own tier
soft = row(acct="soft", weekly_pct=40, weekly_reset_h=30.0, login_expires_h=100.0)
clear = row(acct="clear", weekly_pct=40, weekly_reset_h=30.0)
assert ca.cliff_band(soft) == "soft"
assert ca.score_interactive(soft, cfg)[0] < ca.score_interactive(clear, cfg)[0]
assert ca.desk_keys(soft, cfg)[2] == ca.DESK_TIER_SAFE
assert ca.score_interactive(soft, cfg)[0] > ca.score_interactive(
    row(acct="hot", session_pct=70, weekly_pct=40, weekly_reset_h=1.0), cfg)[0]
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "load_cfg: a desk constant out of range fails with a message; absence keeps the default" {
  python3 - "$CA_CFG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); c["router"]["DESK_5H_FLOOR"] = 60      # a fraction typed as a %
json.dump(c, open(sys.argv[1], "w"))
PY
  run python3 "$CA_BIN" --route interactive --no-heal
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid router constants"* ]] || { echo "$output"; false; }
  [[ "$output" == *DESK_5H_FLOOR* ]] || { echo "$output"; false; }
  [[ "$output" != *Traceback* ]] || false

  # OPTIONAL by contract: removed entirely, the code default stands and the tool still runs. A
  # required-key addition would sys.exit for every consumer at once while a land converges.
  python3 - "$CA_CFG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
for k in ("DESK_5H_FLOOR", "DESK_W_FLOOR", "DESK_HYST_MARGIN", "DESK_HYST_TTL_MIN"):
    c["router"].pop(k, None)
json.dump(c, open(sys.argv[1], "w"))
PY
  run bash -c "python3 '$CA_BIN' --route interactive --fresh --no-heal 2>&1 >/dev/null"
  [[ "$output" != *Traceback* ]] || { echo "$output"; false; }
  [[ "$output" != *"invalid router constants"* ]] || { echo "$output"; false; }
}

@test "--route interactive: e2e picks the earliest-resetting safe account and says WHY on route-meta" {
  python3 - <<'PY'
import json, os, time, importlib.machinery, importlib.util
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
def r(n, wk, wrh, **kw):
    d = {"acct": n, "auth": "ok", "k": 0, "k_work": 0, "session_pct": 10, "session_reset_h": 3.0,
         "weekly_pct": wk, "weekly_reset_h": wrh, "fable_pct": 10, "fable_reset_h": 24.0,
         "credits_on": False}
    d.update(kw); return d
# roomiest week + latest reset vs the operator's stated preference: earlier expiry, low 5h use
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None,
           "rows": [r("roomy", 3, 159.0), r("expiring", 47, 86.0)]},
          open(os.environ["CACHE"], "w"))
PY
  run bash -c "python3 '$CA_BIN' --route interactive 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "expiring" ]
  run bash -c "python3 '$CA_BIN' --route interactive 2>&1 >/dev/null"
  [[ "$output" == *"route-meta: "* ]] || { echo "$output"; false; }
  [[ "$output" == *"acct=expiring"* ]] || { echo "$output"; false; }
  # W1.7 — WHICH instrument charged concurrency, so a pick made on the pane census is auditable
  [[ "$output" == *"k_src=work"* ]] || { echo "$output"; false; }
  [[ "$output" == *"kwork_to=0"* ]] || { echo "$output"; false; }
  [[ "$output" == *"desk_tier=2"* ]] || { echo "$output"; false; }
  [[ "$output" == *"desk_incumbent=0"* ]] || { echo "$output"; false; }
  # the desk fields are the DESK lane's own — they must not leak onto a dispatch decision
  run bash -c "python3 '$CA_BIN' --route general 2>&1 >/dev/null"
  [[ "$output" == *"k_src="* ]] || { echo "$output"; false; }
  [[ "$output" != *desk_tier* ]] || { echo "$output"; false; }
}

@test "--route interactive: the desk decision is RECORDED, with its runner-up, and only for --route" {
  # W2.6 — before this the desk lane wrote nothing. cc-route records every general/fable decision
  # into route.jsonl; the interactive lane's only footprint was one `--assign` row in a ledger it
  # SHARES with handoff-fire and which prunes 400 -> 200, so exactly FOUR launcher-routed launches
  # survived in the entire history when the routing incident was investigated. A lane whose
  # decisions cannot be replayed is a lane whose policy cannot be falsified.
  python3 - <<'PY'
import json, os, time, importlib.machinery, importlib.util
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
def r(n, wk, wrh):
    return {"acct": n, "auth": "ok", "k": 0, "k_work": 0, "session_pct": 10,
            "session_reset_h": 3.0, "weekly_pct": wk, "weekly_reset_h": wrh, "fable_pct": 10,
            "fable_reset_h": 24.0, "credits_on": False}
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None,
           "rows": [r("roomy", 3, 159.0), r("expiring", 47, 86.0)]},
          open(os.environ["CACHE"], "w"))
PY
  local rec="$CC_ROUTE_RECORDS_DIR/route.jsonl"
  run bash -c "python3 '$CA_BIN' --route interactive 2>/dev/null"
  [ "$status" -eq 0 ] && [ "${lines[0]}" = "expiring" ] || false
  [ -f "$rec" ]
  run python3 -c "
import json, os, sys
rows = [json.loads(l) for l in open(os.environ['CC_ROUTE_RECORDS_DIR'] + '/route.jsonl')]
assert len(rows) == 1, rows
d = rows[0]
# cc-route's OWN four keys first, so one jq filter reads both producers
for f in ('ts', 'slot', 'outcome', 'detail'):
    assert f in d, (f, d)
assert d['slot'] == 'interactive' and d['outcome'] == 'route', d
assert d['acct'] == 'expiring' and d['kind'] == 'interactive', d
# the runner-up is what makes a decision RE-JUDGEABLE rather than merely readable: 'expiring won'
# says nothing about whether it won by a nose, and the margin is what hysteresis acts on
assert d['runner_up'] == 'roomy', d
assert d['score'] > d['runner_up_score'], d
assert d['desk_tier'] == 2 and d['desk_incumbent'] is False, d
print('OK')"
  # TWO statements, not `A && B || C`: an assertion in the LEFT element of an AND-OR list is
  # the [and-absorbed] class the liveness analyzer reports (scripts/bats-assert-liveness.py),
  # and the fixer DECLINES this three-part shape rather than guess. Split, each failure keeps
  # its own diagnostic, and each `[[ ]]` sits in condition position where errexit still binds.
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
  # --rank is DIAGNOSTIC: it must not manufacture a decision record...
  run bash -c "python3 '$CA_BIN' --rank interactive >/dev/null 2>&1"
  [ "$(wc -l < "$rec")" -eq 1 ]
  # ...and the dispatch lanes must not be double-recorded — cc-route is their producer, and a
  # second one would double-count every dispatch decision in the same file.
  run bash -c "python3 '$CA_BIN' --route general >/dev/null 2>&1"
  [ "$(wc -l < "$rec")" -eq 1 ]
  # kill switch (house pattern): off means no record, never a broken launch
  run bash -c "CC_ROUTE_DESK_LOG=off python3 '$CA_BIN' --route interactive >/dev/null 2>&1"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$rec")" -eq 1 ]
}

@test "--route interactive: an ABSTENTION is recorded too, never silence" {
  # "the desk refused and the launcher fell back to its pinned account" is a decision. Recorded as
  # outcome=none: the silent version is indistinguishable from the router never having run, which
  # is precisely the state that made the 2026-08-11 incident nearly unreconstructable.
  python3 - <<'PY'
import json, os, time, importlib.machinery, importlib.util
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader(
    "ca", importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])))
importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).exec_module(ca)
cfg = json.load(open(os.environ["CA_CFG"]))
# 5h past the routing cutoff on every account: policy refuses, data is fine
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None,
           "rows": [{"acct": "capped", "auth": "ok", "k": 0, "k_work": 0, "session_pct": 99,
                     "session_reset_h": 3.0, "weekly_pct": 10, "weekly_reset_h": 20.0,
                     "fable_pct": 10, "fable_reset_h": 24.0, "credits_on": False}]},
          open(os.environ["CACHE"], "w"))
PY
  run bash -c "python3 '$CA_BIN' --route interactive 2>/dev/null"
  [ "$status" -eq 2 ] && [ "${lines[0]}" = "none" ] || false
  run python3 -c "
import json, os
rows = [json.loads(l) for l in open(os.environ['CC_ROUTE_RECORDS_DIR'] + '/route.jsonl')]
assert len(rows) == 1, rows
d = rows[0]
assert d['outcome'] == 'none' and d['acct'] is None and d['score'] is None, d
# and the reason the desk refused is IN the record — an abstention with no cause is a shrug
assert d['excluded'].get('capped'), d
print('OK')"
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# --- read_creds failure attribution -----------------------------------------------------------
# Hermetic per this suite's own contract: a config_dir that hashes to a nonexistent keychain
# service, and LOG_PATH rebound onto BATS_TEST_TMPDIR. Never reads a real credential.
#
# 🚨 Do NOT try to isolate the log by overriding HOME. `security find-generic-password` resolves
# the login keychain through HOME, so a temp HOME makes EVERY read return rc 44 and the
# "stays silent on a non-failure" arm passes vacuously — the harness breaking the subject.
_readcreds_probe() {   # <src> <timeout-s>  -> prints "state|logbody"
  CC_KEYCHAIN_TIMEOUT_S="$2" python3 - "$1" "$BATS_TEST_TMPDIR" <<'PY'
import importlib.util, os, sys
src, tmp = sys.argv[1], sys.argv[2]
shim = os.path.join(tmp, "ca_mod.py")
open(shim, "w").write(open(src).read())          # spec_from_file_location needs a .py name
spec = importlib.util.spec_from_file_location("ca", shim)
ca = importlib.util.module_from_spec(spec); spec.loader.exec_module(ca)
log = os.path.join(tmp, "kc.log"); ca.LOG_PATH = log
open(log, "w").close()
_, state = ca.read_creds("/nonexistent/cc-hermetic-fixture", "nobody-cc-test")
print(state + "|" + open(log).read().replace("\n", " "))
PY
}

@test "read_creds NAMES which failure path fired, with elapsed and returncode" {
  # Before this, all four returns collapsed to the bare label 'keychain-error', p.stderr (the one
  # string carrying the OSStatus) was discarded, and nothing was logged at all — so the
  # 2026-09-01T04:43Z fleet-wide outage could be reconstructed only from route.jsonl, and WHICH
  # path fired remained unknowable. That matters because probe_account copies this state into
  # row["error"], which _excluded() tests FIRST, so one unexplained hiccup drops an account from
  # every lane; when it hits all four, `claude` silently falls back to its pinned account.
  out="$(_readcreds_probe "$CA_BIN" 0.000001)"
  # `[ ]` (the test BUILTIN), never `[[ ]]` (a shell KEYWORD): under bats' errexit only the
  # builtin form aborts the test from a non-final line, so a mid-test `[[ ]]` is a dead
  # assertion that can never fail. scripts/bats-assert-liveness.py blocks the land on it.
  [ "${out%%|*}" = "keychain-error" ]
  # grep -c, never grep -q: under pipefail an early-exiting -q SIGPIPEs its own producer, so
  # the pipeline can report FAILURE on the very input it just matched (MEMORY.md
  # grep-q-under-pipefail-inverts-the-verdict). Count, then assert on the count.
  run bash -c "printf '%s' \"\${1}\" | grep -c 'path=timeout'" _ "${out#*|}"
  [ "$output" -ge 1 ]
  run bash -c "printf '%s' \"\${1}\" | grep -c 'elapsed_ms='" _ "${out#*|}"
  [ "$output" -ge 1 ]
}

@test "read_creds stays silent when the item is merely absent" {
  # rc 44 is 'no-keychain-item' -> auth logged-out, a GENUINE credential fact, not an instrument
  # failure. It must not be logged, or the log stops discriminating the thing it exists to show.
  out="$(_readcreds_probe "$CA_BIN" 10)"
  [ "${out%%|*}" = "no-keychain-item" ]
  run bash -c "printf '%s' \"\${1}\" | grep -c 'keychain-error'" _ "${out#*|}"
  [ "$output" = 0 ]
}

@test "MUTANT: a read_creds that logs nothing must fail the attribution test" {
  # Control-can-fail, aimed at the exact line that carries the value.
  mutant="$BATS_TEST_TMPDIR/mutant-ca"
  sed 's/^        _log_keychain_failure(config_dir, "timeout".*$/        pass/' "$CA_BIN" > "$mutant"
  grep -q '^        pass$' "$mutant"
  out="$(_readcreds_probe "$mutant" 0.000001)"
  [ "${out%%|*}" = "keychain-error" ]             # still the same state...
  run bash -c "printf '%s' \"\${1}\" | grep -c 'path=timeout'" _ "${out#*|}"
  [ "$output" = 0 ]                               # ...but the attribution is gone
}
