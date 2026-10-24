#!/usr/bin/env python3
# Attribute every billed response to ONE account, then save per-account event arrays.
# Rules (each saved as a separate attribution column so fits can be compared):
#   T  timeline: the session's account at the response time, from move evidence (tombstones, locks);
#      falls back to the single holder, else the earliest-birthtime holder.   <- primary
#   B  earliest-birthtime holder (yesterday's sk_bc_meter2.py rule)
#   P  holder of the live parent <sid>.jsonl if unique, else first holder (sk-cache-ttlfit2.py rule)
#   N  naive: every per-account copy counted under its own account (what /usage does)
# Read-only; writes events.npz + build.log under /tmp/usage-audit/r2/cache-read-weight/.
import csv, collections, bisect, json
import numpy as np

D = "/tmp/usage-audit/r2/cache-read-weight/"
ACCTS = ["next", "next2", "next3", "next4"]
AI = {a: i for i, a in enumerate(ACCTS)}


def family(m):
    if m.startswith("claude-opus-5-5"):
        return 1
    if m.startswith("claude-opus-5"):
        return 0
    if m.startswith("claude-fable"):
        return 2
    if m.startswith("claude-sonnet"):
        return 3
    if m.startswith("claude-haiku"):
        return 4
    if m.startswith("claude-opus-4"):
        return 5
    return 6


files = {}
for a in ACCTS:
    for line in open(D + "rows_%s.tsv.files" % a):
        fi, sz, bt, mt, rel = line.rstrip("\n").split("\t", 4)
        files[(a, int(fi))] = (float(bt), rel)

# move timeline per session
mv = collections.defaultdict(list)
for r in csv.DictReader(open(D + "moves.tsv"), delimiter="\t"):
    if r["from"] in AI and r["to"] in AI:
        mv[r["sid"]].append((float(r["ts"]), r["from"], r["to"]))
for s in mv:
    mv[s].sort()


def acct_at(sid, t):
    E = mv.get(sid)
    if not E:
        return None
    a = E[0][1]
    for ts, f, to in E:
        if ts <= t:
            a = to
        else:
            break
    return a


retired = collections.defaultdict(set)
for r in csv.DictReader(open(D + "retired_rows.tsv"), delimiter="\t"):
    retired[r["req"]].add(r["acct"])

# live parent transcript holders: (proj, sid) -> accounts holding <proj>/<sid>.jsonl
mainhold = collections.defaultdict(set)
for (a, fi), (bt, rel) in files.items():
    parts = rel.split("/")
    if len(parts) == 2 and parts[1].endswith(".jsonl"):
        mainhold[(parts[0], parts[1][:-6])].add(a)

recs = collections.defaultdict(list)
for a in ACCTS:
    for r in csv.DictReader(open(D + "rows_%s.tsv" % a), delimiter="\t"):
        if r["model"] == "<synthetic>":
            continue
        recs[r["req"]].append(r)

stat = collections.Counter()
out = []  # ts, T, B, P, fam, kind, inp, cc5, cc1, cr, outF, outFirst, outMax, web
naive = []
for req, L in recs.items():
    for r in L:
        cc_un = int(r["cc"]) - int(r["cc5"]) - int(r["cc1"])
        naive.append(
            (
                float(r["ts"]),
                AI[r["acct"]],
                family(r["model"]),
                0 if r["kind"] == "m" else 1,
                int(r["inp"]),
                int(r["cc5"]) + max(0, cc_un),
                int(r["cc1"]),
                int(r["cr"]),
                int(r["out_final"]),
                int(r["out_first"]),
                int(r["out_max"]),
                int(r["web"]),
            )
        )
    holders = sorted(set(r["acct"] for r in L))
    r0 = L[0]
    bt0, rel0 = files[(r0["acct"], int(r0["file"]))]
    parts = rel0.split("/")
    proj = parts[0]
    sid = parts[1][:-6] if len(parts) == 2 else parts[1]
    t = float(r0["ts"])
    # B: earliest birthtime holder
    bsort = sorted(L, key=lambda r: files[(r["acct"], int(r["file"]))][0])
    aB = bsort[0]["acct"]
    # P: live parent holder
    ph = [a for a in mainhold.get((proj, sid), ()) if a in holders]
    aP = ph[0] if len(ph) == 1 else holders[0]
    # T: timeline
    tl = acct_at(sid, t)
    allh = set(holders) | retired.get(req, set())
    if tl is not None and tl in allh:
        aT = tl
        stat["T_timeline"] += 1
        if len(holders) == 1 and tl != holders[0]:
            stat["T_moved_off_single_live_holder"] += 1
    elif tl is not None:
        stat["T_timeline_not_a_holder"] += 1
        aT = holders[0] if len(holders) == 1 else aB
    elif len(holders) == 1:
        aT = holders[0]
        stat["T_single_holder"] += 1
    else:
        aT = aB
        stat["T_fallback_birthtime"] += 1
    if len(holders) > 1:
        stat["multi_holder"] += 1
    if aT != aB:
        stat["T_ne_B"] += 1
    if aT != aP:
        stat["T_ne_P"] += 1
    # output from the FINAL record; if copies disagree keep the max over copies of the final record
    outF = max(int(r["out_final"]) for r in L)
    outFirst = min(int(r["out_first"]) for r in L)
    outMax = max(int(r["out_max"]) for r in L)
    cc_un = int(r0["cc"]) - int(r0["cc5"]) - int(r0["cc1"])
    out.append(
        (
            t,
            AI[aT],
            AI[aB],
            AI[aP],
            family(r0["model"]),
            0 if r0["kind"] == "m" else 1,
            int(r0["inp"]),
            int(r0["cc5"]) + max(0, cc_un),
            int(r0["cc1"]),
            int(r0["cr"]),
            outF,
            outFirst,
            outMax,
            int(r0["web"]),
        )
    )
    stat["unique_req"] += 1
stat["naive_rows"] = len(naive)
A = np.array(out, dtype=float)
Nv = np.array(naive, dtype=float)
np.savez_compressed(D + "events.npz", A=A, N=Nv)
cols = ["inp", "cc5", "cc1", "cr", "outF", "outFirst", "outMax"]
tot = A[:, 6:13].sum(0)
totN = Nv[:, 4:11].sum(0)
with open(D + "build.log", "w") as f:
    for k, v in sorted(stat.items()):
        f.write("%s\t%d\n" % (k, v))
    f.write(
        "unique totals (M): "
        + " ".join("%s=%.1f" % (c, x / 1e6) for c, x in zip(cols, tot))
        + "\n"
    )
    f.write(
        "naive totals (M):  "
        + " ".join("%s=%.1f" % (c, x / 1e6) for c, x in zip(cols, totN))
        + "\n"
    )
    for i, a in enumerate(ACCTS):
        f.write(
            "%s T-attributed cr=%.0fM out=%.1fM | naive cr=%.0fM out=%.1fM\n"
            % (
                a,
                A[A[:, 1] == i, 9].sum() / 1e6,
                A[A[:, 1] == i, 10].sum() / 1e6,
                Nv[Nv[:, 1] == i, 7].sum() / 1e6,
                Nv[Nv[:, 1] == i, 8].sum() / 1e6,
            )
        )
print(open(D + "build.log").read())
