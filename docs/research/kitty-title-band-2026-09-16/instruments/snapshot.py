#!/usr/bin/env python3
"""Snapshot every live kitty pane -> (account, session-id, worktree, branch, layout position).
Read-only. Joins: kitty @ ls  x  ~/.claude*/cc-registry/<window-id>.json  x  reso-resume-one argv
                  x  lr-select.py --scan (for the branch column / fallback sid).
"""
import glob, json, os, subprocess, sys

SOCK = sys.argv[1] if len(sys.argv) > 1 else 'unix:/tmp/kitty-597'

env = dict(os.environ)
for k in ('KITTY_LISTEN_ON', 'KITTY_PID', 'KITTY_WINDOW_ID'):
    env.pop(k, None)
ls = json.loads(subprocess.run(['kitty', '@', '--to', SOCK, 'ls'],
                               capture_output=True, text=True, env=env).stdout)

# registry rows across every config dir (they symlink, but read them all)
reg = {}
for d in glob.glob(os.path.expanduser('~/.claude*/cc-registry/*.json')):
    try:
        r = json.load(open(d))
    except Exception:
        continue
    if r.get('paneUUID'):
        reg.setdefault(str(r['paneUUID']), r)

# branch lookup by realpath(cwd) from lr-select's TSV, if present
branch = {}
lrsid = {}
_here = os.path.dirname(os.path.abspath(__file__))
for _cand in (os.environ.get('KTB_LRSEL', ''),
              os.path.join(_here, 'lr-select-scan-2026-09-16.tsv'),
              '/private/tmp/ktb-live-deploy/lrsel.tsv'):
  if not _cand or not os.path.exists(_cand):
    continue
  try:
    for line in open(_cand):
      f = line.rstrip('\n').split('\t')
      if len(f) >= 4:
        branch[os.path.realpath(f[2])] = f[3]
        lrsid[os.path.realpath(f[2])] = (f[0], f[1])
    break
  except OSError:
    pass

# registry stores the CONFIG-DIR basename; reso-resume-one wants the LAUNCHER ALIAS.
# Derived from accounts.json (accounts[].name <-> accounts[].config_dir), never hardcoded.
ALIAS = {}
try:
    _a = json.load(open(os.path.expanduser('~/.claude/accounts.json')))
    for _r in _a.get('accounts', []):
        _cd = os.path.basename(os.path.expanduser(_r.get('config_dir', ''))).lstrip('.')
        if _cd and _r.get('name'):
            ALIAS[_cd] = _r['name']
except Exception:
    pass

rows = []
for osw in ls:
    for tab in osw['tabs']:
        for i, w in enumerate(tab['windows']):
            cmd = w.get('cmdline') or []
            acct = sid = wt = br = None
            src = ''
            if len(cmd) >= 5 and cmd[1].endswith('reso-resume-one'):
                acct, wt, sid = cmd[2], cmd[3], cmd[4]
                br = cmd[5] if len(cmd) > 5 else None
                src = 'argv(reso-resume-one)'
            r = reg.get(str(w['id']))
            if sid is None and r:
                acct, sid, wt = r.get('account'), r.get('session_id'), r.get('cwd')
                src = 'cc-registry'
            cwd = os.path.realpath(w.get('cwd') or (wt or ''))
            if sid is None and cwd in lrsid:
                acct, sid = lrsid[cwd]
                src = 'lr-select(by cwd)'
            if acct in ALIAS:
                acct = ALIAS[acct]
            if br is None:
                br = branch.get(cwd)
            rows.append(dict(oswin=osw['id'], platform=osw.get('platform_window_id'),
                             tab=tab['id'], layout=tab['layout'], pos=i,
                             win=w['id'], pid=w['pid'], cols=w['columns'], lines=w['lines'],
                             cwd=w.get('cwd'), title=w.get('title'),
                             account=acct, session_id=sid, worktree=wt or w.get('cwd'),
                             branch=br, source=src,
                             neighbors=w.get('neighbors')))
mode = sys.argv[2] if len(sys.argv) > 2 else 'table'
if mode == 'tsv':
    for r in rows:
        if r['session_id'] and r['account']:
            print('\t'.join([r['account'], r['session_id'], r['worktree'], r['branch'] or 'HEAD',
                             f"oswin{r['oswin']}/tab{r['tab']}/pos{r['pos']}"]))
else:
    print(json.dumps(rows, indent=2))
