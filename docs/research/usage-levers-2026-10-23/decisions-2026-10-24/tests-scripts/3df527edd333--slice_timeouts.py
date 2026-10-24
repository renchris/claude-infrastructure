#!/usr/bin/env python3
"""Real behavior for criterion (c): when a subagent's OWN bounded wait slice runs out (a foreground
loop with an inner `timeout N`, N < 300, that came back with exit 124), what is its next Bash call?
Resume in another slice, escalate to a long call (what W3 would deny), background it, or move on?
Read-only over the round's bash.jsonl (14 days, 4 accounts, copies deduped by id).
Usage: python3 -I slice_timeouts.py <bash.jsonl>"""

import json, re, sys
from collections import Counter, defaultdict

TO_RX = re.compile(r"(?:^|[;&|\s(])g?timeout\s+(?:-\S+\s+)*([0-9]+)([sm]?)\s")
LOOP = re.compile(r"(^|[;&|\s(])(while|until|for)\s.*sleep\s", re.S)


def inner(cmd):
    ns = [
        int(m.group(1)) * (60 if m.group(2) == "m" else 1) for m in TO_RX.finditer(cmd)
    ]
    return max(ns) if ns else None


seen = set()
byfile = defaultdict(list)
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r["id"] in seen:
        continue
    seen.add(r["id"])
    byfile[r["file"]].append(r)
k = Counter()
ex = defaultdict(list)
chains = Counter()
for f, L in byfile.items():
    L.sort(key=lambda r: r["t"])
    for i, r in enumerate(L):
        c = r.get("cmd") or ""
        n = inner(c)
        if r.get("bg") or n is None or n >= 300 or not LOOP.search(c):
            continue
        h = r.get("res_head") or ""
        if not re.search(r"(rc=|exit[= ]|Exit code |status=)124\b|\b124\b", h[:200]):
            continue
        nx = L[i + 1] if i + 1 < len(L) else None
        if nx is None:
            cat = "no later Bash call in this agent"
        else:
            nc = nx.get("cmd") or ""
            nn = inner(nc)
            to = nx.get("to")
            long_to = isinstance(to, (int, float)) and to > 270000
            if nx.get("bg"):
                cat = "next Bash backgrounded"
            elif LOOP.search(nc) and (long_to or (nn is not None and nn >= 300)):
                cat = "ESCALATED: long foreground loop (inner >=300 or tool >270000)"
            elif LOOP.search(nc) and not long_to and (nn is None or nn < 300):
                cat = "RESUMED: another bounded foreground slice"
            else:
                cat = "moved on / one-shot check"
        k[cat] += 1
        if len(ex[cat]) < 2 and nx is not None:
            ex[cat].append((c[:160], (nx.get("cmd") or "")[:160], nx.get("to")))
tot = sum(k.values())
print("bounded foreground wait slices that timed out (exit 124):", tot)
for a, b in k.most_common():
    print("  %4d  %4.0f%%  %s" % (b, 100.0 * b / tot, a))
for a, L in ex.items():
    print("##", a)
    for x, y, t in L:
        print("   was:  ", x.replace("\n", " "))
        print("   next: ", y.replace("\n", " "), "| tool timeout", t)
