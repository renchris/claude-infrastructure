import json,collections,datetime,bisect
tok=json.load(open('next3-minute-tokens.json'))
ev=[]  # (dt, model, dict)
for r in tok:
    dt=datetime.datetime.fromisoformat(r['hour']+':00+00:00')
    ev.append((dt,r['model'],r))
ev.sort(key=lambda x:x[0])
times=[e[0] for e in ev]
rows=[]
for line in open('/Users/chrisren/.claude/logs/account-utilization.jsonl'):
    try: d=json.loads(line)
    except: continue
    if d.get('acct')!='next3' or d.get('weekly_pct') is None: continue
    if not d['ts'].startswith('2026-09-'): continue
    rows.append(d)
rows.sort(key=lambda d:d['ts'])
def P(s): return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
segs=[]
for i in range(1,len(rows)):
    a,b=rows[i-1],rows[i]
    if a['weekly_reset_at']!=b['weekly_reset_at']: continue
    ta,tb=P(a['ts']),P(b['ts'])
    gap=(tb-ta).total_seconds()
    if gap<=0 or gap>3600*2: continue
    dw=b['weekly_pct']-a['weekly_pct']; df=(b.get('fable_pct') or 0)-(a.get('fable_pct') or 0)
    if dw<0 or df<0: continue
    lo=bisect.bisect_left(times,ta); hi=bisect.bisect_left(times,tb)
    agg=collections.defaultdict(collections.Counter)
    for j in range(lo,hi):
        _,m,r=ev[j]
        c=agg[m]
        for k in ('in','out','cc','cr','n'): c[k]+=r[k]
    segs.append({'t0':a['ts'],'t1':b['ts'],'gap_s':gap,'dw':dw,'df':df,
                 'models':{m:dict(c) for m,c in agg.items()}})
print("segments:",len(segs),"covering", sum(s['gap_s'] for s in segs)/3600,"h")
def tot(d): return d.get('in',0)+d.get('out',0)+d.get('cc',0)+d.get('cr',0)
FA='claude-fable-5-1'; OP='claude-opus-5'
fonly=[s for s in segs if tot(s['models'].get(FA,{}))>0 and sum(tot(v) for k,v in s['models'].items() if k!=FA)==0]
oonly=[s for s in segs if tot(s['models'].get(OP,{}))>0 and sum(tot(v) for k,v in s['models'].items() if k!=OP)==0]
print("fable-ONLY segments:",len(fonly),"  opus-ONLY segments:",len(oonly))
def summ(name,S,M):
    dw=sum(s['dw'] for s in S); df=sum(s['df'] for s in S)
    c=collections.Counter()
    for s in S:
        for k,v in s['models'].get(M,{}).items(): c[k]+=v
    T=c['in']+c['out']+c['cc']+c['cr']
    hrs=sum(s['gap_s'] for s in S)/3600
    print(f"\n{name}: n={len(S)} seg, {hrs:.1f}h  Δweekly={dw}pp Δfable={df}pp")
    print(f"   tokens: in={c['in']:,} cache_create={c['cc']:,} cache_read={c['cr']:,} out={c['out']:,}  TOTAL={T:,}")
    if dw>0:
        print(f"   → {T/dw:,.0f} total tok / 1pp weekly ; {c['out']/dw:,.0f} out-tok / 1pp weekly ; {(c['cc']+c['in'])/dw:,.0f} fresh-in/1pp")
    if df>0:
        print(f"   → {T/df:,.0f} total tok / 1pp FABLE ; {c['out']/df:,.0f} out-tok / 1pp fable")
    return dw,df,c,T
summ("FABLE-ONLY",fonly,FA); summ("OPUS-ONLY",oonly,OP)
json.dump(segs,open('next3-segments.json','w'))
