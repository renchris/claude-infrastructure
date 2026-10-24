#!/usr/bin/env python3
# Data-completeness check: per ISO week, blocks where the weekly meter moved but the account's attributed
# transcripts show (almost) no tokens, and the ratio of meter pp to list-weighted tokens.
import sys

sys.path.insert(0, "/tmp/usage-audit/r2/cache-read-weight")
import collections
import numpy as np
from datetime import datetime, timezone
from fitlib import *

A, acol = load_events("T")
feats = [lambda S, c=c: S[:, c] / 1e6 for c in (6, 7, 8, 9, 10)] + [
    lambda S: np.ones(len(S))
]
cum = cum_by_acct(A, acol, feats)
U = load_util()
for meter, H in (("w", 3 * 3600), ("s", 3600)):
    P, st = pairs(U, meter)
    B = blocks(P, H)
    X, y = design(B, cum)
    wk = collections.defaultdict(lambda: [0, 0, 0, 0.0, 0.0, 0.0, 0])
    for (a, t0, t1, d), x, yy in zip(B, X, y):
        w = datetime.fromtimestamp(t0, timezone.utc).strftime("%G-W%V")
        r = wk[w]
        r[0] += 1
        r[1] += yy
        if yy >= 2 and x[5] < 20:
            r[2] += 1  # meter moved >=2pp but <20 requests
            r[6] += yy
        r[3] += x[1] * 1.25 + x[2] * 2 + x[4] * 5  # list-eq excluding cr
        r[4] += x[3]
        r[5] += x[5]
    print(
        "meter=%s H=%.0fh: week n pp moved>=2pp&<20req(n,pp) pp_per_Mlisteq(no cr) cr(B) kreq"
        % (meter, H / 3600)
    )
    for w in sorted(wk):
        r = wk[w]
        print(
            "  %s n=%4d pp=%5d  orphan=%3d (%4d pp)  pp/Mleq=%.3f  cr=%6.1fB kreq=%6.1f  pp/kreq=%.3f"
            % (
                w,
                r[0],
                r[1],
                r[2],
                r[6],
                r[1] / max(1e-9, r[3]),
                r[4] / 1e3,
                r[5] / 1e3,
                r[1] / max(1e-9, r[5] / 1e3),
            )
        )
