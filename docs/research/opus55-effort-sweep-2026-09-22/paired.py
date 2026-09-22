#!/usr/bin/env python3
"""paired.py — paired comparisons over the 36 ground-truth items (strict majority, >=2 of 3).

Each item is credited or not per arm; a pair of arms is compared on its DISCORDANT items (credited
by one arm only) with an exact two-sided sign test (McNemar's exact form). Also per-brief sign test.
The 09-10 Fable README reported vote-threshold tables but no formal paired test; this adds one.

  paired.py <scores.jsonl>
"""
import json, sys
from math import comb
from collections import defaultdict

rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip() and '"error"' not in l]
votes = defaultdict(set)
for r in rows:
    for g in r["credited"]:
        votes[(r["brief_id"], r["arm"], g)].add(r["judge"])
man = {m["id"]: m for m in json.load(open("../../../tests/fixtures/codex-probe/manifest.json"))}
items = [(b, i) for b, m in sorted(man.items()) if m["has_defect"] for i in range(1, len(m["ground_truth"]) + 1)]
hit = lambda a, b, i: len(votes.get((b, a, i), ())) >= 2

def p2(k, n):
    return min(1.0, 2 * sum(comb(n, j) for j in range(0, min(k, n - k) + 1)) / 2 ** n) if n else 1.0

PAIRS = [("o55@xhigh", "f51@high"), ("o55@high", "f51@high"), ("o55@medium", "f51@high"),
         ("o55@xhigh", "o5@max"), ("o55@high", "o5@high"), ("o55@xhigh", "o5@high"),
         ("o55@medium", "o55@xhigh"), ("o55@high", "o55@xhigh"), ("o55@xhigh", "o55@max"),
         ("o55@low", "o55@medium"), ("o5@high", "o5@max")]
print("| A vs B | A | B | items A only | items B only | exact sign p (items) | briefs A>B / A<B | sign p (briefs) |")
print("|---|---|---|---|---|---|---|---|")
for a, b in PAIRS:
    ao = sum(1 for (x, i) in items if hit(a, x, i) and not hit(b, x, i))
    bo = sum(1 for (x, i) in items if hit(b, x, i) and not hit(a, x, i))
    ta = sum(hit(a, x, i) for x, i in items); tb = sum(hit(b, x, i) for x, i in items)
    briefs = sorted({x for x, _ in items})
    d = [sum(hit(a, x, i) for y, i in items if y == x) - sum(hit(b, x, i) for y, i in items if y == x) for x in briefs]
    w, l = sum(v > 0 for v in d), sum(v < 0 for v in d)
    print(f"| {a} vs {b} | {ta} | {tb} | {ao} | {bo} | {p2(ao, ao + bo):.2f} | {w} / {l} | {p2(w, w + l):.2f} |")
