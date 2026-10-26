#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# THE REBALANCER'S LANDING BAND (C1): bin/claude-accounts rebal_band_row / --rebal-band.
# Design: docs/research/account-rotation-100p-2026-10-24/REPORT.md §4 C1 and the §6 wave A row, whose
# acceptance is pinned by R1: against the 2026-10-24 snapshot it names next4 and next3 as sinks.
#
# THE SNAPSHOT IS THE REAL LEDGER, not invented paces. SNAP below is ~/.claude/logs/account-utilization.jsonl
# for the 48.5 h before 2026-10-25T05:27Z (the report's §2 "right now"), reduced to the samples where an
# account's weekly_pct or its weekly reset changed: "<min before T0>:<weekly_pct>:<reset h from T0>". The
# seeder replays it on a 7-minute grid (the real cadence is ~6.9 min) shifted so that T0 is now. next and
# next2 roll their week inside the window, exactly as they did. Rows: acct session_pct session_reset_h points…
#
# HERMETIC: HOME, the SSOT, the cache and the ledger live under BATS_TEST_TMPDIR; no network. Interpreter is
# the deployment one, /usr/bin/python3. Each rule case that has a mutant re-runs against a copy with that one
# site changed and must die; an anchor not found exactly once fails loudly rather than passing vacuously.

SNAP='next 65 1.05 2909:21:-1.45 2880:22:-1.45 2865:23:-1.45 2849:24:-1.45 2826:25:-1.45 2788:26:-1.45 2570:27:-1.45 2232:28:-1.45 2179:29:-1.45 2134:30:-1.45 1902:31:-1.45 1783:32:-1.45 1763:33:-1.45 1723:34:-1.45 1696:35:-1.45 1633:36:-1.45 1607:37:-1.45 1587:38:-1.45 1560:39:-1.45 1541:40:-1.45 1494:41:-1.45 1449:42:-1.45 1443:43:-1.45 1436:44:-1.45 1423:45:-1.45 1416:46:-1.45 1403:47:-1.45 1390:48:-1.45 1364:49:-1.45 1331:50:-1.45 1298:51:-1.45 1246:52:-1.45 1137:53:-1.45 1015:54:-1.45 872:55:-1.45 762:56:-1.45 689:57:-1.45 676:58:-1.45 670:59:-1.45 663:60:-1.45 650:61:-1.45 637:62:-1.45 601:63:-1.45 581:64:-1.45 575:65:-1.45 561:66:-1.45 555:67:-1.45 541:68:-1.45 515:69:-1.45 508:70:-1.45 495:71:-1.45 483:72:-1.45 469:73:-1.45 463:74:-1.45 456:75:-1.45 449:76:-1.45 443:77:-1.45 429:78:-1.45 416:79:-1.45 403:80:-1.45 383:81:-1.45 376:82:-1.45 365:83:-1.45 351:84:-1.45 337:85:-1.45 304:86:-1.45 265:87:-1.45 215:88:-1.45 202:89:-1.45 196:90:-1.45 189:91:-1.45 182:92:-1.45 176:93:-1.45 169:94:-1.45 156:95:-1.45 150:96:-1.45 143:97:-1.45 128:98:-1.45 110:99:-1.45 86:0:166.55 72:2:166.55 59:3:166.55 34:4:166.55 7:5:166.55
next2 1 3.55 2909:65:-18.45 2894:66:-18.45 2880:67:-18.45 2865:68:-18.45 2857:69:-18.45 2834:70:-18.45 2818:71:-18.45 2803:72:-18.45 2736:73:-18.45 2675:74:-18.45 2578:75:-18.45 2552:76:-18.45 2492:77:-18.45 2384:78:-18.45 2276:79:-18.45 2232:80:-18.45 2209:81:-18.45 2172:82:-18.45 2021:83:-18.45 1932:84:-18.45 1918:85:-18.45 1909:86:-18.45 1902:87:-18.45 1894:88:-18.45 1872:89:-18.45 1857:90:-18.45 1841:91:-18.45 1795:92:-18.45 1789:93:-18.45 1769:94:-18.45 1749:95:-18.45 1696:96:-18.45 1669:97:-18.45 1641:98:-18.45 1469:99:-18.45 1105:0:149.55 801:1:149.55 228:2:149.55
next3 2 1.88 2909:12:54.55 1683:13:54.55 1370:14:54.55 1351:16:54.55 716:17:54.55 143:18:54.55
next4 1 4.72 2909:52:3.55 2865:53:3.55 2366:54:3.55 2358:55:3.55 2351:56:3.55 2336:57:3.55 2328:58:3.55 2116:59:3.55 1887:60:3.55 1879:61:3.55 1872:62:3.55 1841:63:3.55 1834:64:3.55 1613:65:3.55 1370:66:3.55 670:67:3.55 656:68:3.55 630:70:3.55 609:71:3.55 588:72:3.55 561:73:3.55 528:74:3.55 490:75:3.55 463:76:3.55 389:77:3.55 311:78:3.55 242:79:3.55 156:80:3.55 79:81:3.55 52:82:3.55 13:83:3.55'

