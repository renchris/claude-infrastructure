import os,json,sys,glob,re,collections
roots=[os.path.expanduser(p) for p in ['~/.claude/projects','~/.claude-secondary/projects','~/.claude-tertiary/projects','~/.claude-quaternary/projects','~/.claude-next4/projects']]
seen=set();files=[]
for r in roots:
    for dp,dn,fn in os.walk(r,followlinks=True):
        for f in fn:
            if f.endswith('.jsonl'):
                p=os.path.realpath(os.path.join(dp,f))
                if p not in seen: seen.add(p); files.append(p)
pat=re.compile(rb'permissionDecision\\":\s?\\"ask')
out=open('/tmp/hookask-verify/asks2.jsonl','w')
nfiles=0
for p in files:
    try: b=open(p,'rb').read()
    except Exception: continue
    if not pat.search(b): continue
    nfiles+=1
    asks={};results={};rej={}
    for line in b.split(b'\n'):
        if not line: continue
        if b'hook_success' in line and pat.search(line):
            try: o=json.loads(line)
            except Exception: continue
            a=o.get('attachment') or {}
            if a.get('type')!='hook_success': continue
            so=a.get('stdout') or ''
            try:
                d=json.loads(so); h=d.get('hookSpecificOutput',{})
                if h.get('permissionDecision')!='ask': continue
                reason=h.get('permissionDecisionReason','')
            except Exception:
                reason='UNPARSED'
            asks.setdefault(a.get('toolUseID'),[]).append(dict(file=p,sub='/subagents/' in p,hook=a.get('command'),hookName=a.get('hookName'),reason=reason[:160],tid=a.get('toolUseID'),ts=o.get('timestamp'),version=o.get('version'),sid=o.get('sessionId')))
        elif b'tool_result' in line:
            try: o=json.loads(line)
            except Exception: continue
            m=o.get('message') or {}
            c=m.get('content')
            if isinstance(c,list):
                for it in c:
                    if isinstance(it,dict) and it.get('type')=='tool_result':
                        cc=it.get('content')
                        if isinstance(cc,list): cc=' '.join(x.get('text','') for x in cc if isinstance(x,dict))
                        S=str(cc); k='denied' if (S.startswith('Permission to use') and 'has been denied' in S[-400:]) else ('user-rejected' if ("doesn't want to proceed" in S[:400] or 'The user doesn' in S[:200]) else 'ran'); results[it.get('tool_use_id')]=(S[:200],o.get('timestamp'),k,it.get('is_error'))
    for tid,lst in asks.items():
        r=results.get(tid)
        for a in lst:
            if r is None: a['outcome']='noresult'
            else:
                s=r[0]; a['outcome']=r[2]; a['is_error']=r[3]
                a['result_ts']=r[1]; a['result_head']=s[:100]
            out.write(json.dumps(a)+'\n')
print('files scanned',len(files),'files with ask',nfiles)
