import sys,json,glob,bisect,collections,datetime,time
sys.path.insert(0,'/Users/chrisren/Development/claude-infrastructure/hooks/lib')
import permission_matcher as pm
arch=[]
for f in glob.glob('/Users/chrisren/.claude/autonomy/permission-archive/*.jsonl'):
    for l in open(f,errors='replace'): arch.append(json.loads(l))
now=max(r['ts'] for r in arch); lo=now-30*86400
A=[r for r in arch if r['ts']>=lo and r.get('tool_name')=='Bash']
vb=collections.defaultdict(list)
for l in open('/Users/chrisren/.claude/logs/validate-bash-decisions.jsonl'):
    r=json.loads(l)
    if r['decision']=='ask': vb[r['sid']].append(r['ts'])
cg=collections.defaultdict(list)
for l in open('/Users/chrisren/.reso/curl-audit.jsonl'):
    r=json.loads(l)
    if r['decision']=='ask':
        cg[r['session_id']].append(datetime.datetime.strptime(r['ts'],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp())
for d in (vb,cg):
    for k in d: d[k].sort()
def hit(d,sid,t,w=15):
    L=d.get(sid) or []
    i=bisect.bisect_left(L,t-w); return i<len(L) and L[i]<=t+w
c=collections.Counter()
for r in A:
    cmd=pm.command_of(r)
    if r.get('tool_input_truncated') or not cmd: s='trunc'
    else:
        dec=pm.split_leaves(cmd); s='structural' if [k for k in dec.structural if k!='bash_c'] else 'non-structural'
    h='vb' if hit(vb,r['session_id'],r['ts']) else ('curl' if hit(cg,r['session_id'],r['ts']) else '-')
    c[(s,h)]+=1
print('bash rows 30d',len(A))
for k in sorted(c): print(k,c[k])
print('--- with transcript vb asks unioned')
for l in open('asks2.jsonl'):
    r=json.loads(l)
    if (r['hook'] or '').endswith('validate-bash.sh') and r['ts']:
        vb[r['sid']].append(datetime.datetime.fromisoformat(r['ts'].replace('Z','+00:00')).timestamp())
    if (r['hook'] or '').endswith('curl-gate-scope.sh') and r['ts']:
        cg[r['sid']].append(datetime.datetime.fromisoformat(r['ts'].replace('Z','+00:00')).timestamp())
for d in (vb,cg):
    for k in d: d[k].sort()
c=collections.Counter()
for r in A:
    cmd=pm.command_of(r)
    if r.get('tool_input_truncated') or not cmd: s='trunc'
    else:
        dec=pm.split_leaves(cmd); s='structural' if [k for k in dec.structural if k!='bash_c'] else 'non-structural'
    h='vb' if hit(vb,r['session_id'],r['ts']) else ('curl' if hit(cg,r['session_id'],r['ts']) else '-')
    c[(s,h)]+=1
for k in sorted(c): print(k,c[k])
print('lo',datetime.datetime.utcfromtimestamp(lo))
