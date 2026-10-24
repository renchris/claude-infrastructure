#!/usr/bin/env python3
import json, collections

D = "/tmp/usage-audit/lever-subagents/"
rows = [json.loads(l) for l in open(D + "slots.jsonl")]; K = set(open(D + "keep_paths.txt").read().split()); rows = [r for r in rows if r["path"] in K]
runs = json.load(open(D + "runs.json"))
W = lambda r: r["inp"] + r["cc"] * 1.25 + r["cr"] * 0.1 + r["out"] * 5
ws = [r for r in rows if r["agentType"] == "workflow-subagent" and r["first"]]
lean = [r for r in rows if r["agentType"] == "workflow-lean" and r["first"]]
print("== workflow-subagent slots by need class")


def cls(r):
    n = r["needs"]
    if any(
        x.startswith(
            (
                "git-commit",
                "git-push",
                "git-merge",
                "git-rebase",
                "git-cherry",
                "git-am",
            )
        )
        or x == "land"
        for x in n
    ):
        return "commit/land"
    if any(x.startswith("skill:") for x in n):
        return "skill"
    if any(x.startswith("mcp:") for x in n):
        return "mcp"
    if "agent" in n:
        return "agent-tool"
    if any(x.startswith("git-") for x in n):
        return "other-git(checkout/reset/stash/tag/switch)"
    if r["writes"]:
        return "writes-files-only"
    return "read-only"


c = collections.defaultdict(lambda: [0, 0, 0.0])
for r in ws:
    for a in (r["acct"], "ALL"):
        k = (a, cls(r))
        c[k][0] += 1
        c[k][1] += r["nreq"]
        c[k][2] += W(r)
for k in sorted(c, key=lambda k: (k[0] != "ALL", k[0], -c[k][0])):
    print(
        f"{k[0]:5} {k[1]:45} slots={c[k][0]:5} req={c[k][1]:6} wEq_M={c[k][2] / 1e6:7.1f}"
    )
sk = collections.Counter(
    x
    for r in ws
    for x in r["needs"]
    if x.startswith(("skill:", "mcp:", "git-", "land", "agent"))
)
print("needs tokens across workflow-subagent slots:", sk.most_common(20))
lean_first_med = sorted(r["first"] for r in lean)[len(lean) // 2]
ws_first_med = sorted(r["first"] for r in ws)[len(ws) // 2]
print("lean first median", lean_first_med, "ws first median", ws_first_med)
tot_over = tot_raw = elig_over = elig_raw = 0
elig_n = 0
peracct = collections.defaultdict(lambda: [0, 0.0, 0.0, 0.0])
for r in ws:
    delta = max(0, r["first"] - lean_first_med)
    raw = delta * r["nreq"]
    w = delta * 1.25 + delta * 0.1 * max(0, r["nreq"] - 1)
    tot_over += w
    tot_raw += raw
    peracct[r["acct"]][3] += W(r)
    if cls(r) in ("read-only", "writes-files-only"):
        elig_over += w
        elig_raw += raw
        elig_n += 1
        peracct[r["acct"]][0] += 1
        peracct[r["acct"]][1] += w
        peracct[r["acct"]][2] += raw
print(
    f"overhead all ws: n={len(ws)} raw_inSide={tot_raw / 1e6:.0f}M wEq={tot_over / 1e6:.0f}M ; eligible n={elig_n} raw={elig_raw / 1e6:.0f}M wEq={elig_over / 1e6:.0f}M"
)
for a, v in sorted(peracct.items()):
    print(
        f"  eligible {a}: n={v[0]} overhead_wEq={v[1] / 1e6:.0f}M raw={v[2] / 1e6:.0f}M of ws_total_wEq={v[3] / 1e6:.0f}M"
    )
print("== workflows spawning workflow-subagent slots (top 30 by slots)")
g = collections.defaultdict(lambda: [0, 0, 0.0, collections.Counter(), None])


def nm(r):
    run = runs.get(f"{r['acct']}|{r['wf']}") if r["wf"] else None
    return run, (run or {}).get("name") or (
        "(direct Agent spawn)" if not r["wf"] else "(run record missing)"
    )


for r in ws:
    run, name = nm(r)
    k = (r["acct"], name)
    g[k][0] += 1
    g[k][2] += W(r)
    g[k][3][cls(r)] += 1
    if run:
        g[k][4] = (
            run["n_agent_calls"],
            run["n_agentType"],
            run["n_lean"],
            run["scriptPath"],
        )
for r in lean:
    run, name = nm(r)
    if (r["acct"], name) in g:
        g[(r["acct"], name)][1] += 1
for k in sorted(g, key=lambda k: -g[k][0])[:30]:
    v = g[k]
    print(
        f"{k[0]:5} {str(k[1])[:42]:42} ws={v[0]:4} lean={v[1]:4} wEq_M={v[2] / 1e6:6.1f} {dict(v[3])} script(agent(,agentType:,lean)={v[4][:3] if v[4] else None}"
    )
print(collections.Counter("run found" if nm(r)[0] else nm(r)[1] for r in ws))
names = collections.Counter(nm(r)[1] for r in ws)
print("distinct workflow names with ws slots:", len(names))
