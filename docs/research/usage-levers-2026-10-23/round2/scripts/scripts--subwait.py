#!/usr/bin/env python3
# SUBAGENT rebuilds (5-minute cache): what preceded each bust, with the MEASURED runtime of the tool call
# (tool_use timestamp -> tool_result timestamp), not only its timeout parameter. Also: in every subagent
# transcript that launched a run_in_background Bash, the request gaps while it waited for that job.
import json, collections, re, os
from datetime import datetime

T = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
G = [json.loads(l) for l in open("/tmp/usage-audit/r2/cache-rebuilds/gaps.jsonl")]
SB = [g for g in G if g["sub"]]
byfile = collections.defaultdict(list)
for g in SB:
    byfile[g["root"] + "/" + g["rel"]].append(g)
POLL = re.compile(
    r"\b(until|while)\b.*\bsleep\b|\bsleep\s+\d{2,}|tail\s+-f|gh run watch|wait\s+\$|--watch"
)
out = open("/tmp/usage-audit/r2/cache-rebuilds/subwait.jsonl", "w")
for path, gaps in byfile.items():
    tools = {}
    tres = {}
    req = {}
    order = []
    for line in open(path, errors="replace"):
        if not line.startswith("{"):
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        t = d.get("type")
        ts = T(d["timestamp"]) if d.get("timestamp") else None
        m = d.get("message") or {}
        if t == "assistant":
            mid = m.get("id")
            if mid and mid not in req:
                req[mid] = dict(ts=ts, tools=[], stop=None)
                order.append(mid)
            if mid and m.get("stop_reason"):
                req[mid]["stop"] = m.get("stop_reason")
            for c in m.get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    inp = c.get("input") or {}
                    tools[c["id"]] = dict(
                        name=c.get("name"),
                        cmd=str(inp.get("command") or "")[:200],
                        bg=bool(inp.get("run_in_background")),
                        to=inp.get("timeout"),
                        ts=ts,
                        block=inp.get("block"),
                        tto=inp.get("timeout"),
                    )
                    if mid:
                        req[mid]["tools"].append(c["id"])
        elif t == "user":
            c = m.get("content")
            if isinstance(c, list):
                for x in c:
                    if isinstance(x, dict) and x.get("type") == "tool_result":
                        tres[x.get("tool_use_id")] = ts
    for g in gaps:
        pr = req.get(g["prev_mid"])
        if not pr:
            continue
        tl = [
            tools[i]
            | dict(
                rt=(tres.get(i) - tools[i]["ts"])
                if tres.get(i) and tools[i]["ts"]
                else None
            )
            for i in pr["tools"]
            if i in tools
        ]
        if not tl:
            kind = "no tool (" + str(pr["stop"]) + ")"
            rt = None
        else:
            x = max(tl, key=lambda x: x["rt"] or 0)
            rt = x["rt"]
            nm = x["name"]
            if nm == "Bash" and not x["bg"]:
                to = x["to"] or 120000
                kind = (
                    "fg Bash "
                    + ("poll " if POLL.search(x["cmd"]) else "")
                    + ("timeout>270s" if to > 270000 else "timeout<=270s")
                )
            elif nm == "Bash":
                kind = "bg Bash launch"
            else:
                kind = nm
        out.write(
            json.dumps(
                dict(
                    rel=g["rel"],
                    gap=g["gap"],
                    bust=g["bust"],
                    cc=g["cc"],
                    pp=g["pp"],
                    kind=kind,
                    rt=rt,
                    cmd=(
                        max(tl, key=lambda x: x["rt"] or 0)["cmd"][:120] if tl else ""
                    ),
                )
            )
            + "\n"
        )
    # background-wait windows: launched bg Bash -> requests until next 30 min or end
    bg = [
        (tools[i]["ts"], i)
        for i in tools
        if tools[i]["name"] == "Bash" and tools[i]["bg"] and tools[i]["ts"]
    ]
out.close()

# ---- part 2: request gaps while a subagent waits on its own background Bash (all subagent files, window) ----
W0 = T("2026-10-17T00:00:00Z")
ROOTS = [
    "/Users/chrisren/.claude/projects",
    "/Users/chrisren/.claude-secondary/projects",
    "/Users/chrisren/.claude-tertiary/projects",
    "/Users/chrisren/.claude-quaternary/projects",
]
import glob

