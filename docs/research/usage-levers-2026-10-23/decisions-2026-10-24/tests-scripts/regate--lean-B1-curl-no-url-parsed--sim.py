import json,re,shlex,importlib.util,collections
spec=importlib.util.spec_from_file_location('cg','/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/curl-gate.da7cb10ba.py')
cg=importlib.util.module_from_spec(spec); spec.loader.exec_module(cg)
rows=json.load(open('/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/nourl.json'))
FORLIT=[0,10,26,27,31,34,38,43,46,47,48,52,53]
tally=collections.Counter()
for i in FORLIT:
    c=rows[i]['cmd_redacted']
    m=next(m for m in cg._FOR_RE.finditer(c) if m.group(1)=='u')
    words=shlex.split(m.group(2))
    b=cg.shell_bindings(c)
    # why the pinned resolver failed
    ub=cg._UNSEEN_BINDERS.search(c)
    globw=[w for w in words if re.search(r"[$*?\[{]",w)]
    why=('unseen-binder %r'%ub.group(0)) if ub else ('loop word has [$*?[{] (%d of %d words)'%(len(globw),len(words)) if globw else ('u bound >1 or other' if 'u' not in b else 'expansion cap'))
    invs=cg.curl_invocations(c) or cg.curl_invocations_by_segment(c)
    verdicts=[]
    for a in invs:
        for w in words:
            v=[t.replace('${u}',w).replace('$u',w) for t in a]
            v=[t.replace('$UA','Mozilla/5.0') for t in v]
            v=[t.replace('$i','1').replace('$((i+1))','1') for t in v]
            d,r=cg.decide(cg.parse_argv(v,c)); verdicts.append((d,r))
    final=next(((d,r) for want in ('deny','ask') for d,r in verdicts if d==want),('allow',''))
    tally[final[0]]+=1
    print(i,len(words),'words |',why,'| simulated:',final[0],final[1][:70])
print('simulated outcome',dict(tally))
