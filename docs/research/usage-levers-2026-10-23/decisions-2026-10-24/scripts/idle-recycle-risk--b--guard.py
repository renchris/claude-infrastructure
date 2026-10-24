# Guard G2: hold an idle recycle when the predecessor's final assistant message asks the operator for
# something. Flags every candidate idle point (turn start after >=15 min at >=150k ACTUAL context, a
# superset of the counterfactual recycle points), then re-runs w4/sim.py's own row() with the hold
# added to busy(). usage: python3 -I guard.py
import importlib.util, json, sys, re, collections
from datetime import datetime
SIMPY = '/Users/chrisren/Development/claude-infrastructure/docs/research/usage-levers-2026-10-23/w4/sim.py'
sys.argv = [SIMPY, '/tmp/usage-audit/w4']
spec = importlib.util.spec_from_file_location('w4sim', SIMPY); sim = importlib.util.module_from_spec(spec); spec.loader.exec_module(sim)
# waiting-recycle.sh's GENUINE open-decision regex (hooks/waiting-recycle.sh:1210), verbatim
GENUINE = re.compile(r"your (credential|password|api.?key|secret|token|login|cookie)|need (your|the)[^.]{0,40}(credential|password|secret|token|key|access|permission|approval)|only you (can|have|know)|(don.?t|do not|no) [a-z ]{0,20}access|which account|you.?ll need to (provide|give|share|tell|run|log ?in)|i (don.?t|do not) have (access|the |your |permission)|can you (provide|share|tell me|give me|confirm which)|which (do you|would you|of (these|the)|option|approach|one)|(would|do) you prefer|your call|up to you|how would you like|which direction|your approval|requires? (your|sudo|approval|authentication)|run (this|it|the [a-z ]{0,20}) ?yourself|sudo|interactive login|auth login|pushing to (main|origin)|push (is|remains)[^.]{0,20}your call|won.?t push|will not push|not push(ing)? (to|without)|force.?push|destructive migration|drop table|delete[^.]{0,20}production|navigation pattern|(db|database) timeout", re.I)
ASKS = re.compile(r"\?\s*\**\s*$|⛔|\bneeds? you\b|\byour (call|calls|pick|picks|decision|answer|ruling|sign-?off|go-?ahead|choice)\b|\breply (with|approve|yes)|\bwaiting (on|for) your\b|\bstill yours\b|\byours( next)?:|\banswer (here|it)\b|\btell me\b|\blet me know\b|\bshall i\b|\bshould i\b|\bwant me to\b|\bdo you want\b|approve or veto|once you(.ve| have)? (decide|decided|answer|reply|confirm|pick)|▶ run this|\bone step needs you\b|\bwaiting on you\b", re.I | re.M)
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
def text_of(c):
    if isinstance(c, list): return ' '.join(b.get('text', '') for b in c if isinstance(b, dict) and b.get('type') == 'text')
    return c if isinstance(c, str) else ''
cand = collections.defaultdict(list)
for k, L in sim.sess.items():
    for p, r in zip(L, L[1:]):
        if r['turn'] and r['ts'] - p['ts'] >= 900 and p['ctx'] >= 150_000:
            cand[k].append(p['ts'])
flags = {}
MISSING = set()
for k, T in cand.items():
    texts = []
    for f in sim.sess_files[k]:
        try: fh = open(sim.files[f]['path'], 'rb')
        except OSError: MISSING.add(k); continue
        for line in fh:
            if b'"type":"assistant"' not in line[:3000] or b'"text"' not in line: continue
            r = json.loads(line)
            if r.get('isSidechain'): continue
            t = text_of((r.get('message') or {}).get('content'))
            if t.strip(): texts.append((ep(r.get('timestamp', '')) or 0, t))
    texts.sort(key=lambda x: x[0])
    j = 0
    for t0 in sorted(T):
        last = ''
        for ts, t in texts:
            if ts <= t0 + 0.5: last = t
            else: break
        tail = last[-1500:]
        flags[(k, round(t0, 3))] = dict(genuine=bool(GENUINE.search(tail)), asks=bool(ASKS.search(tail)), len=len(last))
json.dump({'%s|%.3f' % kk: v for kk, v in flags.items()}, open('/tmp/idle-recycle-risk/b/guard_flags.json', 'w'))
n = len(flags)
print('sessions with a missing transcript file: %d' % len(MISSING))
print('candidate idle points (>=15m, >=150k actual): %d; final message asks operator: %d (%.0f%%); GENUINE regex: %d (%.0f%%)'
      % (n, sum(v['asks'] for v in flags.values()), 100 * sum(v['asks'] for v in flags.values()) / n,
         sum(v['genuine'] for v in flags.values()), 100 * sum(v['genuine'] for v in flags.values()) / n))
orig_busy = sim.busy
base = sim.row(150_000, 15, 'mid')
res = dict(base=dict(pp=base['saved_pp_week_total'], recycles=base['recycles_14d'], term=base['terminal_recycles_14d']))
for name in ('asks', 'genuine'):
    held = set(kk for kk, v in flags.items() if v[name])
    def busy2(sid, t, held=held):
        return orig_busy(sid, t) or (sid, round(t - 900, 3)) in held
    sim.busy = busy2
    g = sim.row(150_000, 15, 'mid')
    res['hold_' + name] = dict(pp=g['saved_pp_week_total'], recycles=g['recycles_14d'], term=g['terminal_recycles_14d'])
    sim.busy = orig_busy
print(json.dumps(res))
json.dump(res, open('/tmp/idle-recycle-risk/b/guard_sim.json', 'w'))
