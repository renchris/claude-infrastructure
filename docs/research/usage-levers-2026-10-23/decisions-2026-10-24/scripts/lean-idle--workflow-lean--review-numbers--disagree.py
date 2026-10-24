import json,collections,re,sys,random
theirs={}
for l in open("/tmp/lean-idle/workflow-lean/slots.jsonl"):
    t=json.loads(l); theirs[t["aid"]]=(t["cls"],t.get("site_verdict"))
mine=[json.loads(l) for l in open("/tmp/lean-idle/workflow-lean/review-numbers/slots.jsonl")]
HK=("skill","mcp","agent","git_real","ship","home_claude_write")
HARD={"skill","mcp","agent_tool","ship","git_real","claude_home_write"}
GIT=re.compile(r"(?:^|[\s;&|(])git\s+(?:-C\s+(\S+)\s+)?(?:-c\s+\S+\s+)*(commit|push|reset|rebase|merge|cherry-pick|stash|checkout|switch|add)\b")
SHIP=re.compile(r"(?:^|[\s;&|(/])(ship-land|deploy-live)(?:\.sh)?\b")
dis=[s for s in mine if s["agentType"]=="workflow-subagent" and any(s["need"].get(k) for k in HK) and theirs.get(s["aid"],("",None))[0] not in HARD and theirs.get(s["aid"],("",None))[1]=="would-deny"]
print("disagreeing wd slots", len(dis), collections.Counter(k for s in dis for k in HK if s["need"].get(k)))
random.seed(1)
kinds=collections.Counter()
for s in random.sample(dis, min(14,len(dis))):
    shown=0
    for l in open(s["path"]):
        if '"tool_use"' not in l: continue
        d=json.loads(l)
        for c in (d.get("message") or {}).get("content") or []:
            if isinstance(c,dict) and c.get("type")=="tool_use" and c.get("name")=="Bash":
                cmd=c["input"].get("command","")
                c2=re.sub(r"'[^']*'|\"(?:\\.|[^\"\\])*\"", " Q ", re.sub(r"<<-?\s*['\"]?(\w+)['\"]?.*?\n\1\b"," ",cmd,flags=re.S))
                m=GIT.search(c2) or SHIP.search(c2)
                if m and shown<1:
                    print("---", s["aid"][:8], theirs[s["aid"]][0], "|", cmd[max(0,m.start()-80):m.end()+60].replace("\n"," ")[:220]); shown+=1
