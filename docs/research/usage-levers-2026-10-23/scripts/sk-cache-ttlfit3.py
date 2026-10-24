#!/usr/bin/env python3
# Skeptic test: does the plan's weekly meter charge a 1h cache write more than a 5m write?
# Regress per-(account, 6h bucket) weekly_pct delta on cc5m, cc1h, output (no intercept), with a bootstrap CI.
# Shared (cross-account) subagent records are attributed to the account holding the parent main-session jsonl.
import csv, collections, json, os, time, random
from datetime import datetime
import numpy as np

csv.field_size_limit(10**9)
H = os.path.expanduser("~")
ROOT = {
    "next": H + "/.claude/projects",
    "next2": H + "/.claude-secondary/projects",
    "next3": H + "/.claude-tertiary/projects",
    "next4": H + "/.claude-quaternary/projects",
}
B = 6 * 3600
now = time.time()
cut = now - 7 * 86400


def T(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


recs = {}
holders = collections.defaultdict(set)
for a in ROOT:
    for r in csv.DictReader(open(f"/tmp/usage-audit/sk-cache-{a}.tsv"), delimiter="\t"):
        holders[r["mid"]].add(a)
        if r["mid"] not in recs:
            recs[r["mid"]] = r
pcache = {}
tok = collections.defaultdict(lambda: np.zeros(5))
for mid, r in recs.items():
    acc = r["acct"]
    if len(holders[mid]) > 1:
        proj, sid = r["rel"].split("/")[0], r["rel"].split("/")[1]
        key = (proj, sid)
        if key not in pcache:
            pcache[key] = [
                a for a in ROOT if os.path.exists(f"{ROOT[a]}/{proj}/{sid}.jsonl")
            ]
        h = [a for a in pcache[key] if a in holders[mid]]
        if len(h) == 1:
            acc = h[0]
    t = T(r["ts"])
    b = int((t - cut) // B)
    tok[(acc, b)] += np.array(
        [int(r["cc5m"]), int(r["cc1h"]), int(r["out_max"]), int(r["in"]), int(r["cr"])], dtype=float
    )
# meter: weekly_pct at bucket edges (first and last sample inside the bucket), skip buckets with a reset drop
samp = collections.defaultdict(list)
for line in open(H + "/.claude/logs/account-utilization.jsonl"):
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("stale") or d.get("weekly_pct") is None:
        continue
    t = datetime.fromisoformat(d["ts"]).timestamp()
    if t < cut:
        continue
    samp[(d["acct"], int((t - cut) // B))].append((t, d["weekly_pct"]))
X, y = [], []
for k, v in samp.items():
    v.sort()
    if len(v) < 10 or k not in tok:
        continue
    ws = [w for _, w in v]
    if any(b < a for a, b in zip(ws, ws[1:])):
        continue  # reset inside bucket
    # delta across the bucket ~ tokens in the bucket (sample-edge mismatch is noise)
    X.append(tok[k] / 1e6)
    y.append(ws[-1] - ws[0])
X = np.array(X)
y = np.array(y)
print(
    f"buckets={len(y)} total dpp={y.sum():.0f} tokens(M) cc5m={X[:, 0].sum():.0f} cc1h={X[:, 1].sum():.0f} out={X[:, 2].sum():.1f}"
)
print(
    "corr cc5m~cc1h",
    np.corrcoef(X[:, 0], X[:, 1])[0, 1].round(3),
    "cc5m~out",
    np.corrcoef(X[:, 0], X[:, 2])[0, 1].round(3),
    "cc1h~out",
    np.corrcoef(X[:, 1], X[:, 2])[0, 1].round(3),
)
for cols, lab in [([0, 1, 2], "cc5m,cc1h,out"), ([0, 1, 2, 4], "cc5m,cc1h,out,cr(diag)"), ([0, 1, 2, 3], "cc5m,cc1h,out,in")]:
    A = X[:, cols]
    coef = np.linalg.lstsq(A, y, rcond=None)[0]
    pred = A @ coef
    r2 = 1 - ((y - pred) ** 2).sum() / ((y - y.mean()) ** 2).sum(); r2u = 1 - ((y - pred) ** 2).sum() / (y ** 2).sum(); print("  uncentered r2", round(r2u, 3))
    random.seed(1)
    ratios = []
    for _ in range(2000):
        idx = np.array([random.randrange(len(y)) for _ in range(len(y))])
        c = np.linalg.lstsq(A[idx], y[idx], rcond=None)[0]
        if c[0] > 0:
            ratios.append(c[1] / c[0])
    ratios.sort()
    lo, md, hi = (
        ratios[int(0.025 * len(ratios))],
        ratios[len(ratios) // 2],
        ratios[int(0.975 * len(ratios))],
    )
    print(
        f"OLS [{lab}] coef pp/Mtok={np.round(coef, 4)} r2={r2:.3f} | 1h/5m price ratio median {md:.2f}, 95% bootstrap CI [{lo:.2f}, {hi:.2f}] (list price ratio = 1.60)"
    )
