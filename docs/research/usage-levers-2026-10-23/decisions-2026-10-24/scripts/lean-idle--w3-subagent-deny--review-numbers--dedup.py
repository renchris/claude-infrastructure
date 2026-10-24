#!/usr/bin/env python3
"""Dedupe mybash.jsonl by tool_use id; report copy disagreement; write broad set (fg, to>270000).
Usage: python3 -I dedup.py mybash.jsonl broad.jsonl"""

import json, sys
from collections import Counter, defaultdict

SRC, OUT = sys.argv[1], sys.argv[2]
cp = defaultdict(list)
for l in open(SRC):
    r = json.loads(l)
    cp[r["id"]].append(r)
tot = sum(len(v) for v in cp.values())
print("rows", tot, "unique ids", len(cp), "copies dropped", tot - len(cp))
dis = Counter()
accts = Counter()
broad = []
for tid, v in cp.items():
    if len(v) > 1:
        accts[tuple(sorted(set(x["acct"] for x in v)))] += 1
        k = lambda x: (x.get("tres"), x.get("nt0"), x.get("ncc"), x["ctx"])
        if len(set(k(x) for x in v)) > 1:
            dis["disagree"] += 1
            if len(set(x.get("tres") is None for x in v)) > 1:
                dis["result_missing_in_some"] += 1
            if len(set(x.get("nt0") is None for x in v)) > 1:
                dis["next_missing_in_some"] += 1
            if len(set(round(x["t"]) for x in v)) > 1:
                dis["issue_ts_differs"] += 1
        else:
            dis["agree"] += 1
    # pick most complete copy: has result, has next, latest file length
    best = max(
        v,
        key=lambda x: (
            x.get("tres") is not None,
            x.get("nt0") is not None,
            x.get("nfile", 0),
        ),
    )
    best["ncopies"] = len(v)
    if (
        (not best["bg"])
        and isinstance(best["to"], (int, float))
        and best["to"] > 270000
    ):
        broad.append(best)
print("dup agreement", dict(dis))
print("dup account combos (top)", accts.most_common(8))
print("broad unique", len(broad))
with open(OUT, "w") as f:
    for r in broad:
        f.write(json.dumps(r) + "\n")
