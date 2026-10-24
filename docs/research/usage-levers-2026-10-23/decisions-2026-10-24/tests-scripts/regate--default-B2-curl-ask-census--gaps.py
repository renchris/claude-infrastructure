import json, sys, collections
from datetime import date, datetime, timedelta
CUT="2026-09-29T00:00:00Z"; W30="2026-08-30T00:00:00Z"
rows=[json.loads(l) for l in open(sys.argv[1], encoding="utf-8")]
pre=[r for r in rows if r['ts']<CUT]
days=sorted({r['ts'][:10] for r in pre}); dset=set(days)
d0=date.fromisoformat(days[0]); dend=date(2026,9,28)
print("first", days[0], "last", days[-1], "days with rows", len(days), "of", (dend-d0).days+1)
d=d0; run=None; gaps=[]
while d<=dend:
    if d.isoformat() not in dset:
        run = run or d
    else:
        if run and (d-run).days>=3: gaps.append((run, d-timedelta(1), (d-run).days))
        run=None
    d+=timedelta(1)
if run and (dend-run).days+1>=3: gaps.append((run,dend,(dend-run).days+1))
for g in gaps: print("GAP", g[0], "..", g[1], g[2], "days")
w=[r for r in pre if r['ts']>=W30]; wd={r['ts'][:10] for r in w}
print("30d window: days 2026-08-30..2026-09-28 = 30; days with rows", len(wd), "; missing", sorted({(date(2026,8,30)+timedelta(i)).isoformat() for i in range(30)}-wd))
last_get_unknown=max(r['ts'] for r in pre if r['decision']=='ask' and r['reason'].startswith('GET to unknown host') and r['session_id']!='smoke')
first_unvetted=min(r['ts'] for r in pre if r['reason'].startswith('GET to unvetted host'))
print("last 'GET to unknown host' ask:", last_get_unknown, " first 'GET to unvetted host':", first_unvetted)
print("ask rows per day in 30d (clean):", sorted(collections.Counter(r['ts'][:10] for r in w if r['decision']=='ask' and r['tool_use_id']!='unknown').items()))
