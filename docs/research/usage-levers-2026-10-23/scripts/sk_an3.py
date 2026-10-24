#!/usr/bin/env python3
"""Skeptic analysis 3: refined eligibility (Monitor/TaskStop/ToolSearch treated as substitutable;
git merge-base not a mutation), saving per account and for b13, against my own deduped denominators."""

import json, collections, re, glob, os, time

rows = [json.loads(l) for l in open("/tmp/usage-audit/skeptic-subagents/sk_rows.jsonl")]
keep = set(json.load(open("/tmp/usage-audit/skeptic-subagents/sk_keep.json")))
rows = [r for r in rows if r["path"] in keep and r["first_in_window"]]
GM = re.compile(
    r"git(?:\s+-C\s+\S+)?\s+(commit|push|merge(?!-)|rebase|cherry-pick|am|reset|checkout|switch|stash|tag|add|worktree\s+add|branch\s+-[dDmM])\b"
)
SAND = re.compile(
    r"(/tmp/|/private/tmp|mktemp|\$TMPDIR|rehearsal|\$R/sb|\$R\b|\$D\b|\$H\b|sandbox|scratch)",
    re.I,
)
wfname = {}
for root in [
    "~/.claude-next/projects",
    "~/.claude-secondary/projects",
    "~/.claude-tertiary/projects",
    "~/.claude-quaternary/projects",
]:
    root = os.path.realpath(os.path.expanduser(root))
    for p in glob.glob(root + "/*/*/workflows/wf_*.json"):
        try:
            if os.stat(p).st_mtime < time.time() - 9 * 86400:
                continue
            wfname[os.path.basename(p)[:-5]] = (
                json.load(open(p)).get("workflowName") or "?"
            )
        except Exception:
            pass


def cls(r):
    if r["skills"]:
        return "X-skill"
    if r["mcps"]:
        return "X-mcp"
    if "Agent" in r["tools"] or "Task" in r["tools"]:
        return "X-agent"
    g = [c for c in r["gitcmds"] if GM.search(c)]
    if g:
        return "B-git-sandbox" if all(SAND.search(c) for c in g) else "X-git-nonsandbox"
    return "A-eligible"


lean = sorted(sum(r["first"][:3]) for r in rows if r["agentType"] == "workflow-lean")
LP50 = lean[len(lean) // 2]
den = {
    "next": 1148.1 + 474.5,
    "next2": 673.8 + 988.4,
    "next3": 751.1 + 293.2,
    "next4": 293.4 + 584.2,
}
den["ALL"] = 5206.7
agg = collections.defaultdict(lambda: [0, 0.0])
for r in rows:
    if r["agentType"] != "workflow-subagent":
        continue
    d = max(0, sum(r["first"][:3]) - LP50)
    s = d * 1.25 + d * 0.1 * max(0, r["nreq"] - 1)
    k = cls(r)
    b13 = wfname.get(r["wf"], "").startswith("b13-round")
    for key in ((r["acct"], k), ("ALL", k), ("ALL", k + ("|b13" if b13 else "|other"))):
        agg[key][0] += 1
        agg[key][1] += s
print("lean first-request p50 used as baseline:", LP50)
for key in sorted(agg, key=lambda k: (k[0] != "ALL", k)):
    n, s = agg[key]
    print(
        f"{key[0]:5} {key[1]:28} slots={n:5} save_wEq_M={s / 1e6:7.1f} share_of_acct={100 * s / 1e6 / den[key[0]]:5.2f}%"
    )
