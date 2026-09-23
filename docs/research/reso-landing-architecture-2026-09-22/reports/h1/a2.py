import json, datetime as dt, collections as C, subprocess, math
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
t=lambda s: dt.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ')
cut=t('2026-09-16T04:59:00Z'); w=[r for r in rows if t(r['ts_start'])>=cut]
lands=sorted([r for r in w if r['exit']==0], key=lambda r:r['ts_end'])
# ancestry cross-check
R='/Users/chrisren/Development/reso-management-app'
bad=0
for r in lands:
    rc=subprocess.run(['git','-C',R,'merge-base','--is-ancestor',r['head'],'origin/main']).returncode
    if rc!=0: bad+=1; print('NOT ANCESTOR',r['head'],r['branch'])
print('landed heads not on origin/main:',bad,'of',len(lands))
# git commits since cut not covered: walk first-parent list from origin/main back to first landed head's earliest
revs=subprocess.run(['git','-C',R,'rev-list','--first-parent','origin/main','--since=2026-09-16T04:59:00Z'],capture_output=True,text=True).stdout.split()
heads={r['head'] for r in lands}
# segments: commits between heads
seg=0; orphan=[]
cur=[]
for c in revs:  # newest first
    if c in heads:
        if cur and seg==0: orphan+=cur  # commits newer than newest land head
        cur=[]; seg+=1
    else: cur.append(c)
print('commits on main since cut',len(revs),'landed-head commits',len(heads & set(revs)),'commits above newest logged head',len(orphan))
# repos
print('repos',C.Counter(r['repo'].split('/')[-1][:20] for r in w).most_common(8))
# per-day lands
print('lands/day',sorted(C.Counter(r['ts_end'][:10] for r in lands).items()))
# hourly lands for 09-22/23
hr=C.Counter(r['ts_end'][:13] for r in lands if r['ts_end']>='2026-09-22')
print('hourly lands 09-22..23:',sorted(hr.items()))
ends=[t(r['ts_end']) for r in lands]
def maxwin(mins, since=None):
    best=(0,None)
    E=[e for e in ends if since is None or e>=since]
    for i,e in enumerate(E):
        n=sum(1 for f in E if e<=f<e+dt.timedelta(minutes=mins))
        if n>best[0]: best=(n,e)
    return best
for m in (30,60,120,180):
    print('max lands in any %d-min window:'%m, maxwin(m))
# attempts-start per hour (arrival of land requests, incl. failures) on peak
ar=C.Counter(r['ts_start'][:13] for r in w if r['ts_start']>='2026-09-22')
print('hourly attempts 09-22..23:',sorted(ar.items()))
# concurrency: number of in-flight attempts at each attempt start
iv=[(t(r['ts_start']),t(r['ts_end']),r['branch']) for r in w]
conc=[]
for s,e,b in iv:
    n=len({bb for ss,ee,bb in iv if ss<=s<=ee})
    conc.append((n,s,b))
print('in-flight attempts at attempt start: dist',sorted(C.Counter(n for n,_,_ in conc).items()))
print('max',max(conc))
# distinct branches attempting per hour at peak
bh=C.defaultdict(set)
for r in w:
    if r['ts_start']>='2026-09-22': bh[r['ts_start'][:13]].add(r['branch'])
print('distinct landers/hour peak:',sorted((k,len(v)) for k,v in bh.items()))
