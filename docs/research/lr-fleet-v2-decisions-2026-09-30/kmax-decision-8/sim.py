import json, os, re, datetime, collections, bisect
from zoneinfo import ZoneInfo
H=json.load(open('heavy.json'))
STORES={os.path.expanduser('~/.claude/projects'):'next', os.path.expanduser('~/.claude-secondary/projects'):'next2',
        os.path.expanduser('~/.claude-tertiary/projects'):'next3', os.path.expanduser('~/.claude-quaternary/projects'):'next4'}
ACC=['next','next2','next3','next4']
def ts(v): return datetime.datetime.fromisoformat(v.replace('Z','+00:00')).timestamp()
fmt=lambda t: datetime.datetime.utcfromtimestamp(t).strftime('%m-%d %H:%MZ')
# per file: list of ts
files=collections.defaultdict(list)
for line in open('ts_hits.txt'):
    p,_,m=line.rstrip('\n').partition(':"timestamp":"')
    files[p].append(ts(m.rstrip('"')))
units=[]  # (acct, sid_owner, kind, sorted ts)
dropped=0
for p,tt in files.items():
    acct=next((a for d,a in STORES.items() if p.startswith(d+'/')),None)
    rel=p[len(next(d for d in STORES if p.startswith(d+'/')))+1:]
    parts=rel.split('/')
    base=os.path.basename(p)
    if len(parts)==2: kind='top'; owner=base.split('.jsonl')[0]
    elif '/subagents/' in p and base.startswith('agent-'): kind='sub'; owner=parts[1]
    else: continue
    try: bt=os.stat(p).st_birthtime
    except OSError: continue
    keep=sorted(t for t in tt if t>=bt-120); dropped+=len(tt)-len(keep)
    if keep: units.append((acct,owner,kind,keep))
print('units',len(units),'dropped copied-history stamps',dropped)
def kwork(t, excl_sid):
    c={a:0 for a in ACC}
    for acct,owner,kind,keep in units:
        if owner==excl_sid: continue
        i=bisect.bisect_right(keep,t)
        if i and keep[i-1]>t-600: c[acct]+=1
    return c
# utilization rows
U=[json.loads(l) for l in open('/Users/chrisren/.claude/logs/account-utilization.jsonl')]
for r in U: r['_t']=ts(r['ts'])
byacct={a:sorted([r for r in U if r['acct']==a], key=lambda r:r['_t']) for a in ACC}
def urow(a,t):
    rs=byacct[a]; ks=[r['_t'] for r in rs]; i=bisect.bisect_right(ks,t)
    return rs[i-1] if i else None
def urow_ago(a,t,sec):
    return urow(a,t-sec)
def when(v):
    return ts(v) if v else None
RS=re.compile(r'resets (\d+)(?::(\d+))?(am|pm) \(([^)]+)\)')
def reset_of(text,t0):
    m=RS.search(text); h=int(m.group(1))%12+(12 if m.group(3)=='pm' else 0); mi=int(m.group(2) or 0)
    d=datetime.datetime.fromtimestamp(t0,ZoneInfo(m.group(4))).replace(hour=h,minute=mi,second=0,microsecond=0)
    for k in range(8):
        c=(d+datetime.timedelta(days=k)).timestamp()
        if c>t0-60: return c
def src_of(h):
    rs=reset_of(h['text'],h['t0']); key='weekly_reset_at' if 'weekly' in h['text'] else 'session_reset_at'
    best=[]
    for a in ACC:
        r=urow(a,h['t0']+60)
        if r and r.get(key) and abs(ts(r[key])-rs)<=20*60: best.append(a)
    return best
def limited(a,t):
    r=urow(a,t)
    if not r: return 'no-row'
    if (r.get('session_pct') or 0)>=100 and (when(r.get('session_reset_at')) or 0)>t: return '5h-100'
    if (r.get('weekly_pct') or 0)>=100 and (when(r.get('weekly_reset_at')) or 0)>t: return '7d-100'
    if r.get('auth') not in ('ok',None): return 'auth:'+str(r.get('auth'))
    return None
def floors(a,t):
    r=urow(a,t)
    su=(r.get('session_pct') or 0)/100
    # native burn: slope of session_pct over prior 60 min within same 5h window, else 0
    r0=urow(a,t-3600); b=0.0
    if r0 and r0.get('session_reset_at')==r.get('session_reset_at') and r['_t']>r0['_t']:
        b=max(0.0,((r.get('session_pct') or 0)-(r0.get('session_pct') or 0))/100/((r['_t']-r0['_t'])/3600))
    srh=(when(r.get('session_reset_at')) or t+3600-0)-t; srh/=3600
    ahead=min(1.0,max(0.0,srh))
    if su+(b+1*0.07)*ahead>=0.60: return 'recovery-5h-thin(su=%.2f,b=%.2f)'%(su,b)
    wu=(r.get('weekly_pct') or 0)/100; wrem=max(0.0,1.0-wu)
    wrh=((when(r.get('weekly_reset_at')) or t)-t)/3600; span=min(max(0.0,wrh),9.0)
    if wrem-2*0.011*span<0.10: return 'recovery-weekly-thin(wrem=%.2f)'%wrem
    return None
# mover weight timeline from heavy.py logic (recompute exactly using all copies' subagent stamps, no birthtime filter)
import glob
TSRE=re.compile(rb'"timestamp":"([0-9T:\.\-]+Z?)"')
def sub_stamps(sid):
    subs={}
    for d in STORES:
        for p in glob.glob(os.path.join(d,'*',sid,'subagents','**','agent-*.jsonl'),recursive=True):
            s=subs.setdefault(os.path.basename(p),set())
            for line in open(p,'rb'):
                m=TSRE.search(line)
                if m: s.add(ts(m.group(1).decode()))
    return [sorted(v) for v in subs.values()]
res=[]
for h in H:
    t0=h['t0']; src=src_of(h); S=sub_stamps(h['sid'])
    def w(t): return 1+sum(1 for v in S if (lambda i: i and v[i-1]>t-600)(bisect.bisect_right(v,t)))
    horizon=min(h['resume_min'] or 10**9, 60)
    print('\n=== %s %s src(reset-match)=%s birth-guess=%s w0=%d reset+%sm hist-resume+%sm  %s'%(h['death'],h['sid'][:8],src,h['acct_guess'],h['w0'],h['reset_min'],h['resume_min'],h['text'][:45]))
    first={}
    for k in range(0,horizon+1):
        t=t0+60*k; wk=w(t); kw=kwork(t,h['sid'])
        cells=[]
        for a in ACC:
            if a in src: continue
            free=8-kw[a]; lim=limited(a,t); fl=floors(a,t) if not lim else None
            cells.append((a,free,lim,fl))
            for tag,K,ww,need_ok in (('seat',8,wk,False),('seat+floors',8,wk,True),('w1+floors',8,1,True),('K12+floors',12,wk,True),('K16+floors',16,wk,True),('seat-K12',12,wk,False)):
                if tag in first: continue
                if K-kw[a]>=ww and (not need_ok or (not lim and not fl)): first[tag]=(k,a)
        if k in (0,5,8,9,10,11,12,15,20,30,45,60) or k==horizon:
            print('  +%2dm w=%-3d '%(k,wk)+'  '.join('%s:free=%d%s'%(a,f,'' if not (l or fl) else '['+(l or fl)+']') for a,f,l,fl in cells))
    print('  FIRST', first)
    res.append(dict(death=h['death'],sid=h['sid'][:8],src=src,w0=h['w0'],reset_min=h['reset_min'],resume_min=h['resume_min'],first=first))
json.dump(res,open('sim.json','w'))
