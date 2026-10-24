import json,sys,os,collections,re,glob,time
# survey user records that are NOT pure tool_result; bucket by prefix
roots=sys.argv[1:]
cut=time.time()-2*86400
c=collections.Counter(); keys=collections.Counter(); ex={}
n=0
for r in roots:
  for f in glob.glob(r+'/*/*.jsonl'):
    if os.path.getmtime(f)<cut: continue
    n+=1
    if n>150: break
    with open(f,'rb') as fh:
      for line in fh:
        if b'"type":"user"' not in line[:400] and b'"type": "user"' not in line[:400]:
          if b'"type":"user"' not in line: continue
        try: d=json.loads(line)
        except: continue
        if d.get('type')!='user': continue
        m=d.get('message',{}); ct=m.get('content')
        if isinstance(ct,list):
          if all(isinstance(x,dict) and x.get('type')=='tool_result' for x in ct): continue
          txt=' '.join(x.get('text','') for x in ct if isinstance(x,dict) and x.get('type')=='text')
        else: txt=ct or ''
        for k in d: keys[k]+=1
        p=re.sub(r'\s+',' ',txt.strip())[:60]
        tag=(d.get('isMeta'),d.get('origin',None) if not isinstance(d.get('origin'),dict) else json.dumps(d.get('origin'))[:60], p[:28])
        c[tag]+=1; ex.setdefault(tag,p)
print('files',n)
print(keys.most_common(40))
for k,v in c.most_common(70): print(v,k)
