import json,sys,statistics as st,collections
rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]
def ok(r, tol=3):
    a=r.get('answer'); t=r['truth']
    if not a: return False
    ap,al=a.rsplit(':',1); tp,tl=t.rsplit(':',1)
    ap=ap.lstrip('./')
    return ap==tp and abs(int(al)-int(tl))<=tol
by=collections.defaultdict(list)
for r in rows: by[r['arm']].append(r)
print(f"{'arm':28} {'n':>3} {'correct':>8} {'exact':>6} {'path':>5} {'fail':>4} {'med_out':>8} {'med_turns':>9} {'med_wall':>8} served")
for arm in sorted(by):
    rs=by[arm]; n=len(rs)
    c=sum(ok(r) for r in rs); ex=sum(ok(r,0) for r in rs)
    pth=sum(1 for r in rs if r.get('answer') and r['answer'].rsplit(':',1)[0].lstrip('./')==r['truth'].rsplit(':',1)[0])
    fail=sum(1 for r in rs if r.get('failed') or r.get('is_error'))
    out=[r['output_tokens'] for r in rs if r.get('output_tokens') is not None]
    tu=[r['num_turns'] for r in rs if r.get('num_turns') is not None]
    wl=[r['wall'] for r in rs if r.get('wall') is not None]
    sv=collections.Counter(m for r in rs for m in (r.get('served') or []))
    print(f"{arm:28} {n:>3} {c:>8} {ex:>6} {pth:>5} {fail:>4} {st.median(out) if out else '-':>8} {st.median(tu) if tu else '-':>9} {st.median(wl) if wl else '-':>8} {dict(sv)}")
if len(sys.argv)>2:
    qs=sorted(set(r['qid'] for r in rows))
    print('per-question correct (of reps) by arm:')
    arms=sorted(by)
    print('qid'.ljust(10)+' '.join(a.split('@')[0][-8:]+'@'+a.split('@')[1][:3] for a in arms))
    for q in qs:
        print(q.ljust(10)+' '.join(f"{sum(ok(r) for r in by[a] if r['qid']==q)}/{sum(1 for r in by[a] if r['qid']==q)}".rjust(15) for a in arms))
