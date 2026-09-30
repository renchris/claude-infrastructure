import json, os, re, sys, datetime, collections
STORES = {os.path.expanduser('~/.claude/projects'):'next', os.path.expanduser('~/.claude-secondary/projects'):'next2',
          os.path.expanduser('~/.claude-tertiary/projects'):'next3', os.path.expanduser('~/.claude-quaternary/projects'):'next4'}
def acct_of(p):
    for d,a in STORES.items():
        if p.startswith(d+'/'): return a
def ts(v):
    try: return datetime.datetime.fromisoformat(v.replace('Z','+00:00')).timestamp()
    except Exception: return None
def text(r):
    c=(r.get('message') or {}).get('content')
    if isinstance(c,str): return c
    return ' '.join(b.get('text','') for b in c or [] if isinstance(b,dict) and isinstance(b.get('text'),str))
recs = {}  # uuid -> list of (acct, path, ts, text, sid)
for p in open('limfiles.txt').read().split():
    a = acct_of(p); sidf = os.path.basename(p)[:-6]
    bt = os.stat(p).st_birthtime
    for line in open(p, errors='replace'):
        if 'rate_limit' not in line and '429' not in line: continue
        try: r = json.loads(line)
        except Exception: continue
        if not isinstance(r, dict): continue
        st = r.get('apiErrorStatus')
        try: st = int(st)
        except Exception: st = None
        if not (r.get('error')=='rate_limit' or st==429): continue
        if r.get('isSidechain'): continue
        t = ts(r.get('timestamp') or '')
        if t is None: continue
        recs.setdefault(r.get('uuid'), []).append((a, p, t, text(r)[:120], r.get('sessionId') or sidf, bt))
# attribute each uuid to the store whose file was born earliest (the original writer)
rows = []
for u, lst in recs.items():
    lst.sort(key=lambda x: x[5])
    a,p,t,tx,sid,bt = lst[0]
    rows.append(dict(uuid=u, acct=a, path=p, t=t, text=tx, sid=sid, copies=len(lst)))
rows.sort(key=lambda r:(r['sid'], r['t']))
deaths = []
for r in rows:
    d = deaths[-1] if deaths else None
    if d and d['sid']==r['sid'] and d['acct']==r['acct'] and r['t']-d['last'] <= 1800:
        d['last']=r['t']; d['n']+=1; continue
    deaths.append(dict(sid=r['sid'], acct=r['acct'], path=r['path'], t=r['t'], last=r['t'], n=1, text=r['text']))
json.dump(deaths, open('deaths.json','w'), indent=0)
print('limit records (dedup uuid):', len(rows), ' deaths:', len(deaths), ' sids:', len({d['sid'] for d in deaths}))
c = collections.Counter()
for d in deaths:
    tx=d['text']; k = 'weekly' if 'weekly' in tx else 'session' if 'session' in tx else 'monthly' if 'monthly' in tx else 'opus/other:'+tx[:50]
    c[k]+=1
print(c.most_common())
fmt=lambda t: datetime.datetime.utcfromtimestamp(t).strftime('%Y-%m-%d %H:%MZ')
print('range', fmt(min(d['t'] for d in deaths)), fmt(max(d['t'] for d in deaths)))
