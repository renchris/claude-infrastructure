import json,os,random,sys,glob
from collections import defaultdict
dirs=[os.path.expanduser(p) for p in ["~/.claude","~/.claude-secondary","~/.claude-tertiary","~/.claude-quaternary"]]
files=[]
for d in dirs:
    r=os.path.realpath(d)
    files += glob.glob(os.path.join(r,"projects","**","*.jsonl"),recursive=True)
files=sorted(set(os.path.realpath(f) for f in files))
random.seed(11)
# sample to bound runtime
SAMPLE=float(os.environ.get("SAMPLE","0.25"))
sel=[f for f in files if random.random()<SAMPLE]
print(f"total jsonl {len(files)} · sampled {len(sel)}",file=sys.stderr)
agg=defaultdict(lambda: dict(turns=0,out=0,cr=0,cc=0,inp=0))
seen=set()
for f in sel:
    try: fh=open(f,errors="replace")
    except OSError: continue
    with fh:
        for line in fh:
            if '"usage"' not in line: continue
            try: r=json.loads(line)
            except Exception: continue
            m=r.get("message") or {}
            if m.get("role")!="assistant": continue
            mid=m.get("id")
            key=(r.get("sessionId"),mid)
            if mid and key in seen: continue
            if mid: seen.add(key)
            u=m.get("usage") or {}
            model=m.get("model") or "?"
            eff=r.get("effort") or "?"
            k=(model,eff)
            a=agg[k]; a["turns"]+=1
            a["out"]+=u.get("output_tokens") or 0
            a["cr"]+=u.get("cache_read_input_tokens") or 0
            a["cc"]+=u.get("cache_creation_input_tokens") or 0
            a["inp"]+=u.get("input_tokens") or 0
print(f"{'model':<26}{'eff':<8}{'turns':>9}{'out/turn':>10}{'cacheRd/turn':>14}{'cacheWr/turn':>14}")
for (model,eff),a in sorted(agg.items(),key=lambda x:-x[1]["turns"]):
    if a["turns"]<50: continue
    t=a["turns"]
    print(f"{model:<26}{eff:<8}{t:>9}{a['out']/t:>10.0f}{a['cr']/t:>14.0f}{a['cc']/t:>14.0f}")
