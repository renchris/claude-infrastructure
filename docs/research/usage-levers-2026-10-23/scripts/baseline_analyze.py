#!/usr/bin/env python3
import json, collections, statistics as S

recs = [json.loads(l) for l in open("/tmp/usage-audit/headscan.jsonl")]


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p / 100 * len(xs)))] if xs else None


def tot(r):
    u = r["u"]
    return u[0] + u[1] + u[2]


print("files", len(recs), "with first usage", sum(1 for r in recs if "u" in r))
print(
    "\n== first-request input-side tokens (input+cache_creation+cache_read), fresh = skill_listing or instructions attachment before first reply"
)
groups = collections.defaultdict(list)
for r in recs:
    if "u" not in r:
        continue
    fresh = ("skill_listing" in r["att"]) or bool(r["instr"])
    if r["sub"]:
        groups[(r["acct"], "sub")].append(r)
    else:
        groups[(r["acct"], "main-fresh" if fresh else "main-other")].append(r)
for k in sorted(groups):
    xs = [tot(r) for r in groups[k]]
    pc = [r["prompt_chars"] // 4 for r in groups[k]]
    print(
        f"{k[0]:6} {k[1]:11} n={len(xs):5} p10={pct(xs, 10):6} p50={pct(xs, 50):6} p90={pct(xs, 90):6} max={max(xs):7} | prompt~tok p50={pct(pc, 50)} | base-ex-prompt p50={pct([a - b for a, b in zip(xs, pc)], 50)}"
    )
print("\n== subagents by agentType (all accounts)")
bt = collections.defaultdict(list)
for r in recs:
    if r["sub"] and "u" in r:
        bt[r.get("agentType")].append(r)
for k, v in sorted(bt.items(), key=lambda kv: -len(kv[1]))[:15]:
    xs = [tot(r) for r in v]
    pc = [r["prompt_chars"] // 4 for r in v]
    instr = sum(1 for r in v if r["instr"])
    sl = sum(1 for r in v if "skill_listing" in r["att"])
    print(
        f"{str(k):28} n={len(v):5} p50={pct(xs, 50):6} p90={pct(xs, 90):6} prompt~tok p50={pct(pc, 50):5} with-instructions={instr} with-skill_listing={sl}"
    )
print("\n== fresh main: attachment chars p50 / mean (all accounts)")
fm = [r for k, v in groups.items() if k[1] == "main-fresh" for r in v]
types = collections.Counter()
for r in fm:
    for t in r["att"]:
        types[t] += 1
for t, c in types.most_common(25):
    xs = [r["att"].get(t, 0) for r in fm if t in r["att"]]
    print(f"{t:28} present={c:5} p50={pct(xs, 50):7} mean={int(S.mean(xs)):7}")
print("\n== fresh main: instructions files (path -> n, p50 chars)")
ic = collections.defaultdict(list)
for r in fm:
    for p, ty, n in r["instr"]:
        key = (p or "").replace("/Users/chrisren", "~")
        if "/.worktrees/" in key:
            key = "<worktree>/" + "/".join(key.split("/")[-3:])
        if "/projects/" in key and key.endswith("MEMORY.md"):
            key = key.split("/projects/")[1]
        ic[(key, ty)].append(n)
for (k, ty), v in sorted(ic.items(), key=lambda kv: -sum(kv[1]))[:25]:
    print(f"{ty:8} {k[:95]:95} n={len(v):5} p50={pct(v, 50):6}")
it = [sum(x[2] for x in r["instr"]) for r in fm]
print(
    "\n== instructions total chars per fresh main p50", pct(it, 50), "p90", pct(it, 90)
)
print(
    "\n== hooks before first reply in fresh main (event, type, cmd) -> n, p50 chars, mean"
)
hc = collections.defaultdict(list)
for r in fm:
    for at, ev, hn, cmd, n in r["hooks"]:
        hc[(ev, at, cmd)].append(n)
for k, v in sorted(hc.items(), key=lambda kv: -sum(kv[1]))[:20]:
    print(f"{str(k)[:80]:80} n={len(v):5} p50={pct(v, 50):6} mean={int(S.mean(v)):6}")
print(
    "hook chars per fresh main p50",
    pct([sum(h[4] for h in r["hooks"]) for r in fm], 50),
)
print("\n== subagent attachments (all) present / p50")
sb = [r for r in recs if r["sub"] and "u" in r]
types = collections.Counter(t for r in sb for t in r["att"])
for t, c in types.most_common(12):
    xs = [r["att"][t] for r in sb if t in r["att"]]
    print(f"{t:28} present={c:5} p50={pct(xs, 50):7}")
hs = collections.defaultdict(list)
for r in sb:
    for at, ev, hn, cmd, n in r["hooks"]:
        hs[(ev, at, cmd)].append(n)
for k, v in sorted(hs.items(), key=lambda kv: -sum(kv[1]))[:8]:
    print("  sub-hook", k, len(v), pct(v, 50))
