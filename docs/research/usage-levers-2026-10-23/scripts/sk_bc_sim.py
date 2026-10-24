#!/usr/bin/env python3
# Skeptic recycle simulation. Main sessions, 7d window, copies removed (main has ~none).
# Policies: ANY request (agent-like) | TURN boundary only (idle points) | EXPIRED boundary only (gap>1h).
import csv, collections, os
from datetime import datetime

CUT7 = datetime.fromisoformat("2026-10-17T02:30:00+00:00").timestamp()
ACCTS = ["next", "next2", "next3", "next4"]
WEIGHTS = {  # inp, cc5m, cc1h, cr, out
    "agent 1/.1/1.25/5": (1, 1.25, 1.25, 0.1, 5),
    "list-5.5 1/.05/2/5": (1, 1.25, 2.0, 0.05, 5),
    "meter-fit(no inp) pp/Mtok": (0, 0.3473, 0.2896, 0.0067, 0.9248),
    "meter-fit(with inp) pp/Mtok": (410.08, 0.2331, 0.2789, 0.0045, 0.3596),
}
seen = set()
main = collections.defaultdict(list)
allrows = []
for a in ACCTS:
    with open("/tmp/usage-audit/sk_bc_rows_%s.tsv" % a) as f:
        r = csv.reader(f, delimiter="\t")
        next(r)
        for x in r:
            if float(x[3]) < CUT7 or x[5] == "<synthetic>":
                continue
            if x[4] in seen:
                continue  # cross-account copy (subagent transcripts copied on transplant)
            seen.add(x[4])
            inp, cc, cc5, cc1, cr, out = (
                int(x[6]),
                int(x[7]),
                int(x[8]),
                int(x[9]),
                int(x[10]),
                int(x[11]),
            )
            cc5 = cc5 + max(0, cc - cc5 - cc1)
            rec = (float(x[3]), inp, cc5, cc1, cr, out, int(x[12]))
            allrows.append(rec)
            if x[1] == "m":
                main[(a, int(x[2]))].append(rec)
for k in main:
    main[k].sort()


def cost(w, inp, cc5, cc1, cr, out):
    return w[0] * inp + w[1] * cc5 + w[2] * cc1 + w[3] * cr + w[4] * out


R = 100_000  # successor context once re-primed (measured p50 at request 10 for fresh AND successor sessions)
R_FIRST_W = 59_000  # successor first-request cache write p50 (sk_bc_succ.py)
REBUILD_REQS = 9  # requests 2..10 that grow the successor from ~74k to ~100k (reads of the growing context)
HANDOFF_REQS = 3  # predecessor handoff turn
HANDOFF_OUT = 4000  # output tokens to write the handoff (estimate)


def simulate(T, policy, w):
    base = new = 0.0
    nrec = 0
    for k, L in main.items():
        off = 0
        prev_c = None
        prev_t = None
        prev_eff = 0
        for t, inp, cc5, cc1, cr, out, turn in L:
            c = inp + cc5 + cc1 + cr
            bc = cost(w, inp, cc5, cc1, cr, out)
            base += bc
            if prev_c is not None and c < 0.6 * prev_c:
                off = (
                    0  # the original compacted/cleared: its own context already dropped
                )
            can = False
            if prev_c is not None and prev_eff > T:
                if policy == "any":
                    can = True
                elif policy == "turn":
                    can = bool(turn)
                elif policy == "expired":
                    can = bool(turn) and (t - prev_t) > 3600
            if can:
                nrec += 1
                # predecessor writes a handoff: HANDOFF_REQS reads at its current context + output
                new += cost(w, 0, 0, 0, HANDOFF_REQS * prev_eff, HANDOFF_OUT)
                # successor re-prime: first request writes R_FIRST_W (1h), reads the shared prefix; then rebuild reads
                new += cost(w, 0, 0, R_FIRST_W, 74_000 - R_FIRST_W, 0)
                new += cost(w, 0, 0, R - 74_000, REBUILD_REQS * 87_000, 0)
                off = prev_c - R
            eff = c - off
            if off:
                # same new content as the original (its cc), capped by the smaller context; the rest is read
                fresh5 = min(cc5, eff)
                fresh1 = min(cc1, max(0, eff - fresh5))
                crn = max(0, eff - fresh5 - fresh1 - inp)
                new += cost(w, inp, fresh5, fresh1, crn, out)
            else:
                new += bc
            prev_c, prev_t, prev_eff = c, t, eff
    return base, new, nrec


tot = {n: sum(cost(w, *r[1:6]) for r in allrows) for n, w in WEIGHTS.items()}
nmain = sum(len(L) for L in main.values())
nturn = sum(r[6] for L in main.values() for r in L)
print(
    "main sessions %d, main requests %d, turn-start requests %d (%.1f%%)"
    % (len(main), nmain, nturn, 100.0 * nturn / nmain)
)
for n, w in WEIGHTS.items():
    mb = sum(cost(w, *r[1:6]) for L in main.values() for r in L)
    mcr = sum(cost(w, 0, 0, 0, r[4], 0) for L in main.values() for r in L)
    print(
        "\n== weights %s: all-usage total %.4g, main %.1f%% of it, main cache-read %.1f%% of all"
        % (n, tot[n], 100 * mb / tot[n], 100 * mcr / tot[n])
    )
    for policy in ("any", "turn", "expired"):
        for T in (150_000, 250_000, 350_000):
            base, new, nrec = simulate(T, policy, w)
            print(
                "   %-7s T=%dk recycles=%5d  main saving %5.1f%%  = %5.1f%% of ALL usage"
                % (
                    policy,
                    T // 1000,
                    nrec,
                    100 * (base - new) / base,
                    100 * (base - new) / tot[n],
                )
            )
