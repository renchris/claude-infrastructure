#!/usr/bin/env python3
"""Full deny texts per class (one example each) and sub-variants of the subagent ask->deny refusal.
Usage: python3 -I fulltext.py <followups.jsonl>"""

import json, sys, re
from collections import Counter

rows = [json.loads(l) for l in open(sys.argv[1])]
want = {}
for r in rows:
    k = r["cls"]
    if k.startswith("other:Refused inside a subagent: no one"):
        # sub-variant: the sentence after the first
        sub = re.sub(
            r"\s+",
            " ",
            r["reason_head"].split("no one can answer a prompt here.", 1)[-1],
        )[:70]
        k = "subagent-ask-refused | " + sub
    want.setdefault(k, []).append(r)
c = Counter({k: len(v) for k, v in want.items()})
for k, v in c.most_common(25):
    print(v, k)


def full(r):
    for line in open(r["file"], errors="replace"):
        if r["id"] in line and "tool_result" in line:
            d = json.loads(line)
            for x in d["message"]["content"]:
                if isinstance(x, dict) and x.get("tool_use_id") == r["id"]:
                    cc = x.get("content")
                    return cc if isinstance(cc, str) else json.dumps(cc)
    return ""


print()
for k in ["builtin-sleep-block", "goal-gate"] + [
    k for k, _ in c.most_common(4) if k.startswith("subagent-ask")
]:
    if k in want:
        print("=====", k)
        print(full(want[k][0])[:2500])
        print()
