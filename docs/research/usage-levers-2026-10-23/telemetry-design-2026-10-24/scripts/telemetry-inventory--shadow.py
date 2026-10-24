import json,collections,os
L=os.path.expanduser('~/.claude/logs/')
def rows(f):
    for l in open(L+f):
        try: yield json.loads(l)
        except: pass
r=list(rows('idle-recycle-shadow.jsonl'))
print('IRS',len(r),'ts',min(x['ts'] for x in r),max(x['ts'] for x in r),'sids',len({x.get('sid') for x in r}))
print(' v',collections.Counter(x.get('v') for x in r),'would_advise',sum(bool(x.get('would_advise')) for x in r),'k2',sum(bool(x.get('would_advise_k2')) for x in r),'guarded_k2',sum(bool(x.get('guarded_k2')) for x in r),'has_k2_field',sum('would_advise_k2' in x for x in r))
print(' cfg',collections.Counter(x.get('config_dir') for x in r))
g=list(rows('idle-keepalive.jsonl'))
print('IKA',len(g),collections.Counter((x.get('kind'),x.get('v')) for x in g))
print(' ts',min(x.get('ts','') for x in g),max(x.get('ts','') for x in g),'acct',collections.Counter(x.get('acct') for x in g))
print(' outcome',collections.Counter(x.get('outcome') for x in g if x.get('kind')=='gap'))
print(' wake-row keys',sorted({k for x in g if x.get('kind')!='gap' for k in x})[:40])
w=list(rows('workflow-lean-shadow.jsonl'))
print('WLS',len(w),'ts',min(x['ts'] for x in w),max(x['ts'] for x in w),'sessions',len({x.get('session_id') for x in w}),'would_deny',sum(bool(x.get('would_deny')) for x in w),'resume',sum(bool(x.get('resume_from_run_id')) for x in w),'parse',collections.Counter(x.get('parse') for x in w))
s=list(rows('subagent-long-bash.jsonl'))
print('SLB',len(s),'ts',min(x['ts'] for x in s),max(x['ts'] for x in s),collections.Counter(x.get('v') for x in s),'acct',collections.Counter(x.get('acct') for x in s))
print(' why',collections.Counter(x.get('why') for x in s),'class',collections.Counter(x.get('would_deny_class') for x in s),'exempt',collections.Counter(x.get('exempt') for x in s))
