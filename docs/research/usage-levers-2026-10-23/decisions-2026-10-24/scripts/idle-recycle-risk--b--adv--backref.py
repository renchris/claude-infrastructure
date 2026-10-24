# For a few later back-referencing prompts: was the referent first said BEFORE the recycle point (predecessor)
# or only after the operator's return (the successor's own conversation)?
import json, sys
from datetime import datetime
B = '/tmp/idle-recycle-risk/b/'
R = [json.loads(l) for l in open(B + 'ctx.jsonl')]
P = [json.loads(l) for l in open(B + 'points.jsonl')]
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
cases = [(149, 'Landing Standby'), (149, 'Standby'), (229, 'Q2 2027'), (229, 'taxiway'), (156, 'public record'), (163, 'Freddie Mac'), (159, '1176 Ridgeway'), (294, 'selection')]
for pid, kw in cases:
    r = R[pid]; t_rec = r['t_prev'] + 900; t_op = r['first_op']['ts']
    first = None
    for path in P[pid]['files']:
        for line in open(path, 'rb'):
            if b'"type":"assistant"' not in line[:3000] or kw.lower().encode() not in line.lower(): continue
            x = json.loads(line)
            if x.get('isSidechain'): continue
            t = ep(x.get('timestamp', '')) or 0
            if first is None or t < first: first = t
    where = 'never in main-thread assistant text' if first is None else ('PRE-recycle (predecessor)' if first < t_rec else 'post-return (successor)' if first > t_op else 'in the gap (machine turns)')
    print(pid, repr(kw), where)
