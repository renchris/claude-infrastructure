#!/usr/bin/env python3
# Skeptic meter fit: which token classes move the plan meters (weekly_pct, session_pct) on Opus-5.5?
# Inputs: sk_bc_rows_<acct>.tsv (+ .files), ~/.claude/logs/account-utilization.jsonl. Read-only.
import csv, json, os, bisect, itertools, random, collections
from datetime import datetime
import numpy as np

ACCTS = ["next", "next2", "next3", "next4"]
T0 = datetime.fromisoformat("2026-10-09T06:00:00+00:00").timestamp()

# ---- tokens, attributed to the ORIGINATING account (earliest file birthtime for cross-account copies)
paths = {}
for a in ACCTS:
    for line in open("/tmp/usage-audit/sk_bc_rows_%s.tsv.files" % a):
        fi, sz, p = line.rstrip("\n").split("\t", 2)
        paths[(a, int(fi))] = p
birth = {}


def btime(key):
    if key not in birth:
        try:
            birth[key] = os.stat(paths[key]).st_birthtime
        except OSError:
            birth[key] = 9e18
    return birth[key]


cand = collections.defaultdict(list)
for a in ACCTS:
    with open("/tmp/usage-audit/sk_bc_rows_%s.tsv" % a) as f:
        r = csv.reader(f, delimiter="\t")
        next(r)
        for x in r:
            cc5, cc1 = int(x[8]), int(x[9])
            cc = int(x[7])
            cand[x[4]].append(
                (
                    a,
                    int(x[2]),
                    float(x[3]),
                    x[5],
                    int(x[6]),
                    cc5 + max(0, cc - cc5 - cc1),
                    cc1,
                    int(x[10]),
                    int(x[11]),
                )
            )
ev = {a: [] for a in ACCTS}
ncopy = 0
for k, v in cand.items():
    if len(v) > 1:
        accts = set(e[0] for e in v)
        if len(accts) > 1:
            ncopy += 1
            v = sorted(v, key=lambda e: btime((e[0], e[1])))
    e = v[0]
    if e[3] == "<synthetic>":
        continue
    ev[e[0]].append((e[2], e[4], e[5], e[6], e[7], e[8]))  # ts, inp, cc5, cc1h, cr, out
print("cross-account copies re-attributed by birthtime:", ncopy)
cum = {}
for a in ACCTS:
    L = sorted(ev[a])
    ts = [x[0] for x in L]
    C = np.zeros((len(L) + 1, 5))
    if L:
        C[1:] = np.cumsum(np.array([x[1:] for x in L], dtype=float), axis=0)
    cum[a] = (ts, C)


def tok(a, t0, t1):
    ts, C = cum[a]
    return C[bisect.bisect_right(ts, t1)] - C[bisect.bisect_right(ts, t0)]


# ---- meter samples
util = collections.defaultdict(list)
for line in open(os.path.expanduser("~/.claude/logs/account-utilization.jsonl")):
    try:
        r = json.loads(line)
    except Exception:
        continue
    if r.get("auth") != "ok" or r.get("stale"):
        continue
    t = datetime.fromisoformat(r["ts"]).timestamp()
    if t < T0:
        continue

    def rnd(s):
        if not isinstance(s, str):
            return -1
        return round(datetime.fromisoformat(s).timestamp() / 3600.0)

    util[r["acct"]].append(
        (
            t,
            r["weekly_pct"],
            rnd(r["weekly_reset_at"]),
            r["session_pct"],
            rnd(r["session_reset_at"]),
        )
    )


def intervals(meter, H):
    X, y, who = [], [], []
    for a in ACCTS:
        S = sorted(util[a])
        i = 0
        while i < len(S) - 1:
            t0, w0, wr0, s0, sr0 = S[i]
            j = i + 1
            ok = True
            while j < len(S):
                t1, w1, wr1, s1, sr1 = S[j]
                if (
                    (meter == "w" and wr1 != wr0)
                    or (meter == "s" and sr1 != sr0)
                    or t1 - S[j - 1][0] > 1800
                ):
                    ok = False
                    break
                if t1 - t0 >= H * 3600:
                    break
                j += 1
            if not ok or j >= len(S):
                i = j if j > i else i + 1
                continue
            t1 = S[j][0]
            d = (S[j][1] - w0) if meter == "w" else (S[j][3] - s0)
            if d < 0:
                i = j
                continue
            X.append(tok(a, t0, t1) / 1e6)
            y.append(d)
            who.append(a)
            i = j
    return np.array(X), np.array(y, dtype=float), who


