import json,collections,statistics as s
T=json.load(open('T.json'))
W,O=0.245,0.404
def q(xs,p):
    xs=sorted(xs); return xs[min(len(xs)-1,int(p*len(xs)))]
for k in ['job:watch:failed','job:watch:completed','goal','job:bash:completed','prompt']:
    L=[t for t in T if t['kind']==k]
    if not L: continue
    f=lambda c:[t[c] for t in L if t[c] is not None]
    ov=[(t['cw']*W+t['out']*O)/1e6 for t in L]
    one=sum(t['nreq']==1 for t in L)/len(L)
    la=[t for t in L if t['idle_after']>=3300]
    print('%-22s n=%5d nreq med %s mean %.2f | cw med %s mean %.0f | out med %s mean %.0f | grow_own med %s mean %.0f | grow_next med %s mean %.0f | w+o pp med %.4f mean %.4f | 1req %.2f | recap after (idle>=3300) %d/%d'%(
      k,len(L),q(f('nreq'),.5),s.mean(f('nreq')),q(f('cw'),.5),s.mean(f('cw')),q(f('out'),.5),s.mean(f('out')),q(f('grow_own'),.5),s.mean(f('grow_own')),q(f('grow_next'),.5),s.mean(f('grow_next')),q(ov,.5),s.mean(ov),one,sum(t['rec_after'] for t in la),len(la)))
