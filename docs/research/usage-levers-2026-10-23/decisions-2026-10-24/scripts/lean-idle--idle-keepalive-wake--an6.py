import csv,collections,bisect
ACCTS=['next','next2','next3','next4']
fid={}
for a in ACCTS:
    for l in open(a+'.files'):
        p=l.rstrip('\n').split('\t',7); fid[(a,p[0])]=p[3]
ev=collections.defaultdict(list)
for a in ACCTS:
    for l in open(a+'.ev'):
        fi,ts,lab,blk=l.rstrip('\n').split('\t')
        if lab in ('sys:stop_hook_summary','sys:turn_duration'): ev[fid[(a,fi)]].append((float(ts),lab))
for k in ev: ev[k].sort()
R=list(csv.DictReader(open('gaps.tsv'),delimiter='\t'))
pre=[r for r in R if r['terminal']=='0' and 3300<=float(r['dur'])<3600]
d=sorted(float(r['dur'])-3300 for r in pre)
q=lambda xs,p: xs[min(len(xs)-1,int(p*len(xs)))]
print('pre-TTL gaps',len(pre),'dur-3300 p10 %.0f p25 %.0f p50 %.0f p75 %.0f p90 %.0f'%tuple(q(d,p) for p in (.1,.25,.5,.75,.9)))
off=[]
for r in R:
    if r['terminal']=='1' or float(r['dur'])<300: continue
    L=ev.get(r['sid'],[]); st=float(r['start'])
    i=bisect.bisect_right(L,(st,''))
    while i<len(L) and L[i][1]!='sys:turn_duration': i+=1
    if i<len(L) and L[i][0]<st+600: off.append(L[i][0]-st)
off.sort(); print('turn_duration record after gap start (s): p10 %.0f p25 %.0f p50 %.0f p75 %.0f p90 %.0f n=%d'%(tuple(q(off,p) for p in (.1,.25,.5,.75,.9))+(len(off),)))
# pre-TTL gaps: measure the stop offset per gap and test whether the watcher fires before stop+3300
ok=late=0
for r in pre:
    L=ev.get(r['sid'],[]); st=float(r['start']); i=bisect.bisect_right(L,(st,''))
    while i<len(L) and L[i][1]!='sys:turn_duration': i+=1
    if i<len(L) and L[i][0]<st+600:
        stop=L[i][0]-3  # sync Stop hooks finish ~just before turn_duration is written
        if float(r['end'])<stop+3300: ok+=1
        else: late+=1
print('pre-TTL gaps where the gap ends before Stop+3300 (keepalive would not fire):',ok,'after (double wake):',late)
