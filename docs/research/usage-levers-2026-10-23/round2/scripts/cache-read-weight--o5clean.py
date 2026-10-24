import sys
sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
import numpy as np
from datetime import datetime
from fitlib import *
A, acol = load_events("T")
NOF = lambda S: (S[:, 4] != 2)
feats = [lambda S, c=c: S[:, c] * NOF(S) / 1e6 for c in (7, 8, 9, 10)] + [lambda S: NOF(S) / 1e3, lambda S: (S[:, 4] == 2) * (S[:, 7] + S[:, 8]) / 1e6]
names = ["cc5", "cc1", "cr", "out", "kreq", "fable_cc"]
cum = cum_by_acct(A, acol, feats)
U = load_util()
T = lambda s: datetime.fromisoformat(s + "T00:00:00+00:00").timestamp()
for lab, lo, hi in (("W37-W38 (Opus 5, fewest orphans)", T("2026-09-07"), T("2026-09-21")), ("W34-W36", T("2026-08-17"), T("2026-09-07"))):
    for meter, H in (("w", 3 * 3600), ("s", 3600)):
        P, st = pairs(U, meter)
        B = [b for b in blocks(P, H) if lo <= b[1] < hi]
        X, y = design(B, cum)
        b = nnls(X, y)
        bs = boot(X, y, cluster_ids(B), nnls, R=300)
        c = np.percentile(bs[:, 2], [2.5, 50, 97.5])
        print("%s meter=%s n=%d pp=%d R2=%.3f %s | cr CI [%.5f %.5f %.5f] zero=%.0f%% cr-share=%.1f%%" % (lab, meter, len(y), y.sum(), r2(X, y, b), " ".join("%s=%.4f" % (n, v) for n, v in zip(names, b)), *c, 100 * (bs[:, 2] == 0).mean(), 100 * X[:, 2].sum() * b[2] / (X @ b).sum()))
