#!/usr/bin/env python3
# Independent reviewer scan (does not read the researcher's TSVs or gaps.jsonl).
# Usage: python3 -I scan.py <acct> <projects root> <out.jsonl>
# For every transcript (no symlinks, realpath-deduped, mtime >= cut) build the request timeline
# (message.id keyed, first-record usage), and for every candidate gap (main > 2700 s, sub > 270 s,
# or any bust) emit the gap with an independent state classification:
#   A  : a tool_use of the pre-gap request got its tool_result in the second half of the gap
#   bg : background tasks launched before gap start, not ended before gap start (task-notification
#        by task-id or tool-use-id, TaskStop result, or a SessionStart:resume/startup in between,
#        which resets the in-process task registry -- reported separately as 'reset')
#   end: the first input record after gap start (task-notification / teammate / prompt / ...)
import json, os, re, sys, time
from datetime import datetime

acct, root, outp = sys.argv[1], sys.argv[2], sys.argv[3]
CUT = "2026-10-17T02:45:00"
END = "2026-10-24T02:50:00"
cut_epoch = datetime.fromisoformat(CUT + "+00:00").timestamp() - 86400
T = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
RE_TID = re.compile(r"<task-id>([^<]+)</task-id>")
RE_TU = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")
RE_ST = re.compile(r"<status>([^<]+)</status>")
RE_BG = re.compile(r"running in background with ID: ?([A-Za-z0-9_-]{5,})")
RE_STOP = re.compile(r"stopped task: ?([A-Za-z0-9_-]+)")

files = []
seen = set()
for dp, dn, fn in os.walk(root):
    for f in fn:
        if not f.endswith(".jsonl"):
            continue
        p = os.path.join(dp, f)
        try:
            if os.path.islink(p):
                continue
            st = os.stat(p)
        except OSError:
            continue
        if st.st_mtime < cut_epoch:
            continue
        rp = os.path.realpath(p)
        if rp in seen:
            continue
        seen.add(rp)
        files.append(p)
sys.stderr.write(f"{acct} files={len(files)}\n")


def notif_blocks(s):
    out = []
    for blk in s.split("<task-notification>")[1:]:
        a = RE_TID.search(blk)
        b = RE_TU.search(blk)
        c = RE_ST.search(blk)
        out.append((a and a.group(1), b and b.group(1), c and c.group(1), blk[:200]))
    return out


