"""Reviewer: strict false-deny recount with a tighter git/ship classifier (subcommand must end at
whitespace/terminator; ship-land/deploy-live only as a command word), re-reading each candidate slot."""
import json,collections,re,runpy,sys
sys.argv=["x"]
g=runpy.run_path("/tmp/lean-idle/workflow-lean/review-numbers/savings.py", run_name="lib")
S,runs=g["S"],g["runs"]
GIT=re.compile(r"(?:^|[;&|(]\s*|&&\s*|\|\|\s*|^\s*)(?:\w+=\S*\s+)*git\s+(?:-C\s+(\S+)\s+)?(?:-c\s+\S+\s+)*(commit|push|reset\s+--hard|rebase|merge(?=\s)(?!\s+--(?:is-ancestor|abort))|cherry-pick|stash(?:\s+(?:push|pop|apply|drop|save))?(?=\s|$|[;&|])|checkout|switch|add)(?=\s|$|[;&|)])", re.M)
SHIP=re.compile(r"(?:^|[;&|(]\s*|&&\s*|^\s*)(?:\S*/)?(ship-land|deploy-live)(?:\.sh)?(?=\s|$)", re.M)
TMP=re.compile(r"/tmp\b|/private/tmp|/var/folders|mktemp|TMPDIR")
def strict(path):
    k=collections.Counter()
    for l in open(path):
        if '"tool_use"' not in l: continue
        d=json.loads(l)
        for c in (d.get("message") or {}).get("content") or []:
            if not isinstance(c,dict) or c.get("type")!="tool_use": continue
            n=c.get("name",""); inp=c.get("input") or {}
            if n=="Skill": k["skill"]+=1
            elif n.startswith("mcp__"): k["mcp"]+=1
            elif n in ("Agent","Task"): k["agent"]+=1
            elif n in ("Write","Edit","MultiEdit") and re.match(r"^(/Users/[^/]+|~)/\.claude", str(inp.get("file_path",""))): k["claude_home"]+=1
            elif n=="Bash":
                cmd=str(inp.get("command",""))
                c2=re.sub(r"<<-?\s*['\"]?(\w+)['\"]?.*?\n\s*\1\b"," ",cmd,flags=re.S)
                c2=re.sub(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", " Q ", c2)
                m=GIT.search(c2)
                if m and not TMP.search(cmd): k["git_real"]+=1
                if SHIP.search(c2): k["ship"]+=1
    return k
CUT=1790226000000
import datetime
def st(r):
    if r.get("start"): return r["start"]
    if r.get("ts_min"): return datetime.datetime.fromisoformat(r["ts_min"].replace("Z","+00:00")).timestamp()*1000
    return 0
wd={rid for rid,r in runs.items() if r.get("would_deny") and r.get("sha") and st(r)>=CUT}
hardruns=collections.defaultdict(set); nslots=nhard=0
for s in S:
    if s["runId"] in wd and s["agentType"]=="workflow-subagent" and s.get("sv")=="would-deny":
        nslots+=1
        if any(s["need"].get(x) for x in ("skill","mcp","agent","git_real","ship","home_claude_write")):
            k=strict(s["path"])
            if k:
                nhard+=1
                for x in k: hardruns[x].add(s["runId"])
allr=set().union(*hardruns.values()) if hardruns else set()
print("denied runs",len(wd),"strict false-deny runs",len(allr),f"{100*len(allr)/len(wd):.1f}%","slots",nhard,"of",nslots,{k:len(v) for k,v in hardruns.items()})
