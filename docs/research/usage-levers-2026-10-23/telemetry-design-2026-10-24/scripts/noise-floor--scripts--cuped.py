#!/usr/bin/env python3
# CUPED / regression adjustment on pre-treatment covariates for the event-level idle metrics.
# usage: python3 -I cuped.py <data_dir>
# D3 covariates: context at gap start (prev request ctx), gap>=3600 flag, their product.
# D1 covariates: context at the idle point, main wpp of the session before the idle point.
import math, os, sys
from collections import defaultdict
D = sys.argv[1]; S = 1790398800; E = S + 28 * 86400
W_READ, W_WRITE, W_OUT = 0.0067, 0.245, 0.404
Z = 1.959964 + 0.841621
seen = set(); rows = defaultdict(list)
for a in ["next", "next2", "next3", "next4"]:
    with open(os.path.join(D, a + ".req.tsv")) as fh:
        fh.readline()
        for line in fh:
            v = line.rstrip("\n").split("\t")
            if v[2] != "0" or v[5] in seen: continue
            seen.add(v[5])
            inp, cc, cr, out = int(v[7]), int(v[8]), int(v[10]), int(v[11])
            rows[(a, v[3])].append((float(v[4]), inp + cc + cr, int(v[12]), ((inp + cc) * W_WRITE + cr * W_READ + out * W_OUT) / 1e6))

def ols_resid_var(X, y):
    # tiny normal-equation OLS with intercept
    n = len(y); k = len(X[0]) + 1
    A = [[0.0] * k for _ in range(k)]; b = [0.0] * k
    for xi, yi in zip(X, y):
        r = [1.0] + list(xi)
        for i in range(k):
            b[i] += r[i] * yi
            for j in range(k): A[i][j] += r[i] * r[j]
    # solve A beta = b (Gauss-Jordan)
    M = [A[i] + [b[i]] for i in range(k)]
    for c in range(k):
        p = max(range(c, k), key=lambda r: abs(M[r][c])); M[c], M[p] = M[p], M[c]
        pv = M[c][c]
        if abs(pv) < 1e-18: continue
        M[c] = [x / pv for x in M[c]]
        for r in range(k):
            if r != c:
                f = M[r][c]; M[r] = [x - f * y_ for x, y_ in zip(M[r], M[c])]
    beta = [M[i][k] for i in range(k)]
    res = [yi - (beta[0] + sum(bj * xj for bj, xj in zip(beta[1:], xi))) for xi, yi in zip(X, y)]
    m = sum(y) / n
    vy = sum((yi - m) ** 2 for yi in y) / (n - 1)
    vr = sum(r * r for r in res) / (n - k)
    return vy, vr

def rep(label, X, y, lo, hi):
    vy, vr = ols_resid_var(X, y)
    nw = len(y) / 4.0
    for wk in (1, 2, 4):
        n = nw * wk
        print("%s weeks=%d raw_MDE_pp/wk=%.1f adj_MDE_pp/wk=%.1f R2=%.2f expected=%.1f-%.1f" % (
            label, wk, Z * math.sqrt(2 * vy / (n / 2)) * nw, Z * math.sqrt(2 * vr / (n / 2)) * nw, 1 - vr / vy, lo, hi))

X3, y3, X1, y1 = [], [], [], []
for k, rs in rows.items():
    rs.sort(); got = False
    for i in range(1, len(rs)):
        ts, ctx, turn, wpp = rs[i]
        if ts < S or ts >= E or not turn: continue
        g = ts - rs[i - 1][0]; pc = rs[i - 1][1] / 1e6
        if g >= 3300:
            ex = 1.0 if g >= 3600 else 0.0
            X3.append((pc, ex, pc * ex)); y3.append(wpp)
        if not got and g >= 900 and rs[i - 1][1] >= 200000:
            got = True
            pre = sum(x[3] for x in rs[:i] if x[0] >= S)
            X1.append((pc, pre)); y1.append(sum(x[3] for x in rs[i:] if x[0] < E))
rep("D3", X3, y3, 3.9, 5.1)
rep("D1", X1, y1, 8.0, 11.1)
