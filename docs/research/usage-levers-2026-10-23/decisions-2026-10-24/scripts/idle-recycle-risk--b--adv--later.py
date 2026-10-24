# Operator prompts AFTER the first return, up to the next recycle point in the session (or session end):
# the worker labelled only the first. Count them, and flag explicit back-references to earlier conversation.
import json, collections, re, sys
from datetime import datetime
sys.path.insert(0, '/tmp/idle-recycle-risk/b')
from lib import MACHINE_TYPED
B = '/tmp/idle-recycle-risk/b/'
R = [json.loads(l) for l in open(B + 'ctx.jsonl')]
P = [json.loads(l) for l in open(B + 'points.jsonl')]
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
BACK = re.compile(r"\b(earlier|we discussed|you (said|mentioned|suggested|recommended)|as (we|you) (said|discussed|did|have done|'ve done)|last time|yesterday|remember|previously|before you|the one (we|you)|we talked|that we (did|had|found)|you found|our (earlier|previous))\b", re.I)
by = collections.defaultdict(list)
for j, r in enumerate(R):
    r['pid'] = j
    if r['first_op'] and r['first_op']['ts'] >= r['t_prev'] + 900: by[r['sid']].append(r)
tot = 0; flagged = []; nsess = 0
for sid, rs in by.items():
    pts = sorted(p['t_prev'] for p in P if p['sid'] == sid)
    users = []
    for path in P[rs[0]['pid']]['files']:
        try: fh = open(path, 'rb')
        except OSError: continue
        for line in fh:
            if b'"type":"user"' not in line[:3000] or b'"tool_result"' in line: continue
            try: x = json.loads(line)
            except Exception: continue
            if x.get('isMeta') or x.get('isSidechain'): continue
            o = x.get('origin') or {}
            c = (x.get('message') or {}).get('content')
            t = c if isinstance(c, str) else ' '.join(b.get('text', '') for b in c if isinstance(b, dict) and b.get('type') == 'text') if isinstance(c, list) else ''
            if (isinstance(o, dict) and o.get('kind') == 'human' and not MACHINE_TYPED.match(t.lstrip())) or t.lstrip().startswith(('<bash-input>', '<command-name>')):
                users.append((ep(x.get('timestamp', '')) or 0, t))
    users = sorted(set(users))
    done = set()
    for r in rs:
        t0 = r['first_op']['ts']
        if t0 in done: continue
        done.add(t0); nsess += 1
        stop = min([p + 900 for p in pts if p > t0] or [9e18])
        later = [u for u in users if t0 + 1 < u[0] < stop]
        tot += len(later)
        for u in later:
            if BACK.search(u[1]) and not u[1].lstrip().startswith(('<bash-input>', '<command')):
                flagged.append((r['pid'], round((u[0] - t0) / 60), ' '.join(u[1].split())[:160]))
print('distinct returns %d; later operator prompts to the same successor (before the next recycle) %d' % (nsess, tot))
print('later prompts with an explicit back-reference word: %d' % len(flagged))
for f in flagged: print(' ', f)
