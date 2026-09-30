import json, os, re, glob, datetime, collections, bisect
from zoneinfo import ZoneInfo
STORES={os.path.expanduser('~/.claude/projects'):'next', os.path.expanduser('~/.claude-secondary/projects'):'next2',
        os.path.expanduser('~/.claude-tertiary/projects'):'next3', os.path.expanduser('~/.claude-quaternary/projects'):'next4'}
ACC=['next','next2','next3','next4']
def ts(v): return datetime.datetime.fromisoformat(v.replace('Z','+00:00')).timestamp()
fmt=lambda t: datetime.datetime.utcfromtimestamp(t).strftime('%m-%d %H:%MZ')
U=[json.loads(l) for l in open('/Users/chrisren/.claude/logs/account-utilization.jsonl')]
for r in U: r['_t']=ts(r['ts'])
byacct={a:sorted([r for r in U if r['acct']==a],key=lambda r:r['_t']) for a in ACC}
bykeys={a:[r['_t'] for r in byacct[a]] for a in ACC}
def urow(a,t):
    i=bisect.bisect_right(bykeys[a],t); return byacct[a][i-1] if i else None
def when(v): return ts(v) if v else None
RS=re.compile(r'resets (\d+)(?::(\d+))?(am|pm) \(([^)]+)\)')
def reset_of(text,t0):
    m=RS.search(text)
    if not m: return None
    h=int(m.group(1))%12+(12 if m.group(3)=='pm' else 0); mi=int(m.group(2) or 0)
    d=datetime.datetime.fromtimestamp(t0,ZoneInfo(m.group(4))).replace(hour=h,minute=mi,second=0,microsecond=0)
    for k in range(8):
        c=(d+datetime.timedelta(days=k)).timestamp()
        if c>t0-60: return c
def src_of(text,t0):
    rs=reset_of(text,t0)
    if rs is None: return []
    key,pk=('weekly_reset_at','weekly_pct') if 'weekly' in text else ('session_reset_at','session_pct')
    out=[]
    for a in ACC:
        for dt in (60,300,600):
            r=urow(a,t0+dt)
            if r and r.get(key) and abs(ts(r[key])-rs)<=1200 and (r.get(pk) or 0)>=99: out.append(a); break
    return out
ALL=json.load(open('deaths_w.json'))
for d in ALL: d['src']=src_of(d['text'],d['t'])
# ---- stamps -> units, copy-aware
files=collections.defaultdict(list)
for line in open('ts_hits.txt'):
    p,_,m=line.rstrip('\n').partition(':"timestamp":"'); files[p].append(ts(m.rstrip('"')))
groups=collections.defaultdict(list)
for p,tt in files.items():
    d0=next(d for d in STORES if p.startswith(d+'/')); acct=STORES[d0]; parts=p[len(d0)+1:].split('/'); base=os.path.basename(p)
    if len(parts)==2: key=('top',base.split('.jsonl')[0]); owner=key[1]
    elif '/subagents/' in p and base.startswith('agent-'): key=(parts[1],base.split('.jsonl')[0]); owner=parts[1]
    else: continue
    st=os.stat(p); groups[key].append((st.st_mtime,0 if st.st_birthtime%1 else 1,p,acct,owner,set(tt)))
units=[]
for key,fl in groups.items():
    fl.sort(key=lambda x:(x[0],x[1],x[2])); per=collections.defaultdict(list)
    for x in set().union(*[f[5] for f in fl]):
        per[next(f for f in fl if x in f[5])[3]].append(x)
    for a,xs in per.items(): units.append([a,fl[0][4],'top' if key[0]=='top' else 'sub',sorted(xs)])
tl=collections.defaultdict(list)
for a,o,k,xs in units:
    if k=='top': tl[o]+= [(x,a) for x in xs]
for o in tl: tl[o].sort()
def owner_acct(o,x):
    # a dead session (limit death within the last 3h) is pinned to its measured source account
    for d in ALL:
        if d['sid']==o and d['src'] and len(d['src'])==1 and d['t']-3600<=x<=d['t']+3*3600: return d['src'][0]
    L=tl.get(o)
    if not L: return None
    ks=[a for a,_ in L]; i=bisect.bisect_left(ks,x); c=[L[j] for j in (i-1,i) if 0<=j<len(L)]
    b=min(c,key=lambda q:abs(q[0]-x)); return b[1] if abs(b[0]-x)<=1800 else None
nu=[]
for a,o,k,xs in units:
    per=collections.defaultdict(list)
    for x in xs: per[owner_acct(o,x) or a].append(x)
    for aa,v in per.items(): nu.append((aa,o,k,sorted(v)))
units=nu
def fresh(v,t):
    i=bisect.bisect_right(v,t); return bool(i) and v[i-1]>t-600
def kwork(t,excl):
    c={a:0 for a in ACC}
    for a,o,k,xs in units:
        if o!=excl and fresh(xs,t): c[a]+=1
    return c
