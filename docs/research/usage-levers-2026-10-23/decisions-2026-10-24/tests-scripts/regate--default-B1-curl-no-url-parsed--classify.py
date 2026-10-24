import json, re, importlib.util, shlex
spec = importlib.util.spec_from_file_location("cg", "/tmp/conv-tests/regate/default-B1-curl-no-url-parsed/curl-gate.py")
cg = importlib.util.module_from_spec(spec); spec.loader.exec_module(cg)
nu = sorted(json.load(open('nourl.json')), key=lambda r: r['ts'])
SHORTV = set("AoeHwdubrXmKTcCyYzEDtx")
def positionals(argv):
    out=[]; i=1
    while i < len(argv):
        t=argv[i]
        if t in (")","|","||","&&",";"): break
        if t.startswith('--'):
            if '=' not in t and (t in cg._VALUE_FLAGS_LONG or t in ('--data-urlencode','--data','--data-raw','--output','--url','-G')):
                if t=='--url': out.append(argv[i+1] if i+1<len(argv) else ''); 
                i+=2; continue
            i+=1; continue
        if t.startswith('-') and len(t)>1:
            if t[-1] in SHORTV and len(t)>=2: i+=2; continue
            i+=1; continue
        out.append(t); i+=1
    return out
rows=[]
for i,r in enumerate(nu):
    cmd=r['cmd_redacted'].strip()
    invs = cg.curl_invocations(cmd) or cg.curl_invocations_by_segment(cmd) or []
    urltoks=[]
    for a in invs:
        for v in cg.expand_argv(a, cmd):
            if cg.info_only(v): continue
            p=cg.parse_argv(v, cmd); d,reason=cg.decide(p)
            if reason.startswith('No URL'):
                pos=[t for t in positionals(v) if '$' in t or '`' in t]
                urltoks.append(pos[0] if pos else '(none)')
    urltoks=list(dict.fromkeys(urltoks))
    rows.append(dict(i=i, ts=r['ts'], tuid=r['tool_use_id'], urltoks=urltoks, heredoc='<<' in cmd))
    print(i, 'heredoc' if '<<' in cmd else '       ', urltoks)
json.dump(rows,open('urltoks.json','w'),indent=1)
