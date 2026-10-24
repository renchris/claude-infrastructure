import json,sys,collections
for f in sys.argv[1:]:
    types=collections.Counter()
    for line in open(f):
        try: d=json.loads(line)
        except: continue
        types[d.get("type")]+=1
        if d.get("type")=="assistant" and types["assistant"]<=2:
            m=d["message"]
            print({k:(d[k] if not isinstance(d[k],(dict,list)) else '...') for k in d if k!="message"})
            print(m.get("model"), m.get("id"), m.get("usage"))
    print(f, types)
