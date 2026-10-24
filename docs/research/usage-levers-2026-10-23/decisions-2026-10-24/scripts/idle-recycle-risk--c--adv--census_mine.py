# Actual-world (no counterfactual) census over the W4 rows: turn starts after >=15 min idle with the
# idle-point context >=150k, split by opener (1 prompt/wake, 2 job notice) — the shadow-equivalent count.
import csv, collections, sys
from datetime import datetime, timezone
D = "/tmp/usage-audit/w4/"
S, E = (float(x) for x in open(D + "window").read().split())
occ = {}
for a in ("next", "next2", "next3", "next4"):
    with open(D + "rows_%s.tsv" % a) as f:
        r = csv.reader(f, delimiter="\t"); next(r)
        for x in r:
            occ.setdefault(x[4], (x[2], float(x[3]), int(x[6]) + int(x[7]) + int(x[10]), int(x[12])))
sess = collections.defaultdict(list)
for req, (sid, ts, ctx, turn) in occ.items():
    sess[sid].append((ts, ctx, turn))
tot = collections.Counter(); daywin = collections.Counter(); perday = collections.Counter()
lo_h, hi_h = 8 + 21 / 60, 18 + 0 / 60
for sid, L in sess.items():
    L.sort()
    for p, r in zip(L, L[1:]):
        if r[2] and r[0] - p[0] >= 900 and p[1] >= 150000:
            k = "prompt" if r[2] == 1 else "notice"
            tot[k] += 1
            d = datetime.fromtimestamp(r[0], timezone.utc)
            perday[(d.date().isoformat(), k)] += 1
            h = d.hour + d.minute / 60
            if lo_h <= h < hi_h:
                daywin[k] += 1
days = (E - S) / 86400
print("14d actual-world turn starts after >=15m idle at >=150k: prompt-opened %d (%.1f/day), notice-opened %d (%.1f/day)" % (
    tot["prompt"], tot["prompt"] / days, tot["notice"], tot["notice"] / days))
print("same, restricted to 08:21-18:00 UTC each day: prompt-opened %d (%.1f per such window), notice-opened %d (%.1f per window)" % (
    daywin["prompt"], daywin["prompt"] / days, daywin["notice"], daywin["notice"] / days))
pass
win = collections.Counter()
for sid, L in sess.items():
    for p, r in zip(L, L[1:]):
        if r[2] == 1 and r[0] - p[0] >= 900 and p[1] >= 150000:
            d = datetime.fromtimestamp(r[0], timezone.utc); h = d.hour + d.minute / 60
            if lo_h <= h < hi_h: win[d.date().isoformat()] += 1
import statistics
full = sorted((d, n) for d, n in win.items() if "2026-10-11" <= d <= "2026-10-23")
print("per-day prompt-opened in 08:21-18:00Z, full days:", full)
print("median", statistics.median([n for d, n in full]), "min", min(n for d, n in full), "max", max(n for d, n in full), "days", len(full))
