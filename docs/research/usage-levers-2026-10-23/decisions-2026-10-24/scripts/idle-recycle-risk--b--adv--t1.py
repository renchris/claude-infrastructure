# T1: same operator prompt counted for >1 recycle point? T5: unknown-origin user records near points.
import json, collections
R = [json.loads(l) for l in open('/tmp/idle-recycle-risk/b/ctx.jsonl')]
for j, r in enumerate(R): r['pid'] = j
elig = [r for r in R if r['first_op'] and r['first_op']['ts'] >= r['t_prev'] + 900]
key = collections.Counter((r['sid'], r['first_op']['ts']) for r in elig)
dups = {k: v for k, v in key.items() if v > 1}
print('eligible returns', len(elig), 'distinct (sid, op_ts)', len(key), 'shared by >1 point', len(dups), 'extra rows', sum(v - 1 for v in dups.values()))
# for each shared prompt, which points? a later point lies between the earlier point and the prompt
for (sid, ts), v in list(dups.items())[:30]:
    ps = [r for r in elig if r['sid'] == sid and r['first_op']['ts'] == ts]
    print(' ', sid[:8], v, [(r['pid'], r['nth_in_session'], round((ts - r['t_prev'])/60)) for r in ps], repr(ps[0]['first_op']['text'][:60]))
kinds = collections.Counter()
for r in R:
    for o in r['openers']:
        kinds[o['kind']] += 1
print('opener kinds', dict(kinds))
print('first_op kinds', dict(collections.Counter(r['first_op']['kind'] for r in elig)))
print('first_op ps/ok', dict(collections.Counter((r['first_op'].get('ps'), r['first_op'].get('ok')) for r in elig)))
print('machine kinds before op (sum)', dict(sum((collections.Counter(r['machine_kinds_before_op']) for r in elig), collections.Counter())))
