# Existing successor sessions (sim.py's SUCC markers on the first prompt): their first operator-typed prompt
# after the brief, how the successor answered, and that turn's token cost. Empirical anchor for a "miss".
import importlib.util, json, sys, collections
sys.path.insert(0, '/tmp/idle-recycle-risk/b')
from lib import MACHINE_TYPED, v1, OPERATOR_STEP
SIMPY = '/Users/chrisren/Development/claude-infrastructure/docs/research/usage-levers-2026-10-23/w4/sim.py'
sys.argv = [SIMPY, '/tmp/usage-audit/w4']
spec = importlib.util.spec_from_file_location('w4sim', SIMPY); sim = importlib.util.module_from_spec(spec); spec.loader.exec_module(sim)
from datetime import datetime
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
def text_of(c):
    if isinstance(c, list): return ' '.join(b.get('text', '') for b in c if isinstance(b, dict) and b.get('type') == 'text')
    return c if isinstance(c, str) else ''
succ = []
for k, L in sim.sess.items():
    fl = [sim.files[f] for f in sim.sess_files[k]]
    starts = [s for s in (sim.first_line_ts(f['path']) for f in fl) if s is not None]
    if not starts or min(starts) < sim.S + 600 or L[0]['ts'] - min(starts) > 3600: continue
    fp = ' '.join(f['fp'] for f in fl)
    if any(p.lower() in fp.lower() for p in sim.SUCC): succ.append((k, [f['path'] for f in fl]))
out = []
for k, paths in succ:
    users, asst = [], []
    for p in paths:
        for line in open(p, 'rb'):
            h = line[:3000]
            if b'"type":"user"' in h:
                if b'"tool_result"' in line: continue
                r = json.loads(line)
                if r.get('isMeta') or r.get('isSidechain'): continue
                o = r.get('origin') or {}
                t = text_of((r.get('message') or {}).get('content'))
                ok = o.get('kind') if isinstance(o, dict) else None
                op = ok == 'human' and not MACHINE_TYPED.match(t.lstrip()) and r.get('promptSource') != 'sdk'
                users.append((ep(r.get('timestamp', '')) or 0, op, t))
            elif b'"type":"assistant"' in h:
                r = json.loads(line)
                if r.get('isSidechain'): continue
                m = r.get('message') or {}
                asst.append((ep(r.get('timestamp', '')) or 0, r.get('requestId'), text_of(m.get('content')), m.get('usage') or {}))
    users.sort(key=lambda x: x[0]); asst.sort(key=lambda x: x[0])
    ops = [u for u in users[1:] if u[1]]
    if not ops: out.append(dict(sid=k, first_op=None)); continue
    u = ops[0]
    nxt = [x[0] for x in users if x[0] > u[0] + 1]
    te = nxt[0] if nxt else float('inf')
    turn = {}
    for a in asst:
        if u[0] < a[0] < te: turn.setdefault(a[1], a)
    tl = list(turn.values())
    ctx = lambda us: (us.get('input_tokens') or 0) + (us.get('cache_creation_input_tokens') or 0) + (us.get('cache_read_input_tokens') or 0)
    out.append(dict(sid=k, first_op=u[2][:300], v1=v1(u[2]), mins_after_start=round((u[0] - users[0][0]) / 60),
                    n_req=len(tl), growth=(ctx(tl[-1][3]) - ctx(tl[0][3])) if tl else None,
                    reply=' '.join(a[2] for a in asst if u[0] < a[0] < te and a[2].strip())[:400]))
json.dump(out, open('/tmp/idle-recycle-risk/b/succ.json', 'w'), indent=1)
print('successor sessions', len(succ), 'with an operator prompt after the brief', sum(1 for o in out if o['first_op']), 'v1-positive', sum(1 for o in out if o.get('v1')))
for o in out:
    if o['first_op']: print('%s v1=%d +%sm n_req=%s growth=%s | %r\n      REPLY %r' % (o['sid'][:8], o['v1'], o['mins_after_start'], o['n_req'], o['growth'], o['first_op'][:130], o['reply'][:220]))
