import json,sys
for p in sys.argv[1:]:
    ids=set(); 
    for l in open(p):
        d=json.loads(l)
        if d.get('type')=='assistant': ids.add(d['message'].get('id'))
    print(len(ids),p.split('/')[-1])
