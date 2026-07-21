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
  # DERIVED from the real SSOT — never hand-copied (a hand-copied block silently diverges
  # the moment a constant is added, and the suite then certifies math production never runs;
  # cache_grace_s was added later and a hand-copied fixture missed it immediately).
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [{"name": "next3", "config_dir": "/tmp/ca-test-nonexistent-xyz",
                "launcher": "claude-next3", "fable_launcher": "claude-fable3",
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
assert ca._excluded(row(k=R["KMAX"]), R) == "kmax-concurrency"
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
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
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
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "cache_read: a valid-JSON non-dict cache degrades to a miss instead of wedging the tool" {
  open_cache() { :; }
  echo 'null' > "$CACHE"
  run python3 -c "$LOAD"'
assert ca.cache_read(cfg) is None
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
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
assert ca.fmt_h(0.5) == "30m" and ca.fmt_h(2.0) == "2.0h" and ca.fmt_h(96.0) == "4.0d"
# both reset cells are fixed-width; an overflow skews every column to its right
for h in (-41.0, None, 0.0, 0.5, 2.0, 96.0, 1e5):
    assert len("↻" + ca.fmt_h(h)) <= 5, (h, ca.fmt_h(h))
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
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
    [[ "$output" == *"requires general|fable"* ]]
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
  [[ "$output" == *"excluded"* && "$output" == *"gone"* ]]

  run bash -c "python3 '$CA_BIN' --rank general 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]                       # the throttled row is absent from the ranking
  [[ "${lines[0]}" =~ ^[a-z0-9]+\ [0-9]+\.[0-9]{6}$ ]]
  [[ "${lines[0]}" == next3* ]]
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
for f in ('acct', 'auth', 'k', 'is_self', 'route_reasons', 'route_reason_class'):
    assert f in r, f
print('OK')" <<< "$output"
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}

@test "--relogin-info: rejects a missing value and an unknown account" {
  run python3 "$CA_BIN" --relogin-info
  [ "$status" -eq 1 ]
  [[ "$output" == *"requires an account name"* ]]
  run python3 "$CA_BIN" --relogin-info nosuch
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown account"* ]]
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
  [[ "$output" == *"invalid router constants"* ]]
  [[ "$output" != *Traceback* ]]

  python3 - "$CA_CFG" <<'PY'
import json, sys
c = json.load(open(sys.argv[1])); c["router"].pop("EPS_H")
json.dump(c, open(sys.argv[1], "w"))
PY
  run python3 "$CA_BIN" --json --no-heal
  [ "$status" -ne 0 ]
  [[ "$output" == *"missing or non-numeric"* ]]
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
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]

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
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
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
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
}
