#!/usr/bin/env python3
# Build the idle-gap table from scan.py output: one row per idle gap in an interactive main session
# (Stop -> next turn opener), plus one terminal row per session (last Stop -> SessionEnd / window end).
# usage: python3 -I gaps.py <dir>   -> writes <dir>/gaps.tsv, <dir>/wturns.tsv, <dir>/sess.tsv
import bisect
import collections
import csv
import os
import re
import sys
from datetime import datetime
from zoneinfo import ZoneInfo

D = sys.argv[1]
ACCTS = ["next", "next2", "next3", "next4"]
S, E = (float(x) for x in open(os.path.join(D, "window")).read().split())
CHI = ZoneInfo("America/Chicago")

files = {}
for a in ACCTS:
    for line in open(os.path.join(D, a + ".files")):
        fi, mt, sz, sid, closed, ep, goal_n, path = line.rstrip("\n").split("\t", 7)
        files[(a, int(fi))] = dict(
            mt=float(mt),
            sid=sid,
            closed=int(closed),
            ep=ep,
            goal=int(goal_n),
            path=path,
        )

# requests: dedupe by request id, charge to the account whose copy stopped growing first (w4/sim.py)
occ = collections.defaultdict(list)
for a in ACCTS:
    with open(os.path.join(D, a + ".req")) as f:
        for x in csv.reader(f, delimiter="\t"):
            occ[x[4]].append((files[(a, int(x[1]))]["mt"], a, x))
sess = collections.defaultdict(list)
sess_files = collections.defaultdict(set)
for req, v in occ.items():
    v.sort(key=lambda e: e[0])
    mt, a, x = v[0]
    rec = dict(
        ts=float(x[3]),
        acct=a,
        model=x[5],
        inp=int(x[6]),
        cw=int(x[7]),
        cr=int(x[10]),
        out=max(int(e[2][11]) for e in v),
    )
    rec["ctx"] = rec["inp"] + rec["cw"] + rec["cr"]
    sid = files[(a, int(x[1]))]["sid"]
    sess[sid].append(rec)
    for e in v:
        sess_files[sid].add((e[1], int(e[2][1])))
for k in sess:
    sess[k].sort(key=lambda r: r["ts"])

fid2sid = {k: v["sid"] for k, v in files.items()}
ops = collections.defaultdict(set)
for a in ACCTS:
    for line in open(os.path.join(D, a + ".op")):
        fi, ts, kind, meta, extra, txt = (line.rstrip("\n").split("\t", 5) + [""])[:6]
        if meta == "1":
            continue
        ops[fid2sid[(a, int(fi))]].add((float(ts), kind, extra))
evs = collections.defaultdict(set)
for a in ACCTS:
    for line in open(os.path.join(D, a + ".ev")):
        fi, ts, lab, blk = line.rstrip("\n").split("\t")
        evs[fid2sid[(a, int(fi))]].add((float(ts), lab, blk))
jobs = collections.defaultdict(dict)
for a in ACCTS:
    for line in open(os.path.join(D, a + ".jobs")):
        fi, sid, tu, nm, w, js, je = line.rstrip("\n").split("\t")
        if not js:
            continue
        jobs[sid][tu] = (nm, int(w), float(js), float(je) if je else None)

# SessionEnd times from ~/.claude/logs/sessions.log (local time)
ends = collections.defaultdict(list)
rx = re.compile(
    r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\] Session ended sid=([0-9a-f-]+) reason=(\S+)"
)
with open(os.path.expanduser("~/.claude/logs/sessions.log"), errors="ignore") as fh:
    for line in fh:
        if not line.startswith("[2026-10"):
            continue
        m = rx.match(line)
        if m:
            t = (
                datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")
                .replace(tzinfo=CHI)
                .timestamp()
            )
            ends[m.group(2)].append((t, m.group(3)))
for k in ends:
    ends[k].sort()


def interactive(sid):
    eps = [files[f]["ep"] for f in sess_files[sid]]
    return any(e == "cli" for e in eps)


