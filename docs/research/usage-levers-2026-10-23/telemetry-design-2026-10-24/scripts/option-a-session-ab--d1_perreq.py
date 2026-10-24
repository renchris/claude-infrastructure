#!/usr/bin/env python3
# Option A, D1: is a NORMALISED outcome (main wpp per main request after the first 15-min/200k idle
# point) detectable under session randomization, where the noise-floor key's TOTAL outcome (rest-of-
# session wpp, MDE 28.6 pp/week) was not? A/A permutation over sessions, per calendar week of the
# idle point, with and without regression on pre-treatment covariates (context at the idle point,
# mean wpp per request before it). MDE reported relative to the control mean (80% power, 2-sided 5%).
# usage: python3 -I d1_perreq.py <noise-floor data dir>
import math, os, random, sys
from collections import defaultdict

D = sys.argv[1]
S = 1790398800
E = S + 28 * 86400
WK = 7 * 86400
W_READ, W_WRITE, W_OUT = 0.0067, 0.245, 0.404
Z = 1.959964 + 0.841621
R = 400
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
            inp, cc, cr, out, turn = (
                int(v[7]),
                int(v[8]),
                int(v[10]),
                int(v[11]),
                int(v[12]),
            )
            rows[v[3]].append(
                (
                    float(v[4]),
                    inp + cc + cr,
                    turn,
                    ((inp + cc) * W_WRITE + cr * W_READ + out * W_OUT) / 1e6,
                )
            )
units = []  # (sid, week, post_wpp, post_n, ctx_idle, pre_mean)
for sid, rs in rows.items():
    rs.sort()
    for i in range(1, len(rs)):
        ts, ctx, turn, wpp = rs[i]
        if ts < S or ts >= E or not turn:
            continue
        if ts - rs[i - 1][0] >= 900 and rs[i - 1][1] >= 200000:
            post = [x for x in rs[i:] if x[0] < E]
            pre = rs[:i]
            units.append(
                (
                    sid,
                    int((ts - S) // WK),
                    sum(x[3] for x in post),
                    len(post),
                    rs[i - 1][1] / 1e6,
                    sum(x[3] for x in pre) / len(pre),
                )
            )
            break
print("D1 units_28d=%d per_week=%.0f" % (len(units), len(units) / 4.0))


def resid(X, y):
    k = len(X[0]) + 1
    A = [[0.0] * k for _ in range(k)]
    b = [0.0] * k
    for xi, yi in zip(X, y):
        r = [1.0] + list(xi)
        for i in range(k):
            b[i] += r[i] * yi
            for j in range(k):
                A[i][j] += r[i] * r[j]
    M = [A[i] + [b[i]] for i in range(k)]
    for c in range(k):
        p = max(range(c, k), key=lambda q: abs(M[q][c]))
        M[c], M[p] = M[p], M[c]
        pv = M[c][c]
        if abs(pv) < 1e-18:
            continue
        M[c] = [v / pv for v in M[c]]
        for q in range(k):
            if q != c:
                f = M[q][c]
                M[q] = [v - f * w for v, w in zip(M[q], M[c])]
    be = [M[i][k] for i in range(k)]
    my = sum(y) / len(y)
    return [
        yi - (be[0] + sum(bj * xj for bj, xj in zip(be[1:], xi))) + my
        for xi, yi in zip(X, y)
    ]


def aa(vals, weeks, label):
    rng = random.Random(11)
    mean = sum(vals) / len(vals)
    out = {}
    for wk_set_label, groups in (
        ("1", [[0], [1], [2], [3]]),
        ("2", [[0, 1], [2, 3]]),
        ("4", [[0, 1, 2, 3]]),
    ):
        var = []
        for g in groups:
            idx = [i for i, w in enumerate(weeks) if w in g]
            ds = []
            for _ in range(R):
                t = [rng.random() < 0.5 for _ in idx]
                yt = [vals[i] for i, z in zip(idx, t) if z]
                yc = [vals[i] for i, z in zip(idx, t) if not z]
                if yt and yc:
                    ds.append(sum(yc) / len(yc) - sum(yt) / len(yt))
            m = sum(ds) / len(ds)
            var.append(sum((d - m) ** 2 for d in ds) / (len(ds) - 1))
        out[wk_set_label] = Z * math.sqrt(sum(var) / len(var)) / mean
    print(
        "  %s MDE_rel weeks=1 %.1f%%  weeks=2 %.1f%%  weeks=4 %.1f%%"
        % (label, 100 * out["1"], 100 * out["2"], 100 * out["4"])
    )


weeks = [u[1] for u in units]
y_total = [u[2] for u in units]
y_req = [u[2] / u[3] for u in units]
X = [(u[4], u[5]) for u in units]
aa(y_total, weeks, "rest-of-session wpp (total)              ")
aa(resid(X, y_total), weeks, "rest-of-session wpp, ctx+pre adjusted   ")
aa(y_req, weeks, "wpp per main request after idle point   ")
aa(resid(X, y_req), weeks, "wpp per request, ctx+pre adjusted       ")
print("DONE")
