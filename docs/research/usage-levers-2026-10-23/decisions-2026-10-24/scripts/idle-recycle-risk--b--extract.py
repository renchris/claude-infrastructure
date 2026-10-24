# For each recycle point (points.jsonl), stream the session's transcript file(s) and record:
#   the turn opener(s) between the idle start and the recycle-point request, the predecessor's final
#   assistant text before the gap, and the FIRST operator-typed prompt at/after the idle point.
# usage: python3 -I extract.py points.jsonl out.jsonl
import json, sys, re, collections
from datetime import datetime
pts = [json.loads(l) for l in open(sys.argv[1])]
def ep(s):
    try: return datetime.fromisoformat(s.replace('Z', '+00:00')).timestamp()
    except Exception: return None
def text_of(c):
    if isinstance(c, list):
        out = []
        for b in c:
            if not isinstance(b, dict): continue
            if b.get('type') == 'text': out.append(b.get('text', ''))
            elif b.get('type') == 'image': out.append('[image]')
        return ' '.join(out)
    return c if isinstance(c, str) else ''
import sys as _s; _s.path.insert(0, '/tmp/idle-recycle-risk/b'); from lib import MACHINE_TYPED
SUCC = re.compile(r'self-recycle|resumed by a deterministic|predecessor|HANDOFF-ENGAGE|continuation bridge|successor', re.I)
def kind(r, t):
    if r.get('isMeta'): return 'meta'
    o = r.get('origin') or {}
    ok = o.get('kind') if isinstance(o, dict) else None
    ps = r.get('promptSource')
    s = t.lstrip()
    if ok == 'task-notification' or s.startswith('<task-notification>'): return 'notice'
    if ok == 'auto-continuation': return 'autocont'
    if ps == 'sdk': return 'sdk'
    if s.startswith('Another Claude session sent a message') or s.startswith('<teammate-message'): return 'peer'
    if s.startswith('[Request interrupted'): return 'interrupt'
    if s.startswith(('<bash-stdout', '<bash-stderr', '<local-command-stdout', '<local-command-stderr', '<local-command-caveat', 'Caveat:')): return 'localout'
    if MACHINE_TYPED.match(s): return 'injected'
    if ok == 'human': return 'operator'
    if s.startswith(('<bash-input>', '<command-name>', '<command-message>')): return 'operator-noorigin'
    return 'unknown-noorigin'
by_sid = collections.defaultdict(list)
for p in pts: by_sid[p['sid']].append(p)
out = open(sys.argv[2], 'w')
for sid, P in by_sid.items():
    users, asst = [], []   # (ts, kind, text, extra)
    for path in P[0]['files']:
        try: fh = open(path, 'rb')
        except OSError: continue
        for line in fh:
            head = line[:3000]
            isu = b'"type":"user"' in head
            isa = b'"type":"assistant"' in head
            if not (isu or isa): continue
            if isu and b'"tool_result"' in line and b'"tool_use_id"' in line:
                # tool results never open a turn
                continue
            try: r = json.loads(line)
            except Exception: continue
            if r.get('isSidechain'): continue
            ts = ep(r.get('timestamp', '')) or 0
            m = r.get('message') or {}
            if r.get('type') == 'user':
                c = m.get('content')
                if isinstance(c, list) and any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in c): continue
                t = text_of(c)
                o = r.get('origin') or {}
                users.append((ts, kind(r, t), t[:4000], dict(ps=r.get('promptSource'), ok=(o.get('kind') if isinstance(o, dict) else None), ver=r.get('version'))))
            elif r.get('type') == 'assistant':
                t = text_of(m.get('content'))
                tools = [b.get('name') for b in (m.get('content') or []) if isinstance(b, dict) and b.get('type') == 'tool_use']
                asst.append((ts, r.get('requestId'), t, tools, (m.get('usage') or {})))
    users.sort(key=lambda x: x[0]); asst.sort(key=lambda x: x[0])
    for p in P:
        tP, tR = p['t_prev'], p['t_req']
        openers = [dict(ts=u[0], kind=u[1], text=u[2][:600], **u[3]) for u in users if tP < u[0] <= tR + 0.5]
        # predecessor's final words: the assistant text records of the last turn before the gap
        last_txt = [a for a in asst if a[0] <= tP + 0.5 and a[2].strip()]
        last = last_txt[-1][2] if last_txt else ''
        last_ts = last_txt[-1][0] if last_txt else None
        # last operator prompt before the gap (how long the operator had been away)
        prev_op = [u for u in users if u[0] <= tP and u[1] in ('operator', 'operator-noorigin')]
        # first operator prompt after the idle start
        nxt = [u for u in users if u[0] > tP]
        first_op = None; n_mach_before = 0; mach_kinds = collections.Counter()
        for u in nxt:
            if u[1] in ('operator', 'operator-noorigin'):
                first_op = u; break
            if u[1] not in ('meta',): n_mach_before += 1; mach_kinds[u[1]] += 1
        turn = []
        if first_op:
            nxt_open = [u[0] for u in users if u[0] > first_op[0] + 1 and u[1] not in ('meta',)]
            t_end = nxt_open[0] if nxt_open else float('inf')
            turn = [a for a in asst if first_op[0] < a[0] < t_end]
        def ctx_of(u): return (u.get('input_tokens') or 0) + (u.get('cache_creation_input_tokens') or 0) + (u.get('cache_read_input_tokens') or 0)
        reqs = {}
        for a in turn:
            reqs.setdefault(a[1], a)
        tl = list(reqs.values())
        reply_txt = ' '.join(a[2] for a in turn if a[2].strip())
        rec = dict(p)
        rec.update(op_turn=dict(n_req=len(tl), out=sum((a[4].get('output_tokens') or 0) for a in tl),
                                cw=sum((a[4].get('cache_creation_input_tokens') or 0) for a in tl),
                                ctx0=(ctx_of(tl[0][4]) if tl else None), ctx1=(ctx_of(tl[-1][4]) if tl else None),
                                tools=collections.Counter(t for a in turn for t in a[3]).most_common(6),
                                reply_head=reply_txt[:700]))
        rec.pop('files', None)
        rec.update(openers=openers, last_asst=last[-6000:], last_asst_len=len(last), last_asst_ts=last_ts,
                   prev_op_ts=(prev_op[-1][0] if prev_op else None), prev_op_text=(prev_op[-1][2][:300] if prev_op else None),
                   first_op=(dict(ts=first_op[0], kind=first_op[1], text=first_op[2], **first_op[3]) if first_op else None),
                   n_machine_before_op=n_mach_before, machine_kinds_before_op=dict(mach_kinds),
                   session_end_ts=(asst[-1][0] if asst else None))
        out.write(json.dumps(rec) + '\n')
out.close()
print('wrote', sum(len(v) for v in by_sid.values()))
