import csv,collections
J={}
for a in ['next','next2','next3','next4']:
    for line in open(a+'.jobs'):
        fi,sid,tu,nm,w,js,je=line.rstrip('\n').split('\t'); J[tu]=(nm,w)
def pk(s):
    k,_,ex=s.partition('|')
    if k=='job':
        tu,_,stt=ex.partition('|'); j=J.get(tu)
        return 'watcher-'+stt if j and j[1]=='1' else 'job'
    return k or 'none'
R=list(csv.DictReader(open('gaps.tsv'),delimiter='\t'))
c=collections.defaultdict(lambda:[0,0,0])
for r in R:
    d=float(r['dur'])
    if d<3300: continue
    st=float(r['start']); end=float(r['end'])
    kill= r['first_ev_t'] and float(r['first_ev_t'])<min(end-5,st+3300)
    awk= kill and r['first_ev_lab']=='sys:away_summary'
    x=c[pk(r['prev_kind'])]; x[0]+=1; x[1]+=bool(kill); x[2]+=bool(awk)
for k,v in sorted(c.items(),key=lambda kv:-kv[1][0]): print('%-18s gaps>=3300 %4d timer-killed %4d (%.0f%%) by away %d'%(k,v[0],v[1],100*v[1]/v[0],v[2]))
tot=[sum(v[i] for v in c.values()) for i in range(3)]; print('ALL',tot, '%.0f%%'%(100*tot[1]/tot[0]))
