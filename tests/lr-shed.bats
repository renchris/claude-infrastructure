#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# THE LATE-BAND IDLE SHED (D2b, packet 76a584cc935b; LR_SUSTAINED_LOAD W16): the router's band verdict
# (bin/claude-accounts shed_band_row / --shed-band), the controller (scripts/limit-recover/lr-shed.py)
# and the move-lane seams it drives (bin/cc-lr CC_LR_MOVE_ORIGIN / _HOLD_FOCUSED / _QUEUED_OUT).
# Design: docs/research/lr-sustained-load-2026-10-20/impl/D2-warning-band-shedding.md §6, §8 T1, T2, T4,
# with the correctness review D1-D17 and the efficacy review E1-E10 (each case names the one it pins).
#
# RED AT THE PARENT TREE: no --shed-band, no shed_band_row, no lr-shed.py, no origin seam. Every case
# below that names a rule also names its MUTANT, and the mutant case re-runs the assertion against a
# copy of the subject with that one site changed: it must die (rule "Green in both arms"). A mutant
# whose anchor is not found exactly once fails loudly rather than passing vacuously.
#
# HERMETIC: HOME, LR_STATE_DIR, LR_RECON_ROOT and TMPDIR live under BATS_TEST_TMPDIR (run the suite with
# TMPDIR=/tmp); claude-accounts reads a seeded cache and a synthetic utilization ledger, never the
# network; the controller's claude-accounts, cc-lr and pager are recording stubs. Interpreters are the
# deployment ones: /usr/bin/python3 (3.9) for the controller and the router, /bin/bash (3.2) for cc-lr.

setup() {
  command -v jq >/dev/null || skip "jq required"
  unset CC_BATS_ACTIVE
  unset CC_ROUTE_SHED CC_ROUTE_SHED_LV_OPEN CC_ROUTE_SHED_TTW_OPEN_H CC_ROUTE_SHED_GUARD_H CC_SHED_BAND_MAX_AGE_S \
        LR_SHED LR_SHED_IDLE_S LR_SHED_MAX LR_SHED_COOLDOWN_S LR_SHED_NOW LR_SHED_STRAND_BREAKER LR_SHED_BAND_TO \
        LR_SHED_PLAN_TO LR_SHED_PLACE_TO LR_SHED_MOVE_TO LR_SHED_TICK_BUDGET_S LR_SHED_INFLIGHT_S LR_SHED_INFLIGHT_HARD_S \
        CLAUDE_CODE_SESSION_ID KITTY_WINDOW_ID CC_PANE_ID ITERM_SESSION_ID TMUX_PANE CC_ACCOUNTS_BIN \
        CC_LR_MOVE_ORIGIN CC_LR_MOVE_HOLD_FOCUSED CC_LR_MOVE_QUEUED_OUT CC_ROUTE_RECOVERY
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PY=/usr/bin/python3
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export LR_STATE_DIR="$HOME/.reso/limit-recover"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon" TMPDIR="$BATS_TEST_TMPDIR/tmp"
  SHED="$LR_STATE_DIR/shed"
  mkdir -p "$SHED" "$LR_RECON_ROOT/sessions" "$LR_STATE_DIR/move" "$TMPDIR"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export SUBJ_SHED="$REPO/scripts/limit-recover/lr-shed.py"
  export CA_BIN="$REPO/bin/claude-accounts"
  ca_fixture
  shed_stubs
}

# ── the router's fixture world (tests/account-recovery-lane.bats' shape) ─────────────────────────────
ca_fixture() {
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json" CACHE="$BATS_TEST_TMPDIR/cache.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG" CLAUDE_ACCOUNTS_LASTGOOD="$BATS_TEST_TMPDIR/lastgood.json"
  export CLAUDE_ACCOUNTS_LOG="$BATS_TEST_TMPDIR/claude-accounts.log"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl" CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
  export CC_ROUTE_RECORDS_DIR="$BATS_TEST_TMPDIR/route-records"
  : > "$CC_UTIL_LOG"
  "$PY" - "$CA_CFG" "$CACHE" "$REPO/accounts.json" "$BATS_TEST_TMPDIR/model-config.yaml" <<'PY'
import json, sys
cfg_path, cache, real, yaml = sys.argv[1:5]
r = json.load(open(real))
acct = lambda n, d: {"name": n, "config_dir": "/tmp/ca-shed-test-nonexistent-" + d, "launcher": "claude-" + n,
                     "email": "t@example.com", "mailbox": "t@example.com", "dia_profile": "T"}
json.dump({"keychain_account": "test", "oauth_scopes": "x",
           "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
           "user_agent": "test", "claude_bin": "/nonexistent/claude", "model_config_ssot": yaml,
           "dia_local_state": "/nonexistent/LS", "cache_file": cache,
           "cache_ttl_s": r["cache_ttl_s"], "lock_wait_s": r["lock_wait_s"], "cache_grace_s": r["cache_grace_s"],
           "login_warn_h": r["login_warn_h"], "frontier": r["frontier"], "router": r["router"],
           "accounts": [acct("next2", "b"), acct("next3", "c"), acct("next4", "d")]}, open(cfg_path, "w"))
PY
}

LOAD='
import importlib.machinery, os, json, math, time
from datetime import datetime, timezone
ca = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).load_module()
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"])); R = cfg["router"]
NOW = time.time()
def iso(t): return datetime.fromtimestamp(t, timezone.utc).isoformat()
def row(used=97.5, reset_h=10.0, ewma=1.0, flat=1.0, **kw):
    r = {"acct": "next3", "weekly_pct": used, "weekly_reset_at": iso(NOW + reset_h * 3600.0), "weekly_reset_h": reset_h,
         "burn_wk_ewma_ph": ewma, "burn_wk_flat_ph": flat, "credits_on": False}
    r.update(kw); return r
def v(r, facts=None): return ca.shed_band_row(r, R, facts, NOW)
'

