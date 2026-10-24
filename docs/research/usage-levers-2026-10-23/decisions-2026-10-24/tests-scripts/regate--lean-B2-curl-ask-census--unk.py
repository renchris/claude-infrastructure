import json, sys, collections as C
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if r['ts']<'2026-09-29T00:00:00Z']
u=[r for r in rows if r['tool_use_id']=='unknown']
print('all rows with tool_use_id=unknown',len(u),'decisions',C.Counter(r['decision'] for r in u),'ts range',min(r['ts'] for r in u),max(r['ts'] for r in u))
ua=[r for r in u if r['decision']=='ask']
print('unknown ask rows',len(ua),'sessions',len({r['session_id'] for r in ua}),C.Counter(r['session_id'] for r in ua).most_common(5))
def cls(s):
    if 'confirm intent' in s: return 'confirm intent'
    for k in ('GET to unknown host','GET to unvetted host','No URL parsed','Non-HTTP scheme'):
        if s.startswith(k): return k
    return 'other'
print('unknown ask by class',C.Counter(cls(r['reason']) for r in ua))
print('first unknown ts',min(r['ts'] for r in rows if r['tool_use_id']=='unknown'),'last real tuid ts', max(r['ts'] for r in rows if r['tool_use_id'].startswith('toolu')))
# test/probe sessions
ts=[r for r in rows if r['decision']=='ask' and not (len(r['session_id'])==36)]
print('ask rows with non-uuid session_id',C.Counter(r['session_id'] for r in ts))
for lab,lo in (('ALL',''),('L30','2026-08-30T00:00:00Z')):
    a=[r for r in rows if r['decision']=='ask' and r['ts']>=lo]
    known={r['tool_use_id'] for r in a if r['tool_use_id']!='unknown'}
    nu=sum(r['tool_use_id']=='unknown' for r in a)
    ci=[r for r in a if 'confirm intent' in r['reason']]
    ck={r['tool_use_id'] for r in ci if r['tool_use_id']!='unknown'}; cu=sum(r['tool_use_id']=='unknown' for r in ci)
    print(lab,'ask: distinct real tuid',len(known),'+ unknown-tuid rows',nu,'=> prompts between',len(known)+ (1 if nu else 0),'and',len(known)+nu)
    print(lab,'CI : distinct real tuid',len(ck),'+ unknown-tuid rows',cu)
# nanaimo cmd full
for r in rows:
    if r['ts']=='2026-09-10T13:48:52Z': c=r['cmd_redacted']; print('nanaimo curl count',c.count('curl'),[c[i:i+120] for i in range(len(c)) if c.startswith('curl',i)][:4])
