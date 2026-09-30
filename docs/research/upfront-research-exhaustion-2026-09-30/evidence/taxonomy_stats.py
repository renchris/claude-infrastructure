#!/usr/bin/env python3
"""Recompute every count in /tmp/rescomp/taxonomy.md from the ledger taxonomy_holes.py."""
import collections, importlib.util, sys
spec = importlib.util.spec_from_file_location("L", "/tmp/rescomp/taxonomy_holes.py")
L = importlib.util.module_from_spec(spec); spec.loader.exec_module(L)
H = L.H
ids = [h[0] for h in H]
assert len(ids) == len(set(ids)), "duplicate ids"
print("holes:", len(H), " ids 1..%d contiguous:" % max(ids), sorted(ids) == list(range(1, max(ids)+1)))
base = lambda c: "C2" if c.startswith("C2") else c
order = ["C%d" % i for i in range(1, 12)]
cls = collections.defaultdict(list)
for h in H: cls[base(h[7])].append(h)
print("\n%-4s %4s %5s | %3s %3s %3s %3s %3s | %3s %3s %3s %3s" % ("cls","n","%","DC","REF","COS","NEW","UNC","D","P","O","N"))
tm = collections.Counter(); tf = collections.Counter()
for c in order:
    rows = cls[c]; m = collections.Counter(h[5] for h in rows); f = collections.Counter(h[6] for h in rows)
    tm += m; tf += f
    print("%-4s %4d %5.1f | %3d %3d %3d %3d %3d | %3d %3d %3d %3d" % (c, len(rows), 100*len(rows)/len(H), m["DC"], m["REF"], m["COS"], m["NEW"], m["UNC"], f["D"], f["P"], f["O"], f["N"]))
print("TOT  %4d       | %3d %3d %3d %3d %3d | %3d %3d %3d %3d" % (len(H), tm["DC"], tm["REF"], tm["COS"], tm["NEW"], tm["UNC"], tf["D"], tf["P"], tf["O"], tf["N"]))
print("\nC2 subtypes:", collections.Counter(h[7] for h in H if h[7].startswith("C2")))
print("DC and desk:", sum(1 for h in H if h[5]=="DC" and h[6]=="D"), "by class:",
      {c: sum(1 for h in cls[c] if h[5]=="DC" and h[6]=="D") for c in order})
print("per shard:", dict(sorted(collections.Counter(h[1] for h in H).items())))
for c in order: print(c, ", ".join(str(h[0]) for h in cls[c]))
inside = sum(len(cls[c]) for c in ["C3","C4","C5","C6","C7","C8"])
print("\nmiss-inside-frame C3-C8:", inside, "%.1f%%" % (100*inside/len(H)),
      "DC", sum(1 for c in ["C3","C4","C5","C6","C7","C8"] for h in cls[c] if h[5]=="DC"))
print("C2u+C11:", sum(1 for h in H if h[7]=="C2u") + len(cls["C11"]),
      "DC", sum(1 for h in H if h[7]=="C2u" and h[5]=="DC") + sum(1 for h in cls["C11"] if h[5]=="DC"))
print("C9+C10:", len(cls["C9"])+len(cls["C10"]), "DC", sum(1 for c in ["C9","C10"] for h in cls[c] if h[5]=="DC"))
