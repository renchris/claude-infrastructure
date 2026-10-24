# Recount the census/timing/classifier numbers from the worker's labels + my own dedupe of shared prompts.
import json, sys, collections
sys.path.insert(0, '/tmp/idle-recycle-risk/b')
from lib import v0, v1
B = '/tmp/idle-recycle-risk/b/'
R = {json.loads(l)['pid']: json.loads(l) for l in open(B + 'adv/returns.jsonl')}
pids = json.load(open(B + 'sample_pids.json')); L = json.load(open(B + 'labels.json')); HO = json.load(open(B + 'holdout_labels.json'))
H = set(int(p) for p in HO['H']) | set(pids[n - 1] for n in range(1, 61) if L[str(n)].startswith('H'))
A = set(int(p) for p, v in HO['H'].items() if v['A']) | set(pids[n - 1] for n in range(1, 61) if 'A' in L[str(n)])
print('H', len(H), sorted(H)); print('A', len(A), sorted(A))
print('returns rows', len(R), 'distinct prompts', len(set((r['sid'], r['op'][:200], r['gap_min'] - 0) for r in R.values())))
# dedupe: same sid and same op text -> keep the latest point (the successor that would actually receive it)
seen = {}
for p, r in sorted(R.items()):
    k = (r['sid'], r['op'])
    if k not in seen or r['gap_min'] < R[seen[k]]['gap_min']: seen[k] = p
D = set(seen.values())
print('deduped returns', len(D), 'H in deduped', len(H & D), 'H share %.1f%%' % (100 * len(H & D) / len(D)))
f = lambda pool, cond: sum(1 for p in pool if cond(R[p]))
print('15-60m: all %d/%d, H %d/%d, A %d/%d' % (f(R, lambda r: r['gap_min'] < 60), len(R), f(H, lambda r: r['gap_min'] < 60), len(H), f(A, lambda r: r['gap_min'] < 60), len(A)))
print('not cp: all %d, H %d, A %d' % (f(R, lambda r: not r['cp']), f(H, lambda r: not r['cp']), f(A, lambda r: not r['cp'])))
fl = [p for p in R if v0(R[p]['op'])]
print('v0 flags %d; tp %d; precision %.2f recall %.2f' % (len(fl), len(set(fl) & H), len(set(fl) & H) / len(fl), len(set(fl) & H) / len(H)))
fl1 = [p for p in R if v1(R[p]['op'])]
print('v1 flags %d; tp %d' % (len(fl1), len(set(fl1) & H)))
# where is each H's referent: post-gap machine turns present?
for p in sorted(H): r = R[p]; print('  H pid %d gap %dm nmach %d cp %d A %d | %s' % (p, r['gap_min'], r['nmach'], r['cp'], p in A, ' '.join(r['op'].split())[:60]))