setup() {
  command -v jq >/dev/null || skip "jq required"
  unset CC_BATS_ACTIVE CC_SHED_BAND_MAX_AGE_S CC_ROUTE_PROJ CC_ROUTE_PROJ_LOOKAHEAD_H
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PY=/usr/bin/python3
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export CA_BIN="$REPO/bin/claude-accounts"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json" CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG" CLAUDE_ACCOUNTS_LASTGOOD="$BATS_TEST_TMPDIR/lastgood.json"
  export CLAUDE_ACCOUNTS_LOG="$BATS_TEST_TMPDIR/claude-accounts.log"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl" CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
  export CC_ROUTE_RECORDS_DIR="$BATS_TEST_TMPDIR/route-records"
  : > "$CC_UTIL_LOG"
  "$PY" - "$CA_CFG" "$CACHE" "$REPO/accounts.json" <<'PY'
import json, sys
cfg_path, cache, real = sys.argv[1:4]
r = json.load(open(real))
acct = lambda n, d: {"name": n, "config_dir": "/tmp/ca-rebal-test-nonexistent-" + d, "launcher": "claude-" + n,
                     "email": "t@example.com", "mailbox": "t@example.com", "dia_profile": "T"}
json.dump({"keychain_account": "test", "oauth_scopes": "x",
           "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
           "user_agent": "test", "claude_bin": "/nonexistent/claude", "model_config_ssot": "/nonexistent/m.yaml",
           "dia_local_state": "/nonexistent/LS", "cache_file": cache,
           "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"], "cache_grace_s": r["cache_grace_s"],
           "login_warn_h": r["login_warn_h"], "frontier": r["frontier"], "router": r["router"],
           "accounts": [acct("next", "a"), acct("next2", "b"), acct("next3", "c"), acct("next4", "d")]},
          open(cfg_path, "w"))
PY
}

# seed_snapshot → the cache as a sweep at T0 would have written it, and SNAP replayed into the ledger
seed_snapshot() { SNAP="$SNAP" "$PY" - <<'PY'
import importlib.machinery, json, os, time
from datetime import datetime, timezone
ca = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).load_module()
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
now = time.time(); iso = lambda t: datetime.fromtimestamp(t, timezone.utc).isoformat()
rows, led = [], []
for line in os.environ["SNAP"].splitlines():
    a, s5, s5h, *pts = line.split()
    pts = sorted((int(m), int(w), float(rh)) for m, w, rh in (p.split(":") for p in pts))[::-1]
    grid = sorted(set(range(pts[0][0], -1, -7)) | {m for m, _w, _r in pts} | {0}, reverse=True)
    for m in grid:
        _m, w, rh = [p for p in pts if p[0] >= m][-1]
        t = now - m * 60.0
        led.append((t, {"ts": iso(t), "acct": a, "k": 0, "k_work": 1, "session_pct": int(s5), "weekly_pct": w,
                        "weekly_reset_at": iso(now + rh * 3600.0), "credits_on": False, "auth": "ok", "stale": False}))
    _m, w, rh = pts[-1]
    rows.append({"acct": a, "auth": "ok", "k": 0, "k_work": 1, "session_pct": float(s5), "session_reset_h": float(s5h),
                 "weekly_pct": float(w), "weekly_reset_h": rh, "weekly_reset_at": iso(now + rh * 3600.0),
                 "fable_pct": 5, "fable_reset_h": rh, "credits_on": False})
