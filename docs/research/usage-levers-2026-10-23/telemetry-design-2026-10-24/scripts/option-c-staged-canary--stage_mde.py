#!/usr/bin/env python3
"""Stage-by-stage MDE / tripwire arithmetic for option C (staged canary).
Inputs are the noise-floor worker's MEASURED per-event SDs and event rates
(/tmp/lev-design/noise-floor/event_level.out, data/d4events.out, summary.tsv).
MDE (80% power, two-sided 5%) in pp/week fleet = 2.80*sd*sqrt(1-R2)*sqrt((1/p+1/(1-p))/N)*n_w,
N = n_w*weeks; the same formula eventmde.py uses at p=0.5 (checked: D3 1wk -> 6.0)."""
import math
Z = 1.959964 + 0.841621
LEV = {
    # name: (sd per event pp, events/week, {covariate label: R2}, expected pp/week lo-hi)
    "D3": (0.0358, 906, {"raw": 0.0, "ctx": 0.11, "ctx+timing": 0.94}, (3.9, 5.1)),
    "D4": (2.63 / (2 * Z * math.sqrt(932)), 932, {"raw": 0.0, "ctx": 0.06}, (1.4, 5.2)),
    "D1": (0.4028, 162, {"raw": 0.0}, (8.0, 11.1)),
}
def mde(sd, nw, r2, p, weeks, extra=1.0):
    N = nw * weeks
    return Z * sd * math.sqrt(1 - r2) * math.sqrt((1 / p + 1 / (1 - p)) / N) * nw * extra
print("lever cov p weeks MDE_pp_wk expected")
for k, (sd, nw, covs, ex) in LEV.items():
    for cov, r2 in covs.items():
        for p in (0.10, 0.50, 0.95):
            for w in (1, 2, 4):
                print(k, cov, p, w, round(mde(sd, nw, r2, p, w), 2), "%s-%s" % ex)
print("# hillclimb round inside the 50% stage: cand vs inc, each 25% of eligible events;")
print("# 'test' = the sealed 50% session half only (x sqrt2 on N)")
for k, (sd, nw, covs, ex) in LEV.items():
    for cov, r2 in covs.items():
        for w in (1, 2, 4):
            # two arms of 0.25 each: var factor (1/.25+1/.25)=8 vs 4 at 50/50 -> sqrt2
            pooled = mde(sd, nw, r2, 0.5, w, extra=math.sqrt(2))
            test = pooled * math.sqrt(2)
            print(k, cov, "round", w, "pooled", round(pooled, 2), "test_half", round(test, 2))
def wilson_lo(x, n, z=1.959964):
    if n == 0:
        return 0.0
    ph = x / n
    d = 1 + z * z / n
    c = ph + z * z / (2 * n)
    r = z * math.sqrt(ph * (1 - ph) / n + z * z / (4 * n * n))
    return (c - r) / d
def wilson_hi(x, n, z=1.959964):
    return 1 - wilson_lo(n - x, n, z)
print("# compliance: smallest n whose Wilson95 lower bound clears the bar at an observed rate")
for bar in (0.80, 0.60):
    for obs in (1.0, 0.95, 0.90):
        n = next(n for n in range(1, 5000) if wilson_lo(round(obs * n), n) >= bar)
        print("bar", bar, "observed", obs, "n_min", n)
print("# revert side: largest observed rate at n whose Wilson95 UPPER bound is still below the bar")
for bar in (0.80,):
    for n in (10, 20, 30):
        xs = [x for x in range(n + 1) if wilson_hi(x, n) < bar]
        print("bar", bar, "n", n, "revert_if_x_le", max(xs) if xs else None)
def pois_ge(k, lam):
    return 1 - sum(math.exp(-lam) * lam ** i / math.factorial(i) for i in range(k))
print("# PTL main-session deaths: baseline 95% upper bound 0.087/100 sessions (rule of three on 0/3454);")
print("# treated sessions/week = 863.5*p (3454 main sessions / 4 weeks)")
for p in (0.10, 0.50, 1.0):
    lam = 0.087 / 100 * 863.5 * p
    print("p", p, "lambda", round(lam, 3), " ".join("P(X>=%d)=%.4f" % (k, pois_ge(k, lam)) for k in (1, 2, 3)))
print("# D2 (ESTIMATED: per-run log-cost SD sigma is NOT measured; 64 would-deny runs/week = 275/30d*7")
print("# from decisions REPORT; session-level arms, design effect ignored) -> detectable run-cost ratio")
for sigma in (0.8, 1.2, 1.6):
    for w in (1, 2, 4):
        N = 64.2 * w
        m = Z * sigma * math.sqrt(4 / N)
        print("sigma", sigma, "weeks", w, "MDE_log", round(m, 2), "ratio_detectable<=", round(math.exp(-m), 2))
