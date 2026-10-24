# For each wrong-action case, write replay/<pid>.in.txt (state at the recycle moment t_prev+900, the machine
# inputs between recycle and the operator's reply, the predecessor's in-gap replies kept separate, the reply)
# and replay/<pid>.after.txt (what the predecessor did next; NOT read until the action is recorded).
# usage: python3 -I -B replay_extract.py
import json, os
from datetime import datetime
B = '/tmp/idle-recycle-risk/b/'; K = '/tmp/conv-tests/43da49891e75/replay/'
R = [json.loads(l) for l in open(B + 'ctx.jsonl')]
P = [json.loads(l) for l in open(B + 'points.jsonl')]
CASES = [40, 69, 120, 136, 167, 168, 187, 208, 263, 272]
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
def blocks(c):
    if isinstance(c, str): return [('text', c)]
    out = []
    for b in c or []:
        if not isinstance(b, dict): continue
        t = b.get('type')
        if t == 'text': out.append(('text', b.get('text', '')))
        elif t == 'tool_use': out.append(('tool_use', b.get('name', '') + ' ' + json.dumps(b.get('input', {}))[:700]))
        elif t == 'tool_result':
            cc = b.get('content'); s = cc if isinstance(cc, str) else ' '.join(x.get('text', '') for x in (cc or []) if isinstance(x, dict))
            out.append(('tool_result', s[:500]))
    return out
for pid in CASES:
    r = R[pid]; files = P[pid]['files']
    recs = []
    for f in files:
        if not os.path.exists(f): continue
        for line in open(f, 'rb'):
            try: x = json.loads(line)
            except Exception: continue
            if x.get('type') not in ('user', 'assistant') or x.get('isSidechain'): continue
            ts = ep(x.get('timestamp', '')) or 0
            recs.append((ts, x['type'], blocks((x.get('message') or {}).get('content')), x.get('isMeta')))
    recs.sort(key=lambda z: z[0])
    t_rc = r['t_prev'] + 900; t_op = r['first_op']['ts']
    before = [z for z in recs if z[0] <= t_rc]
    between = [z for z in recs if t_rc < z[0] < t_op - 0.5]
    after = [z for z in recs if z[0] >= t_op - 0.5]
    # predecessor's assistant texts before the recycle moment (last 6) - the final one is the G3 final message
    atexts = [(z[0], b[1]) for z in before if z[1] == 'assistant' for b in z[2] if b[0] == 'text' and b[1].strip()]
    with open(K + '%d.in.txt' % pid, 'w') as o:
        o.write('pid=%d sid=%s acct=%s ctx_eff=%dk path=%s\nrecycle moment=%s  operator reply at=%s (+%dm)\n' % (
            pid, r['sid'], r['acct'], int(float(r['ctx_eff'])) // 1000, r['path'],
            datetime.utcfromtimestamp(t_rc).isoformat(), datetime.utcfromtimestamp(t_op).isoformat(), (t_op - t_rc) // 60))
        o.write('\n##### PREDECESSOR ASSISTANT TEXTS BEFORE RECYCLE (last 6, oldest first; the last one is the G3 final message)\n')
        for ts, t in atexts[-6:]:
            o.write('--- [%s]\n%s\n' % (datetime.utcfromtimestamp(ts).isoformat(), t[-5000:]))
        ops = [(z[0], b[1]) for z in before if z[1] == 'user' and not z[3] for b in z[2] if b[0] == 'text' and b[1].strip()]
        o.write('\n##### LAST 4 USER-SIDE TEXT INPUTS BEFORE RECYCLE (operator or machine)\n')
        for ts, t in ops[-4:]:
            o.write('--- [%s]\n%s\n' % (datetime.utcfromtimestamp(ts).isoformat(), t[:1500]))
        o.write('\n##### MACHINE INPUTS BETWEEN RECYCLE AND OPERATOR REPLY (the successor would receive these)\n')
        for z in between:
            if z[1] == 'user' and not z[3]:
                for b in z[2]:
                    if b[0] == 'text' and b[1].strip(): o.write('--- [%s] %s\n' % (datetime.utcfromtimestamp(z[0]).isoformat(), b[1][:1200]))
        o.write('\n##### PREDECESSOR ASSISTANT TEXTS BETWEEN RECYCLE AND REPLY (lenient variant: assume the successor said these)\n')
        for z in between:
            if z[1] == 'assistant':
                for b in z[2]:
                    if b[0] == 'text' and b[1].strip(): o.write('--- [%s]\n%s\n' % (datetime.utcfromtimestamp(z[0]).isoformat(), b[1][-2500:]))
        o.write('\n##### OPERATOR REPLY\n%s\n' % r['first_op']['text'])
    with open(K + '%d.after.txt' % pid, 'w') as o:
        for z in after[:60]:
            for b in z[2]:
                o.write('[%s] %s %s: %s\n' % (datetime.utcfromtimestamp(z[0]).isoformat(), z[1], b[0], b[1][:1500]))
    print(pid, 'before', len(before), 'between', len(between), 'after', len(after))