def fact(a,t):
    r=urow(a,t)
    if not r or t-r['_t']>1800: return 'no-row'
    if (r.get('session_pct') or 0)>=100 and (when(r.get('session_reset_at')) or 0)>t: return '5h-100'
    if (r.get('weekly_pct') or 0)>=100 and (when(r.get('weekly_reset_at')) or 0)>t: return '7d-100'
    if r.get('auth') not in ('ok',None): return 'auth'
    return None
def floors(a,t):
    r=urow(a,t); su=(r.get('session_pct') or 0)/100; r0=urow(a,t-3600); b=0.0
    if r0 and r0.get('session_reset_at') and r0.get('session_reset_at')[:15]==(r.get('session_reset_at') or '')[:15] and r['_t']>r0['_t']:
        b=max(0.0,((r.get('session_pct') or 0)-(r0.get('session_pct') or 0))/100/((r['_t']-r0['_t'])/3600))
    sr=when(r.get('session_reset_at')); ahead=min(1.0,max(0.0,(sr-t)/3600)) if sr else 1.0
    if su+(b+0.07)*ahead>=0.60: return '5h-thin'
    wrem=max(0.0,1.0-(r.get('weekly_pct') or 0)/100); wr=when(r.get('weekly_reset_at')); span=min(max(0.0,(wr-t)/3600),9.0) if wr else 9.0
    if wrem-2*0.011*span<0.10: return 'wk-thin'
    return None
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
H=json.load(open('heavy.json'))
out=[]
for h in H:
    t0=h['t0']; src=src_of(h['text'],t0); S=sub_stamps(h['sid'])
    W=lambda t: 1+sum(1 for v in S if fresh(v,t))
    hz=min(h['resume_min'] if h['resume_min'] is not None else 10**9, 90)
    first={}; trace=[]
    for k in range(hz+1):
        t=t0+60*k; w=W(t); kw=kwork(t,h['sid'])
        info={a:(8-kw[a],fact(a,t) or floors(a,t) if (fact(a,t) is None and urow(a,t)) else fact(a,t)) for a in ACC if a not in src}
        trace.append((k,w,info))
        tests={'w_le_8':lambda a,K=8:w<=8,
               'seat_K8':lambda a:8-kw[a]>=w, 'seat_K12':lambda a:12-kw[a]>=w, 'seat_K16':lambda a:16-kw[a]>=w,
               'seat_w1':lambda a:8-kw[a]>=1,
               'full_K8':lambda a:8-kw[a]>=w and info[a][1] is None, 'full_K12':lambda a:12-kw[a]>=w and info[a][1] is None,
               'full_K16':lambda a:16-kw[a]>=w and info[a][1] is None, 'full_w1':lambda a:8-kw[a]>=1 and info[a][1] is None}
        for tag,f in tests.items():
            if tag in first: continue
            ok=[a for a in info if f(a)]
            if ok: first[tag]=(k,ok[0])
    rec=dict(death=h['death'],sid=h['sid'][:8],src=src,cap=('weekly' if 'weekly' in h['text'] else '5h'),w0=h['w0'],
             reset_min=h['reset_min'],hist_resume_min=h['resume_min'],first=first,horizon=hz,
             trace=[(k,w,{a:v for a,v in i.items()}) for k,w,i in trace if k in (0,5,8,9,10,11,12,15,20,30)])
    out.append(rec)
    print('\n== %(death)s %(sid)s src=%(src)s %(cap)s w0=%(w0)d reset+%(reset_min)sm hist-resume+%(hist_resume_min)sm horizon=%(horizon)sm'%rec)
    for k,w,i in rec['trace']: print('   +%2dm w=%-3d %s'%(k,w,'  '.join('%s:free=%d%s'%(a,f,'['+x+']' if x else '') for a,(f,x) in i.items())))
    print('   FIRST', json.dumps(first))
json.dump(out,open('final.json','w'))

# validation: reconstructed vs logged k_work (row <=2 min old), non-source accounts, heavy windows
diffs=[]
for h in H:
    src=src_of(h['text'],h['t0'])
    for a in ACC:
        if a in src: continue
        for r in byacct[a]:
            if r.get('k_work') is None or not (h['t0']-600<=r['_t']<=h['t0']+3600): continue
            diffs.append((r['k_work'], kwork(r['_t'],None)[a], a, h['death']))
import statistics
print('VALID n=%d'%len(diffs), 'exact=%d'%sum(1 for l,c,_,_ in diffs if l==c), 'within2=%d'%sum(1 for l,c,_,_ in diffs if abs(l-c)<=2),
      'median(logged-recon)=%s'%statistics.median([l-c for l,c,_,_ in diffs]), 'max|d|=%d'%max(abs(l-c) for l,c,_,_ in diffs))
print(sorted(diffs,key=lambda x:-abs(x[0]-x[1]))[:6])
