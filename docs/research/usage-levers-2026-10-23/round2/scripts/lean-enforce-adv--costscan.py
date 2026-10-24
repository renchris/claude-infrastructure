#!/usr/bin/env python3
"""Independent per-slot weighted cost scan of Workflow agent() transcripts (read-only, streaming).
Slots: <cfg>/projects/*/*/subagents/workflows/wf_*/agent-*.jsonl, mtime < 8 days, first request >= CUT.
Usage deduped by message.id (last record wins). Cross-account copies deduped by agent id (keep max nreq).
Weights: input 1, cache_creation 1.25, cache_read 0.1, output 5 (list-price ratios)."""
import json, os, glob, sys, time
CUT = sys.argv[1] if len(sys.argv) > 1 else "2026-10-17T00:00:00"
ROOTS = {"next": "~/.claude-next", "next2": "~/.claude-secondary", "next3": "~/.claude-tertiary", "next4": "~/.claude-quaternary"}
FILE_CUT = time.time() - 8 * 86400
OUT = "/tmp/usage-audit/r2/lean-enforce-adv/costslots.jsonl"
best = {}
wfname = {}
nfiles = 0
for acct, r in ROOTS.items():
    root = os.path.realpath(os.path.expanduser(r)) + "/projects"
    for p in glob.glob(root + "/*/*/workflows/wf_*.json"):
        try:
            if os.stat(p).st_mtime < FILE_CUT: continue
            wfname[os.path.basename(p)[:-5]] = json.load(open(p)).get("workflowName") or "?"
        except Exception: pass
    for p in glob.glob(root + "/*/*/subagents/workflows/wf_*/agent-*.jsonl"):
        try:
            if os.stat(p).st_mtime < FILE_CUT: continue
        except Exception: continue
        nfiles += 1
        aid = os.path.basename(p)[:-6]
        wf = os.path.basename(os.path.dirname(p))
        try: at = json.load(open(p[:-6] + ".meta.json")).get("agentType")
        except Exception: at = None
        msgs = {}; order = []; first_ts = None
        with open(p, "rb") as f:
            for line in f:
                if b'"usage"' not in line: continue
                try: d = json.loads(line)
                except Exception: continue
                if d.get("type") != "assistant": continue
                m = d.get("message") or {}
                u = m.get("usage"); mid = m.get("id")
                if not u or not mid: continue
                if mid not in msgs: order.append(mid)
                msgs[mid] = u
                if first_ts is None: first_ts = d.get("timestamp")
        if not order or (first_ts or "") < CUT: continue
        W = 0.0; tot = {"in":0,"cc":0,"cr":0,"out":0}
        for mid in order:
            u = msgs[mid]
            tot["in"] += u.get("input_tokens") or 0; tot["cc"] += u.get("cache_creation_input_tokens") or 0
            tot["cr"] += u.get("cache_read_input_tokens") or 0; tot["out"] += u.get("output_tokens") or 0
        W = tot["in"] + 1.25*tot["cc"] + 0.1*tot["cr"] + 5*tot["out"]
        u0 = msgs[order[0]]
        first = (u0.get("input_tokens") or 0) + (u0.get("cache_creation_input_tokens") or 0) + (u0.get("cache_read_input_tokens") or 0)
        rec = {"aid": aid, "acct": acct, "wf": wf, "name": wfname.get(wf, "?"), "agentType": at, "nreq": len(order), "first": first, "W": W, **tot, "ts": first_ts}
        if aid not in best or rec["nreq"] > best[aid]["nreq"]: best[aid] = rec
with open(OUT, "w") as o:
    for r in best.values(): o.write(json.dumps(r) + "\n")
print("files", nfiles, "slots", len(best), "wfnames", len(wfname))
print("DONE")
