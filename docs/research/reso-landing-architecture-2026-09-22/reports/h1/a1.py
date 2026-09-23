import json, datetime as dt, collections as C, re
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
t=lambda s: dt.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ')
cut=t('2026-09-16T04:59:00Z'); w=[r for r in rows if t(r['ts_start'])>=cut]
print('attempts',len(w),'lands',sum(r['exit']==0 for r in w))
print('exit classes',C.Counter((r['exit'],r['exit_class']) for r in w).most_common())
print('ship_class',C.Counter(r['ship_class'] for r in w))
print('rounds dist',C.Counter(r['rounds'] for r in w))
print('lane',C.Counter(r['lane'] for r in w))
# per round
allr=[(r,i,pr) for r in w for i,pr in enumerate(r['per_round'])]
print('rounds total',len(allr))
print('suite_mode',C.Counter(pr.get('suite_mode') for r,i,pr in allr))
print('round rc',C.Counter(pr.get('rc') for r,i,pr in allr))
print('tsc_skipped',C.Counter(pr.get('tsc_skipped') for r,i,pr in allr))
# show every rejected round with context
for r,i,pr in allr:
    if pr.get('push_rc') not in (None,0) or pr.get('rc') not in (0,):
        tail=(pr.get('push_tail') or '').replace('\n',' | ')[-150:]
        print(r['ts_start'],r['branch'][:28],'rnd',i+1,'/',r['rounds'],'rc',pr.get('rc'),'prc',pr.get('push_rc'),'mode',pr.get('suite_mode'),'rec',pr.get('reconcile_s'),'tsc',pr.get('tsc_s'),'sem',pr.get('sem_wait_s'),'suite',pr.get('suite_s'),'push',pr.get('push_s'),'L',r['load1_entry'],'|',tail[-110:])
