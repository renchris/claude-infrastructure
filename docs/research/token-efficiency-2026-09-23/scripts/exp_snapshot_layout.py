#!/usr/bin/env python3
"""exp_snapshot_layout.py TRANSCRIPT — print the structure of prompt_snapshot attachments: keys, system blocks
(len, cache_control, first 70 chars), tool count/names order, message roles/sizes and cache_control positions."""
import json,sys
def short(s,n=70): return s[:n].replace('\n','\\n')
for line in open(sys.argv[1]):
    r=json.loads(line)
    if r.get('type')!='attachment' or r['attachment'].get('type')!='prompt_snapshot': continue
    a=r['attachment']; print('=== prompt_snapshot keys:',list(a.keys()))
    snap=a.get('snapshot',a)
    if isinstance(snap,dict): print('  snapshot keys:',list(snap.keys()))
    def walk(o,path=''):
        if isinstance(o,dict):
            for k,v in o.items():
                if k=='system' and isinstance(v,list):
                    for i,b in enumerate(v): print(f'  system[{i}] len={len(b.get("text",""))} cc={b.get("cache_control")} :: {short(b.get("text",""))}')
                elif k=='system' and isinstance(v,str): print('  system str len',len(v))
                elif k=='tools' and isinstance(v,list):
                    print(f'  tools n={len(v)} cc_on={[t.get("name") for t in v if isinstance(t,dict) and t.get("cache_control")]} defer={sum(1 for t in v if isinstance(t,dict) and t.get("defer_loading"))}')
                    print('   names:',[t.get('name') for t in v if isinstance(t,dict)][:60])
                elif k=='messages' and isinstance(v,list):
                    for i,m in enumerate(v):
                        c=m.get('content'); 
                        if isinstance(c,str): print(f'  msg[{i}] {m.get("role")} str len={len(c)} :: {short(c)}')
                        else:
                            for j,b in enumerate(c):
                                t=b.get('text') if isinstance(b,dict) else None
                                print(f'  msg[{i}].{j} {m.get("role")} {b.get("type")} len={len(json.dumps(b))} cc={b.get("cache_control")} :: {short(t or "")}')
                else: walk(v,path+'.'+k)
        elif isinstance(o,list):
            for x in o: walk(x,path)
    walk(a)
