# Is the worker's "final message" (last assistant text with ts <= t_prev+0.5) the predecessor's real final
# message? scan.py stamps a request with its FIRST streamed record, so the last request's text block can
# sit after t_prev. True final = last main-chain assistant text before the first non-meta user record after t_prev.
import json, collections, statistics
from datetime import datetime
B = '/tmp/idle-recycle-risk/b/'
R = [json.loads(l) for l in open(B + 'ctx.jsonl')]
P = [json.loads(l) for l in open(B + 'points.jsonl')]
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
by = collections.defaultdict(list)
for j, r in enumerate(R): r['pid'] = j; by[r['sid']].append(r)
res = {}
for sid, rs in by.items():
    asst, users = [], []
    for path in P[rs[0]['pid']]['files']:
        try: fh = open(path, 'rb')
        except OSError: continue
        for line in fh:
            h = line[:3000]
            if b'"type":"assistant"' in h:
                try: x = json.loads(line)
                except Exception: continue
                if x.get('isSidechain'): continue
                c = (x.get('message') or {}).get('content')
                if isinstance(c, list):
                    t = ' '.join(b.get('text', '') for b in c if isinstance(b, dict) and b.get('type') == 'text').strip()
                    if t: asst.append((ep(x.get('timestamp', '')) or 0, t))
            elif b'"type":"user"' in h:
                try: x = json.loads(line)
                except Exception: continue
                if x.get('isSidechain') or x.get('isMeta'): continue
                c = (x.get('message') or {}).get('content')
                if isinstance(c, list) and any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in c): continue
                users.append(ep(x.get('timestamp', '')) or 0)
    asst.sort(); users.sort()
    for r in rs:
        nxt = [u for u in users if u > r['t_prev'] + 0.5]
        lim = nxt[0] if nxt else r['t_req']
        lim = min(lim, r['t_req'] + 0.5)
        tf = [a for a in asst if a[0] < lim]
        res[r['pid']] = dict(true_final=(tf[-1][1] if tf else ''), true_ts=(tf[-1][0] if tf else None), lag=(tf[-1][0] - r['t_prev'] if tf else None))
same = sum(1 for r in R if res[r['pid']]['true_final'].strip()[-300:] == (r['last_asst'] or '').strip()[-300:])
print('points', len(R), 'worker final == true final', same, 'differ', len(R) - same)
lags = [res[r['pid']]['lag'] for r in R if res[r['pid']]['lag'] is not None]
print('true final text ts - t_prev (s): median %.1f p90 %.1f max %.1f' % (statistics.median(lags), sorted(lags)[int(.9*len(lags))], max(lags)))
L = [len(res[r['pid']]['true_final']) for r in R]
print('true final chars over 310: median', statistics.median(L), 'p90', sorted(L)[int(.9*len(L))])
json.dump({str(k): v for k, v in res.items()}, open(B + 'adv/true_final.json', 'w'))
