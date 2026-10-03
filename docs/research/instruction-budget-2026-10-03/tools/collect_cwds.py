#!/usr/bin/env python3
"""Collect distinct session cwds from ~/.claude*/projects dirs modified in last N days + live claude procs.
Output: /tmp/ibudget/cwds.json  {cwd: {"sessions": n, "accounts": [...], "last": mtime}}"""
import os, json, glob, time, sys, subprocess
DAYS = float(sys.argv[1]) if len(sys.argv) > 1 else 14
H = os.path.expanduser('~')
cut = time.time() - DAYS * 86400
out = {}
def add(cwd, acct, mt, n=1):
    e = out.setdefault(cwd, {"sessions": 0, "accounts": set(), "last": 0})
    e["sessions"] += n; e["accounts"].add(acct); e["last"] = max(e["last"], mt)
seen_pd = set()
for pd in sorted(glob.glob(H + '/.claude*/projects')):
    rp = os.path.realpath(pd)
    if rp in seen_pd: continue  # ~/.claude-next/projects -> ~/.claude/projects
    seen_pd.add(rp)
    acct = pd.split('/')[-2]
    for d in os.scandir(pd):
        if not d.is_dir(): continue
        try: mt = d.stat().st_mtime
        except OSError: continue
        if mt < cut: continue
        cwd = None; nsess = 0
        for f in os.scandir(d.path):
            if not f.name.endswith('.jsonl'): continue
            try:
                if f.stat().st_mtime < cut: continue
            except OSError: continue
            nsess += 1
            if cwd: continue
            try:
                with open(f.path, errors='ignore') as fh:
                    for i, line in enumerate(fh):
                        if i > 60: break
                        if '"cwd"' in line:
                            try: cwd = json.loads(line).get('cwd')
                            except Exception: pass
                            if cwd: break
            except OSError: pass
        if not cwd:
            cwd = 'UNDECODED:' + d.name
        if nsess: add(cwd, acct, mt, nsess)
# live processes
try:
    r = subprocess.run(['lsof', '-a', '-d', 'cwd', '-c', 'claude', '-Fn'], capture_output=True, text=True, timeout=60)
    for l in r.stdout.splitlines():
        if l.startswith('n/'): add(l[1:], 'LIVE', time.time(), 0)
except Exception as ex:
    print('lsof failed', ex, file=sys.stderr)
for v in out.values(): v["accounts"] = sorted(v["accounts"])
json.dump(out, open('/tmp/ibudget/cwds.json', 'w'), indent=1, sort_keys=True)
print(len(out), 'distinct cwds;', sum(v['sessions'] for v in out.values()), 'session files;',
      sum(1 for v in out.values() if 'LIVE' in v['accounts']), 'live cwds')
