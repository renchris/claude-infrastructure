import os, sys, json
from datetime import datetime
root = sys.argv[1]; t_end = float(sys.argv[2])
start7 = t_end - 7*86400; start24 = t_end - 86400
best = {}  # msgid -> [ts, ctx, inp, cc, cr, out, is_sub, sid]
sess_first = {}; sess_last = {}
for dp, dn, fn in os.walk(root):
    for f in fn:
        if not f.endswith('.jsonl'): continue
        p = os.path.join(dp, f)
        try:
            if os.stat(p).st_mtime < start7: continue
            fh = open(p, 'rb')
        except OSError: continue
        is_sub = '/subagents/' in p
        with fh:
            for line in fh:
                if b'"assistant"' not in line: continue
                try: r = json.loads(line)
                except Exception: continue
                if r.get('type') != 'assistant': continue
                m = r.get('message') or {}
                if m.get('model') == '<synthetic>' or not m.get('id'): continue
                try: e = datetime.fromisoformat(r['timestamp'].replace('Z', '+00:00')).timestamp()
                except Exception: continue
                if e < start7 or e > t_end: continue
                u = m.get('usage') or {}
                inp = u.get('input_tokens') or 0; cc = u.get('cache_creation_input_tokens') or 0
                cr = u.get('cache_read_input_tokens') or 0; out = u.get('output_tokens') or 0
                k = m['id']
                if k in best:
                    b = best[k]; b[5] = max(b[5], out)
                else:
                    best[k] = [e, inp + cc + cr, inp, cc, cr, out, is_sub, r.get('sessionId')]
def share(rows, wf):
    tot = sum(wf(r) for r in rows); hi = sum(wf(r) for r in rows if r[1] > 150000)
    return round(100 * hi / tot, 1) if tot else None
W = {
 'requests': lambda r: 1,
 'all_tokens': lambda r: r[2] + r[3] + r[4] + r[5],
 'price_weighted(in1,cc1.25,cr0.1,out5)': lambda r: r[2] + 1.25*r[3] + 0.1*r[4] + 5*r[5],
 'output_only': lambda r: r[5],
 'noncached(in+cc+out)': lambda r: r[2] + r[3] + r[5],
}
for name, s in (('24h', start24), ('7d', start7)):
    rows = [r for r in best.values() if r[0] >= s]
    print(name, 'requests', len(rows), 'sessions', len(set(r[7] for r in rows)))
    for wn, wf in W.items(): print('  >150k share by', wn, share(rows, wf))
