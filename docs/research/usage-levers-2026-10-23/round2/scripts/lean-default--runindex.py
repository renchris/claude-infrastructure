#!/usr/bin/env python3
"""Index every Workflow run on the 4 accounts: runId -> name, timestamp, script text (from the run's
wf_<id>.json `.script`, else its saved scripts/*-wf_<id>.js), and the runtime agentType of each slot
(from subagents/workflows/<runId>/agent-*.meta.json, deduped by agent id across accounts). Then run
the static agent() classifier (agentcalls.py) on each script.
Output runs.jsonl; summary to stdout. Read-only."""

import json, glob, os, sys, collections, re

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from agentcalls import classify

ACCTS = {
    "next": "~/.claude-next",
    "next2": "~/.claude-secondary",
    "next3": "~/.claude-tertiary",
    "next4": "~/.claude-quaternary",
}
D = os.path.dirname(os.path.abspath(__file__))
runs = {}
for a, d in ACCTS.items():
    base = os.path.expanduser(d) + "/projects"
    for f in glob.glob(base + "/*/*/workflows/wf_*.json"):
        rid = os.path.basename(f)[:-5]
        try:
            j = json.load(open(f))
        except Exception:
            continue
        r = runs.setdefault(rid, {"runId": rid, "acct": a, "files": []})
        r["files"].append(f)
        if j.get("script") and not r.get("script"):
            r["script"] = j["script"]
            r["script_src"] = "wf.json"
        r.setdefault("name", j.get("workflowName"))
        r.setdefault("ts", j.get("timestamp"))
        r.setdefault("scriptPath", j.get("scriptPath"))
        r.setdefault("status", j.get("status"))
        r.setdefault("agentCount", j.get("agentCount"))
    for f in glob.glob(base + "/*/*/workflows/scripts/*.js"):
        m = re.search(r"(wf_[0-9a-f]{8}-[0-9a-f]{3})\.js$", f)
        if not m:
            continue
        rid = m.group(1)
        r = runs.setdefault(rid, {"runId": rid, "acct": a, "files": []})
        if not r.get("script"):
            try:
                r["script"] = open(f, errors="replace").read()
                r["script_src"] = "scripts/"
            except Exception:
                pass
        r.setdefault("saved_script", f)
# runtime slot types
slot_seen = set()
for a, d in ACCTS.items():
    for f in glob.glob(
        os.path.expanduser(d)
        + "/projects/*/*/subagents/workflows/wf_*/agent-*.meta.json"
    ):
        aid = os.path.basename(f)[:-10]
        if aid in slot_seen:
            continue
        slot_seen.add(aid)
        rid = os.path.basename(os.path.dirname(f))
        try:
            mt = json.load(open(f))
        except Exception:
            continue
        r = runs.setdefault(rid, {"runId": rid, "acct": a, "files": []})
        r.setdefault("rt", collections.Counter())[mt.get("agentType") or "?"] += 1
out = open(os.path.join(D, "runs.jsonl"), "w")
for rid, r in runs.items():
    s = r.pop("script", None)
    r["has_script"] = bool(s)
    if s:
        try:
            calls = classify(s)
        except Exception as e:
            calls = []
            r["parse_error"] = str(e)[:200]
        r["calls"] = calls
        r["n_calls"] = len(calls)
        r["verdicts"] = dict(collections.Counter(c["verdict"] for c in calls))
        r["script_len"] = len(s)
        r["mentions_agentType"] = "agentType" in s
    r["rt"] = dict(r.get("rt") or {})
    out.write(json.dumps(r) + "\n")
print(
    "runs",
    len(runs),
    "with script",
    sum(1 for r in runs.values() if r.get("has_script")),
    "with slots",
    sum(1 for r in runs.values() if r.get("rt")),
    "slots",
    len(slot_seen),
)
