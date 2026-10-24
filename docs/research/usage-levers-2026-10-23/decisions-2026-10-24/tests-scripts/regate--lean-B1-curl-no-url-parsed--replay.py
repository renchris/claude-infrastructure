import json,re,importlib.util,collections,sys
spec=importlib.util.spec_from_file_location('cg','/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/curl-gate.da7cb10ba.py')
cg=importlib.util.module_from_spec(spec); spec.loader.exec_module(cg)
rows=json.load(open('/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/nourl.json'))
out=[]
for i,r in enumerate(rows):
    c=r['cmd_redacted']
    d,why,_=cg.decide_command(c)
    invs=cg.curl_invocations(c)
    path='whole'
    if invs is None: invs=cg.curl_invocations_by_segment(c); path='segment'
    nourl=[]
    for a in invs or []:
        for v in cg.expand_argv(a,c):
            if cg.info_only(v): continue
            p=cg.parse_argv(v,c); dd,rr=cg.decide(p)
            if rr.startswith('No URL parsed'): nourl.append(a)
    # $-tokens in no-url invocations that are not flag values we can ignore: take tokens with $
    toks=sorted({t for a in nourl for t in a[1:] if '$' in t or '`' in t})
    ub=cg._UNSEEN_BINDERS.search(c)
    b=cg.shell_bindings(c)
    out.append(dict(i=i,replay=d,replay_reason=why[:40],path=path,n_nourl_inv=len(nourl),toks=toks,unseen=ub.group(0) if ub else None,bindings=sorted(b)))
json.dump(out,open('/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/replay.json','w'),indent=0)
print('replay decisions',collections.Counter((o['replay'],o['replay_reason']) for o in out))
print('unseen-binder refusals',collections.Counter(o['unseen'] for o in out))
for o in out: print(o['i'],o['path'],o['n_nourl_inv'],repr(o['unseen']),[t[:50] for t in o['toks']][:4])
