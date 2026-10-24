import json, importlib.util
spec = importlib.util.spec_from_file_location("cg", "/tmp/conv-tests/regate/default-B1-curl-no-url-parsed/curl-gate.py")
cg = importlib.util.module_from_spec(spec); spec.loader.exec_module(cg)
nu = sorted(json.load(open('nourl.json')), key=lambda r: r['ts'])
res=[]
for i, r in enumerate(nu):
    cmd = r['cmd_redacted'].strip()
    invs = cg.curl_invocations(cmd)
    fb = False
    if invs is None:
        invs = cg.curl_invocations_by_segment(cmd); fb=True
    bad=[]
    for a in invs:
        for v in cg.expand_argv(a, cmd):
            if cg.info_only(v): continue
            p = cg.parse_argv(v, cmd)
            d, reason = cg.decide(p)
            if reason.startswith('No URL'):
                # positional non-flag tokens with $ in them
                bad.append(' '.join(v)[:220])
    res.append(dict(i=i, fallback=fb, n_inv=len(invs), nourl_invs=bad))
    print(f"--- {i} fb={fb} invs={len(invs)}")
    for b in bad[:4]: print("   ", b)
json.dump(res, open('diag.json','w'), indent=1)
