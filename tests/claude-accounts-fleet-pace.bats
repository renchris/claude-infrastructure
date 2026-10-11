#!/usr/bin/env bats
# The fleet pace line — fleet_pace (pure) and fleet_pace_line (the readout's one conclusion).
#
# WHAT IT IS FOR. Every pace figure on the readout is per account, so on 2026-10-09 three accounts
# each needing a p93-p98 burn at once read as three separate facts while the fleet's one throughput
# was a third of what its near resets needed. The line sums the fleet's realised 24h burn and asks
# how much of the quota resetting inside 48h that pace leaves unused. Telemetry judge replay
# (2026-10-10, /tmp/rtd-judge/pace.py): first fires 10-09T10:00Z; in the prior three weeks one
# episode, after which next4 stranded 26pp; the healthy span 09-09..10-02 never fires.
#
# The figure is rendered `~`, never `>=`: at 2026-10-03T18Z it read 58pp and 26pp actually died.
#
# Hermetic: $HOME, the SSOT, the ledgers and the clock origin are all fixtures; samples are built
# relative to a minute-aligned NOW, so reset keys (minute-rounded) land on whole hours exactly.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CA_CFG="$BATS_TEST_TMPDIR/accounts.json"
  export CLAUDE_ACCOUNTS_JSON="$CA_CFG"
  export CLAUDE_ACCOUNTS_LASTGOOD="$BATS_TEST_TMPDIR/lastgood.json"
  export CLAUDE_ACCOUNTS_LOG="$BATS_TEST_TMPDIR/claude-accounts.log"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
  export CC_ASSIGN_LOG="$BATS_TEST_TMPDIR/assign-ledger.jsonl"
  export CC_ROUTE_RECORDS_DIR="$BATS_TEST_TMPDIR/route-records"
  unset CC_ACCOUNTS_FLEET_PACE NO_COLOR CC_BOARD_COLOR
  python3 - "$CA_CFG" "$REPO/accounts.json" "$BATS_TEST_TMPDIR" <<'PY'
