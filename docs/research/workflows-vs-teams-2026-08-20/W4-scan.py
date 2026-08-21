#!/usr/bin/env python3
"""W4 — per-unit quota accounting, independently derived.

Walks all four per-account transcript stores, classifies each transcript into an
orchestration-unit class, and computes per-unit output / cache-creation / lifetime /
implementation-footprint.  Dedupes on message.id (one API response is written once per
CONTENT BLOCK, so a naive line sum inflates 2-3x).

Usage: w4scan.py <hours> <out.json>
"""

import os, sys, json, time, re

HOURS = float(sys.argv[1]) if len(sys.argv) > 1 else 168.0
OUT = sys.argv[2] if len(sys.argv) > 2 else "/dev/stdout"

ROOTS = [
    os.path.expanduser(p)
    for p in (
        "~/.claude/projects",
        "~/.claude-secondary/projects",
        "~/.claude-tertiary/projects",
        "~/.claude-quaternary/projects",
    )
]

WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}
SPAWN_TOOLS = {"Agent", "Task"}

now = time.time()
cutoff = now - HOURS * 3600

# ---- collect candidate files, realpath-deduped -----------------------------
seen_real = set()
files = []
for r in ROOTS:
    store = os.path.basename(os.path.dirname(r))
    for dp, dn, fn in os.walk(r):
        for f in fn:
            if not f.endswith(".jsonl"):
                continue
            p = os.path.join(dp, f)
            try:
                st = os.stat(p)
            except OSError:
                continue
            if st.st_mtime < cutoff:
                continue
            rp = os.path.realpath(p)
            if rp in seen_real:
                continue
            seen_real.add(rp)
            rel = os.path.relpath(p, r).split("/")
            if "workflows" in rel:
                cls = "workflow-agent"
            elif "subagents" in rel:
                cls = "sidechain-subagent"
            else:
                cls = "depth1"
            files.append((p, cls, store, st.st_size))

ts_re = re.compile(r'"timestamp":"([^"]+)"')


def parse_ts(s):
    # 2026-08-21T01:41:45.935Z
    try:
        return time.mktime(time.strptime(s[:19], "%Y-%m-%dT%H:%M:%S"))
    except Exception:
        return None


units = []
for p, cls, store, size in files:
    out = cc = cr = inp = 0
    ids = set()
    nresp = 0
    nwrite = 0
    nspawn = 0
    ntool = 0
    wfiles = set()
    nuser = 0
    agentName = None
    teamName = None
    first_ts = last_ts = None
    model = None
    cwd = None
    try:
        fh = open(p, errors="replace")
    except OSError:
        continue
    with fh:
        for line in fh:
            if '"timestamp"' in line:
                m = ts_re.search(line)
                if m:
                    t = parse_ts(m.group(1))
                    if t:
                        if first_ts is None or t < first_ts:
                            first_ts = t
                        if last_ts is None or t > last_ts:
                            last_ts = t
            if '"agentName"' in line and agentName is None:
                try:
                    d0 = json.loads(line)
                except Exception:
                    d0 = {}
                agentName = d0.get("agentName") or agentName
                teamName = d0.get("teamName") or teamName
            if '"type":"assistant"' not in line and '"type": "assistant"' not in line:
                if '"type":"user"' in line:
                    nuser += 1
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            msg = d.get("message") or {}
            mid = msg.get("id")
            if cwd is None:
                cwd = d.get("cwd")
            content = msg.get("content") or []
            if isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        nm = b.get("name")
                        ntool += 1
                        if nm in WRITE_TOOLS:
                            nwrite += 1
                            fp = (b.get("input") or {}).get("file_path")
                            if fp:
                                wfiles.add(fp)
                        elif nm in SPAWN_TOOLS:
                            nspawn += 1
            if mid and mid in ids:
                continue  # <- the message.id dedupe (repo memory: lines repeat per block)
            if mid:
                ids.add(mid)
            u = msg.get("usage") or {}
            if not u:
                continue
            nresp += 1
            out += u.get("output_tokens", 0) or 0
            cc += u.get("cache_creation_input_tokens", 0) or 0
            cr += u.get("cache_read_input_tokens", 0) or 0
            inp += u.get("input_tokens", 0) or 0
            model = model or msg.get("model")
    if nresp == 0:
        continue
    if cls == "depth1":
        cls2 = "teams-agent" if agentName else "main-session"
    else:
        cls2 = cls
    units.append(
        dict(
            path=p,
            cls=cls2,
            store=store,
            out=out,
            cc=cc,
            cr=cr,
            inp=inp,
            nresp=nresp,
            nwrite=nwrite,
            nfiles=len(wfiles),
            ntool=ntool,
            nspawn=nspawn,
            nuser=nuser,
            model=model,
            life=(last_ts - first_ts) if (first_ts and last_ts) else None,
            first=first_ts,
            last=last_ts,
            agent=agentName,
            team=teamName,
            cwd=cwd,
            size=size,
        )
    )

json.dump(dict(hours=HOURS, nfiles=len(files), units=units), open(OUT, "w"))
print("files scanned", len(files), "units with usage", len(units), file=sys.stderr)
