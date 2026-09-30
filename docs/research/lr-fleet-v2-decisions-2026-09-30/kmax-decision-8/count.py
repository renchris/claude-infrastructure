import json, datetime as dt, collections, os
F=json.load(open('/tmp/kmaxq/files.json'))
def P(s): return dt.datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
rows=[json.loads(l) for l in open(os.path.expanduser('~/.claude/logs/account-utilization.jsonl')) if '"ts":"2026-09-29T0' in l]
rows=[r for r in rows if '2026-09-29T04:26'<=r['ts']<'2026-09-29T06:22']
print(f"{'ts':8} {'acct':5} {'k':>3} {'kw':>4} | {'top':>3} {'sub':>3} {'tot':>3} | lbSub=kw-min(k,kw) | capTop=min(top,k)+sub | wall_log wall_recon_capped")
agg=collections.Counter()
for r in rows:
    T=P(r['ts']); a=r['acct']
    hit=[f for f in F if f['acct']==a and any(T-600<t<=T for t in f['ts'])]
    top=sum(f['top'] for f in hit); sub=len(hit)-top
    k=r['k']; kw=r['k_work']
    lb = (kw-min(k,kw)) if (k is not None and kw is not None) else None
    cap = (min(top,k)+sub) if k is not None else None
    wl = kw is not None and kw>=8
    wr = cap is not None and cap>=8
    wtop = k is not None and min(top,k)>=8
    print(f"{r['ts'][11:19]} {a:5} {str(k):>3} {str(kw):>4} | {top:>3} {sub:>3} {len(hit):>3} | {str(lb):>4} | {str(cap):>4} | {int(wl)} {int(wr)} topOnlyWall={int(wtop)} src={r['k_src']}")
    if kw is not None:
        agg['rows_work']+=1; agg['kw']+=kw; agg['lb']+=lb; agg['wall_log']+=wl
        agg['recon_sub']+=sub; agg['recon_top']+=top; agg['recon_tot']+=len(hit)
        if wl:
            agg['wall_kw']+=kw; agg['wall_lb']+=lb; agg['wall_sub']+=sub; agg['wall_tot']+=len(hit); agg['wall_top_capped']+=min(top,k)
            agg['wall_rows_still_wall_if_kw_capped_at_k']+= (min(kw,k)>=8)
            agg['wall_rows_still_wall_top_only']+= (min(top,k)>=8)
print(dict(agg))
print('---')
import collections
w=collections.Counter(); wf=0; ag=0
for r in rows:
    kw=r['k_work']; k=r['k']
    if kw is None or kw<8: continue
    T=P(r['ts']); a=r['acct']
    hit=[f for f in F if f['acct']==a and any(T-600<t<=T for t in f['ts'])]
    sub=[f for f in hit if not f['top']]
    wf+=sum('/workflows/' in f['path'] for f in sub); ag+=sum('/workflows/' not in f['path'] for f in sub)
    w[a]+=1; w['sub_bounded']+=min(len(sub),kw)
    top=[f for f in hit if f['top']]
    sdk=0
    for f in top:
        for line in open(f['path']):
            try:o=json.loads(line)
            except: continue
            if o.get('entrypoint'): sdk+= o['entrypoint']=='sdk-cli'; break
    w['top_sdk']+=sdk; w['top_all']+=len(top)
print(dict(w),'workflow_sub',wf,'agent_sub',ag)
