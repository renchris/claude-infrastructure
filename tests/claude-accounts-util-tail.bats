#!/usr/bin/env bats
# _util_tail — the utilization series is selected by TIME, and it reports the span it ACHIEVED
# (USAGE_TELEMETRY_100P §5.2 S1b, RED-proof cases RP-6..RP-8 plus the regression control RP-8b).
#
# THE DEFECT. `_util_tail(path=None, max_bytes=131072)` was called argument-less by apply_burn,
# so the lookback was whatever 128 KiB happened to buy. Against the live file (3,675,531 B, mean
# record 292.4 B) that is 407 rows spanning 12.16 h, while the docstring claimed 48 h — so M2's
# 48 h lookback was unreachable and every metric fitted on it was fitted on a window that does
# not exist. The coupling is also INVERTED: adding one field to the record shortens the window.
#
# RP-8b IS THE LOAD-BEARING CASE and it is why the reader fix could not land alone. At a TRUE
# 48 h span the incumbent widest-pair weekly estimator anchors on a sample from BEFORE the
# weekly reset, reads `d < 0`, and leaves the field absent for the whole first stretch of every
# weekly window — the estimator goes blind exactly when the week's plan is set. Restoring the
# span without making the anchor roll-aware is a REGRESSION, not a fix (§5.5). A green suite
# that does not prove this is a vacuous suite.
#
# Hermetic: $HOME and $CLAUDE_CONFIG_DIR into BATS_TEST_TMPDIR; every case passes `path=`.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CA_BIN="$REPO/bin/claude-accounts"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CC_UTIL_LOG="$BATS_TEST_TMPDIR/util-series.jsonl"
}

LOAD='
import importlib.machinery, importlib.util, json, os, sys, time
from datetime import datetime, timedelta, timezone
sys.argv = ["claude-accounts"]
loader = importlib.machinery.SourceFileLoader("ca", os.environ["CA_BIN"])
ca = importlib.util.module_from_spec(importlib.util.spec_from_loader("ca", loader))
loader.exec_module(ca)
ca.LOG_PATH = os.path.join(os.environ["BATS_TEST_TMPDIR"], "claude-accounts.log")
TMP = os.environ["BATS_TEST_TMPDIR"]
NOW = datetime.now(timezone.utc)
def rec(mins_ago, sp=10, wp=40, acct="next3", sra=None, wra=None):
    # padded to ~292 B, the live mean record size, so the byte pre-filter faces the real regime
    e = {"ts": (NOW - timedelta(minutes=mins_ago)).isoformat(), "acct": acct, "k": 2,
         "k_work": 1, "k_src": "work", "session_pct": sp, "weekly_pct": wp, "fable_pct": 5,
         "session_reset_at": sra, "weekly_reset_at": wra, "credits_on": False, "auth": "ok"}
    s = json.dumps(e)
    e["pad"] = "x" * max(0, 291 - len(s) - 10)
    return json.dumps(e) + "\n"
'

