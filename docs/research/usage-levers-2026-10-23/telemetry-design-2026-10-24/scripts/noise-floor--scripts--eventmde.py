#!/usr/bin/env python3
# Event-level noise for the idle levers, main sessions only, 28-day window.
# usage: python3 -I eventmde.py <data_dir>
# D3 event: a turn-start request after a gap >= 3300 s; outcome = weighted pp of that first request
#           (the cache rebuild a keepalive would avoid). D1 event: first turn start per session after
#           >= 900 s idle at >= 200k context; outcome = weighted pp of all later main requests in that session.
# MDE (event-randomized 50/50 over 7 days) = 2.80 * sqrt(2 * var / (n_week / 2)), expressed in pp/week fleet
# (per-event MDE x events per week), so it compares directly with the decisions' expected pp/week.
import math
import os
import sys
from collections import defaultdict

D = sys.argv[1]
S = 1790398800
E = S + 28 * 86400
W_READ, W_WRITE, W_OUT = 0.0067, 0.245, 0.404
Z = 1.959964 + 0.841621
seen = set()
rows = defaultdict(list)
for a in ["next", "next2", "next3", "next4"]:
    with open(os.path.join(D, a + ".req.tsv")) as fh:
        fh.readline()
        for line in fh:
            v = line.rstrip("\n").split("\t")
            if v[2] != "0" or v[5] in seen:
                continue
            seen.add(v[5])
            ts = float(v[4])
            inp, cc, cr, out, turn = (
                int(v[7]),
                int(v[8]),
                int(v[10]),
                int(v[11]),
                int(v[12]),
            )
            wpp = ((inp + cc) * W_WRITE + cr * W_READ + out * W_OUT) / 1e6
            rows[(a, v[3])].append((ts, inp + cc + cr, turn, wpp, cc * W_WRITE / 1e6))


def summ(xs, label, expect_lo, expect_hi):
    n = len(xs)
    m = sum(xs) / n
    var = sum((x - m) ** 2 for x in xs) / (n - 1)
    nw = n / 4.0
    mde_ev = Z * math.sqrt(2 * var / (nw / 2))
    srt = sorted(xs)
    print(
        "%s n_28d=%d per_week=%.0f mean=%.4f sd=%.4f p50=%.4f p90=%.4f cv=%.2f MDE_per_event=%.4f MDE_pp_per_week=%.1f expected=%.1f-%.1f"
        % (
            label,
            n,
            nw,
            m,
            math.sqrt(var),
            srt[n // 2],
            srt[int(0.9 * n)],
            math.sqrt(var) / m,
            mde_ev,
            mde_ev * nw,
            expect_lo,
            expect_hi,
        )
    )


d3 = []
d3cc = []
d1 = []
for k, rs in rows.items():
    rs.sort()
    got_d1 = False
    for i in range(1, len(rs)):
        ts, ctx, turn, wpp, ccpp = rs[i]
        if ts < S or ts >= E or not turn:
            continue
        g = ts - rs[i - 1][0]
        if g >= 3300:
            d3.append(wpp)
            d3cc.append(ccpp)
        if not got_d1 and g >= 900 and rs[i - 1][1] >= 200000:
            got_d1 = True
            d1.append(sum(x[3] for x in rs[i:] if x[0] < E))
summ(d3, "D3 first-request-after-55min-gap wpp", 3.9, 5.1)
summ(d3cc, "D3 same, cache-write part only", 3.9, 5.1)
summ(d1, "D1 rest-of-session wpp after first 15min/200k idle point", 8.0, 11.1)
