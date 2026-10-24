# Print key-sets and short text of non-tool_result user records + other record types in one transcript.
import json, sys, collections
p = sys.argv[1]
kinds = collections.Counter()
keysets = collections.Counter()
n = 0
for line in open(p, 'rb'):
    try:
        r = json.loads(line)
    except Exception:
        continue
    t = r.get('type')
    kinds[t] += 1
    if t == 'user':
        c = (r.get('message') or {}).get('content')
        if isinstance(c, list) and any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in c):
            continue
        keysets[tuple(sorted(r.keys()))] += 1
        if n < int(sys.argv[2]):
            txt = c if isinstance(c, str) else ' | '.join((b.get('text') or b.get('type', '')) for b in c if isinstance(b, dict))
            extra = {k: r.get(k) for k in ('isMeta', 'userType', 'origin', 'promptId', 'permissionMode', 'isCompactSummary', 'isVisibleInTranscriptOnly') if k in r}
            print(r.get('timestamp'), extra, repr(txt[:160]))
            n += 1
print(kinds)
for k, v in keysets.most_common(10):
    print(v, k)
