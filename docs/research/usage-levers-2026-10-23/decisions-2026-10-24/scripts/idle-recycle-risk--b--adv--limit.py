# Idle points whose gap is a usage-limit stall (a synthetic "hit your limit" / API-error message right before
# or inside the gap): the predecessor cannot run a handoff turn on that account then.
import json, collections, re
from datetime import datetime
B = '/tmp/idle-recycle-risk/b/'
P = [json.loads(l) for l in open(B + 'points.jsonl')]
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
LIM = re.compile(r"hit your (weekly |session |5-hour |usage )?limit|usage limit|limit reached|resets \d|rate.?limit|API Error", re.I)
by = collections.defaultdict(list)
for j, p in enumerate(P): p['pid'] = j; by[p['sid']].append(p)
hits = []
for sid, ps in by.items():
    syn = []
    for path in ps[0]['files']:
        try: fh = open(path, 'rb')
        except OSError: continue
        for line in fh:
            if b'"type":"assistant"' not in line[:3000] or (b'<synthetic>' not in line and b'isApiErrorMessage' not in line): continue
            try: x = json.loads(line)
            except Exception: continue
            m = x.get('message') or {}
            t = ' '.join(b.get('text', '') for b in (m.get('content') or []) if isinstance(b, dict))
            if m.get('model') == '<synthetic>' or x.get('isApiErrorMessage'):
                syn.append((ep(x.get('timestamp', '')) or 0, t[:100]))
    for p in ps:
        w = [s for s in syn if p['t_prev'] - 5 < s[0] < p['t_req'] and LIM.search(s[1])]
        if w: hits.append((p['pid'], round((w[0][0] - p['t_prev'])), w[0][1][:70]))
print('points whose idle gap holds a synthetic limit/API-error message: %d of %d' % (len(hits), len(P)))
for h in hits: print(' ', h)
json.dump([h[0] for h in hits], open(B + 'adv/limitpts.json', 'w'))
