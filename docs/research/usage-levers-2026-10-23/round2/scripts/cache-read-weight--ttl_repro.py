#!/usr/bin/env python3
# Reproduce sk-cache-ttlfit2.py's DESIGN on the r2 event data, switching one choice at a time:
# attribution (T vs P), window (7d vs o55 era), estimator (OLS vs NNLS), inp column (absent vs present).
# ttlfit2: 6h calendar buckets from now-7d; y = last - first weekly_pct inside the bucket (>=10 samples,
# no decrease); X = tokens in the WHOLE bucket; OLS, no intercept, no inp column.
import sys

sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
import json, collections
import numpy as np
from datetime import datetime
from fitlib import *

NOW = datetime.fromisoformat(
    "2026-10-24T04:40:00+00:00"
).timestamp()  # ~when ttlfit2 ran (Oct 23 21:40 PDT)
samp_all = collections.defaultdict(list)
for line in open(UTIL):
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("stale") or d.get("weekly_pct") is None:
        continue
    samp_all[d["acct"]].append(
        (datetime.fromisoformat(d["ts"]).timestamp(), d["weekly_pct"])
    )


def run(rule, cut, BK, est, with_inp, label):
    A, acol = load_events(rule)
    A = A[A[:, 0] >= cut]
    feats = [
        lambda S, c=c: S[:, c] / 1e6 for c in (7, 8, 12, 6, 9)
    ]  # cc5, cc1, outMax, inp, cr
    tok_b = collections.defaultdict(lambda: np.zeros(5))
    for i, a in enumerate(ACCTS):
        S = A[A[:, acol] == i]
        bidx = ((S[:, 0] - cut) // BK).astype(int)
        F = np.column_stack([f(S) for f in feats])
        for b in np.unique(bidx):
            tok_b[(a, b)] += F[bidx == b].sum(0)
    samp = collections.defaultdict(list)
    for a, L in samp_all.items():
        for t, w in L:
            if t >= cut:
                samp[(a, int((t - cut) // BK))].append((t, w))
    X, y = [], []
    for k, v in samp.items():
        v.sort()
        if len(v) < 10 or k not in tok_b:
            continue
        ws = [w for _, w in v]
        if any(b < a for a, b in zip(ws, ws[1:])):
            continue
        X.append(tok_b[k])
        y.append(ws[-1] - ws[0])
    X = np.array(X)
    y = np.array(y, float)
    cols = [0, 1, 2, 4] + ([3] if with_inp else [])
    names = ["cc5m", "cc1h", "out", "cr"] + (["inp"] if with_inp else [])
    Xc = X[:, cols]
    b = np.linalg.lstsq(Xc, y, rcond=None)[0] if est == "OLS" else nnls(Xc, y)
    rng = np.random.default_rng(1)
    crs = []
    for _ in range(500):
        ii = rng.integers(0, len(y), len(y))
        bb = (
            np.linalg.lstsq(Xc[ii], y[ii], rcond=None)[0]
            if est == "OLS"
            else nnls(Xc[ii], y[ii])
        )
        crs.append(bb[3])
    lo, hi = np.percentile(crs, [2.5, 97.5])
    print(
        "%-44s n=%3d pp=%4d R2=%.3f  %s  cr 95%%CI [%.5f, %.5f]"
        % (
            label,
            len(y),
            y.sum(),
            r2(Xc, y, b),
            " ".join("%s=%.5f" % (n, v) for n, v in zip(names, b)),
            lo,
            hi,
        )
    )


cut7 = NOW - 7 * 86400
cutE = datetime.fromisoformat("2026-09-28T00:00:00+00:00").timestamp()
run("P", cut7, 6 * 3600, "OLS", False, "ttlfit2 as written: P, 7d, 6h, OLS, no inp")
run("T", cut7, 6 * 3600, "OLS", False, "  attribution T")
run("P", cut7, 6 * 3600, "NNLS", False, "  NNLS")
run("P", cut7, 6 * 3600, "OLS", True, "  + inp column")
run("T", cut7, 6 * 3600, "NNLS", True, "  T + NNLS + inp")
run("P", cutE, 6 * 3600, "OLS", False, "  P, o55 era (from 09-28)")
run("T", cutE, 6 * 3600, "OLS", False, "  T, o55 era")
run("T", cutE, 6 * 3600, "NNLS", True, "  T, o55 era, NNLS + inp")
