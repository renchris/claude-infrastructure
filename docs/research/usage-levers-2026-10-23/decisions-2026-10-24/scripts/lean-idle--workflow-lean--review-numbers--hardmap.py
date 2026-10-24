"""Reviewer: aid -> strict-hard (tight classifier from fd2.py) for every default slot the loose scan flagged."""
import json,runpy,sys
sys.argv=["x"]
f=runpy.run_path("/tmp/lean-idle/workflow-lean/review-numbers/fd2.py", run_name="lib")
out={}
for l in open("/tmp/lean-idle/workflow-lean/review-numbers/slots.jsonl"):
    s=json.loads(l)
    if s["agentType"]=="workflow-subagent" and any(s["need"].get(x) for x in ("skill","mcp","agent","git_real","ship","home_claude_write")):
        out[s["aid"]]=bool(f["strict"](s["path"]))
json.dump(out,open("/tmp/lean-idle/workflow-lean/review-numbers/hardmap.json","w"))
print("flagged",len(out),"strict",sum(out.values()))
