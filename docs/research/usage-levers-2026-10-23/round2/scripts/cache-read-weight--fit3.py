#!/usr/bin/env python3
# Robustness on the clean Opus-5.5 era: leave-one-week-out CV, block length, intercept.
import sys

sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
import numpy as np
from datetime import datetime, timezone
from fitlib import *

A, acol = load_events("T")
NAMES = ["cc5", "cc1", "cr", "out", "kreq"]
feats = [lambda S, c=c: S[:, c] / 1e6 for c in (7, 8, 9, 10)] + [
    lambda S: np.ones(len(S)) / 1e3
]
cum = cum_by_acct(A, acol, feats)
U = load_util()
E0 = datetime.fromisoformat("2026-09-28T00:00:00+00:00").timestamp()
LISTW = lambda crw: np.array([1.25, 2.0, crw, 5.0, 0.0])


def models(Xtr, ytr):
    out = {}
    out["NNLS full"] = nnls(Xtr, ytr)
    b = np.zeros(5)
    k = [0, 1, 3, 4]
    b[k] = nnls(Xtr[:, k], ytr)
    out["NNLS cr=0"] = b
    b = np.zeros(5)
    k = [0, 1, 2, 3]
    b[k] = nnls(Xtr[:, k], ytr)
    out["NNLS no-kreq"] = b
    for crw in (0.0, 0.05):
        w = LISTW(crw)
        z = Xtr @ w
        out["list cr=%.2f" % crw] = w * (z @ ytr) / (z @ z)
    return out


for meter, H in (("w", 3 * 3600), ("s", 3600)):
    P, st = pairs(U, meter)
    B = [b for b in blocks(P, H) if b[1] >= E0]
    X, y = design(B, cum)
    wk = np.array(
        [datetime.fromtimestamp(b[1], timezone.utc).strftime("%G-W%V") for b in B]
    )
    print(
        "\n== meter=%s H=%.0fh LOWO-CV over weeks %s (n=%d)"
        % (meter, H / 3600, sorted(set(wk)), len(y))
    )
    agg = {}
    for w in sorted(set(wk)):
        te = wk == w
        M = models(X[~te], y[~te])
        line = []
        for k, b in M.items():
            p = X[te] @ b
            e = y[te] - p
            agg.setdefault(k, [0.0, 0.0, 0.0])
            agg[k][0] += e @ e
            agg[k][1] += p.sum()
            agg[k][2] += y[te].sum()
            line.append(
                "%s RMSE=%.3f pred/obs=%.3f"
                % (k, np.sqrt(e @ e / te.sum()), p.sum() / y[te].sum())
            )
        print(
            "  %s n=%3d obs=%4d | %s | cr coef(full)=%.5f"
            % (w, te.sum(), y[te].sum(), " | ".join(line), M["NNLS full"][2])
        )
    for k, v in agg.items():
        print(
            "  POOLED %-14s RMSE=%.3f  pred/obs=%.3f"
            % (k, np.sqrt(v[0] / len(y)), v[1] / v[2])
        )

print(
    "\n== block-length sensitivity (weekly meter, o55 era), and with an intercept per block-hour"
)
P, st = pairs(U, "w")
for Hh in (1, 2, 3, 6, 12, 24):
    B = [b for b in blocks(P, Hh * 3600) if b[1] >= E0]
    X, y = design(B, cum)
    b = nnls(X, y)
    hrs = np.array([(t1 - t0) / 3600 for a, t0, t1, d in B])
    Xi = np.column_stack([X, hrs])
    bi = nnls(Xi, y)
    cl = cluster_ids(B)
    bs = boot(X, y, cl, nnls, R=200)
    lo, hi = np.percentile(bs[:, 2], [2.5, 97.5])
    sh = X[:, 2].sum() * b[2] / (X @ b).sum()
    print(
        "  H=%2dh n=%4d R2=%.3f cr=%.5f CI[%.5f %.5f] zero=%2.0f%% cr-share=%.1f%% | %s | +intercept: cr=%.5f pp/h=%.4f R2=%.3f"
        % (
            Hh,
            len(y),
            r2(X, y, b),
            b[2],
            lo,
            hi,
            100 * (bs[:, 2] == 0).mean(),
            100 * sh,
            " ".join("%s=%.4f" % (n, v) for n, v in zip(NAMES, b)),
            bi[2],
            bi[5],
            r2(Xi, y, bi),
        )
    )
