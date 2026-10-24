import json,sys
from datetime import datetime
p=sys.argv[1]; g0=datetime.fromisoformat(sys.argv[2].replace('Z','+00:00')).timestamp(); w=float(sys.argv[3])
last=None
for n,line in enumerate(open(p,errors='ignore')):
    try: r=json.loads(line)
    except Exception: continue
    t=r.get('timestamp'); typ=r.get('type'); sub=r.get('subtype') or (r.get('attachment') or {}).get('type') if isinstance(r.get('attachment'),dict) or r.get('subtype') else ''
    if isinstance(t,str):
        last=datetime.fromisoformat(t.replace('Z','+00:00')).timestamp()
        if g0-15<=last<=g0+w: print(n,'%+8.0f'%(last-g0),typ,sub or '', len(line))
    else:
        if last and g0-15<=last<=g0+w: print(n,'  (nots)',typ,line[:160].strip())
