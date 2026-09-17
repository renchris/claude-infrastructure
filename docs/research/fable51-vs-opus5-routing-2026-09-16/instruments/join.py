import json,collections,datetime
tok=json.load(open('next3-hourly-tokens.json'))
byhour=collections.defaultdict(lambda: collections.defaultdict(lambda: collections.Counter()))
for r in tok:
    c=byhour[r['hour']][r['model']]
    for k in ('in','out','cc','cr','n'): c[k]+=r[k]
# quota series
rows=[]
for line in open('/Users/chrisren/.claude/logs/account-utilization.jsonl'):
    try: d=json.loads(line)
    except: continue
    if d.get('acct')!='next3': continue
    if d.get('weekly_pct') is None: continue
    if not d['ts'].startswith('2026-09-'): continue
    rows.append(d)
rows.sort(key=lambda d:d['ts'])
# per hour: last sample
hq={}
for d in rows: hq[d['ts'][:13]]=d
hours=sorted(hq)
print("quota hours:",len(hours), hours[0], hours[-1])
recs=[]
for i in range(1,len(hours)):
    h0,h1=hours[i-1],hours[i]
    a,b=hq[h0],hq[h1]
    # skip across weekly reset
    if a['weekly_reset_at']!=b['weekly_reset_at']: continue
    # skip non-adjacent hours (gap) -> still ok, tokens attributed to h1 only; require adjacency
    t0=datetime.datetime.fromisoformat(h0+':00:00'); t1=datetime.datetime.fromisoformat(h1+':00:00')
    if (t1-t0).total_seconds()!=3600: continue
    dw=b['weekly_pct']-a['weekly_pct']; df=(b.get('fable_pct') or 0)-(a.get('fable_pct') or 0)
    if dw<0 or df<0: continue
    m=byhour.get(h1,{})
    op=m.get('claude-opus-5',collections.Counter())
    fa=m.get('claude-fable-5-1',collections.Counter())
    other=sum(sum(v[k] for k in ('in','out','cc','cr')) for kk,v in m.items() if kk not in ('claude-opus-5','claude-fable-5-1'))
    recs.append({'h':h1,'dw':dw,'df':df,
        'op_tot':op['in']+op['out']+op['cc']+op['cr'],'fa_tot':fa['in']+fa['out']+fa['cc']+fa['cr'],
        'op':dict(op),'fa':dict(fa),'other':other})
print("paired hours:",len(recs))
fonly=[r for r in recs if r['fa_tot']>0 and r['op_tot']==0 and r['other']==0]
oonly=[r for r in recs if r['op_tot']>0 and r['fa_tot']==0 and r['other']==0]
both=[r for r in recs if r['op_tot']>0 and r['fa_tot']>0]
print("fable-only hours:",len(fonly)," opus-only hours:",len(oonly)," mixed:",len(both))
def summ(name,S):
    dw=sum(r['dw'] for r in S); df=sum(r['df'] for r in S)
    tot=sum(r['op_tot']+r['fa_tot'] for r in S)
    cr=sum(r['op'].get('cr',0)+r['fa'].get('cr',0) for r in S)
    out=sum(r['op'].get('out',0)+r['fa'].get('out',0) for r in S)
    inp=sum(r['op'].get('in',0)+r['fa'].get('in',0) for r in S)
    cc=sum(r['op'].get('cc',0)+r['fa'].get('cc',0) for r in S)
    print(f"{name}: hours={len(S)} Δweekly={dw}pp Δfable={df}pp tokens={tot:,} (in={inp:,} cc={cc:,} cr={cr:,} out={out:,})")
    if dw: print(f"   tokens per 1pp weekly = {tot/dw:,.0f}   out-tokens per 1pp weekly = {out/dw:,.0f}")
    return dw,tot,out,inp,cc,cr
print(); summ("FABLE-ONLY",fonly); summ("OPUS-ONLY",oonly)
json.dump(recs,open('next3-hourly-joined.json','w'))
