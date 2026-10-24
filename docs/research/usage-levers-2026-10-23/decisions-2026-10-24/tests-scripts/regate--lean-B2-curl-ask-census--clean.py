import json,sys,collections as C
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if r['ts']<'2026-09-29T00:00:00Z' and r['decision']=='ask' and r['tool_use_id']!='unknown' and r['session_id'] not in ('smoke','probe')]
def cls(s):
    if 'confirm intent' in s: return 'confirm intent'
    for k in ('GET to unknown host','GET to unvetted host','No URL parsed','Non-HTTP scheme'):
        if s.startswith(k): return k
    return 'other'
for lab,lo in (('ALL',''),('L30','2026-08-30T00:00:00Z')):
    a=[r for r in rows if r['ts']>=lo]
    print(lab,'ask rows',len(a),'prompts',len({r['tool_use_id'] for r in a}),'sessions',len({r['session_id'] for r in a}))
    for k,v in C.Counter(cls(r['reason']) for r in a).most_common(): print(f'   {v:5d} {100*v/len(a):5.1f}% {k}')
    ci=[r for r in a if 'confirm intent' in r['reason']]
    print('   CI prompts',len({r['tool_use_id'] for r in ci}),'sessions',len({r['session_id'] for r in ci}),'POST-unknown',sum(r['reason'].startswith('POST to unknown') for r in ci),'methods',C.Counter(r['method'] for r in ci).most_common(),'distinct hosts',len({r['host'] for r in ci}),'top5',C.Counter(r['host'] for r in ci).most_common(5))
