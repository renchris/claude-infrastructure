# Heuristic rate of operator "new idea / reframe" prompts in the 67 loop sessions (genuine human prompts only).
import json,re,glob,os,collections,statistics,datetime
IDEA=re.compile(r"\b(what about|how about|as well|also |anyway to|any way to|is there (a|any)|are there any|should we|could we|can we|instead|what if|better than|rather than|i thought|i feel like|we (also )?need|it'?s mission critical|we want|we only want|we don'?t want|remember)\b|https?://",re.I)
SKIP=re.compile(r"^\s*(\(checking in\)|continue|recycle|proceed|hi|yes|no|ok|okay|send them)\b|SCQA|Pyramid Principles|\[limit-recover\]|relaunch|In-place upgrade|Another Claude session|teammate-message",re.I)
asks=json.load(open('/tmp/rescomp/loop_asks.json'))
sids=sorted(set(a['sid'] for a in asks))
def best(sid):
    fs=glob.glob(os.path.expanduser(f'~/.claude*/projects/*/{sid}.jsonl'))
    return max(fs,key=os.path.getsize) if fs else None
tot=collections.Counter(); per=[]
for sid in sids:
    f=best(sid)
    if not f: continue
    ts=[];n=0;ni=0
    for l in open(f,'rb'):
        try: r=json.loads(l)
        except: continue
        if r.get('type')!='user' or r.get('isMeta'): continue
        c=(r.get('message') or {}).get('content')
        if not isinstance(c,str) or c.lstrip().startswith('<') or len(c)>6000: continue
        if 'Workflow harness' in c or c.startswith('TASK') : continue
        n+=1; t=r.get('timestamp','')
        if t: ts.append(t)
        if not SKIP.search(c) and IDEA.search(c):
            ni+=1; print("HIT",sid[:8],t[:16],"|",c.replace("\n"," ")[:200])
    if len(ts)>=2:
        a=datetime.datetime.fromisoformat(min(ts).replace('Z','+00:00')); b=datetime.datetime.fromisoformat(max(ts).replace('Z','+00:00'))
        days=max((b-a).total_seconds()/86400,1/24)
        per.append((sid[:8],n,ni,round(days,2),round(ni/days,1)))
    tot['prompts']+=n; tot['idea']+=ni
print(tot)
per.sort(key=lambda x:-x[2])
print('sessions',len(per),'median idea-prompts/session',statistics.median([p[2] for p in per]),'median span days',statistics.median([p[3] for p in per]))
print('median idea-prompts per active day',statistics.median([p[4] for p in per]))
for p in per[:12]: print(p)
