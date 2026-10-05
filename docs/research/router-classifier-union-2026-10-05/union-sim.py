import json, sys
from pathlib import Path
H = Path.home()/".claude/autonomy/research/router-heldout"
REL=("completeness","pushback"); LIM=9.0
d=json.load(open(sys.argv[1]))
strata=[json.loads(l)["stratum"] for l in open(H/"tuning.jsonl")]
lab=[{int(r["id"][1:]):r["label"] for r in map(json.loads,open(H/f"tuning-labels-{v}.jsonl"))} for v in ("anthropic","openai")]
agreed={k:lab[0][k] for k in lab[0] if lab[1].get(k)==lab[0][k]}
border=[k for k in lab[0] if k in lab[1] and lab[0][k]!=lab[1][k] and (lab[0][k] in REL or lab[1][k] in REL)]
def ok(c): return c and c["label"] not in("INVALID","TIMEOUT") and c["wall_s"]<=LIM
def union(off,on):
    if ok(off) and off["label"] in REL: return off["label"]
    if ok(on) and on["label"] in REL: return on["label"]
    if ok(off): return off["label"]
    if ok(on): return on["label"]
    return None
arms={a:{} for a in d["arms"]}
for a,rows in d["arms"].items():
    for k,cs in rows.items():
        arms[a][int(k)]=[(c["label"] if ok(c) else None) for c in cs]
for base in ("on-pre","on-e1b"):
    u={}
    for k in arms["off-e1b"]:
        u[k]=[union(d["arms"]["off-e1b"][str(k)][i], d["arms"][base].get(str(k),[None,None])[i]) for i in range(len(d["arms"]["off-e1b"][str(k)]))]
    arms[f"union(off+{base})"]=u
for a,rows in arms.items():
    calls=[(k,l) for k,ls in rows.items() for l in ls]
    fb=sum(1 for _,l in calls if l is None)
    rec=[l in REL for k,l in calls if strata[k]!="other" and agreed.get(k) in REL]
    oth=[l==agreed[k] for k,l in calls if strata[k]=="other" and k in agreed and l is not None]
    othall=[l==agreed[k] for k,l in calls if strata[k]=="other" and k in agreed]
    bd=sum(1 for k,l in calls if k in border and l in REL)
    stab=sum(1 for k,ls in rows.items() if len(ls)==2 and ls[0]!=ls[1])
    print(f"{a:22s} recall {sum(rec)}/{len(rec)}  other(answered) {sum(oth)}/{len(oth)}  other(all) {sum(othall)}/{len(othall)}  borderline {bd}/{2*len(border)}  fallback {fb}/{len(calls)}  rows-flipped {stab}/{len(rows)}")