# seed <acct:weekly_pct:reset_h:pace_pph>… → the shared cache, and a 48 h ledger at that pace per account
seed() { "$PY" - "$@" <<'PY'
import importlib.machinery, json, os, sys, time
from datetime import datetime, timezone
ca = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"]).load_module()
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
now = time.time(); iso = lambda t: datetime.fromtimestamp(t, timezone.utc).isoformat()
rows, led = [], []
for spec in sys.argv[1:]:
    a, wk, rh, pace = spec.split(":"); wk, rh, pace = float(wk), float(rh), float(pace)
    ra = iso(now + rh * 3600.0)
    rows.append({"acct": a, "auth": "ok", "k": 0, "k_work": 1, "session_pct": 5.0, "session_reset_h": 3.0,
                 "weekly_pct": wk, "weekly_reset_h": rh, "weekly_reset_at": ra, "fable_pct": 5,
                 "fable_reset_h": rh, "credits_on": False})
    for i in range(288, -1, -1):
        t = now - i * 600.0
        led.append((t, {"ts": iso(t), "acct": a, "k": 0, "k_work": 1, "session_pct": 5, "weekly_pct": round(max(0.0, wk - pace * i / 6.0), 2),
                        "weekly_reset_at": ra, "credits_on": False, "auth": "ok", "stale": False}))
json.dump({"ts": now, "cfg_key": ca._cfg_key(cfg), "no_heal": False,
           "window": {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True},
           "prev": None, "rows": rows}, open(os.environ["CACHE"], "w"))
with open(os.environ["CC_UTIL_LOG"], "w") as fh:
    for _t, e in sorted(led, key=lambda x: x[0]):
        fh.write(json.dumps(e) + "\n")
PY
}

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

# ── the controller's stubs ───────────────────────────────────────────────────────────────────────────
shed_stubs() {
  export LR_SHED_CA_BIN="$STUBS/claude-accounts" LR_SHED_CCLR_BIN="$STUBS/cc-lr" LR_SHED_PAGE_BIN="$STUBS/page"
  export STUB_DIR="$STUBS" BAND_JSON="$BATS_TEST_TMPDIR/band.json" PLAN_JSON="$BATS_TEST_TMPDIR/plan.json"
  BAND_RA=$(( $(date +%s) + 36000 )); export BAND_RA
  cat > "$LR_SHED_CA_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_DIR/ca.log"
case " $* " in
  *" --shed-band "*) [ -z "${CA_SLEEP:-}" ] || sleep "$CA_SLEEP"; cat "$BAND_JSON"; exit "${CA_RC:-0}" ;;
  *" --place "*)
    mv=""; prev=""; for a in "$@"; do [ "$prev" = --movers ] && mv="$a"; prev="$a"; done
    /usr/bin/python3 -c 'import json,os,sys
m=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
alt=os.environ.get("PLACE_ALT","")
out={}
for i,x in enumerate(m):
    out[x["sid"]]={"acct": (alt if alt and i % 2 else os.environ.get("PLACE_TO","next2")), "reason":"placed","eta_s":None,"weight":1}
print(json.dumps(out))' "$mv"; exit 0 ;;
esac
exit 64
STUB
  cat > "$LR_SHED_CCLR_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_DIR/cclr.log"
case "$1" in
  plan) cat "$PLAN_JSON"; exit 0 ;;
  move)
    case " $* " in *" --dry-run "*) echo "DRY RUN"; exit 0 ;; esac
    env | grep -E '^(CC_LR_MOVE_ORIGIN|CC_LR_MOVE_HOLD_FOCUSED|LR_MOVE_CARRY_DRAFT|LR_DEAD_SOURCE_RELEASE|CC_LR_MOVE_GOAL_HOLD|CLAUDE_CODE_SESSION_ID|KITTY_WINDOW_ID|CC_PANE_ID)=' \
      | sort | tr '\n' ' ' >> "$STUB_DIR/cclr.env"; echo >> "$STUB_DIR/cclr.env"
    n=$(grep -c '^move' "$STUB_DIR/cclr.log")
    b="20261021T0${n}0000Z-next3-next2-$n"
    [ -z "${CC_LR_MOVE_QUEUED_OUT:-}" ] || printf '%s\n' "$b" > "$CC_LR_MOVE_QUEUED_OUT"
    exit 0 ;;
