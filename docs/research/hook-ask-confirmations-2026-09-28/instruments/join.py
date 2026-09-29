import json,glob,bisect,collections,datetime
arch=[]
for f in glob.glob('/Users/chrisren/.claude/autonomy/permission-archive/*.jsonl'):
    for l in open(f,errors='replace'):
        arch.append(json.loads(l))
by=collections.defaultdict(list)
for r in arch: by[r['session_id']].append(r['ts'])
for k in by: by[k].sort()
amin=min(r['ts'] for r in arch); amax=max(r['ts'] for r in arch)
def hit(sid,t,w=15):
    L=by.get(sid)
    if not L: return False
    i=bisect.bisect_left(L,t-w)
    return i<len(L) and L[i]<=t+w
# curl
ca=[json.loads(l) for l in open('/Users/chrisren/.reso/curl-audit.jsonl')]
def ep(s): return datetime.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()
cas=[r for r in ca if r['decision']=='ask' and r.get('tool_use_id') not in ('unknown',None,'') and amin<=ep(r['ts'])<=amax]
print('archive span',datetime.datetime.utcfromtimestamp(amin),datetime.datetime.utcfromtimestamp(amax))
print('curl asks in span (real tid)',len(cas),'joined',sum(hit(r['session_id'],ep(r['ts'])) for r in cas))
vb=[json.loads(l) for l in open('/Users/chrisren/.claude/logs/validate-bash-decisions.jsonl')]
vbs=[r for r in vb if r['decision']=='ask' and len(r['sid'])==36 and not r['sid'].startswith('00000000')]
print('vb real asks',len(vbs),'joined',sum(hit(r['sid'],r['ts']) for r in vbs))
# per reason class for vb
c=collections.Counter()
for r in vbs:
    k=r['reason'][:20]; c[(k,hit(r['sid'],r['ts']))]+=1
for k,v in sorted(c.items()): print(v,k)
