"""Reviewer: per-project prefix delta on 2.1.293 from small-brief slots (brief < 4000 chars),
bracketing tokens/char at 0.25 and 0.45; also per-project within-project slope."""
import json,statistics as st,collections,re
S=[json.loads(l) for l in open("/tmp/lean-idle/workflow-lean/review-numbers/slots.jsonl")]
S=[s for s in S if s["nreq"] and s["version"]=="2.1.293"]
def proj(c):
    c=c or ""
    if "/.worktrees/" in c or c.endswith("claude-infrastructure"): return "infra"
    if "agent-context-sync" in c: return "agentsync"
    if c.startswith(("/tmp","/private/tmp")): return "tmp"
    if "/Development/personal" in c: return "personal"
    return "other"
ft=lambda s:s["first_cw"]+s["first_cr"]+s["first_in"]
def fit(xs,ys):
    mx,my=st.mean(xs),st.mean(ys); sxx=sum((x-mx)**2 for x in xs)
    b=sum((x-mx)*(y-my) for x,y in zip(xs,ys))/sxx; return my-b*mx,b
out={}
for at in ("workflow-subagent","workflow-lean"):
    g=collections.defaultdict(list)
    for s in S:
        if s["agentType"]==at: g[proj(s["cwd"])].append(s)
    for p,ss in sorted(g.items()):
        small=[s for s in ss if s["brief_chars"]<4000]
        if len(small)<10: continue
        a,b=fit([s["brief_chars"] for s in ss],[ft(s) for s in ss])
        m25=st.median([ft(s)-0.25*s["brief_chars"] for s in small]); m45=st.median([ft(s)-0.45*s["brief_chars"] for s in small])
        out[(at,p)]=(m25,m45,a)
        print(f"{at:18s} {p:10s} n={len(ss):5d} small={len(small):5d} prefix@0.25={m25:7.0f} prefix@0.45={m45:7.0f} within-fit a={a:7.0f} b={b:.3f}")
for p in ("infra","personal","agentsync","other","tmp"):
    if ("workflow-subagent",p) in out:
        d=out[("workflow-subagent",p)]; L=[v for (at,q),v in out.items() if at=="workflow-lean"]
        lm25=st.median([v[0] for v in L]); lm45=st.median([v[1] for v in L])
        print("delta",p,"@0.25",round(d[0]-lm25),"@0.45",round(d[1]-lm45))
