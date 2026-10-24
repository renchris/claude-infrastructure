#!/usr/bin/env python3
# Reviewer replay of hooks/idle-keepalive.sh in wake mode, built from rscan.py output only.
# usage: python3 -I rsim.py <dir>
import bisect
import collections
import json
import os
import re
import statistics as stt
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

D = sys.argv[1]
S, E = 1791655200.0, 1792864800.0
WK = 7.0 / 14.0
ACCTS = ["next", "next2", "next3", "next4"]
CHI = ZoneInfo("America/Chicago")
W, O = 0.245, 0.404
WAKE, TTL, SETTLE, TURN = 3300.0, 3600.0, 20.0, 30.0
TUID = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")
STAT = re.compile(r"<status>([a-z_]+)</status>")

F = []
for a in ACCTS:
    for line in open(os.path.join(D, a + ".jsonl")):
        F.append(json.loads(line))
occ = collections.defaultdict(list)
for k, f in enumerate(F):
    for x in f["reqs"]:
        occ[x[7]].append(k)
owner = {rid: min(v, key=lambda k: F[k]["mt"]) for rid, v in occ.items()}
ends = collections.defaultdict(list)
rx = re.compile(
    r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\] Session ended sid=([0-9a-f-]+) reason=(\S+)"
)
for line in open(os.path.expanduser("~/.claude/logs/sessions.log"), errors="ignore"):
    m = rx.match(line)
    if m and line.startswith("[2026-10"):
        ends[m.group(2)].append(
            datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
            .replace(tzinfo=CHI)
            .timestamp()
        )
ALIVE = set(open(os.path.join(D, "alive.txt")).read().split())


def ctxof(x):
    return x[2] + x[3] + x[6]


