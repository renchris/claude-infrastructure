# In lead transcripts: does a teammate idle_notification OPEN a lead turn (i.e. a request follows it)?
import json, sys, re
from datetime import datetime
def ep(s): return datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
n_idle=0; opened=0; samples=[]
for path in sys.argv[1:]:
    recs=[]
    for line in open(path,'rb'):
        try: r=json.loads(line)
        except Exception: continue
        recs.append(r)
    for i,r in enumerate(recs):
        if r.get('type')!='user': continue
        c=(r.get('message') or {}).get('content')
        t=c if isinstance(c,str) else ' '.join(b.get('text','') for b in c if isinstance(b,dict) and b.get('type')=='text') if isinstance(c,list) else ''
        if '<teammate-message' in t and 'idle_notification' in t:
            n_idle+=1
            # previous assistant-with-usage before this record and next one after
            prev=next((x for x in reversed(recs[:i]) if x.get('type')=='assistant'),None)
            nxt=next((x for x in recs[i+1:] if x.get('type') in ('assistant','user') and not (x.get('type')=='user' and isinstance((x.get('message') or {}).get('content'),list) and any(isinstance(b,dict) and b.get('type')=='tool_result' for b in x['message']['content']))),None)
            if prev and nxt and nxt.get('type')=='assistant':
                gap=ep(r['timestamp'])-ep(prev['timestamp'])
                if gap>60: opened+=1; samples.append(round(gap))
print('idle_notification user records',n_idle,'that opened a lead turn after >60 s of lead idle',opened,'sample gaps',sorted(samples)[-8:])
