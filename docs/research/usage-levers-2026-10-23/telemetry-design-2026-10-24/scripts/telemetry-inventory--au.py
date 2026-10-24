import json,sys,collections,datetime as dt
p=sys.argv[1]
rows=collections.defaultdict(list); keys=collections.Counter(); bad=0; stale=collections.Counter(); auth=collections.Counter(); wire=collections.Counter()
for line in open(p):
    try: r=json.loads(line)
    except: bad+=1; continue
    keys[frozenset(r.keys())]+=1
    t=dt.datetime.fromisoformat(r['ts']).timestamp()
    rows[r.get('acct')].append(t)
    stale[(r.get('acct'),r.get('stale'))]+=1; auth[(r.get('acct'),r.get('auth'))]+=1
    wire[(r.get('acct'), r.get('wire_7d_util') is not None)]+=1
print("bad",bad,"schemas",len(keys))
for k,v in keys.most_common(4): print(v, sorted(k)[:40])
now=max(max(v) for v in rows.values())
for a,ts in sorted(rows.items(), key=lambda x:str(x[0])):
    ts.sort(); g=[b-a_ for a_,b in zip(ts,ts[1:])]
    g7=[b-a_ for a_,b in zip(ts,ts[1:]) if b>now-7*86400]
    gs=sorted(g7) or [0]
    big=[x for x in g7 if x>1800]
    print(a,"n",len(ts),"first",dt.datetime.utcfromtimestamp(ts[0]).isoformat(),"n7d",len(g7)+1,"median_gap7d_s",round(gs[len(gs)//2]),"p95",round(gs[int(len(gs)*.95)]),"gaps>30min_7d",len(big),"sum_h",round(sum(big)/3600,1))
print("stale",dict(stale)); print("auth",dict(auth)); print("wire7d_present",dict(wire))
