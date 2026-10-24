#!/usr/bin/env python3
# Measure what one idle WAKE TURN costs in a main session: requests in the turn, cache read, cache write,
# output, and the context size. Wakes = harness task-notifications that arrive while the session is idle
# (previous request ended its turn): cc-await-ping watcher exits (timeout = "exit code 2" / mail),
# Goal check-ins, asyncRewake peer-mail wakes, and other background-task completions (for contrast).
# Window: main transcripts (not /subagents/) on all 4 accounts, requests 2026-10-17T00:00Z .. 2026-10-24T03:00Z.
# Usage tokens: first record per message.id for input-side fields, max over records for output.
import os, sys, json, re, glob, collections
from datetime import datetime

T = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
W0, W1 = T("2026-10-17T00:00:00Z"), T("2026-10-24T03:00:00Z")
ROOTS = {
    "next": "/Users/chrisren/.claude/projects",
    "next2": "/Users/chrisren/.claude-secondary/projects",
    "next3": "/Users/chrisren/.claude-tertiary/projects",
    "next4": "/Users/chrisren/.claude-quaternary/projects",
}
RE_TN = re.compile(r"<task-notification>(.*?)</task-notification>", re.S)
RE_TU = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")
RE_SU = re.compile(r"<summary>(.*?)</summary>", re.S)
out = open("/tmp/usage-audit/r2/cache-rebuilds/wakes.jsonl", "w")
seen_mid = set()
nfiles = 0
for acct, root in ROOTS.items():
    for p in glob.glob(root + "/*/*.jsonl"):
        try:
            if os.path.getmtime(p) < W0:
                continue
        except OSError:
            continue
        rp = os.path.realpath(p)
        nfiles += 1
        tools = {}
        reqs = {}  # mid -> dict
        order = []  # sequence of ('req', mid) / ('wake', kind, ts) / ('prompt', ts)
        for line in open(rp, errors="replace"):
            if not line.startswith("{"):
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            t = d.get("type")
            if t == "assistant":
                if d.get("isSidechain"):
                    continue
                m = d.get("message") or {}
                mid = m.get("id")
                if not mid:
                    continue
                u = m.get("usage") or {}
                if mid not in reqs:
                    reqs[mid] = dict(
                        ts=T(d["timestamp"]),
                        inp=u.get("input_tokens") or 0,
                        cc=u.get("cache_creation_input_tokens") or 0,
                        cr=u.get("cache_read_input_tokens") or 0,
                        out=u.get("output_tokens") or 0,
                        stop=m.get("stop_reason"),
                        model=m.get("model"),
                    )
                    order.append(("req", mid))
                else:
                    r = reqs[mid]
                    r["out"] = max(r["out"], u.get("output_tokens") or 0)
                    if m.get("stop_reason"):
                        r["stop"] = m.get("stop_reason")
                for c in m.get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        inp = c.get("input") or {}
                        tools[c.get("id")] = (
                            c.get("name"),
                            str(inp.get("command") or "")[:200],
                            bool(inp.get("run_in_background")),
                        )
            elif t in ("user", "attachment"):
                if t == "user":
                    c = (d.get("message") or {}).get("content")
                    s = (
                        c
                        if isinstance(c, str)
                        else " ".join(
                            (x.get("text") or "")
                            for x in c
                            if isinstance(x, dict) and x.get("type") == "text"
                        )
                        if isinstance(c, list)
                        else ""
                    )
                    if isinstance(c, list) and any(
                        isinstance(x, dict) and x.get("type") == "tool_result"
                        for x in c
                    ):
                        continue
                else:
                    a = d.get("attachment") or {}
                    if a.get("type") != "queued_command":
                        continue
                    s = str(a.get("prompt") or "")
                ts = T(d["timestamp"]) if d.get("timestamp") else None
                blks = RE_TN.findall(s)
                if blks:
                    for b in blks:
                        tu = RE_TU.search(b)
                        su = RE_SU.search(b)
                        su = su.group(1) if su else ""
                        kind = "bg_other"
                        if tu:
                            nm, cmd, bg = tools.get(tu.group(1), (None, "", False))
                            if nm == "Bash" and "cc-await-ping" in cmd:
                                kind = (
                                    "watcher_timeout"
                                    if "exit code 2" in su
                                    else "watcher_other"
                                )
                            elif nm == "Workflow":
                                kind = "workflow_done"
                            elif nm in ("Agent", "Task"):
                                kind = "agent_done"
                        elif "Goal check-in" in su:
                            kind = "goal_checkin"
                        elif "peer mail" in su:
                            kind = "rewake_mail"
                        order.append(("wake", kind, ts))
                elif "Peer mail arrived while you were idle" in s:
                    order.append(("wake", "rewake_mail", ts))
                elif (
                    t == "user"
                    and not d.get("isMeta")
                    and not s.startswith("Stop hook feedback")
                ):
                    order.append(("prompt", ts))
        # walk: a wake that follows an end_turn request starts a wake turn
        last_req = None
        i = 0
        while i < len(order):
            o = order[i]
            if o[0] == "req":
                last_req = o[1]
                i += 1
                continue
            if o[0] == "wake" and last_req and reqs[last_req]["stop"] == "end_turn":
                kind = o[1]
                # collect requests until end_turn, stop at a prompt
                j = i + 1
                turn = []
                extra_wakes = 0
                while j < len(order) and len(turn) < 40:
                    if order[j][0] == "req":
                        turn.append(order[j][1])
                        if reqs[order[j][1]]["stop"] == "end_turn":
                            break
                    elif order[j][0] == "prompt":
                        break
                    else:
                        extra_wakes += 1
                    j += 1
                if turn:
                    f = reqs[turn[0]]
                    if W0 <= f["ts"] <= W1 and turn[0] not in seen_mid:
                        seen_mid.add(turn[0])
                        pl = reqs[last_req]
                        out.write(
                            json.dumps(
                                dict(
                                    acct=acct,
                                    file=rp[-80:],
                                    kind=kind,
                                    gap=f["ts"] - pl["ts"],
                                    prev_pp=pl["inp"] + pl["cc"] + pl["cr"],
                                    n=len(turn),
                                    cr=sum(reqs[m]["cr"] for m in turn),
                                    cc=sum(reqs[m]["cc"] for m in turn),
                                    cc_first=f["cc"],
                                    cr_first=f["cr"],
                                    inp=sum(reqs[m]["inp"] for m in turn),
                                    out=sum(reqs[m]["out"] for m in turn),
                                    dur=reqs[turn[-1]]["ts"] - f["ts"],
                                    extra_wakes=extra_wakes,
                                    model=f["model"],
                                )
                            )
                            + "\n"
                        )
                i = j if turn else i + 1
                continue
            i += 1
out.close()
print("files", nfiles, file=sys.stderr)
