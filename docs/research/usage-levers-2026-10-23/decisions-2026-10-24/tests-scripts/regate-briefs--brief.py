import json,sys,glob,os
run,aid=sys.argv[1],sys.argv[2]
n=int(sys.argv[3]) if len(sys.argv)>3 else 4000
paths=[]
for a in ['next','secondary','tertiary','quaternary']:
    paths+=glob.glob(os.path.expanduser(f'~/.claude-{a}/projects/*/*/subagents/workflows/{run}*/agent-{aid}.jsonl'))
p=paths[0]; print(p)
k=0
for l in open(p):
    d=json.loads(l)
    if d.get('type')=='user':
        c=d['message']['content']
        if isinstance(c,list):
            if any(x.get('type')=='tool_result' for x in c): break
            c='\n'.join(x.get('text','') for x in c if x.get('type')=='text')
        print('---USER---'); print(c[:n]); k+=1
