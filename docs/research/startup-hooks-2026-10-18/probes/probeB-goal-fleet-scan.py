import json,os,sys,glob,time
from datetime import datetime
cut=time.time()-48*3600
files=[f for f in glob.glob(os.path.expanduser("~/.claude*/projects/*/*.jsonl")) if os.path.getmtime(f)>cut]
def ts(s):
    try: return datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()
    except Exception: return None
out=[]
for f in files:
    try: rows=[json.loads(l) for l in open(f) if '"timestamp"' in l]
    except Exception: continue
    if not any((r.get("attachment") or {}).get("type")=="goal_status" for r in rows): continue
    t0=None; wake=None; evals=[]; wakearm=False
    for r in rows:
        t=ts(r.get("timestamp","")) 
        if t is None: continue
        if t0 is None: t0=t
        s=json.dumps(r)
        if "mailbox-wake-arm" in s: wakearm=True
        if wake is None and ("Peer mail arrived while you were idle" in s or ("task-notification" in s and "peer mail" in s)): wake=t
        a=r.get("attachment") or {}
        if a.get("type")=="goal_status" and a.get("met") is False and not a.get("sentinel"): evals.append(t)
    early=[e for e in evals if e-t0<14000 and (wake is None or e<wake)]
    out.append((os.path.basename(f)[:8], len(evals), len(early), wakearm, round((early[0]-t0)/60,1) if early else None))
print("sessions with goal_status in 48h:",len(out))
print("with >=1 evaluation inside birth-watcher window before any mail wake:",sum(1 for o in out if o[2]>0))
print("total such evaluations:",sum(o[2] for o in out))
for o in sorted(out,key=lambda o:-o[2])[:12]: print(o)
