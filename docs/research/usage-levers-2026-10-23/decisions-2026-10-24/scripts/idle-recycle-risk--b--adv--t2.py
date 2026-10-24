# T2: what are the task-notification gap-enders? (watchers/monitors that die with the predecessor?)
import json, collections, re
R = [json.loads(l) for l in open('/tmp/idle-recycle-risk/b/ctx.jsonl')]
c = collections.Counter(); ex = collections.defaultdict(list)
for j, r in enumerate(R):
    ks = [o for o in r['openers'] if o['kind'] == 'notice']
    if not ks or any(o['kind'] in ('operator','operator-noorigin') for o in r['openers']): continue
    t = ks[-1]['text']
    m = re.search(r'<summary>(.*?)</summary>', t, re.S)
    s = (m.group(1) if m else t)[:200]
    st = re.search(r'<status>(.*?)</status>', t)
    kind = re.search(r'<task-type>(.*?)</task-type>|<type>(.*?)</type>', t)
    tag = 'goal' if 'Goal check-in' in t[:300] else 'monitor' if re.search(r'monitor', t[:400], re.I) else 'await-ping' if 'await' in t.lower()[:600] else (st.group(1) if st else 'nostatus')
    c[tag] += 1; ex[tag].append((j, s.replace('\n',' ')[:150]))
print(dict(c))
for k, v in ex.items():
    print('==', k)
    for x in v[:8]: print('  ', x)
