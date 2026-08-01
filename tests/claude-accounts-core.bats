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
# exactly ONE row marked, and it is the row the footer route line also names
assert len(picked) == 1, picked
assert picked[0].lstrip().startswith("win"), picked
assert "➤ general → win" in plain, plain
# the marker must not cost the row its column alignment
assert len(tbl[0]) == len(tbl[1]), [len(x) for x in tbl]
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
for f in ('acct', 'auth', 'k', 'is_self', 'route_reasons', 'route_reason_class'):
    assert f in r, f
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
# a heal that merely did not happen stays stale — the distinction is the whole point
ca.heal = lambda *a, **k: (False, "heal timed out")
r = ca.collect(cfg)[0]
assert r["auth"] == "stale", r
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]]
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
  run python3 -c "$LOAD$READOUT"'
rows = [row(acct="poor", weekly_pct=95, fable_pct=95),
        row(acct="rich", weekly_pct=5,  fable_pct=90, is_self=True),
        row(acct="fab",  weekly_pct=40, fable_pct=1)]
out = rd(rows)
g, _ = ca.ranked(rows, cfg, WIN_OPEN, "general")
f, _ = ca.ranked(rows, cfg, WIN_OPEN, "fable")
gp, fp = g[0][1]["acct"], f[0][1]["acct"]
assert gp != fp, (gp, fp)                       # the case a single marker would collapse
assert "➤" in acctrow(out, gp) and f"**{gp}**" in acctrow(out, gp), out
assert "➤ᶠ" in acctrow(out, fp), out
assert "➤ᶠ" not in acctrow(out, gp), out        # general pick is not also flagged as fable
assert "← you" in acctrow(out, "rich"), out
# the footer states the SAME answer as the marks — one router, not two opinions
assert f"➤ general → **{gp}**" in out and f"➤ fable → **{fp}**" in out, out
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
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
    'rows, wj, cached, prev = get_data(cfg, fresh=fresh, no_heal=no_heal)',
    'rows = [{"acct": "next3", "auth": "ok", "launcher": "claude3",\n'
    '         "login_expires_h": 50.0, "login_fixable": False,\n'
    '         "login_expires_at": "' + stamp + '"}]\n'
    '    wj, cached, prev = {}, False, None')
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
    'rows, wj, cached, prev = get_data(cfg, fresh=fresh, no_heal=no_heal)',
    'rows = [{"acct": "next3", "auth": "ok", "launcher": "claude3",\n'
    '         "login_expires_h": 500.0, "login_expires_at": "2099-01-01T00:00:00+00:00",\n'
    '         "login_fixable": False}]\n    wj, cached, prev = {}, False, None')
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
