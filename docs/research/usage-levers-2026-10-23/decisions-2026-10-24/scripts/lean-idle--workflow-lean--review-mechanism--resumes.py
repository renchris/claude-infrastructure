import json, collections, os, sys
sys.dont_write_bytecode = True
W = '/tmp/lean-idle/workflow-lean'
runs = {}
for l in open(f'{W}/runs.jsonl'):
    r = json.loads(l); runs[r['runId']] = r
calls = [json.loads(l) for l in open(f'{W}/review-mechanism/wfcalls.jsonl')]
# resolve resume calls; need the input resumeFromRunId -> re-read from transcript lines by tool_use id
import re
res = []
byfile = collections.defaultdict(set)
for c in calls:
    if 'resumeFromRunId' in c['keys']:
        byfile[c['p']].add(c['id'])
for p, ids in byfile.items():
    for line in open(p, 'rb'):
        if b'resumeFromRunId' not in line: continue
        try: d = json.loads(line)
        except Exception: continue
        if d.get('type') != 'assistant': continue
        for c in (d.get('message') or {}).get('content') or []:
            if isinstance(c, dict) and c.get('id') in ids:
                inp = c['input']
                res.append(dict(ts=d.get('timestamp'), rid=inp.get('resumeFromRunId'), sp=inp.get('scriptPath'), p=p, id=c['id']))
print('resume calls', len(res))
# what did each resume's tool_result say? and was the run a would-deny?
wd = collections.Counter()
for r in res:
    run = runs.get(r['rid'])
    sp = r['sp']
    verdict = None
    if sp and os.path.isfile(sp):
        src = open(sp, encoding='utf-8', errors='replace').read()
        import importlib.util
        spec = importlib.util.spec_from_file_location('hook', f'{W}/hook_copy.py'); hook = importlib.util.module_from_spec(spec); spec.loader.exec_module(hook)
        slots = [hook.slot_row(src, off, a) for off, a in hook.agent_calls(src)]
        verdict = any(s['verdict']=='would-deny' for s in slots)
        nwd = sum(s['verdict']=='would-deny' for s in slots)
    else:
        nwd = None
    r['wd_now'] = verdict; r['nwd_sites'] = nwd
    r['in_runs'] = bool(run); r['run_wd'] = run.get('would_deny') if run else None
    wd[(verdict, r['run_wd'])] += 1
print('(script-file verdict now, run would_deny in replay):', dict(wd))
json.dump(res, open(f'{W}/review-mechanism/resumes.json', 'w'), indent=1)
for r in res[:60]:
    print(r['ts'][:16], r['rid'], 'wd_file=', r['wd_now'], 'nwd_sites=', r['nwd_sites'], 'run_wd=', r['run_wd'])
