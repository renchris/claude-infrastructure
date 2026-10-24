#!/usr/bin/env python3
# r2 meter refit. usage: python3 -I fit1.py <rule T|B|P|N> <era all|o5|o55> <Hw_hours> <Hs_hours> [R]
import sys
sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
import numpy as np
from datetime import datetime
from fitlib import *

rule, era = sys.argv[1], sys.argv[2]
Hw, Hs = float(sys.argv[3]) * 3600, float(sys.argv[4]) * 3600
R = int(sys.argv[5]) if len(sys.argv) > 5 else 500
A, acol = load_events(rule if rule != "N" else "T", naive=(rule == "N"))
NAMES = ["inp", "cc5m", "cc1h", "cr", "out"]
feats = [lambda S, c=c: S[:, c] / 1e6 for c in (6, 7, 8, 9, 10)] + [
    lambda S: np.ones(len(S)) / 1e3
]
cum = cum_by_acct(A, acol, feats)
U = load_util()
ERA = {
    "all": (datetime.fromisoformat("2026-08-17T00:00:00+00:00").timestamp(), 9e18),
    "o5": (
        datetime.fromisoformat("2026-08-17T00:00:00+00:00").timestamp(),
        datetime.fromisoformat("2026-09-21T00:00:00+00:00").timestamp(),
    ),
    "o55": (datetime.fromisoformat("2026-09-28T00:00:00+00:00").timestamp(), 9e18),
}[era]
HOLD = datetime.fromisoformat("2026-10-17T00:00:00+00:00").timestamp()
LIST = {"inp": 1.0, "cc5m": 1.25, "cc1h": 2.0, "out": 5.0}


def fitN(X, y):
    return nnls(X, y)


