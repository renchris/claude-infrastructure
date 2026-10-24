# Mechanism check: split each class by the request's prompt size (inp+cc+cr) <=200k vs >200k.
import sys
sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
import numpy as np
from datetime import datetime
from fitlib import *
A, acol = load_events("T")
U = load_util()
E0 = datetime.fromisoformat("2026-09-28T00:00:00+00:00").timestamp()
ctx = lambda S: S[:, 6] + S[:, 7] + S[:, 8] + S[:, 9]
lo = lambda S: (ctx(S) <= 200000).astype(float)
hi = lambda S: (ctx(S) > 200000).astype(float)
names, feats = [], []
for gn, g in (("le200k", lo), ("gt200k", hi)):
    names += [gn + "_cw", gn + "_cr", gn + "_out", gn + "_kreq"]
    feats += [lambda S, g=g: (S[:, 7] + S[:, 8]) * g(S) / 1e6, lambda S, g=g: S[:, 9] * g(S) / 1e6, lambda S, g=g: S[:, 10] * g(S) / 1e6, lambda S, g=g: g(S) / 1e3]
cum = cum_by_acct(A, acol, feats)
for meter, H in (("w", 3 * 3600), ("s", 3600)):
    P, st = pairs(U, meter)
    B = [b for b in blocks(P, H) if b[1] >= E0]
    X, y = design(B, cum)
    b = nnls(X, y)
    bs = boot(X, y, cluster_ids(B), nnls, R=300)
    print("meter=%s n=%d R2=%.4f" % (meter, len(y), r2(X, y, b)))
    for i, n in enumerate(names):
        c = np.percentile(bs[:, i], [2.5, 97.5])
        print("  %-12s total=%9.1f coef=%.5f CI[%.5f %.5f] zero=%3.0f%% share=%.1f%%" % (n, X[:, i].sum(), b[i], c[0], c[1], 100 * (bs[:, i] == 0).mean(), 100 * X[:, i].sum() * b[i] / (X @ b).sum()))
