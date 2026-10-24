# D1 case pool census over the prior research's recycle points (read-only). usage: python3 -I d1_pool.py
import json, collections, datetime
B = '/tmp/idle-recycle-risk/b/'
R = [json.loads(l) for l in open(B + 'ctx.jsonl')]
ts = [r['t_prev'] for r in R]
f = lambda t: datetime.datetime.utcfromtimestamp(t).strftime('%Y-%m-%d')
print('points', len(R), 'from', f(min(ts)), 'to', f(max(ts)))
print('acct', collections.Counter(r['acct'] for r in R))
fo = [r for r in R if r.get('first_op')]
print('with first_op', len(fo), 'ctx>=200k', sum(1 for r in R if r['ctx_eff'] >= 200000), 'first_op & ctx>=200k', sum(1 for r in fo if r['ctx_eff'] >= 200000))
print('first_op kinds', collections.Counter((r.get('first_op') or {}).get('kind') for r in R).most_common(6))
print('sessions', len({r['sid'] for r in R}))
L = json.load(open(B + 'labels.json')); H = json.load(open(B + 'holdout_labels.json'))
lab = collections.Counter(v[:1] for k, v in L.items() if k != '_key')
print('sample labels first char', lab, 'A in label', sum(1 for k, v in L.items() if k != '_key' and 'A' in v))
print('holdout H', len(H['H']), 'holdout A', sum(v['A'] for v in H['H'].values()))
