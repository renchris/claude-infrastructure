import pickle,collections,sys
WL=lambda r: r[1]+1.25*r[2]+0.1*r[4]+5*r[5]
WM=lambda r: 1.95*r[5]+0.25*(r[2]+r[1])
CTX=lambda r: r[1]+r[2]+r[4]
for BASE in (61e3,74e3,120e3):
  T=collections.Counter(); sim=collections.Counter(); hand=0
  for a in ['next','next2','next3','next4']:
    R=pickle.load(open(f'/tmp/usage-audit/skeptic-lp/{a}.pkl','rb'))['reqs']
    for r in R: T['WL']+=WL(r); T['WM']+=WM(r)
    bys=collections.defaultdict(list)
    for r in R:
      if r[6]=='main': bys[r[7]].append(r)
    for s,L in bys.items():
      L.sort(key=lambda r:r[0]); off=0
      for r in L:
        if CTX(r)-off>250e3 and CTX(r)>BASE:
          off=CTX(r)-BASE; hand+=1; sim['L_cost']+=1.25*BASE; sim['M_cost']+=0.25*BASE
        sim['L_save']+=0.1*off
  print('successor base %.0fk: %d handoffs/7d; list proxy: cache_read removed %.1f%%, successor base re-write %.1f%%, net %.1f%%; meter: removed 0, re-write cost %.2f%% (net negative)'%(BASE/1e3,hand,100*sim['L_save']/T['WL'],100*sim['L_cost']/T['WL'],100*(sim['L_save']-sim['L_cost'])/T['WL'],100*sim['M_cost']/T['WM']))
