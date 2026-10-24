#!/usr/bin/env python3
# Independent reviewer scan (numbers lens). Full json.loads of every main-session transcript line.
# Emits one JSON object per transcript file: requests, turn openers, every other timestamped record,
# background jobs (start/end) and untimestamped-record counts.
# usage: python3 -I rscan.py <acct> <projects_dir> <start_epoch> <end_epoch> <out.jsonl>
import json
import os
import re
import sys
import time
from datetime import datetime

acct, root, S, E, outp = sys.argv[1:6]
S, E = float(S), float(E)
LO = S - 3 * 86400
TUID = re.compile(r"<tool-use-id>([^<]+)</tool-use-id>")


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def content_text(c):
    """-> (is_tool_result, text)"""
    if isinstance(c, str):
        return False, c
    if isinstance(c, list):
        out = []
        for b in c:
            if isinstance(b, dict):
                if b.get("type") == "tool_result":
                    return True, ""
                if b.get("type") == "text":
                    out.append(b.get("text") or "")
        return False, " ".join(out)
    return False, ""


paths = []
for d in os.listdir(root):
    pd = os.path.join(root, d)
    if not os.path.isdir(pd):
        continue
    for f in os.listdir(pd):
        if f.endswith(".jsonl"):
            p = os.path.join(pd, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            if st.st_mtime >= S:
                paths.append((p, st.st_mtime, st.st_size))
t0 = time.time()
nb = 0
fo = open(outp, "w")
for p, mt, sz in paths:
    reqs = {}
    opens = []
    other = []
    jobs = {}
    notes = []
    eps = {}
    nots = {}
    sids = {}
    with open(p, "rb") as fh:
        for raw in fh:
            nb += len(raw)
            try:
                r = json.loads(raw)
            except Exception:
                nots["badjson"] = nots.get("badjson", 0) + 1
                continue
            if not isinstance(r, dict):
                continue
            ts = r.get("timestamp")
            t = ep(ts) if isinstance(ts, str) else None
            typ = r.get("type") or "?"
            if t is None:
                nots[typ] = nots.get(typ, 0) + 1
                continue
            if r.get("isSidechain"):
                continue
            if r.get("entrypoint"):
                eps[r["entrypoint"]] = eps.get(r["entrypoint"], 0) + 1
            if r.get("sessionId"):
                sids[r["sessionId"]] = sids.get(r["sessionId"], 0) + 1
            msg = r.get("message") if isinstance(r.get("message"), dict) else {}
            # notifications can appear in user records or queue-operation content
            sraw = None
            if typ in ("user", "queue-operation"):
                sraw = raw.decode("utf-8", "ignore")
                if "<task-notification>" in sraw:
                    for tu in TUID.findall(sraw):
                        notes.append((t, tu))
            if typ == "assistant":
                u = msg.get("usage")
                if isinstance(u, dict) and msg.get("model") != "<synthetic>":
                    for b in msg.get("content") or []:
                        if isinstance(b, dict) and b.get("type") == "tool_use":
                            nm = b.get("name")
                            bi = b.get("input") or {}
                            if not isinstance(bi, dict):
                                bi = {}
                            cmd = str(bi.get("command", ""))
                            bg = bool(bi.get("run_in_background"))
                            if nm == "Bash" and bg:
                                kind = "watch" if "cc-await-ping" in cmd else "bash"
                            elif nm == "Monitor":
                                kind = "watch"
                            elif nm in ("Agent", "Task") and bg:
                                kind = "agent"
                            elif nm == "Workflow":
                                kind = "workflow"
                            elif nm in ("Agent", "Task"):
                                kind = "agent_fg"
                            else:
                                kind = None
                            if kind and b.get("id") and b["id"] not in jobs:
                                tm = re.search(r"--timeout[ =](\d+)", cmd)
                                jobs[b["id"]] = [
                                    t,
                                    kind,
                                    int(tm.group(1)) if tm else None,
                                ]
                    rid = r.get("requestId") or msg.get("id") or r.get("uuid")
                    o = u.get("output_tokens") or 0
                    if rid in reqs:
                        x = reqs[rid]
                        x[8] = max(x[8], o)
                        x[9] = t  # last record time of this request
                    else:
                        cc = u.get("cache_creation") or {}
                        reqs[rid] = [
                            t,
                            msg.get("model", ""),
                            u.get("input_tokens") or 0,
                            u.get("cache_creation_input_tokens") or 0,
                            cc.get("ephemeral_5m_input_tokens") or 0,
                            cc.get("ephemeral_1h_input_tokens") or 0,
                            u.get("cache_read_input_tokens") or 0,
                            rid,
                            o,
                            t,
                        ]
                    continue
                other.append((t, "assistant_nousage"))
                continue
            if typ == "user":
                tr, txt = content_text(msg.get("content"))
                if tr:
                    other.append((t, "tool_result"))
                    continue
                if r.get("isMeta"):
                    other.append((t, "user_meta"))
                    continue
                opens.append((t, txt[:700]))
                continue
            if typ == "system":
                lab = "sys:" + str(r.get("subtype") or "?")
            elif typ == "attachment":
                a = r.get("attachment") if isinstance(r.get("attachment"), dict) else {}
                lab = "att:" + str(a.get("type") or "?")
            else:
                lab = "top:" + typ
            other.append((t, lab))
    sid = max(sids, key=sids.get) if sids else os.path.basename(p)[:-6]
    R = sorted(reqs.values())
    rec = dict(
        acct=acct,
        path=p,
        fsid=os.path.basename(p)[:-6],
        sid=sid,
        mt=mt,
        sz=sz,
        eps=eps,
        nots=nots,
        reqs=[x for x in R if LO <= x[0] <= E + 3600],
        opens=[x for x in opens if LO <= x[0] <= E + 3600],
        other=[x for x in other if LO <= x[0] <= E + 3600],
        jobs=jobs,
        notes=notes,
    )
    fo.write(json.dumps(rec, separators=(",", ":")) + "\n")
fo.close()
sys.stderr.write(
    "RDONE %s files=%d GB=%.2f secs=%.0f\n"
    % (acct, len(paths), nb / 1e9, time.time() - t0)
)
