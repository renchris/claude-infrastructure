# W4 busy() misses: a job (any tool_use that later got a <task-notification>) launched before idle minute 15
# whose notice lands after it, or never lands, and that scan.py's .jobs did not carry as a non-watcher job.
import json, re, collections
B = '/tmp/idle-recycle-risk/b/'
P = [json.loads(l) for l in open(B + 'points.jsonl')]
from datetime import datetime
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
jobs = collections.defaultdict(dict)
for a in ('next','next2','next3','next4'):
    for line in open('/tmp/usage-audit/w4/rows_%s.tsv.jobs' % a):
        fi, sid, tu, nm, w, js, je = line.rstrip('\n').split('\t')
        jobs[sid][tu] = int(w)
TU = re.compile(rb'<tool-use-id>([^<]+)</tool-use-id>')
WATCH = re.compile(r'cc-await-ping|wait|watch|await|ping|inbox|mail|wake|poll', re.I)
by = collections.defaultdict(list)
for j, p in enumerate(P): p['pid'] = j; by[p['sid']].append(p)
miss = []
for sid, ps in by.items():
    launch, notice = {}, {}
    for path in ps[0]['files']:
        try: fh = open(path, 'rb')
        except OSError: continue
        for line in fh:
            h = line[:3000]
            if b'"type":"assistant"' in h and b'"tool_use"' in line:
                try: x = json.loads(line)
                except Exception: continue
                if x.get('isSidechain'): continue
                for b in (x.get('message') or {}).get('content') or []:
                    if isinstance(b, dict) and b.get('type') == 'tool_use' and b.get('name') in ('Bash', 'Agent', 'Task', 'Workflow'):
                        inp = b.get('input') or {}
                        launch.setdefault(b['id'], (ep(x.get('timestamp', '')) or 0, b['name'], str(inp.get('description') or inp.get('command') or '')[:80], str(inp.get('command') or '')))
            if b'<task-notification>' in line:
                i = line.find(b'"timestamp":"')
                ts = ep(line[i + 13:i + 40].split(b'"')[0].decode()) if i >= 0 else None
                for tu in TU.findall(line):
                    tu = tu.decode()
                    if ts and (tu not in notice or ts < notice[tu]): notice[tu] = ts
    for p in ps:
        t15 = p['t_prev'] + 900
        hits = []
        for tu, (ls, nm, d, cmd) in launch.items():
            if tu not in notice: continue          # never backgrounded (foreground call returned inline)
            if not (ls < t15 < notice[tu]): continue
            if WATCH.search(d) or 'cc-await-ping' in cmd or nm == 'Monitor': continue
            if tu in jobs.get(sid, {}) and jobs[sid][tu] == 0: continue  # sim already knew it (should have been busy)
            hits.append((nm, d, round((notice[tu] - t15) / 60)))
        if hits: miss.append((p['pid'], hits))
print('points where a non-watcher job ran across idle minute 15 but busy() did not know it: %d of %d' % (len(miss), len(P)))
for m in miss: print(' ', m[0], m[1][:2])
json.dump([m[0] for m in miss], open(B + 'adv/busymiss.json', 'w'))
