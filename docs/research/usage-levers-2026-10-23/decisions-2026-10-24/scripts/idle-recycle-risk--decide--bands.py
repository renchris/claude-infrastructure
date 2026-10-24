# Count (b) H/A labels and (c-review) context-dependent operator returns by context band at the recycle point.
import json, csv, collections
B = '/tmp/idle-recycle-risk/b/'
R = [json.loads(l) for l in open(B + 'ctx.jsonl')]
for j, r in enumerate(R): r['pid'] = j; r['ctx_eff'] = int(float(r['ctx_eff']))
def band(c): return '150-200k' if c < 200_000 else '200-250k' if c < 250_000 else '250-350k' if c < 350_000 else '>=350k'
pids = json.load(open(B + 'sample_pids.json')); L = json.load(open(B + 'labels.json')); HO = json.load(open(B + 'holdout_labels.json'))
elig = [r for r in R if r['first_op'] and r['first_op']['ts'] >= float(r['t_prev']) + 900]
lab = {}
for n, pid in enumerate(pids, 1): lab[pid] = (L[str(n)][0], int('A' in L[str(n)]))
for r in elig:
    if r['pid'] in lab: continue
    h = HO['H'].get(str(r['pid']))
    lab[r['pid']] = ('H', h['A']) if h else ('S/I', 0)
pts = collections.Counter(band(r['ctx_eff']) for r in R)
ret = collections.Counter(band(r['ctx_eff']) for r in elig)
H = collections.Counter(band(r['ctx_eff']) for r in elig if lab[r['pid']][0] == 'H')
A = collections.Counter(band(r['ctx_eff']) for r in elig if lab[r['pid']][0] == 'H' and lab[r['pid']][1])
print('b: mid points / returns / H / A by band (n=%d points, %d returns)' % (len(R), len(elig)))
for b in ('150-200k', '200-250k', '250-350k', '>=350k'): print(' ', b, pts[b], ret[b], H[b], A[b])
# c review labels: i = row index among mid rows of c/points_150k_15m.tsv
rows = [x for x in csv.DictReader(open('/tmp/idle-recycle-risk/c/points_150k_15m.tsv'), delimiter='\t', quoting=csv.QUOTE_NONE) ]
lb = list(csv.DictReader(open('/tmp/idle-recycle-risk/c/adv/op_returns_labels.tsv'), delimiter='\t', quoting=csv.QUOTE_NONE))
cd = collections.Counter(); op = collections.Counter(); bad = 0
for x in lb:
    i = int(x['i']); p = rows[i]
    if p['sid'][:8] != x['sid']: bad += 1; continue
    if x['label'].startswith('op-'): op[band(int(p['ctx']))] += 1
    if x['label'] == 'op-context-dependent': cd[band(int(p['ctx']))] += 1
print('c-review: operator-ended gaps / context-dependent by band (sid mismatches %d)' % bad)
for b in ('150-200k', '200-250k', '250-350k', '>=350k'): print(' ', b, op[b], cd[b])