NAMES = ["inp", "cc5m", "cc1h", "cr", "out"]


def nnls(X, y):
    best = (np.inf, None)
    k = X.shape[1]
    for m in range(1, k + 1):
        for S in itertools.combinations(range(k), m):
            b, *_ = np.linalg.lstsq(X[:, S], y, rcond=None)
            if (b < 0).any():
                continue
            sse = float(((X[:, S] @ b - y) ** 2).sum())
            if sse < best[0]:
                full = np.zeros(k)
                full[list(S)] = b
                best = (sse, full)
    return best[1], best[0]


def r2(sse, y):
    return 1 - sse / float(((y - y.mean()) ** 2).sum())


def scalar_fit(X, y, w):
    z = X @ np.array(w)
    s = float(z @ y / (z @ z))
    sse = float(((s * z - y) ** 2).sum())
    return s, r2(sse, y)


random.seed(7)
for meter, H in (("w", 3), ("w", 6), ("s", 1), ("s", 2)):
    X, y, who = intervals(meter, H)
    if len(y) < 20:
        print(meter, H, "too few intervals", len(y))
        continue
    b, sse = nnls(X, y)
    print(
        "\nMETER=%s interval>=%sh n=%d sum_pp=%d  corr(out,cr)=%.3f corr(cc1h,cr)=%.3f"
        % (
            "weekly" if meter == "w" else "5h-session",
            H,
            len(y),
            y.sum(),
            np.corrcoef(X[:, 4], X[:, 3])[0, 1],
            np.corrcoef(X[:, 2], X[:, 3])[0, 1],
        )
    )
    print(
        "  NNLS pp/Mtok:",
        " ".join("%s=%.4f" % (n, v) for n, v in zip(NAMES, b)),
        " R2=%.3f" % r2(sse, y),
    )
    # cr pinned at list ratios (relative to fitted out coefficient): compare R2 when cr forced to out/50 and out/100
    for lab, crw in (("cr=0", 0.0), ("cr=0.05in", 0.05), ("cr=0.1in", 0.1)):
        s, rr = scalar_fit(X, y, [1, 1.25, 2.0, crw, 5])
        print(
            "  one-scalar list shape [in 1, cc5m 1.25, cc1h 2, %s, out 5]: R2=%.4f  (%.4f pp per M input-eq)"
            % (lab, rr, s)
        )
    # bootstrap of cr coefficient and its share of predicted pp
    crs, shares = [], []
    idx = np.arange(len(y))
    for _ in range(300):
        ii = np.random.default_rng(random.randint(0, 1 << 30)).choice(idx, len(idx))
        bb, _ = nnls(X[ii], y[ii])
        crs.append(bb[3])
        pred = X[ii] @ bb
        shares.append(float((X[ii][:, 3] * bb[3]).sum() / max(1e-9, pred.sum())))
    crs = np.array(crs)
    shares = np.array(shares)
    print(
        "  bootstrap cr coef: p5=%.5f p50=%.5f p95=%.5f  zero in %.0f%%;  cr share of predicted pp p50=%.1f%% p95=%.1f%%"
        % (
            np.percentile(crs, 5),
            np.percentile(crs, 50),
            np.percentile(crs, 95),
            100.0 * (crs == 0).mean(),
            100 * np.percentile(shares, 50),
            100 * np.percentile(shares, 95),
        )
    )
    # list-implied cr coefficient = out coef / 50 (cr 0.1 in, out 5 in) and /100 (0.05)
    print(
        "  list-implied cr coef from fitted out: out/50=%.5f  out/100=%.5f"
        % (b[4] / 50, b[4] / 100)
    )