esac
exit 64
STUB
  printf '#!/bin/bash\nprintf "%%s\\n" "$1" >> "%s/pages.log"\n' "$STUBS" > "$LR_SHED_PAGE_BIN"
  chmod +x "$STUBS"/*
}

S_IDLE=3d1d988a-0000-4000-8000-000000000001   # idle 2820 s: the incident's late idle
S_BUSY=769b7294-0000-4000-8000-000000000002   # idle 300 s
S_DRAFT=dddd0003-0000-4000-8000-000000000003
S_MID=eeee0004-0000-4000-8000-000000000004

# band <acct:verdict[:trip]>… [targets=a,b] → BAND_JSON as --shed-band prints it (reset 10 h out)
band() {
  "$PY" - "$@" > "$BAND_JSON" <<'PY'
import json, os, sys, time
from datetime import datetime, timezone
now = time.time(); ra = float(os.environ["BAND_RA"])   # one reset for the whole case: one window key
accts, tg = [], ["next2", "next4"]
for a in sys.argv[1:]:
    if a.startswith("targets="):
        tg = [x for x in a[8:].split(",") if x]; continue
    p = a.split(":")
    d = {"acct": p[0], "verdict": p[1], "reset_at": datetime.fromtimestamp(ra, timezone.utc).isoformat(),
         "reset_key": round(ra / 60.0), "used_pct": 97.5, "k_work": 1, "cache_age_s": 30.0, "ledger_age_s": 400.0}
    if len(p) > 2:
        d["trip"] = p[2]
    accts.append(d)
print(json.dumps({"v": 1, "ts": now, "accounts": accts, "targets": tg, "excluded": {}, "knobs": {}}))
PY
}
plan_rows() { # the incident's four rows
  jq -nc --arg a "$S_IDLE" --arg b "$S_BUSY" --arg c "$S_DRAFT" --arg d "$S_MID" '{from:"next3", to:"next2", rows:[
    {sid:$a, act:"move", disposition:"move", idle_s:2820, cache:"warm"},
    {sid:$b, act:"move", disposition:"move", idle_s:300, cache:"warm"},
    {sid:$c, act:"move", disposition:"draft", idle_s:4000, cache:"cold"},
    {sid:$d, act:"hold", disposition:"hold:mid-turn", idle_s:10, cache:"warm"}]}' > "$PLAN_JSON"
}
on_mode() { printf 'on\n' > "$SHED/mode"; : > "$LR_STATE_DIR/autorecover.on"; }
tick() { "$PY" "${SHED_PY:-$SUBJ_SHED}" --tick; }
moves() { if [ -f "$STUBS/cclr.log" ]; then grep -c '^move .* --wait 0' "$STUBS/cclr.log" || true; else echo 0; fi; }
dec() { jq -c "select(.ev == \"$1\")" "$SHED/decisions.jsonl" 2>/dev/null; }

# ══ T1: the router's band verdict ═════════════════════════════════════════════════════════════════════

@test "T1-1 [RED] the late band: 97 % exactly is band on the LEVEL arm; one under with a far wall is out" {
  run "$PY" -c "$LOAD"'
t, f = v(row(used=97.0, ewma=0.5, flat=0.4))
assert t == "band" and f["trip"] == "level", (t, f)
assert f["reset_key"] == round(datetime.fromisoformat(f["reset_at"]).timestamp() / 60.0), f
t, f = v(row(used=90.0, reset_h=30.0, ewma=1.0, flat=0.8))
assert t == "out", (t, f)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "T1-2 mutant m2 (> for >= on the level arm) turns 97.0 into out: dies" {
  mutate "$CA_BIN" "$BATS_TEST_TMPDIR/ca-m2" '    level = 100.0 * used >= lv' '    level = 100.0 * used > lv'
  CA_BIN="$BATS_TEST_TMPDIR/ca-m2" run "$PY" -c "$LOAD"'
t, f = v(row(used=97.0, ewma=0.5, flat=0.4)); assert t == "band", t; print("OK")'
  [ "$status" -ne 0 ] || { echo "the mutant survived: $output"; false; }
}

@test "T1-3 the guard reads the SLOW pace: the fast pace walls 2.5 h early, the slow one too late ⇒ band-guard" {
  run "$PY" -c "$LOAD"'
t, f = v(row(used=97.5, reset_h=5.0, ewma=1.0, flat=0.5))
assert t == "band-guard" and f["ttw_lo_h"] == 5.0 and f["ttw_hi_h"] == 2.5, (t, f)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "T1-4 mutant m1 (the guard reads the fast pace) sheds into a strand: dies" {
  mutate "$CA_BIN" "$BATS_TEST_TMPDIR/ca-m1" '    if not (lo > 0 and ttw_lo <= wrh - gh):' '    if not (lo > 0 and ttw_hi <= wrh - gh):'
  CA_BIN="$BATS_TEST_TMPDIR/ca-m1" run "$PY" -c "$LOAD"'
t, f = v(row(used=97.5, reset_h=5.0, ewma=1.0, flat=0.5)); assert t == "band-guard", t; print("OK")'
  [ "$status" -ne 0 ] || { echo "the mutant survived: $output"; false; }
}

@test "T1-5 the TTW arm: under the level, a fast pace that walls within 2 h trips as 'ttw'" {
  run "$PY" -c "$LOAD"'
t, f = v(row(used=95.0, ewma=2.0, flat=2.6)); assert t == "band" and f["trip"] == "ttw", (t, f)
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "T1-6 D4: NaN anywhere is unknown, never band; a zero slow pace is band-guard" {
  run "$PY" -c "$LOAD"'
nan = float("nan")
assert v(row(used=nan, wire={"7d_util": nan}))[0] == "unknown:no-reset", v(row(wire={"7d_util": nan}))
assert v(row(ewma=nan))[0] == "unknown:pace-unknown"
assert v(row(flat=nan))[0] == "unknown:pace-stale"
assert v(row(flat=None))[0] == "unknown:pace-stale"
assert v(row(weekly_reset_at=None, weekly_reset_h=nan))[0] == "unknown:no-reset"
assert v(row(ewma=float("inf")))[0] == "unknown:pace-unknown"
assert v(row(used=97.5, ewma=0.5, flat=0.0))[0] == "band-guard"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "T1-7 mutant m3 (a plain number check lets NaN through to min()) reaches band: dies" {
  mutate "$CA_BIN" "$BATS_TEST_TMPDIR/ca-m3" '    return _is_num(x) and math.isfinite(x)' '    return _is_num(x)'
  CA_BIN="$BATS_TEST_TMPDIR/ca-m3" run "$PY" -c "$LOAD"'
assert v(row(flat=float("nan")))[0] == "unknown:pace-stale"; print("OK")'
  [ "$status" -ne 0 ] || { echo "the mutant survived: $output"; false; }
}

@test "T1-8 D7: at or past the wall, or under a rejected 5h/7d window or live fact, the verdict is walled" {
  run "$PY" -c "$LOAD"'
assert v(row(used=100.0))[0] == "walled"
assert v(row(used=60.0, wire={"7d_status": "rejected", "7d_util": 0.6}))[0] == "walled"
assert v(row(used=60.0, wire={"5h_status": "rejected"}))[0] == "walled"
live = {"status": "rejected", "scope": "7d", "resets_at": NOW + 7200, "observed_at": NOW - 60}
assert v(row(used=60.0), [live])[0] == "walled"
dead = dict(live, resets_at=NOW - 3600)
assert v(row(used=60.0), [dead])[0] == "out"
assert v(row(used=60.0), [dict(live, scope="fable")])[0] == "out"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "T1-9 mutant (no walled verdict): a 100 % account reads band from the wall to the reset: dies" {
  mutate "$CA_BIN" "$BATS_TEST_TMPDIR/ca-m7" '    if (_shed_finite(used) and used >= 1.0) or wire_rejects' '    if (_shed_finite(used) and used >= 9.0) or wire_rejects'
  CA_BIN="$BATS_TEST_TMPDIR/ca-m7" run "$PY" -c "$LOAD"'
assert v(row(used=100.0))[0] == "walled"; print("OK")'
  [ "$status" -ne 0 ] || { echo "the mutant survived: $output"; false; }
}

@test "T1-10 credits on is hold-credits, a stale level is unknown:level-stale, CC_ROUTE_SHED=off is off" {
  run "$PY" -c "$LOAD"'
assert v(row(credits_on=True))[0] == "hold-credits"
assert v(row(stale_quota=True))[0] == "unknown:level-stale"
os.environ["CC_ROUTE_SHED"] = "off"
assert v(row())[0] == "off"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "T1-11 D12: a knob typo in the env falls back to the default, never clamps toward a wider band" {
  run "$PY" -c "$LOAD"'
for raw, want in (("0.97", 97.0), ("98", 98.0), ("nan", 97.0), ("inf", 97.0), ("x", 97.0), ("50", 97.0)):
    os.environ["CC_ROUTE_SHED_LV_OPEN"] = raw
    assert ca.shed_knob(R, "SHED_LV_OPEN") == want, (raw, ca.shed_knob(R, "SHED_LV_OPEN"))
os.environ["CC_ROUTE_SHED_TTW_OPEN_H"] = "48"
assert ca.shed_knob(R, "SHED_TTW_OPEN_H") == 2.0
os.environ["CC_ROUTE_SHED_LV_OPEN"] = "0.97"
assert v(row(used=60.0, reset_h=60.0, ewma=0.5, flat=0.4))[0] == "out"
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "T1-12 mutant (shed_knob clamps like _dispatch_knob): 0.97 opens the band from 95 %: dies" {
  mutate "$CA_BIN" "$BATS_TEST_TMPDIR/ca-m12" '        if math.isfinite(v) and lo <= v <= hi:
            return v' '        if math.isfinite(v):
            return clamp(v, lo, hi)'
  CA_BIN="$BATS_TEST_TMPDIR/ca-m12" run "$PY" -c "$LOAD"'
os.environ["CC_ROUTE_SHED_LV_OPEN"] = "0.97"
assert ca.shed_knob(R, "SHED_LV_OPEN") == 97.0; print("OK")'
  [ "$status" -ne 0 ] || { echo "the mutant survived: $output"; false; }
}

@test "T1-13 the SSOT range refuses SHED_LV_OPEN 0.97 at load" {
  jq '.router.SHED_LV_OPEN = 0.97' "$CA_CFG" > "$CA_CFG.t" && mv "$CA_CFG.t" "$CA_CFG"
  seed next3:97.5:10:1
  run "$PY" "$CA_BIN" --shed-band --json --max-wait 0
  [ "$status" -ne 0 ] || { echo "$output"; false; }
  [[ "$output" == *"SHED_LV_OPEN must be a number in [95.0, 100.0]"* ]] || { echo "$output"; false; }
}

@test "T1-14 [RED] --shed-band end to end: the walling account is band and not a target; each account carries its ages and k_work" {
  seed next2:10:100:0.1 next3:97.5:10:1 next4:40:60:0.3
  run "$PY" "$CA_BIN" --shed-band --json --max-wait 0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | jq -e '
    (.accounts[] | select(.acct == "next3") | .verdict == "band" and .trip == "level" and (.reset_key | type) == "number"
       and .k_work == 1 and (.cache_age_s | type) == "number" and (.ledger_age_s | type) == "number")
    and (.accounts[] | select(.acct == "next2") | .verdict == "out")
    and ((.targets | index("next3")) == null) and (.targets | length) >= 1
    and .knobs.SHED_LV_OPEN == 97' >/dev/null || { echo "$output"; false; }
}

@test "T1-15 cache-only: no cache means exit 3 and wait_data, with get_data asked for max_wait 0" {
  rm -f "$CACHE"
  run "$PY" "$CA_BIN" --shed-band --json --max-wait 0
  [ "$status" -eq 3 ] || { echo "rc $status: $output"; false; }
  [ "$(printf '%s\n' "$output" | tail -1 | jq -c .)" = '{"v":1,"wait_data":true}' ] || { echo "$output"; false; }
  [ ! -e "$CACHE" ]
  run "$PY" -c "$LOAD"'
seen = {}
def spy(cfg, **kw):
    seen.update(kw); raise ca.CacheOnlyUnavailable("spy")
ca.get_data = spy
assert ca.cmd_shed_band(["--shed-band"], cfg) == ca.PLACE_EXIT_WAIT_DATA
assert seen.get("max_wait") == 0 and seen.get("max_age") == 1200, seen
print("OK")'
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "T1-16 CC_ROUTE_SHED=off makes every account's verdict off; --place --exclude never places on an excluded account" {
  seed next2:10:100:0.1 next3:97.5:10:1 next4:40:60:0.3
  CC_ROUTE_SHED=off run "$PY" "$CA_BIN" --shed-band --json --max-wait 0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | jq -e '[.accounts[].verdict] | unique == ["off"]' >/dev/null || { echo "$output"; false; }
  printf '{"sid":"s1","src":"next3","kind":"idle","w":1}\n' > "$BATS_TEST_TMPDIR/m.jsonl"
  echo '{"next2":0,"next3":0,"next4":0}' > "$BATS_TEST_TMPDIR/kw.json"; mkdir -p "$BATS_TEST_TMPDIR/facts"
  run "$PY" "$CA_BIN" --place --lane general --recovery --movers "$BATS_TEST_TMPDIR/m.jsonl" --facts "$BATS_TEST_TMPDIR/facts" \
      --kwork "$BATS_TEST_TMPDIR/kw.json" --exclude next3,next2 --json --max-wait 0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(printf '%s\n' "$output" | jq -r .s1.acct)" = next4 ] || { echo "$output"; false; }
  run "$PY" "$CA_BIN" --place --lane general --recovery --movers "$BATS_TEST_TMPDIR/m.jsonl" --facts "$BATS_TEST_TMPDIR/facts" \
      --kwork "$BATS_TEST_TMPDIR/kw.json" --exclude next3,next2,next4 --json --max-wait 0
  [ "$(printf '%s\n' "$output" | jq -r .s1.acct)" = null ] || { echo "$output"; false; }
  [[ "$(printf '%s\n' "$output" | jq -r .s1.reason)" == *excluded* ]] || { echo "$output"; false; }
}

@test "T1-17 a null swept k_work falls back to the newest ledger sample's, only inside the read's grace" {
  seed next2:10:100:0.1 next3:97.5:10:1
  jq '.rows |= map(.k_work = null)' "$CACHE" > "$CACHE.t" && mv "$CACHE.t" "$CACHE"
  run "$PY" "$CA_BIN" --shed-band --json --max-wait 0
  printf '%s\n' "$output" | jq -e '[.accounts[].k_work] == [1, 1]' >/dev/null || { echo "$output"; false; }
  # every ledger sample 2000 s older than the 1200 s grace: unmeasured, never a stale count
  "$PY" -c 'import json,sys
from datetime import datetime, timedelta
out = []
for l in open(sys.argv[1]):
    e = json.loads(l); e["ts"] = (datetime.fromisoformat(e["ts"]) - timedelta(seconds=2000)).isoformat(); out.append(json.dumps(e))
open(sys.argv[1], "w").write("\n".join(out) + "\n")' "$CC_UTIL_LOG"
  run "$PY" "$CA_BIN" --shed-band --json --max-wait 0
  printf '%s\n' "$output" | jq -e '[.accounts[].k_work] == [null, null]' >/dev/null || { echo "$output"; false; }
}

# ══ T2: the controller ════════════════════════════════════════════════════════════════════════════════

@test "T2-1 [RED] the incident's two late idles: ONE move of the 47-min idle only, at one slot, under the shed's environment" {
  on_mode; band next3:band:level; plan_rows
  export CLAUDE_CODE_SESSION_ID=caller-sid KITTY_WINDOW_ID=77 CC_PANE_ID=77
  run tick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(moves)" -eq 1 ] || { cat "$STUBS/cclr.log"; false; }
  grep -qx "move --from next3 --sids $S_IDLE --to next2 --wait 0 --slots 1" "$STUBS/cclr.log" || { cat "$STUBS/cclr.log"; false; }
  grep -qx "plan --from next3 --to next2 --json" "$STUBS/cclr.log" || { cat "$STUBS/cclr.log"; false; }
  [ "$(cat "$STUBS/cclr.env")" = "CC_LR_MOVE_GOAL_HOLD=always CC_LR_MOVE_HOLD_FOCUSED=1 CC_LR_MOVE_ORIGIN=shed LR_DEAD_SOURCE_RELEASE=off LR_MOVE_CARRY_DRAFT=off " ] \
    || { cat "$STUBS/cclr.env"; false; }
  dec move | jq -e 'select(.batch != null and .n == 1)' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
  dec pick | jq -e '.hist == {"move": 2, "draft": 1, "hold:mid-turn": 1}' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
  grep -q -- '--exclude next3' "$STUBS/ca.log" || { cat "$STUBS/ca.log"; false; }
}

@test "T2-2 mutants m4 (no idle filter) and m5 (a draft row selected) each move a session they must not: die" {
  on_mode; band next3:band:level; plan_rows
  mutate "$SUBJ_SHED" "$BATS_TEST_TMPDIR/m4.py" '        and r["idle_s"] >= Q_S' '        and r["idle_s"] >= 0'
  mutate "$SUBJ_SHED" "$BATS_TEST_TMPDIR/m5.py" '        and r.get("disposition") == "move"' '        and r.get("disposition") in ("move", "draft")'
  for m in m4 m5; do
    rm -f "$STUBS/cclr.log" "$SHED/state.json" "$SHED/decisions.jsonl"
    SHED_PY="$BATS_TEST_TMPDIR/$m.py" run tick
    ! grep -qx "move --from next3 --sids $S_IDLE --to next2 --wait 0 --slots 1" "$STUBS/cclr.log" || { echo "$m survived"; cat "$STUBS/cclr.log"; false; }
  done
}

@test "T2-3 shadow: the pick is on disk with its histogram, the move is only timed as a dry run (E7)" {
  printf 'shadow\n' > "$SHED/mode"; : > "$LR_STATE_DIR/autorecover.on"; band next3:band:level; plan_rows
  run tick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(moves)" -eq 0 ] || { cat "$STUBS/cclr.log"; false; }
  grep -qx "move --from next3 --sids $S_IDLE --to next2 --dry-run" "$STUBS/cclr.log" || { cat "$STUBS/cclr.log"; false; }
  dec pick | jq -e --arg s "${S_IDLE:0:8}" '.mode == "shadow" and .picks == [$s + ">next2"]' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
  dec dry-run | jq -e '.rc == 0 and (.wall_s | type) == "number" and .router == "ranked"' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
}

@test "T2-4 mutant m6 (moves in shadow): dies" {
  printf 'shadow\n' > "$SHED/mode"; band next3:band:level; plan_rows
  mutate "$SUBJ_SHED" "$BATS_TEST_TMPDIR/m6.py" '        if mode != "on":' '        if mode == "never":'
  SHED_PY="$BATS_TEST_TMPDIR/m6.py" run tick
  [ "$(moves)" -ne 0 ] || { echo "the mutant moved nothing, so the shadow assertion has no power"; false; }
}

@test "T2-5 zero-human: mode on without autorecover.on acts as shadow (why=zero-human); m7 ignoring it dies" {
  printf 'on\n' > "$SHED/mode"; band next3:band:level; plan_rows
  run tick
  [ "$(moves)" -eq 0 ] || { cat "$STUBS/cclr.log"; false; }
  dec band | jq -e 'select(.acct == "next3") | .mode == "shadow" and .why == "zero-human"' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
  rm -f "$STUBS/cclr.log" "$SHED/state.json"
  mutate "$SUBJ_SHED" "$BATS_TEST_TMPDIR/m7.py" '    if m == "on" and not os.path.exists(os.path.join(STATE, "autorecover.on")):' '    if False:'
  SHED_PY="$BATS_TEST_TMPDIR/m7.py" run tick
  [ "$(moves)" -eq 1 ] || { echo "m7 survived"; false; }
}

@test "T2-6 hysteresis: the level arm opens at once (E2); the TTW arm needs two looks >= 300 s apart; release needs two >= 1200 s; unknown changes nothing" {
  run "$PY" - "$SUBJ_SHED" <<'PY'
import importlib.machinery, sys
m = importlib.machinery.SourceFileLoader("shed", sys.argv[1]).load_module()
def w(): return {"open": False, "trip_at": None, "fail_at": None, "looks": 0, "unknown_n": 0}
x = w(); m.step_hysteresis(x, "band", "level", 1000.0); assert x["open"], x
x = w(); m.step_hysteresis(x, "band", "ttw", 1000.0); assert not x["open"], x
m.step_hysteresis(x, "unknown:pace-stale", None, 1100.0); assert not x["open"] and x["trip_at"] == 1000.0, x
m.step_hysteresis(x, "band", "ttw", 1299.0); assert not x["open"], x
m.step_hysteresis(x, "band", "ttw", 1300.0); assert x["open"], x
m.step_hysteresis(x, "band-guard", "ttw", 2000.0); assert x["open"], x
m.step_hysteresis(x, "unknown:level-stale", None, 2500.0); assert x["open"] and x["fail_at"] == 2000.0, x
m.step_hysteresis(x, "band-guard", "ttw", 3199.0); assert x["open"], x
m.step_hysteresis(x, "band-guard", "ttw", 3200.0); assert not x["open"] and x["closed_by"] == "band-guard", x
x = w(); m.step_hysteresis(x, "band", "ttw", 1000.0); m.step_hysteresis(x, "out", None, 1200.0)
m.step_hysteresis(x, "band", "ttw", 1400.0); assert not x["open"] and x["trip_at"] == 1400.0, x
print("OK")
PY
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "T2-7 mutant (the level arm waits for confirmation like the TTW arm): the first look no longer opens: dies" {
  mutate "$SUBJ_SHED" "$BATS_TEST_TMPDIR/me2.py" '            if trip == "level":' '            if trip == "never":'
  run "$PY" - "$BATS_TEST_TMPDIR/me2.py" <<'PY'
import importlib.machinery, sys
m = importlib.machinery.SourceFileLoader("shed", sys.argv[1]).load_module()
x = {"open": False, "trip_at": None, "fail_at": None}
m.step_hysteresis(x, "band", "level", 1000.0); assert x["open"], x
PY
  [ "$status" -ne 0 ] || { echo "the mutant survived: $output"; false; }
}

@test "T2-8 our timeout is unknown: exit 0, one unknown row, an open window stays open, nothing moves (m8 dies)" {
  on_mode; band next3:band:level; plan_rows
  run tick
  [ "$(moves)" -eq 1 ]
  rm -f "$STUBS/cclr.log"; mv "$SHED/state.json" "$BATS_TEST_TMPDIR/state.open.json"; cp "$BATS_TEST_TMPDIR/state.open.json" "$SHED/state.json"
  export CA_SLEEP=5 LR_SHED_BAND_TO=1
  run tick
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -s "$STUBS/cclr.log" ]
  dec band | tail -1 | jq -e '.verdict == "unknown" and (.cause | startswith("rc=124"))' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
  jq -e '[.windows[] | select(.acct == "next3")][0].open == true' "$SHED/state.json" >/dev/null || { cat "$SHED/state.json"; false; }
  # The unknown VERDICT (a blind band row, not a failed read) is held the same way; m8 reads our
  # blindness as `out`, and two such looks 20 min apart close the open window.
  unset CA_SLEEP LR_SHED_BAND_TO
  band next3:unknown:pace-stale
  for t in 0 1300; do LR_SHED_NOW="$(( $(date +%s) + t ))" run tick; done
  jq -e '[.windows[] | select(.acct == "next3")][0] | .open == true and .unknown_n >= 2' "$SHED/state.json" >/dev/null || { cat "$SHED/state.json"; false; }
  cp "$BATS_TEST_TMPDIR/state.open.json" "$SHED/state.json"
  mutate "$SUBJ_SHED" "$BATS_TEST_TMPDIR/m8.py" '        w["unknown_n"] = w.get("unknown_n", 0) + 1
        return' '        v = "out"'
  for t in 0 1300; do LR_SHED_NOW="$(( $(date +%s) + t ))" SHED_PY="$BATS_TEST_TMPDIR/m8.py" run tick; done
  ! jq -e '[.windows[] | select(.acct == "next3")][0].open == true' "$SHED/state.json" >/dev/null \
    || { echo "m8 survived: an unknown verdict left the window as it was"; false; }
}

@test "T2-9 D3/E3: an unsettled shed batch on disk holds its source; past the bounded release with no runner it is settled:unknown" {
  on_mode; band next3:band:level; plan_rows
  b="$LR_STATE_DIR/move/$(date -u +%Y%m%dT%H%M%SZ)-next3-next2-1"; mkdir -p "$b"
  jq -nc --argjson ts "$(date +%s)" '{origin:"shed", from:"next3", to:"next2", ts:$ts, rows:[{sid:"x1", act:"move"}]}' > "$b/plan.json"
  run tick
  [ "$(moves)" -eq 0 ] || { cat "$STUBS/cclr.log"; false; }
  dec in-flight | jq -e '.acct == "next3"' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
  # an OPERATOR batch on the same source does not hold the shed
  jq '.origin = null' "$b/plan.json" > "$b/p.t" && mv "$b/p.t" "$b/plan.json"
  run tick; [ "$(moves)" -eq 1 ] || { cat "$STUBS/cclr.log"; false; }
  rm -f "$STUBS/cclr.log" "$SHED/state.json"
  # 2000 s old, no settle marker, no runner: released and logged
  jq -c --argjson ts "$(( $(date +%s) - 2000 ))" '.origin = "shed" | .ts = $ts' "$b/plan.json" > "$b/p.t" && mv "$b/p.t" "$b/plan.json"
  run tick
  [ "$(moves)" -eq 1 ] || { cat "$STUBS/cclr.log"; cat "$SHED/decisions.jsonl"; false; }
  dec settled-unknown | jq -e '.acct == "next3"' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
}

@test "T2-10 E3 mutant (no bounded release: an unsettled batch holds forever): dies" {
  on_mode; band next3:band:level; plan_rows
  b="$LR_STATE_DIR/move/$(date -u +%Y%m%dT%H%M%SZ)-next3-next2-1"; mkdir -p "$b"
  jq -nc --argjson ts "$(( $(date +%s) - 2000 ))" '{origin:"shed", from:"next3", to:"next2", ts:$ts, rows:[{sid:"x1", act:"move"}]}' > "$b/plan.json"
  mutate "$SUBJ_SHED" "$BATS_TEST_TMPDIR/me3.py" '    return False, "settled:unknown"' '    return True, "young"'
  SHED_PY="$BATS_TEST_TMPDIR/me3.py" run tick
  [ "$(moves)" -eq 0 ] || { echo "the mutant still moved, so the release case has no power"; false; }
}

@test "T2-11 breaker: a STRANDED member writes shed/breaker, aborts unsettled shed batches, pages ONCE over 3 ticks; on acts as shadow" {
  on_mode; band next3:band:level; plan_rows
  b="$LR_STATE_DIR/move/$(date -u +%Y%m%dT%H%M%SZ)-next3-next2-9"; mkdir -p "$b"
  jq -nc --argjson ts "$(( $(date +%s) - 4000 ))" '{origin:"shed", from:"next3", to:"next2", ts:$ts, rows:[{sid:"s9", act:"move"}]}' > "$b/plan.json"
  echo '{"sid":"s9","verdict":"STRANDED","reason":"no copy"}' > "$b/s9.json"
  for _i in 1 2 3; do run tick; [ "$status" -eq 0 ] || { echo "$output"; false; }; done
  [ -s "$SHED/breaker" ] && jq -e '.why == "casualty"' "$SHED/breaker" >/dev/null
  [ -e "$b/abort" ]
  [ "$(grep -c "shed-casualty-" "$STUBS/pages.log")" -eq 1 ] || { cat "$STUBS/pages.log"; false; }
  [ "$(moves)" -eq 0 ] || { cat "$STUBS/cclr.log"; false; }
  dec band | tail -1 | jq -e '.mode == "shadow" and .why == "breaker"' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
}

@test "T2-12 D11/E5: the cooldown is set on MOVED only; a transient NOTMOVED is re-pickable next tick" {
  on_mode; band next3:band:level
  S_A=aaaa0001-0000-4000-8000-00000000000a; S_B=bbbb0002-0000-4000-8000-00000000000b
  jq -nc --arg a "$S_A" --arg b "$S_B" '{rows:[{sid:$a, act:"move", disposition:"move", idle_s:4000, cache:"cold"},
                                              {sid:$b, act:"move", disposition:"move", idle_s:3000, cache:"cold"}]}' > "$PLAN_JSON"
  b="$LR_STATE_DIR/move/$(date -u +%Y%m%dT%H%M%SZ)-next3-next2-5"; mkdir -p "$b/summary.settled"
  jq -nc --arg a "$S_A" --arg bb "$S_B" --argjson ts "$(( $(date +%s) - 3000 ))" '{origin:"shed", from:"next3", to:"next2", ts:$ts, rows:[{sid:$a, act:"move"},{sid:$bb, act:"move"}]}' > "$b/plan.json"
  echo '{"verdict":"MOVED","reason":"ok"}' > "$b/$S_A.json"
  echo '{"verdict":"NOTMOVED","reason":"HELD:unreachable"}' > "$b/$S_B.json"
  run tick
  grep -qx "move --from next3 --sids $S_B --to next2 --wait 0 --slots 1" "$STUBS/cclr.log" || { cat "$STUBS/cclr.log"; false; }
  jq -e --arg a "$S_A" '.cooldown[$a] != null' "$SHED/state.json" >/dev/null
}

@test "T2-13 strand audit: a window that closed at 96 after sheds trips the breaker and pages once; 100 is quiet; no sample in its last 30 min is unknown (E8)" {
  on_mode; band next2:out
  ra=$(( $(date +%s) - 3600 ))
  st() { jq -nc --argjson re "$ra" '{v:1, windows:{"next3:1":{acct:"next3", reset_epoch:$re, sheds:2, open:false, audited:false}}, cooldown:{}, paged:{}, batches:{}}' > "$SHED/state.json"; }
  led() { "$PY" -c 'import json,sys
from datetime import datetime, timezone
print(json.dumps({"ts": datetime.fromtimestamp(float(sys.argv[1]), timezone.utc).isoformat(), "acct": "next3", "weekly_pct": float(sys.argv[2])}))' "$1" "$2" > "$CC_UTIL_LOG"; }
  st; led $(( ra - 600 )) 96
  run tick
  dec strand-audit | jq -e '.verdict == "strand" and .final == 96' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
  jq -e '.why == "strand"' "$SHED/breaker" >/dev/null
  [ "$(grep -c shed-strand "$STUBS/pages.log")" -eq 1 ]
  rm -f "$SHED/breaker" "$SHED/decisions.jsonl" "$STUBS/pages.log"
  st; led $(( ra - 600 )) 100
  run tick
  dec strand-audit | jq -e '.verdict == "ok"' >/dev/null; [ ! -e "$SHED/breaker" ]; [ ! -e "$STUBS/pages.log" ]
  rm -f "$SHED/decisions.jsonl"
  st; led $(( ra - 3600 )) 90
  run tick
  dec strand-audit | jq -e '.verdict == "unknown"' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
  [ ! -e "$SHED/breaker" ]; [ ! -e "$STUBS/pages.log" ]
}

@test "T2-14 D1 lock: a LIVE (pid, lstart) holder makes a tick a no-op; a dead one is reaped and the tick runs" {
  on_mode; band next3:band:level; plan_rows
  sleep 60 3>&- & SP=$!
  printf '%s %s' "$SP" "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$SP" | tr -s ' ' | sed 's/^ //;s/ $//')" > "$SHED/run.lock"
  run tick
  kill "$SP" 2>/dev/null || true
  [ ! -s "$SHED/decisions.jsonl" ] || { cat "$SHED/decisions.jsonl"; false; }
  [ "$(moves)" -eq 0 ]
  wait "$SP" 2>/dev/null || true
  run tick
  dec lock-reaped | jq -e ".holder == \"$SP\"" >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
  [ "$(moves)" -eq 1 ]
  [ ! -e "$SHED/run.lock" ]
}

@test "T2-15 E1: an open limited reconciler record means no queueing (yield:recovery); shadow still logs the would-yield pick" {
  on_mode; band next3:band:level; plan_rows
  echo '{"sid":"L1","kind":"limited","terminal":null}' > "$LR_RECON_ROOT/sessions/L1.json"
  echo '{"sid":"I1","kind":"idle","terminal":null}' > "$LR_RECON_ROOT/sessions/I1.json"
  echo '{"sid":"L2","kind":"limited","terminal":{"outcome":"ENGAGED"}}' > "$LR_RECON_ROOT/sessions/L2.json"
  run tick
  [ "$(moves)" -eq 0 ] || { cat "$STUBS/cclr.log"; false; }
  dec yield | jq -e '.limited_open == 1' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
  ! grep -q '^plan' "$STUBS/cclr.log" 2>/dev/null
  rm -f "$SHED/decisions.jsonl" "$SHED/state.json"; printf 'shadow\n' > "$SHED/mode"
  run tick
  dec pick | jq -e '.would_yield == true' >/dev/null || { cat "$SHED/decisions.jsonl"; false; }
}

@test "T2-16 E1 mutant (no yield): a shed batch queues beside an open limited cohort: dies" {
  on_mode; band next3:band:level; plan_rows
  echo '{"sid":"L1","kind":"limited"}' > "$LR_RECON_ROOT/sessions/L1.json"
  mutate "$SUBJ_SHED" "$BATS_TEST_TMPDIR/me1.py" '        if yielded and mode == "on":' '        if False:'
  SHED_PY="$BATS_TEST_TMPDIR/me1.py" run tick
  [ "$(moves)" -eq 1 ] || { echo "the mutant queued nothing, so the yield case has no power"; false; }
}

@test "T2-17 D17: picks follow --place across targets (one batch per target), and a walled account sheds nothing" {
  on_mode; band next3:band:level
  jq -nc '{rows:[{sid:"p1", act:"move", disposition:"move", idle_s:4000, cache:"cold"},
                 {sid:"p2", act:"move", disposition:"move", idle_s:3900, cache:"cold"}]}' > "$PLAN_JSON"
  PLACE_ALT=next4 run tick
  grep -qx "move --from next3 --sids p1 --to next2 --wait 0 --slots 1" "$STUBS/cclr.log" || { cat "$STUBS/cclr.log"; false; }
  grep -qx "move --from next3 --sids p2 --to next4 --wait 0 --slots 1" "$STUBS/cclr.log" || { cat "$STUBS/cclr.log"; false; }
  rm -f "$STUBS/cclr.log" "$SHED/state.json"
  band next3:walled
  run tick
  [ ! -s "$STUBS/cclr.log" ]
}

@test "T2-18 D12 + kill switches: absent or malformed mode writes nothing; LR_SHED=off writes nothing; out-of-range knobs do less, never more" {
  band next3:band:level; plan_rows
  run tick; [ ! -e "$SHED/decisions.jsonl" ]
  printf 'On\n' > "$SHED/mode"; run tick; [ ! -e "$SHED/decisions.jsonl" ]
  on_mode; LR_SHED=off run tick; [ ! -e "$SHED/decisions.jsonl" ]
  run "$PY" - "$SUBJ_SHED" <<'PY'
import importlib.machinery, os, sys
os.environ.update(LR_SHED_MAX="40", LR_SHED_IDLE_S="60", LR_SHED_COOLDOWN_S="-5")
m = importlib.machinery.SourceFileLoader("shed", sys.argv[1]).load_module()
assert (m.MAX_PER_TICK, m.Q_S, m.COOLDOWN_S) == (4, 1800, 21600), (m.MAX_PER_TICK, m.Q_S, m.COOLDOWN_S)
print("OK")
PY
  [ "$status" -eq 0 ] && [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "T2-19 G1: the controller reads no load figure" {
  run grep -nE 'getloadavg|vm\.loadavg|load1' "$SUBJ_SHED"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "T2-20 --report and --status read back the windows, the blind share and the dry-run times" {
  printf 'shadow\n' > "$SHED/mode"; band next3:band:level; plan_rows
  run tick
  run "$PY" "$SUBJ_SHED" --report --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | jq -e '.mode == "shadow" and (.windows | length) == 1 and .windows[0].picks == 1
    and .summary.ticks == 1 and .summary.blind_share == 0 and .summary.dry_runs == 1' >/dev/null || { echo "$output"; false; }
  run "$PY" "$SUBJ_SHED" --status
  [[ "$output" == "mode shadow · breaker absent · lock free" ]] || { echo "$output"; false; }
}

# ══ T4: the move-lane seams (bin/cc-lr) ═══════════════════════════════════════════════════════════════

cclr_env() {
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"; CCLR="$REPO/bin/cc-lr"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_MOVE_ENV_DIR"
  export LRU_STATE="$LR_STATE_DIR" LRU_REG_DIR="$BATS_TEST_TMPDIR/reg" LRU_CFG_ROOT="$HOME"; mkdir -p "$LRU_REG_DIR"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_COMPOSER=off LRU_SELF_SID="" LRU_LR_LIB="$BATS_TEST_TMPDIR/absent-lr-lib.sh"
  export LRU_NOTIFY_BIN="$STUBS/cc-notify" LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\nexit 0\n' > "$LRU_NOTIFY_BIN"; printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"
  printf '#!/bin/bash\nexit 0\n' > "$STUBS/launchctl"
  export CC_ACCOUNTS_BIN="$STUBS/ca-rank"; printf '#!/bin/bash\nprintf "next2 0.9\\nnext3 0.4\\n"\n' > "$CC_ACCOUNTS_BIN"
  chmod +x "$STUBS"/*
  export PATH="$STUBS:$PATH" CC_LR_UPGRADE_BIN="$LRU" CC_LR_MOVE_POLL_S=0 CC_LR_LOAD_PER_CORE=0
  BIN="/opt/cc/.claude-280/node_modules/.bin/claude"; LST="Tue Sep 22 06:47:13 2026"
  local i=0 sid
  for sid in "$@"; do
    i=$((i + 1))
    printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"claude-tertiary","cwd":"%s","lstart":"%s"}\n' \
      "40$i" "$((50000 + i))" "$sid" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/40$i.json"
    printf '%d 1 %s %s\n' "$((50000 + i))" "$LST" "$BIN --model claude-opus-5-5" >> "$LRU_PS_SNAPSHOT"
    mkdir -p "$HOME/.claude-tertiary/projects/-x"
    printf '%s\n' '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"idle"}]}}' \
      > "$HOME/.claude-tertiary/projects/-x/$sid.jsonl"
  done
}
batchdir() { local d; for d in "$LR_STATE_DIR"/move/*/; do case "$d" in */requests/) continue ;; esac; [ -f "$d/plan.json" ] && { printf '%s\n' "${d%/}"; return 0; }; done; return 1; }

