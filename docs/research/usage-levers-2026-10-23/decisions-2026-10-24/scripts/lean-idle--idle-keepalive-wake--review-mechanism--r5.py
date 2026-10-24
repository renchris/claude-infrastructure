# For 55-60 min gaps that end in a WATCHER notification: arm time (watcher tool_use ts), gap start (last request ts),
# turn_duration ts (~Stop), notification ts. Who fires first: watcher notice vs keepalive (launch+3300)?
# launch is bracketed: lo = gap start (earliest possible Stop), hi = turn_duration ts (sync Stop hooks done).
import csv, collections, bisect
D='/tmp/lean-idle/idle-keepalive-wake/'
A=['next','next2','next3','next4']
fid={}
for a in A:
    for l in open(D+a+'.files'):
        p=l.rstrip('\n').split('\t',7); fid[(a,p[0])]=p[3]
td=collections.defaultdict(list)
for a in A:
    for l in open(D+a+'.ev'):
        fi,ts,lab,blk=l.rstrip('\n').split('\t')
        if lab=='sys:turn_duration': td[fid[(a,fi)]].append(float(ts))
for k in td: td[k].sort()
W=collections.defaultdict(list)
for a in A:
    for l in open(D+a+'.jobs'):
        fi,sid,tu,nm,w,js,je=l.rstrip('\n').split('\t')
        if w=='1' and js and je: W[sid].append((float(js),float(je)))
R=list(csv.DictReader(open(D+'gaps.tsv'),delimiter='\t'))
res=collections.Counter(); m_lo=[]; m_hi=[]; arm_lead=[]
for r in R:
    if r['terminal']=='1' or r['end_kind']!='job': continue
    d=float(r['dur'])
    if not 3300<=d<3600: continue
    st=float(r['start']); en=float(r['end']); sid=r['sid']
    js=[j for j in W[sid] if abs(j[1]-en)<=2]
    if not js: res['end not a watcher notice']+=1; continue
    arm=js[0][0]
    L=td[sid]; i=bisect.bisect_right(L,st); tdt=L[i] if i<len(L) and L[i]<st+600 else None
    if tdt is None: res['no turn_duration']+=1; continue
    arm_lead.append(st-arm)
    lo=en-(st+3300); hi=en-(tdt+3300)
    m_lo.append(lo); m_hi.append(hi)
    res['keepalive first even if launch=turn_duration ts' if hi>0 else ('watcher first even if launch=gap start' if lo<=0 else 'ambiguous (depends on launch within [start,turn_duration])')]+=1
q=lambda xs,p: sorted(xs)[min(len(xs)-1,int(p*len(xs)))]
print(dict(res))
print('arm lead (gap start - watcher arm) p10/p50/p90: %.0f %.0f %.0f'%(q(arm_lead,.1),q(arm_lead,.5),q(arm_lead,.9)))
print('notice - (turn_duration+3300) p10/p50/p90: %.0f %.0f %.0f'%(q(m_hi,.1),q(m_hi,.5),q(m_hi,.9)))
print('arm earlier than the gap by >60s (watcher armed in an EARLIER turn):',sum(1 for x in arm_lead if x>60),'of',len(arm_lead))
