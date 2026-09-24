#!/usr/bin/env python3
"""Enumerate every hook in each config dir's settings.json (+ project settings for
claude-infrastructure), resolve its script into the repo, and diff the sets across dirs.
Output: JSON on stdout (list of hooks + per-dir diffs)."""
import json, os, re, sys
H = os.path.expanduser('~')
REPO = f'{H}/Development/claude-infrastructure'
DIRS = ['.claude', '.claude-next', '.claude-secondary', '.claude-tertiary', '.claude-quaternary']
def hooks_of(path):
    try: s = json.load(open(path))
    except Exception as e: return None
    out = []
    for ev, groups in (s.get('hooks') or {}).items():
        for g in groups:
            m = g.get('matcher', '')
            for hk in g.get('hooks', []):
                c = hk.get('command') or hk.get('prompt') or hk.get('url') or ''
                out.append(dict(event=ev, matcher=m, type=hk.get('type'), timeout=hk.get('timeout'),
                                is_async=hk.get('async'), command=c))
    return out
def script_of(cmd):
    m = re.search(r'(?:~|\$HOME|/Users/chrisren)/\.claude/hooks/([\w.\-]+)', cmd)
    if not m: return None, None, None
    name = m.group(1)
    live = f'{H}/.claude/hooks/{name}'
    real = os.path.realpath(live) if os.path.exists(live) else None
    repo = f'{REPO}/hooks/{name}'
    size = os.path.getsize(repo) if os.path.exists(repo) else None
    return name, real, size
res = {'per_dir': {}, 'hooks': []}
base = hooks_of(f'{H}/.claude/settings.json')
keyset = lambda L: {(h['event'], h['matcher'], h['command']) for h in L}
for d in DIRS:
    L = hooks_of(f'{H}/{d}/settings.json')
    if L is None: res['per_dir'][d] = 'unreadable'; continue
    res['per_dir'][d] = dict(n=len(L), only_here=sorted(map(list, keyset(L) - keyset(base))),
                             missing_here=sorted(map(list, keyset(base) - keyset(L))))
for p in [f'{REPO}/.claude/settings.json', f'{REPO}/.claude/settings.local.json']:
    L = hooks_of(p)
    res['per_dir'][p] = 'absent' if L is None else dict(n=len(L), hooks=[[h['event'], h['matcher'], h['command']] for h in L])
for h in base:
    name, real, size = script_of(h['command'])
    h.update(script=name, resolves_to=real, repo_bytes=size,
             in_repo=bool(real and real.startswith(REPO)))
    res['hooks'].append(h)
from collections import Counter
res['count_by_event'] = Counter(h['event'] for h in base)
res['n_hooks'] = len(base)
res['n_distinct_scripts'] = len({h['script'] for h in base if h['script']})
res['not_in_repo'] = [h['command'] for h in base if not h['in_repo']]
json.dump(res, sys.stdout, indent=1, default=str)
