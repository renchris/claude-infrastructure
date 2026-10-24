#!/usr/bin/env python3
"""Read-only 7-day scan of subagent transcripts across the 4 config dirs.
Per subagent file: agentType (meta.json), dedup'd requests (by message.id, max per field),
first-request input side, totals. Writes /tmp/usage-audit/subagents.jsonl and prints summary."""

import json, os, sys, time, glob

ACCTS = {
    "next": os.path.expanduser("~/.claude-next/projects/"),
    "next2": os.path.expanduser("~/.claude-secondary/projects/"),
    "next3": os.path.expanduser("~/.claude-tertiary/projects/"),
    "next4": os.path.expanduser("~/.claude-quaternary/projects/"),
}
CUTOFF = time.time() - 7 * 86400
OUT = "/tmp/usage-audit/subagents.jsonl"


def scan_file(path):
    reqs = {}
    order = []
    with open(path, "rb") as fh:
        for line in fh:
            if b'"type":"assistant"' not in line or b'"usage"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            m = d.get("message") or {}
            u = m.get("usage") or {}
            mid = m.get("id") or d.get("requestId") or d.get("uuid")
            if m.get("model") == "<synthetic>":
                continue
            rec = reqs.get(mid)
            vals = (
                u.get("input_tokens") or 0,
                u.get("cache_creation_input_tokens") or 0,
                u.get("cache_read_input_tokens") or 0,
                u.get("output_tokens") or 0,
            )
            if rec is None:
                reqs[mid] = list(vals) + [m.get("model"), d.get("timestamp")]
                order.append(mid)
            else:
                for i in range(4):
                    if vals[i] > rec[i]:
                        rec[i] = vals[i]
    return reqs, order


def main():
    out = open(OUT, "w")
    t0 = time.time()
    nfiles = 0
    nbytes = 0
    for acct, root in ACCTS.items():
        for dirpath, dirnames, filenames in os.walk(root):
            if "/subagents" not in dirpath:
                continue
            for fn in filenames:
                if not fn.endswith(".jsonl") or not fn.startswith("agent-"):
                    continue
                p = os.path.join(dirpath, fn)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                if st.st_mtime < CUTOFF:
                    continue
                meta = {}
                mp = p[:-6] + ".meta.json"
                try:
                    meta = json.load(open(mp))
                except Exception:
                    pass
                reqs, order = scan_file(p)
                nfiles += 1
                nbytes += st.st_size
                if not order:
                    first = None
                else:
                    r = reqs[order[0]]
                    first = r[0] + r[1] + r[2]
                tot = [0, 0, 0, 0]
                models = {}
                for mid in order:
                    r = reqs[mid]
                    for i in range(4):
                        tot[i] += r[i]
                    models[r[4]] = models.get(r[4], 0) + 1
                rel = p[len(root) :]
                parts = rel.split("/")
                wf = None
                if "workflows" in parts:
                    i = parts.index("workflows")
                    if i + 1 < len(parts):
                        wf = parts[i + 1]
                sess_dir = os.path.join(root, *parts[:2])
                rec = dict(
                    acct=acct,
                    path=p,
                    session_dir=sess_dir,
                    wf=wf,
                    agentType=meta.get("agentType", "?"),
                    desc=meta.get("description"),
                    phase=meta.get("workflowPhase"),
                    nreq=len(order),
                    first=first,
                    inp=tot[0],
                    cc=tot[1],
                    cr=tot[2],
                    out=tot[3],
                    models=models,
                    size=st.st_size,
                    mtime=st.st_mtime,
                    t_first=reqs[order[0]][5] if order else None,
                )
                out.write(json.dumps(rec) + "\n")
                if nfiles % 500 == 0:
                    print(
                        f"progress files={nfiles} GB={nbytes / 1e9:.2f} t={time.time() - t0:.0f}s",
                        flush=True,
                    )
    out.close()
    print(
        f"DONE files={nfiles} GB={nbytes / 1e9:.2f} t={time.time() - t0:.0f}s",
        flush=True,
    )


main()
