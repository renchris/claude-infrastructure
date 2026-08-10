#!/usr/bin/env python3
"""Citation graph over the backlog — the derived impact signal.

An item's title cites other 12-hex item ids. In-degree (how many OTHER items name
this one) is a measured proxy for "closing this retires or unblocks others" — it
cannot go stale, because nothing stores it.

Emits, per item: in-degree, out-degree, and the ids on each side.
"""

import json
import os
import re
from collections import defaultdict

SP = os.path.dirname(os.path.abspath(__file__))
items = json.load(open(os.path.join(SP, "backlog-open.json")))
by_id = {i["id"]: i for i in items}

HEX12 = re.compile(r"\b[0-9a-f]{12}\b")

out = defaultdict(set)
inn = defaultdict(set)

for it in items:
    src = it["id"]
    blob = " ".join(
        str(it.get(k) or "")
        for k in ("title", "evidence", "needs", "dodRef", "condition", "source")
    )
    for tgt in set(HEX12.findall(blob)):
        if tgt == src or tgt not in by_id:
            continue  # self-ref, or a git sha / foreign id that is not an open item
        out[src].add(tgt)
        inn[tgt].add(src)

rows = []
for i in items:
    iid = i["id"]
    rows.append(
        {
            "id": iid,
            "status": i.get("status"),
            "project": i.get("project"),
            "in": len(inn[iid]),
            "out": len(out[iid]),
            "cited_by": sorted(inn[iid]),
            "cites": sorted(out[iid]),
            "title": (i.get("title") or "")[:120],
        }
    )

rows.sort(key=lambda r: (-r["in"], -r["out"]))
with open(os.path.join(SP, "citegraph.json"), "w") as fh:
    json.dump(rows, fh, indent=1)

linked = sum(1 for r in rows if r["in"] or r["out"])
print(
    f"items={len(rows)}  with-any-edge={linked}  edges={sum(len(v) for v in out.values())}"
)
print("\nTOP IN-DEGREE (closing these retires/unblocks the most):")
for r in rows[:20]:
    if not r["in"]:
        break
    print(
        f"  in={r['in']:2d} out={r['out']:2d}  {r['id']}  [{r['status']}]  {r['title'][:88]}"
    )
