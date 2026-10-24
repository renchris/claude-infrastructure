#!/usr/bin/env python3
"""Per-account wrong-deny cost (the read-out's ACCEPT test is per account) with copies attributed to the
earliest-born transcript copy. Usage: python3 -I peracct.py mybash.jsonl myjoined.json <days> [from_iso]"""

import json, math, os, sys
from collections import defaultdict
from datetime import datetime

SRC, JF, DAYS = sys.argv[1], sys.argv[2], float(sys.argv[3])
tf = (
    datetime.fromisoformat(sys.argv[4].replace("Z", "+00:00")).timestamp()
    if len(sys.argv) > 4
    else 0
)
wk = 7.0 / DAYS
J = [r for r in json.load(open(JF)) if r["why"] and r["t"] >= tf]
ids = set(r["id"] for r in J)
copies = defaultdict(set)
for l in open(SRC):
    if '"to": null' in l:
        continue
    x = json.loads(l)
    if x["id"] in ids:
        copies[x["id"]].add((x["file"], x["acct"]))
bt = {}


def birth(f):
    if f not in bt:
        try:
            bt[f] = os.stat(f).st_birthtime
        except OSError:
            bt[f] = 9e18
    return bt[f]


def acct_of(r):
    c = copies.get(r["id"]) or {(r["file"], r["acct"])}
    return min(c, key=lambda fa: birth(fa[0]))[1]


K = dict(
    low=(0.0057, 500, 60),
    high=(0.0076, 1234, 300),
    readout=(0.0057, 300, 150),
    readout_hi=(0.0076, 300, 150),
)


def per(ctx, k):
    R, w, o = K[k]
    return (ctx * R + w * 0.245 + o * 0.404) / 1e6


ndup = sum(1 for v in copies.values() if len(set(a for _, a in v)) > 1)
print("narrow calls", len(J), "with copies on >1 account", ndup)
for cls in ("narrow", "poll-loop"):
    rs = [r for r in J if cls == "narrow" or r["why"] == cls]
    for k in K:
        out = defaultdict(float)
        out2 = defaultdict(float)
        for r in rs:
            if r["rt"] is None or r["rt"] > 270:
                continue
            a = acct_of(r)
            if k.startswith("readout"):
                n = n2 = 1
            else:
                n = 1 if r["why"] == "poll-loop" else 2
                n2 = 2
            out[a] += n * per(r["ctx"], k)
            out2[a] += n2 * per(r["ctx"], k)
        print(
            "%-9s %-10s wrong pp/week per account (researcher n) %s | (bg message: 2 extra) %s"
            % (
                cls,
                k,
                {a: round(v * wk, 3) for a, v in sorted(out.items())},
                {a: round(v * wk, 3) for a, v in sorted(out2.items())},
            )
        )
