#!/usr/bin/env python3
"""W0 item 3b: validate the background-shell detector against every live claude, read-only (ps only
plus <cfg>/sessions/*.json for pid->sid). Detector under test: a claude process with a child
`/bin/(zsh|bash) -c ... shell-snapshots/snapshot-...` (the Bash tool's shell) while the session is at
rest. Contrast: the NAIVE rule "any shell child" also counts hook children (mailbox-wake-arm.sh)."""
import glob, json, os, re, subprocess, time
H = os.path.expanduser('~')
ps = subprocess.run(['/bin/ps', '-axo', 'pid=,ppid=,stat=,ucomm=,command='], capture_output=True, text=True).stdout
rows = []
for l in ps.splitlines():
    p = l.split(None, 4)
    if len(p) < 5: continue
    rows.append(dict(pid=int(p[0]), ppid=int(p[1]), stat=p[2], comm=p[3], cmd=p[4]))
kids = {}
for r in rows: kids.setdefault(r['ppid'], []).append(r)
pid2sid = {}
for f in glob.glob(H + '/.claude*/sessions/*.json'):
    try:
        d = json.load(open(f)); pid2sid[int(d.get('pid'))] = (d.get('sessionId') or '')[:8] + ('/bg' if d.get('kind') == 'bg' else '')
    except Exception: pass
SNAP = re.compile(r'^/bin/(zsh|bash) -c .*shell-snapshots/snapshot-')
SHELL = re.compile(r'^(/bin/)?(zsh|bash|sh)\b')
def transcript_idle_s(sid8):
    fs = glob.glob(H + '/.claude*/projects/*/' + sid8 + '*.jsonl') if sid8 else []
    return int(time.time() - max(os.path.getmtime(f) for f in fs)) if fs else None
claudes = [r for r in rows if r['comm'] in ('claude', 'claude.exe') and 'Z' not in r['stat']]
print('ts', time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'live_claude', len(claudes))
print('pid sid8 idle_s snap_children(detector) naive_shell_children hook_children detector naive')
agree = hit = naive_fp = 0
for c in sorted(claudes, key=lambda r: r['pid']):
    ch = kids.get(c['pid'], [])
    snap = [k for k in ch if SNAP.search(k['cmd'])]
    naive = [k for k in ch if SHELL.search(k['cmd'])]
    hooks = [k for k in ch if '/hooks/' in k['cmd']]
    sid = pid2sid.get(c['pid'], '?')
    idle = transcript_idle_s(sid.split('/')[0] if sid != '?' else '')
    det = 'HIT' if snap else 'miss'; nv = 'HIT' if naive else 'miss'
    hit += bool(snap); naive_fp += bool(naive) and not snap
    grand = ','.join(sorted({g['comm'] for k in snap for g in kids.get(k['pid'], [])})) or '-'
    print(c['pid'], sid, idle, f"{len(snap)}[{grand}]", len(naive), len(hooks), det, nv)
print(f'summary: detector HIT {hit}/{len(claudes)}; naive-rule false positives (shell child that is only a hook) {naive_fp}/{len(claudes)}')
