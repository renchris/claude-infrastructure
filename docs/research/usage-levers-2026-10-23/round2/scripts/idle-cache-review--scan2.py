#!/usr/bin/env python3
# Every SUBAGENT foreground Bash tool_use in the window: timeout param, runtime (tool_use -> tool_result),
# context of the issuing request. Deduped later by tool_use id. Usage: python3 -I scan2.py <acct> <root> <out>
import json, os, sys
from datetime import datetime

acct, root, outp = sys.argv[1], sys.argv[2], sys.argv[3]
CUT = "2026-10-17T02:45:00"
END = "2026-10-24T02:50:00"
cut_epoch = datetime.fromisoformat(CUT + "+00:00").timestamp() - 86400
T = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
out = open(outp, "w")
seen = set()
n = 0
for dp, dn, fn in os.walk(root):
    if "/subagents" not in dp:
        continue
    for f in fn:
        if not f.endswith(".jsonl"):
            continue
        p = os.path.join(dp, f)
        try:
            if os.path.islink(p) or os.stat(p).st_mtime < cut_epoch:
                continue
        except OSError:
            continue
        rp = os.path.realpath(p)
        if rp in seen:
            continue
        seen.add(rp)
        tu = {}
        res = {}
        req = {}
        try:
            fh = open(p, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"tool_use"' not in line and '"tool_result"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                ts = d.get("timestamp")
                if not ts:
                    continue
                m = d.get("message") or {}
                if d.get("type") == "assistant":
                    u = m.get("usage") or {}
                    mid = m.get("id")
                    if mid and mid not in req:
                        req[mid] = (
                            (u.get("input_tokens") or 0)
                            + (u.get("cache_creation_input_tokens") or 0)
                            + (u.get("cache_read_input_tokens") or 0)
                        )
                    for c in m.get("content") or []:
                        if (
                            isinstance(c, dict)
                            and c.get("type") == "tool_use"
                            and c.get("name") == "Bash"
                        ):
                            i = c.get("input") or {}
                            if i.get("run_in_background"):
                                continue
                            tu[c.get("id")] = (
                                ts,
                                i.get("timeout"),
                                mid,
                                str(i.get("command") or "")[:80],
                            )
                elif d.get("type") == "user":
                    c = m.get("content")
                    if isinstance(c, list):
                        for x in c:
                            if isinstance(x, dict) and x.get("type") == "tool_result":
                                res.setdefault(x.get("tool_use_id"), ts)
        for k, (ts, to, mid, cmd) in tu.items():
            if not (CUT <= ts[:19] <= END):
                continue
            r = res.get(k)
            rt = (T(r) - T(ts)) if r else None
            out.write(
                json.dumps(
                    dict(
                        id=k,
                        acct=acct,
                        rel=p.split("/projects/", 1)[1],
                        ts=ts,
                        to=to,
                        rt=rt,
                        pp=req.get(mid, 0),
                        cmd=cmd,
                    )
                )
                + "\n"
            )
            n += 1
out.close()
sys.stderr.write(f"{acct} DONE n={n}\n")
