# Brief's 4-class spec (inp, cache writes, cache reads, output) on the clean Opus-5.5 era, T attribution.
import sys, json
sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
import numpy as np
from datetime import datetime
from fitlib import *
A, acol = load_events("T")
U = load_util()
E0 = datetime.fromisoformat("2026-09-28T00:00:00+00:00").timestamp()
HOLD = datetime.fromisoformat("2026-10-17T00:00:00+00:00").timestamp()
res = {}
for outcol, olab in ((10, "out_final"), (11, "out_first")):
    feats = [lambda S: S[:, 6] / 1e6, lambda S: (S[:, 7] + S[:, 8]) / 1e6, lambda S: S[:, 9] / 1e6, lambda S, c=outcol: S[:, c] / 1e6]
    names = ["inp", "cw", "cr", "out"]
    cum = cum_by_acct(A, acol, feats)
    for meter, H in (("w", 3 * 3600), ("s", 3600)):
        P, st = pairs(U, meter)
        B = [b for b in blocks(P, H) if b[1] >= E0]
        X, y = design(B, cum)
        b = nnls(X, y)
        bs = boot(X, y, cluster_ids(B), nnls, R=500)
        sh = X * b
        crsh = bs[:, 2] * X[:, 2].sum() / np.maximum(1e-9, (bs * X.sum(0)).sum(1))
        tr = np.array([bb[1] < HOLD for bb in B]); te = ~tr
        bt = nnls(X[tr], y[tr]); b0 = np.zeros(4); b0[[0, 1, 3]] = nnls(X[tr][:, [0, 1, 3]], y[tr])
        def ev(bb):
            e = y[te] - X[te] @ bb
            return dict(test_R2=round(float(1 - e @ e / ((y[te] - y[te].mean()) @ (y[te] - y[te].mean()))), 4), RMSE=round(float(np.sqrt(e @ e / te.sum())), 3), pred_pp=round(float((X[te] @ bb).sum()), 1))
        k = "%s_%s" % (olab, meter)
        res[k] = dict(n_blocks=len(y), sum_pp=float(y.sum()), R2=round(float(r2(X, y, b)), 4),
                      coef_pp_per_Mtok={n: round(float(v), 6) for n, v in zip(names, b)},
                      CI95={n: [round(float(x), 6) for x in np.percentile(bs[:, i], [2.5, 97.5])] for i, n in enumerate(names)},
                      cr_zero_in_pct=round(float(100 * (bs[:, 2] == 0).mean()), 1),
                      share_pct={n: round(float(100 * sh[:, i].sum() / sh.sum()), 1) for i, n in enumerate(names)},
                      cr_share_CI95=[round(float(100 * x), 1) for x in np.percentile(crsh, [2.5, 97.5])],
                      heldout=dict(n_train=int(tr.sum()), n_test=int(te.sum()), observed_pp=float(y[te].sum()), with_cr=ev(bt), cr_zero=ev(b0)))
        print(k, json.dumps(res[k]))
json.dump(res, open("/tmp/usage-audit/r2/cache-read-weight/fit4.json", "w"), indent=1)
