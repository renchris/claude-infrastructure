#!/usr/bin/env bats
# claude-accounts — the WIRE truth vs the endpoint integer.
#
# WHAT THIS SUITE IS FOR. `/api/oauth/usage` reports each window as an INTEGER `percent` that
# ROUNDS UP and CLAMPS at 100. So `weekly 100%` is a THREE-WAY COLLAPSE — "99% used, server says
# allowed", "exactly full", and "102% used, server says rejected" — and the router read the first
# of those as `weekly-exhausted`. Measured live on 2026-09-19: `next` read `percent: 100` from the
# endpoint while `anthropic-ratelimit-unified-7d-utilization: 0.99` / `7d-status: allowed_warning`
# rode a real HTTP 200, i.e. the fleet was refusing a WORKING account; `next4` read `percent: 100`
# on its 5h window against a wire `1.02` / `rejected`, which is the same collapse at the other end.
#
# THE DIRECTION THAT MUST HOLD. The wire may only ever ADD precision or ADD a refusal. An absent
# wire (probe not wanted, transport failed, header set missing) must leave every verdict byte-
# identical to the endpoint-only behaviour — `predicate-refusal-is-not-a-negative`: a read that
# could not happen is not a permissive answer. W-3 and W-7 are the arms that pin that.
#
# Hermetic: scratch SSOT + ledger + cache in BATS_TEST_TMPDIR, unreachable endpoints, LOG_PATH
# redirected. fetch_wire_limits is ALWAYS stubbed — this suite never touches the network, and a
# test that did would be spending the operator's quota to assert a rendering.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_SSOT="$REPO/accounts.json"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CA_LEDGER="$BATS_TEST_TMPDIR/lastgood.json"
  export CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$CA_LEDGER"
  export YAML="$BATS_TEST_TMPDIR/model-config.yaml"
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
  "messages_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": yaml, "dia_local_state": "/nonexistent/LS",
  "cache_file": cache,
  "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"],
  "cache_grace_s": r["cache_grace_s"], "login_warn_h": r["login_warn_h"],
  "frontier": r["frontier"], "router": r["router"],
  "accounts": [{"name": "next3", "config_dir": "/tmp/ca-test-nonexistent-xyz",
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
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
ca.LASTGOOD_PATH = os.environ["CA_LEDGER"]
cfg = json.load(open(os.environ["CA_CFG"]))
R = cfg["router"]
SCOPED = cfg["frontier"]["scoped_display_name"]
CALLS = []
def limits(session=5, weekly=11, fable=7):
    return [{"kind": "session", "percent": session, "resets_at": None},
            {"kind": "weekly_all", "percent": weekly, "resets_at": None},
            {"kind": "weekly_scoped", "percent": fable, "resets_at": None,
             "scope": {"model": {"display_name": SCOPED}}}]
def probe(lim, wire=None):
    """One collect() with the usage endpoint stubbed and the wire stubbed to `wire` (None = the
    probe returns nothing, i.e. a MISS). Every call is recorded so a test can assert the GATE."""
    ca.concurrency = lambda c: {"next3": 0}
    ca.read_creds = lambda d, k: ({"accessToken": "t", "expiresAt": 9e12}, "present")
    ca.fetch_usage = lambda *a, **k: (200, {"limits": lim})
    def _wire(*a, **k):
        CALLS.append(1)
        return wire
    ca.fetch_wire_limits = _wire
    del CALLS[:]
    return ca.collect(cfg, no_heal=True)[0]
'

# ---- W-1: the live defect ----------------------------------------------------------------------
# The endpoint says 100; the server says 0.99 and `allowed_warning`. Pre-fix this row scored
# `weekly-exhausted` and was refused by every lane. FAILS PRE-FIX on the routability assert.

@test "W-1: endpoint 100 + wire 0.99 allowed => routable, with the last ~1pp of headroom" {
  run python3 -c "$LOAD"'
r = probe(limits(weekly=100),
          {"7d_util": 0.99, "7d_status": "allowed_warning", "5h_util": 0.05,
           "5h_status": "allowed", "status": "allowed_warning", "http": 200})
assert r["weekly_pct"] == 100, "the ENDPOINT meter is recorded untouched: the series keys window "\
                               "rolls on a meter going backwards, so a provenance switch mid-"\
                               "series would read as a reset"
assert r["wire"]["7d_util"] == 0.99, r
assert abs(ca.weekly_headroom(r) - 0.01) < 1e-9, ca.weekly_headroom(r)
assert ca._excluded(r, R) is None, ca._excluded(r, R)
score, reason = ca.score_general(r, cfg)
assert reason is None and score > 0, (score, reason)
assert ca.score_interactive(r, cfg)[1] is None, ca.score_interactive(r, cfg)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-2: the other end of the same collapse ---------------------------------------------------
# A server `rejected` is a FACT, and it outranks a comfortable-looking integer. The endpoint here
# reads a routable 97; only the wire knows the account is refused.

@test "W-2: a wire 7d 'rejected' excludes even when the endpoint integer looks routable" {
  run python3 -c "$LOAD"'
# WIRE_FORCE, and the reason is a REAL PROPERTY of the gate rather than test scaffolding. The
# endpoint integer here reads a comfortable 97, so wire_wanted() declines to spend the call and
# there is no wire to reject with — this state is reachable ONLY under `--wire`. That is not a
# contrivance: the endpoint LAGS the wire (measured 2026-09-19, next3 read 28 against a wire
# 0.30), so a fast burn genuinely can cross the wall between sweeps while the integer still looks
# fine, and the default gate will not probe it. The residual is named in the research doc; what
# this test pins is the half that IS in our hands — once a `rejected` verdict is in the row, it
# outranks the integer.
ca.WIRE_FORCE = True
r = probe(limits(weekly=97),
          {"7d_util": 1.0, "7d_status": "rejected", "5h_util": 0.1,
           "5h_status": "allowed", "status": "rejected", "http": 429})
assert CALLS == [1], "with --wire the probe must fire even away from the wall"
assert ca._excluded(r, R) == "weekly-exhausted", ca._excluded(r, R)
assert ca.score_general(r, cfg)[1] == "weekly-exhausted", ca.score_general(r, cfg)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-3: the control, and the cost gate -------------------------------------------------------
# Away from the wall the probe must not fire AT ALL — the whole cost argument rests on it. Passes
# pre-fix on the verdict and post-fix on both; the CALLS assert is what gives it power.

@test "W-3: away from the wall the wire is never called and every verdict is unchanged" {
  run python3 -c "$LOAD"'
import json as J
r = probe(limits(session=5, weekly=11))
assert CALLS == [], "a probe fired below WIRE_NEAR_WALL — the cost gate is open"
assert "wire" not in r and "wire_miss" not in r, r
assert ca._excluded(r, R) is None
assert abs(ca.weekly_headroom(r) - 0.89) < 1e-9, ca.weekly_headroom(r)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-4: the gate itself ----------------------------------------------------------------------
# WIRE_NEAR_WALL is the band where the integer is AMBIGUOUS, and nothing else earns the call.

@test "W-4: wire_wanted fires only at/above the wall, on --wire, and never under the kill switch" {
  run python3 -c "$LOAD"'
W = ca.WIRE_NEAR_WALL
assert ca.wire_wanted(5, 11) is False
assert ca.wire_wanted(5, W) is True,  "the weekly meter at the wall must earn the read"
assert ca.wire_wanted(W, 11) is True, "the 5h meter at the wall must too — it clamps the same way"
assert ca.wire_wanted(None, None) is False, "no reading is not a reason to spend a call"
assert ca.wire_wanted(5, 11, force=True) is True
os.environ["CC_ACCOUNTS_WIRE"] = "off"
assert ca.wire_wanted(5, 100) is False and ca.wire_wanted(5, 100, force=True) is False, \
    "the kill switch must outrank --wire"
del os.environ["CC_ACCOUNTS_WIRE"]
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-5: overage the integer cannot represent -------------------------------------------------
# `percent` maxes at 100, so a 5h window measured at 1.02 and a 5h window at exactly 1.00 are the
# same cell. The unclamped fraction is what the 5h cutoff should be reading.

@test "W-5: a wire 5h above 1.0 is carried unclamped and refuses the row" {
  run python3 -c "$LOAD"'
r = probe(limits(session=100, weekly=50),
          {"5h_util": 1.02, "5h_status": "rejected", "7d_util": 0.5,
           "7d_status": "allowed", "status": "rejected", "http": 429})
assert r["session_pct"] == 100, "the endpoint clamp is preserved in the recorded meter"
assert r["wire"]["5h_util"] == 1.02, r
assert ca._excluded(r, R) == "5h-cutoff", ca._excluded(r, R)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-6: the renderer says WHICH of the three states it is ------------------------------------
# The bullet used to read `weekly **LIMITED** (100%)` for all three. Each now names its own state
# in plain words, answer first, and says who decided it — the server or our rounding (2026-10-03:
# the `ʷ` cell suffix that used to carry this was a code the operator could not read at a glance).

@test "W-6: the three 100%-states render as three different plain sentences, no coded marks" {
  run python3 -c "$LOAD"'
import io, contextlib
WIN_OPEN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
def readout(wire):
    r = probe(limits(weekly=100), wire)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ca.render_readout([r], cfg, WIN_OPEN, False)
    return buf.getvalue(), r
allowed, r1 = readout({"7d_util": 0.99, "7d_status": "allowed_warning", "5h_util": 0.05,
                       "5h_status": "allowed", "status": "allowed_warning", "http": 200})
assert "was **not out of weekly quota**" in allowed and "server read 99% used" in allowed, allowed
assert "was still accepting work" in allowed and "still accepts work" not in allowed, allowed
assert "of the week left" not in allowed and "5-hour window" not in allowed, \
    "no headroom figure off a two-decimal reading: %r" % allowed
row = next(l for l in allowed.splitlines() if l.startswith("|") and "next3" in l)
assert "| 99% |" in row, "a still-allowed weekly cell is the server s whole percent, never 100%%: %r" % row
rejected, _ = readout({"7d_util": 1.0, "7d_status": "rejected", "5h_util": 0.05,
                       "5h_status": "allowed", "status": "rejected", "http": 429})
assert "is **out of weekly quota**, confirmed by Anthropic" in rejected, rejected
blind, r3 = readout(None)
assert "shows 100% weekly, **not confirmed**" in blind and "rounds up" in blind, blind
for out in (allowed, rejected, blind):
    assert "ʷ" not in out and "wire" not in out.replace("--wire", ""), "no coded marks or jargon: %r" % out
assert allowed != rejected != blind, "three states, three renderings"
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-9: nothing on screen needs a legend ------------------------------------------------------
# `ʷ` shipped as a bare glyph, then gained a footnote legend (2026-09-20); the operator still could
# not read it at a glance (2026-10-03). The marker and its legend are gone — the per-account
# sentence carries the verdict — and an account away from the wall prints no verdict at all.

@test "W-9: no ʷ marker and no legend at the wall; no verdict sentence away from it" {
  run python3 -c "$LOAD"'
import io, contextlib
WIN_OPEN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
def readout(lim, wire):
    r = probe(lim, wire)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ca.render_readout([r], cfg, WIN_OPEN, False)
    return buf.getvalue()
marked = readout(limits(weekly=100),
                 {"7d_util": 0.99, "7d_status": "allowed_warning", "5h_util": 0.05,
                  "5h_status": "allowed", "status": "allowed_warning", "http": 200})
assert "ʷ" not in marked and "rate-limit headers" not in marked, marked
assert "not out of weekly quota" in marked, marked
plain = readout(limits(session=5, weekly=11), None)
assert "ʷ" not in plain and "weekly quota" not in plain and "not confirmed" not in plain, plain
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-7: a MISS is not a permissive answer ----------------------------------------------------
# Transport failure / missing header set. The verdict must be exactly what the endpoint alone
# would have given — never softer, because "we could not read it" is not "the server allows it".

@test "W-7: a wire miss at 100 degrades to the endpoint verdict, not to routable" {
  run python3 -c "$LOAD"'
r = probe(limits(weekly=100), None)
assert CALLS == [1], "the probe was wanted at 100 and must have been attempted"
assert r.get("wire_miss") is True and "wire" not in r, r
assert ca.weekly_headroom(r) == 0.0, ca.weekly_headroom(r)
assert ca.score_general(r, cfg)[1] == "weekly-exhausted", ca.score_general(r, cfg)
assert ca.wire_rejects(r, "7d") is False, "an unread wire must not manufacture a refusal either"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-8: the series records the wire BESIDE the meters, never in place of them -----------------
# `_rolled` calls any meter decrease a window reset. Writing a wire 99 into weekly_pct where the
# prior row holds an endpoint 100 would fabricate a roll and corrupt every burn fit downstream.

@test "W-8: the utilization series keeps weekly_pct endpoint-sourced and adds wire_* beside it" {
  run python3 -c "$LOAD"'
r = probe(limits(weekly=100),
          {"7d_util": 0.99, "7d_status": "allowed_warning", "5h_util": 0.05,
           "5h_status": "allowed", "status": "allowed_warning", "http": 200})
p = os.environ["CC_UTIL_LOG"]
ca.record_utilization([r], path=p, min_interval_s=0)
rec = json.loads(open(p).read().strip().splitlines()[-1])
assert rec["weekly_pct"] == 100, rec
assert rec["wire_7d_util"] == 0.99 and rec["wire_7d_status"] == "allowed_warning", rec
assert rec["wire_5h_util"] == 0.05, rec
prev = dict(rec); prev["weekly_pct"] = 100
assert ca._rolled(prev, rec, "weekly_reset_at", "weekly_pct") is False, \
    "two adjacent rows at the same endpoint meter must never read as a window roll"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-10: the EPS_H rollover grace is a RECOVERY allowance only (FLEET_V2 W6 D1.7) ------------
# 2026-09-30 06:16-06:19Z: next2 wire-rejected on 5h with its reset 0.186-0.231 h away. The grace
# (reset < EPS_H 0.25 h => routable) kept it as the ONLY dispatch candidate, and all three fresh
# workers hit the limit within 3 s. A fresh fire starts now, so every non-recovery lane refuses a
# wire-rejected 5h window while its reset is still ahead; the recovery lane keeps the grace.

@test "W-10: a wire-5h-rejected account inside EPS_H is refused for dispatch, kept for recovery" {
  run python3 -c "$LOAD"'
from datetime import datetime, timezone, timedelta
W = {"5h_util": 1.01, "5h_status": "rejected", "7d_util": 0.4, "7d_status": "allowed",
     "status": "rejected", "http": 429}
at = (datetime.now(timezone.utc) + timedelta(hours=0.2)).isoformat()
r = dict(acct="next2", auth="ok", session_pct=100, session_reset_h=0.2, session_reset_at=at,
         weekly_pct=40, weekly_reset_h=40.0, fable_pct=0, fable_reset_h=40.0, k=0, k_work=0,
         credits_on=False, wire=W)
assert 0 < 0.2 < R["EPS_H"], R["EPS_H"]
assert ca._excluded(r, R) == "5h-cutoff", ca._excluded(r, R)
assert ca.score_general(r, cfg)[1] == "5h-cutoff", ca.score_general(r, cfg)
assert ca._excluded(r, R, recovery=True) != "5h-cutoff", ca._excluded(r, R, recovery=True)
# The ABSOLUTE stamp decides, not the as-of-the-sweep countdown: a row whose cached countdown
# still reads 0.2 h but whose reset has already passed is no longer refused on the stale wire.
past = dict(r, session_reset_at=(datetime.now(timezone.utc) - timedelta(minutes=1)).isoformat())
assert ca._excluded(past, R) != "5h-cutoff", ca._excluded(past, R)
# Reset unknown => refused, as before, on every lane.
unk = dict(r, session_reset_at=None, session_reset_h=None)
assert ca._excluded(unk, R) == "5h-cutoff" and ca._excluded(unk, R, recovery=True) == "5h-cutoff"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-10: the board draws the three 100%-states IN THE BAR (operator, 2026-10-01) -------------
# The board showed refused and 99%-still-allowed accounts as the same solid red bar at `100%`, with
# the difference only in six lines of footnote prose. The bar and percent now carry it: refused =
# solid bar at 100%, still-allowed = the server's WHOLE wire percent over a bar whose last cell is never
# full. The board ALSO prints the plain sentence (2026-10-03): the bar alone left "confirmed out"
# readable only from a missing line, which the operator could not read.

@test "W-10: board — refused is solid and says confirmed, 99%-allowed keeps a sliver and says not out" {
  run env CC_BOARD_COLOR=off python3 -c "$LOAD"'
import io, contextlib
WIN_OPEN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
def board(wire):
    r = probe(limits(weekly=100), wire)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        ca.render_readout([r], cfg, WIN_OPEN, False, narrow=True)
    return buf.getvalue()
refused = board({"7d_util": 1.0, "7d_status": "rejected", "5h_util": 0.05,
                 "5h_status": "allowed", "status": "rejected", "http": 429})
allowed = board({"7d_util": 0.99, "7d_status": "allowed_warning", "5h_util": 0.05,
                 "5h_status": "allowed", "status": "allowed_warning", "http": 200})
assert "▆▆▆▆▆▆▆▆" in refused and "100%" in refused, refused
assert "▆▆▆▆▆▆▆▁" in allowed, "a spendable bar must not read full: %r" % allowed
row = next(l for l in allowed.splitlines() if "next3" in l and "▆" in l)
assert " 99%" in row and "≥99%" not in row and "100%" not in row, row
blind = board(None)
brow = next(l for l in blind.splitlines() if "next3" in l and "▄" in l)
assert "▄▄▄▄▄▄▄▄" in brow and "≥99%" in brow and "100%" not in brow, \
    "an unconfirmed 100%% must be half height and read >=99%%, never 100%%: %r" % brow
rrow = next(l for l in refused.splitlines() if "next3" in l and "▆" in l)
assert "▄" not in rrow and " 100%" in rrow, rrow
flat = lambda t: " ".join(t.split())
assert "next3 is out of weekly quota, confirmed by Anthropic" in flat(refused), refused
assert "next3 was not out of weekly quota" in flat(allowed), allowed
for out in (refused, allowed):
    assert "ʷ" not in out and "rate-limit headers" not in out, out
# Whole cells round 94% up to 8; the cap keeps a still-spendable bar one cell short of full.
assert ca.board_bar(94.0) == "▆▆▆▆▆▆▆▁", ca.board_bar(94.0)
assert ca.board_bar(100.0, True) == "▆▆▆▆▆▆▆▆"
assert ca.board_bar(100.0) == "▄▄▄▄▄▄▄▄", "no server verdict: half height, not solid"
assert (ca.pct_text(100.0, True), ca.pct_text(99.0, False), ca.pct_text(100.0, None)) \
    == ("100%", "99%", "≥99%")
assert ca.pct_rgb(100.0, True) == ca.RED and ca.pct_rgb(99.0, False) == ca.NEAR_WALL_RGB \
    and ca.pct_rgb(100.0, None) == ca.GRAY
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- W-11: CONTROL — the 2026-10-06 incident, replayed from the series verbatim ---------------
# 06:01:45Z the sweep recorded next3 at endpoint 100 / wire 0.99 allowed_warning with 11 live
# sessions; the board printed "99.0%" and "still accepts work (about 1% of the week left, roughly
# 5% of one 5-hour window)", and about a minute later sessions on next3 were refused. The wire is
# rounded to hundredths and capped at 0.99 until the server refuses
# (docs/research/sessionstart-readout-2026-10-06/README.md, R2), so 0.99 is the server's whole
# percent: no tenth, and no headroom figure (the true remainder is anywhere from ~1pp down to 0).
# A snapshot is not a present tense: the note carries the read's clock time and the account's load.
# FAILS PRE-FIX on checks 1-4; checks 5-6 and the colour pin the 2026-10-01/03 rulings.

@test "W-11: CONTROL replay of the 06:01:45Z next3 row: server's whole percent, no headroom figure, read time and load" {
  run env CC_BOARD_COLOR=off python3 -c "$LOAD"'
import re, time, unicodedata
from datetime import datetime, timezone, timedelta
# VERBATIM, ~/.claude/logs/account-utilization.jsonl, the next3 row at ts 2026-10-06T06:01:45.
REC = json.loads(r"""{"ts":"2026-10-06T06:01:45.738874+00:00","acct":"next3","k":11,"k_work":4,"k_src":"work","session_pct":7,"weekly_pct":100,"fable_pct":3,"session_reset_at":"2026-10-06T07:50:00.443077+00:00","weekly_reset_at":"2026-10-06T12:00:00.443099+00:00","wire_5h_util":0.06,"wire_7d_util":0.99,"wire_5h_status":"allowed","wire_7d_status":"allowed_warning","credits_on":false,"credits_used":0.0,"auth":"ok","stale":false}""")
AGE_S = 79
P = datetime.fromisoformat
# The series row is flat; the renderer takes the collect() shape. Rebuild it (wire_* -> wire{})
# and rebase every absolute stamp so the read is AGE_S old NOW while each countdown is unchanged.
shift = (datetime.now(timezone.utc) - timedelta(seconds=AGE_S)) - P(REC["ts"])
def build(**over):
    r = {k: REC[k] for k in ("acct", "k", "k_work", "session_pct", "weekly_pct", "fable_pct",
                             "credits_on", "credits_used", "auth")}
    r.update(session_reset_at=(P(REC["session_reset_at"]) + shift).isoformat(),
             weekly_reset_at=(P(REC["weekly_reset_at"]) + shift).isoformat(),
             session_reset_h=(P(REC["session_reset_at"]) - P(REC["ts"])).total_seconds() / 3600,
             weekly_reset_h=(P(REC["weekly_reset_at"]) - P(REC["ts"])).total_seconds() / 3600,
             wire={w: REC["wire_" + w] for w in ("5h_util", "7d_util", "5h_status", "7d_status")})
    r.update(over)
    return r
# The read time comes from the cache ts field (_quota_age_s), never an mtime.
json.dump({"ts": time.time() - AGE_S, "rows": []}, open(cfg["cache_file"], "w"))
# Local clock, as the board header prints it; two candidates absorb a minute boundary on a slow box.
clocks = {(datetime.now() - timedelta(seconds=s)).strftime("%H:%M") for s in (AGE_S, AGE_S + 10)}
WIN_OPEN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
cells = lambda s: sum(2 if unicodedata.east_asian_width(c) in ("W", "F") else 1 for c in s)
bad = []
for label, r in (("k_work=4", build()), ("k_work=None", build(k_work=None))):
    v, ex = ca.board_eff(r, "weekly_pct")
    assert ex is False, "the replay must land in the nearly-out state: %r" % ((v, ex),)
    if ca.pct_rgb(v, ex) != ca.NEAR_WALL_RGB: bad.append((label, "near-wall orange lost", ca.pct_rgb(v, ex)))
    for narrow in (True, False):
        surf = label + (" board" if narrow else " readout")
        out = "\n".join(ca.readout_lines([r], cfg, WIN_OPEN, True, narrow=narrow))
        lines = out.splitlines()
        ri = next(i for i, l in enumerate(lines) if "next3" in l and ("▆" in l or "▄" in l or l.startswith("|")))
        row = lines[ri]
        ni = next(i for i in range(ri + 1, len(lines)) if "next3" in lines[i] and "week" in lines[i])
        nl, j = [lines[ni]], ni + 1
        while narrow and j < len(lines) and lines[j].startswith("   "):
            nl.append(lines[j]); j += 1
        note = " ".join(" ".join(nl).split())
        # (1) a two-decimal read never prints a tenth, anywhere on either surface
        if re.search(r"\b99\.\d%", out): bad.append((surf, "tenth printed", re.findall(r"\b99\.\d%", out)))
        # (2) the cell is the server s whole percent; only a refusal prints 100%, only an unread meter >=99%
        if not re.search(r"(^|[ |])99%", row) or "≥99%" in row or "100%" in row:
            bad.append((surf, "cell is not the server s whole 99%", row))
        # (3) no headroom figure and no present-tense acceptance off the snapshot
        if re.search(r"\d+% of (the week|one 5-hour window)", note) or "still accepts work" in note:
            bad.append((surf, "headroom figure or present tense in note", note))
        # (4) the read carries its clock time and the load on the account
        if not any(c in note for c in clocks): bad.append((surf, "no read time", note, sorted(clocks)))
        if not re.search(r"\b11 live session", note): bad.append((surf, "no live-session count", note))
        # (5) RULINGS 2026-10-01/03: inline state, last cell open, not the unconfirmed half-height bar
        if narrow and ("▆▆▆▆▆▆▆▁" not in row or "▄" in row):
            bad.append((surf, "bar: spendable last cell must stay open", row))
        # (6) the note still fits the 76-cell board budget
        if narrow and any(cells(l) > 76 for l in lines):
            bad.append((surf, "line over 76 cells", [l for l in lines if cells(l) > 76]))
for b in bad: print("FAIL", b)
assert not bad, "%d checks failed" % len(bad)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
