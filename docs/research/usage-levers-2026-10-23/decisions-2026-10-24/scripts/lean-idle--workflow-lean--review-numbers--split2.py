"""Reviewer: wk-0/wk-1 (2.1.293) gross saving with per-slot prefix delta
D = first_tokens - k*brief_chars - 6,500 (lean prefix), k in {0.30, 0.41}; b13 vs rest; turn models;
with/without the fit4 per-request cost. Also break-even ratios and deny-overhead check."""
import json,runpy,sys
sys.argv=["x"]
g=runpy.run_path("/tmp/lean-idle/workflow-lean/review-numbers/savings.py", run_name="lib")
elig,week,strip_prefix,runs=g["elig"],g["week"],g["strip_prefix"],g["runs"]
WW,WO=0.245,0.404
def sv(s,wr,k,turns=1.195,add=None,perreq=0.0006):
    ft=s["first_cw"]+s["first_cr"]+s["first_in"]
    D=max(0,ft-k*s["brief_chars"]-6500)
    base=(WW*s["cw"]+wr*s["cr"]+WO*s["out"])/1e6+perreq*s["nreq"]
    cw,cr=strip_prefix(s,D)
    resid=(WW*cw+wr*cr+WO*s["out"])/1e6+perreq*s["nreq"]
    lean=resid*turns if add is None else resid*(1+add/s["nreq"])
    return base-lean
rec=[s for s in elig if week(s["first_ts"])<=1]
isb=lambda s:(runs[s["runId"]].get("name") or "").startswith("b13")
B=[s for s in rec if isb(s)]; R=[s for s in rec if not isb(s)]
print("slots b13",len(B),"rest",len(R))
for k in (0.30,0.41):
    for wr in (0.0057,0.0076):
        cells=[]
        for lab,kw in (("x1.195",{}),("x1.195 no-perreq",dict(perreq=0)),("+1req",dict(add=1)),("x1.0",dict(turns=1.0)),("x1.5",dict(turns=1.5))):
            cells.append(f"{lab}: b13 {sum(sv(s,wr,k,**kw) for s in B)/2:5.1f} rest {sum(sv(s,wr,k,**kw) for s in R)/2:5.1f}")
        print(f"k={k} reads={wr} | "+" | ".join(cells))
for grp,ss in (("b13",B),("rest",R)):
    for k in (0.30,0.41):
        lo,hi=1.0,3.0
        for _ in range(40):
            mid=(lo+hi)/2
            if sum(sv(s,0.0057,k,turns=mid) for s in ss)>0: lo=mid
            else: hi=mid
        lo2,hi2=1.0,3.0
        for _ in range(40):
            mid=(lo2+hi2)/2
            if sum(sv(s,0.0076,k,turns=mid,perreq=0) for s in ss)>0: lo2=mid
            else: hi2=mid
        print(f"break-even turns {grp} k={k}: with per-request/.0057 {lo:.2f}; no per-request/.0076 {lo2:.2f}")
