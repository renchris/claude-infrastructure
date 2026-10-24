#!/usr/bin/env python3
"""Evaluate the candidate PreToolUse(Workflow) rule against history.
Rule R1: deny the Workflow call iff its script has >=1 agent() call classified `missing` (no
agentType key, no spread) and not marked `// needs-default`. `indeterminate` calls are allowed.
Rule R2: as R1 but `indeterminate` also denies.
Truth for parse reliability: the run's runtime slots (meta.json agentType) include >=1
workflow-subagent (default) slot. Slot-level: for each default slot in slots.jsonl (7-day window),
was its run denied, and did the slot need the default (Skill/MCP/Agent tool/real git mutation/repo
code write/sandbox git)? Read-only; prints tables."""

import json, os, collections, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slotsum import needs  # noqa

D = os.path.dirname(os.path.abspath(__file__))
runs = {
    json.loads(l)["runId"]: json.loads(l) for l in open(os.path.join(D, "runs.jsonl"))
}
CUT = sys.argv[1] if len(sys.argv) > 1 else "2026-10-17"


def verdict(r, rule):
    v = collections.Counter()
    for c in r.get("calls", []):
        if c["marked"]:
            v["marked"] += 1
            continue
        v[c["verdict"]] += 1
    deny = v["missing"] > 0 or (rule == "R2" and v["indeterminate"] > 0)
    return deny, v


for window in ("all", CUT):
    for rule in ("R1", "R2"):
        cm = collections.Counter()
        ex = collections.defaultdict(list)
        for rid, r in runs.items():
            if not r.get("has_script") or not r.get("rt"):
                continue
            if window != "all" and (r.get("ts") or "") < window:
                continue
            deny, v = verdict(r, rule)
            nd = r["rt"].get("workflow-subagent", 0)
            tot = sum(r["rt"].values())
            truth = nd > 0
            k = (
                ("deny" if deny else "allow")
                + "/"
                + ("has_default" if truth else "no_default")
            )
            if r["n_calls"] == 0:
                k += "/zero_calls_parsed"
            cm[k] += 1
            if len(ex[k]) < 6:
                ex[k].append((rid, r.get("name"), dict(v), r["rt"]))
        n = sum(cm.values())
        print(f"\n== window={window} rule={rule} runs={n}")
        for k, c in sorted(cm.items()):
            print(f"   {k:45s} {c:4d}")
        for k in ex:
            if k.startswith("deny/no_default") or k.startswith("allow/has_default"):
                for e in ex[k]:
                    print("     e.g.", k, e)

# slot-level, 7-day window, rule R1
rows = [json.loads(l) for l in open(os.path.join(D, "slots.jsonl"))]
st = collections.Counter()
per_need = collections.Counter()
for s in rows:
    if s["agentType"] != "workflow-subagent":
        continue
    r = runs.get(s["wf"])
    if not r or not r.get("has_script"):
        st["no_script"] += 1
        continue
    deny, v = verdict(r, "R1")
    nd = needs(s).split(":")[0]
    st[("denied" if deny else "allowed")] += 1
    per_need[(("denied" if deny else "allowed"), nd)] += 1
print("\n== slot level (7-day default slots), rule R1:", dict(st))
for k, c in sorted(per_need.items()):
    print("   ", k, c)
