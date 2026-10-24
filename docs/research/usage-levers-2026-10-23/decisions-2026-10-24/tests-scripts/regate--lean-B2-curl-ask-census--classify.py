import json,sys,collections as C
D=sys.argv[1]
ci=json.load(open(D+'/ci30.json')); j=json.load(open(D+'/join-out.json'))
P="The user doesn't want to proceed with this tool use"
seen={}
for r in ci:
    t=r['tool_use_id']
    if t=='unknown' or t in seen: continue
    if t not in j: seen[t]=('unknown',r); continue
    texts=[x[0] for x in j[t]]
    st='denied' if any(x.startswith(P) for x in texts) else 'granted'
    seen[t]=(st,r)
print('prompts by outcome',C.Counter(v[0] for v in seen.values()))
print('found in subagent files',sum(1 for k,v in j.items() if any('/subagents/' in f for _,f in v)),'in main',sum(1 for k,v in j.items() if any('/subagents/' not in f for _,f in v)))
for t,(st,r) in sorted(seen.items(), key=lambda kv: kv[1][1]['ts']):
    if st!='granted': print(st.upper(),r['ts'],r['host'],'|',r['reason'][:70],'|',r['session_id'][:8],t[-8:])
for k,v in j.items():
    for x,f in v:
        if any(w in x[:200].lower() for w in ('doesn','reject','denied','not want','interrupt')): print('CHECK',k[-8:],repr(x[:150]))
