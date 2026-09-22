#!/usr/bin/env python3
"""Per-agent usage from a Workflow transcript dir.

Maps agentId -> label via journal.jsonl 'started' lines, then sums usage over UNIQUE
message ids (streamed records repeat an id with growing usage; keep the max per field).
Prints JSON: {label: {agentId, models, output, cache_creation, cache_read, input, turns, tools}}.
"""

import json, sys, glob, os, collections

d = sys.argv[1]
labels = {}
for line in open(os.path.join(d, "journal.jsonl")):
    try:
        r = json.loads(line)
    except Exception:
        continue
    if r.get("type") == "started":
        labels[r["agentId"]] = r.get("label")

out = {}
for f in sorted(glob.glob(os.path.join(d, "agent-*.jsonl"))):
    aid = os.path.basename(f)[len("agent-") : -len(".jsonl")]
    per = {}
    models = set()
    tools = collections.Counter()
    seen_tool_ids = set()
    for line in open(f):
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("type") != "assistant":
            continue
        m = r.get("message") or {}
        mid = m.get("id") or r.get("uuid")
        models.add(m.get("model"))
        u = m.get("usage") or {}
        cur = per.setdefault(mid, collections.Counter())
        for k in (
            "output_tokens",
            "cache_creation_input_tokens",
            "cache_read_input_tokens",
            "input_tokens",
        ):
            cur[k] = max(cur[k], u.get(k) or 0)
        for c in m.get("content") or []:
            if (
                isinstance(c, dict)
                and c.get("type") == "tool_use"
                and c.get("id") not in seen_tool_ids
            ):
                seen_tool_ids.add(c.get("id"))
                tools[c.get("name")] += 1
    tot = collections.Counter()
    for c in per.values():
        tot.update(c)
    out[labels.get(aid, aid)] = {
        "agentId": aid,
        "models": sorted(x for x in models if x),
        "output": tot["output_tokens"],
        "cache_creation": tot["cache_creation_input_tokens"],
        "cache_read": tot["cache_read_input_tokens"],
        "input": tot["input_tokens"],
        "turns": len(per),
        "tools": dict(tools),
    }
json.dump(out, sys.stdout, indent=1, sort_keys=True)
print()
