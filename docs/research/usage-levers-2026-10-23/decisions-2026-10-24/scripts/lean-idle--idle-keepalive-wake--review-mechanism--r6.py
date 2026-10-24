# Resolve the "dead pane, no SessionEnd, unknown lifetime" unknown with ~/.claude/logs/claude-crashes.jsonl:
# for each censored non-alive terminal gap, death ts (first crash/close record after the last request) vs the
# transcript's last write (file mtime, the TERM_MODE=low assumption) vs window end (TERM_MODE=high).
import csv, json, collections, os
from datetime import datetime
D='/tmp/lean-idle/idle-keepalive-wake/'
S,E=(float(x) for x in open(D+'window').read().split())
ALIVE=set(open(D+'alive_sids.txt').read().split())
MT={}
for a in ['next','next2','next3','next4']:
    for l in open(D+a+'.files'):
        p=l.rstrip('\n').split('\t',7); MT[p[3]]=max(MT.get(p[3],0.0),float(p[1]))
death=collections.defaultdict(list)
for l in open(os.path.expanduser('~/.claude/logs/claude-crashes.jsonl'),errors='ignore'):
    try: r=json.loads(l)
    except Exception: continue
    if not r.get('sid') or not r.get('ts'): continue
    t=datetime.fromisoformat(r['ts'].replace('Z','+00:00')).timestamp()
    death[r['sid']].append((t,r.get('class',''),r.get('cause','')))
G=list(csv.DictReader(open(D+'gaps.tsv'),delimiter='\t'))
rows=[]
for g in G:
    if g['terminal']!='1' or g['end_kind']!='censored' or g['sid'] in ALIVE: continue
    st=float(g['start']); sid=g['sid']
    ds=[d for d in sorted(death.get(sid,[])) if d[0]>=st-5]
    rows.append((sid,st,MT.get(sid,st),ds[0] if ds else None,float(g['end'])))
found=[r for r in rows if r[3]]
print('censored dead terminal gaps',len(rows),'with a crash/close record after last request',len(found))
lag=sorted(r[3][0]-r[2] for r in found)   # death - last write
idle_d=sorted(r[3][0]-r[1] for r in found)
q=lambda xs,p: xs[min(len(xs)-1,int(p*len(xs)))]
print('death - last transcript write (s): p10 %.0f p50 %.0f p90 %.0f max %.0f'%(q(lag,.1),q(lag,.5),q(lag,.9),lag[-1]))
print('death - gap start (s): p50 %.0f p90 %.0f; >=3300: %d'%(q(idle_d,.5),q(idle_d,.9),sum(1 for x in idle_d if x>=3300)))
print('classes',collections.Counter((r[3][1],r[3][2]) for r in found).most_common(8))
ge=[r for r in rows if r[4]-r[1]>=3300]
print('of those idle>=3300 to window end (the finding\'s dead-unknown class): %d, with death record %d'%(len(ge),sum(1 for r in ge if r[3])))
# wakes under re-arm-every-3330 at true death vs low vs high
def nw(d): return 0 if d<3300 else int((d-3300)//3330)+1
WK=7/((E-S)/86400)
tl=sum(nw(r[2]-r[1]) for r in rows); th=sum(nw(r[4]-r[1]) for r in rows)
tt=sum(nw((r[3][0] if r[3] else r[2])-r[1]) for r in rows)
tt_hi=sum(nw((r[3][0] if r[3] else r[4])-r[1]) for r in rows)
print('re-arm wakes/wk: low(last write) %.1f | crash-log death, missing->last write %.1f | missing->window end %.1f | high(window end) %.1f'%(tl*WK,tt*WK,tt_hi*WK,th*WK))
# --- the rows with no crash/close record: any other trace after the last request?
miss=[r for r in rows if not r[3]]
open(D+'review-mechanism/dead_nodeath.txt','w').write('\n'.join(r[0] for r in miss)+'\n')
print('no death record:',len(miss),'; idle-to-window-end >=3300:',sum(1 for r in miss if r[4]-r[1]>=3300))
