# Does the Opus 5 era (W37-38, researcher's pipeline, T attribution) actually REJECT cr~0.005, or is it just collinear?
import sys
sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
import numpy as np
from datetime import datetime
from fitlib import *
A, acol = load_events("T")
U = load_util()
opus = lambda S: np.isin(S[:, 4], [0, 1])
fab = lambda S: S[:, 4] == 2
feats = [lambda S: opus(S) * 1e-3, lambda S: opus(S) * (S[:, 7] + S[:, 8]) / 1e6, lambda S: opus(S) * S[:, 9] / 1e6, lambda S: opus(S) * S[:, 10] / 1e6, lambda S: fab(S) * (S[:, 7] + S[:, 8]) / 1e6, lambda S: (~opus(S) & ~fab(S)) * (S[:, 7] + S[:, 8] + S[:, 10]) / 1e6]
names = ["kreq", "cw", "cr", "out", "fable_cw", "other"]
cum = cum_by_acct(A, acol, feats)
for meter, H in (("w", 3 * 3600), ("s", 3600)):
    P, st = pairs(U, meter)
    t0 = datetime.fromisoformat("2026-09-07T00:00:00+00:00").timestamp(); t1 = datetime.fromisoformat("2026-09-21T00:00:00+00:00").timestamp()
    B = [b for b in blocks(P, H) if t0 <= b[1] < t1]
    X, y = design(B, cum)
    print("meter", meter, "n", len(y), "pp", y.sum(), "corr(kreq,cr)=%.3f corr(cw,cr)=%.3f" % (np.corrcoef(X[:, 0], X[:, 2])[0, 1], np.corrcoef(X[:, 1], X[:, 2])[0, 1]), "mean cr/req (k tok)=%.0f" % (X[:, 2].sum() / X[:, 0].sum()))
    for fix in (None, 0.0, 0.0025, 0.005, 0.0075):
        if fix is None:
            b = nnls(X, y)
        else:
            cols = [0, 1, 3, 4, 5]
            b = np.zeros(6); b[2] = fix
            b[cols] = nnls(X[:, cols], y - fix * X[:, 2])
        e = y - X @ b
        print("   cr=%s  RMSE=%.3f R2=%.4f  %s" % ("free" if fix is None else fix, np.sqrt(e @ e / len(y)), r2(X, y, b), " ".join("%s=%.4f" % (n, v) for n, v in zip(names, b))))
    # without kreq
    cols = [1, 2, 3, 4, 5]
    b = np.zeros(6); b[cols] = nnls(X[:, cols], y)
    e = y - X @ b
    print("   no-kreq RMSE=%.3f R2=%.4f %s" % (np.sqrt(e @ e / len(y)), r2(X, y, b), " ".join("%s=%.4f" % (n, v) for n, v in zip(names, b))))
