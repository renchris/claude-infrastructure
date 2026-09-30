import json,sys
f=sys.argv[1]; lo=sys.argv[2] if len(sys.argv)>2 else ''; hi=sys.argv[3] if len(sys.argv)>3 else 'z'
for l in open(f):
    try: r=json.loads(l)
    except: continue
    t=r.get('timestamp','')
    if not (lo<=t<=hi): continue
    if r.get('type')=='user' and not r.get('isMeta'):
        c=(r.get('message') or {}).get('content')
        if isinstance(c,str) and not c.lstrip().startswith('<'):
            print(t,'USER:',c.replace('\n',' ')[:700]); print('--')
    if len(sys.argv)>4 and r.get('type')=='assistant':
        for b in (r.get('message') or {}).get('content') or []:
            if isinstance(b,dict) and b.get('type')=='text' and b.get('text','').strip():
                print(t,'ASSIST:',b['text'].replace('\n',' ')[:int(sys.argv[4])]); print('--')
