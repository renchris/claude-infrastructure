import json, re
exec(open('relaxed.py').read().split("res = []")[0])
FORLIT=[0,10,26,27,31,34,38,43,46,47,48,52,53]
def run(i, allow_q, strip_arith, joint):
    cmd = nu[i]['cmd_redacted'].strip()
    b,_ = relaxed_bindings(cmd, allow_q=allow_q, strip_arith=strip_arith)
    invs = cg.curl_invocations(cmd) or cg.curl_invocations_by_segment(cmd) or []
    vs_all=[]
    for a in invs:
        if joint: vs = joint_variants(a,b) or [a]
        else:
            # pinned expand_argv semantics with these bindings
            variants=[[]]; capped=False
            for t in a:
                c = cg.expand_token(t,b) or [t]
                variants=[v+[x] for v in variants for x in c]
                if len(variants)>cg._EXPAND_CAP: variants=[a]; capped=True; break
            vs=variants
        vs_all+=vs
    vd=[cg.decide(cg.parse_argv(v,cmd)) for v in vs_all if not cg.info_only(v)]
    return 'ask' if any(d!='allow' for d,_ in vd) else 'allow'
for i in FORLIT:
    cmd=nu[i]['cmd_redacted']
    m=re.search(r"for\s+u\s+in\s+([^;\n]*?)\s*(?:;|\n)\s*do", cmd)
    import shlex
    nwords=len(shlex.split(m.group(1))) if m else None
    nu_refs=None
    print(i, 'words',nwords, 'arith' if '$((' in cmd else '', '?' if m and '?' in m.group(1) else '',
          'only_q', run(i,True,False,False), 'only_arith', run(i,False,True,False), 'only_joint', run(i,False,False,True),
          'q+arith', run(i,True,True,False), 'all', run(i,True,True,True))
