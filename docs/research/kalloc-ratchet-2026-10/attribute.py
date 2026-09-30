#!/usr/bin/env python3
"""Attribute data.kalloc.1024 growth to process classes from sandbox_churn.py rows.

For every process name (sandboxed names carry an `sb:` prefix) with enough births: the Pearson r
between its per-window birth count and the window's Δdata.kalloc.1024, the least-squares slope
(elements per birth) and that name's implied share of total growth. Also a joint least-squares fit
over the top-K names (numpy), so collinear classes do not each claim the same growth.

Usage: attribute.py [PATH] [--min-births 50] [--top 15]
"""

import json
import math
import os
import sys


def pearson(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    if not sxx or not syy:
        return None, None
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    return sxy / math.sqrt(sxx * syy), sxy / sxx


def main():
    args = sys.argv[1:]
    minb = int(args[args.index("--min-births") + 1]) if "--min-births" in args else 50
    top = int(args[args.index("--top") + 1]) if "--top" in args else 15
    paths = [x for x in args if not x.startswith("--") and not x.isdigit()]
    path = (
        paths[0]
        if paths
        else os.path.expanduser("~/.claude/logs/kalloc-sandbox-churn-2.jsonl")
    )
    rows = [json.loads(line) for line in open(path) if '"births_by_comm"' in line]
    if len(rows) < 10:
        sys.exit(f"{len(rows)} windows with births_by_comm in {path}; need >= 10")
    dk = [r["d_kalloc1024"] for r in rows]
    names = {}
    for r in rows:
        for k, v in r["births_by_comm"].items():
            names[k] = names.get(k, 0) + v
    total = sum(dk)
    print(
        f"windows={len(rows)}  Δdata.kalloc.1024 total={total}  ({total / 1024:.1f} MiB)"
    )
    res = []
    for k, n in names.items():
        if n < minb:
            continue
        xs = [r["births_by_comm"].get(k, 0) for r in rows]
        r_, b = pearson(xs, dk)
        if r_ is None:
            continue
        res.append((r_, b, n, k))
    res.sort(reverse=True)
    print(f"\n{'r':>6} {'elts/birth':>10} {'births':>7} {'share':>7}  name")
    for r_, b, n, k in res[:top]:
        print(
            f"{r_:6.3f} {b:10.2f} {n:7d} {b * n / total * 100 if total else 0:6.1f}%  {k}"
        )
    try:
        import numpy as np
    except ImportError:
        print("\n(numpy absent: joint fit skipped)")
        return
    keys = [k for _, _, _, k in res[:top]]
    X = np.array(
        [[r["births_by_comm"].get(k, 0) for k in keys] + [1.0] for r in rows],
        dtype=float,
    )
    y = np.array(dk, dtype=float)
    coef, *_ = np.linalg.lstsq(X, y, rcond=None)
    pred = X @ coef
    r2 = 1 - ((y - pred) ** 2).sum() / ((y - y.mean()) ** 2).sum()
    print(
        f"\njoint least squares over top {len(keys)} names: R^2 = {r2:.3f}; intercept {coef[-1]:.1f} elts/window"
    )
    for k, c in sorted(zip(keys, coef[:-1]), key=lambda t: -t[1] * names[t[0]]):
        print(
            f"  {c:9.2f} elts/birth  x {names[k]:6d} births = {c * names[k]:9.0f}  {k}"
        )


if __name__ == "__main__":
    main()