G = []  # gaps
T = []  # wake-turn proxies
for k, f in enumerate(F):
    if not f["eps"].get("cli"):
        continue
    L = sorted(x for x in f["reqs"] if owner[x[7]] == k)
    if not L or not any(S <= x[0] <= E for x in L):
        continue
    sid = f["fsid"]
    O_ = sorted(f["opens"])
    Ot = [o[0] for o in O_]
    OT = sorted(f["other"])
    allw = sorted(Ot + [o[0] for o in OT])
    stops = [o[0] for o in OT if o[1] in ("sys:turn_duration", "sys:stop_hook_summary")]
    away = [o[0] for o in OT if o[1] == "sys:away_summary"]
    notes = {}
    for t, tu in f["notes"]:
        notes[tu] = min(t, notes.get(tu, t))
    jobs = {
        tu: (v[0], notes.get(tu), v[1])
        for tu, v in f["jobs"].items()
        if v[1] != "agent_fg"
    }
    last_t = L[-1][9]
    n = len(L)
    later = [0] * n
    c = 0
    for i in range(n - 1, -1, -1):
        later[i] = c
        c += 1
        if i > 0 and ctxof(L[i]) < 0.6 * ctxof(L[i - 1]):
            c = 0

    def okind(txt):
        if txt.startswith("<task-notification>"):
            if "peer mail" in txt[:90]:
                return "mail"
            if "Goal check-in" in txt[:120]:
                return "goal"
            m = TUID.search(txt)
            if m and m.group(1) in jobs:
                sm = STAT.search(txt)
                return "job:" + jobs[m.group(1)][2] + ":" + (sm.group(1) if sm else "?")
            if "Monitor event" in txt[:120]:
                return "job:watch"
            return "notif"
        if txt.startswith("<command-") or txt.startswith("<local-command"):
            return "cmd"
        if txt.startswith("Stop hook feedback"):
            return "stopfb"
        return "prompt"

    def busy(t, kinds):
        return any(
            kd in kinds and js <= t < (je if je else last_t)
            for js, je, kd in jobs.values()
        )

    def busy_nonote(t):
        return any(
            kd in ("bash", "agent", "workflow") and je is None and js <= t < last_t
            for js, je, kd in jobs.values()
        )

    def stop_after(i, end):
        j = bisect.bisect_left(stops, L[i][9])
        return (
            stops[j]
            if j < len(stops) and stops[j] < end and stops[j] < L[i][9] + 600
            else L[i][9] + 2
        )

    # turns: opener index -> requests in the turn
    open_idx = []
    for i in range(n - 1):
        j = bisect.bisect_right(Ot, L[i][9])
        if j < len(Ot) and Ot[j] <= L[i + 1][0]:
            open_idx.append((i, j))
    prev_kind = {}
    real = [(i, j, okind(O_[j][1])) for i, j in open_idx]
    real = [
        x for x in real if x[2] != "stopfb"
    ]  # Stop-hook feedback continues the same turn
    for q, (i, j, kind) in enumerate(real):
        i2 = real[q + 1][0] if q + 1 < len(real) else n - 1  # last request of this turn
        prev_kind[i2] = kind
        turn = L[i + 1 : i2 + 1]
        gb = O_[j][0] - L[i][0]
        if 60 <= gb < 3500 and turn:
            st2 = stop_after(i2, 1e18)
            nxt_open = Ot[real[q + 1][1]] if q + 1 < len(real) else E
            a0 = bisect.bisect_right(away, st2)
            rec_after = int(a0 < len(away) and away[a0] < min(nxt_open, st2 + 3300))
            idle_after = nxt_open - st2
            T.append(
                dict(
                    acct=f["acct"],
                    kind=kind,
                    ctx0=ctxof(L[i]),
                    nreq=len(turn),
                    cw=sum(x[3] for x in turn),
                    out=sum(x[8] for x in turn),
                    cr=sum(x[6] for x in turn),
                    grow_own=ctxof(turn[-1]) + turn[-1][8] - ctxof(L[i]),
                    grow_next=(ctxof(L[i2 + 1]) - ctxof(L[i])) if i2 + 1 < n else None,
                    idle_after=idle_after,
                    rec_after=rec_after,
                )
            )
    ex = sorted(ends.get(sid, []))

    def gap(i, end, term, end_kind):
        p = L[i]
        st = p[0]
        if not (S <= st <= E):
            return
        stop = stop_after(i, end)
        j = bisect.bisect_right(allw, stop + SETTLE)
        kt = (
            allw[j]
            if j < len(allw) and allw[j] <= stop + WAKE and allw[j] < end
            else None
        )
        a0 = bisect.bisect_right(away, stop)
        rec = away[a0] if a0 < len(away) and away[a0] < end else None
        exits = [t for t in ex if st < t < end]
        ctx = ctxof(p)
        if not term:
            r = L[i + 1]
            ctx1 = ctxof(r)
            reb = int(ctx > 0 and ctx1 >= 0.6 * ctx and r[3] >= 0.5 * ctx)
            saved = max(0, min(ctx, r[3] - max(0, ctx1 - ctx))) if reb else 0
            lt = later[i + 1] + 1
        else:
            reb = saved = lt = 0
        wt = stop + WAKE
        G.append(
            dict(
                acct=f["acct"],
                sid=sid,
                st=st,
                stop=stop,
                end=end,
                dur=end - st,
                term=term,
                end_kind=end_kind,
                exit=exits[0] if exits else None,
                ctx=ctx,
                reb=reb,
                saved=saved,
                kill=kt,
                rec=rec,
                later=lt,
                busy=busy(wt, ("bash", "agent", "workflow")),
                busy_nn=busy_nonote(wt),
                watch=busy(wt, ("watch",)),
                prev=prev_kind.get(i, ""),
                mt=f["mt"],
                alive=sid in ALIVE,
            )
        )

    for i, j in open_idx:
        gap(i, Ot[j], False, "open")
    e2 = [t for t in ex if t >= last_t - 5]
    gap(n - 1, e2[0] if e2 else E, True, "exit" if e2 else "censored")

json.dump(G, open(os.path.join(D, "G.json"), "w"))
json.dump(T, open(os.path.join(D, "T.json"), "w"))
print("gaps", len(G), "turn proxies", len(T))
