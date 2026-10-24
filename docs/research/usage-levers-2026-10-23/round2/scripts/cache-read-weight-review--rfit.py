#!/usr/bin/env python3
# Reviewer's ATTRIBUTION-FREE pooled fit (read-only).
# Sum of weekly_pct deltas over all 4 accounts (all Max 20x, same quota) vs globally de-duplicated
# tokens over all 4 config dirs. No account attribution is needed, so the T/B/P rule question drops out.
# usage: python3 -I rfit.py <era_start_iso> <era_end_iso> <holdout_start_iso|-> <H_hours> [spec]
import sys, json, collections, bisect
from datetime import datetime, timezone
import numpy as np

D = "/tmp/usage-audit/r2/cache-read-weight-review/"
AC = ["next", "next2", "next3", "next4"]
E0 = datetime.fromisoformat(sys.argv[1]).timestamp()
E1 = datetime.fromisoformat(sys.argv[2]).timestamp()
HO = None if sys.argv[3] == "-" else datetime.fromisoformat(sys.argv[3]).timestamp()
H = float(sys.argv[4]) * 3600
SPEC = sys.argv[5] if len(sys.argv) > 5 else "base"
METER = sys.argv[6] if len(sys.argv) > 6 else "w"


def nnls(A, b):
    m, n = A.shape
    P = np.zeros(n, bool)
    x = np.zeros(n)
    w = A.T @ (b - A @ x)
    tol = 1e-10 * max(1.0, np.abs(A).max()) * max(m, n)
    it = 0
    while (~P).any() and (w[~P] > tol).any() and it < 3 * n + 10:
        it += 1
        j = np.where(~P)[0][np.argmax(w[~P])]
        P[j] = True
        while True:
            z = np.zeros(n)
            z[P] = np.linalg.lstsq(A[:, P], b, rcond=None)[0]
            if (z[P] > 0).all():
                break
            q = P & (z <= 0)
            al = np.min(x[q] / (x[q] - z[q]))
            x = x + al * (z - x)
            P = P & (x > 1e-14)
            x[~P] = 0
        x = z
        w = A.T @ (b - A @ x)
    return x


# ---- tokens: global de-dup over the 4 accounts
G = {}
for a in AC:
    f = open(D + "r_%s.tsv" % a)
    hdr = f.readline().rstrip("\n").split("\t")
    for line in f:
        v = line.rstrip("\n").split("\t")
        k = v[0]
        t = float(v[1])
        row = (
            [t, v[2], v[3]]
            + [int(x) for x in v[4:12]]
            + [v[12], int(v[13]), int(v[14])]
        )
        # row: 0 ts,1 model,2 kind,3 inp,4 cc5,5 cc1,6 cc,7 cr,8 out,9 ntool,10 clf,11 speed,12 xin,13 xout
        if k in G:
            g = G[k]
            g[0] = min(g[0], t)
            g[8] = max(g[8], row[8])
            g[9] = max(g[9], row[9])
            g[10] = max(g[10], row[10])
            g.append(a)
        else:
            G[k] = row + [a]
print("unique responses", len(G), file=sys.stderr)


def fam(m):
    if m.startswith("claude-opus-5-5"):
        return "o55"
    if m.startswith("claude-opus-5"):
        return "o5"
    if m.startswith("claude-fable"):
        return "fable"
    return "other"


rows = []
for k, g in G.items():
    if not (E0 - 86400 <= g[0] <= E1 + 86400):
        continue
    rows.append(g)
rows.sort(key=lambda g: g[0])
import os

# placebo: shift token timestamps by RFIT_SHIFT_H hours against the meter (0 = real alignment)
ts = np.array([g[0] for g in rows]) + 3600 * float(os.environ.get("RFIT_SHIFT_H", "0"))


def col(fn):
    return np.array([fn(g) for g in rows], float)


cw = lambda g: g[4] + g[5] + max(0, g[6] - g[4] - g[5])
F = collections.OrderedDict()
isf = lambda g, f: fam(g[1]) == f
if SPEC in ("base", "nocr", "tool", "kind", "ctx", "sq"):
    F["kreq"] = col(lambda g: 1e-3 if fam(g[1]) in ("o55", "o5") else 0)
