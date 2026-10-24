import json,glob,os,re
idx={}
for a in ['next','secondary','tertiary','quaternary']:
    for p in glob.glob(os.path.expanduser(f'~/.claude-{a}/projects/*/*/subagents/workflows/wf_*/agent-*.jsonl')):
        idx[os.path.basename(p)[6:-6]]=p
out=open('cands2.jsonl','w')
for l in open('/tmp/lean-idle/workflow-lean/slots.jsonl'):
    d=json.loads(l)
    if not (d['agentType']=='workflow-subagent' and 15<=d['nreq']<=60 and not d['repo_write'] and not d['home_claude_write'] and not d['git_real'] and not d['skills'] and not d['mcps'] and not d['agent_tool'] and not d['ship'] and not set(d['tools'])&{'Edit','NotebookEdit','WebFetch','WebSearch'}): continue
    p=idx.get(d['aid'])
    if not p: continue
    brief=''
    for ln in open(p):
        r=json.loads(ln)
        if r.get('type')=='user':
            c=r['message']['content']
            if isinstance(c,list):
                if any(x.get('type')=='tool_result' for x in c): break
                c='\n'.join(x.get('text','') for x in c if x.get('type')=='text')
            brief+=c+'\n'
    i=brief.find('computed task text follows:'); t=brief[i+28:] if i>0 else brief
    if not re.search(r'projects/\*|transcripts', t): continue
    if re.search(r'(?i)kitty|truememory|reso-management|agent-context-sync|mjml|craigslist|sevenrooms|voiceink', t): continue
    d['path']=p; d['brief']=t
    out.write(json.dumps(d)+'\n')
