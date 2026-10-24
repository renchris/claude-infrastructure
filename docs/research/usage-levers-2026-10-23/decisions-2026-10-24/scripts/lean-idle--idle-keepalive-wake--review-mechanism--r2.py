# Terminal gaps (last request -> session end/censor) where a NON-watcher background job started and was never
# notified: the busy-scoped redesign (R2) would keep waking these every ~3330 s, but busy() in gaps.py ends
# un-notified jobs at last_ts, so the replay books zero wakes for them.
import csv, collections, os
D='/tmp/lean-idle/idle-keepalive-wake/'
S,E=(float(x) for x in open(D+'window').read().split())
WK=7.0/((E-S)/86400)
ALIVE=set(open(D+'alive_sids.txt').read().split())
MT={}
for a in ['next','next2','next3','next4']:
    for l in open(D+a+'.files'):
        p=l.rstrip('\n').split('\t',7); MT[p[3]]=max(MT.get(p[3],0.0),float(p[1]))
J=collections.defaultdict(list)
for a in ['next','next2','next3','next4']:
    for l in open(D+a+'.jobs'):
        fi,sid,tu,nm,w,js,je=l.rstrip('\n').split('\t')
        if js: J[sid].append((nm,int(w),float(js),float(je) if je else None,tu))
G=list(csv.DictReader(open(D+'gaps.tsv'),delimiter='\t'))
rows=[]
for g in G:
    if g['terminal']!='1': continue
    st=float(g['start']); sid=g['sid']
    open_jobs=[j for j in J[sid] if j[1]==0 and j[2]<=st and j[3] is None]
    if not open_jobs: continue
    end=float(g['end']); exit_t=float(g['exit_t']) if g['exit_t'] else None
    kind=g['end_kind']
    lo_end = end if kind=='exit' else (end if sid in ALIVE else max(st,MT.get(sid,st)))
    hi_end = end
    rows.append((g['acct'],sid,kind,sid in ALIVE,st,lo_end-st,hi_end-st,int(g['ctx']),[j[0] for j in open_jobs],min(j[2] for j in open_jobs)))
def nw(d): return 0 if d<3300 else int((d-3300)//3330)+1
print('terminal gaps with an un-notified non-watcher job:',len(rows))
c=collections.Counter(r[2]+('/alive' if r[3] else '') for r in rows); print('by end kind',dict(c))
c2=collections.Counter(n for r in rows for n in set(r[8])); print('job tool names',dict(c2))
lo=[r for r in rows if r[5]>=3300]; hi=[r for r in rows if r[6]>=3300]
print('>=3300 s idle: low-mode %d, high-mode %d'%(len(lo),len(hi)))
for lab,idx in (('low',5),('high',6)):
    for prof,(nreq,cw,out,away) in {'brief_min':(1,1000,300,0),'proxy_med':(3,1515,522,0.64)}.items():
        for rn,r in (('lowreads',0.0057),('highreads',0.0076)):
            wakes=sum(nw(x[idx]) for x in rows)
            cost=sum(nw(x[idx])*((nreq+away)*x[7]*r+cw*0.245+out*0.404)/1e6 for x in rows)
            print('%-4s %-9s %-9s wakes/wk %7.1f cost pp/wk %6.2f'%(lab,prof,rn,wakes*WK,cost*WK))
print('--- largest (low mode) ---')
for r in sorted(rows,key=lambda r:-r[5])[:12]:
    print(r[0],r[1][:8],r[2],'alive' if r[3] else '', 'idle_lo %.1fh idle_hi %.1fh ctx %d jobs %s'%(r[5]/3600,r[6]/3600,r[7],r[8]))
