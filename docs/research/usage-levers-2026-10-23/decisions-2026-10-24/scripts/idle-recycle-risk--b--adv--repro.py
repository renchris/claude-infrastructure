# Reproduce W4 150k/15m: recycles, terminal, sessions; and the hold-on-asks guard row; and a busy-miss-corrected row.
import importlib.util, json, sys, collections
SIMPY = '/Users/chrisren/Development/claude-infrastructure/docs/research/usage-levers-2026-10-23/w4/sim.py'
sys.argv = [SIMPY, '/tmp/usage-audit/w4']
spec = importlib.util.spec_from_file_location('w4sim_adv', SIMPY); sim = importlib.util.module_from_spec(spec); spec.loader.exec_module(sim)
base = sim.row(150_000, 15, 'mid')
print('150k/15m mid: pp/wk %.2f recycles %d terminal %d sessions_recycled %d' % (base['saved_pp_week_total'], base['recycles_14d'], base['terminal_recycles_14d'], base['sessions_recycled']))
cp = sim.row(350_000, 15, 'mid', rules=[(350_000, 15), (250_000, 60)])
print('current practice mid: pp/wk %.2f recycles %d terminal %d' % (cp['saved_pp_week_total'], cp['recycles_14d'], cp['terminal_recycles_14d']))
# busy-miss correction: hold at the 22 points whose idle minute 15 had a job busy() did not know
B = '/tmp/idle-recycle-risk/b/'
P = [json.loads(l) for l in open(B + 'points.jsonl')]
miss = set((P[i]['sid'], round(P[i]['t_prev'], 3)) for i in json.load(open(B + 'adv/busymiss.json')))
ob = sim.busy
sim.busy = lambda sid, t: ob(sid, t) or (sid, round(t - 900, 3)) in miss
g = sim.row(150_000, 15, 'mid')
print('with the 22 busy misses held: pp/wk %.2f recycles %d terminal %d' % (g['saved_pp_week_total'], g['recycles_14d'], g['terminal_recycles_14d']))
sim.busy = ob
# hold-on-asks from the worker's flags
F = json.load(open(B + 'guard_flags.json'))
held = set(k for k, v in F.items() if v['asks'])
sim.busy = lambda sid, t: ob(sid, t) or ('%s|%.3f' % (sid, round(t - 900, 3))) in held
g2 = sim.row(150_000, 15, 'mid')
print('hold-on-asks: pp/wk %.2f recycles %d terminal %d' % (g2['saved_pp_week_total'], g2['recycles_14d'], g2['terminal_recycles_14d']))
