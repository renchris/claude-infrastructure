#!/usr/bin/env python3
"""Per workflow-subagent / workflow-lean slot: tools used, and whether it needed Skill/MCP/commit-class git.
Also joins workflow run records (<session>/workflows/wf_*.json) for names + script agentType usage."""

import json, os, re, collections, glob

rows = [json.loads(l) for l in open("/tmp/usage-audit/subagents.jsonl")]
rows = [r for r in rows if r["t_first"] and r["t_first"] >= "2026-10-16T23:59"]
GITW = re.compile(
    r"\bgit\b[^|;&\n]*\b(commit|push|merge|rebase|cherry-pick|am|reset|checkout|switch|stash|tag)\b"
)
LAND = re.compile(
    r"\b(cc-land|land-branch|gh pr (create|merge)|/land|cc-ship|bin/ship)\b"
)
out = open("/tmp/usage-audit/slots.jsonl", "w")
for r in rows:
    if r["agentType"] not in ("workflow-subagent", "workflow-lean", "general-purpose"):
        continue
    tools = collections.Counter()
    needs = set()
    writes = 0
    with open(r["path"], "rb") as fh:
        for line in fh:
            if b'"tool_use"' not in line or b'"type":"assistant"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            for c in (d.get("message") or {}).get("content") or []:
                if not isinstance(c, dict) or c.get("type") != "tool_use":
                    continue
                n = c.get("name", "")
                tools[n] += 1
                if n == "Skill":
                    needs.add("skill:" + str((c.get("input") or {}).get("skill")))
                if n.startswith("mcp__"):
                    needs.add("mcp:" + n.split("__")[1])
                if n in ("Agent", "Task"):
                    needs.add("agent")
                if n in ("Write", "Edit", "NotebookEdit"):
                    writes += 1
                if n == "Bash":
                    cmd = str((c.get("input") or {}).get("command", ""))
                    m = GITW.search(cmd)
                    if m:
                        needs.add("git-" + m.group(1))
                    if LAND.search(cmd):
                        needs.add("land")
    r2 = dict(r)
    r2["tools"] = dict(tools)
    r2["needs"] = sorted(needs)
    r2["writes"] = writes
    out.write(json.dumps(r2) + "\n")
out.close()
# workflow run records
runs = {}
for acct, root in [
    ("next", "~/.claude-next/projects/"),
    ("next2", "~/.claude-secondary/projects/"),
    ("next3", "~/.claude-tertiary/projects/"),
    ("next4", "~/.claude-quaternary/projects/"),
]:
    root = os.path.expanduser(root)
    for p in glob.glob(root + "*/*/workflows/wf_*.json"):
        if os.stat(p).st_mtime < __import__("time").time() - 8 * 86400:
            continue
        try:
            d = json.load(open(p))
        except Exception:
            continue
        s = d.get("script") or ""
        n_agent = len(re.findall(r"\bagent\s*\(", s))
        n_lean = len(re.findall(r"agentType\s*:\s*['\"`]workflow-lean", s))
        n_type = len(re.findall(r"agentType\s*:", s))
        runs[(acct, d.get("runId"))] = dict(
            name=d.get("workflowName"),
            scriptPath=d.get("scriptPath"),
            agentCount=d.get("agentCount"),
            totalTokens=d.get("totalTokens"),
            n_agent_calls=n_agent,
            n_agentType=n_type,
            n_lean=n_lean,
            session=os.path.dirname(os.path.dirname(p)),
        )
json.dump(
    {f"{k[0]}|{k[1]}": v for k, v in runs.items()},
    open("/tmp/usage-audit/runs.json", "w"),
)
print("runs", len(runs))
