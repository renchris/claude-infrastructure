#!/usr/bin/env python3
"""What the harness returns when a foreground Bash hits its tool timeout. Read-only.
Usage: python3 -I timeout_behavior.py <bash.jsonl>"""
import json, sys, re
from collections import Counter
seen=set(); c=Counter(); ex={}
for l in open(sys.argv[1]):
    r=json.loads(l)
    if r["id"] in seen or r["bg"] or not isinstance(r["to"],(int,float)) or r["rt"] is None: continue
    seen.add(r["id"])
    if r["rt"] >= r["to"]/1000.0 - 1:
        h=(r.get("res_head") or "")
        k=re.sub(r"[0-9]+","N",h[:70])
        c[k]+=1; ex.setdefault(k,(r["to"],round(r["rt"]),h[:200]))
print("fg calls whose runtime reached the tool timeout:", sum(c.values()))
for k,v in c.most_common(12): print(v, repr(k), ex[k][:2])
