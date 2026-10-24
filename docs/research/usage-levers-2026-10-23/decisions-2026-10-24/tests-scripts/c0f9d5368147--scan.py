#!/usr/bin/env python3
# Wake-turn scan (decision c0f9d5368147). Read-only over main-session transcripts.
# usage: python3 -I scan.py <acct> <projects_dir> <start_epoch> <end_epoch> <out.jsonl>
# Emits one JSON object per top-level transcript (projects/*/*.jsonl; subagents excluded):
#   reqs   : [t_first, t_last, rid, model, inp, cc, cc5, cc1, cr, out, tools, ntext, lasttext]
#   opens  : [t, origin_kind, producer, turnOrigin, isMeta, text[:3000]]
#   conts  : [t, text[:300]]          (isMeta user records with no turnOrigin: Stop hook feedback, skill bodies)
#   sys    : [t, label]
#   qc     : [t, commandMode, origin_kind, prompt[:300]]   (queued_command attachments, mid-turn deliveries)
#   jobs   : {tool_use_id: [t, name, cmd[:300], bg]}
import json
import os
import sys
from datetime import datetime

acct, root, S, E, outp = sys.argv[1:6]
S, E = float(S), float(E)
LO, HI = S - 2 * 86400, E + 2 * 3600


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def text_of(c):
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
        return False, "\n".join(out)
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
                paths.append((p, st.st_mtime))
fo = open(outp, "w")
nb = 0
for p, mt in paths:
    reqs, opens, conts, sysr, qc, jobs = {}, [], [], [], [], {}
    eps, sids = {}, {}
    with open(p, "rb") as fh:
        for raw in fh:
            nb += len(raw)
            try:
                r = json.loads(raw)
            except Exception:
                continue
            if not isinstance(r, dict) or r.get("isSidechain"):
                continue
            ts = r.get("timestamp")
            t = ep(ts) if isinstance(ts, str) else None
            if t is None or not (LO <= t <= HI):
                continue
            typ = r.get("type")
            if r.get("entrypoint"):
                eps[r["entrypoint"]] = eps.get(r["entrypoint"], 0) + 1
            if r.get("sessionId"):
                sids[r["sessionId"]] = sids.get(r["sessionId"], 0) + 1
            msg = r.get("message") if isinstance(r.get("message"), dict) else {}
            if typ == "assistant":
                u = msg.get("usage")
                if not isinstance(u, dict) or msg.get("model") == "<synthetic>":
                    continue
                rid = r.get("requestId") or msg.get("id") or r.get("uuid")
                tools, ntext, last = [], 0, ""
                for b in msg.get("content") or []:
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "tool_use":
                        bi = b.get("input") if isinstance(b.get("input"), dict) else {}
                        nm = b.get("name") or "?"
                        cmd = str(
                            bi.get("command")
                            or bi.get("file_path")
                            or bi.get("pattern")
                            or bi.get("description")
                            or bi.get("subagent_type")
                            or ""
                        )[:300]
                        bg = bool(bi.get("run_in_background"))
                        tools.append([nm, cmd, bg])
                        if b.get("id"):
                            jobs.setdefault(b["id"], [t, nm, cmd, bg])
                    elif b.get("type") == "text":
                        tx = b.get("text") or ""
                        ntext += len(tx)
                        last = tx[-400:]
                o = u.get("output_tokens") or 0
                if rid in reqs:
                    x = reqs[rid]
                    x[1] = max(x[1], t)
                    x[9] = max(x[9], o)
                    x[10].extend(tools)
                    x[11] += ntext
                    if last:
                        x[12] = last
                else:
                    cc = u.get("cache_creation") or {}
                    reqs[rid] = [
                        t,
                        t,
                        rid,
                        msg.get("model", ""),
                        u.get("input_tokens") or 0,
                        u.get("cache_creation_input_tokens") or 0,
                        cc.get("ephemeral_5m_input_tokens") or 0,
                        cc.get("ephemeral_1h_input_tokens") or 0,
                        u.get("cache_read_input_tokens") or 0,
                        o,
                        tools,
                        ntext,
                        last,
                    ]
                continue
            if typ == "user":
                tr, txt = text_of(msg.get("content"))
                if tr:
                    continue
                o = r.get("origin") if isinstance(r.get("origin"), dict) else {}
                to = r.get("turnOrigin")
                if isinstance(to, dict):
                    to = to.get("kind") or json.dumps(to)[:40]
                meta = bool(r.get("isMeta"))
                if meta and to is None and not o:
                    conts.append([t, txt[:300]])
                    continue
                opens.append(
                    [t, o.get("kind"), o.get("producer"), to, meta, txt[:3000]]
                )
                continue
            if typ == "system":
                sysr.append([t, "sys:" + str(r.get("subtype") or "?")])
                continue
            if typ == "attachment":
                a = r.get("attachment") if isinstance(r.get("attachment"), dict) else {}
                at = a.get("type")
                if at == "queued_command":
                    oo = a.get("origin") if isinstance(a.get("origin"), dict) else {}
                    pr = a.get("prompt")
                    qc.append([t, a.get("commandMode"), oo.get("kind"), str(pr)[:300]])
                elif at in (
                    "hook_blocking_error",
                    "hook_stopped_continuation",
                    "async_hook_response",
                    "goal_status",
                ):
                    sysr.append([t, "att:" + at])
                continue
            if typ in ("queue-operation",):
                sysr.append([t, "top:queue-operation"])
    sid = max(sids, key=sids.get) if sids else os.path.basename(p)[:-6]
    rec = dict(
        acct=acct,
        path=p,
        fsid=os.path.basename(p)[:-6],
        sid=sid,
        mt=mt,
        eps=eps,
        reqs=sorted(reqs.values(), key=lambda x: x[0]),
        opens=opens,
        conts=conts,
        sys=sysr,
        qc=qc,
        jobs=jobs,
    )
    fo.write(json.dumps(rec, separators=(",", ":")) + "\n")
fo.close()
sys.stderr.write("DONE %s files=%d GB=%.2f\n" % (acct, len(paths), nb / 1e9))
