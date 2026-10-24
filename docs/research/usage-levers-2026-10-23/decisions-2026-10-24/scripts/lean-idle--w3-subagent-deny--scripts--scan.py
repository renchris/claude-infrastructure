#!/usr/bin/env python3
"""Replay scan for the W3 subagent long-Bash rule (read-only over transcripts).

For every subagent transcript touched in the window, emits:
  bash.jsonl   every subagent Bash tool_use in the window (fg + bg): timeout, runtime, issuing-request
               context, next request's usage and gap; full command only for fg timeout > 270000.
  bg.jsonl     every background Bash launch: what the subagent did until the task-notification
               (requests, inter-request gaps, rebuilds, poll-like calls).
  gaps.jsonl   every inter-request gap > 240 s in a subagent with its cause and cache write.
  files.jsonl  per-file request counts / totals (for denominators).
Usage: python3 -I scan.py <filelist> <outdir> <start_iso> <end_iso> <workers>
"""

import json
import os
import re
import sys
from datetime import datetime
from multiprocessing import Pool

FL, OUT, START, END, NW = (
    sys.argv[1],
    sys.argv[2],
    sys.argv[3],
    sys.argv[4],
    int(sys.argv[5]),
)


def T(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


T0, T1 = T(START), T(END)
TASK_RX = re.compile(r"<task-id>([^<]+)</task-id>")
STATUS_RX = re.compile(r"<status>([^<]+)</status>")
BGID_RX = re.compile(r"running in background with ID: ([A-Za-z0-9_-]+)")


def acct_of(p):
    m = re.search(r"/\.claude(-[a-z]+)?/projects/", p)
    return (m.group(1) or "").lstrip("-") or "next"


def text_of(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return " ".join(
            x.get("text", "")
            for x in c
            if isinstance(x, dict) and x.get("type") == "text"
        )
    return ""


def scan_file(p):
    reqs = []  # ordered: dict(mid, t0, t1, cc, cr, inp, out, tools=[(id,name,input)])
    rbymid = {}
    results = {}  # tool_use_id -> dict(t, err, head, interrupted, bgid)
    notes = []  # (t, task_id, status)
    try:
        fh = open(p, errors="replace")
    except OSError:
        return None
    with fh:
        for line in fh:
            try:
                d = json.loads(line)
            except Exception:
                continue
            if not isinstance(d, dict):
                continue
            t = T(d.get("timestamp") or "")
            if t is None:
                continue
            typ = d.get("type")
            m = d.get("message") if isinstance(d.get("message"), dict) else {}
            if typ == "assistant":
                mid = m.get("id") or d.get("uuid")
                u = m.get("usage") if isinstance(m.get("usage"), dict) else {}
                r = rbymid.get(mid)
                if r is None:
                    r = dict(
                        mid=mid,
                        t0=t,
                        t1=t,
                        cc=0,
                        cr=0,
                        inp=0,
                        out=0,
                        tools=[],
                        model=m.get("model"),
                    )
                    rbymid[mid] = r
                    reqs.append(r)
                r["t1"] = max(r["t1"], t)
                r["cc"] = max(r["cc"], int(u.get("cache_creation_input_tokens") or 0))
                r["cr"] = max(r["cr"], int(u.get("cache_read_input_tokens") or 0))
                r["inp"] = max(r["inp"], int(u.get("input_tokens") or 0))
                r["out"] = max(r["out"], int(u.get("output_tokens") or 0))
                for c in m.get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        r["tools"].append(
                            (c.get("id"), c.get("name"), c.get("input") or {})
                        )
            elif typ == "user":
                c = m.get("content")
                if isinstance(c, list):
                    for x in c:
                        if isinstance(x, dict) and x.get("type") == "tool_result":
                            tid = x.get("tool_use_id")
                            if tid in results:
                                continue
                            s = x.get("content")
                            s = s if isinstance(s, str) else text_of(s)
                            tur = (
                                d.get("toolUseResult")
                                if isinstance(d.get("toolUseResult"), dict)
                                else {}
                            )
                            bgid = tur.get("backgroundTaskId")
                            if not bgid:
                                mm = BGID_RX.search(s or "")
                                bgid = mm.group(1) if mm else None
                            results[tid] = dict(
                                t=t,
                                err=bool(x.get("is_error")),
                                head=(s or "")[:300],
                                interrupted=bool(tur.get("interrupted")),
                                bgid=bgid,
                            )
                        elif (
                            isinstance(x, dict)
                            and x.get("type") == "text"
                            and "<task-notification>" in x.get("text", "")
                        ):
                            for mm in TASK_RX.finditer(x["text"]):
                                st = STATUS_RX.search(x["text"])
                                notes.append(
                                    (t, mm.group(1), st.group(1) if st else None)
                                )
                elif isinstance(c, str) and "<task-notification>" in c:
                    for mm in TASK_RX.finditer(c):
                        st = STATUS_RX.search(c)
                        notes.append((t, mm.group(1), st.group(1) if st else None))
            elif typ == "attachment":
                a = d.get("attachment") if isinstance(d.get("attachment"), dict) else {}
                pr = a.get("prompt")
                pr = pr if isinstance(pr, str) else (json.dumps(pr) if pr else "")
                if "<task-notification>" in pr:
                    for mm in TASK_RX.finditer(pr):
                        st = STATUS_RX.search(pr)
                        notes.append((t, mm.group(1), st.group(1) if st else None))
    if not reqs:
        return None
    acct = acct_of(p)
    base = os.path.basename(p)
    aid = base[len("agent-") : -len(".jsonl")] if base.startswith("agent-") else base
    parts = p.split("/")
    try:
        sid = parts[parts.index("subagents") - 1]
    except ValueError:
        sid = "-"
    tp = (
        "/".join(parts[: parts.index("subagents") - 1]) + "/" + sid + ".jsonl"
        if "subagents" in parts
        else "-"
    )
    ctx = lambda r: r["inp"] + r["cc"] + r["cr"]
    bash_rows, bg_rows, gap_rows = [], [], []
    idx_of = {id(r): i for i, r in enumerate(reqs)}
    # first notification per task id
    note_t = {}
    for t, tid, st in sorted(notes):
        note_t.setdefault(tid, (t, st))
    for i, r in enumerate(reqs):
        nxt = reqs[i + 1] if i + 1 < len(reqs) else None
        if not (T0 <= r["t0"] <= T1):
            continue
        if nxt is not None:
            gap = nxt["t0"] - r["t0"]
            if gap > 240:
                gap_rows.append(
                    dict(
                        acct=acct,
                        aid=aid,
                        t=r["t0"],
                        gap=gap,
                        ctx=ctx(r),
                        ncc=nxt["cc"],
                        ncr=nxt["cr"],
                        nctx=ctx(nxt),
                        tools=[
                            (
                                n,
                                bool(inp.get("run_in_background")),
                                inp.get("timeout"),
                                str(inp.get("command") or "")[:120],
                            )
                            for _, n, inp in r["tools"]
                        ],
                    )
                )
        for tid, name, inp in r["tools"]:
            if name != "Bash":
                continue
            res = results.get(tid)
            to = inp.get("timeout")
            bg = (
                inp.get("run_in_background") is True
                or str(inp.get("run_in_background")).lower() == "true"
            )
            cmd = str(inp.get("command") or "")
            row = dict(
                id=tid,
                acct=acct,
                aid=aid,
                sid=sid,
                tp=tp,
                file=p,
                t=r["t0"],
                to=to,
                bg=bg,
                ctx=ctx(r),
                out=r["out"],
                model=r["model"],
                rt=(res["t"] - r["t1"]) if res else None,
                res_head=res["head"][:200] if res else None,
                err=res["err"] if res else None,
                interrupted=res["interrupted"] if res else None,
                ntools=len(r["tools"]),
            )
            if nxt is not None:
                row.update(
                    gap=nxt["t0"] - r["t0"],
                    ncc=nxt["cc"],
                    ncr=nxt["cr"],
                    ninp=nxt["inp"],
                    nout=nxt["out"],
                )
            big = (not bg) and isinstance(to, (int, float)) and to > 270000
            row["cmd"] = cmd[:20000] if big else cmd[:200]
            row["cmd_trunc"] = big and len(cmd) > 20000
            bash_rows.append(row)
            if bg and res and res.get("bgid"):
                tk = res["bgid"]
                nt = note_t.get(tk)
                end_t = nt[0] if nt else None
                # requests after launch until the notification (or end of transcript)
                seq = []
                for j in range(i + 1, len(reqs)):
                    rj = reqs[j]
                    if end_t is not None and rj["t0"] > end_t:
                        break
                    seq.append(rj)
                gaps = []
                prev = r
                for rj in seq:
                    gaps.append(rj["t0"] - prev["t0"])
                    prev = rj
                after = None
                if end_t is not None:
                    for j in range(i + 1, len(reqs)):
                        if reqs[j]["t0"] >= end_t:
                            after = reqs[j]
                            break
                polls = []
                for rj in seq:
                    for _, n2, i2 in rj["tools"]:
                        c2 = str(i2.get("command") or "")
                        polls.append(
                            (
                                n2,
                                i2.get("timeout"),
                                bool(i2.get("run_in_background")),
                                c2[:160],
                            )
                        )
                bg_rows.append(
                    dict(
                        id=tid,
                        acct=acct,
                        aid=aid,
                        t=r["t0"],
                        task=tk,
                        done_t=end_t,
                        status=nt[1] if nt else None,
                        dur=(end_t - r["t0"]) if end_t else None,
                        nreq=len(seq),
                        gaps=[round(g, 1) for g in gaps],
                        reqs=[
                            dict(cc=x["cc"], cr=x["cr"], inp=x["inp"], out=x["out"])
                            for x in seq
                        ],
                        calls=polls[:40],
                        ctx=ctx(r),
                        cmd=cmd[:200],
                        after_gap=(after["t0"] - (seq[-1]["t0"] if seq else r["t0"]))
                        if after
                        else None,
                        after_cc=after["cc"] if after else None,
                        after_ctx=ctx(after) if after else None,
                        last_req_t=reqs[-1]["t0"],
                    )
                )
    inwin = [r for r in reqs if T0 <= r["t0"] <= T1]
    frow = dict(
        acct=acct,
        aid=aid,
        file=p,
        nreq=len(inwin),
        cc=sum(r["cc"] for r in inwin),
        cr=sum(r["cr"] for r in inwin),
        out=sum(r["out"] for r in inwin),
        inp=sum(r["inp"] for r in inwin),
    )
    return bash_rows, bg_rows, gap_rows, frow


def main():
    files = [l.strip() for l in open(FL) if l.strip()]
    os.makedirs(OUT, exist_ok=True)
    fb, fg, fgp, ff = (
        open(os.path.join(OUT, n), "w")
        for n in ("bash.jsonl", "bg.jsonl", "gaps.jsonl", "files.jsonl")
    )
    n = 0
    with Pool(NW) as pool:
        for res in pool.imap_unordered(scan_file, files, chunksize=8):
            n += 1
            if n % 500 == 0:
                sys.stderr.write("progress %d/%d\n" % (n, len(files)))
                sys.stderr.flush()
            if not res:
                continue
            b, g, gp, f = res
            for x in b:
                fb.write(json.dumps(x) + "\n")
            for x in g:
                fg.write(json.dumps(x) + "\n")
            for x in gp:
                fgp.write(json.dumps(x) + "\n")
            ff.write(json.dumps(f) + "\n")
    for f in (fb, fg, fgp, ff):
        f.close()
    sys.stderr.write("DONE files=%d\n" % n)


if __name__ == "__main__":
    main()
