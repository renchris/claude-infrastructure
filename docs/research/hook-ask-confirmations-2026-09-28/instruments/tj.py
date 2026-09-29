import json,glob,collections,datetime,re
arch=[]
for f in glob.glob('/Users/chrisren/.claude/autonomy/permission-archive/*.jsonl'):
    for l in open(f):
        try: arch.append(json.loads(l))
        except Exception: pass
t_end=datetime.datetime(2026,9,29,1,47,tzinfo=datetime.timezone.utc).timestamp(); t0=t_end-30*86400
win=[a for a in arch if t0<=a['ts']<=t_end and a.get('tool_name')=='Bash']
asks=json.load(open('asks.json'))
def ep(s): return datetime.datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
tid2hook={k.split('|')[0]:v['hook'] for k,v in asks.items()}
bysid=collections.defaultdict(list)
for k,v in asks.items():
    if v['ts']: bysid[v['sid']].append((ep(v['ts']),v['hook'],k.split('|')[0],v['reason']))
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/curl-audit.jsonl') if l.strip()]
curlids={}
for r in rows:
    if r['decision']=='ask' and r.get('tool_use_id')!='unknown':
        curlids[r['tool_use_id']]=1
        bysid[r['session_id']].append((datetime.datetime.strptime(r['ts'],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp(),'curl-gate-scope.sh',r['tool_use_id'],r['cmd_redacted']))
vb=[json.loads(l) for l in open('/Users/chrisren/.claude/logs/validate-bash-decisions.jsonl')]
for r in vb:
    if r['decision']=='ask': bysid[r['sid']].append((r['ts'],'validate-bash.sh',None,r['reason']))
c=collections.Counter()
for a in win:
    cid=a.get('cleared_tool_use_id') or ''
    exact=tid2hook.get(cid) or (cid in curlids)
    near=[x for x in bysid.get(a['session_id'],[]) if abs(x[0]-a['ts'])<=15]
    if exact or not near: continue
    cmd=(a.get('tool_input') or {}).get('command','') or ''
    # does archived command itself look like the hook's trigger?
    hooks={x[1] for x in near}
    trig = ('curl' in cmd and 'curl-gate-scope.sh' in hooks) or (re.search(r'\brm\b|git\s.*reset|git\s.*clean|git\s.*restore|stash\s+drop',cmd) and 'validate-bash.sh' in hooks)
    c[(a['resolved_by'], 'cid' if cid else 'nocid', 'cmd-fits-hook' if trig else 'cmd-does-NOT-fit')]+=1
for x in sorted(c.items(),key=str): print(x)
