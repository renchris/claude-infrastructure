import csv,collections,statistics
rows=[r for r in csv.DictReader(open('/tmp/usage-audit/requests.csv')) if r['sub']=='0' and r['model']!='<synthetic>']
byf=collections.defaultdict(list)
for r in rows:
    r['ctx']=int(r['inp'])+int(r['cr'])+int(r['cc']); r['cc']=int(r['cc']); r['cr']=int(r['cr']); r['inp']=int(r['inp'])
    byf[(r['acct'],r['file'])].append(r)
for k in byf: byf[k].sort(key=lambda r:r['ts'])
def pct(v,q):
    v=sorted(v); return v[min(len(v)-1,int(q*len(v)))] if v else 0
# fresh-session first request: file whose first request in window is the file's first-ever request
firsts=[];n10=[];n30=[];firstcc=[]
for k,g in byf.items():
    if g[0]['first_in_file']=='1':
        firsts.append(g[0]['ctx']); firstcc.append(g[0]['cc'])
        if len(g)>=10: n10.append(g[9]['ctx'])
        if len(g)>=30: n30.append(g[29]['ctx'])
print('files(main)=',len(byf),'fresh-first n=',len(firsts))
for nm,v in [('first',firsts),('first_cc',firstcc),('req10',n10),('req30',n30)]:
    print(' %s: n=%d p10=%d p25=%d p50=%d p75=%d p90=%d'%(nm,len(v),pct(v,.1),pct(v,.25),pct(v,.5),pct(v,.75),pct(v,.9)))
big=sum(1 for x in firsts if x>150000); print(' fresh-first >150k (likely resume/fork copies):',big)
# peak ctx per file
peaks=[max(r['ctx'] for r in g) for g in byf.values() if len(g)>=5]
print('per-file peak ctx (files>=5 req) n=%d p50=%d p75=%d p90=%d'%(len(peaks),pct(peaks,.5),pct(peaks,.75),pct(peaks,.9)))
# weights (API list-price ratios, ASSUMPTION): uncached 1, cache read 0.1, cache write(1h) 2
W={'inp':1.0,'cr':0.1,'cc':1.25}
def cost(r): return r['inp']*W['inp']+r['cr']*W['cr']+r['cc']*W['cc']
base_raw=sum(r['ctx'] for r in rows); base_w=sum(cost(r) for r in rows)
print('baseline raw=%.3fB weighted=%.3fB-eq'%(base_raw/1e9,base_w/1e9))
for R in [pct(firsts,.5),pct(n10,.5)]:
  for T in [150000,250000,350000,500000]:
    raw=0;w=0;nrec=0
    for g in byf.values():
        off=0; prev=None
        for r in g:
            c=r['ctx']
            if prev is not None and c < prev*0.6: off=0   # real compaction/clear in original: reset offset
            prev=c
            s=c-off
            if s>T:
                # recycle: handoff turn (est. 3 requests at ~T, cache-read) + fresh successor primed at R (cache write)
                nrec+=1
                raw+=3*T; w+=3*T*W['cr']
                off=c-R; s=R
                raw+=R; w+=R*W['cc']
                continue
            raw+=s
            # keep original's per-request fresh part (cc+inp) as-is, rest cache read
            fresh=r['cc']+r['inp']
            w+=min(fresh,s)*(W['cc'])+max(0,s-fresh)*W['cr']
    print('R=%dk T=%dk: recycles=%d raw=%.3fB (save %.1f%%) weighted=%.3fB (save %.1f%%)'%(R//1000,T//1000,nrec,raw/1e9,100*(1-raw/base_raw),w/1e9,100*(1-w/base_w)))
allr=list(csv.DictReader(open('/tmp/usage-audit/requests.csv')))
tot_w=sum(int(r['inp'])+0.1*int(r['cr'])+1.25*int(r['cc'])+5*int(r['outp']) for r in allr)
main_out=sum(5*int(r['outp']) for r in rows)
print('fleet total weighted (main+sub, incl output x5)=%.3fB-eq; main input-side weighted=%.3fB; main output x5=%.3fB'%(tot_w/1e9,base_w/1e9,main_out/1e9))
