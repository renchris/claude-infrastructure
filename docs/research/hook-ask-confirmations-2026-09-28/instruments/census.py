import json,re,collections,sys,os
files=[l.strip() for l in open('files.txt')]
asks={}  # key toolUseID -> info
recs=0; hookcount=collections.Counter(); perfile_dupe=0
results={}
askre=re.compile(r'"permissionDecision"\s*:\s*"ask"')
for f in files:
    sub='/subagents/' in f
    try:
        fh=open(f,errors='replace')
    except Exception: continue
    for line in fh:
        if '"attachment"' in line and 'hook_success' in line and 'ask' in line:
            try: r=json.loads(line)
            except Exception: continue
            a=r.get('attachment') or {}
            if a.get('type')!='hook_success': continue
            so=a.get('stdout') or ''
            if not askre.search(so): continue
            recs+=1
            cmd=os.path.basename(a.get('command','') or '')
            try: reason=json.loads(so)['hookSpecificOutput'].get('permissionDecisionReason','')
            except Exception: reason='?'
            tid=a.get('toolUseID')
            k=(tid,cmd)
            if k in asks: perfile_dupe+=1; continue
            asks[k]=dict(hook=cmd,reason=reason,file=f,sub=sub,ts=r.get('timestamp'),hookName=a.get('hookName'),version=r.get('version'),sid=r.get('sessionId'))
        elif '"tool_result"' in line and 'tool_use_id' in line:
            try: r=json.loads(line)
            except Exception: continue
            c=(r.get('message') or {}).get('content')
            if isinstance(c,list):
                for b in c:
                    if isinstance(b,dict) and b.get('type')=='tool_result':
                        t=b.get('content')
                        if isinstance(t,list): t=' '.join(x.get('text','') for x in t if isinstance(x,dict))
                        results[b.get("tool_use_id")]=(str(t)[:200], b.get("is_error"), ("has been denied" in str(t)) and str(t).startswith("Permission to use"))
print('ask attachment records',recs,'distinct (toolUseID,hook)',len(asks),'dupes',perfile_dupe)
print(collections.Counter(v['hook'] for v in asks.values()))
def outcome(t):
    if t is None: return 'no-result'
    s,e,d=t
    if d: return 'denied'
    if "doesn't want to proceed" in s or 'user doesn' in s.lower(): return 'user-rejected'
    return 'ran'
oc=collections.Counter((v['hook'],outcome(results.get(k[0]))) for k,v in asks.items())
print(oc)
print('subagent',sum(v['sub'] for v in asks.values()))
ts=sorted(v['ts'] for v in asks.values() if v['ts'])
print('ts range',ts[0],ts[-1])
json.dump({f'{k[0]}|{k[1]}':dict(v,outcome=outcome(results.get(k[0]))) for k,v in asks.items()},open('asks.json','w'))
