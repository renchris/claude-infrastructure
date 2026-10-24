#!/usr/bin/env python3
# Saving model with cache reads weighted 0 (the "reads do not count" branch of the open quota question).
import json, statistics as st
rows=[json.loads(l) for l in open("/tmp/usage-audit/r2/lean-enforce-adv/costslots.jsonl")]
lean=[r for r in rows if r["agentType"]=="workflow-lean"]
LP=st.median([r["first"] for r in lean])
def W0(r): return r["in"]+1.25*r["cc"]+5*r["out"]
npr=st.mean([(W0(r)-1.25*r["first"])/r["nreq"] for r in lean])
for infl in (0.0,0.195,0.27):
    s=0; a=0
    for r in rows:
        if r["agentType"]!="workflow-subagent": continue
        d=max(0,r["first"]-LP); x=1.25*d; s+=x; a+=x-infl*r["nreq"]*npr
    print(f"cr=0 inflation {infl}: model saving {s/1e6:.1f}M, adjusted {a/1e6:.1f}M (lean nonprefix/req {npr/1e3:.1f}k)")
