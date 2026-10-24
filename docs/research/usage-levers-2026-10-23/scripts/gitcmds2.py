#!/usr/bin/env python3
"""For workflow-subagent slots flagged git/land: classify the actual mutating git commands
(real repo vs scratch /tmp repo vs false positive like merge-base)."""

import json, re, collections, sys

D = "/tmp/usage-audit/lever-subagents/"
K = set(open(D + "keep_paths.txt").read().split())
rows = [json.loads(l) for l in open(D + "slots.jsonl")]
rows = [
    r
    for r in rows
    if r["path"] in K
    and r["agentType"] == "workflow-subagent"
    and r["first"]
    and any(x.startswith("git-") or x == "land" for x in r["needs"])
]
MUT = re.compile(
    r"\bgit\b((?:\s+-C\s+\S+|\s+-c\s+\S+|\s+--\S+)*)\s+(commit|push|merge|rebase|cherry-pick|am|reset|checkout|switch|stash|tag)(?![-\w])"
)
LAND = re.compile(r"\b(cc-land|land-branch|gh pr (create|merge))\b")
TMP = re.compile(
    r"(/tmp/|/private/tmp|/var/folders|\$TMPDIR|mktemp|\$T\b|\$W\b|\$tmp|\$TMP|scratch|rehears)",
    re.I,
)
cls = collections.Counter(); GC = {}
ex = collections.defaultdict(list)
per = collections.Counter()
for r in rows:
    kinds = set()
    with open(r["path"], "rb") as fh:
        for line in fh:
            if b'"Bash"' not in line or b'"type":"assistant"' not in line:
                continue
            d = json.loads(line)
            for c in (d.get("message") or {}).get("content") or []:
                if (
                    not isinstance(c, dict)
                    or c.get("type") != "tool_use"
                    or c.get("name") != "Bash"
                ):
                    continue
                cmd = str((c.get("input") or {}).get("command", ""))
                for m in MUT.finditer(cmd):
                    verb = m.group(2)
                    scratch = bool(TMP.search(cmd)) or (
                        "/tmp" in (r.get("session_dir") or "")
                    )
                    k = verb + (":scratch" if scratch else ":real?")
                    kinds.add(k)
                    if len(ex[k]) < 4:
                        ex[k].append(cmd[:220].replace("\n", " "))
                if LAND.search(cmd):
                    kinds.add("land")
                    ex["land"].append(cmd[:200]) if len(ex["land"]) < 4 else None
    real_commit = any(
        k in kinds
        for k in (
            "commit:real?",
            "push:real?",
            "merge:real?",
            "rebase:real?",
            "cherry-pick:real?",
            "am:real?",
            "land",
        )
    )
    per[
        "slot real-repo commit-class"
        if real_commit
        else (
            "slot scratch-only git mutation"
            if kinds
            else "slot false positive (merge-base etc.)"
        )
    ] += 1
    GC[r["path"]] = "realcommit" if real_commit else ("scratchgit" if kinds else "fp")
    for k in kinds:
        cls[k] += 1
print(per); json.dump(GC, open(D + "gitclass.json", "w"))
print(cls.most_common())
for k, v in ex.items():
    print("==", k)
    for e in v:
        print("   ", e)
