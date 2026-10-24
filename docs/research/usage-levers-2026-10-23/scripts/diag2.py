import json,os,sys,re,collections,time,glob
root=sys.argv[1]; CUT=time.time()-5*86400
want=('A session-scoped Stop hook','short and concise','Your response above was stop','(Re-invocation of /e')
got={}; al=collections.Counter(); alx={}
n=0
for f in glob.glob(root+'/*/*.jsonl'):
  if os.path.getmtime(f)<CUT: continue
  n+=1
  with open(f,'rb') as fh:
    for line in fh:
      if b'autonomous-loop' in line:
        try: d=json.loads(line)
        except: continue
        k=(d.get('type'),d.get('subtype') or (d.get('attachment') or {}).get('type') if isinstance(d.get('attachment'),dict) else d.get('subtype'))
        al[str(k)]+=1
        if str(k) not in alx:
          s=line.decode(errors='ignore'); i=s.find('autonomous-loop'); alx[str(k)]=s[max(0,i-150):i+120]
      if b'"isMeta":true' in line and b'"type":"user"' in line and b'tool_use_id' not in line:
        d=json.loads(line); ct=d['message'].get('content'); t=ct if isinstance(ct,str) else ' '.join(x.get('text','') for x in ct if isinstance(x,dict))
        for w in want:
          if t.lstrip().startswith(w) and w not in got: got[w]=t[:500]
print(n); print(al); 
for k,v in alx.items(): print('---AL',k,repr(v))
for k,v in got.items(): print('---META',repr(v))