import json, sys
cfg_path, real, tmp = sys.argv[1:4]
r = json.load(open(real))
json.dump({
  "keychain_account": "test", "oauth_scopes": "x",
  "usage_endpoint": "http://127.0.0.1:9/never", "token_endpoint": "http://127.0.0.1:9/never",
  "user_agent": "test", "claude_bin": "/nonexistent/claude",
  "model_config_ssot": tmp + "/model-config.yaml", "dia_local_state": "/nonexistent/LS",
  "cache_file": tmp + "/cache.json",
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
import importlib.machinery, importlib.util, json, os, sys, time
from datetime import datetime, timezone
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
cfg = json.load(open(os.environ["CA_CFG"]))
NOW = (time.time() // 60.0) * 60.0          # minute-aligned, and never ahead of the real clock
FLEET = ["next", "next2", "next3", "next4"]
def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")
def ser(acct, level, reset_in_h, hours=None):
    """One sample per hour from 50h ago to now; level(h_ago) -> weekly_pct."""
    hs = hours if hours is not None else [50 - i for i in range(51)]
    return [{"acct": acct, "weekly_pct": level(h), "_t": NOW - h * 3600.0,
             "ts": iso(NOW - h * 3600.0), "weekly_reset_at": iso(NOW + reset_in_h * 3600.0)}
            for h in sorted(hs, reverse=True)]
def burner(now_ph, prior_ph, top):
    """Burns now_ph pp/h over the last 24h and prior_ph pp/h before that, ending at top."""
    return lambda h: top - now_ph * h if h <= 24 else top - now_ph * 24 - prior_ph * (h - 24)
# The 2026-10-10 01:56Z shape: three resets inside 48h holding 6 + 44 + 56 pp, and the fleet pace
# fallen from 2.1 to 1.0 pp/h. next4 and next3 each burned 1.05 pp/h the day before; today only
# next3 burns, at 1.0.
def week(next3_hours=None, next2_hours=None, shift=0.0):
    return (ser("next2", lambda h: 94.0, 9 + shift, next2_hours)
            + ser("next", lambda h: 56.0, 20 + shift)
            + ser("next4", burner(0.0, 1.05, 44.0), 31 + shift)
            + ser("next3", burner(1.0, 1.05, 60.0), 150 + shift, next3_hours))
WEEK_LINE = "⚠ 1.0 pp/h fleet burn (2.1 a day ago) vs 3.4 needed — ~75pp dies by next4\x27s reset in 1d 7h"
'

@test "FP-1: the this-week shape fires with the exact rendered line" {
  # pace 24/24 = 1.0; a day ago 50.4/24 = 2.1; near next2 (9h, 6) next (20h, 44) next4 (31h, 56):
  # needed = 106/31 = 3.42, shortfall = 106 - 1.0 x 31 = 75 by next4. An hour ago it read 72.5.
  run python3 -c "$LOAD"'
S = week()
v = ca.fleet_pace(S, NOW)
assert abs(v["pace"] - 1.0) < 1e-9, v
assert v["near"] == ["next2", "next", "next4"], v
assert abs(v["needed"] - 106.0 / 31.0) < 1e-9 and abs(v["short_pp"] - 75.0) < 1e-9, v
assert (v["by"], v["by_h"]) == ("next4", 31.0), v
prev = ca.fleet_pace(S, NOW - 3600.0)
assert abs(prev["short_pp"] - (106.0 - 32.0 * 25.1 / 24.0)) < 1e-9, prev
line = ca.fleet_pace_line(None, S, NOW)
assert line == WEEK_LINE, line
# the 2026-10-03 shape read ~58pp and 26pp died: the figure is an estimate, never a bound
assert "≥" not in line and ">=" not in line, line
# rows name the fleet: the same samples answer the same way when the readout passes its rows
assert ca.fleet_pace_line([{"acct": a} for a in FLEET], S, NOW) == WEEK_LINE
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-2: silent in a healthy week, and silent with nothing resetting inside 48h" {
  run python3 -c "$LOAD"'
# next3 burns 4.0 pp/h today: 106 - 4.0 x 31 < 0, nothing dies
S = (ser("next2", lambda h: 94.0, 9) + ser("next", lambda h: 56.0, 20)
     + ser("next4", lambda h: 44.0, 31) + ser("next3", burner(4.0, 1.0, 98.0), 150))
v = ca.fleet_pace(S, NOW)
assert abs(v["pace"] - 4.0) < 1e-9 and v["short_pp"] < 0, v
assert ca.fleet_pace_line(None, S, NOW) is None
# every reset far away: no shortfall to speak of, however idle the fleet
F = [e for a in FLEET for e in ser(a, lambda h: 10.0, 100)]
v = ca.fleet_pace(F, NOW)
assert v["near"] == [] and v["short_pp"] == 0.0 and v["by"] is None, v
assert ca.fleet_pace_line(None, F, NOW) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-3: an anchor more than 3h older than now-24h silences the line; 2.9h still measures" {
  # FLEET_ANCHOR_GAP_H. next3 keeps its last 23 hourly rows plus ONE older row at 24+g hours ago,
  # so its anchor is that row and the gap behind the window start is exactly g.
  run python3 -c "$LOAD"'
recent = list(range(0, 24))
for g, measured in ((2.9, True), (3.1, False)):
    S = week(next3_hours=recent + [24 + g])
    v = ca.fleet_pace(S, NOW)
    assert (v is not None) == measured, (g, v)
    assert (ca.fleet_pace_line(None, S, NOW) is not None) == measured, g
# no anchor at all: the series starts inside the window
S = week(next3_hours=list(range(0, 21)))
assert ca.fleet_pace(S, NOW) is None
assert ca.fleet_pace_line(None, S, NOW) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-4: a newest row over 1h old silences the line; 0.9h still measures" {
  # FLEET_MAX_AGE_H. A fleet sum missing one live member is not a fleet pace, and a quiet reading
  # that old is no evidence the account is quiet now.
  run python3 -c "$LOAD"'
old = [50 - i for i in range(49)]                    # hourly, 50h ago down to 2h ago
for age, measured in ((0.9, True), (1.1, False)):
    S = week(next2_hours=old + [age])
    assert (ca.fleet_pace(S, NOW) is not None) == measured, age
    assert (ca.fleet_pace_line(None, S, NOW) is not None) == measured, age
# a member the readout names but the ledger never sampled: abstain, never shrink the fleet
S = week()
assert ca.fleet_pace_line([{"acct": a} for a in FLEET + ["next5"]], S, NOW) is None
# a stale-flagged row is an echo, not a measurement: as newest it does not refresh the account
S = week(next2_hours=old) + [dict(ser("next2", lambda h: 94.0, 9, [0])[0], stale=True)]
assert ca.fleet_pace(S, NOW) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-5: the shortfall must hold for two consecutive hourly evaluations" {
  # FLEET_SUSTAIN_H and FLEET_NEAR_H on one fixture. next4 resets in 47.4h holding 100pp, so at NOW
  # it is inside the 48h horizon (shortfall 100 - 1.0 x 47.4 = 52.6) and an hour ago it was not.
  run python3 -c "$LOAD"'
def fleet(end):
    hs = [50 - i for i in range(51)] + list(range(-1, end - 1, -1))
    return (ser("next4", lambda h: 0.0, 47.4, hs) + ser("next", lambda h: 50.0, 100, hs)
            + ser("next2", lambda h: 50.0, 120, hs) + ser("next3", lambda h: 80.0 - h, 150, hs))
S = fleet(0)
cur, prev = ca.fleet_pace(S, NOW), ca.fleet_pace(S, NOW - 3600.0)
assert cur["near"] == ["next4"] and abs(cur["short_pp"] - 52.6) < 1e-9, cur
assert prev["near"] == [] and prev["short_pp"] == 0.0, prev
assert ca.fleet_pace_line(None, S, NOW) is None          # raw condition true, not yet sustained
# one hour later, with that hour sampled, both evaluations hold
S = fleet(-1)
line = ca.fleet_pace_line(None, S, NOW + 3600.0)
assert line == "⚠ 1.0 pp/h fleet burn (1.0 a day ago) vs 2.2 needed — ~54pp dies by next4\x27s reset in 1d 22h", line
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-6: the 30pp floor — 31 then 30 fires, 30.5 then 29.5 does not" {
  # FLEET_SHORT_FLOOR_PP. One near account (20h) at level L, pace exactly 1.0: the shortfall is
  # (100 - L) - 20 now and (100 - L) - 21 an hour ago.
  run python3 -c "$LOAD"'
def fleet(L):
    return (ser("next4", lambda h: L, 20) + ser("next", lambda h: 50.0, 100)
            + ser("next2", lambda h: 50.0, 120) + ser("next3", lambda h: 80.0 - h, 150))
S = fleet(49.0)
assert (ca.fleet_pace(S, NOW)["short_pp"], ca.fleet_pace(S, NOW - 3600.0)["short_pp"]) == (31.0, 30.0)
assert ca.fleet_pace_line(None, S, NOW) is not None
S = fleet(49.5)
assert (ca.fleet_pace(S, NOW)["short_pp"], ca.fleet_pace(S, NOW - 3600.0)["short_pp"]) == (30.5, 29.5)
assert ca.fleet_pace_line(None, S, NOW) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-7: a weekly reset inside the window adds the new level, never a negative burn" {
  # One account whose window rolled 10.5h ago at 90%: after the roll it reads 3, then climbs 0.5
  # pp/h to 8. Burned in the window = 3 + 5 = 8pp. A signed delta reads -82, a clamped one 5.
  run python3 -c "$LOAD"'
pre = [{"acct": "x", "weekly_pct": 90.0, "_t": NOW - h * 3600.0,
        "weekly_reset_at": iso(NOW - 10.5 * 3600.0)} for h in range(50, 10, -1)]
post = [{"acct": "x", "weekly_pct": 3.0 + 0.5 * (10 - h), "_t": NOW - h * 3600.0,
         "weekly_reset_at": iso(NOW + 157.5 * 3600.0)} for h in range(10, -1, -1)]
v = ca.fleet_pace(pre + post, NOW)
assert abs(v["pace"] - 8.0 / 24.0) < 1e-9, v
# FLEET_WINDOW_H: the 1.05 pp/h before the window never enters today pace, only the day-ago one
S = week()
assert abs(ca._fleet_burn(ca._fleet_series(S), NOW) - 1.0) < 1e-9
assert abs(ca._fleet_burn(ca._fleet_series(S), NOW - 86400.0) - 2.1) < 1e-9
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-8: the day-ago clause drops out when that pace cannot be measured; the kill switch silences" {
  run python3 -c "$LOAD"'
S = [e for e in week() if e["_t"] >= NOW - 30 * 3600.0]   # no anchor near now-48h
line = ca.fleet_pace_line(None, S, NOW)
assert line == WEEK_LINE.replace(" (2.1 a day ago)", ""), line
os.environ["CC_ACCOUNTS_FLEET_PACE"] = "off"
assert ca.fleet_pace_line(None, week(), NOW) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-9: the readouts carry it from the ledger, AMBER on the board and table, plain in markdown" {
  # End to end through CC_UTIL_LOG: fleet_pace_line(rows) reads the series itself at the REAL clock,
  # which runs a few seconds past NOW. The resets move out 15 minutes so that drift cannot carry
  # next4 under 31h (fmt_h truncates: 30.99h is "1d 6h"); every rendered figure is unchanged.
  run python3 -c "$LOAD"'
import contextlib, io, re
with open(os.environ["CC_UTIL_LOG"], "w") as f:
    for e in week(shift=0.25):
        f.write(json.dumps({k: v for k, v in e.items() if k != "_t"}) + "\n")
def rw(acct, wk, wrh):
    return {"acct": acct, "auth": "ok", "k": 0, "k_work": 0, "session_pct": 5, "weekly_pct": wk,
            "fable_pct": 10, "email": acct + "@x.com", "dia_profile": acct.upper(),
            "launcher": "claude-" + acct, "weekly_reset_h": wrh, "fable_reset_h": 40.0,
            "session_reset_h": 3.0, "credits_on": False}
rows = [rw("next2", 94, 9.0), rw("next", 56, 20.0), rw("next4", 44, 31.0), rw("next3", 10, 150.0)]
WIN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
plain = lambda s: re.sub(r"\x1b\[[0-9;]*m", "", s)
md = ca.readout_lines(rows, cfg, WIN, False, narrow=False)
assert WEEK_LINE in md, md
board = ca.readout_lines(rows, cfg, WIN, False, narrow=True)
amber = "\x1b[38;2;%d;%d;%dm" % ca.AMBER
grey = "\x1b[38;2;%d;%d;%dm" % ca.BOARD_LABEL
fp = [ln for ln in board if ln.startswith(amber)]
assert fp and not any(grey in ln for ln in fp), fp
assert " ".join(plain(ln).strip() for ln in fp) == WEEK_LINE, fp
assert all(ca._disp_w(plain(ln)) <= ca.NARROW_W for ln in fp), fp
ca.COLOR = True
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    ca.render_table(rows, cfg, WIN, False, None)
assert ("  " + amber + WEEK_LINE + "\x1b[0m") in buf.getvalue(), buf.getvalue()
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-10: never on the ranking path — apply_burn, ranked() and the --rank/--route CLI do not compute it" {
  # --rank runs inside handoff-fire under a 25 s alarm; this line reads the ledger and belongs to
  # the readout renderers only. The CLI half drives main() itself, because a call added to its
  # --rank/--route branch never passes through ranked(); --readout is the control that the spy is
  # wired (on a binary without the line it counts 0 there too, and the test fails).
  run python3 -c "$LOAD"'
import contextlib, io
orig = (ca.fleet_pace, ca.fleet_pace_line, ca._fleet_burn)
def boom(*a, **k):
    raise AssertionError("fleet pace computed on the ranking path")
ca.fleet_pace = ca.fleet_pace_line = ca._fleet_burn = boom
rows = [{"acct": a, "auth": "ok", "k": 0, "k_work": 0, "session_pct": 5, "weekly_pct": w,
         "fable_pct": 10, "weekly_reset_h": h, "fable_reset_h": 40.0, "session_reset_h": 3.0,
         "credits_on": False} for a, w, h in (("next2", 94, 9.0), ("next4", 44, 31.0))]
ca.apply_burn(rows, cfg, samples=week())
WIN = {"active": True, "end": "2099-12-31", "deadline": None, "permanent": True}
for lane in ("general", "fable", "interactive"):
    ca.ranked(rows, cfg, WIN, lane)
ca.fleet_pace, ca.fleet_pace_line, ca._fleet_burn = orig
cached = [{"acct": "next3", "auth": "ok", "k": 0, "session_pct": 5.0, "session_reset_h": 3.0,
           "weekly_pct": 40.0, "weekly_reset_h": 20.0, "fable_pct": 7, "fable_reset_h": 20.0,
           "credits_on": False}]
json.dump({"ts": time.time(), "cfg_key": ca._cfg_key(cfg), "no_heal": False, "window": WIN,
           "prev": None, "rows": cached}, open(cfg["cache_file"], "w"))
calls = []
def spy(*a, **k):
    calls.append(a)
    return orig[1](*a, **k)
ca.fleet_pace_line = spy
for argv, want in ((["--rank", "general"], 0), (["--route", "general"], 0),
                   (["--rank", "fable"], 0), (["--route", "fable", "--recovery"], 0),
                   (["--readout"], 1)):
    calls.clear()
    sys.argv = ["claude-accounts"] + argv
    out, rc = io.StringIO(), 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            ca.main()
    except SystemExit as e:
        rc = e.code or 0
    assert rc == 0, (argv, rc)
    assert out.getvalue().strip(), argv              # the branch really ran and answered
    assert len(calls) == want, (argv, len(calls))
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-11: an EARLIER reset that holds most of the quota is the one named, by max over resets" {
  # short_pp and needed are maxima over the near resets, not the last one. next2 resets in 9h
  # holding 60pp, next4 in 40h holding 5pp; next3 burns 2.0 pp/h. By next2: 60 - 2 x 9 = 42 dies,
  # needing 60/9 = 6.7 pp/h. By next4 the cumulative 65 needs only 1.6 and leaves -15 — a
  # last-reset reading names next4 and goes silent.
  run python3 -c "$LOAD"'
S = (ser("next2", lambda h: 40.0, 9) + ser("next4", lambda h: 95.0, 40)
     + ser("next", lambda h: 50.0, 120) + ser("next3", lambda h: 98.0 - 2.0 * h, 150))
v = ca.fleet_pace(S, NOW)
assert abs(v["pace"] - 2.0) < 1e-9 and v["near"] == ["next2", "next4"], v
assert (v["by"], v["by_h"]) == ("next2", 9.0), v
assert abs(v["short_pp"] - 42.0) < 1e-9, v
assert abs(v["needed"] - 60.0 / 9.0) < 1e-9, v
assert abs(v["left"] - 65.0) < 1e-9, v
line = ca.fleet_pace_line(None, S, NOW)
assert line == "⚠ 2.0 pp/h fleet burn (2.0 a day ago) vs 6.7 needed — ~42pp dies by next2\x27s reset in 9.0h", line
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "FP-12: a newest row whose weekly reset has already passed is not near, and the line stays silent" {
  # The lower bound of 0 < wrh <= FLEET_NEAR_H. next2 reset 30 minutes ago and the poller has not
  # rolled it yet (its rows still read 20% under the passed stamp, inside FLEET_MAX_AGE_H). An hour
  # ago the same stamp was 0.5h ahead and next2 WAS near with ~80pp left: the fixture is not
  # vacuous, only the passed stamp keeps it out now.
  run python3 -c "$LOAD"'
S = (ser("next2", lambda h: 20.0, -0.5) + ser("next", lambda h: 50.0, 120)
     + ser("next4", lambda h: 50.0, 120) + ser("next3", lambda h: 80.0 - h, 150))
prev = ca.fleet_pace(S, NOW - 3600.0)
assert prev["near"] == ["next2"] and prev["short_pp"] >= ca.FLEET_SHORT_FLOOR_PP, prev
v = ca.fleet_pace(S, NOW)
assert abs(v["pace"] - 1.0) < 1e-9, v
assert v["near"] == [] and v["by"] is None and v["short_pp"] == 0.0, v
assert ca.fleet_pace_line(None, S, NOW) is None
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