out = open(os.path.join(D, "gaps.tsv"), "w")
cols = [
    "acct",
    "sid",
    "goal",
    "start",
    "end",
    "dur",
    "end_kind",
    "terminal",
    "exit_in_gap",
    "exit_t",
    "ctx",
    "out_prev",
    "cw1",
    "cr1",
    "ctx1",
    "inp1",
    "rebuild",
    "saved_tok",
    "first_ev_t",
    "first_ev_lab",
    "away_t",
    "busy_at_wake",
    "watcher_at_wake",
    "busy_at_15",
    "later_reqs",
    "closed",
    "model",
    "prev_kind",
]
out.write("\t".join(cols) + "\n")
wt = open(os.path.join(D, "wturns.tsv"), "w")
wcols = [
    "acct",
    "sid",
    "kind",
    "extra",
    "gap_before",
    "ctx0",
    "nreq",
    "cw",
    "cr",
    "cr_first",
    "out",
    "inp",
    "growth",
    "dur_s",
    "blocks",
    "away_after",
    "next_gap",
]
wt.write("\t".join(wcols) + "\n")
ss = open(os.path.join(D, "sess.tsv"), "w")
ss.write("sid\tacct\tinteractive\tgoal\tnreq\tfirst\tlast\tend_t\tend_reason\n")

