# Survey non-tool_result user records in window: counts of origin.kind / promptSource / queueOrigin / turnOrigin,
# and top text prefixes (first 50 chars) for origin.kind=human. Streams; bounded by file list from scan.py .files.
import json, sys, collections, glob
S, E = (float(x) for x in open('/tmp/usage-audit/w4/window').read().split())
from datetime import datetime
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
paths = []
for f in glob.glob('/tmp/usage-audit/w4/rows_*.tsv.files'):
    for line in open(f):
        paths.append(line.rstrip('\n').split('\t')[5])
c_or = collections.Counter(); c_ps = collections.Counter(); c_q = collections.Counter(); c_to = collections.Counter()
pref = collections.Counter(); combo = collections.Counter()
for p in paths:
    try: fh = open(p, 'rb')
    except OSError: continue
    for line in fh:
        if b'"type":"user"' not in line[:3000]: continue
        if b'"tool_result"' in line: continue
        try: r = json.loads(line)
        except Exception: continue
        if r.get('type') != 'user' or r.get('isMeta') or r.get('isSidechain'): continue
        t = ep(r.get('timestamp', '')) or 0
        if t < S or t > E: continue
        o = r.get('origin') or {}
        k = o.get('kind', '-') if isinstance(o, dict) else str(o)
        c_or[k] += 1
        c_ps[str(r.get('promptSource'))] += 1
        c_q[str(r.get('queueOrigin'))] += 1
        c_to[json.dumps(r.get('turnOrigin'))[:80]] += 1
        combo[(k, str(r.get('promptSource')), str(r.get('queueOrigin')))] += 1
        if k == 'human':
            c = (r.get('message') or {}).get('content')
            if isinstance(c, list):
                c = ' '.join(b.get('text', '') for b in c if isinstance(b, dict))
            pref[(c or '')[:40].replace('\n', ' ')] += 1
print('origin.kind', c_or.most_common())
print('promptSource', c_ps.most_common())
print('queueOrigin', c_q.most_common())
print('turnOrigin', c_to.most_common(15))
print('combo', combo.most_common(20))
print('human prefixes:')
for k, v in pref.most_common(70): print(v, repr(k))
