# Build the corpus of Bash tool calls on CC >= 2.1.284, deduped by tool_use_id, with the safety-deny label.
import json,sys,datetime,re
P='Permission for this command was denied by a built-in Claude Code safety check'
files=[l.strip() for l in open('/tmp/autodeny-census/final/corpus_files.txt') if l.strip()]
def vnum(v):
    try: return tuple(int(x) for x in v.split('.'))
    except Exception: return (0,)
def txt_of(c):
    if isinstance(c,str): return c
    if isinstance(c,list): return ' '.join(x.get('text','') for x in c if isinstance(x,dict))
    return ''
uses={}; res={}
for f in files:
    ctx='workflow' if '/subagents/workflows/' in f else 'subagent' if '/subagents/' in f else 'main'
    try: fh=open(f,errors='replace')
    except Exception: continue
    for line in fh:
        hb='"name":"Bash"' in line; hr='"tool_result"' in line
        if not (hb or hr): continue
        try: e=json.loads(line)
        except Exception: continue
        ver=e.get('version') or ''
        msg=e.get('message') or {}
        cont=msg.get('content') if isinstance(msg,dict) else None
        if not isinstance(cont,list): continue
        for b in cont:
            if not isinstance(b,dict): continue
            if b.get('type')=='tool_use' and b.get('name')=='Bash':
                if vnum(ver)<(2,1,284): continue
                cmd=(b.get('input') or {}).get('command')
                if isinstance(cmd,str) and b.get('id') not in uses:
                    uses[b['id']]=dict(cmd=cmd,ver=ver,ts=e.get('timestamp'),ctx=ctx,file=f)
            elif b.get('type')=='tool_result':
                tid=b.get('tool_use_id')
                s=txt_of(b.get('content')).lstrip()
                if s.startswith('Error: '): s=s[7:]
                lab=s.startswith(P)
                pd=e.get('permissionDecision') or {}
                if tid not in res or lab:
                    res[tid]=dict(safety=lab,ts=e.get('timestamp'),pdsrc=pd.get('source'),pdreason=pd.get('reasonType'),pddec=pd.get('decision'),
                                  flagged=(s.split('What was flagged:',1)[1][:400] if lab and 'What was flagged:' in s else ''))
out=[]
for tid,u in uses.items():
    r=res.get(tid)
    if r is None: continue
    u.update(r); u['id']=tid; out.append(u)
json.dump(out,open('/tmp/autodeny-census/final/corpus.json','w'))
print('bash calls',len(out),'safety-labelled',sum(o['safety'] for o in out))
