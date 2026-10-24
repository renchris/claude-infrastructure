#!/usr/bin/env python3
import json, statistics as st, collections
rows=[json.loads(l) for l in open("/tmp/usage-audit/r2/lean-enforce-adv/costslots.jsonl")]
def grp(r):
    t=r["agentType"]; b13=(r["name"] or "").startswith("b13-round")
    return f"{t}|{'b13' if b13 else 'other'}"
g=collections.defaultdict(list)
for r in rows: g[grp(r)].append(r)
def p50(x): return st.median(x) if x else 0
print("group | n | nreq p50 | nreq mean | first p50 | W p50 (k) | W mean (k) | W total (M) | nonprefix/req mean (k)")
for k in sorted(g, key=lambda k:-len(g[k])):
    R=g[k]
    npr=[(r["W"]-1.25*r["first"]-0.1*r["first"]*max(0,r["nreq"]-1))/r["nreq"] for r in R]
    print(f"{k} | {len(R)} | {p50([r['nreq'] for r in R])} | {st.mean([r['nreq'] for r in R]):.1f} | {p50([r['first'] for r in R]):.0f} | {p50([r['W'] for r in R])/1e3:.0f} | {st.mean([r['W'] for r in R])/1e3:.0f} | {sum(r['W'] for r in R)/1e6:.1f} | {st.mean(npr)/1e3:.1f}")
# saving model, as in sk_an3: d = first - lean p50 first; s = 1.25 d + 0.1 d (n-1)
lean=[r for r in rows if r["agentType"]=="workflow-lean"]
LP=p50([r["first"] for r in lean])
lean_npr=st.mean([(r["W"]-1.25*r["first"]-0.1*r["first"]*max(0,r["nreq"]-1))/r["nreq"] for r in lean])
for infl in (0.0, 0.195, 0.27):
    tot=0; totadj=0; n=0
    for r in rows:
        if r["agentType"]!="workflow-subagent": continue
        d=max(0,r["first"]-LP); s=1.25*d+0.1*d*max(0,r["nreq"]-1)
        extra=infl*r["nreq"]*(lean_npr+0.1*LP)
        tot+=s; totadj+=s-extra; n+=1
    print(f"inflation {infl}: default slots {n}, model saving {tot/1e6:.1f}M, minus extra lean requests {totadj/1e6:.1f}M (lean p50 first {LP}, lean nonprefix/req {lean_npr/1e3:.1f}k)")
