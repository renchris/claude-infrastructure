import json
exec(open('relaxed.py').read().split("nu = sorted")[0])
exec("def relaxed_bindings" + open('relaxed.py').read().split("def relaxed_bindings")[1].split("res = []")[0])
from collections import Counter
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/curl-audit.jsonl')]
post=[r for r in rows if r['ts']>='2026-09-29T00:00:00Z' and r['decision']=='ask' and (r.get('reason') or '').startswith('No URL parsed') and r['session_id']!='t']
c=Counter(); sess=Counter()
for r in post:
    cmd=r['cmd_redacted'].strip()
    try: pinned=cg.decide_command(cmd)[0]
    except Exception: pinned='err'
    b,_=relaxed_bindings(cmd)
    invs=cg.curl_invocations(cmd) or cg.curl_invocations_by_segment(cmd) or []
    vd=[]
    for a in invs:
        for v in (joint_variants(a,b) or [a]):
            if not cg.info_only(v): vd.append(cg.decide(cg.parse_argv(v,cmd))[0])
    rel='deny' if 'deny' in vd else 'ask' if 'ask' in vd else 'allow'
    c[(pinned,rel)]+=1
    if rel!='ask': sess[r['session_id']]+=1
print('post-window nourl (excl session t):',len(post),'tuids',len({r['tool_use_id'] for r in post}),'sessions',len({r['session_id'] for r in post}))
print('(pinned,relaxed):',dict(c)); print('sessions gaining:',len(sess),sess.most_common(5))
