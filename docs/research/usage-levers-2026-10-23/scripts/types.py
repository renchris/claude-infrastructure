import json,sys,collections
c=collections.Counter()
for p in sys.argv[1:]:
    for line in open(p,errors='replace'):
        try: d=json.loads(line)
        except: continue
        t=d.get('type'); st=d.get('subtype') or (d.get('attachment') or {}).get('type') if isinstance(d.get('attachment'),dict) else d.get('subtype')
        c[(t,st)]+=1
        if t=='assistant':
            u=d['message'].get('usage') or {}
            if d.get('diagnostics') or d['message'].get('diagnostics'): c[('DIAG',str(d['message'].get('diagnostics'))[:150])]+=1
            if d['message'].get('context_management'): c[('CTXM',str(d['message'].get('context_management'))[:150])]+=1
for k,v in c.most_common(60): print(v,k)
