# T3: gap-ending "completed" notices of real (non-watcher) jobs: was the job in scan.py's .jobs, flagged watcher?
import json, re, collections
R = [json.loads(l) for l in open('/tmp/idle-recycle-risk/b/ctx.jsonl')]
jobs = collections.defaultdict(list)
for a in ('next','next2','next3','next4'):
    for line in open('/tmp/usage-audit/w4/rows_%s.tsv.jobs' % a):
        fi, sid, tu, nm, w, js, je = line.rstrip('\n').split('\t')
        jobs[sid].append((tu, nm, int(w), float(js) if js else None, float(je) if je else None))
WATCH = re.compile(r'wait|watch|await|ping|inbox|mail|wake|monitor|poll', re.I)
c = collections.Counter(); rows = []
for j, r in enumerate(R):
    if any(o['kind'] in ('operator','operator-noorigin') for o in r['openers']): continue
    ks = [o for o in r['openers'] if o['kind'] == 'notice']
    if not ks: continue
    t = ks[-1]['text']
    m = re.search(r'<summary>(.*?)</summary>', t, re.S); s = m.group(1) if m else ''
    tid = re.search(r'<tool-use-id>([^<]+)</tool-use-id>', t)
    if not s.startswith(('Background command', 'Background agent')): continue
    watcherish = bool(WATCH.search(s))
    J = {x[0]: x for x in jobs.get(r['sid'], [])}
    hit = J.get(tid.group(1)) if tid else None
    t15 = r['t_prev'] + 900
    st = 'no-tool-use-id' if not tid else 'not-in-jobs' if not hit else ('flagged-watcher' if hit[2] else ('running@15' if hit[3] and hit[3] <= t15 < (hit[4] or 9e18) else 'not-running@15'))
    c[(watcherish, st)] += 1
    if not watcherish: rows.append((j, st, s[:90]))
print(dict(c))
for x in rows: print(' ', x)
