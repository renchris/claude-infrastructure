#!/usr/bin/env python3
"""Independent reviewer scan (numbers lens) of subagent foreground Bash calls.
Usage: python3 -I myscan.py <filelist> <out.jsonl> <start_iso> <end_iso> <workers>
Per Bash tool_use whose issuing request is in the window, emit one row per COPY (dedupe later):
 id, file, acct, mid (issuing message id), t_issue (first record ts of the issuing message),
 t_issue_last, t_res, to, bg, cmd (full if fg & to>270000 else 200 chars), ctx (inp+cc+cr of issuing),
 n_bash_same_req, n_tools_same_req, next: mid, t, cc, cc5, cc1, cr, inp; model; res flags.
"""

import json, os, re, sys
from datetime import datetime
from multiprocessing import Pool

FL, OUT, S0, S1, NW = (
    sys.argv[1],
    sys.argv[2],
    sys.argv[3],
    sys.argv[4],
    int(sys.argv[5]),
)


def ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


T0, T1 = ts(S0), ts(S1)


def acct(p):
    m = re.search(r"/\.claude-([a-z]+)/projects/", p)
    return m.group(1) if m else "?"


def one(p):
    msgs = {}  # mid -> dict
    order = []
    res = {}
    try:
        f = open(p, errors="replace")
    except OSError:
        return []
    with f:
        for ln in f:
            if '"timestamp"' not in ln:
                continue
            try:
                d = json.loads(ln)
            except Exception:
                continue
            if not isinstance(d, dict):
                continue
            t = ts(d.get("timestamp") or "")
            if t is None:
                continue
            m = d.get("message")
            if not isinstance(m, dict):
                continue
            if d.get("type") == "assistant":
                mid = m.get("id")
                if not mid:
                    continue
                u = m.get("usage") or {}
                x = msgs.get(mid)
                if x is None:
                    x = dict(
                        mid=mid,
                        t=t,
                        tl=t,
                        inp=0,
                        cc=0,
                        cr=0,
                        cc5=0,
                        cc1=0,
                        model=m.get("model"),
                        tools=[],
                    )
                    msgs[mid] = x
                    order.append(x)
                x["tl"] = max(x["tl"], t)
                x["inp"] = max(x["inp"], int(u.get("input_tokens") or 0))
                x["cc"] = max(x["cc"], int(u.get("cache_creation_input_tokens") or 0))
                x["cr"] = max(x["cr"], int(u.get("cache_read_input_tokens") or 0))
                cb = u.get("cache_creation") or {}
                if isinstance(cb, dict):
                    x["cc5"] = max(
                        x["cc5"], int(cb.get("ephemeral_5m_input_tokens") or 0)
                    )
                    x["cc1"] = max(
                        x["cc1"], int(cb.get("ephemeral_1h_input_tokens") or 0)
                    )
                for c in m.get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        x["tools"].append(
                            (c.get("id"), c.get("name"), c.get("input") or {})
                        )
            elif d.get("type") == "user":
                c = m.get("content")
                if isinstance(c, list):
                    for y in c:
                        if isinstance(y, dict) and y.get("type") == "tool_result":
                            tid = y.get("tool_use_id")
                            if tid in res:
                                continue
                            tur = (
                                d.get("toolUseResult")
                                if isinstance(d.get("toolUseResult"), dict)
                                else {}
                            )
                            s = y.get("content")
                            if isinstance(s, list):
                                s = " ".join(
                                    z.get("text", "") for z in s if isinstance(z, dict)
                                )
                            s = s if isinstance(s, str) else ""
                            res[tid] = dict(
                                t=t,
                                err=bool(y.get("is_error")),
                                bgid=tur.get("backgroundTaskId"),
                                intr=bool(tur.get("interrupted")),
                                head=s[:160],
                            )
    out = []
    a = acct(p)
    for i, x in enumerate(order):
        if not (T0 <= x["t"] <= T1):
            continue
        bash = [tt for tt in x["tools"] if tt[1] == "Bash"]
        if not bash:
            continue
        nx = order[i + 1] if i + 1 < len(order) else None
        for tid, _, inp in bash:
            to = inp.get("timeout")
            bg = inp.get("run_in_background") in (True, "true", "True")
            cmd = str(inp.get("command") or "")
            big = (not bg) and isinstance(to, (int, float)) and to > 270000
            r = res.get(tid)
            row = dict(
                id=tid,
                file=p,
                acct=a,
                mid=x["mid"],
                t=x["t"],
                tl=x["tl"],
                to=to,
                bg=bg,
                cmd=cmd if big else cmd[:200],
                ctx=x["inp"] + x["cc"] + x["cr"],
                nb=len(bash),
                nt=len(x["tools"]),
                model=x["model"],
                tres=r["t"] if r else None,
                err=r["err"] if r else None,
                bgid=r["bgid"] if r else None,
                intr=r["intr"] if r else None,
                rhead=r["head"] if (r and big) else None,
                nfile=len(order),
                idx=i,
            )
            if nx:
                row.update(
                    nmid=nx["mid"],
                    nt0=nx["t"],
                    ncc=nx["cc"],
                    ncc5=nx["cc5"],
                    ncc1=nx["cc1"],
                    ncr=nx["cr"],
                    ninp=nx["inp"],
                )
            out.append(row)
    return out


if __name__ == "__main__":
    files = [l.strip() for l in open(FL) if l.strip()]
    n = 0
    with open(OUT, "w") as fo, Pool(NW) as pool:
        for rows in pool.imap_unordered(one, files, chunksize=16):
            n += 1
            for r in rows:
                fo.write(json.dumps(r) + "\n")
    sys.stderr.write("DONE files=%d\n" % n)
