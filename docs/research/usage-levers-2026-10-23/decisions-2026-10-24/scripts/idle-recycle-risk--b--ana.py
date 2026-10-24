# Final tables for measurement (b). Inputs: ctx.jsonl (extract.py), labels.json + sample_pids.json (60 hand labels),
# holdout_labels.json (hand review of the other 133), guard_flags.json + guard_sim.json (guard.py).
# usage: python3 -I ana.py > ana.out ; writes ana.json
import json, sys, math, collections, statistics, importlib.util, os
sys.path.insert(0, '/tmp/idle-recycle-risk/b')
from lib import v0, v1, OPERATOR_STEP, MACHINE_TYPED
from datetime import datetime
B = '/tmp/idle-recycle-risk/b/'
R = [json.loads(l) for l in open(B + 'ctx.jsonl')]
for j, r in enumerate(R): r['pid'] = j
DAYS = 14.0
WK = 7.0 / DAYS
out = {}
def wilson(k, n, z=1.96):
    p = k / n; d = 1 + z * z / n; c = p + z * z / (2 * n); h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return round(100 * (c - h) / d, 1), round(100 * (c + h) / d, 1)
# ---- 1. what ended the idle gap at each recycle point
def opener_class(r):
    ks = [o for o in r['openers'] if o['kind'] != 'meta']
    if not all(os.path.exists(f) for f in json.loads(open(B + 'points.jsonl').readlines()[r['pid']])['files']):
        return 'transcript file gone'
    if any(o['kind'] in ('operator', 'operator-noorigin') and not MACHINE_TYPED.match(o['text'].lstrip()) for o in ks):
        return 'operator'
    if not ks:
        metas = [o for o in r['openers'] if o['kind'] == 'meta']
        return 'machine: peer-wake (meta) / no user record'
    o = ks[-1]; t = o['text']
    if o['kind'] == 'notice':
        if 'Goal check-in' in t[:200]: return 'machine: goal check-in'
        if 'peer mail' in t[:200]: return 'machine: peer-mail watcher'
        return 'machine: background-job / watcher notice'
    if o['kind'] == 'peer': return 'machine: peer / teammate message'
    if o['kind'] == 'injected' or MACHINE_TYPED.match(t.lstrip()): return 'machine: injected rail prompt (restore / limit-recover / crash)'
    return 'machine: other (' + o['kind'] + ')'
oc = collections.Counter(opener_class(r) for r in R)
out['opener_310'] = dict(oc.most_common())
# ---- 2. first operator prompt after the idle start
pre = [r for r in R if r['first_op'] and r['first_op']['ts'] < r['t_prev'] + 900]
elig = [r for r in R if r['first_op'] and r['first_op']['ts'] >= r['t_prev'] + 900]
none = [r for r in R if not r['first_op']]
out['returns'] = dict(points=len(R), operator_return_after_min15=len(elig), operator_activity_before_min15=len(pre),
                      no_operator_prompt_before_session_end=len(none),
                      return_is_the_gap_ender=sum(1 for r in elig if r['first_op']['ts'] <= r['t_req'] + 0.5),
                      return_after_machine_turns=sum(1 for r in elig if r['first_op']['ts'] > r['t_req'] + 0.5))
# ---- 3. hand labels
pids = json.load(open(B + 'sample_pids.json')); L = json.load(open(B + 'labels.json')); HO = json.load(open(B + 'holdout_labels.json'))
lab = {}
for n, pid in enumerate(pids, 1):
    lab[pid] = dict(cls=L[str(n)][0], A=int('A' in L[str(n)]), ref=HO['sample_H_ref'].get(str(pid)))
for r in elig:
    if r['pid'] in lab: continue
    h = HO['H'].get(str(r['pid']))
    t = r['first_op']['text'].strip()
    lab[r['pid']] = dict(cls='H', A=h['A'], ref=h['ref']) if h else dict(cls='S/I', A=0, ref=None)
sc = collections.Counter(lab[p]['cls'] for p in pids)
out['sample60'] = dict(counts=dict(sc), H_pct=round(100 * sc['H'] / 60, 1), H_wilson95=wilson(sc['H'], 60),
                       HS_pct=round(100 * (sc['H'] + sc['S']) / 60, 1), A=sum(lab[p]['A'] for p in pids),
                       A_wilson95=wilson(sum(lab[p]['A'] for p in pids), 60))
H = [r for r in elig if lab[r['pid']]['cls'] == 'H']
A = [r for r in H if lab[r['pid']]['A']]
out['census193'] = dict(H=len(H), A=len(A), H_pct_of_returns=round(100 * len(H) / len(elig), 1),
                        H_per_week=round(len(H) * WK, 1), A_per_week=round(len(A) * WK, 1),
                        H_pct_of_310_midsession_points=round(100 * len(H) / len(R), 1),
                        H_pct_of_528_all_recycles=round(100 * len(H) / 528, 1),
                        sample_extrapolated_H_per_week=round(sc['H'] / 60 * len(elig) * WK, 1),
                        S_in_sample_extrapolated_per_week=round(sc['S'] / 60 * len(elig) * WK, 1))
