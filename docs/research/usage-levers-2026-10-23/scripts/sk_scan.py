#!/usr/bin/env python3
"""Skeptic re-scan (independent of lever-subagents scripts). Read-only.
Per subagent transcript (agent-*.jsonl under */subagents/**) in the 4 config dirs:
unique requests by message.id (last usage record wins, synthetic skipped), request-timestamp
window (>= now-7d), first-request split incl. cache_creation 5m/1h TTL, tool names, skills,
mcp servers, git-mutation commands. Output: sk_rows.jsonl"""

import json, os, re, sys, time, collections
from datetime import datetime, timezone, timedelta

ACCTS = {
    "next": "~/.claude-next/projects",
    "next2": "~/.claude-secondary/projects",
    "next3": "~/.claude-tertiary/projects",
    "next4": "~/.claude-quaternary/projects",
}
NOW = time.time()
CUT_TS = datetime.fromtimestamp(NOW - 7 * 86400, tz=timezone.utc).strftime(
    "%Y-%m-%dT%H:%M:%S"
)
FILE_CUT = NOW - 8 * 86400
OUT = "/tmp/usage-audit/skeptic-subagents/sk_rows.jsonl"
GITMUT = re.compile(
    r"(?:^|[;&|(\s])git(?:\s+-C\s+\S+)?\s+(commit|push|merge|rebase|cherry-pick|am|reset|checkout|switch|stash|tag|add|worktree\s+add|branch\s+-[dDmM])\b"
)


def usage_tuple(u):
    cc = u.get("cache_creation") or {}
    return [
        u.get("input_tokens") or 0,
        u.get("cache_creation_input_tokens") or 0,
        u.get("cache_read_input_tokens") or 0,
        u.get("output_tokens") or 0,
        cc.get("ephemeral_5m_input_tokens") or 0,
        cc.get("ephemeral_1h_input_tokens") or 0,
    ]


def scan(path):
    reqs = collections.OrderedDict()
    tools = collections.Counter()
    skills = set()
    mcps = set()
    gitcmds = []
    with open(path, "rb") as fh:
        for line in fh:
            if b'"assistant"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            m = d.get("message") or {}
            if m.get("model") == "<synthetic>":
                continue
            u = m.get("usage")
            mid = m.get("id")
            if u and mid:
                if mid not in reqs:
                    reqs[mid] = [usage_tuple(u), d.get("timestamp") or ""]
                else:
                    reqs[mid][0] = usage_tuple(u)
            for c in m.get("content") or []:
                if not isinstance(c, dict) or c.get("type") != "tool_use":
                    continue
                n = c.get("name", "")
                tools[n] += 1
                inp = c.get("input") or {}
                if n == "Skill":
                    skills.add(str(inp.get("skill") or inp.get("command")))
                elif n.startswith("mcp__"):
                    mcps.add(n.split("__")[1])
                elif n == "Bash":
                    cmd = str(inp.get("command", ""))
                    mm = GITMUT.search(cmd)
                    if mm and len(gitcmds) < 6:
                        gitcmds.append(cmd[:300])
    return reqs, tools, skills, mcps, gitcmds


def main():
    out = open(OUT, "w")
    nf = nb = 0
    t0 = time.time()
    for acct, root in ACCTS.items():
        root = os.path.realpath(os.path.expanduser(root))
        for dp, dns, fns in os.walk(root):
            if "/subagents" not in dp:
                continue
            for fn in fns:
                if not (fn.startswith("agent-") and fn.endswith(".jsonl")):
                    continue
                p = os.path.join(dp, fn)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                if st.st_mtime < FILE_CUT:
                    continue
                nf += 1
                nb += st.st_size
                try:
                    meta = json.load(open(p[:-6] + ".meta.json"))
                except Exception:
                    meta = {}
                reqs, tools, skills, mcps, gitcmds = scan(p)
                win = [(k, v) for k, v in reqs.items() if v[1] >= CUT_TS]
                if not win:
                    continue
                allfirst = next(iter(reqs.values()))
                tot = [0] * 6
                for _, v in win:
                    for i in range(6):
                        tot[i] += v[0][i]
                rel = p[len(root) + 1 :].split("/")
                wf = None
                if "workflows" in rel:
                    i = rel.index("workflows")
                    wf = rel[i + 1] if i + 1 < len(rel) - 1 else None
                out.write(
                    json.dumps(
                        dict(
                            acct=acct,
                            path=p,
                            aid=fn[:-6],
                            proj=rel[0],
                            sess=rel[1],
                            wf=wf,
                            mtime=st.st_mtime,
                            size=st.st_size,
                            agentType=meta.get("agentType", "?"),
                            desc=meta.get("description"),
                            nreq_all=len(reqs),
                            nreq=len(win),
                            first=allfirst[0],
                            first_ts=allfirst[1],
                            first_in_window=allfirst[1] >= CUT_TS,
                            tot=tot,
                            tools=dict(tools),
                            skills=sorted(skills),
                            mcps=sorted(mcps),
                            gitcmds=gitcmds,
                        )
                    )
                    + "\n"
                )
        print(
            f"acct {acct} done files={nf} GB={nb / 1e9:.2f} t={time.time() - t0:.0f}s",
            flush=True,
        )
    out.close()
    print(
        f"DONE files={nf} GB={nb / 1e9:.2f} cut_ts={CUT_TS} t={time.time() - t0:.0f}s",
        flush=True,
    )


main()
