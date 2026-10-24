#!/usr/bin/env python3
"""Pick 20 real subagent poll-loop calls the proposed W3 deny would refuse.
Predicate: the d9ffc3964 hook's narrow class == poll-loop (as replayed into myjoined.json by the
numbers reviewer, which agreed with the live hook on 11,436/11,436), MINUS the proposed exemption
(an inner `timeout N` with N < 300, price.py's selfbound()). One call per agent (its FIRST
poll-loop call: the first deny is the one whose response we are testing). Seeded simple random
sample. Read-only. Usage: python3 -I sample.py <myjoined.json> <out.json> [seed]"""
import json, re, sys, random
from collections import Counter

J = json.load(open(sys.argv[1]))
TO_RX = re.compile(r"(?:^|[;&|\s(])g?timeout\s+(?:-\S+\s+)*([0-9]+)([sm]?)\s")


def selfbound(cmd):
    ns = [int(m.group(1)) * (60 if m.group(2) == "m" else 1) for m in TO_RX.finditer(cmd)]
    return bool(ns) and max(ns) < 300


pl = [r for r in J if r.get("why") == "poll-loop"]
den = [r for r in pl if not selfbound(r["cmd"])]
first = {}
for r in sorted(den, key=lambda r: r["t"]):
    k = r["file"].rsplit("/", 1)[-1]
    first.setdefault(k, r)
agents = sorted(first.values(), key=lambda r: r["id"])
LOOPKW = re.compile(r"(^|[;&|\s(])(while|until|for)\s")


def kind(c):
    m = LOOPKW.search(c)
    return m.group(2) if m else "?"


print("poll-loop calls", len(pl), "denied after exemption", len(den), "unique agents", len(agents))
print("population loop kind (denied calls):", Counter(kind(r["cmd"]) for r in den))
print("population rebuilt share (denied calls): %d/%d" % (sum(bool(r["reb"]) for r in den), len(den)))
print("population workflow share (agents): %d/%d" % (sum("/workflows/" in r["file"] for r in agents), len(agents)))
random.seed(int(sys.argv[3]) if len(sys.argv) > 3 else 33)
S = random.sample(agents, 20)
print("sample loop kind:", Counter(kind(r["cmd"]) for r in S))
print("sample rebuilt: %d/20" % sum(bool(r["reb"]) for r in S))
print("sample workflow agents: %d/20" % sum("/workflows/" in r["file"] for r in S))
print("sample accounts:", Counter(r["acct"] for r in S))
json.dump(S, open(sys.argv[2], "w"), indent=1)
