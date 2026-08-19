import json,os,glob,datetime,collections,bisect,re
roots=[os.path.expanduser(p) for p in ("~/.claude","~/.claude-secondary","~/.claude-tertiary","~/.claude-quaternary")]
def ts2dt(s):
    s=re.sub(r'\.\d+','',s).replace("Z","+0000")
    return datetime.datetime.strptime(s,"%Y-%m-%dT%H:%M:%S%z")
pdt=sorted(ts2dt(json.loads(l)["ts"]) for l in open(os.path.expanduser("~/.claude/logs/pane-spawns.jsonl"))
           if '"ppid_comm": "claude"' in l or '"ppid_comm":"claude"' in l)
lo,hi=pdt[0],pdt[-1]
W=datetime.timedelta(seconds=60)
calls=[]  # (dt, named:bool, subtype)
seen=set()
for root in roots:
    for fp in glob.glob(root+"/projects/*/*.jsonl"):
        b=os.path.basename(fp)
        if b in seen: continue
        seen.add(b)
        try: f=open(fp,errors="replace")
        except: continue
        with f:
            for ln in f:
                if '"tool_use"' not in ln: continue
                try: r=json.loads(ln)
                except: continue
                if r.get("type")!="assistant" or not r.get("timestamp"): continue
                try: d=ts2dt(r["timestamp"])
                except: continue
                if d<lo or d>hi: continue
                for c in ((r.get("message") or {}).get("content") or []):
                    if isinstance(c,dict) and c.get("type")=="tool_use" and c.get("name") in ("Agent","Task"):
                        i=c.get("input") or {}
                        calls.append((d,bool(i.get("name")),i.get("subagent_type") or "?"))
def rate(off_s):
    off=datetime.timedelta(seconds=off_s)
    nh=nt=uh=ut=0
    for d,named,_ in calls:
        dd=d+off
        i=bisect.bisect_left(pdt,dd-W)
        hit = i<len(pdt) and pdt[i]<=dd+W
        if named: nt+=1; nh+=hit
        else:     ut+=1; uh+=hit
    return nh,nt,uh,ut
print("total Agent/Task calls in window:",len(calls))
print(f"{'offset':>10} {'named hit%':>12} {'unnamed hit%':>14}")
for off in (0, 900, 3600, 7200, 86400, -3600, -86400):
    nh,nt,uh,ut=rate(off)
    print(f"{off:>10} {100*nh/nt:>11.1f}% ({nh}/{nt})  {100*uh/ut:>7.1f}% ({uh}/{ut})")
# subtype-controlled: only deep-research, only Explore
for st in ("deep-research","Explore","general-purpose"):
    sub=[c for c in calls if c[2]==st]
    nh=nt=uh=ut=0
    for d,named,_ in sub:
        i=bisect.bisect_left(pdt,d-W); hit=i<len(pdt) and pdt[i]<=d+W
        if named: nt+=1; nh+=hit
        else: ut+=1; uh+=hit
    print(f"[{st:16}] named {nh}/{nt}  unnamed {uh}/{ut}")
