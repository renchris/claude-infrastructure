import json,sys,re,statistics as st,collections
truth=json.load(open('truth.json'))
rows=[json.loads(l) for l in open('results.jsonl') if l.strip()]
def parse(t):
    if not t: return None
    i=t.find('['); j=t.rfind(']')
    if i<0 or j<0: return None
    try: return json.loads(t[i:j+1])
    except Exception: return None
by=collections.defaultdict(list)
for r in rows:
    T=truth[r['file']]; tp={(k,v) for k,vs in T.items() for v in vs}; tn=set(T)
    p=parse(r.get('result')); 
    if p is None: r.update(parsed=False, pr=0, pp=0, nr=0, np=0); by[r['arm']].append(r); continue
    gp={(str(e.get('name')),str(e.get('default'))) for e in p if isinstance(e,dict)}; gn={a for a,_ in gp}
    r.update(parsed=True, tp=len(tp), hit=len(gp&tp), got=len(gp), nhit=len(gn&tn), ngot=len(gn), nt=len(tn))
    by[r['arm']].append(r)
print(f"{'arm':26} {'n':>3} {'parsed':>6} {'pair_R':>7} {'pair_P':>7} {'name_R':>7} {'name_P':>7} {'perfect':>7} {'med_out':>8} {'med_wall':>8} served")
for a in sorted(by):
    rs=by[a]; ok=[r for r in rs if r.get('parsed')]
    H=sum(r['hit'] for r in ok); T=sum(r['tp'] for r in rs if 'tp' in r) or sum(sum(len(v) for v in truth[r['file']].values()) for r in rs); G=sum(r['got'] for r in ok)
    NH=sum(r['nhit'] for r in ok); NT=sum(len(truth[r['file']]) for r in rs); NG=sum(r['ngot'] for r in ok)
    perfect=sum(1 for r in ok if r['hit']==r['tp'] and r['got']==r['tp'])
    out=[r['output_tokens'] for r in rs if r.get('output_tokens') is not None]; wl=[r['wall'] for r in rs if r.get('wall')]
    sv=collections.Counter(m for r in rs for m in (r.get('served') or []))
    print(f"{a:26} {len(rs):>3} {len(ok):>6} {H/T:>7.3f} {H/max(G,1):>7.3f} {NH/NT:>7.3f} {NH/max(NG,1):>7.3f} {perfect:>7} {st.median(out):>8} {st.median(wl):>8} {dict(sv)}")
# per-file misses for haiku
for a in sorted(by):
    miss=collections.Counter()
    for r in by[a]:
        if r.get('parsed') and r['hit']<r['tp']: miss[r['file']]+=r['tp']-r['hit']
    print(a, dict(miss))
