import json, sys, collections
CUT="2026-09-29T00:00:00Z"; W30="2026-08-30T00:00:00Z"
g=collections.defaultdict(list)
for line in open(sys.argv[1], encoding="utf-8"):
    r=json.loads(line)
    if r["ts"]>=CUT or r.get("decision")!="ask": continue
    g[r["tool_use_id"]].append(r)
print("tid=='unknown' rows:", len(g.get("unknown",[])))
multi={k:v for k,v in g.items() if len(v)>1}
print("tids with >1 ask row:", len(multi), "rows in them:", sum(len(v) for v in multi.values()))
same=sum(1 for v in multi.values() if len({(r['reason'],r['cmd_redacted']) for r in v})==1)
print("  of which all rows same reason+cmd:", same)
span=collections.Counter()
for v in multi.values():
    ts=sorted(r['ts'] for r in v); 
    from datetime import datetime
    d=(datetime.fromisoformat(ts[-1][:-1])-datetime.fromisoformat(ts[0][:-1])).total_seconds()
    span['0s' if d==0 else '<=2s' if d<=2 else '<=60s' if d<=60 else '>60s']+=1
print("  ts spread within tid:", span)
# sessions differ within tid?
print("  tids spanning >1 session_id:", sum(1 for v in multi.values() if len({r['session_id'] for r in v})>1))
# example
k=next(iter(multi)); 
for r in multi[k]: print("  ex", r['ts'], r['session_id'][:8], r['reason'][:60])
