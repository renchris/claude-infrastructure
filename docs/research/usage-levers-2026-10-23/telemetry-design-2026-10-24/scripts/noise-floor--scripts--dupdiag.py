#!/usr/bin/env python3
# diagnose cross-account duplicate request ids: main vs sub, owner-set size, same path suffix
import os, sys
from collections import Counter, defaultdict
D = sys.argv[1]; S = 1790398800; E = S + 28 * 86400
ACCTS = ["next", "next2", "next3", "next4"]
paths = {}
for a in ACCTS:
    with open(os.path.join(D, a + ".files.tsv")) as fh:
        fh.readline()
        for line in fh:
            v = line.split("\t"); paths[(a, int(v[0]))] = v[1]
cp = defaultdict(list); mainown = defaultdict(set)
for a in ACCTS:
    with open(os.path.join(D, a + ".req.tsv")) as fh:
        fh.readline()
        for line in fh:
            v = line.split("\t")
            ts = float(v[4])
            if ts < S or ts >= E: continue
            cp[v[5]].append((a, int(v[1]), int(v[2]), v[3], ts, int(v[8]), int(v[10])))
            if v[2] == "0": mainown[v[3]].add(a)
c = Counter(); tok = Counter()
for k, cs in cp.items():
    ac = {x[0] for x in cs}
    if len(ac) < 2: continue
    sub = cs[0][2]
    own = mainown.get(cs[0][3], set())
    suffix_same = len({paths[(x[0], x[1])].split("/projects/")[1] for x in cs}) == 1
    key = ("sub" if sub else "main", "own%d" % min(len(own), 2), "samepath" if suffix_same else "diffpath")
    c[key] += 1
    tok[key] += cs[0][6] * 0.245 + cs[0][5] * 0.0067
for k, n in c.most_common(): print(k, n, "approx_wpp_cc+cr=%.0f" % (tok[k] / 1e6))
