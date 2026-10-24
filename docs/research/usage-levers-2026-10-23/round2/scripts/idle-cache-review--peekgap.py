#!/usr/bin/env python3
# Print a compact record timeline of one transcript in a time window around a gap. Read-only.
import json, sys
from datetime import datetime
T=lambda s: datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()
path, gap_end_iso, gap = sys.argv[1], sys.argv[2], float(sys.argv[3])
ge=T(gap_end_iso); gs=ge-gap
lo=gs-float(sys.argv[4]) if len(sys.argv)>4 else gs-1800
for line in open(path, errors="replace"):
    try: d=json.loads(line)
    except Exception: continue
    ts=d.get("timestamp")
    if not ts: continue
    t=T(ts)
    if t<lo or t>ge+120: continue
    ty=d.get("type"); m=d.get("message") or {}
    desc=""
    if ty=="assistant":
        u=m.get("usage") or {}
        parts=[]
        for c in m.get("content") or []:
            if c.get("type")=="tool_use":
                i=c.get("input") or {}
                parts.append(f"TU[{c.get('name')} bg={i.get('run_in_background')} to={i.get('timeout')} id={c.get('id')[-6:]}] "+str(i.get('command') or i.get('description') or '')[:90].replace('\n',' '))
            elif c.get("type")=="text": parts.append("TXT "+c.get("text","")[:80].replace('\n',' '))
        desc=f"mid={str(m.get('id'))[-6:]} stop={m.get('stop_reason')} cr={u.get('cache_read_input_tokens')} cc={u.get('cache_creation_input_tokens')} "+" | ".join(parts)
    elif ty=="user":
        c=m.get("content")
        if isinstance(c,list):
            for x in c:
                if isinstance(x,dict) and x.get("type")=="tool_result":
                    cc=x.get("content"); s=cc if isinstance(cc,str) else json.dumps(cc)
                    desc+=f"TR[{x.get('tool_use_id','')[-6:]}] "+s[:120].replace('\n',' ')
                elif isinstance(x,dict) and x.get("type")=="text":
                    desc+="UTXT "+x.get("text","")[:160].replace('\n',' ')
        else: desc="USTR "+str(c)[:160].replace('\n',' ')
        tur=d.get("toolUseResult")
        if isinstance(tur,dict) and tur.get("backgroundTaskId"): desc+=f" bgid={tur.get('backgroundTaskId')}"
    elif ty=="attachment":
        a=d.get("attachment") or {}; desc="ATT "+str(a.get("type"))+" "+json.dumps(a)[:160]
    elif ty=="system":
        desc="SYS "+str(d.get("subtype"))+" "+str(d.get("content"))[:140].replace('\n',' ')
    else: desc=str(ty)
    mark=" <<GAPSTART" if abs(t-gs)<1 else (" <<GAPEND" if abs(t-ge)<1 else "")
    print(f"{ts[11:19]} {ty[:4]:4s} {desc[:260]}{mark}")
