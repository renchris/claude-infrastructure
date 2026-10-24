import json, importlib.util, sys, hashlib, collections, os
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('hook', '/Users/chrisren/Development/claude-infrastructure/hooks/workflow-lean-shadow.py')
hook = importlib.util.module_from_spec(spec); spec.loader.exec_module(hook)
n=wd=0; shas={}; mismatch=0; noscr=0
for l in open('/tmp/lean-idle/workflow-lean/runs.jsonl'):
    r=json.loads(l)
    src=None
    if r.get('json'):
        try: src=json.load(open(r['json'])).get('script')
        except Exception: pass
    if not src and r.get('script_file') and os.path.isfile(r['script_file']):
        src=open(r['script_file'],encoding='utf-8',errors='replace').read()
    if not src and r.get('scriptPath') and os.path.isfile(r['scriptPath']):
        src=open(r['scriptPath'],encoding='utf-8',errors='replace').read()
    if not src: noscr+=1; continue
    slots=[hook.slot_row(src,o,a) for o,a in hook.agent_calls(src)]
    w=any(s['verdict']=='would-deny' for s in slots)
    n+=1; wd+=w; shas[hashlib.sha1(src.encode()).hexdigest()]=w
    if bool(r.get('would_deny'))!=w: mismatch+=1
print('runs with script', n, 'would-deny', wd, 'unique scripts', len(shas), 'wd unique', sum(shas.values()), 'mismatch vs replay', mismatch, 'no script', noscr)
