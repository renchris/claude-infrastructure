import json,sys,os,collections,glob,time
cut=time.time()-2*86400
c=collections.Counter(); n=0; al=collections.Counter()
for r in sys.argv[1:]:
  for f in glob.glob(r+'/*/*.jsonl'):
    if os.path.getmtime(f)<cut: continue
    n+=1
    if n>150: break
    with open(f,'rb') as fh:
      for line in fh:
        if b'autonomous-loop' in line: al[line[:0].decode()+ ('user' if b'"type":"user"' in line[:300] else 'other')]+=1
        if b'"type":"user"' not in line: continue
        try: d=json.loads(line)
        except: continue
        if d.get('type')!='user': continue
        o=d.get('origin'); 
        c[('turnOrigin',json.dumps(d.get('turnOrigin'))[:90])]+=1
        c[('promptSource',json.dumps(d.get('promptSource'))[:60])]+=1
        c[('turnPosition',json.dumps(d.get('turnPosition'))[:40])]+=1
        if d.get('scheduledTaskId'): c[('sched',str(d.get('message',{}).get('content'))[:80])]+=1
print(n, al)
for k,v in sorted(c.items(), key=lambda x:-x[1])[:60]: print(v,k)