for sid, L in sess.items():
    inter = interactive(sid)
    goal = int(any(files[f]["goal"] for f in sess_files[sid]))
    O = sorted(ops.get(sid, ()))
    Ot = [o[0] for o in O]
    EVL = sorted(evs.get(sid, ()))
    Et = [e[0] for e in EVL]
    J = list(jobs.get(sid, {}).values())
    last_ts = L[-1]["ts"]
    sess_end = next(
        ((t, r) for t, r in ends.get(sid, ()) if t >= last_ts - 5), (None, "")
    )
    ss.write(
        "%s\t%s\t%d\t%d\t%d\t%.0f\t%.0f\t%s\t%s\n"
        % (
            sid,
            L[-1]["acct"],
            inter,
            goal,
            len(L),
            L[0]["ts"],
            last_ts,
            "%.0f" % sess_end[0] if sess_end[0] else "",
            sess_end[1],
        )
    )
    if not inter:
        continue

    def busy(t):
        for nm, w, js, je in J:
            if w:
                continue
            if js <= t < (je if je is not None else last_ts):
                return True
        return False

    def watcher(t):
        for nm, w, js, je in J:
            if w and js <= t < (je if je is not None else last_ts):
                return True
        return False

    # compaction marks: request whose ctx < 60% of the previous one
    n = len(L)
    # number of later requests until the next compaction (for context-growth pricing)
    later = [0] * n
    cnt = 0
    for i in range(n - 1, -1, -1):
        later[i] = cnt
        cnt += 1
        if i > 0 and L[i]["ctx"] < 0.6 * L[i - 1]["ctx"]:
            cnt = 0

    def first_event(t0, t1):
        j = bisect.bisect_right(Et, t0)
        if j < len(Et) and Et[j] < t1:
            return EVL[j]
        return None

    def away(t0, t1):
        j = bisect.bisect_right(Et, t0)
        while j < len(Et) and Et[j] < t1:
            if EVL[j][1] == "sys:away_summary":
                return Et[j]
            j += 1
        return None

    def gaprow(i_prev, i_next, end_t, end_kind, terminal, prev_kind=""):
        p = L[i_prev]
        st = p["ts"]
        dur = end_t - st
        if st < S or dur < 0:
            return
        ex = [t for t, r in ends.get(sid, ()) if st < t < end_t]
        exit_t = ex[0] if ex else None
        if i_next is not None:
            r = L[i_next]
            cw1, cr1, ctx1, inp1 = r["cw"], r["cr"], r["ctx"], r["inp"]
            compaction = ctx1 < 0.6 * p["ctx"]
            rebuild = int((not compaction) and cw1 >= 0.5 * p["ctx"] and p["ctx"] > 0)
            grow = max(0, ctx1 - p["ctx"])
            saved = max(0, min(p["ctx"], cw1 - grow)) if rebuild else 0
            acct = r["acct"]
        else:
            cw1 = cr1 = ctx1 = inp1 = -1
            rebuild, saved, acct = 0, 0, p["acct"]
        fe = first_event(st + 20, min(end_t, st + 3300))
        aw = away(st, end_t)
        out.write(
            "\t".join(
                str(x)
                for x in [
                    acct,
                    sid,
                    goal,
                    "%.0f" % st,
                    "%.0f" % end_t,
                    "%.0f" % dur,
                    end_kind,
                    int(terminal),
                    int(exit_t is not None),
                    "%.0f" % exit_t if exit_t else "",
                    p["ctx"],
                    p["out"],
                    cw1,
                    cr1,
                    ctx1,
                    inp1,
                    rebuild,
                    saved,
                    "%.0f" % fe[0] if fe else "",
                    fe[1] if fe else "",
                    "%.0f" % aw if aw else "",
                    int(busy(st + 3300)),
                    int(watcher(st + 3300)),
                    int(busy(st + 900)),
                    later[i_next] + 1 if i_next is not None else 0,
                    int(any(files[f]["closed"] for f in sess_files[sid])),
                    p["model"],
                    prev_kind,
                ]
            )
            + "\n"
        )

    prev_open = ""
    for i in range(1, n):
        a, b = L[i - 1]["ts"], L[i]["ts"]
        j = bisect.bisect_right(Ot, a)
        if j < len(Ot) and Ot[j] <= b:
            o = O[j]
            gaprow(i - 1, i, o[0], o[1], False, prev_open)
            prev_open = o[1] + "|" + o[2]
            # wake-turn proxy rows: a turn opened by a rewake (goal/mail) or a job notice
            k = i
            while k + 1 < n:
                jj = bisect.bisect_right(Ot, L[k]["ts"])
                if jj < len(Ot) and Ot[jj] <= L[k + 1]["ts"]:
                    break
                k += 1
            turn = L[i : k + 1]
            nxt_gap = (L[k + 1]["ts"] - L[k]["ts"]) if k + 1 < n else -1
            blocks = sum(
                1
                for e in EVL
                if L[i]["ts"] <= e[0] <= L[k]["ts"] + 30
                and e[1] == "att:hook_blocking_error"
            )
            aw_after = (
                away(L[k]["ts"], L[k]["ts"] + 3300)
                if nxt_gap < 0 or nxt_gap > 300
                else None
            )
            ctx_after = (
                L[k + 1]["ctx"] if k + 1 < n else turn[-1]["ctx"] + turn[-1]["out"]
            )
            wt.write(
                "\t".join(
                    str(x)
                    for x in [
                        L[i]["acct"],
                        sid,
                        o[1],
                        o[2],
                        "%.0f" % (o[0] - a),
                        L[i - 1]["ctx"],
                        len(turn),
                        sum(r["cw"] for r in turn),
                        sum(r["cr"] for r in turn),
                        turn[0]["cr"],
                        sum(r["out"] for r in turn),
                        sum(r["inp"] for r in turn),
                        ctx_after - L[i - 1]["ctx"],
                        "%.0f" % (turn[-1]["ts"] - o[0]),
                        blocks,
                        "%.0f" % (aw_after - L[k]["ts"]) if aw_after else "",
                        "%.0f" % nxt_gap,
                    ]
                )
                + "\n"
            )
    # terminal gap: last request -> session end (or window end)
    end_t = sess_end[0] if sess_end[0] else E
    gaprow(
        n - 1, None, max(end_t, last_ts), "exit" if sess_end[0] else "censored", True, prev_open
    )
out.close()
wt.close()
ss.close()
sys.stderr.write(
    "sessions=%d interactive=%d\n" % (len(sess), sum(1 for s in sess if interactive(s)))
)
