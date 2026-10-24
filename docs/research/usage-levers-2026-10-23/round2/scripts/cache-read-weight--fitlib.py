#!/usr/bin/env python3
# Shared helpers for the r2 cache-read meter refit. Read-only.
import json, bisect, collections
from datetime import datetime, timezone
import numpy as np

D = "/tmp/usage-audit/r2/cache-read-weight/"
ACCTS = ["next", "next2", "next3", "next4"]
UTIL = "/Users/chrisren/.claude/logs/account-utilization.jsonl"
# event array A columns (build.py): 0 ts, 1 T, 2 B, 3 P, 4 fam, 5 kind(0 main,1 sub), 6 inp, 7 cc5, 8 cc1,
# 9 cr, 10 outF, 11 outFirst, 12 outMax, 13 web
FAM = {
    0: "opus5",
    1: "opus55",
    2: "fable",
    3: "sonnet",
    4: "haiku",
    5: "opus4",
    6: "other",
}


def nnls(A, b, maxiter=None):
    """Lawson-Hanson active-set NNLS: min ||Ax-b|| s.t. x>=0."""
    m, n = A.shape
    P = np.zeros(n, bool)
    x = np.zeros(n)
    w = A.T @ (b - A @ x)
    it = 0
    maxiter = maxiter or 3 * n + 10
    tol = 1e-10 * max(1.0, np.abs(A).max()) * max(m, n)
    while (~P).any() and (w[~P] > tol).any() and it < maxiter:
        it += 1
        j = np.where(~P)[0][np.argmax(w[~P])]
        P[j] = True
        while True:
            z = np.zeros(n)
            z[P] = np.linalg.lstsq(A[:, P], b, rcond=None)[0]
            if (z[P] > 0).all():
                break
            q = P & (z <= 0)
            alpha = np.min(x[q] / (x[q] - z[q]))
            x = x + alpha * (z - x)
            P = P & (x > 1e-14)
            x[~P] = 0
        x = z
        w = A.T @ (b - A @ x)
    return x


def load_events(rule="T", naive=False):
    z = np.load(D + "events.npz")
    if naive:
        N = z[
            "N"
        ]  # ts, acct, fam, kind, inp, cc5, cc1, cr, outF, outFirst, outMax, web
        A = np.zeros((len(N), 14))
        A[:, 0] = N[:, 0]
        A[:, 1] = N[:, 1]
        A[:, 4] = N[:, 2]
        A[:, 5] = N[:, 3]
        A[:, 6:14] = N[:, 4:12]
        return A, 1
    A = z["A"]
    return A, {"T": 1, "B": 2, "P": 3}[rule]


def cum_by_acct(A, acol, feats):
    """feats: list of functions row-block -> column vector. Returns {acct: (ts, C)} with C cumulative."""
    out = {}
    for i, a in enumerate(ACCTS):
        S = A[A[:, acol] == i]
        S = S[np.argsort(S[:, 0])]
        F = (
            np.column_stack([f(S) for f in feats])
            if len(S)
            else np.zeros((0, len(feats)))
        )
        C = np.zeros((len(S) + 1, len(feats)))
        if len(S):
            C[1:] = np.cumsum(F, axis=0)
        out[a] = (S[:, 0].copy(), C)
    return out


def tok(cum, a, t0, t1):
    ts, C = cum[a]
    return C[bisect.bisect_right(ts, t1)] - C[bisect.bisect_right(ts, t0)]


def load_util():
    U = collections.defaultdict(list)
    for line in open(UTIL):
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("auth") != "ok" or r.get("stale") or r.get("credits_on"):
            continue
        if r.get("weekly_pct") is None or r.get("session_pct") is None:
            continue
        t = datetime.fromisoformat(r["ts"]).timestamp()

        def rnd(s):
            if not isinstance(s, str):
                return -1
            return round(datetime.fromisoformat(s).timestamp() / 3600.0)

        U[r["acct"]].append(
            (
                t,
                r["weekly_pct"],
                rnd(r["weekly_reset_at"]),
                r["session_pct"],
                rnd(r["session_reset_at"]),
                r.get("fable_pct") if r.get("fable_pct") is not None else -1,
            )
        )
    for a in U:
        U[a].sort()
    return U


def pairs(U, meter, maxgap=1800, sat=99):
    """Consecutive reading pairs with no reset of THIS meter, no gap > maxgap, no decrease, unsaturated."""
    vi, ri = {"w": (1, 2), "s": (3, 4), "f": (5, 2)}[meter]
    P = collections.defaultdict(list)
    stat = collections.Counter()
    for a, S in U.items():
        for x0, x1 in zip(S, S[1:]):
            if x1[0] - x0[0] > maxgap:
                stat["gap"] += 1
                continue
            if x1[ri] != x0[ri]:
                stat["reset"] += 1
                continue
            if x0[vi] < 0 or x1[vi] < 0:
                stat["missing"] += 1
                continue
            d = x1[vi] - x0[vi]
            if d < 0:
                stat["decrease"] += 1
                continue
            if x0[vi] >= sat or x1[vi] >= sat:
                stat["saturated"] += 1
                continue
            P[a].append((x0[0], x1[0], d))
            stat["ok"] += 1
    return P, stat


def blocks(P, H):
    """Merge contiguous valid pairs into blocks of >= H seconds."""
    B = []
    for a, L in P.items():
        cur = None
        for t0, t1, d in L:
            if cur is not None and abs(t0 - cur[2]) < 1e-6:
                cur[2] = t1
                cur[3] += d
            else:
                cur = [a, t0, t1, d]
            if cur[2] - cur[1] >= H:
                B.append(tuple(cur))
                cur = None
    return B


def design(B, cum):
    X = np.array([tok(cum, a, t0, t1) for a, t0, t1, d in B])
    y = np.array([d for a, t0, t1, d in B], float)
    return X, y


def r2(X, y, b):
    e = y - X @ b
    return 1 - (e @ e) / ((y - y.mean()) @ (y - y.mean()))


def cluster_ids(B):
    return np.array([hash((a, int(t0 // 86400))) for a, t0, t1, d in B])


def boot(X, y, cl, fitfun, R=1000, seed=7):
    rng = np.random.default_rng(seed)
    u = np.unique(cl)
    idx = {c: np.where(cl == c)[0] for c in u}
    res = []
    for _ in range(R):
        pick = rng.choice(u, len(u))
        ii = np.concatenate([idx[c] for c in pick])
        res.append(fitfun(X[ii], y[ii]))
    return np.array(res)


def day(t):
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%d")
