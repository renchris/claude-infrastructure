#!/usr/bin/env python3
"""Rank every zone and every IOKit class by how well its per-interval DELTA tracks data.kalloc.1024's.

Input: the rows probe.py --sample-all writes (default ~/.claude/logs/kalloc-ratchet-cogrowth.jsonl).
A kernel object that is allocated alongside each leaked 1 KiB buffer (a mach message, a pipe, a
vnode, an IOKit user client) grows in step with it, so its delta series correlates and its
net growth ratio (d_other / d_kalloc) is stable. Also reports pid-counter (fork rate) and nprocs.

Usage: cogrowth.py [PATH] [--top 25] [--min-growth 50]
"""

import json
import math
import os
import sys

ZONE = "data.kalloc.1024"


def pearson(xs, ys):
    n = len(xs)
    if n < 5:
        return None
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    if sxx == 0 or syy == 0:
        return None
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / math.sqrt(sxx * syy)


def main():
    args = [a for a in sys.argv[1:]]
    top = int(args[args.index("--top") + 1]) if "--top" in args else 25
    ming = int(args[args.index("--min-growth") + 1]) if "--min-growth" in args else 50
    paths = [a for a in args if not a.startswith("--") and not a.isdigit()]
    path = (
        paths[0]
        if paths
        else os.path.expanduser("~/.claude/logs/kalloc-ratchet-cogrowth.jsonl")
    )
    rows = []
    with open(path) as fh:
        for line in fh:
            r = json.loads(line)
            if "zones" in r and ZONE in r["zones"]:
                rows.append(r)
    if len(rows) < 6:
        sys.exit(f"only {len(rows)} usable rows in {path}; need >= 6")
    dk = [b["zones"][ZONE] - a["zones"][ZONE] for a, b in zip(rows, rows[1:])]
    total_k = rows[-1]["zones"][ZONE] - rows[0]["zones"][ZONE]
    span_h = (rows[-1]["t"] - rows[0]["t"]) / 3600
    print(
        f"rows={len(rows)} span={span_h:.2f} h  {ZONE}: {rows[0]['zones'][ZONE]} -> "
        f"{rows[-1]['zones'][ZONE]} (+{total_k} elements = {total_k / 1024:.1f} MiB, "
        f"{total_k / 1024 / 1024 / span_h * 24 if span_h else 0:.2f} GiB/day)"
    )

    def forks(a, b):
        d = b["pid"] - a["pid"]
        return d if d >= 0 else d + 99999

    for label, series in (
        ("forks(pid delta)", [forks(a, b) for a, b in zip(rows, rows[1:])]),
        ("nprocs delta", [b["nprocs"] - a["nprocs"] for a, b in zip(rows, rows[1:])]),
        ("load1", [b["load1"] for b in rows[1:]]),
    ):
        r = pearson(series, dk)
        print(
            f"  r(d_kalloc, {label}) = {None if r is None else round(r, 3)}   total={sum(series):.0f}"
        )

    cands = []
    for kind in ("zones", "io"):
        keys = set(rows[0][kind]) & set(rows[-1][kind])
        for k in keys:
            if kind == "zones" and k == ZONE:
                continue
            try:
                d = [b[kind][k] - a[kind][k] for a, b in zip(rows, rows[1:])]
            except KeyError:
                continue
            growth = rows[-1][kind][k] - rows[0][kind][k]
            if abs(growth) < ming and kind == "zones":
                continue
            if abs(growth) < 3 and kind == "io":
                continue
            r = pearson(d, dk)
            if r is None:
                continue
            cands.append((r, kind, k, growth, growth / total_k if total_k else 0))
    cands.sort(reverse=True)
    print(f"\nTop {top} co-growers by r(delta, d_kalloc):")
    print(f"  {'r':>6}  {'kind':5}  {'net growth':>10}  {'per kalloc elt':>14}  name")
    for r, kind, k, g, ratio in cands[:top]:
        print(f"  {r:6.3f}  {kind:5}  {g:10d}  {ratio:14.4f}  {k}")
    print("\nNet-growth leaders (any r):")
    for r, kind, k, g, ratio in sorted(cands, key=lambda c: -abs(c[3]))[:15]:
        print(f"  {r:6.3f}  {kind:5}  {g:10d}  {ratio:14.4f}  {k}")


if __name__ == "__main__":
    main()
