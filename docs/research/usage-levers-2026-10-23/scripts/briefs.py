#!/usr/bin/env python3
"""Control for brief length: first user message chars per slot, and Write/Edit targets of default slots."""

import json, collections, re

D = "/tmp/usage-audit/lever-subagents/"
K = set(open(D + "keep_paths.txt").read().split())
rows = [json.loads(l) for l in open(D + "slots.jsonl")]
rows = [
    r
    for r in rows
    if r["path"] in K
    and r["first"]
    and r["agentType"] in ("workflow-subagent", "workflow-lean")
]
out = open(D + "briefs.jsonl", "w")
for r in rows:
    blen = None
    wt = collections.Counter()
    with open(r["path"], "rb") as fh:
        for i, line in enumerate(fh):
            if blen is None and b'"type":"user"' in line:
                d = json.loads(line)
                c = (d.get("message") or {}).get("content")
                blen = (
                    len(c)
                    if isinstance(c, str)
                    else sum(len(x.get("text", "")) for x in c if isinstance(x, dict))
                )
            if (
                r["agentType"] == "workflow-subagent"
                and b'"tool_use"' in line
                and (b'"Write"' in line or b'"Edit"' in line)
            ):
                d = json.loads(line)
                for c in (d.get("message") or {}).get("content") or []:
                    if (
                        isinstance(c, dict)
                        and c.get("type") == "tool_use"
                        and c.get("name") in ("Write", "Edit")
                    ):
                        p = str((c.get("input") or {}).get("file_path", ""))
                        if p.startswith(("/tmp", "/private/tmp", "/var/folders")):
                            k = "tmp"
                        elif "/.cache/" in p or "/autonomy/research/" in p:
                            k = "cache/research-store"
                        elif p.endswith(
                            (".md", ".txt", ".json", ".jsonl", ".csv", ".html")
                        ):
                            k = "repo-doc"
                        else:
                            k = "repo-code"
                        wt[k] += 1
    out.write(
        json.dumps(
            dict(
                path=r["path"],
                acct=r["acct"],
                agentType=r["agentType"],
                first=r["first"],
                brief_chars=blen,
                writes=dict(wt),
            )
        )
        + "\n"
    )
out.close()
rs = [json.loads(l) for l in open(D + "briefs.jsonl")]
for t in ("workflow-subagent", "workflow-lean"):
    x = [r for r in rs if r["agentType"] == t and r["brief_chars"] is not None]
    bl = sorted(r["brief_chars"] for r in x)
    fs = sorted(r["first"] - r["brief_chars"] / 4 for r in x)
    print(
        t,
        "n",
        len(x),
        "brief_chars p50",
        bl[len(bl) // 2],
        "mean",
        sum(bl) // len(bl),
        "p90",
        bl[int(0.9 * len(bl))],
        "| first minus brief/4: p50",
        int(fs[len(fs) // 2]),
        "p10",
        int(fs[int(0.1 * len(fs))]),
        "p90",
        int(fs[int(0.9 * len(fs))]),
    )
wc = collections.Counter()
for r in rs:
    if r["agentType"] == "workflow-subagent" and r["writes"]:
        wc[
            "slots writing repo-code"
            if r["writes"].get("repo-code")
            else (
                "slots writing repo-doc"
                if r["writes"].get("repo-doc")
                else "slots writing tmp/cache only"
            )
        ] += 1
print(wc)