# ---- 4. classifiers vs labels
def pr(fn, pool):
    tp = sum(1 for r in pool if fn(r['first_op']['text']) and lab[r['pid']]['cls'] == 'H')
    fp = sum(1 for r in pool if fn(r['first_op']['text']) and lab[r['pid']]['cls'] != 'H')
    fn_ = sum(1 for r in pool if not fn(r['first_op']['text']) and lab[r['pid']]['cls'] == 'H')
    return dict(flagged=tp + fp, tp=tp, fp=fp, fn=fn_, precision=round(tp / max(1, tp + fp), 2), recall=round(tp / max(1, tp + fn_), 2))
samp = [r for r in elig if r['pid'] in set(pids)]; hold = [r for r in elig if r['pid'] not in set(pids)]
out['classifier'] = {'v0_brief_rule_sample': pr(v0, samp), 'v0_brief_rule_all193': pr(v0, elig),
                     'v1_sample(in-fit)': pr(v1, samp), 'v1_holdout133': pr(v1, hold), 'v1_all193': pr(v1, elig)}
# ---- 5. when the operator comes back, against the current practice
def band(c): return '150-250k' if c < 250_000 else '250-350k' if c < 350_000 else '>=350k'
def gb(r):
    g = (r['first_op']['ts'] - r['t_prev']) / 60
    return '15-60m' if g < 60 else '60m-3h' if g < 180 else '3-12h' if g < 720 else '>=12h'
tab = {}
for name, pool in (('all_returns', elig), ('H_returns', H)):
    t = collections.Counter((band(r['ctx_eff']), gb(r)) for r in pool)
    tab[name] = {'%s|%s' % k: v for k, v in sorted(t.items())}
    tab[name + '_15to60_share_pct'] = round(100 * sum(1 for r in pool if gb(r) == '15-60m') / max(1, len(pool)), 1)
    tab[name + '_new_rule_only (current practice would not recycle here)'] = sum(1 for r in pool if not r['cp_also'])
    tab[name + '_new_rule_only_and_15to60'] = sum(1 for r in pool if not r['cp_also'] and gb(r) == '15-60m')
    tab[name + '_250to350k_and_15to60'] = sum(1 for r in pool if 250_000 <= r['ctx_eff'] < 350_000 and gb(r) == '15-60m')
out['timing'] = tab
# ---- 6. guards
F = json.load(open(B + 'guard_flags.json'))
def flag(r, k): return F.get('%s|%.3f' % (r['sid'], round(r['t_prev'], 3)), {}).get(k)
G = {}
for k in ('asks', 'genuine'):
    G['hold_on_' + k] = dict(H_caught=sum(1 for r in H if flag(r, k)), A_caught=sum(1 for r in A if flag(r, k)),
                             points_held_of_310=sum(1 for r in R if flag(r, k)),
                             all_returns_held=sum(1 for r in elig if flag(r, k)))
G['sim'] = json.load(open(B + 'guard_sim.json'))
refc = collections.Counter(lab[r['pid']]['ref'] for r in H)
refA = collections.Counter(lab[r['pid']]['ref'] for r in A)
G['quote_final_message'] = dict(H_ref_in_final_msg=dict(refc), A_ref_in_final_msg=dict(refA))
lens = [r['last_asst_len'] for r in R]
G['final_msg_chars_310'] = dict(median=statistics.median(lens), p90=sorted(lens)[int(0.9 * len(lens))], max=max(lens))
out['guards'] = G
# ---- 7. cost of a miss (estimated)
SIMPY = '/Users/chrisren/Development/claude-infrastructure/docs/research/usage-levers-2026-10-23/w4/sim.py'
sys.argv = [SIMPY, '/tmp/usage-audit/w4']
spec = importlib.util.spec_from_file_location('w4sim', SIMPY); sim = importlib.util.module_from_spec(spec); spec.loader.exec_module(sim)
P = [json.loads(l) for l in open(B + 'points.jsonl')]
nextpt = collections.defaultdict(list)
for p in P: nextpt[p['sid']].append(p['t_req'])
W_CW, W_CR, W_OUT = 0.245, 0.0067, 0.404
rows = []
for r in H:
    t_op = r['first_op']['ts']
    later = [x for x in nextpt[r['sid']] if x > t_op + 1]
    t_stop = min(later) if later else float('inf')
    n_later = sum(1 for q in sim.sess[r['sid']] if t_op < q['ts'] < t_stop)
    low = r['last_asst_len'] / 4.0 + 2000          # estimated: final message (chars/4) + ~2k of tool overhead to find it
    high = sim.RP['ctx']                            # estimated: a re-read as large as a whole re-prime (58.6k)
    for nm, tok in (('low', low), ('high', high)):
        pp = tok * W_CW / 1e6 + tok * n_later * W_CR / 1e6 + 400 * W_OUT / 1e6
        rows.append((nm, tok, n_later, pp))
def agg(nm):
    xs = [x for x in rows if x[0] == nm]
    return dict(tokens_median=round(statistics.median(x[1] for x in xs)), later_requests_median=statistics.median(x[2] for x in xs),
                pp_per_miss_median=round(statistics.median(x[3] for x in xs), 4), pp_per_week_total=round(sum(x[3] for x in xs) * WK, 3))
out['miss_cost_estimated'] = dict(low=agg('low'), high=agg('high'),
    guard_quote_final_msg_cost_pp_week=round(statistics.median(lens) / 4 * W_CW / 1e6 * 528 * WK + 0, 4))
json.dump(out, open(B + 'ana.json', 'w'), indent=1)
print(json.dumps(out, indent=1))
