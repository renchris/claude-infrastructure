# Blind view of the 60 sampled operator returns: NO reply, NO labels.
# usage: python3 -I -B blind_view.py > blind_view.txt
import json, os
B = '/tmp/idle-recycle-risk/b/'
R = [json.loads(l) for l in open(B + 'ctx.jsonl')]
pids = json.load(open(B + 'sample_pids.json'))
def text_of(c):
    if isinstance(c, list):
        return ' '.join(b.get('text', '') for b in c if isinstance(b, dict) and b.get('type') == 'text')
    return c if isinstance(c, str) else ''
from datetime import datetime
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
for n, pid in enumerate(pids, 1):
    r = R[pid]
    fo = r['first_op']
    # last assistant text strictly before the operator prompt (main thread), from the transcript
    last_before = None
    if fo and os.path.exists(r['path']):
        for line in open(r['path'], 'rb'):
            if b'"type":"assistant"' not in line[:3000]: continue
            try: x = json.loads(line)
            except Exception: continue
            if x.get('isSidechain'): continue
            ts = ep(x.get('timestamp', '')) or 0
            if ts >= fo['ts']: continue
            t = text_of((x.get('message') or {}).get('content'))
            if t.strip(): last_before = (ts, t)
    print('=' * 100)
    print('#%02d pid=%d sid=%s acct=%s ctx_eff=%dk gap=%dm op_after_idle=%dm machine_turns_before=%d %s' % (
        n, pid, r['sid'][:8], r['acct'], r['ctx_eff'] // 1000, r['gap_s'] // 60,
        ((fo['ts'] - r['t_prev']) // 60) if fo else -1, r['n_machine_before_op'], r['machine_kinds_before_op']))
    print('  PREV OPERATOR PROMPT (300):', repr((r['prev_op_text'] or '')[:300]))
    print('  PREDECESSOR FINAL MSG (tail 1500):', repr(r['last_asst'][-1500:]))
    ops = [o for o in r['openers'] if o['kind'] != 'meta']
    for o in ops[:3]:
        print('  GAP OPENER [%s] (200):' % o['kind'], repr(o['text'][:200]))
    if last_before and r['n_machine_before_op'] > 0 and abs(last_before[0] - (r['last_asst_ts'] or 0)) > 1:
        print('  LAST ASSISTANT BEFORE PROMPT (tail 900):', repr(last_before[1][-900:]))
    print('  OPERATOR PROMPT [%s]:' % (fo['kind'] if fo else None), repr((fo['text'] if fo else '')[:1200]))
