import pickle,collections,statistics as S
# re-weight the other agent's own deduped rows (v2.pkl) under the repo's measured meter price list
WL=lambda r: r[2]+1.25*r[3]+0.1*r[4]+5*r[5]
WM=lambda r: 1.95*r[5]+0.25*(r[3]+r[2])          # tm2 REPORT M1: 1.95 pp/Mtok out, 0.25 cc, cache_read ~0
tot=collections.Counter()
first=[]; 
for a in ['next','next2','next3','next4']:
  R=pickle.load(open(f'/tmp/usage-audit/{a}.v2.pkl','rb'))['reqs']
  for r in R:
    tot['n']+=1; tot['WL']+=WL(r); tot['WM']+=WM(r)
    tot['L_in']+=r[2]; tot['L_cc']+=1.25*r[3]; tot['L_cr']+=0.1*r[4]; tot['L_out']+=5*r[5]
    tot['cr']+=r[4]; tot['cc']+=r[3]; tot['out']+=r[5]; tot['inp']+=r[2]
    if r[7]=='main':
      tot['WL_main']+=WL(r); tot['WM_main']+=WM(r)
      for c in (200,250):
        tot[f'L_ex{c}']+=0.1*max(0,r[1]-c*1000)
print('requests',tot['n'])
print('list-proxy weight shares: input %.1f%% cc %.1f%% cache_read %.1f%% output %.1f%%'%tuple(100*tot[k]/tot['WL'] for k in ('L_in','L_cc','L_cr','L_out')))
print('main-thread share of weight: list %.1f%%  meter %.1f%%'%(100*tot['WL_main']/tot['WL'],100*tot['WM_main']/tot['WM']))
print('cap>250k saving bound under list %.1f%%; under meter (cache_read=0) 0.0%%'%(100*tot['L_ex250']/tot['WL']))
print('token volume: cache_read %.2fB (%.1f%% of tokens), cc %.2fB, out %.3fB, in %.3fB'%(tot['cr']/1e9,100*tot['cr']/(tot['cr']+tot['cc']+tot['out']+tot['inp']),tot['cc']/1e9,tot['out']/1e9,tot['inp']/1e9))
