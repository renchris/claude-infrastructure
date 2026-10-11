import json,sys,re,datetime,collections,os
P='Permission for this command was denied by a built-in Claude Code safety check'
files=set()
for lst in sys.argv[1:]:
    files|={l.strip() for l in open(lst) if l.strip()}
def iso(s): return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
def txt_of(c):
    if isinstance(c,str): return c
    if isinstance(c,list): return ' '.join(x.get('text','') for x in c if isinstance(x,dict))
    return ''
hits={}
for f in sorted(files):
    uses={}
    try: fh=open(f,errors='replace')
    except Exception: continue
    for line in fh:
        if '"tool_use"' not in line and P not in line: continue
        try: e=json.loads(line)
        except Exception: continue
        msg=e.get('message') or {}
        cont=msg.get('content') if isinstance(msg,dict) else None
        if not isinstance(cont,list): continue
        for b in cont:
            if not isinstance(b,dict): continue
            if b.get('type')=='tool_use': uses[b.get('id')]=(e.get('timestamp'),b.get('name'),b.get('input'))
            elif b.get('type')=='tool_result':
                t=txt_of(b.get('content'))
                s=t.lstrip()
                if s.startswith('Error: '): s=s[7:]
                if not s.startswith(P): continue
                tid=b.get('tool_use_id'); u=uses.get(tid)
                el=None
                if u and u[0] and e.get('timestamp'): el=(iso(e['timestamp'])-iso(u[0])).total_seconds()
                flagged=s.split('What was flagged:',1)[1].strip() if 'What was flagged:' in s else ''
                capped=bool(re.search(r'gone unanswered \d+ times',s))
                rec=dict(tool_use_id=tid,file=f,sid=e.get('sessionId'),ts=e.get('timestamp'),ver=e.get('version'),elapsed=el,
                         tool=u[1] if u else None,cmd=(u[2] or {}).get('command') if u and isinstance(u[2],dict) else None,
                         ctx=('workflow' if '/subagents/workflows/' in f else 'subagent' if '/subagents/' in f else 'main'),
                         flagged=flagged,capped=capped,stores=[f.split('/projects/')[0].replace(os.path.expanduser('~'),'~')])
                if tid in hits:
                    hits[tid]['stores']=sorted(set(hits[tid]['stores']+rec['stores']))
                else: hits[tid]=rec
json.dump(list(hits.values()),open('/tmp/autodeny-census/final/hits.json','w'),indent=0)
print('unique',len(hits))