if SPEC == "kind":
    F["kreq_sub"] = col(
        lambda g: 1e-3 if fam(g[1]) in ("o55", "o5") and g[2] == "s" else 0
    )
F["cw_opus"] = col(lambda g: cw(g) / 1e6 if fam(g[1]) in ("o55", "o5") else 0)
if SPEC != "nocr":
    if SPEC == "kind":
        F["cr_main"] = col(
            lambda g: g[7] / 1e6 if fam(g[1]) in ("o55", "o5") and g[2] == "m" else 0
        )
        F["cr_sub"] = col(
            lambda g: g[7] / 1e6 if fam(g[1]) in ("o55", "o5") and g[2] == "s" else 0
        )
    elif SPEC == "ctx":
        F["cr_lt200k"] = col(
            lambda g: (
                g[7] / 1e6
                if fam(g[1]) in ("o55", "o5") and g[7] + g[6] + g[3] <= 200000
                else 0
            )
        )
        F["cr_gt200k"] = col(
            lambda g: (
                g[7] / 1e6
                if fam(g[1]) in ("o55", "o5") and g[7] + g[6] + g[3] > 200000
                else 0
            )
        )
    else:
        F["cr_opus"] = col(lambda g: g[7] / 1e6 if fam(g[1]) in ("o55", "o5") else 0)
if SPEC == "sq":
    # context^2 term: a cost superlinear in context (e.g. attention) would load here, not on linear cr
    F["ctx2"] = col(
        lambda g: ((g[7] + g[6] + g[3]) / 1e6) ** 2 if fam(g[1]) in ("o55", "o5") else 0
    )
F["out_opus"] = col(lambda g: g[8] / 1e6 if fam(g[1]) in ("o55", "o5") else 0)
if SPEC == "tool":
    F["ktool"] = col(lambda g: g[9] * 1e-3 if fam(g[1]) in ("o55", "o5") else 0)
F["fable_all"] = col(
    lambda g: (cw(g) + g[8] + g[7] * 0.1) / 1e6 if fam(g[1]) == "fable" else 0
)
F["other_all"] = col(
    lambda g: (cw(g) + g[8] + g[7] * 0.1) / 1e6 if fam(g[1]) == "other" else 0
)
names = list(F)
M = np.column_stack([F[n] for n in names])
C = np.vstack([np.zeros(len(names)), np.cumsum(M, 0)])


def tok(t0, t1):
    return C[bisect.bisect_right(ts, t1)] - C[bisect.bisect_right(ts, t0)]


# ---- meter: synchronized polls, all 4 accounts valid, no reset of any account, no decrease, unsaturated
VI, RI = {
    "w": ("weekly_pct", "weekly_reset_at"),
    "s": ("session_pct", "session_reset_at"),
}[METER]
polls = collections.defaultdict(dict)
for line in open("/Users/chrisren/.claude/logs/account-utilization.jsonl"):
    try:
        r = json.loads(line)
    except Exception:
        continue
    polls[r["ts"]][r["acct"]] = r
P = sorted(polls)
st = collections.Counter()


def rh(s):
    return (
        round(datetime.fromisoformat(s).timestamp() / 3600)
        if isinstance(s, str)
        else None
    )


def good(d):
    return all(
        a in d
        and d[a].get("auth") == "ok"
        and not d[a].get("stale")
        and not d[a].get("credits_on")
        and d[a].get(VI) is not None
        for a in AC
    )


