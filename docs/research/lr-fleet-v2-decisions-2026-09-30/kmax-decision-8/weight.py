import json, os, glob, datetime, re
STORES = [os.path.expanduser(p) for p in ('~/.claude/projects','~/.claude-secondary/projects','~/.claude-tertiary/projects','~/.claude-quaternary/projects')]
TSRE = re.compile(rb'"timestamp":"([0-9T:\.\-]+Z?)"')
def ts(v):
    try: return datetime.datetime.fromisoformat(v.replace('Z','+00:00')).timestamp()
    except Exception: return None
def file_ts(p):
    out=[]
    with open(p,'rb') as f:
        for line in f:
            m = TSRE.search(line)
            if m:
                t = ts(m.group(1).decode())
                if t: out.append(t)
    return out
deaths = json.load(open('deaths.json'))
cache = {}
def sub_files(sid):
    if sid in cache: return cache[sid]
    files = {}
    for s in STORES:
        for p in glob.glob(os.path.join(s,'*',sid,'subagents','**','agent-*.jsonl'), recursive=True):
            files.setdefault(os.path.basename(p), []).append(p)
    agg = {}
    for name, ps in files.items():
        tt=set()
        for p in ps: tt.update(file_ts(p))
        agg[name]=sorted(tt)
    cache[sid]=agg; return agg
fmt=lambda t: datetime.datetime.utcfromtimestamp(t).strftime('%Y-%m-%d %H:%MZ')
for d in deaths:
    agg = sub_files(d['sid'])
    t=d['t']
    d['w'] = 1 + sum(1 for tt in agg.values() if any(t-600 < x <= t for x in tt))
    # last subagent write after death (within 3h) to see decay
    d['nsub_total']=len(agg)
json.dump(deaths, open('deaths_w.json','w'))
import collections
print(collections.Counter(d['w'] for d in deaths))
heavy=[d for d in deaths if d['w']>8]
print('heavy', len(heavy))
for d in heavy: print(fmt(d['t']), d['acct'], d['sid'][:8], 'w=',d['w'], d['text'][:60])
