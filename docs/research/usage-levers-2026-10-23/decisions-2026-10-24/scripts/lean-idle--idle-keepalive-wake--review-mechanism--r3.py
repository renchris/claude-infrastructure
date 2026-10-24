# List every transcript line written inside a live-logged idle gap (incl. lines WITHOUT a timestamp, by position)
import json, sys
from datetime import datetime
def ep(s): return datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
path, gs, ge = sys.argv[1], ep(sys.argv[2]), ep(sys.argv[3])
prev_t=None; inside=False
for i,line in enumerate(open(path,'rb')):
    try: r=json.loads(line)
    except Exception: print(i,'unparseable',len(line)); continue
    t=r.get('timestamp'); te=ep(t) if t else None
    lab=r.get('type','?')+':'+str(r.get('subtype') or (r.get('attachment') or {}).get('type') or '')
    if te is not None: inside = gs-30 <= te <= ge+5
    if inside:
        print('%5d %-8s %-40s %6d B %s'%(i, ('+%.0f'%(te-gs)) if te else 'no-ts', lab, len(line), (str((r.get('message') or {}).get('content'))[:90].replace('\n',' ') if r.get('type') in ('user',) else '')))
