#!/usr/bin/env python3
# Skeptic analysis 1: dedup, request counts vs /usage, main ctx distribution, weightings vs /usage >150k share.
import csv, sys, collections
from datetime import datetime

CUT7 = datetime.fromisoformat("2026-10-17T02:30:00+00:00").timestamp()
ACCTS = ["next", "next2", "next3", "next4"]
USAGE_REQ7 = {"next": 72233, "next2": 82745, "next3": 53237, "next4": 63509}
USAGE_GT150 = {"next": 69, "next2": 62, "next3": 66, "next4": 58}

rows = []
for a in ACCTS:
    with open("/tmp/usage-audit/sk_bc_rows_%s.tsv" % a) as f:
        r = csv.reader(f, delimiter="\t")
        next(r)
        for x in r:
            rows.append(
                (
                    x[0],
                    x[1],
                    int(x[2]),
                    float(x[3]),
                    x[4],
                    x[5],
                    int(x[6]),
                    int(x[7]),
                    int(x[8]),
                    int(x[9]),
                    int(x[10]),
                    int(x[11]),
                    int(x[12]),
                    int(x[13]),
                )
            )
print("rows loaded (per-file dedup by requestId):", len(rows))

# cross-file duplicates
occ = collections.defaultdict(list)
for i, x in enumerate(rows):
    occ[(x[0], x[4])].append(i)
dup_keys = [k for k, v in occ.items() if len(v) > 1]
kinds = collections.Counter()
for k in dup_keys:
    ks = tuple(sorted(rows[i][1] for i in occ[k]))
    kinds[ks] += 1
print("req keys in >1 file:", len(dup_keys), "of", len(occ), dict(kinds))
# cross-account duplicates
acc_by_req = collections.defaultdict(set)
for x in rows:
    acc_by_req[x[4]].add(x[0])
print(
    "req keys appearing in >1 account:",
    sum(1 for v in acc_by_req.values() if len(v) > 1),
)
# sidechain records inside main files
print(
    "main-file rows with isSidechain=1:",
    sum(1 for x in rows if x[1] == "m" and x[13] == 1),
)

# keep first occurrence globally (prefer main copy order irrelevant: identical usage)
seen = set()
U = []
for x in rows:
    k = (x[0], x[4])
    if k in seen:
        continue
    seen.add(k)
    U.append(x)
R7 = [x for x in U if x[3] >= CUT7]
print("\n7d request counts (global dedup) vs /usage:")
for a in ACCTS:
    n = sum(1 for x in R7 if x[0] == a)
    nm = sum(1 for x in R7 if x[0] == a and x[1] == "m")
    print(
        "  %-6s %6d  /usage %6d  diff %+.2f%%   main=%d sub=%d"
        % (a, n, USAGE_REQ7[a], 100.0 * (n - USAGE_REQ7[a]) / USAGE_REQ7[a], nm, n - nm)
    )

models = collections.Counter((x[1], x[5]) for x in R7)
print("\nmodel x kind (7d):", models.most_common(8))


def pct(v, q):
    v = sorted(v)
    return v[min(len(v) - 1, int(q * len(v)))]


M = [x for x in R7 if x[1] == "m"]
ctx = [x[6] + x[7] + x[10] for x in M]
print(
    "\nMAIN n=%d p50=%d p75=%d p90=%d p99=%d max=%d"
    % (len(ctx), pct(ctx, 0.5), pct(ctx, 0.75), pct(ctx, 0.9), pct(ctx, 0.99), max(ctx))
)
tot = sum(ctx)
for T in (150e3, 200e3, 250e3, 300e3, 500e3):
    print(
        "  >%dk: %.1f%% of requests, %.1f%% of input-side tokens"
        % (
            T / 1e3,
            100.0 * sum(1 for c in ctx if c > T) / len(ctx),
            100.0 * sum(c for c in ctx if c > T) / tot,
        )
    )
cr = sum(x[10] for x in M)
cc = sum(x[7] for x in M)
inp = sum(x[6] for x in M)
out = sum(x[11] for x in M)
cc1h = sum(x[9] for x in M)
cc5 = sum(x[8] for x in M)
print(
    "  main totals: input-side %.2fB  cr %.2fB (%.1f%%) cc %.3fB inp %.4fB out %.3fB"
    % (tot / 1e9, cr / 1e9, 100.0 * cr / tot, cc / 1e9, inp / 1e9, out / 1e9)
)
A = [x for x in R7]
cc1hA = sum(x[9] for x in A)
cc5A = sum(x[8] for x in A)
ccA = sum(x[7] for x in A)
print(
    "  cache-write TTL split, all 7d records: 1h %.1f%%  5m %.1f%%  (of cc %.3fB); main only 1h %.1f%%"
    % (100.0 * cc1hA / ccA, 100.0 * cc5A / ccA, ccA / 1e9, 100.0 * cc1h / max(1, cc))
)

# weighting fits vs /usage >150k share (main+sub, per account)
W = {
    "agent 1/0.1/1.25/5": (1, 0.1, 1.25, 1.25, 5),
    "list o5.5 1/0.05/cw5m1.25,cw1h2/5": (1, 0.05, 1.25, 2.0, 5),
    "list 1/0.1/cw5m1.25,cw1h2/5": (1, 0.1, 1.25, 2.0, 5),
    "meter-proxy cr=0 1/0/1.25,2/5": (1, 0.0, 1.25, 2.0, 5),
    "requests (unweighted)": None,
    "raw input-side tokens": "raw",
}
print("\nshare of usage at >150k context (main+sub) vs /usage 69/62/66/58:")
for name, w in W.items():
    res = []
    for a in ACCTS:
        num = den = 0.0
        for x in R7:
            if x[0] != a:
                continue
            c = x[6] + x[7] + x[10]
            if w is None:
                v = 1.0
            elif w == "raw":
                v = c
            else:
                cc5r = x[8]
                cc1r = x[9]
                other = x[7] - cc5r - cc1r
                v = (
                    w[0] * x[6]
                    + w[1] * x[10]
                    + w[2] * (cc5r + other)
                    + w[3] * cc1r
                    + w[4] * x[11]
                )
            den += v
            if c > 150e3:
                num += v
        res.append(100.0 * num / den)
    mae = sum(abs(r - USAGE_GT150[a]) for r, a in zip(res, ACCTS)) / 4
    print("  %-38s %s  MAE %.1f" % (name, " ".join("%5.1f" % r for r in res), mae))
