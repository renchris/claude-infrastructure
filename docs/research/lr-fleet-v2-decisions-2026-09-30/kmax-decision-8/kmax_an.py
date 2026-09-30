import json,collections,datetime as dt,sys
P=lambda s: dt.datetime.fromisoformat(s.replace('Z','+00:00'))
since=sys.argv[1] if len(sys.argv)>1 else '2026-08-16T10:26'
rows=[]
for l in open('/Users/chrisren/.claude/logs/account-utilization.jsonl'):
    try: r=json.loads(l)
    except: continue
    if r.get('ts','')>=since: rows.append(r)
# sweeps: cluster rows within 60s
rows.sort(key=lambda r:r['ts'])
sweeps=[];cur=None
for r in rows:
    t=P(r['ts'])
    if cur and (t-cur['t0']).total_seconds()<90 and r['acct'] not in cur['s']:
        cur['s'][r['acct']]=r
    else:
        cur={'t0':t,'s':{r['acct']:r}}; sweeps.append(cur)
def limited(r):
    return (r.get('session_pct') or 0)>=100 or (r.get('weekly_pct') or 0)>=100 or r.get('wire_5h_status')=='rejected' or r.get('wire_7d_status')=='rejected'
def elig(r):
    s=r.get('session_pct') or 0; w=r.get('weekly_pct') or 0
    return r.get('auth')=='ok' and s<60 and w<=90 and not limited(r)
full=[x for x in sweeps if len(x['s'])==4 and all(r.get('k_work') is not None for r in x['s'].values())]
storm=[x for x in full if any(limited(r) for r in x['s'].values())]
print('since',since,'sweeps',len(sweeps),'all-4-measured',len(full),'storm (>=1 limited)',len(storm))
for K in (8,10,12,16):
    wall=0; seats=[]; anyb=0
    for x in storm:
        el=[r for r in x['s'].values() if elig(r)]
        if not el: continue
        cap=sum(max(0,K-r['k_work']) for r in el)
        seats.append(cap)
        if all(r['k_work']>=K for r in el): wall+=1
        if any(r['k_work']>=K for r in el): anyb+=1
    ss=sorted(seats); n=len(ss)
    print(f'K={K}: storm sweeps w/ eligible acct {n}; any-eligible-acct-bound {anyb} ({100*anyb/max(n,1):.1f}%); ALL-eligible-bound (0 seats) {wall} ({100*wall/max(n,1):.1f}%); seats p10 {ss[int(n*.1)] if n else None} p50 {ss[n//2] if n else None}')
noel=sum(1 for x in storm if not any(elig(r) for r in x['s'].values()))
print('storm sweeps with NO eligible acct (quota wall, KMAX irrelevant)',noel)
print('--- wall episodes (consecutive measured storm sweeps where every eligible acct k_work>=K; gap<=15min joins)')
for K in (8,12,16):
    eps=[];cur=None
    for x in storm:
        el=[r for r in x['s'].values() if elig(r)]
        w= bool(el) and all(r['k_work']>=K for r in el)
        if w:
            if cur and (x['t0']-cur[1]).total_seconds()<=900: cur[1]=x['t0']; cur[2]+=1
            else:
                cur=[x['t0'],x['t0'],1]; eps.append(cur)
        else:
            if cur and (x['t0']-cur[1]).total_seconds()<=900:
                cur[3:]= [x['t0']]  # first non-wall sweep ends the episode
            cur=None
    durs=[]
    for e in eps:
        end=e[3] if len(e)>3 else e[1]
        durs.append((end-e[0]).total_seconds()/60)
    ds=sorted(durs); n=len(ds)
    print(f'K={K}: episodes {n}; total wall-min (upper, first wall sweep -> first free sweep) {sum(ds):.0f}; p50 {ds[n//2] if n else 0:.0f} p90 {ds[int(n*.9)] if n else 0:.0f} max {ds[-1] if n else 0:.0f}; days with an episode {len(set(e[0].date() for e in eps))}')
print('--- session_pct of kmax-bound eligible accts in K=8 wall sweeps')
sp=[]
for x in storm:
    el=[r for r in x['s'].values() if elig(r)]
    if el and all(r['k_work']>=8 for r in el): sp += [r.get('session_pct') or 0 for r in el]
sp.sort(); n=len(sp)
print('n',n,'p50',sp[n//2],'p90',sp[int(n*.9)],'>=45 (within 15pp of RECOVERY_S_CEIL 60)',sum(1 for s in sp if s>=45))
print('--- k_work of bound accts in K=8 wall sweeps')
kk=sorted(r['k_work'] for x in storm for r in x['s'].values() if elig(r) and all(q['k_work']>=8 for q in x['s'].values() if elig(q)))
n=len(kk); print('n',n,'p25',kk[n//4],'p50',kk[n//2],'p75',kk[3*n//4],'max',kk[-1], 'in 8-11',sum(1 for k in kk if k<12),'in 12-15',sum(1 for k in kk if 12<=k<16),'>=16',sum(1 for k in kk if k>=16))
