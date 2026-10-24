#!/usr/bin/env python3
# Reviewer job-lifetime rescan: background jobs get an end from (a) a task-notification matched by
# tool-use-id OR task-id, (b) a TaskStop/KillShell call naming the task id, and launches whose
# tool_result is an error/denial are dropped. Recomputes busy/watch at stop+3300 for every gap in
# G.json and writes G2.json with busy2/busy2_ub (unknown-end jobs: dead at launch+1h / alive to end).
# usage: python3 -I rjobs.py <dir>
import json
import os
import re
import sys
from datetime import datetime

D = sys.argv[1]
IDRX = re.compile(r"(?:with ID|Task ID|task_id|agentId|agent ID)[:=]?\s*`?\"?([A-Za-z0-9_-]{5,40})")
TID = re.compile(r"<task-id>([^<]+)</task-id>")
TUID = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


G = json.load(open(os.path.join(D, "G.json")))
need = {g["sid"] for g in G}
paths = {}
for a in ["next", "next2", "next3", "next4"]:
    for line in open(os.path.join(D, a + ".jsonl")):
        f = json.loads(line)
        if f["fsid"] in need and f["eps"].get("cli"):
            paths[f["fsid"]] = (f["path"], max((x[9] for x in f["reqs"]), default=0))
JOB = {}
stat = {
    "jobs": 0,
    "denied_or_error": 0,
    "end_by_tuid": 0,
    "end_by_tid": 0,
    "end_by_stop": 0,
    "unknown_end": 0,
}
for sid, (p, last) in paths.items():
    jobs, res, stops, nt_tu, nt_tid = {}, {}, {}, {}, {}
    for raw in open(p, errors="ignore"):
        try:
            r = json.loads(raw)
        except Exception:
            continue
        if not isinstance(r, dict) or r.get("isSidechain"):
            continue
        t = ep(r["timestamp"]) if isinstance(r.get("timestamp"), str) else None
        typ = r.get("type")
        if typ in ("user", "queue-operation") and "<task-notification>" in raw and t:
            for x in TUID.findall(raw):
                nt_tu[x] = min(t, nt_tu.get(x, t))
            for x in TID.findall(raw):
                nt_tid[x] = min(t, nt_tid.get(x, t))
        msg = r.get("message") if isinstance(r.get("message"), dict) else {}
        c = msg.get("content")
        if not isinstance(c, list):
            continue
        for b in c:
            if not isinstance(b, dict):
                continue
            if typ == "assistant" and b.get("type") == "tool_use":
                nm, bi = (
                    b.get("name"),
                    b.get("input") if isinstance(b.get("input"), dict) else {},
                )
                if nm in ("TaskStop", "KillShell", "KillBash"):
                    k = bi.get("task_id") or bi.get("shell_id") or bi.get("id")
                    if k and t:
                        stops[str(k)] = min(t, stops.get(str(k), t))
                    continue
                bg = bool(bi.get("run_in_background"))
                if nm == "Bash" and bg:
                    kd = (
                        "watch"
                        if "cc-await-ping" in str(bi.get("command", ""))
                        else "bash"
                    )
                elif nm == "Monitor":
                    kd = "watch"
                elif nm in ("Agent", "Task") and bg:
                    kd = "agent"
                elif nm == "Workflow":
                    kd = "workflow"
                else:
                    continue
                if b.get("id") and b["id"] not in jobs and t:
                    jobs[b["id"]] = (t, kd)
            elif (
                typ == "user"
                and b.get("type") == "tool_result"
                and b.get("tool_use_id")
            ):
                cc = b.get("content")
                cs = cc if isinstance(cc, str) else json.dumps(cc)
                m = IDRX.search(cs)
                bad = (
                    bool(b.get("is_error"))
                    or "Permission for this action was denied" in cs[:300]
                    or "<tool_use_error>" in cs[:200]
                    or "hook error" in cs[:200]
                )
                res[b["tool_use_id"]] = (m.group(1) if m else None, bad)
    L = []
    for tu, (js, kd) in jobs.items():
        stat["jobs"] += 1
        tid, bad = res.get(tu, (None, False))
        if bad:
            stat["denied_or_error"] += 1
            continue
        ends = []
        if tu in nt_tu:
            ends.append(nt_tu[tu])
            stat["end_by_tuid"] += 1
        if tid and tid in nt_tid:
            ends.append(nt_tid[tid])
            stat["end_by_tid"] += 1
        if tid and tid in stops:
            ends.append(stops[tid])
            stat["end_by_stop"] += 1
        je = min(ends) if ends else None
        if je is None:
            stat["unknown_end"] += 1
        L.append((js, je, kd))
    JOB[sid] = (L, last)
print(stat)
for g in G:
    L, last = JOB.get(g["sid"], ([], 0))
    wt = g["stop"] + 3300
    run = lambda kinds, ub: any(
        kd in kinds
        and js <= wt < (je if je is not None else (last if ub else js + 3600))
        for js, je, kd in L
    )
    g["busy2"] = run(
        ("bash", "agent", "workflow"), False
    )  # unknown-end jobs assumed done 1 h after launch
    g["busy2_ub"] = run(
        ("bash", "agent", "workflow"), True
    )  # unknown-end jobs assumed alive to session end
    g["watch2"] = run(("watch",), False)
json.dump(G, open(os.path.join(D, "G2.json"), "w"))
nt = [g for g in G if not g["term"] and g["stop"] + 3300 < g["end"]]
print(
    "woken nonterminal gaps:",
    len(nt),
    "busy(orig)",
    sum(g["busy"] for g in nt),
    "busy2",
    sum(g["busy2"] for g in nt),
    "busy2_ub",
    sum(g["busy2_ub"] for g in nt),
)
rb = [g for g in nt if g["reb"]]
print(
    "rebuild gaps:",
    len(rb),
    "busy(orig)",
    sum(g["busy"] for g in rb),
    "busy2",
    sum(g["busy2"] for g in rb),
    "busy2_ub",
    sum(g["busy2_ub"] for g in rb),
)
