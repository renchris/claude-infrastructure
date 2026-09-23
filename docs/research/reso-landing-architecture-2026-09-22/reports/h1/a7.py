import pickle, re, json, subprocess, datetime as dt, collections as C, itertools, random
exec(open('/tmp/rla/wave1/h1/a6.py').read().split("for x in res: print(x)")[0])  # reuse res, files, lands, own
g=pickle.load(open('/tmp/rla/wave1/h1/graph.pkl','rb')); deps=g['deps']
TEST=re.compile(r'^(src/.*\.test\.tsx?|lib/.*\.test\.tsx?|tests/.*\.test\.ts|eslint-rules/.*\.test\.ts|scripts/tests/.*\.test\.ts|scripts/__tests__/.*\.test\.ts)$')
tests=[p for p in deps if TEST.match(p)]
memo={}
def clos(p):
    if p in memo: return memo[p]
    seen={p}; st=[p]
    while st:
        x=st.pop()
        for y in deps.get(x,()):
            if y not in seen: seen.add(y); st.append(y)
    memo[p]=seen; return seen
TC={t:clos(t) for t in tests}
ESC=re.compile(r'^(package\.json|pnpm-lock\.yaml|vitest\.(config|setup)\.[cm]?[jt]s|tsconfig[^/]*\.json|next\.config\.[cm]?js|\.nvmrc)$')
def conflict(Fm,Fi):
    if any(ESC.match(f) for f in Fm|Fi): return ('escalate',None,None)
    tt=[t for t,c in TC.items() if (c&Fm) and (c&Fi)]
    # tsc joint dependents among all source files
    ts=[x for x in deps if (clos(x)&Fm) and (clos(x)&Fi)]
    return ('ok',tt,ts)
print('tests in graph',len(tests))
# (1) lost rounds: recompute with own/incoming sets
out=[]
for r in w:
    pass
# rebuild lost-round (Fm,Fi) pairs quickly from res by branch names is lossy; recompute:
pairs=[]
for r in w:
    pr=r['per_round']
    if not pr: continue
    end=t(r['ts_end'])-2; wins=[]
    for i in range(len(pr)-1,-1,-1):
        d=dur(pr[i]); s=end-d; wins.append((i,s,end,pr[i])); end=s-3.5
    myf=own(r)
    for i,s,e,p in wins:
        tail=p.get('push_tail') or ''
        if p.get('push_rc') in (None,0) or not (p['rc']==99 or 'cannot lock ref' in tail): continue
        comp=[x for tt,x in land_t if s<tt<e and x['branch']!=r['branch']]
        inc=set().union(*[files.get(x['head'],set()) for x in comp]) if comp else set()
        pairs.append((r['branch'][:22],i+1,myf,inc))
cnt=C.Counter()
for b,i,Fm,Fi in pairs:
    k,tt,ts=conflict(Fm,Fi)
    tag=k if k!='ok' else ('suite-disjoint' if not tt else 'suite-joint')
    tag2='' if k!='ok' else ('tsc-disjoint' if not ts else 'tsc-joint')
    cnt[(tag,tag2)]+=1
    print(b,i,tag,len(tt or []),(tt or [])[:2],tag2,len(ts or []))
print('LOST ROUNDS:',cnt)
# (2) base rate over all ordered pairs of lands within 60 min of each other
L=[(t(r['ts_end']),files.get(r['head'],set()),r) for r in lands]
base=C.Counter()
for (ta,Fa,ra),(tb,Fb,rb) in itertools.combinations(L,2):
    if abs(tb-ta)>3600 or ra['branch']==rb['branch']: continue
    k,tt,ts=conflict(Fa,Fb)
    base[(k if k!='ok' else ('suite-disjoint' if not tt else 'suite-joint'), '' if k!='ok' else ('tsc-disjoint' if not ts else 'tsc-joint'))]+=1
print('LAND PAIRS within 60 min:',base)