# The stop-rule cases (B4 C3) freeze the clock so the cutoff is exact, count json.loads, and
# compare against a brute-force read of every file.
C3='
import glob, gzip
FIX = NOW.timestamp()
ca.time.time = lambda: FIX
ACCTS = ("next", "next2", "next3", "next4")
def burst_file(p, mins, every=5.0, off=2.5, stale_every=0, junk_every=0, opener=open):
    # one 4-row burst (shared ts) every EVERY min, the newest OFF min ago, back to MINS (or a lo-hi pair)
    lo, hi = mins if isinstance(mins, tuple) else (0, mins)
    with opener(p, "wt") as f:
        k = int((hi - off) // every)
        while off + k * every >= lo:
            for i, a in enumerate(ACCTS):
                ln = rec(off + k * every, acct=a)
                if stale_every and (k + i) % stale_every == 0:
                    e = json.loads(ln); e["stale"] = True; ln = json.dumps(e) + "\n"
                f.write(ln)
                if junk_every and (k + i) % junk_every == 0:
                    f.write("{not json\n")
            k -= 1
def counted(fn, *a, **k):
    n, real = [0], ca.json.loads
    ca.json.loads = lambda *x, **y: (n.__setitem__(0, n[0] + 1), real(*x, **y))[1]
    try:
        return fn(*a, **k), n[0]
    finally:
        ca.json.loads = real
def brute(paths, hours):
    cut, out = FIX - hours * 3600, []
    for p in paths:
        with (gzip.open(p, "rt") if p.endswith(".gz") else open(p)) as f:
            for ln in f:
                try:
                    e = json.loads(ln)
                    t = datetime.fromisoformat(e["ts"]).timestamp()
                except (ValueError, KeyError):
                    continue
                if t >= cut and not e.get("stale"):
                    e["_t"] = t; out.append(e)
    return sorted(out, key=lambda e: e["_t"])
def rows_off(*a, **k):
    os.environ["CC_UTIL_TAIL_CROSS"] = "off"
    try:
        return ca._util_tail_read(*a, **k)[0]
    finally:
        del os.environ["CC_UTIL_TAIL_CROSS"]
'

@test "RP-6: _util_tail honours a TIME span, not a byte cap (128 KiB buys 12 h of the live series)" {
  # 4,400 records at 6 min spacing = 440 h, ~1.29 MB, i.e. ~9x the old 128 KiB cap. A byte-capped
  # reader returns ~45 h of THIS fixture only because its record is small; against the live file
  # the same cap buys 12.16 h. The span assertion is what makes the case regime-independent.
  run python3 -c "$LOAD"'
p = os.path.join(TMP, "util.jsonl")
with open(p, "w") as f:
    for i in range(4400, 0, -1):
        f.write(rec(i * 6))
assert os.path.getsize(p) > 9 * 131072, os.path.getsize(p)
rows, span = ca._util_tail(path=p, hours=48.0)
assert span >= 47.0, span
assert min(r["_t"] for r in rows) <= time.time() - 47 * 3600, span
assert max(r["_t"] for r in rows) >= time.time() - 3600, span
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-7 CONTROL: a genuinely short series reports its SHORT span and does not lie" {
  # Every downstream abstain rule is written against the ACHIEVED span. An implementation that
  # returns the REQUESTED 48.0 passes RP-6 and fails here, and every consumer below it then
  # abstains on a span it never had — L2 inverted.
  run python3 -c "$LOAD"'
p = os.path.join(TMP, "short.jsonl")
with open(p, "w") as f:
    for i in range(20, 0, -1):
        f.write(rec(i * 6))
rows, span = ca._util_tail(path=p, hours=48.0)
assert len(rows) == 20, len(rows)
assert span < 3.0, span
assert span > 1.5, span
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-8 CONTROL: rotation — a .gz sibling is read when the live file is short" {
  # config/store-bounds.manifest:47 rotates this store at 25 MiB; at 237 KiB/day that lands
  # ~2026-12-11. Readers that open only the live path drop to a series of length ~0 that day.
  run python3 -c "$LOAD"'
import gzip
p = os.path.join(TMP, "rot.jsonl")
with open(p, "w") as f:
    for i in range(30, 0, -1):
        f.write(rec(i * 6))                      # newest 3 h only
with gzip.open(p + ".20260801T000000Z.gz", "wt") as f:
    for i in range(630, 30, -1):
        f.write(rec(i * 6))                      # the prior 60 h
rows, span = ca._util_tail(path=p, hours=48.0)
assert span >= 47.0, span
assert min(r["_t"] for r in rows) <= time.time() - 47 * 3600, span
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-8b: at a TRUE 48 h span the weekly anchor is roll-aware, so restoring the span is not a regression" {
  # The pairing this whole commit exists to keep together. 48 h of samples with the weekly window
  # rolling 30 h ago (96 -> 2 pp, reset stamp +168 h). The incumbent anchors on wk[0] — pre-roll,
  # 96 pp — reads d = 20 - 96 < 0, and leaves burn_wk_ppd ABSENT. Roll-aware, the anchor walks
  # forward to the post-roll segment and the same estimator measures 18 pp over 30 h = 14.4 %/d.
  run python3 -c "$LOAD"'
p = os.path.join(TMP, "roll48.jsonl")
OLD = (NOW + timedelta(hours=2)).isoformat()
NEW = (NOW + timedelta(hours=170)).isoformat()
with open(p, "w") as f:
    for i in range(48 * 10, 30 * 10, -1):        # 48 h .. 30 h ago: pre-roll, climbing to 96
        f.write(rec(i * 6, wp=96 - (i - 300) // 20, wra=OLD))
    for i in range(30 * 10, 0, -1):              # 30 h .. now: post-roll, 2 -> 20
        f.write(rec(i * 6, wp=2 + (300 - i) * 18 // 300, wra=NEW))
rows, span = ca._util_tail(path=p, hours=48.0)
assert span >= 47.0, span
r = {"acct": "next3"}
ca.apply_burn([r], {}, samples=rows)
assert "burn_wk_ppd" in r, r
assert 12.0 < r["burn_wk_ppd"] < 17.0, r
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "RP-8c CONTROL: with NO roll in the span the anchor stays at the oldest sample" {
  # Without this, RP-8b is satisfied by an implementation that always anchors on the newest few
  # samples — which would silently shorten every measurement window to nothing.
  run python3 -c "$LOAD"'
p = os.path.join(TMP, "noroll48.jsonl")
WRA = (NOW + timedelta(hours=100)).isoformat()
with open(p, "w") as f:
    for i in range(48 * 10, 0, -1):
        f.write(rec(i * 6, wp=20 + (480 - i) * 24 // 480, wra=WRA))
rows, span = ca._util_tail(path=p, hours=48.0)
r = {"acct": "next3"}
ca.apply_burn([r], {}, samples=rows)
assert "burn_wk_ppd" in r, r
assert 11.0 < r["burn_wk_ppd"] < 13.0, r      # 24 pp over 48 h = 12 %/d, the FULL span
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- the per-process memo (docs/plans/ACCOUNTS_BOARD_FRESHNESS.md D8) ------------------------------
# One board render read the 16 MB series twice — apply_burn 336 h, then fleet_pace_line 72 h — and
# cProfile put _util_tail at 1.22 s of a 1.51 s render. The memo serves the narrower request from
# the wider read, and only in the board-rendering verbs.

@test "memo: 336 h then 72 h in one process returns exactly what unmemoized reads return, with ONE read" {
  run python3 -c "$LOAD"'
p = os.path.join(TMP, "util.jsonl")
with open(p, "w") as f:
    for i in range(3000, 0, -1):
        f.write(rec(i * 6))
plain = {h: ca._util_tail(path=p, hours=h) for h in (336.0, 72.0)}
reads = []
real = ca._util_tail_read
ca._util_tail_read = lambda *a, **k: (reads.append(a), real(*a, **k))[1]
ca._UTIL_MEMO_ON = True
for h in (336.0, 72.0):
    rows, span = ca._util_tail(path=p, hours=h)
    assert rows == plain[h][0] and abs(span - plain[h][1]) < 1e-9, (h, len(rows), len(plain[h][0]))
assert len(reads) == 1, reads
rows[0]["weekly_pct"] = -1                                      # served as COPIES
assert ca._util_tail(path=p, hours=72.0)[0][0]["weekly_pct"] != -1
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "memo: a wider request after a narrower one re-reads; a size or mtime change invalidates" {
  run python3 -c "$LOAD"'
p = os.path.join(TMP, "util.jsonl")
with open(p, "w") as f:
    for i in range(500, 0, -1):
        f.write(rec(i * 6))
reads = []
real = ca._util_tail_read
ca._util_tail_read = lambda *a, **k: (reads.append(a), real(*a, **k))[1]
ca._UTIL_MEMO_ON = True
ca._util_tail(path=p, hours=72.0)
ca._util_tail(path=p, hours=336.0)
assert len(reads) == 2, reads
ca._util_tail(path=p, hours=72.0)
assert len(reads) == 2
with open(p, "a") as f:
    f.write(rec(0, wp=99))
rows, _ = ca._util_tail(path=p, hours=72.0)
assert len(reads) == 3 and rows[-1]["weekly_pct"] == 99, reads
st = os.stat(p)
os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))
ca._util_tail(path=p, hours=72.0)
assert len(reads) == 4, reads
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "memo: OFF under --route and --rank (the launch path), ON under --keepwarm and --readout" {
  run python3 -c "$LOAD"'
class Stop(Exception):
    pass
def stop(**k):
    raise Stop()
ca.load_cfg = stop
for argv, want in ((["--route", "interactive", "--max-wait", "0"], False),
                   (["--rank", "interactive", "--max-wait", "0"], False),
                   (["--keepwarm"], True), (["--readout"], True)):
    ca._UTIL_MEMO_ON = None
    sys.argv = ["claude-accounts"] + argv
    try:
        ca.main()
    except Stop:
        pass
    assert ca._UTIL_MEMO_ON is want, (argv, ca._UTIL_MEMO_ON)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

# ---- the stop rule (LR_SUSTAINED_LOAD W3, B4 C3) ----------------------------------------------------
# The old rule stopped only when a KEPT row fell within 60 s after the cutoff. The log is written
# in bursts, so on ~85% of calls the read doubled to the whole file (and walked every rotated
# sibling). A read now also stops once a slice reaches back past cutoff - UTIL_TAIL_CROSS_SLACK_S.

@test "U1 RED (RP-9): a read that crossed the cutoff stops, keeping exactly the brute-force rows" {
  run python3 -c "$LOAD$C3"'
p = os.path.join(TMP, "u1.jsonl")
burst_file(p, 20 * 1440)                     # cutoff 48 h falls 2.5 min from a burst on each side
(rows, span), n = counted(ca._util_tail_read, p, 48.0)
want = brute([p], 48.0)
assert rows == want, (len(rows), len(want))
n49 = len(brute([p], 49.0))
lines = sum(1 for _ in open(p))
print("json.loads=%d kept=%d n49=%d lines=%d" % (n, len(rows), n49, lines))
assert n <= 4 * n49 + 131072 // 250, (n, n49)          # before C3: ~2x the whole file
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "U2 RED (RP-10): a rotated history is read only as far back as the span — one sibling for 48 h" {
  # Offset so NO row lands within 60 s after the cutoff (the old rule's only stop), and sibling
  # mtimes set newest-first as rotate-autonomy-logs leaves them (B4 correctness review F6).
  run python3 -c "$LOAD$C3"'
p = os.path.join(TMP, "u2.jsonl")
burst_file(p, 180)                                                  # live: newest 3 h
sibs = []
for i, (lo, hi) in enumerate(((180, 3780), (3780, 7380), (7380, 10980))):   # three 60 h siblings
    s = p + ".2026080%dT000000Z.gz" % (3 - i)
    burst_file(s, (lo, hi), opener=gzip.open)
    os.utime(s, (FIX - 3600 * (1 + i), FIX - 3600 * (1 + i)))
    sibs.append(s)
opened, real = [], ca.gzip.open
ca.gzip.open = lambda f, *a, **k: (opened.append(f), real(f, *a, **k))[1]
rows, span = ca._util_tail_read(p, 48.0)
ca.gzip.open = real
assert rows == brute([sibs[0], p], 48.0), len(rows)
assert opened == [sibs[0]], opened                                  # before C3: all three
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "U3: CC_UTIL_TAIL_CROSS=off and ~/.claude/state/util-tail-cross.off restore the old stop rule, read per call" {
  run python3 -c "$LOAD$C3"'
p = os.path.join(TMP, "u3.jsonl")
burst_file(p, 20 * 1440)
lines = sum(1 for _ in open(p))
off = os.path.join(os.environ["HOME"], ".claude", "state", "util-tail-cross.off")
os.makedirs(os.path.dirname(off), exist_ok=True)
def loads():
    return counted(ca._util_tail_read, p, 48.0)[1]
on = loads()
os.environ["CC_UTIL_TAIL_CROSS"] = "off"
env_off = loads()
del os.environ["CC_UTIL_TAIL_CROSS"]
open(off, "w").close()
file_off = loads()
os.remove(off)
print("on=%d env_off=%d file_off=%d lines=%d" % (on, env_off, file_off, lines))
assert on < lines and env_off >= lines and file_off >= lines and loads() == on
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "U4: rows are identical with the stop rule on and off — 8 spans x 5 fixtures" {
  # EQUIVALENCE GUARD. Mutant: break after the first slice unconditionally -> spans past the seed differ.
  run python3 -c "$LOAD$C3"'
F = {}
F["even"] = os.path.join(TMP, "even.jsonl"); burst_file(F["even"], 17 * 1440, every=6.0, off=0.0)
F["bursty"] = os.path.join(TMP, "bursty.jsonl"); burst_file(F["bursty"], 17 * 1440)
F["stale"] = os.path.join(TMP, "stale.jsonl"); burst_file(F["stale"], 17 * 1440, stale_every=7)
F["junk"] = os.path.join(TMP, "junk.jsonl"); burst_file(F["junk"], 17 * 1440, junk_every=11)
F["rotated"] = os.path.join(TMP, "rot.jsonl"); burst_file(F["rotated"], 180)
for i, (lo, hi) in enumerate(((180, 9000), (9000, 17820), (17820, 26640))):
    s = F["rotated"] + ".2026080%dT000000Z.gz" % (3 - i)
    burst_file(s, (lo, hi), opener=gzip.open)
    os.utime(s, (FIX - 3600 * (1 + i), FIX - 3600 * (1 + i)))
n = 0
for name, p in sorted(F.items()):
    files = sorted(glob.glob(p + ".*"), key=os.path.getmtime) + [p]
    for h in (0.5, 2.0, 6.0, 48.0, 49.0, 72.0, 336.0, 400.0):
        on, off = ca._util_tail_read(p, h)[0], rows_off(p, h)
        assert on == off, (name, h, len(on), len(off))
        assert on == brute(files, h), (name, h, len(on))     # both arms share the loop, so also
                                                             # against every row on disk
        assert on, (name, h)
        n += 1
print("OK", n)'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "U5: one write inversion straddling the cutoff, seed slice split between the pair, keeps the old rule's rows" {
  # Red on the slack-less prototype (B4 correctness review F3, c3adv.py): B (cutoff+30 s) is
  # written BEFORE A (cutoff-30 s); the seed slice holds A but not B. Without the slack, A reads as
  # "crossed" and the read stops, losing B. Mutant UTIL_TAIL_CROSS_SLACK_S = 0 -> red.
  run python3 -c "$LOAD$C3"'
iso = lambda t: datetime.fromtimestamp(t, timezone.utc).isoformat()
H = 2.0
cut = FIX - H * 3600
line = lambda t, **x: json.dumps(dict({"ts": iso(t), "acct": "next3", "session_pct": 1,
                                       "weekly_pct": 2}, **x)) + "\n"
tail = "".join(line(cut + 120 + i * 300) for i in range(int((FIX - cut - 120) // 300) + 1))
B = line(cut + 30, pad="b" * 250)
A0 = line(cut - 30, pad="")
A = line(cut - 30, pad="a" * (131072 - 150 - len(tail) - len(A0)))
assert len(A) + len(tail) < 131072 < len(B) + len(A) + len(tail)
p = os.path.join(TMP, "u5.jsonl")
with open(p, "w") as f:
    f.writelines(line(cut - 7200 - i * 300) for i in range(600, 0, -1))
    f.write(B + A + tail)
new, old = ca._util_tail_read(p, H)[0], rows_off(p, H)
assert any(r.get("pad", "").startswith("b") for r in old), "the fixture lost B under the OLD rule"
assert new == old == brute([p], H), (len(new), len(old))
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}

@test "U6: rows come back in time order whichever path stopped the read (the sort is unconditional)" {
  # Before C3 only the sibling walk sorted; a read that now stops in the live file must not hand
  # back FILE order. Mutant: sort only inside the sibling branch -> red.
  run python3 -c "$LOAD$C3"'
p = os.path.join(TMP, "u6.jsonl")
burst_file(p, 3 * 1440)
ls = open(p).readlines()
ls[-1], ls[-9] = ls[-9], ls[-1]                       # one inversion inside the kept window
open(p, "w").writelines(ls)
rows = ca._util_tail_read(p, 6.0)[0]
assert [r["_t"] for r in rows] == sorted(r["_t"] for r in rows)
assert rows == brute([p], 6.0), len(rows)
print("OK")'
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *OK* ]] || { echo "$output"; false; }
}
