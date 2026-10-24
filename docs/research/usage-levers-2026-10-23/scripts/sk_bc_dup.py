#!/usr/bin/env python3
# Cross-account duplicate characterisation (same requestId in several accounts' transcript dirs).
import csv, collections, os
from datetime import datetime

CUT7 = datetime.fromisoformat("2026-10-17T02:30:00+00:00").timestamp()
ACCTS = ["next", "next2", "next3", "next4"]
files = {}
for a in ACCTS:
    for line in open("/tmp/usage-audit/sk_bc_rows_%s.tsv.files" % a):
        fi, sz, p = line.rstrip("\n").split("\t", 2)
        files[(a, int(fi))] = p
by_req = collections.defaultdict(list)
rows = {}
for a in ACCTS:
    with open("/tmp/usage-audit/sk_bc_rows_%s.tsv" % a) as f:
        r = csv.reader(f, delimiter="\t")
        next(r)
        for x in r:
            k = x[4]
            by_req[k].append(
                (
                    a,
                    x[1],
                    int(x[2]),
                    float(x[3]),
                    int(x[6]) + int(x[7]) + int(x[10]),
                    int(x[10]),
                    int(x[7]),
                    int(x[11]),
                )
            )
multi = {k: v for k, v in by_req.items() if len(set(e[0] for e in v)) > 1}
print("request ids present in >1 account:", len(multi), "of", len(by_req))
pairs = collections.Counter(tuple(sorted(set(e[0] for e in v))) for v in multi.values())
print("account sets:", pairs.most_common(8))
kinds = collections.Counter(tuple(sorted(e[1] for e in v)) for v in multi.values())
print("kind sets:", kinds.most_common(5))
same_name = collections.Counter()
ex = []
for k, v in list(multi.items()):
    names = set(os.path.basename(files[(e[0], e[2])]) for e in v)
    same_name["same basename" if len(names) == 1 else "different basename"] += 1
    if len(ex) < 3:
        ex.append([(e[0], files[(e[0], e[2])]) for e in v])
print(same_name)
for e in ex:
    print("  example:", e)
# 7d main-session impact
m7 = [(k, v) for k, v in by_req.items() if any(e[1] == "m" and e[3] >= CUT7 for e in v)]
tot_copies = sum(sum(1 for e in v if e[1] == "m" and e[3] >= CUT7) for k, v in m7)
uniq = len(m7)
tok_copies = sum(sum(e[4] for e in v if e[1] == "m" and e[3] >= CUT7) for k, v in m7)
tok_uniq = sum([e for e in v if e[1] == "m" and e[3] >= CUT7][0][4] for k, v in m7)
print(
    "\n7d MAIN: per-account rows %d, unique request ids across accounts %d (%.1f%% are cross-account copies)"
    % (tot_copies, uniq, 100.0 * (tot_copies - uniq) / tot_copies)
)
print(
    "7d MAIN input-side tokens: per-account sum %.2fB, globally unique %.2fB (%.1f%% inflation)"
    % (tok_copies / 1e9, tok_uniq / 1e9, 100.0 * (tok_copies - tok_uniq) / tok_uniq)
)
s7 = [(k, v) for k, v in by_req.items() if any(e[1] == "s" and e[3] >= CUT7 for e in v)]
tc = sum(sum(1 for e in v if e[1] == "s" and e[3] >= CUT7) for k, v in s7)
print(
    "7d SUB: per-account rows %d, unique %d (%.1f%% copies)"
    % (tc, len(s7), 100.0 * (tc - len(s7)) / tc)
)
# who holds the copy: timestamp of copy identical? (copy = same record in two dirs)
