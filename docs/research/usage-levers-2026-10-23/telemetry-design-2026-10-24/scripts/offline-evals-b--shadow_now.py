# Bounded census of the four live shadow logs (read-only). usage: python3 -I shadow_now.py
import json, os, collections
H = os.path.expanduser('~/.claude/logs/')
def rows(n):
    p = H + n
    if not os.path.exists(p): return []
    out = []
    for l in open(p, errors='replace'):
        try: out.append(json.loads(l))
        except Exception: out.append({'_bad': 1})
    return out
s = rows('subagent-long-bash.jsonl')
v2 = [r for r in s if r.get('v') == 2]
print('subagent rows', len(s), 'v2', len(v2), 'first', s[0].get('ts') if s else None, 'last', s[-1].get('ts') if s else None)
print(' v2 why x class x exempt', collections.Counter((r.get('why'), r.get('would_deny_class'), r.get('exempt')) for r in v2).most_common())
print(' v2 acct', collections.Counter(r.get('acct') for r in v2))
pl = [r for r in v2 if r.get('why') == 'poll-loop']
print(' poll-loop inner_timeout_s', collections.Counter(r.get('inner_timeout_s') for r in pl).most_common(8))
print(' poll-loop timeout_ms', collections.Counter(r.get('timeout_ms') for r in pl).most_common(8))
w = rows('workflow-lean-shadow.jsonl')
print('workflow rows', len(w), 'would_deny', sum(1 for r in w if r.get('would_deny')), 'resume', sum(1 for r in w if r.get('resume_from_run_id')),
      'slots', sum(len(r.get('slots') or []) for r in w), 'slot verdicts', collections.Counter(sl.get('verdict') for r in w for sl in (r.get('slots') or [])))
print(' sessions', len({r.get('session_id') for r in w}), 'repeat>0', sum(1 for r in w if (r.get('repeat_in_session') or 0) > 0))
i = rows('idle-recycle-shadow.jsonl')
ok = [r for r in i if r.get('v') == 'ok']
print('irs rows', len(i), 'ok', len(ok), 'with k2', sum(1 for r in ok if 'would_advise_k2' in r),
      'wa_k2', sum(1 for r in ok if r.get('would_advise_k2')), 'guarded_k2', sum(1 for r in ok if r.get('guarded_k2')),
      'sessions guarded_k2', len({r.get('sid') for r in ok if r.get('guarded_k2')}))
print(' pending_question', collections.Counter(r.get('pq_why') for r in ok if r.get('pending_question')), 'busy_tool', sum(1 for r in ok if r.get('busy_tool')))
k = rows('idle-keepalive.jsonl')
g = [r for r in k if r.get('kind') == 'gap']; wk = [r for r in k if r.get('kind') == 'wake']
print('keepalive gap', len(g), 'wake', len(wk), 'gap outcomes', collections.Counter(r.get('outcome') for r in g))
print(' wake v2 busy', collections.Counter((r.get('busy'), r.get('watcher_fires_before_ttl')) for r in wk if r.get('v') == 2))
print(' gaps>=3300', sum(1 for r in g if (r.get('dur') or 0) >= 3300), 'gaps>=3600 with obs_cw', sum(1 for r in g if (r.get('dur') or 0) >= 3600 and r.get('obs_cw')))
