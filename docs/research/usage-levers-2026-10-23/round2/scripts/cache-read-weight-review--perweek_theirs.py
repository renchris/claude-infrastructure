# Per-week (not LOWO) estimates in the researcher's own per-account pipeline (T attribution), read-only.
import sys
sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
import numpy as np
from datetime import datetime
from fitlib import *
A, acol = load_events("T")
U = load_util()
opus = lambda S: np.isin(S[:, 4], [0, 1])
feats = [lambda S: opus(S) * 1e-3, lambda S: opus(S) * (S[:, 7] + S[:, 8]) / 1e6, lambda S: opus(S) * S[:, 9] / 1e6, lambda S: opus(S) * S[:, 10] / 1e6, lambda S: (~opus(S)) * (S[:, 7] + S[:, 8] + S[:, 10]) / 1e6]
names = ["kreq", "cw", "cr", "out", "nonopus"]
cum = cum_by_acct(A, acol, feats)
P, st = pairs(U, "w")
allB = blocks(P, 3 * 3600)
for w0, w1 in (("2026-09-28", "2026-10-05"), ("2026-10-05", "2026-10-12"), ("2026-10-12", "2026-10-19"), ("2026-10-19", "2026-10-25")):
    t0 = datetime.fromisoformat(w0 + "T00:00:00+00:00").timestamp(); t1 = datetime.fromisoformat(w1 + "T00:00:00+00:00").timestamp()
    B = [b for b in allB if t0 <= b[1] < t1]
    X, y = design(B, cum)
    b = nnls(X, y)
    bs = boot(X, y, cluster_ids(B), nnls, R=300)
    lo, hi = np.percentile(bs[:, 2], [2.5, 97.5])
    print(w0, "n=%d pp=%d R2=%.3f cr=%.5f CI=[%.5f %.5f] zero=%.0f%% | %s" % (len(y), y.sum(), r2(X, y, b), b[2], lo, hi, 100 * (bs[:, 2] == 0).mean(), " ".join("%s=%.4f" % (n, v) for n, v in zip(names, b))))