@test "T4-1 [RED] origin=shed and hold_focused reach plan.json and every intent; the batch id reaches QUEUED_OUT; lr-intent.sh accepts the intent" {
  S1=aaaa0001-0000-4000-8000-000000000001; S2=aaaa0002-0000-4000-8000-000000000002
  cclr_env "$S1" "$S2"
  q="$BATS_TEST_TMPDIR/queued"
  CC_LR_MOVE_ORIGIN=shed CC_LR_MOVE_HOLD_FOCUSED=1 CC_LR_MOVE_QUEUED_OUT="$q" \
    run /bin/bash "$CCLR" move --from next3 --sids "$S1,$S2" --to next2 --wait 0 --slots 1
  # rc 1 is "queued, still in flight" at --wait 0 (cmd_move's own contract); 2 or 3 is a refusal
  [ "$status" -le 1 ] || { echo "rc $status: $output"; false; }
  d="$(batchdir)"
  [ "$(cat "$q")" = "${d##*/}" ] || { cat "$q"; echo "$d"; false; }
  jq -e '.origin == "shed" and .hold_focused == true and .slots == 1' "$d/plan.json" >/dev/null || { cat "$d/plan.json"; false; }
  for s in "$S1" "$S2"; do jq -e '.origin == "shed"' "$d/intent/$s.json" >/dev/null; done
  # no ▶ status row for a machine caller
  [[ "$output" != *"▶ cc-lr move --status"* ]] || { echo "$output"; false; }
  run /bin/bash -c '. "$1/scripts/limit-recover/lr-intent.sh"; lr_intent_check "$2" "$3" "$4" next3 next2 || { echo "$LR_INTENT_WHY"; exit 1; }' _ \
    "$REPO" "$d/intent/$S1.json" "$S1" "$(jq -r .pane "$d/intent/$S1.json")"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "T4-2 unset, plan.json and the intents carry no origin or hold_focused (the operator's batch is as before)" {
  S1=aaaa0001-0000-4000-8000-000000000001
  cclr_env "$S1"
  run /bin/bash "$CCLR" move --from next3 --sids "$S1" --to next2 --wait 0
  [ "$status" -le 1 ] || { echo "rc $status: $output"; false; }
  d="$(batchdir)"
  [ "$(jq -c 'keys' "$d/plan.json")" = '["batch","from","requested_by","requester_pane","requester_sid","router_ranked_epoch","rows","target_unverified","to","to_config_dir","ts","until_idle_s"]' ] \
    || { jq -c keys "$d/plan.json"; false; }
  [ "$(jq -c 'keys' "$d/intent/$S1.json")" = '["batch","expires_epoch","from","kind","pane","plan_row_sha","requested_by","sid","to","ts"]' ] \
    || { jq -c keys "$d/intent/$S1.json"; false; }
  [[ "$output" == *"▶ cc-lr move --status"* ]] || { echo "$output"; false; }
}

@test "T4-3 any other CC_LR_MOVE_ORIGIN refuses with nothing written" {
  S1=aaaa0001-0000-4000-8000-000000000001
  cclr_env "$S1"
  CC_LR_MOVE_ORIGIN=operator run /bin/bash "$CCLR" move --from next3 --sids "$S1" --to next2 --wait 0
  [ "$status" -eq 3 ] || { echo "rc $status: $output"; false; }
  ! batchdir >/dev/null
}
