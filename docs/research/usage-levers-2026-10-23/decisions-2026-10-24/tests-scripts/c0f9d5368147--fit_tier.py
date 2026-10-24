#!/usr/bin/env python3
# Does a 1h-tier cache write carry a higher meter weight than a 5m-tier write?
# Re-fits round 2's fit4 data (Opus 5.5 era, T attribution, same blocks) with the write column split
# into ephemeral_5m (cc5) and ephemeral_1h (cc1). Read-only over /tmp/usage-audit/r2/cache-read-weight.
# usage: python3 -I fit_tier.py
import sys

sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
from datetime import datetime

import numpy as np
from fitlib import (
    blocks,
    boot,
    cluster_ids,
    cum_by_acct,
    design,
    load_events,
    load_util,
    nnls,
    pairs,
    r2,
)

A, acol = load_events("T")
U = load_util()
E0 = datetime.fromisoformat("2026-09-28T00:00:00+00:00").timestamp()
HOLD = datetime.fromisoformat("2026-10-17T00:00:00+00:00").timestamp()
k = A[:, 0] >= E0 - 86400
TMAX = float(A[:, 0].max())
print("last event (UTC)", datetime.utcfromtimestamp(TMAX))
print(
    "events in era: %d; main rows with cc5>0: %d; sub rows with cc1>0: %d; cc5 tok main %.1fM sub %.1fM; cc1 tok main %.1fM sub %.1fM"
    % (
        k.sum(),
        ((A[:, 5] == 0) & (A[:, 7] > 0) & k).sum(),
        ((A[:, 5] == 1) & (A[:, 8] > 0) & k).sum(),
        A[k & (A[:, 5] == 0), 7].sum() / 1e6,
        A[k & (A[:, 5] == 1), 7].sum() / 1e6,
        A[k & (A[:, 5] == 0), 8].sum() / 1e6,
        A[k & (A[:, 5] == 1), 8].sum() / 1e6,
    )
)
feats = [
    lambda S: S[:, 6] / 1e6,
    lambda S: S[:, 7] / 1e6,
    lambda S: S[:, 8] / 1e6,
    lambda S: S[:, 9] / 1e6,
    lambda S: S[:, 10] / 1e6,
]
names = ["inp", "cc5", "cc1", "cr", "out"]
cum = cum_by_acct(A, acol, feats)
for meter, H in (("w", 3 * 3600), ("s", 3600)):
    P, st = pairs(U, meter)
    B = [b for b in blocks(P, H) if b[1] >= E0 and b[2] <= TMAX]
    X, y = design(B, cum)
    cl = cluster_ids(B)
    tr = np.array([bb[1] < HOLD for bb in B])
    te = ~tr
    print(
        "\nmeter=%s blocks=%d pp=%.0f  share of write tokens 1h: %.1f%%; corr(cc5,cc1) across blocks %.3f"
        % (
            meter,
            len(y),
            y.sum(),
            100 * X[:, 2].sum() / (X[:, 1] + X[:, 2]).sum(),
            np.corrcoef(X[:, 1], X[:, 2])[0, 1],
        )
    )
    b = nnls(X, y)
    bs = boot(X, y, cl, nnls, R=500)
    print(
        "  free split: R2 %.4f  " % r2(X, y, b)
        + "  ".join(
            "%s=%.5f[%.5f,%.5f]" % (n, b[i], *np.percentile(bs[:, i], [2.5, 97.5]))
            for i, n in enumerate(names)
        )
    )
    ok = bs[:, 1] > 0
    rat = bs[ok, 2] / bs[ok, 1]
    print(
        "  ratio cc1/cc5: point %.3f; bootstrap median %.3f, 95%% [%.3f, %.3f]; P(ratio>=1.6) %.1f%%; P(ratio>1) %.1f%% (n=%d)"
        % (
            b[2] / b[1],
            np.median(rat),
            *np.percentile(rat, [2.5, 97.5]),
            100 * (rat >= 1.6).mean(),
            100 * (rat > 1).mean(),
            ok.sum(),
        )
    )

    def fit_ratio(rho, Xa, ya):
        Z = np.column_stack([Xa[:, 0], Xa[:, 1] + rho * Xa[:, 2], Xa[:, 3], Xa[:, 4]])
        return nnls(Z, ya), Z

    for rho in (1.0, 1.25, 1.6, 2.0):
        bb, Z = fit_ratio(rho, X, y)
        e = y - Z @ bb
        bt, Zt = fit_ratio(rho, X[tr], y[tr])
        Zte = np.column_stack(
            [X[te][:, 0], X[te][:, 1] + rho * X[te][:, 2], X[te][:, 3], X[te][:, 4]]
        )
        et = y[te] - Zte @ bt
        print(
            "  ratio fixed %.2f: SSE %.1f R2 %.4f | w5m %.4f w1h %.4f cr %.5f | held-out RMSE %.4f"
            % (
                rho,
                e @ e,
                1 - e @ e / ((y - y.mean()) @ (y - y.mean())),
                bb[1],
                bb[1] * rho,
                bb[2],
                np.sqrt(et @ et / te.sum()),
            )
        )
    # reads pinned at round 3's weekly midpoint (weekly meter only)
    if meter == "w":
        yr = y - 0.0067 * X[:, 3]
        Xr = X[:, [0, 1, 2, 4]]
        br = nnls(Xr, yr)
        bsr = boot(Xr, yr, cl, nnls, R=500)
        okr = bsr[:, 1] > 0
        rr = bsr[okr, 2] / bsr[okr, 1]
        print(
            "  reads pinned 0.0067: w5m %.4f w1h %.4f ratio %.3f; bootstrap 95%% [%.3f, %.3f]; P(>=1.6) %.1f%%"
            % (
                br[1],
                br[2],
                br[2] / br[1],
                *np.percentile(rr, [2.5, 97.5]),
                100 * (rr >= 1.6).mean(),
            )
        )
