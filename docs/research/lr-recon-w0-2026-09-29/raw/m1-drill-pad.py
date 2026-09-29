import json, sys, uuid, os, random
src, dst_sid, pairs = sys.argv[1], sys.argv[2], int(sys.argv[3])
recs = [json.loads(l) for l in open(src)]
old = recs[0]['sessionId']
def fix(o):
    s = json.dumps(o).replace(old, dst_sid); return json.loads(s)
recs = [fix(r) for r in recs]
u_t = next(r for r in recs if r.get('type') == 'user' and isinstance(r.get('message', {}).get('content'), str))
a_t = [r for r in recs if r.get('type') == 'assistant'][-1]
last = [r for r in recs if 'uuid' in r][-1]['uuid']
words = 'the reconciler observes every pane and derives a phase from evidence on disk before it acts'.split()
random.seed(dst_sid)
out = list(recs)
for i in range(pairs):
    u = json.loads(json.dumps(u_t)); u['uuid'] = str(uuid.uuid4()); u['parentUuid'] = last
    u['message']['content'] = f'padding question {i}: ' + ' '.join(random.choice(words) for _ in range(60))
    u.pop('promptId', None); last = u['uuid']
    a = json.loads(json.dumps(a_t)); a['uuid'] = str(uuid.uuid4()); a['parentUuid'] = last
    a['message']['content'] = [{'type': 'text', 'text': f'padding answer {i}. ' + ' '.join(random.choice(words) for _ in range(300))}]
    a['message']['id'] = 'msg_pad%06d' % i; a['requestId'] = 'req_pad%06d' % i; last = a['uuid']
    out += [u, a]
with open(os.path.join(os.path.dirname(src), dst_sid + '.jsonl'), 'w') as f:
    for r in out: f.write(json.dumps(r) + '\n')
