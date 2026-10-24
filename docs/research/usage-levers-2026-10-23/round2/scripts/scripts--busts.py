#!/usr/bin/env python3
# Re-derive yesterday's busts (skeptic definition B) from /tmp/usage-audit/sk-cache-<acct>.tsv,
# dedupe by message.id, and emit every MAIN-thread and SUBAGENT bust with its gap, plus every gap>1h main request.
import csv, collections, json, sys
from datetime import datetime
csv.field_size_limit(10**9)
ACCT_DIR={"next":"/Users/chrisren/.claude/projects","next2":"/Users/chrisren/.claude-secondary/projects",
          "next3":"/Users/chrisren/.claude-tertiary/projects","next4":"/Users/chrisren/.claude-quaternary/projects"}
INT=("sub","side","in","cc","cr","cc1h","cc5m","out_first","out_max","nrec","has_stop")
T=lambda s: datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()
U={}
for a in ACCT_DIR:
    for r in csv.DictReader(open(f"/tmp/usage-audit/sk-cache-{a}.tsv"),delimiter="\t"):
        for k in INT: r[k]=int(r[k])
        if r["mid"] in U:
            U[r["mid"]]["out_max"]=max(U[r["mid"]]["out_max"],r["out_max"]); U[r["mid"]]["accts"].append(a)
        else:
            r["accts"]=[a]; U[r["mid"]]=r
TL=collections.defaultdict(list)
for r in U.values():
    r["t"]=T(r["ts"]); TL[r["rel"]].append(r)
out=open(sys.argv[1],"w")
for rel,rs in TL.items():
    rs.sort(key=lambda r:r["t"]); prev=None
    for r in rs:
        if prev is not None:
            pp=prev["in"]+prev["cc"]+prev["cr"]; gap=r["t"]-prev["t"]
            bust= pp>=20000 and r["cr"]<0.5*pp and r["cc"]>=0.5*pp
            if bust or (not r["sub"] and gap>2700) or (r["sub"] and gap>270):
                out.write(json.dumps({"rel":rel,"acct":r["accts"][0],"accts":r["accts"],"root":ACCT_DIR[r["accts"][0]],"mid":r["mid"],
                    "ts":r["ts"],"prev_ts":prev["ts"],"prev_mid":prev["mid"],"gap":gap,"sub":r["sub"],"side":r["side"],"bust":bust,
                    "cc":r["cc"],"cr":r["cr"],"in":r["in"],"pp":pp,"cc1h":r["cc1h"],"cc5m":r["cc5m"],"out_max":r["out_max"],
                    "prev_out":prev["out_max"]})+"\n")
        prev=r
