#!/usr/bin/env python3
"""Refined needs-default class per 7-day default slot (quotes and heredoc bodies stripped before the
git regex, so `grep 'git push'` no longer counts), then run-level: of the runs rule R1 would deny,
how many had every default slot eligible for lean, some, or none. Read-only.
Classes (first match wins): skill, mcp, agent_tool, git_real (mutating git outside a sandbox path),
repo_code_write, git_sandbox (mutating git in /tmp|mktemp clones), soft (ToolSearch/Monitor/TaskStop
only), none."""

import json, os, re, collections, sys

D = os.path.dirname(os.path.abspath(__file__))
rows = [json.loads(l) for l in open(os.path.join(D, "slots.jsonl"))]
runs = {
    json.loads(l)["runId"]: json.loads(l) for l in open(os.path.join(D, "runs.jsonl"))
}
HEREDOC = re.compile(r"<<-?\s*['\"]?(\w+)['\"]?.*?\n.*?\n\s*\1\b", re.S)
QUOTED = re.compile(r"'[^']*'|\"(?:\\.|[^\"\\])*\"")
SBX = re.compile(r"(?:/private)?/tmp/|/var/folders/|mktemp|TMPDIR")
GITMUT = re.compile(
    r"(?:^|[;&|(\s])git(?:\s+-C\s+\S+)?(?:\s+-c\s+\S+)*\s+(commit|push|merge|rebase|cherry-pick|am|reset|checkout|switch|stash\s+(?:push|pop|apply|drop|clear|save)|stash\s*(?:$|[;&|)])|tag\s+-?[a-zA-Z]|add|clean|worktree\s+add|branch\s+-[dDmM])(?![\w-])"
)
LEAN_TOOLS = {
    "Read",
    "Grep",
    "Glob",
    "Bash",
    "Write",
    "Edit",
    "WebFetch",
    "WebSearch",
    "StructuredOutput",
}


def git_class(path):
    real = sbx = 0
    with open(path, "rb") as fh:
        for line in fh:
            if b'"Bash"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            for c in (d.get("message") or {}).get("content") or []:
                if (
                    isinstance(c, dict)
                    and c.get("type") == "tool_use"
                    and c.get("name") == "Bash"
                ):
                    cmd = str((c.get("input") or {}).get("command", ""))
                    c3 = QUOTED.sub(" Q ", HEREDOC.sub(" H ", cmd))
                    if GITMUT.search(c3):
                        if SBX.search(cmd):
                            sbx += 1
                        else:
                            real += 1
    return real, sbx


def cls(r, real, sbx):
    if r["skills"]:
        return "skill"
    if r["mcps"]:
        return "mcp"
    if r["agent_tool"]:
        return "agent_tool"
    if real:
        return "git_real"
    if r["writes_repo_code"]:
        return "repo_code_write"
    if sbx:
        return "git_sandbox"
    if set(r["tools"]) - LEAN_TOOLS:
        return "soft"
    return "none"


out = open(os.path.join(D, "needs2.jsonl"), "w")
c = collections.Counter()
per_run = collections.defaultdict(collections.Counter)
for r in rows:
    if r["agentType"] != "workflow-subagent":
        continue
    real, sbx = git_class(r["path"])
    k = cls(r, real, sbx)
    c[k] += 1
    per_run[r["wf"]][k] += 1
    out.write(
        json.dumps(
            {"aid": r["aid"], "wf": r["wf"], "cls": k, "git_real": real, "git_sbx": sbx}
        )
        + "\n"
    )
n = sum(c.values())
print("7-day default slots by refined class:", n)
for k, v in c.most_common():
    print(f"   {k:16s} {v:5d} ({100 * v / n:.1f}%)")
hard = {"skill", "mcp", "agent_tool", "git_real", "repo_code_write", "git_sandbox"}
rk = collections.Counter()
names = collections.defaultdict(list)
for wf, cc in per_run.items():
    tot = sum(cc.values())
    h = sum(v for k, v in cc.items() if k in hard)
    kind = "all_eligible" if h == 0 else ("all_need_default" if h == tot else "mixed")
    rk[kind] += 1
    nm = (runs.get(wf) or {}).get("name")
    names[kind].append(f"{nm}:{tot}/{h}")
print(
    "runs with default slots, by whether their default slots needed default (hard classes):",
    dict(rk),
)
for k in names:
    print("  ", k, "e.g.", names[k][:12])
