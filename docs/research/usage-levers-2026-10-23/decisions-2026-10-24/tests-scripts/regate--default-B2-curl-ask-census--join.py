import json, sys, collections
ci=json.load(open(sys.argv[1])); files=[l.strip() for l in open(sys.argv[2]) if l.strip()]
want={r['tool_use_id'] for r in ci}
res={}; uses={}
def text(c):
    if isinstance(c,str): return c
    if isinstance(c,list): return "".join(x.get("text","") if isinstance(x,dict) else str(x) for x in c)
    return str(c)
for f in files:
    for l in open(f, encoding="utf-8", errors="replace"):
        if not any(t in l for t in want): continue
        try: o=json.loads(l)
        except Exception: continue
        m=o.get("message") or {}
        cont=m.get("content")
        if not isinstance(cont,list): continue
        for c in cont:
            if not isinstance(c,dict): continue
            if c.get("type")=="tool_result" and c.get("tool_use_id") in want:
                res.setdefault(c["tool_use_id"],[]).append((text(c.get("content")), f, c.get("is_error")))
            if c.get("type")=="tool_use" and c.get("id") in want:
                uses.setdefault(c["id"],[]).append(f)
DEN="The user doesn't want to proceed with this tool use"
tally=collections.Counter(); rows=[]
for r in sorted(ci,key=lambda r:r['ts']):
    t=r['tool_use_id']
    if t not in res: v="unknown"
    else:
        txts=[x[0] for x in res[t]]
        v="denied" if any(x.startswith(DEN) for x in txts) else "granted"
    tally[v]+=1
    rows.append((r['ts'],t,r['host'],r['method'],v, (res.get(t) or [("", "", None)])[0][0][:140].replace("\n"," "), bool(uses.get(t))))
print("prompts", len(ci), tally)
for x in rows:
    if x[4]!="granted": print(x)
json.dump(rows, open(sys.argv[3],"w"))
