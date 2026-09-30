#!/usr/bin/env python3
"""Attribute data.kalloc.1024 growth to SANDBOXED-process churn, by process name, without root.

carry_ab.py showed a process holding a unique sandbox credential carries ~1 `cred` + ~1
data.kalloc.1024 element while it lives, and cogrowth.py found the zone's deltas moving ~1:1 with
`cred` fleet-wide. So the ratchet should track the birth/death rate of sandboxed processes, and
the leak (the part not returned at exit) should be attributable to the classes that churn.

Every POLL seconds: list pids (ps), sandbox_check() each NEW pid once (libsystem_sandbox; no root
for same-user or system pids), and record births/deaths of sandboxed pids by comm. Every WINDOW
seconds: read the zones and emit one row. At the end: per-window Pearson r of Δkalloc against
sandboxed births and deaths, and the per-comm birth/death totals.

Usage: sandbox_churn.py [--secs 900] [--poll 1] [--window 20] [--out PATH]
"""

import argparse
import collections
import ctypes
import json
import math
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe import all_zones  # noqa: E402

_lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
_sbc = _lib.sandbox_check
_sbc.restype = ctypes.c_int
_sbc.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int]


def procs():
    out = subprocess.run(
        ["/bin/ps", "-axo", "pid=,comm="], capture_output=True, text=True
    ).stdout
    d = {}
    for line in out.splitlines():
        p, _, c = line.strip().partition(" ")
        if p.isdigit():
            d[int(p)] = c.rsplit("/", 1)[-1] or c
    return d


def pearson(xs, ys):
    n = len(xs)
    if n < 5:
        return None
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    if not sxx or not syy:
        return None
    return round(
        sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / math.sqrt(sxx * syy), 3
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--secs", type=int, default=900)
    ap.add_argument("--poll", type=float, default=1.0)
    ap.add_argument("--window", type=int, default=20)
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    out = open(a.out, "a", buffering=1) if a.out else sys.stdout
    sandboxed = {}  # pid -> comm, for live sandboxed pids
    seen = set(procs())  # pids alive at start are never births
    for p, c in procs().items():
        if _sbc(p, None, 0) == 1:
            sandboxed[p] = c
    births, deaths = collections.Counter(), collections.Counter()
    wb = wd = wall_births = 0
    wcomm = collections.Counter()      # this window's births by comm, key 'sb:<comm>' or '<comm>'
    z0 = all_zones()
    end, wend = time.time() + a.secs, time.time() + a.window
    rows = []
    while time.time() < end:
        cur = procs()
        for p, c in cur.items():
            if p not in seen:
                seen.add(p)
                wall_births += 1
                sb = _sbc(p, None, 0) == 1
                wcomm[("sb:" if sb else "") + c] += 1
                if sb:
                    sandboxed[p] = c
                    births[c] += 1
                    wb += 1
        for p in [p for p in sandboxed if p not in cur]:
            deaths[sandboxed.pop(p)] += 1
            wd += 1
        if time.time() >= wend:
            z1 = all_zones()
            row = {
                "t": round(time.time(), 1),
                "sb_births": wb,
                "sb_deaths": wd,
                "all_births": wall_births,
                "sb_live": len(sandboxed),
                "births_by_comm": dict(wcomm.most_common(40)),
                "d_kalloc1024": z1["data.kalloc.1024"] - z0["data.kalloc.1024"],
                "d_cred": z1["cred"] - z0["cred"],
            }
            rows.append(row)
            out.write(json.dumps(row) + "\n")
            z0, wb, wd, wall_births, wend = z1, 0, 0, 0, time.time() + a.window
            wcomm = collections.Counter()
        time.sleep(a.poll)
    dk = [r["d_kalloc1024"] for r in rows]
    summary = {
        "windows": len(rows),
        "sum_d_kalloc1024": sum(dk),
        "sum_sb_births": sum(r["sb_births"] for r in rows),
        "sum_sb_deaths": sum(r["sb_deaths"] for r in rows),
        "sum_all_births": sum(r["all_births"] for r in rows),
        "r_dk_sb_births": pearson([r["sb_births"] for r in rows], dk),
        "r_dk_sb_net": pearson([r["sb_births"] - r["sb_deaths"] for r in rows], dk),
        "r_dk_all_births": pearson([r["all_births"] for r in rows], dk),
        "r_dk_dcred": pearson([r["d_cred"] for r in rows], dk),
        "births_by_comm": births.most_common(25),
        "deaths_by_comm": deaths.most_common(25),
    }
    out.write(json.dumps({"summary": summary}) + "\n")


if __name__ == "__main__":
    main()
