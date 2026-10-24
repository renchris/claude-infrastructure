import json, sys, collections as C
rows=[]; bad=0
for ln in open(sys.argv[1]):
    try: r=json.loads(ln)
    except Exception: bad+=1; continue
    if r.get('ts','')<'2026-09-29T00:00:00Z': rows.append(r)
print('rows<cutoff',len(rows),'unparseable lines',bad)
def cls(rs):
    s=rs.get('reason','')
    if 'confirm intent' in s: return 'confirm intent'
    for k in ('GET to unknown host','GET to unvetted host','No URL parsed','Non-HTTP scheme'):
        if s.startswith(k): return k
    return 'OTHER: '+s.split(' ')[0]+' '+' '.join(s.split(' ')[1:4])
for label,lo in (('ALL',''),('LAST30','2026-08-30T00:00:00Z')):
    a=[r for r in rows if r['decision']=='ask' and r['ts']>=lo]
    print('\n==',label,'ask rows',len(a),'distinct tool_use_id',len({r.get('tool_use_id') for r in a}),'sessions',len({r.get('session_id') for r in a}))
    cc=C.Counter(cls(r) for r in a)
    for k,v in cc.most_common(): print(f'  {v:6d} {100*v/len(a):5.1f}%  {k}')
    ci=[r for r in a if 'confirm intent' in r['reason']]
    print('  confirm-intent prompts',len({r.get('tool_use_id') for r in ci}),'sessions',len({r.get('session_id') for r in ci}))
    print('  split POST-unknown',sum(r['reason'].startswith('POST to unknown host') for r in ci),'METHOD host',sum(not r['reason'].startswith('POST to unknown host') for r in ci))
    print('  method field',C.Counter(r.get('method') for r in ci).most_common())
    print('  reason-leading-word',C.Counter(r['reason'].split(' ')[0] for r in ci).most_common())
    hc=C.Counter(r.get('host') for r in ci)
    print('  distinct hosts',len(hc),'top5',hc.most_common(5))
    print('  all hosts',hc.most_common())
    mism=[r for r in ci if r['reason'].split(' ')[0]!=r.get('method')]
    print('  method!=reason-method rows',len(mism))
    for r in mism[:8]: print('    ',r['ts'],r.get('method'),'|',r['reason'][:80],'|',r['cmd_redacted'][:120])
    hm=[r for r in ci if r.get('host') and r['host'] not in r['reason']]
    print('  host field not in reason rows',len(hm))
    for r in hm[:5]: print('    ',r['ts'],r.get('host'),'|',r['reason'][:80])