json.dump({"ts": now, "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None, "rows": rows}, open(os.environ["CACHE"], "w"))
with open(os.environ["CC_UTIL_LOG"], "w") as fh:
    for _t, e in sorted(led, key=lambda x: x[0]):
        fh.write(json.dumps(e) + "\n")
PY
}

LOAD='
import importlib.machinery, os, json, math, time
from datetime import datetime, timezone
ca = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).load_module()
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"])); R = cfg["router"]
NOW = time.time()
T = ca.rebal_bias_table(None)
def iso(t): return datetime.fromtimestamp(t, timezone.utc).isoformat()
def row(used=50.0, reset_h=24.0, ewma=0.5, flat=0.5, s5=10.0, **kw):
    r = {"acct": "next3", "weekly_pct": used, "weekly_reset_at": iso(NOW + reset_h * 3600.0), "weekly_reset_h": reset_h,
         "burn_wk_ewma_ph": ewma, "burn_wk_flat_ph": flat, "session_pct": s5, "session_reset_h": 2.0, "credits_on": False}
    r.update(kw); return r
def v(r, table=T, facts=None): return ca.rebal_band_row(r, R, table, facts, NOW)
'

# mutate <subject> <out> <old> <new> → a copy with exactly one site changed; rc 2 if the anchor is not unique
mutate() { "$PY" - "$@" <<'PY'
import sys
src, out, old, new = sys.argv[1:5]
s = open(src).read()
n = s.count(old)
if n != 1:
    sys.exit("mutant anchor found %d times, not once: %r" % (n, old))
open(out, "w").write(s.replace(old, new))
PY
}

@test "R1 acceptance: the 2026-10-24 snapshot names next4 then next3 as sinks, live and static bias alike" {
  seed_snapshot
  for mode in live static; do
    run "$PY" "$CA_BIN" --rebal-band --json --bias "$mode" --max-wait 0
    [ "$status" -eq 0 ] || { echo "$mode rc $status: $output"; false; }
    printf '%s\n' "$output" | jq -e '
      .sinks == ["next4", "next3"]
      and (.accounts[] | select(.acct == "next4") | .verdict == "sink" and .strand_net_pp >= 4 and .reset_h < 4
             and .landing_net_pct < 97 and .bias_pp > 0 and .bias_pp < .strand_pp)
      and (.accounts[] | select(.acct == "next3") | .verdict == "sink" and .strand_net_pp >= 40
             and .sink_cap_pph > 0.5 and .sink_cap_pph < 1.5)
      and (.accounts[] | select(.acct == "next2") | .verdict == "neutral" and .reset_h > 96)
      and (.accounts[] | select(.acct == "next") | .verdict != "sink")
      and ([.bias.table[].src] | unique) == ["static"]
      and .knobs == {"floor_pp": 4, "horizon_h": 96, "target_pct": 97}' >/dev/null || { echo "$mode: $output"; false; }
  done
}

@test "R2 read-only: --rebal-band leaves the cache and the ledger byte-identical, and the text form names the sinks" {
  seed_snapshot
  before=$(shasum "$CACHE" "$CC_UTIL_LOG")
  run "$PY" "$CA_BIN" --rebal-band --max-wait 0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"sinks: next4, next3"* ]] || { echo "$output"; false; }
  [ "$(shasum "$CACHE" "$CC_UTIL_LOG")" = "$before" ]
}

