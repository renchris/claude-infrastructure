"""Re-verdict every call site with an extended keep-default marker set; join to slots by site index."""
import json,re,sys,importlib.util,collections
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location("hook","/tmp/lean-idle/workflow-lean/hook_copy.py"); hook=importlib.util.module_from_spec(spec); spec.loader.exec_module(hook)
HARD={"skill","mcp","agent_tool","ship","git_real","claude_home_write"}
WW,WO=0.245,0.404
def pp(cw,cr,out,inp,wr): return (WW*(cw+inp)+wr*cr+WO*out)/1e6
def lean_cf(s,t=1.195):
    d=max(0,(s["first_tokens"] or 0)-9200); fw=s["first_cw"] or 0
    ws=min(fw,d); rs=(d-ws)+d*max(0,s["nreq"]-1)
    return max(0,s["cw"]-ws)*t, max(0,s["cr"]-rs)*t, s["out"]*t, s["inp"]*t
EXTRA={
 "mail": re.compile(r"\b(e-?mail|inbox|outlook|ms365|calendar|draft(s|ing)?\s+(an?\s+)?(e-?mail|reply|message)|outbound)\b", re.I),
 "build": re.compile(r"\b(implement|build|fix(es)?|git add|push|land(s|ed|ing)?|worktree)\b", re.I),
}
runs={json.loads(l)["runId"]:json.loads(l) for l in open('runs.jsonl')}
slots=[json.loads(l) for l in open('slots.jsonl')]
def src_of(r):
    if r.get('json'):
        try: return json.load(open(r['json'])).get('script')
        except Exception: pass
    if r.get('script_file'): return open(r['script_file'],encoding='utf-8',errors='replace').read()
    return None
for variant in ("base","mail","mail+build"):
    M=dict(hook.MARKERS)
    if variant!="base": M["mail"]=EXTRA["mail"]
    if variant=="mail+build": M["build"]=EXTRA["build"]
    hook.MARKERS=M
    sv={}
    for rid,r in runs.items():
        src=src_of(r)
        if not src: continue
        sv[rid]=[hook.slot_row(src,off,args)["verdict"] for off,args in hook.agent_calls(src)]
    denied={rid for rid,v in sv.items() if "would-deny" in v}
    fd=set(); save=0; lost_hard=0
    for s in slots:
        if s['agentType']!='workflow-subagent' or s['site'] is None or s['runId'] not in sv: continue
        v=sv[s['runId']][s['site']] if s['site']<len(sv[s['runId']]) else None
        if v=="would-deny":
            if s['cls'] in HARD: fd.add(s['runId'])
            elif s['nreq']: save+=pp(s['cw'],s['cr'],s['out'],s['inp'],0.0057)-pp(*lean_cf(s),0.0057)
    print(f"{variant:11s} denied_runs={len(denied)} false_strict={len(fd)} rate={len(fd)/max(1,len(denied)):.3f} save30d={save:.1f}pp perweek={save/30*7:.1f}")
