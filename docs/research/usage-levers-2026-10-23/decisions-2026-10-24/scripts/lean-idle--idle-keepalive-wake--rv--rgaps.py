#!/usr/bin/env python3
# Reviewer gap builder over rscan.py output. One row per idle gap (a Stop followed by a turn opener),
# plus one terminal row per session. Writes rgaps.tsv and prints population counts.
# usage: python3 -I rgaps.py <dir>
import bisect
import collections
import json
import os
import re
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

D = sys.argv[1]
S, E = 1791655200.0, 1792864800.0
ACCTS = ["next", "next2", "next3", "next4"]
CHI = ZoneInfo("America/Chicago")

F = []
for a in ACCTS:
    for line in open(os.path.join(D, a + ".jsonl")):
        F.append(json.loads(line))

# cross-file duplicate requests
occ = collections.defaultdict(list)
for k, f in enumerate(F):
    for x in f["reqs"]:
        occ[x[7]].append(k)
dup = sum(1 for v in occ.values() if len(v) > 1)
dup_x = sum(1 for v in occ.values() if len({F[k]["acct"] for k in v}) > 1)
print(
    "requests(unique)", len(occ), "dup_across_files", dup, "dup_across_accounts", dup_x
)
owner = {}
for rid, v in occ.items():
    owner[rid] = min(v, key=lambda k: F[k]["mt"])

ends = collections.defaultdict(list)
rx = re.compile(
    r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\] Session ended sid=([0-9a-f-]+) reason=(\S+)"
)
with open(os.path.expanduser("~/.claude/logs/sessions.log"), errors="ignore") as fh:
    for line in fh:
        m = rx.match(line)
        if m and line.startswith("[2026-10"):
            t = (
                datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
                .replace(tzinfo=CHI)
                .timestamp()
            )
            ends[m.group(2)].append(t)

epc = collections.Counter()
for f in F:
    if any(S <= x[0] <= E for x in f["reqs"]):
        epc[max(f["eps"], key=f["eps"].get) if f["eps"] else ""] += 1
print("files with in-window requests by dominant entrypoint", dict(epc))
nots = collections.Counter()
for f in F:
    for k, v in f["nots"].items():
        nots[k] += v
print("untimestamped records by type", dict(nots))

out = open(os.path.join(D, "rgaps.tsv"), "w")
cols = "acct sid fi st stop end dur term exit ctx cw1 cr1 ctx1 rebuild saved kill_t kill_lab away_t n_away busy watch later req_in_win".split()
out.write("\t".join(cols) + "\n")
nsess = nreq = 0
for k, f in enumerate(F):
    if not f["eps"].get("cli"):
        continue
    L = [x for x in f["reqs"] if owner[x[7]] == k]
    if not L:
        continue
    L.sort()
    inwin = [x for x in L if S <= x[0] <= E]
    if not inwin:
        continue
    nsess += 1
    nreq += len(inwin)
    O = sorted(f["opens"])
    Ot = [o[0] for o in O]
    OT = sorted(f["other"])
    Tt = [o[0] for o in OT]
    allw = sorted(Ot + Tt)  # every timestamped non-request write
    stops = [o[0] for o in OT if o[1] in ("sys:turn_duration", "sys:stop_hook_summary")]
    away = [o[0] for o in OT if o[1] == "sys:away_summary"]
    notes = {}
    for t, tu in f["notes"]:
        if tu not in notes or t < notes[tu]:
            notes[tu] = t
    J = []
    for tu, (js, kind, tmo) in f["jobs"].items():
        je = notes.get(tu)
        if kind == "agent_fg":
            continue
        J.append((js, je, kind))
    last_ts = L[-1][9]
    n = len(L)
    later = [0] * n
    c = 0
    for i in range(n - 1, -1, -1):
        later[i] = c
        c += 1
        ci = L[i][3] + L[i][6] + L[i][2]
        if i > 0 and ci < 0.6 * (L[i - 1][3] + L[i - 1][6] + L[i - 1][2]):
            c = 0
    sid = f["fsid"]
    ex = sorted(ends.get(sid, []))

    def emit(i, end, term):
        p = L[i]
        st = p[0]
        if st < S or st > E:
            return
        ctx = p[2] + p[3] + p[6]
        j = bisect.bisect_left(stops, p[9])
        stop = (
            stops[j]
            if j < len(stops) and stops[j] < end and stops[j] < p[9] + 600
            else p[9] + 2
        )
        j = bisect.bisect_right(allw, stop + 20)
        kt = (
            allw[j]
            if j < len(allw) and allw[j] <= stop + 3300 and allw[j] < end
            else None
        )
        kl = ""
        if kt is not None:
            jj = bisect.bisect_left(Tt, kt)
            kl = OT[jj][1] if jj < len(Tt) and Tt[jj] == kt else "opener"
        a0 = bisect.bisect_right(away, stop)
        aw = [t for t in away[a0:] if t < end]
        exits = [t for t in ex if st < t < end]
        if not term:
            r = L[i + 1]
            cw1, cr1 = r[3], r[6]
            ctx1 = r[2] + r[3] + r[6]
            reb = int(ctx > 0 and ctx1 >= 0.6 * ctx and cw1 >= 0.5 * ctx)
            saved = max(0, min(ctx, cw1 - max(0, ctx1 - ctx))) if reb else 0
            lt = later[i + 1] + 1
        else:
            cw1 = cr1 = ctx1 = -1
            reb = saved = lt = 0
        wt = stop + 3300
        busy = int(
            any(
                kd in ("bash", "agent", "workflow")
                and js <= wt < (je if je else last_ts)
                for js, je, kd in J
            )
        )
        watch = int(
            any(
                kd == "watch" and js <= wt < (je if je else last_ts) for js, je, kd in J
            )
        )
        out.write(
            "\t".join(
                str(v)
                for v in [
                    f["acct"],
                    sid,
                    k,
                    "%.1f" % st,
                    "%.1f" % stop,
                    "%.1f" % end,
                    "%.1f" % (end - st),
                    int(term),
                    "%.0f" % exits[0] if exits else "",
                    ctx,
                    cw1,
                    cr1,
                    ctx1,
                    reb,
                    saved,
                    "%.1f" % kt if kt else "",
                    kl,
                    "%.1f" % aw[0] if aw else "",
                    len(aw),
                    busy,
                    watch,
                    lt,
                    int(S <= st <= E),
                ]
            )
            + "\n"
        )

    for i in range(n - 1):
        a, b = L[i][9], L[i + 1][0]
        j = bisect.bisect_right(Ot, a)
        if j < len(Ot) and Ot[j] <= b:
            emit(i, Ot[j], False)
    e2 = [t for t in ex if t >= last_ts - 5]
    emit(n - 1, e2[0] if e2 else E, True)
out.close()
print("interactive sessions", nsess, "in-window requests", nreq)
