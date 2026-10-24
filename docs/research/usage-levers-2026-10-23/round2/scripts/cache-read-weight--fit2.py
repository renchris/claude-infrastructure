#!/usr/bin/env python3
# Structural splits. usage: python3 -I fit2.py <era all|o5|o55> <spec kind|fam|perreq> [meter w|s|f] [H hours] [R]
import sys

sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
import numpy as np
from datetime import datetime
from fitlib import *

era, spec = sys.argv[1], sys.argv[2]
meter = sys.argv[3] if len(sys.argv) > 3 else "w"
H = float(sys.argv[4]) * 3600 if len(sys.argv) > 4 else 3 * 3600
R = int(sys.argv[5]) if len(sys.argv) > 5 else 300
A, acol = load_events("T")
T0 = lambda s: datetime.fromisoformat(s + "T00:00:00+00:00").timestamp()
ERA = {
    "all": (T0("2026-08-17"), 9e18),
    "o5": (T0("2026-08-17"), T0("2026-09-21")),
    "o55": (T0("2026-09-28"), 9e18),
}[era]
M = lambda S: (S[:, 5] == 0).astype(float)
Sb = lambda S: (S[:, 5] == 1).astype(float)
fam = lambda k: lambda S: (S[:, 4] == k).astype(float)
if spec == "kind":
    names, feats = [], []
    for kn, kf in (("main", M), ("sub", Sb)):
        for cn, c in (("cc5", 7), ("cc1", 8), ("cr", 9), ("out", 10)):
            names.append(kn + "_" + cn)
            feats.append(lambda S, c=c, kf=kf: S[:, c] * kf(S) / 1e6)
        names.append(kn + "_kreq")
        feats.append(lambda S, kf=kf: kf(S) / 1e3)
elif spec == "perreq":
    names = ["cc5", "cc1", "cr", "out", "kreq"]
    feats = [lambda S, c=c: S[:, c] / 1e6 for c in (7, 8, 9, 10)] + [
        lambda S: np.ones(len(S)) / 1e3
    ]
elif spec == "fam":
    names, feats = [], []
    groups = (
        ("o5", lambda S: (S[:, 4] == 0) | (S[:, 4] == 5)),
        ("o55", lambda S: S[:, 4] == 1),
        ("fable", lambda S: S[:, 4] == 2),
        ("sh", lambda S: (S[:, 4] == 3) | (S[:, 4] == 4)),
    )
    for gn, gf in groups:
        names += [gn + "_cc", gn + "_cr", gn + "_out", gn + "_kreq"]
        feats += [
            lambda S, gf=gf: (S[:, 7] + S[:, 8]) * gf(S) / 1e6,
            lambda S, gf=gf: S[:, 9] * gf(S) / 1e6,
            lambda S, gf=gf: S[:, 10] * gf(S) / 1e6,
            lambda S, gf=gf: gf(S) / 1e3,
        ]
cum = cum_by_acct(A, acol, feats)
U = load_util()
P, st = pairs(U, meter)
B = [b for b in blocks(P, H) if ERA[0] <= b[1] < ERA[1]]
X, y = design(B, cum)
keep = X.sum(0) > 0
cl = cluster_ids(B)
b = np.zeros(X.shape[1])
b[keep] = nnls(X[:, keep], y)
print(
    "era=%s spec=%s meter=%s H=%.1fh n=%d pp=%d R2=%.4f"
    % (era, spec, meter, H / 3600, len(y), y.sum(), r2(X, y, b))
)
bs = boot(X[:, keep], y, cl, nnls, R=R)
full = np.zeros((len(bs), X.shape[1]))
full[:, keep] = bs
tot = X.sum(0)
pred = (X @ b).sum()
for i, n in enumerate(names):
    lo, md, hi = np.percentile(full[:, i], [2.5, 50, 97.5])
    print(
        "  %-10s total=%10.1f coef=%.5f  CI[%.5f %.5f] zero-in=%3.0f%%  share=%.1f%%"
        % (
            n,
            tot[i],
            b[i],
            lo,
            hi,
            100 * (full[:, i] == 0).mean(),
            100 * tot[i] * b[i] / pred,
        )
    )
