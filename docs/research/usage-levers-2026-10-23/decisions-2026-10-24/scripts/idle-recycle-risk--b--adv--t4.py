# For gap-ending job notices missing from scan.py's .jobs: how was the job launched?
import json, re, sys
R = [json.loads(l) for l in open('/tmp/idle-recycle-risk/b/ctx.jsonl')]
P = [json.loads(l) for l in open('/tmp/idle-recycle-risk/b/points.jsonl')]
for pid in [1, 4, 53, 89, 105, 170, 12, 27]:
    r = R[pid]
    ks = [o for o in r['openers'] if o['kind'] == 'notice']
    t = ks[-1]['text']
    tu = re.search(r'<tool-use-id>([^<]+)</tool-use-id>', t)
    if not tu: print(pid, 'no tuid'); continue
    tu = tu.group(1).encode()
    found = None
    for path in P[pid]['files']:
        for line in open(path, 'rb'):
            if tu in line and b'"tool_use"' in line and b'"assistant"' in line[:3000]:
                x = json.loads(line)
                for b in x['message']['content']:
                    if isinstance(b, dict) and b.get('id') == tu.decode():
                        found = (x.get('timestamp'), b.get('name'), {k: (str(v)[:60]) for k, v in (b.get('input') or {}).items() if k != 'command'}, 'usage' in x['message'])
                break
    # also: any tool_result for it saying moved to background?
    print(pid, 't_prev+15m=%s' % r['t_prev'], found)
