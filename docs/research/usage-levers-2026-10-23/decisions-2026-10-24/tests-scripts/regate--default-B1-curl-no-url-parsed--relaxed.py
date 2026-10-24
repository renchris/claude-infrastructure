import json, re, importlib.util, shlex, itertools
spec = importlib.util.spec_from_file_location("cg", "/tmp/conv-tests/regate/default-B1-curl-no-url-parsed/curl-gate.py")
cg = importlib.util.module_from_spec(spec); spec.loader.exec_module(cg)
nu = sorted(json.load(open('nourl.json')), key=lambda r: r['ts'])
ARITH = re.compile(r"\$\(\(([^()]*)\)\)")
def relaxed_bindings(cmd, allow_q=True, strip_arith=True):
    c = ARITH.sub("0", cmd) if strip_arith else cmd
    if cg._UNSEEN_BINDERS.search(c): return {}, cg._UNSEEN_BINDERS.search(c).group(0)
    sites = {}
    for m in cg._FOR_RE.finditer(c):
        raw = m.group(2)
        try: words = shlex.split(raw, posix=True)
        except ValueError: words = None
        globre = r"[$*\[{]" if allow_q else r"[$*?\[{]"
        ok = words and "$(" not in raw and "`" not in raw and not any(re.search(globre, w) for w in words)
        # an unquoted ? is a real glob: require every ?-word quoted in raw
        if ok and allow_q:
            for w in words:
                if "?" in w and not ('"%s"' % w in raw or "'%s'" % w in raw): ok = False
        sites.setdefault(m.group(1), []).append(("for", words) if ok else None)
    for m in cg._ASSIGN_RE.finditer(c):
        name, plus, bracket, raw = m.groups()
        bad = plus or bracket or "$(" in raw or "`" in raw or raw.startswith("'") and "$" in raw
        sites.setdefault(name, []).append(None if bad else ("assign", raw))
    return {n: s[0] for n, s in sites.items() if len(s) == 1 and s[0] is not None}, None
def joint_variants(argv, b):
    names = sorted({(m.group(1) or m.group(2)) for t in argv for m in cg._REF_RE.finditer(t)})
    fornames = [n for n in names if b.get(n, (None,))[0] == "for"]
    combos = list(itertools.product(*[b[n][1] for n in fornames])) or [()]
    if len(combos) > 256: return None
    out = []
    for combo in combos:
        bb = dict(b)
        for n, v in zip(fornames, combo): bb[n] = ("assign", shlex.quote(v))
        v2 = []
        for t in argv:
            e = cg.expand_token(t, bb)
            if e is None or len(e) != 1: v2.append(t)
            else: v2.append(e[0])
        out.append(v2)
    return out
res = []
for i, r in enumerate(nu):
    cmd = r['cmd_redacted'].strip()
    b, why = relaxed_bindings(cmd)
    invs = cg.curl_invocations(cmd) or cg.curl_invocations_by_segment(cmd) or []
    verdicts = []
    for a in invs:
        vs = joint_variants(a, b) or [a]
        for v in vs:
            if cg.info_only(v): continue
            verdicts.append(cg.decide(cg.parse_argv(v, cmd)))
    final = next(((d, rs) for want in ("deny", "ask") for d, rs in verdicts if d == want), ("allow", "all allow"))
    hosts = sorted({rs.split()[1] if rs.startswith('GET') else '' for d, rs in verdicts if d=='allow'} - {''})
    res.append(dict(i=i, final=final[0], reason=final[1][:70], refused_by=why, nhosts=len(hosts)))
    print(i, final[0], final[1][:70], '| refused_by', why, '| allow-hosts', len(hosts))
json.dump(res, open('relaxed.json','w'), indent=1)