seen = set()
gaps_wait = []  # (gap seconds, bust?, waiting tool kind)
nf = 0
for root in ROOTS:
    for p in glob.glob(root + "/*/*/subagents/*.jsonl") + glob.glob(
        root + "/*/*/subagents/*/*/*.jsonl"
    ):
        try:
            if os.path.getmtime(p) < W0:
                continue
        except OSError:
            continue
        rp = os.path.realpath(p)
        if rp in seen:
            continue
        seen.add(rp)
        # quick filter
        try:
            if os.path.getsize(rp) > 60e6:
                continue
        except OSError:
            continue
        txt = open(rp, errors="replace").read()
        if '"run_in_background":true' not in txt:
            continue
        nf += 1
        reqs = []
        tools = {}
        cur_bg_live = set()
        seenmid = set()
        for line in txt.splitlines():
            if not line.startswith("{"):
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            m = d.get("message") or {}
            if d.get("type") == "assistant" and m.get("id") and m["id"] not in seenmid:
                seenmid.add(m["id"])
                u = m.get("usage") or {}
                reqs.append(
                    dict(
                        ts=T(d["timestamp"]),
                        cc=u.get("cache_creation_input_tokens") or 0,
                        cr=u.get("cache_read_input_tokens") or 0,
                        inp=u.get("input_tokens") or 0,
                        tools=[],
                        bglive=len(cur_bg_live) > 0,
                    )
                )
            if d.get("type") == "assistant":
                for c in m.get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        inp = c.get("input") or {}
                        tools[c["id"]] = (
                            c.get("name"),
                            bool(inp.get("run_in_background")),
                            str(inp.get("command") or "")[:200],
                            inp.get("timeout"),
                        )
                        if reqs:
                            reqs[-1]["tools"].append(c["id"])
            if d.get("type") == "user":
                c = m.get("content")
                if isinstance(c, list):
                    for x in c:
                        if isinstance(x, dict) and x.get("type") == "tool_result":
                            tu = x.get("tool_use_id")
                            if tu in tools and tools[tu][1]:
                                cur_bg_live.add(tu)
                s = json.dumps(c)[:20000] if c else ""
                if "<task-notification>" in s:
                    for tu in re.findall(
                        r"<tool-use-id>([^<]+)</tool-use-id>", s.replace("\\u003c", "<")
                    ):
                        cur_bg_live.discard(tu)
            elif (
                d.get("type") in ("attachment", "queue-operation")
                and "<task-notification>" in line
            ):
                # notifications delivered as queued_command attachments / queue operations
                for tu in re.findall(r"<tool-use-id>([^<\\]+)</tool-use-id>", line):
                    cur_bg_live.discard(tu)
            # a TaskStop or a poll that saw the job finish also ends the wait; TaskStop handled here
            if d.get("type") == "user" and isinstance(m.get("content"), list):
                for x in m["content"]:
                    if (
                        isinstance(x, dict)
                        and x.get("type") == "tool_result"
                        and tools.get(x.get("tool_use_id"), ("",))[0] == "TaskStop"
                    ):
                        cur_bg_live.clear()
        for a, b in zip(reqs, reqs[1:]):
            if not b["bglive"]:
                continue
            pp = a["inp"] + a["cc"] + a["cr"]
            bust = pp >= 20000 and b["cr"] < 0.5 * pp and b["cc"] >= 0.5 * pp
            tk = [tools.get(i, ("?", False, "", None)) for i in a["tools"]]
            k = "none"
            if tk:
                n, bgf, cmd, to = tk[0]
                if n == "Bash" and not bgf:
                    k = "fg Bash " + (
                        "timeout>270s" if (to or 120000) > 270000 else "timeout<=270s"
                    )
                else:
                    k = n
            gaps_wait.append((b["ts"] - a["ts"], bust, k, b["cc"]))
json.dump(
    dict(nfiles=nf, gaps=gaps_wait),
    open("/tmp/usage-audit/r2/cache-rebuilds/subwait_bg.json", "w"),
)
print(
    "subagent files with a bg Bash:", nf, "request pairs while bg live:", len(gaps_wait)
)
