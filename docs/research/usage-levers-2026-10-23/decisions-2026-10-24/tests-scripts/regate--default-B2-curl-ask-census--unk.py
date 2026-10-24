import json, sys, collections
CUT="2026-09-29T00:00:00Z"; W30="2026-08-30T00:00:00Z"
allu=[];asks=[]
for line in open(sys.argv[1], encoding="utf-8"):
    r=json.loads(line)
    if r["ts"]>=CUT: continue
    if r.get("tool_use_id")=="unknown": allu.append(r)
    if r.get("decision")=="ask": asks.append(r)
print("unknown-tid rows (any decision):", len(allu), "range", min(r['ts'] for r in allu), max(r['ts'] for r in allu))
print("unknown-tid by day:", sorted(collections.Counter(r['ts'][:10] for r in allu).items()))
def cls(s):
    if "confirm intent" in s: return "confirm intent"
    for p in ("No URL parsed","Non-HTTP scheme","GET to unknown host","GET to unvetted host"):
        if s.startswith(p): return p
    return "OTHER"
for lab,sel in (("ALL",asks),("LAST30",[r for r in asks if r['ts']>=W30])):
    real=[r for r in sel if r['tool_use_id']!="unknown"]; unk=[r for r in sel if r['tool_use_id']=="unknown"]
    print(f"{lab}: ask rows {len(sel)}; real-tid rows {len(real)} distinct real tids {len({r['tool_use_id'] for r in real})}; unknown-tid rows {len(unk)} (sessions {len({r['session_id'] for r in unk})})")
    for k,v in collections.Counter(cls(r['reason']) for r in unk).items(): print("   unknown-tid", k, v)
