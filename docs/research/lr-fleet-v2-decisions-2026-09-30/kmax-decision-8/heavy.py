import json, os, glob, datetime, re
from zoneinfo import ZoneInfo
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
fmt=lambda t: datetime.datetime.utcfromtimestamp(t).strftime('%m-%d %H:%MZ')
RS = re.compile(r'resets (\d+)(?::(\d+))?(am|pm) \(([^)]+)\)')
def reset_of(text, t0):
    m = RS.search(text)
    if not m: return None
    h=int(m.group(1))%12 + (12 if m.group(3)=='pm' else 0); mi=int(m.group(2) or 0)
    tz=ZoneInfo(m.group(4)); d=datetime.datetime.fromtimestamp(t0, tz)
    c=d.replace(hour=h, minute=mi, second=0, microsecond=0)
    for k in range(8):
        cc = c + datetime.timedelta(days=k)
        if cc.timestamp() > t0 - 60: return cc.timestamp()
deaths=[d for d in json.load(open('deaths_w.json')) if d['w']>8]
out=[]
for d in deaths:
    sid=d['sid']; t0=d['t']
    subs={}
    for s in STORES:
        for p in glob.glob(os.path.join(s,'*',sid,'subagents','**','agent-*.jsonl'), recursive=True):
            subs.setdefault(os.path.basename(p), set()).update(file_ts(p))
    # top-level copies (incl handed-off) : first non-error assistant record after death
    tops=[]
    for s in STORES:
        tops += glob.glob(os.path.join(s,'*',sid+'.jsonl'))+glob.glob(os.path.join(s,'*',sid+'.jsonl.*'))
    resume=None
    for p in tops:
        for line in open(p, errors='replace'):
            if '"assistant"' not in line: continue
            try: r=json.loads(line)
            except Exception: continue
            if r.get('type')!='assistant' or r.get('isSidechain') or r.get('error') or r.get('isApiErrorMessage'): continue
            t=ts(r.get('timestamp') or '')
            if t and t>t0+5 and (resume is None or t<resume): resume=t
    rs = reset_of(d['text'], t0)
    # w(t) per minute
    wl=[]
    for k in range(0, 181):
        t=t0+60*k
        w=1+sum(1 for tt in subs.values() if any(t-600 < x <= t for x in tt))
        wl.append(w)
    first_le = {c: next((k for k,w in enumerate(wl) if w<=c), None) for c in (8,7,6,5,4,3,2,1)}
    last_sub_before_resume = max([x for tt in subs.values() for x in tt if x <= (resume or 1e12)] or [0])
    rec=dict(sid=sid, acct_guess=d['acct'], death=fmt(t0), t0=t0, text=d['text'][:70], w0=d['w'], nsubs=len(subs),
             reset=fmt(rs) if rs else None, reset_min=round((rs-t0)/60) if rs else None,
             resume=fmt(resume) if resume else None, resume_min=round((resume-t0)/60) if resume else None,
             last_sub_write_min=round((last_sub_before_resume-t0)/60,1),
             w_by_min={k:wl[k] for k in (0,1,2,3,5,8,10,11,12,15,20,30)}, first_min_w_le=first_le)
    out.append(rec); print(json.dumps(rec))
json.dump(out, open('heavy.json','w'))
