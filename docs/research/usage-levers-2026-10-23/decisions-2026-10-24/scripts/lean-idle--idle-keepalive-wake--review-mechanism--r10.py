# Independent check of the as-coded timer's death rate on resumed gaps >= 3300 s: walk the real transcript lines between
# the gap-start request and the gap end and ask whether ANY line (timestamped or not) lands after launch+20 s and before
# launch+3300 s. launch := turn_duration ts if present within 60 s, else gap start + 5.
import csv, json, random, collections
from datetime import datetime
D='/tmp/lean-idle/idle-keepalive-wake/'
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
    except Exception: return None
path={}
for a in ['next','next2','next3','next4']:
    for l in open(D+a+'.files'):
        p=l.rstrip('\n').split('\t',7); path.setdefault(p[3],p[7])
G=[g for g in csv.DictReader(open(D+'gaps.tsv'),delimiter='\t') if g['terminal']=='0' and float(g['dur'])>=3300]
random.seed(7); S=random.sample(G,min(250,len(G)))
by=collections.defaultdict(list)
for g in S: by[g['sid']].append(g)
res=collections.Counter(); first=collections.Counter(); agree=collections.Counter()
for sid,gs in by.items():
    try: lines=open(path[sid],'rb').read().split(b'\n')
    except Exception: res['nofile']+=len(gs); continue
    recs=[]
    for ln in lines:
        if not ln.strip(): continue
        try: r=json.loads(ln)
        except Exception: recs.append((None,'bad')); continue
        lab=r.get('type','?')+':'+str(r.get('subtype') or (r.get('attachment') or {}).get('type') or '')
        recs.append((ep(r['timestamp']) if r.get('timestamp') else None, lab))
    for g in gs:
        st=float(g['start']); end=float(g['end'])
        # index of last record with ts <= st+1 ... then find turn_duration within 60 s
        idx=max((i for i,(t,_) in enumerate(recs) if t is not None and t<=st+1),default=None)
        if idx is None: res['noidx']+=1; continue
        launch=st+5
        for t,lab in recs[idx:idx+40]:
            if t is not None and lab=='system:turn_duration' and t-st<60: launch=t; break
        lastt=st; killer=None
        for t,lab in recs[idx+1:]:
            if t is not None: lastt=t
            if lastt>=end-1: break
            eff=t if t is not None else lastt  # an untimestamped line is at least as late as the previous stamp
            if launch+20<eff<launch+3300 or (t is None and lastt>launch+20 and lastt<launch+3300):
                killer=(lab,round(eff-st)); break
        res['killed' if killer else 'survives']+=1
        if killer: first[killer[0]]+=1
        rep=bool(g['first_ev_t'] and float(g['first_ev_t'])<min(end-5,st+3300))
        agree[(rep,bool(killer))]+=1
print(dict(res)); print('first killing record type',first.most_common(8)); print('replay-killed vs direct-killed',dict(agree))