def textof(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        r = []
        for x in c:
            if isinstance(x, dict):
                if x.get("type") == "text":
                    r.append(x.get("text") or "")
                elif x.get("type") == "tool_result":
                    cc = x.get("content")
                    r.append(cc if isinstance(cc, str) else json.dumps(cc)[:3000])
        return "\n".join(r)
    return ""


out = open(outp, "w")
nreq = 0
for p in files:
    rel = p.split("/projects/", 1)[1]
    sub = "/subagents/" in p
    reqs = {}  # mid -> dict
    tu = {}  # tool_use id -> dict
    tr = {}  # tool_use id -> (ts, bgid)
    notifs = []  # (ts, tid, tuid, status)
    stops = []  # (ts, tid)
    inputs = []  # (ts, kind, text)
    starts = []  # (ts, hookName)
    try:
        fh = open(p, errors="replace")
    except OSError:
        continue
    with fh:
        for line in fh:
            try:
                d = json.loads(line)
            except Exception:
                continue
            ts = d.get("timestamp")
            if not ts:
                continue
            try:
                tv = T(ts)
            except Exception:
                continue
            ty = d.get("type")
            if ty == "assistant":
                m = d.get("message") or {}
                mid = m.get("id")
                u = m.get("usage")
                if not mid or not isinstance(u, dict):
                    continue
                r = reqs.get(mid)
                if r is None:
                    r = reqs[mid] = dict(
                        mid=mid,
                        t0=tv,
                        ts=ts,
                        t1=tv,
                        inp=u.get("input_tokens") or 0,
                        cc=u.get("cache_creation_input_tokens") or 0,
                        cr=u.get("cache_read_input_tokens") or 0,
                        stop=None,
                        tools=[],
                    )
                r["t1"] = max(r["t1"], tv)
                if m.get("stop_reason"):
                    r["stop"] = m.get("stop_reason")
                for c in m.get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        i = c.get("input") or {}
                        nm = c.get("name")
                        bg = bool(i.get("run_in_background")) or nm in (
                            "Workflow",
                            "Monitor",
                        )
                        tu[c.get("id")] = dict(
                            name=nm,
                            bg=bg,
                            to=i.get("timeout"),
                            t=tv,
                            mid=mid,
                            cmd=str(i.get("command") or i.get("description") or "")[
                                :160
                            ],
                        )
                        r["tools"].append(c.get("id"))
            elif ty == "user":
                m = d.get("message") or {}
                c = m.get("content")
                tur = d.get("toolUseResult")
                had_tr = False
                if isinstance(c, list):
                    for x in c:
                        if isinstance(x, dict) and x.get("type") == "tool_result":
                            had_tr = True
                            tid = x.get("tool_use_id")
                            s = textof([x])
                            bgid = None
                            if isinstance(tur, dict) and tur.get("backgroundTaskId"):
                                bgid = tur.get("backgroundTaskId")
                            else:
                                mm = RE_BG.search(s or "")
                                if mm:
                                    bgid = mm.group(1)
                            tr.setdefault(tid, (tv, bgid))
                            for k in RE_STOP.findall(s or ""):
                                stops.append((tv, k))
                if not had_tr:
                    s = textof(c)
                    if "<task-notification>" in s:
                        for b in notif_blocks(s):
                            notifs.append((tv,) + b)
                        inputs.append((tv, "notif", s[:300]))
                    elif d.get("isMeta"):
                        pass
                    else:
                        k = "prompt"
                        if "<teammate-message" in s:
                            k = "teammate"
                        elif "Peer mail" in s or "peer mail" in s:
                            k = "mail"
                        elif s.startswith("Stop hook feedback"):
                            k = "stophook"
                        inputs.append((tv, k, s[:300]))
            elif ty == "attachment":
                a = d.get("attachment") or {}
                at = a.get("type")
                hn = str(a.get("hookName") or "")
                if hn.startswith("SessionStart"):
                    starts.append((tv, hn))
                if at == "queued_command":
                    s = str(a.get("prompt") or "")
                    if "<task-notification>" in s:
                        for b in notif_blocks(s):
                            notifs.append((tv,) + b)
                        inputs.append((tv, "notif", s[:300]))
                    else:
                        k = (
                            "teammate"
                            if "<teammate-message" in s
                            else ("mail" if "eer mail" in s else "queued_prompt")
                        )
                        inputs.append((tv, k, s[:300]))
    R = sorted(
        (r for r in reqs.values() if CUT <= r["ts"][:19] <= END), key=lambda r: r["t0"]
    )
    nreq += len(R)
    # map bg task id -> tool use id
    bgmap = {}
    for k, v in tr.items():
        if v[1] and k in tu and tu[k]["bg"]:
            bgmap[v[1]] = k
    for i in range(1, len(R)):
        a, b = R[i - 1], R[i]
        pp = a["inp"] + a["cc"] + a["cr"]
        gap = b["t0"] - a["t0"]
        bust = pp >= 20000 and b["cr"] < 0.5 * pp and b["cc"] >= 0.5 * pp
        if not (bust or (not sub and gap > 2700) or (sub and gap > 270)):
            continue
        gs = a["t1"]
        ge = b["t0"]
        # A: tool of pre-gap request returned late
        late = []
        for t in a["tools"]:
            x = tr.get(t)
            if x and x[0] > gs + 0.5 * (ge - gs) and not tu[t]["bg"]:
                late.append(
                    (
                        tu[t]["name"],
                        tu[t]["to"],
                        round(x[0] - tu[t]["t"]),
                        tu[t]["cmd"][:100],
                    )
                )
        # fg bash runtime for subagent analysis: any non-bg Bash in pre-gap request
        fgb = []
        for t in a["tools"]:
            x = tr.get(t)
            if t in tu and tu[t]["name"] == "Bash" and not tu[t]["bg"] and x:
                fgb.append(
                    (tu[t]["to"], round(x[0] - tu[t]["t"], 1), tu[t]["cmd"][:100])
                )
        # live bg at gs
        done_t = set(n[1] for n in notifs if n[0] <= gs and n[1]) | set(
            s[1] for s in stops if s[0] <= gs
        )
        done_u = set(n[2] for n in notifs if n[0] <= gs and n[2])
        live = []
        for k, v in tu.items():
            if not v["bg"] or v["t"] > gs:
                continue
            x = tr.get(k)
            if x is None or x[0] > gs:
                continue  # never launched (or result after gs)
            bgid = x[1]
            if v["name"] == "Bash" and not bgid:
                continue  # launch failed / not a bg id
            if (bgid and bgid in done_t) or k in done_u:
                continue
            reset = any(v["t"] < s0 <= gs for s0, hn in starts)
            age = gs - v["t"]
            wk = (
                "watcher"
                if ("cc-await-ping" in v["cmd"] and "--stand-down" not in v["cmd"])
                else v["name"]
            )
            live.append(
                dict(
                    kind=wk,
                    age=round(age),
                    reset=reset,
                    cmd=v["cmd"][:100],
                    ended_in_gap=any(
                        gs < n[0] <= ge + 5 and ((bgid and n[1] == bgid) or n[2] == k)
                        for n in notifs
                    ),
                )
            )
        ins = [x for x in inputs if gs < x[0] <= ge + 5]
        end = ins[-1][1] if ins else ("late_tool" if late else "none")
        endtxt = ins[-1][2][:160] if ins else ""
        out.write(
            json.dumps(
                dict(
                    acct=acct,
                    rel=rel,
                    sub=sub,
                    mid=b["mid"],
                    prev=a["mid"],
                    ts=b["ts"],
                    gap=round(gap, 1),
                    gs_gap=round(ge - gs, 1),
                    bust=bust,
                    cc=b["cc"],
                    cr=b["cr"],
                    pp=pp,
                    nreq=len(R),
                    late=late,
                    fgb=fgb,
                    live=live,
                    end=end,
                    endtxt=endtxt,
                    prev_stop=a["stop"],
                )
            )
            + "\n"
        )
out.close()
sys.stderr.write(f"{acct} DONE reqs={nreq}\n")
