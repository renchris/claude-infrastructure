import json, sys, collections as C
rows=[json.loads(l) for l in open(sys.argv[1])]
rows=[r for r in rows if r['ts']<'2026-09-29T00:00:00Z']
a=[r for r in rows if r['decision']=='ask']
ci=[r for r in a if 'confirm intent' in r['reason']]
seen=set()
for r in ci:
    if r['reason'].split(' ')[0]!=r.get('method') or r.get('host') in ('mozilla','$h','research-agent',None,'unknown-host.example.org','yandex.com'):
        k=(r['reason'],r.get('host'),r['cmd_redacted'][:60])
        if k in seen: continue
        seen.add(k)
        print('----',r['ts'],'method=',r.get('method'),'host=',r.get('host'),'sess=',r['session_id'][:8],'tuid=',r['tool_use_id'][-8:])
        print('REASON:',r['reason'])
        c=r['cmd_redacted']; i=c.find('curl'); print('CMD:',c[max(0,i-50):i+500].replace('\n','\\n'))
# duplicates per tool_use_id
for lab,lo in (('ALL',''),('L30','2026-08-30T00:00:00Z')):
    aa=[r for r in a if r['ts']>=lo]
    cnt=C.Counter(r['tool_use_id'] for r in aa)
    multi=[k for k,v in cnt.items() if v>1]
    ident=sum(1 for k in multi if len({(r['reason'],r['cmd_redacted']) for r in aa if r['tool_use_id']==k})==1)
    print(lab,'tool_use_ids with >1 ask row',len(multi),'of which all rows identical reason+cmd',ident,'max rows',max(cnt.values()))
    print(lab,'tool_use_id values that are empty/None/short:',C.Counter(r['tool_use_id'] for r in aa if not r['tool_use_id'] or len(r['tool_use_id'])<10).most_common(5))
