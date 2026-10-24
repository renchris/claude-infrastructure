import csv,collections,statistics as st
J={}
for a in ['next','next2','next3','next4']:
    for line in open(a+'.jobs'):
        fi,sid,tu,nm,w,js,je=line.rstrip('\n').split('\t')
        J[tu]=(nm,w)
W=list(csv.DictReader(open('wturns.tsv'),delimiter='\t'))
def cls(r):
    if r['kind']=='job':
        tu,_,s=r['extra'].partition('|'); j=J.get(tu)
        if j and j[1]=='1': return 'watcher-'+s
        return 'job'
    return r['kind']
G=collections.defaultdict(list)
for r in W:
    gb=float(r['gap_before'])
    if not (60<=gb<3500): continue   # warm cache, real idle before
    G[cls(r)].append(r)
def q(xs,p): xs=sorted(xs); return xs[min(len(xs)-1,int(p*len(xs)))] if xs else None
RD,WR,OU=0.0067,0.245,0.404
print('%-18s %5s | %s'%('class','n','median/mean: nreq cw out extra_cr inp growth dur blocks | pp overhead (no ctx read) med mean | 1-req share'))
for k,L in sorted(G.items(),key=lambda kv:-len(kv[1])):
    f=lambda c:[float(r[c]) for r in L]
    ex=[float(r['cr'])-float(r['cr_first']) for r in L]
    pp=[(float(r['cw'])*WR+float(r['out'])*OU+(float(r['cr'])-float(r['cr_first']))*RD)/1e6 for r in L]
    one=sum(1 for r in L if r['nreq']=='1')
    print('%-18s %5d | nreq %s/%.2f cw %s/%.0f out %s/%.0f xcr %s/%.0f inp %s/%.1f grow %s/%.0f dur %s blk %.2f | %.4f %.4f | %.2f'%(k,len(L),
      q(f('nreq'),.5),st.mean(f('nreq')),q(f('cw'),.5),st.mean(f('cw')),q(f('out'),.5),st.mean(f('out')),q(ex,.5),st.mean(ex),q(f('inp'),.5),st.mean(f('inp')),q(f('growth'),.5),st.mean(f('growth')),q(f('dur_s'),.5),st.mean(f('blocks')),q(pp,.5),st.mean(pp),one/len(L)))
