# Dump each operator return (first operator prompt >= idle min 15) with: predecessor final message,
# and the LAST assistant text before the operator prompt (post-gap, if machine turns intervened).
# usage: python3 -I -B dump.py > returns.txt ; writes returns.jsonl
import json, collections, sys
from datetime import datetime
B = '/tmp/idle-recycle-risk/b/'
R = [json.loads(l) for l in open(B + 'ctx.jsonl')]
P = [json.loads(l) for l in open(B + 'points.jsonl')]
for j, r in enumerate(R): r['pid'] = j; r['files'] = P[j]['files']; assert P[j]['req'] == r['req']
elig = [r for r in R if r['first_op'] and r['first_op']['ts'] >= r['t_prev'] + 900]
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
need = collections.defaultdict(list)
for r in elig: need[r['sid']].append(r)
out = open(B + 'adv/returns.jsonl', 'w')
for sid, rs in need.items():
    asst = []
    for path in rs[0]['files']:
        try: fh = open(path, 'rb')
        except OSError: continue
        for line in fh:
            if b'"type":"assistant"' not in line[:3000]: continue
            try: x = json.loads(line)
            except Exception: continue
            if x.get('isSidechain'): continue
            c = (x.get('message') or {}).get('content')
            if not isinstance(c, list): continue
            t = ' '.join(b.get('text', '') for b in c if isinstance(b, dict) and b.get('type') == 'text').strip()
            if t: asst.append((ep(x.get('timestamp', '')) or 0, t))
    asst.sort()
    for r in rs:
        top = r['first_op']['ts']
        post = [a for a in asst if r['t_prev'] + 0.5 < a[0] < top]
        out.write(json.dumps(dict(pid=r['pid'], sid=sid, gap_min=round((top - r['t_prev']) / 60), ctx=r['ctx_eff'], cp=r['cp_also'],
            nmach=r['n_machine_before_op'], mk=r['machine_kinds_before_op'], op=r['first_op']['text'][:1200],
            final=r['last_asst'][-1500:], post_last=(post[-1][1][-1500:] if post else None), n_post=len(post))) + '\n')
out.close()
print('wrote', len(elig))