@test "R3 cache-only: no cache is exit 3 and wait_data, get_data asked for max_wait 0; a bad --bias is 64" {
  run "$PY" "$CA_BIN" --rebal-band --json --max-wait 0
  [ "$status" -eq 3 ] || { echo "rc $status: $output"; false; }
  [ "$(printf '%s\n' "$output" | tail -1 | jq -c .)" = '{"v":1,"wait_data":true}' ] || { echo "$output"; false; }
  [ ! -e "$CACHE" ]
  run "$PY" -c "$LOAD"'
seen = {}
def spy(cfg, **kw):
    seen.update(kw); raise ca.CacheOnlyUnavailable("spy")
ca.get_data = spy
assert ca.cmd_rebal_band(["--rebal-band", "--bias", "static"], cfg) == ca.PLACE_EXIT_WAIT_DATA
assert seen.get("max_wait") == 0 and seen.get("max_age") == 1200, seen
assert ca.cmd_rebal_band(["--rebal-band", "--bias", "fresh"], cfg) == 64
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "R4 the bias table: a live bucket with >= 5 windows replaces its static point, a thin one does not; interpolation anchors at 0" {
  run "$PY" -c "$LOAD"'
assert [(h, s) for h, _v, s in T] == [(6.0, "static"), (12.0, "static"), (24.0, "static"), (48.0, "static")]
t = ca.rebal_bias_table({"buckets": [{"h": 96.0, "n": 22, "bias": 25.0}, {"h": 48.0, "n": 4, "bias": 99.0},
                                     {"h": 24.0, "n": 9, "bias": 10.0}, {"h": 12.0, "n": 9, "bias": None}]})
assert [(h, round(b, 2), s) for h, b, s in t] == [(6.0, 3.39, "static"), (12.0, 5.52, "static"),
                                                 (24.0, 10.0, "live"), (48.0, 15.25, "static"), (96.0, 25.0, "live")], t
assert ca.rebal_bias_at(0.0, T) == 0.0
assert abs(ca.rebal_bias_at(3.0, T) - 3.39 / 2) < 1e-9
assert abs(ca.rebal_bias_at(36.0, T) - (8.45 + 15.25) / 2) < 1e-9
assert ca.rebal_bias_at(90.0, T) == 15.25 and ca.rebal_bias_at(5.0, []) == 0.0
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "R5 the bias decides a borderline sink: 7 pp raw at 12 h is 1.48 pp net, neutral" {
  run "$PY" -c "$LOAD"'
tok, f = v(row(used=81.0, reset_h=12.0, ewma=1.0, flat=1.0))
assert (tok, f["strand_pp"], f["bias_pp"]) == ("neutral", 7.0, 5.52), (tok, f)
assert v(row(used=71.0, reset_h=12.0, ewma=1.0, flat=1.0))[0] == "sink"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "R5m mutant (bias not subtracted): the borderline account reads sink: dies" {
  mutate "$CA_BIN" "$BATS_TEST_TMPDIR/ca-m5" '    landing_net = landing + bias ' '    landing_net = landing '
  CA_BIN="$BATS_TEST_TMPDIR/ca-m5" run "$PY" -c "$LOAD"'
assert v(row(used=81.0, reset_h=12.0, ewma=1.0, flat=1.0))[0] == "neutral"; print("OK")'
  [ "$status" -ne 0 ] || { echo "the mutant survived: $output"; false; }
}

@test "R6 the horizon: a big strand 100 h out is neutral, the same at 90 h is a sink" {
  run "$PY" -c "$LOAD"'
assert v(row(used=10.0, reset_h=100.0, ewma=0.1, flat=0.1))[0] == "neutral"
assert v(row(used=10.0, reset_h=90.0, ewma=0.1, flat=0.1))[0] == "sink"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "R6m mutant (no horizon check): the 100 h account reads sink: dies" {
  mutate "$CA_BIN" "$BATS_TEST_TMPDIR/ca-m6" '    if wrh <= REBAL_HORIZON_H and strand_net' '    if strand_net'
  CA_BIN="$BATS_TEST_TMPDIR/ca-m6" run "$PY" -c "$LOAD"'
assert v(row(used=10.0, reset_h=100.0, ewma=0.1, flat=0.1))[0] == "neutral"; print("OK")'
  [ "$status" -ne 0 ] || { echo "the mutant survived: $output"; false; }
}

@test "R7 the FAST pace sets the landing: ewma 0.1 with flat 2.0 at 40 % / 40 h walls, a donor-7d with its time to wall" {
  run "$PY" -c "$LOAD"'
tok, f = v(row(used=40.0, reset_h=40.0, ewma=0.1, flat=2.0))
assert tok == "donor-7d" and f["landing_pct"] == 120.0 and f["ttw_hi_h"] == 30.0 and f["landing_lo_pct"] == 44.0, (tok, f)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "R7m mutant (the slow pace sets the landing): the walling account reads sink: dies" {
  mutate "$CA_BIN" "$BATS_TEST_TMPDIR/ca-m7" '    landing = pct + hi * wrh' '    landing = pct + lo * wrh'
  CA_BIN="$BATS_TEST_TMPDIR/ca-m7" run "$PY" -c "$LOAD"'
assert v(row(used=40.0, reset_h=40.0, ewma=0.1, flat=2.0))[0] == "donor-7d"; print("OK")'
  [ "$status" -ne 0 ] || { echo "the mutant survived: $output"; false; }
}

@test "R8 donor-5h, walled, credits and the unknown arms: none of them is ever a sink" {
  run "$PY" -c "$LOAD"'
sink = dict(used=10.0, reset_h=50.0, ewma=0.1, flat=0.1)
assert v(row(**sink))[0] == "sink"
assert v(row(s5=100.0, **sink))[0] == "donor-5h"
assert v(row(burn_5h_ewma_ph=80.0, s5=30.0, **sink))[0] == "donor-5h"
assert v(row(**dict(sink, used=100.0)))[0] == "walled"
tok, f = v(row(credits_on=True, **sink)); assert (tok, f.get("why")) == ("neutral", "credits-on"), (tok, f)
assert v(row(stale_quota=True, **sink))[0] == "unknown:level-stale"
assert v(row(**dict(sink, reset_h=-1.0)))[0] == "unknown:no-reset"
assert v(row(**dict(sink, ewma=None)))[0] == "unknown:pace-unknown"
assert v(row(**dict(sink, flat=None)))[0] == "unknown:pace-stale"
assert v(row(**dict(sink, ewma=float("nan"))))[0] == "unknown:pace-unknown"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "R9 sinks rank soonest reset first, donors soonest wall first" {
  run "$PY" -c "$LOAD"'
rows = [row(acct="a", used=10.0, reset_h=80.0, ewma=0.1, flat=0.1), row(acct="b", used=50.0, reset_h=10.0, ewma=0.5, flat=0.5),
        row(acct="c", used=60.0, reset_h=60.0, ewma=1.0, flat=1.0), row(acct="d", used=90.0, reset_h=60.0, ewma=1.0, flat=1.0)]
ca.get_data = lambda cfg, **kw: (rows, {}, None, None)
ca.apply_burn = lambda rows, cfg, samples=None: None
ca.strand_score = lambda s: {"buckets": []}
import io, contextlib
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    assert ca.cmd_rebal_band(["--rebal-band", "--json"], cfg) == 0
d = json.loads(buf.getvalue())
assert d["sinks"] == ["b", "a"] and d["donors"] == ["d", "c"], (d["sinks"], d["donors"])
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
