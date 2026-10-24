#!/usr/bin/env python3
# Skeptic pass 3 (read-only): for unique workflow-subagent and general-purpose transcripts (first copy only),
# classify whether the slot used anything workflow-lean lacks or forbids:
# Skill, Agent/Task, mcp__*, or a git-mutating / landing Bash command. Weighted by window requests.
import json, re, collections

CUT_ISO = json.load(open("/tmp/usage-audit/skeptic_scan_summary.json"))["cutoff"]
files = [json.loads(l) for l in open("/tmp/usage-audit/skeptic_perfile.jsonl")]
GITMUT = re.compile(
    r"\bgit\s+(-C\s+\S+\s+)?(commit|push|merge|rebase|reset|checkout|stash|cherry-pick|am|tag)\b|\bgh\s+pr\s+(create|merge)|\bcc-land\b|\bland\b.*--",
    re.I,
)
seenrel = set()
stats = collections.defaultdict(collections.Counter)
models = collections.defaultdict(collections.Counter)
descs = collections.defaultdict(collections.Counter)
for rec in files:
    at = rec["agentType"]
    if at not in ("workflow-subagent", "general-purpose"):
        continue
    rel = rec["path"].split("/projects/")[1]
    if rel in seenrel:
        continue
    seenrel.add(rel)
    if rec["req"] == 0:
        continue
    flags = set()
    try:
        fh = open(rec["path"], "rb")
    except OSError:
        continue
    with fh:
        for raw in fh:
            if b'"tool_use"' not in raw:
                continue
            try:
                r = json.loads(raw)
            except Exception:
                continue
            if r.get("type") != "assistant":
                continue
            for c in (r.get("message") or {}).get("content") or []:
                if not isinstance(c, dict) or c.get("type") != "tool_use":
                    continue
                n = c.get("name") or ""
                if n == "Skill":
                    flags.add("skill")
                elif n in ("Agent", "Task"):
                    flags.add("agent")
                elif n.startswith("mcp__"):
                    flags.add("mcp")
                elif n in ("Edit", "Write", "NotebookEdit", "MultiEdit"):
                    flags.add("write_file")
                elif n == "Bash":
                    cmd = str((c.get("input") or {}).get("command") or "")
                    if GITMUT.search(cmd):
                        flags.add("git_mut")
    lean_blocker = bool(flags & {"skill", "agent", "mcp", "git_mut"})
    S = stats[at]
    S["files"] += 1
    S["req"] += rec["req"]
    S["cr"] += rec["cr"]
    for f in flags:
        S["files_" + f] += 1
        S["req_" + f] += rec["req"]
    if lean_blocker:
        S["files_blocked"] += 1
        S["req_blocked"] += rec["req"]
        S["cr_blocked"] += rec["cr"]
    for m, n in rec["models"].items():
        models[at][m] += n
    d = re.sub(r"[:\- ]?\d+$", ":N", rec["desc"] or "")[:30]
    descs[at][(d, lean_blocker)] += rec["req"]
out = {
    "stats": {k: dict(v) for k, v in stats.items()},
    "models": {k: dict(v) for k, v in models.items()},
    "top_desc": {
        k: [[list(x), n] for x, n in v.most_common(25)] for k, v in descs.items()
    },
}
json.dump(out, open("/tmp/usage-audit/skeptic_ws_tools.json", "w"), indent=1)
print("DONE")