for meter, H in (("w", Hw), ("s", Hs)):
    P, st = pairs(U, meter)
    B = [b for b in blocks(P, H) if ERA[0] <= b[1] < ERA[1]]
    X6, y = design(B, cum)
    X = X6[:, :5]
    nreq = X6[:, 5]
    cl = cluster_ids(B)
    print(
        "\n==== rule=%s era=%s meter=%s H=%.1fh  pairs:%s"
        % (rule, era, {"w": "weekly", "s": "5h-session"}[meter], H / 3600, dict(st))
    )
    print(
        "n_blocks=%d sum_pp=%d  tokens in blocks (M): %s  kreq=%.0f"
        % (
            len(y),
            y.sum(),
            " ".join("%s=%.0f" % (n, v) for n, v in zip(NAMES, X.sum(0))),
            nreq.sum(),
        )
    )
    C = np.corrcoef(np.column_stack([X, nreq]).T)
    print(
        "corr cr~out=%.3f cr~cc5=%.3f cr~cc1=%.3f cr~inp=%.3f cr~nreq=%.3f out~cc5=%.3f out~cc1=%.3f inp~nreq=%.3f"
        % (C[3, 4], C[3, 1], C[3, 2], C[3, 0], C[3, 5], C[4, 1], C[4, 2], C[0, 5])
    )
    b = fitN(X, y)
    pred = X @ b
    sh = X * b / pred.sum()
    print(
        "NNLS pp/Mtok: "
        + " ".join("%s=%.5f" % (n, v) for n, v in zip(NAMES, b))
        + "  R2=%.4f" % r2(X, y, b)
    )
    print(
        "  share of predicted pp: "
        + " ".join("%s=%.1f%%" % (n, 100 * v) for n, v in zip(NAMES, sh.sum(0)))
    )
    ols = np.linalg.lstsq(X, y, rcond=None)[0]
    print(
        "OLS (unconstrained): "
        + " ".join("%s=%.5f" % (n, v) for n, v in zip(NAMES, ols))
        + "  R2=%.4f" % r2(X, y, ols)
    )
    bs = boot(X, y, cl, fitN, R=R)
    crsh = (bs[:, 3] * X[:, 3].sum()) / np.maximum(1e-9, (bs * X.sum(0)).sum(1))
    print(
        "cluster bootstrap (acct-day, R=%d) 2.5/50/97.5: " % R
        + " ".join(
            "%s=[%.5f %.5f %.5f]" % (n, *np.percentile(bs[:, i], [2.5, 50, 97.5]))
            for i, n in enumerate(NAMES)
        )
    )
    print(
        "  cr coef == 0 in %.1f%% of resamples; cr share of predicted pp p2.5/50/97.5 = %.1f%% %.1f%% %.1f%%"
        % (100 * (bs[:, 3] == 0).mean(), *(100 * np.percentile(crsh, [2.5, 50, 97.5])))
    )
    # constrained alternatives
    b0 = np.zeros(5)
    keep = [0, 1, 2, 4]
    b0[keep] = nnls(X[:, keep], y)
    print(
        "cr forced 0: "
        + " ".join("%s=%.5f" % (n, v) for n, v in zip(NAMES, b0))
        + "  R2=%.4f" % r2(X, y, b0)
    )
    for crw in (0.0, 0.05, 0.1):
        w = np.array([1, 1.25, 2.0, crw, 5.0])
        z = X @ w
        s = (z @ y) / (z @ z)
        print(
            "  list shape, cr=%.2fx input: scalar=%.5f pp per M input-eq  R2=%.4f"
            % (crw, s, r2(X, y, s * w))
        )
    # with request count as an extra regressor
    Xr = np.column_stack([X, nreq])
    br = nnls(Xr, y)
    print(
        "NNLS + per-1k-request column: "
        + " ".join("%s=%.5f" % (n, v) for n, v in zip(NAMES + ["kreq"], br))
        + "  R2=%.4f" % r2(Xr, y, br)
    )
    # per account (drop inp, which is ~0 tokens and acts as a request-count proxy)
    for i, a in enumerate(ACCTS):
        m = np.array([bb[0] == a for bb in B])
        if m.sum() < 15:
            continue
        ba = nnls(X[m], y[m])
        print(
            "  %-6s n=%3d pp=%4d " % (a, m.sum(), y[m].sum())
            + " ".join("%s=%.5f" % (n, v) for n, v in zip(NAMES, ba))
            + " R2=%.3f cr-share=%.1f%%"
            % (
                r2(X[m], y[m], ba),
                100 * (X[m][:, 3] * ba[3]).sum() / max(1e-9, (X[m] @ ba).sum()),
            )
        )
    # held-out week
    tr = np.array([bb[1] < HOLD for bb in B])
    te = ~tr
    if te.sum() >= 10 and tr.sum() >= 20:
        res = {}
        bF = nnls(X[tr], y[tr])
        b0 = np.zeros(5)
        b0[keep] = nnls(X[tr][:, keep], y[tr])
        res["NNLS full"] = bF
        res["NNLS cr=0"] = b0
        for crw in (0.0, 0.05, 0.1):
            w = np.array([1, 1.25, 2.0, crw, 5.0])
            z = X[tr] @ w
            res["list cr=%.2f" % crw] = w * (z @ y[tr]) / (z @ z)
        yt = y[te]
        print(
            "HELD-OUT week (t0 >= 2026-10-17): n_train=%d n_test=%d observed pp=%d"
            % (tr.sum(), te.sum(), yt.sum())
        )
        for k, bb in res.items():
            p = X[te] @ bb
            e = yt - p
            print(
                "  %-14s pred_pp=%7.1f  test R2=%.4f  RMSE=%.3f  MAE=%.3f  coefs=%s"
                % (
                    k,
                    p.sum(),
                    1 - (e @ e) / ((yt - yt.mean()) @ (yt - yt.mean())),
                    np.sqrt((e @ e) / len(e)),
                    np.abs(e).mean(),
                    " ".join("%.5f" % v for v in bb),
                )
            )
