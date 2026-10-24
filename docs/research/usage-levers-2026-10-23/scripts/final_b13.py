#!/usr/bin/env python3
"""Savings estimate: move eligible workflow-subagent slots to workflow-lean.
Per-slot fixed overhead delta = (first_request - brief_chars/4) - lean median of same (8486).
Weighted cost model (estimate, API price ratios): in 1, cache-write(5m) 1.25, cache-read 0.1, out 5."""

import json, collections

D = "/tmp/usage-audit/lever-subagents/"
K = set(open(D + "keep_paths.txt").read().split())
rows = {
    r["path"]: r
    for r in (json.loads(l) for l in open(D + "slots.jsonl"))
    if r["path"] in K
}
br = {r["path"]: r for r in (json.loads(l) for l in open(D + "briefs.jsonl"))}
gc = json.load(open(D + "gitclass.json"))
tot = json.load(open(D + "totals.json"))
LEAN_FIXED = 8486
W = lambda t: t[0] + t[1] * 1.25 + t[2] * 0.1 + t[3] * 5


def tier(r):
    n = r["needs"]
    b = br.get(r["path"], {})
    if any(x.startswith("skill:") for x in n):
        return "X-skill"
    if any(x.startswith("mcp:") for x in n):
        return "X-mcp"
    g = gc.get(r["path"])
    if g == "realcommit" or "land" in n:
        return "X-commit"
    if (b.get("writes") or {}).get("repo-code"):
        return "X-writes-code"
    if g == "scratchgit":
        return "B-scratch-git-sandbox"
    return "A-eligible"


U = {k.split("|")[1]: v for k, v in json.load(open(D + "runs.json")).items()}
agg = collections.defaultdict(lambda: [0, 0, 0.0, 0.0])
for p, r in rows.items():
    if r["agentType"] != "workflow-subagent" or not r["first"]:
        continue
    b = br.get(p) or {}
    fixed = r["first"] - (b.get("brief_chars") or 0) / 4
    delta = max(0, fixed - LEAN_FIXED)
    sav = delta * 1.25 + delta * 0.1 * max(0, r["nreq"] - 1)
    t = tier(r) + ('|b13' if ((U.get(r['wf']) or {}).get('name') or '').startswith('b13-round') else '|other')
    for a in (r["acct"], "ALL"):
        x = agg[(a, t)]
        x[0] += 1
        x[1] += r["nreq"]
        x[2] += sav
        x[3] += delta * r["nreq"]
accw = {a: W(v["main"]) + W(v["sub"]) for a, v in tot.items()}
accw["ALL"] = sum(accw.values())
print(
    f"{'acct':5} {'tier':24} {'slots':>5} {'req':>6} {'save_wEq_M':>10} {'save_raw_inSide_M':>17} {'%acct_wEq':>9}"
)
for k in sorted(agg, key=lambda k: (k[0] != "ALL", k[0], k[1])):
    x = agg[k]
    print(
        f"{k[0]:5} {k[1]:24} {x[0]:5} {x[1]:6} {x[2] / 1e6:10.1f} {x[3] / 1e6:17.0f} {100 * x[2] / accw[k[0]]:8.1f}%"
    )
print(
    "account 7d wEq_M (main+sub, dedup):", {a: round(v / 1e6) for a, v in accw.items()}
)
