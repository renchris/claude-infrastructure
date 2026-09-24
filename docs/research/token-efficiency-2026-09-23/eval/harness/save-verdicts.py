#!/usr/bin/env python3
"""save-verdicts.py <workflow-journal.jsonl> <verdicts.json> — merge a judge workflow's results into
the committed verdict file (keyed by task/brief id; a later run for the same id replaces the earlier)."""

import json, os, sys

journal, dest = sys.argv[1], sys.argv[2]
have = {g["id"]: g for g in json.load(open(dest))} if os.path.exists(dest) else {}
labels = {}
for line in open(journal):
    r = json.loads(line)
    if r.get("type") == "started":
        labels[r["agentId"]] = r.get("label", "")
    if r.get("type") == "result" and labels.get(r.get("agentId"), "").startswith(
        "judge:"
    ):
        gid = labels[r["agentId"]].split(":", 1)[1]
        res = r.get("result") or {}
        if res.get("verdicts"):
            have[gid] = {
                "id": gid,
                "verdicts": res["verdicts"],
                "judge_agent": r["agentId"],
            }
json.dump(sorted(have.values(), key=lambda g: g["id"]), open(dest, "w"), indent=1)
print(
    f"{dest}: {len(have)} groups, {sum(len(g['verdicts']) for g in have.values())} verdicts"
)
