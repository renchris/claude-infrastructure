import pickle,collections,statistics as S,bisect,re
WL=lambda r: r[1]+1.25*r[2]+0.1*r[4]+5*r[5]
WM=lambda r: 1.95*r[5]+0.25*(r[2]+r[1])
CTX=lambda r: r[1]+r[2]+r[4]
T=collections.Counter(); firsts=[]; sim=collections.Counter(); gap=collections.Counter(); hand=0
for a in ['next','next2','next3','next4']:
  D=pickle.load(open(f'/tmp/usage-audit/skeptic-lp/{a}.pkl','rb')); R=D['reqs']
  for r in R: T['WL']+=WL(r); T['WM']+=WM(r)
  bys=collections.defaultdict(list)
  for r in R:
    if r[6]=='main': bys[r[7]].append(r)
  for s,L in bys.items():
    L.sort(key=lambda r:r[0])
    base=CTX(L[0]); firsts.append(base)
    # cap simulation at 250k: on crossing, hand off; successor restarts at this session's first-request context
    off=0
    for r in L:
      c=CTX(r)-off
      if c>250e3:
        off=CTX(r)-base; hand+=1
        sim['L_cost']+=1.25*base; sim['M_cost']+=0.25*base   # successor must WRITE its base prefix to cache
        c=base
      sim['L_save']+=0.1*(CTX(r)-c)   # cache_read removed; meter saving is 0 (cache_read ~free)
    for p,q in zip(L,L[1:]):
      g=q[0]-p[0]; k='<5m' if g<300 else '5m-1h' if g<3600 else '>1h'
      gap['n'+k]+=1; gap['L'+k]+=1.25*q[2]; gap['M'+k]+=0.25*q[2]
      if g<300 and q[4]<0.5*CTX(p) and CTX(q)>20000: gap['breaks']+=1
  for r in R:
    if r[6]!='main': T['M_subcc']+=0.25*r[2]; T['L_subcc']+=1.25*r[2]
print('main sessions %d; first-request context median %.0fk, p25 %.0fk, p75 %.0fk'%(len(firsts),S.median(firsts)/1e3,S.quantiles(firsts,n=4)[0]/1e3,S.quantiles(firsts,n=4)[2]/1e3))
print('250k-cap simulation: %d handoffs/week; list proxy: cache_read removed %.1f%%, successor cache-write cost %.1f%%, net %.1f%% of weight; meter: removed 0.0%%, cost %.2f%%, net -%.2f%%'%(hand,100*sim['L_save']/T['WL'],100*sim['L_cost']/T['WL'],100*(sim['L_save']-sim['L_cost'])/T['WL'],100*sim['M_cost']/T['WM'],100*sim['M_cost']/T['WM']))
for k in ('<5m','5m-1h','>1h'): print('main cache_creation after gap %s: %d req, list %.2f%%, meter %.2f%% of weight'%(k,gap['n'+k],100*gap['L'+k]/T['WL'],100*gap['M'+k]/T['WM']))
print('unexplained cache breaks (<5m gap, cache_read<50%% of prev ctx, ctx>20k): %d'%gap['breaks'])
print('subagent cache_creation: list %.1f%%, meter %.1f%% of weight'%(100*T['L_subcc']/T['WL'],100*T['M_subcc']/T['WM']))
