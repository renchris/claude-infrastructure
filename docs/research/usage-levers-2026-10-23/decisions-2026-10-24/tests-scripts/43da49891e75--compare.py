# Compare second (blind-ish) labels with the first labels on the 60-sample; recount bands with the 2nd labels.
# usage: python3 -I -B compare.py
import json, collections
B = '/tmp/idle-recycle-risk/b/'
K = '/tmp/conv-tests/43da49891e75/'
R = [json.loads(l) for l in open(B + 'ctx.jsonl')]
for j, r in enumerate(R): r['pid'] = j; r['ctx_eff'] = int(float(r['ctx_eff']))
pids = json.load(open(B + 'sample_pids.json')); L = json.load(open(B + 'labels.json')); HO = json.load(open(B + 'holdout_labels.json'))
S2 = json.load(open(K + 'labels_second.json'))['labels']
def kappa(a, b):
    n = len(a); po = sum(x == y for x, y in zip(a, b)) / n
    pa = sum(a) / n; pb = sum(b) / n; pe = pa * pb + (1 - pa) * (1 - pb)
    return po, pe, (po - pe) / (1 - pe) if pe < 1 else float('nan')
h1, h2, a1, a2 = [], [], [], []
dis = []
for n, pid in enumerate(pids, 1):
    s = S2[str(n)]; assert s[0] == pid
    h1.append(int(L[str(n)].startswith('H'))); a1.append(int('A' in L[str(n)]))
    h2.append(s[1]); a2.append(s[2])
    if h1[-1] != h2[-1] or a1[-1] != a2[-1]:
        dis.append((n, pid, L[str(n)], s[1], s[2], R[pid]['ctx_eff'] // 1000, R[pid]['first_op']['text'][:60]))
for name, x, y in (('ctx-dependent (H)', h1, h2), ('wrong-action (A)', a1, a2)):
    po, pe, k = kappa(x, y)
    print('%-18s first=%d second=%d agree=%d/60 (%.1f%%) p_e=%.3f kappa=%.3f' % (name, sum(x), sum(y), round(po * 60), 100 * po, pe, k))
print('disagreements:', dis)
# 2x2 tables
for name, x, y in (('H', h1, h2), ('A', a1, a2)):
    t = collections.Counter(zip(x, y)); print(name, '2x2 (first,second):', dict(t))
# band recount over all 193 eligible returns: second labels on the 60, first labels on the 133 holdout
def band2(c): return '150-200k' if c < 200_000 else '>=200k'
elig = [r for r in R if r['first_op'] and r['first_op']['ts'] >= float(r['t_prev']) + 900]
first, second = {}, {}
for n, pid in enumerate(pids, 1):
    first[pid] = (int(L[str(n)].startswith('H')), int('A' in L[str(n)]))
    second[pid] = (S2[str(n)][1], S2[str(n)][2])
for r in elig:
    if r['pid'] in first: continue
    h = HO['H'].get(str(r['pid']))
    first[r['pid']] = second[r['pid']] = ((1, h['A']) if h else (0, 0))
for nm, lab in (('first labels', first), ('second labels on sample', second)):
    c = collections.defaultdict(lambda: [0, 0, 0])
    for r in elig:
        b = band2(r['ctx_eff']); c[b][0] += 1; c[b][1] += lab[r['pid']][0]; c[b][2] += lab[r['pid']][1]
    print(nm, {b: dict(returns=v[0], H=v[1], A=v[2]) for b, v in sorted(c.items())})
# reviewer adjustment: 136,167,187 raised after the recycle point (successor raises them itself)
late = {136, 167, 187}
c = collections.defaultdict(lambda: [0, 0])
for r in elig:
    h, a = second[r['pid']]
    if r['pid'] in late: h, a = 0, 0
    b = band2(r['ctx_eff']); c[b][0] += h; c[b][1] += a
print('second + reviewer late-question exclusion', {b: dict(H=v[0], A=v[1]) for b, v in sorted(c.items())})
# where the 10 first-label A cases sit
A1 = sorted(p for p, v in first.items() if v[1])
print('first-label A pids with ctx_k:', [(p, R[p]['ctx_eff'] // 1000, R[p]['n_machine_before_op']) for p in A1])
