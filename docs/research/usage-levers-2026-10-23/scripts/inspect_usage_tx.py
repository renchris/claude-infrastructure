import json,sys
for f in sys.argv[1:]:
    types={}; asst=0; usage=[]; ver=set(); cmd=None; out=None
    for l in open(f):
        try: r=json.loads(l)
        except: continue
        t=r.get('type'); types[t]=types.get(t,0)+1
        if r.get('version'): ver.add(r['version'])
        m=r.get('message') or {}
        if t=='assistant':
            asst+=1
            if m.get('usage'): usage.append(m['usage'])
        c=m.get('content') if isinstance(m,dict) else None
        if isinstance(c,str) and '<command-name>' in c: cmd=c[c.find('<command-name>')+14:c.find('</command-name>')]
        if t=='system' and r.get('subtype'): out=r.get('subtype')
    print(f.split('/projects/')[0].split('/')[-1], f[-44:], 'ver',sorted(ver),'types',types,'assistant',asst,'usage',usage,'cmd',cmd)