pairs = []
for p0, p1 in zip(P, P[1:]):
    t0 = datetime.fromisoformat(p0).timestamp()
    t1 = datetime.fromisoformat(p1).timestamp()
    if t1 < E0 or t0 > E1:
        continue
    d0, d1 = polls[p0], polls[p1]
    if not (good(d0) and good(d1)):
        st["bad"] += 1
        continue
    if t1 - t0 > 1800:
        st["gap"] += 1
        continue
    if any(rh(d0[a][RI]) != rh(d1[a][RI]) for a in AC):
        st["reset"] += 1
        continue
    dd = [d1[a][VI] - d0[a][VI] for a in AC]
    if min(dd) < 0:
        st["decrease"] += 1
        continue
    if any(d0[a][VI] >= 99 or d1[a][VI] >= 99 for a in AC):
        st["sat"] += 1
        continue
    st["ok"] += 1
    pairs.append((t0, t1, sum(dd)))
B = []
cur = None
for t0, t1, d in pairs:
    if cur is not None and abs(t0 - cur[1]) < 1e-6:
        cur[1] = t1
        cur[2] += d
    else:
        cur = [t0, t1, d]
    if cur[1] - cur[0] >= H:
        B.append(tuple(cur))
        cur = None
X = np.array([tok(t0, t1) for t0, t1, d in B])
y = np.array([d for t0, t1, d in B], float)
if os.environ.get("RFIT_ICPT") == "1":
    # background charge per wall-clock hour (e.g. claude.ai chat or any usage with no local transcript)
    X = np.column_stack([X, np.array([(t1 - t0) / 3600.0 for t0, t1, d in B])])
    names = names + ["per_hour"]
day = np.array([int(t0 // 86400) for t0, t1, d in B])
b = nnls(X, y)
e = y - X @ b
R2 = 1 - e @ e / ((y - y.mean()) @ (y - y.mean()))
rng = np.random.default_rng(11)
u = np.unique(day)
idx = {c: np.where(day == c)[0] for c in u}
BS = []
for _ in range(500):
    ii = np.concatenate([idx[c] for c in rng.choice(u, len(u))])
    BS.append(nnls(X[ii], y[ii]))
BS = np.array(BS)
sh = (X * b).sum(0) / (X @ b).sum()
out = dict(
    era=sys.argv[1:3],
    spec=SPEC,
    meter=METER,
    H_h=H / 3600,
    pair_stats=dict(st),
    n_blocks=len(y),
    n_days=len(u),
    sum_pp=float(y.sum()),
    R2=round(float(R2), 4),
    coef={},
)
for i, n in enumerate(names):
    lo, hi = np.percentile(BS[:, i], [2.5, 97.5])
    out["coef"][n] = dict(
        b=round(float(b[i]), 6),
        CI95=[round(float(lo), 6), round(float(hi), 6)],
        zero_pct=round(float(100 * (BS[:, i] == 0).mean()), 1),
        share_pct=round(float(100 * sh[i]), 1),
        total=round(float(X[:, i].sum()), 1),
    )
# collinearity among the opus columns
oc = [i for i, n in enumerate(names) if not n.startswith(("fable", "other"))]
Z = X[:, oc]
out["corr"] = {
    names[i] + "~" + names[j]: round(float(np.corrcoef(Z[:, a], Z[:, c])[0, 1]), 3)
    for a, i in enumerate(oc)
    for c, j in enumerate(oc)
    if a < c
}
if HO:
    tr = np.array([t0 < HO for t0, t1, d in B])
    te = ~tr

    def ev(cols):
        bb = np.zeros(len(names))
        bb[cols] = nnls(X[tr][:, cols], y[tr])
        ee = y[te] - X[te] @ bb
        return dict(
            RMSE=round(float(np.sqrt(ee @ ee / te.sum())), 3),
            R2=round(
                float(1 - ee @ ee / ((y[te] - y[te].mean()) @ (y[te] - y[te].mean()))),
                4,
            ),
            pred=round(float((X[te] @ bb).sum()), 1),
            coef=[round(float(x), 5) for x in bb],
        )

    allc = list(range(len(names)))
    nocr = [i for i, n in enumerate(names) if not n.startswith("cr")]
    out["heldout"] = dict(
        n_train=int(tr.sum()),
        n_test=int(te.sum()),
        obs=float(y[te].sum()),
        with_cr=ev(allc),
        cr0=ev(nocr),
    )
print(json.dumps(out))
