# Simulates the proposed PermissionRequest-time deny: apply the shape predicate ONLY to commands that
# actually raised a permission dialog (the beacon archive), 2.1.293 window, and score against outcomes.
import json,collections,sys,datetime
sys.path.insert(0,'.')
from detect2 import classify
A=json.load(open('/tmp/autodeny-census/archive-rows.json'))
C=json.load(open('corpus.json'))
by=collections.defaultdict(list)
for o in C: by[o['cmd']].append(o)
t0=datetime.datetime(2026,10,7,22,5,tzinfo=datetime.timezone.utc).timestamp()
stats=collections.Counter(); ex=collections.defaultdict(list)
for r in A:
    if r.get('tool_name')!='Bash' or r['ts']<t0: continue
    cmd=(r.get('tool_input') or {}).get('command') or ''
    k=classify(cmd)
    outs=by.get(cmd,[])
    lab='safety_deny' if any(o['safety'] for o in outs) else ('human_accept' if any(o['pdsrc']=='user_temporary' for o in outs) else ('human_reject' if any(o['pdsrc']=='user_reject' for o in outs) else ('hook_reject' if any(o['pddec']=='reject' and o['pdsrc']=='hook' for o in outs) else ('config:'+str(outs[0]['pdreason']) if outs else 'no_transcript_match'))))
    stats[(bool(k),lab)]+=1
    ex[(bool(k),lab)].append(cmd[:200].replace('\n',' | '))
for k,v in sorted(stats.items(),key=str): print(k,v)
for key in [(True,'human_accept'),(True,'no_transcript_match'),(True,'config:None'),(False,'human_accept')]:
    print('==',key); [print('  ',c) for c in ex.get(key,[])[:6]]
