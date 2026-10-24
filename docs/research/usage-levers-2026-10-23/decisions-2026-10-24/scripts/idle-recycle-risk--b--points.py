# Recycle points under a rule set, reusing w4/sim.py's loaded sessions, busy() and fire logic verbatim
# (simulate() copied with one change: it RECORDS each mid-session recycle point instead of pricing it).
# usage: python3 -I points.py <out.jsonl>
import importlib.util, json, sys, collections
SIMPY = '/Users/chrisren/Development/claude-infrastructure/docs/research/usage-levers-2026-10-23/w4/sim.py'
out_path = sys.argv[1]
sys.argv = [SIMPY, '/tmp/usage-audit/w4']
spec = importlib.util.spec_from_file_location('w4sim', SIMPY)
sim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sim)

# (sid, ts) -> (req, acct, file index) for the copy sim.py charged (v[0] after its mtime sort)
where = {}
for req, v in sim.occ.items():
    mt, a, x = v[0]
    where[(x[2], float(x[3]))] = (req, a, int(x[1]))

def points(rules, honor_busy=True):
    rules = sorted(rules, key=lambda kn: kn[1])
    def fires(sid, ctx, idle_s, t0):
        for K, N in rules:
            if idle_s >= N * 60 and ctx >= K and not (honor_busy and sim.busy(sid, t0 + N * 60)):
                return N * 60
        return None
    pts = []
    term = 0
    rp = sim.RP
    for k, L in sim.sess.items():
        off = 0
        prev = None
        for i, r in enumerate(L):
            if prev is not None and r['ctx'] < 0.6 * prev['ctx']:
                off = 0
            eff_prev = (prev['ctx'] - off) if prev is not None else 0
            gap = (r['ts'] - prev['ts']) if prev is not None else 0
            N_s = fires(k, eff_prev, gap, prev['ts']) if (prev is not None and r['turn']) else None
            if N_s is not None:
                grow = min(max(0, r['ctx'] - prev['ctx']), r['cw'] + r['inp'])
                ctx_new = rp['ctx'] + grow
                req, a, fi = where[(k, r['ts'])]
                preq = where[(k, prev['ts'])][0]
                pts.append(dict(sid=k, i=i, req=req, prev_req=preq, acct=a, fi=fi, path=sim.files[(a, fi)]['path'],
                                t_prev=prev['ts'], t_req=r['ts'], gap_s=round(gap, 1), fire_s=N_s,
                                ctx_eff=eff_prev, ctx_actual=prev['ctx'], turn=r['turn'],
                                nth_in_session=sum(1 for p in pts if p['sid'] == k) + 1))
                off = r['ctx'] - ctx_new
            prev = r
        if prev is not None:
            closed = any(sim.files[f]['closed'] for f in sim.sess_files[k])
            if not closed and fires(k, prev['ctx'] - off, sim.E - prev['ts'], prev['ts']) is not None:
                term += 1
    return pts, term

new, tn = points([(150_000, 15)])
cp, tc = points([(350_000, 15), (250_000, 60)])
cpk = set((p['sid'], p['req']) for p in cp)
for p in new:
    p['cp_also'] = int((p['sid'], p['req']) in cpk)
    p['files'] = sorted(set(sim.files[f]['path'] for f in sim.sess_files[p['sid']]))
with open(out_path, 'w') as fh:
    for p in new:
        fh.write(json.dumps(p) + '\n')
print('150k/15m mid-session recycle points: %d (terminal %d); sessions %d' % (len(new), tn, len(set(p['sid'] for p in new))))
print('current practice points: %d (terminal %d); overlap with new by (sid,req): %d' % (len(cp), tc, sum(p['cp_also'] for p in new)))
print('opener kind (scan.py turn field): %s' % dict(collections.Counter(p['turn'] for p in new)))
print('window days %.2f' % sim.DAYS)
