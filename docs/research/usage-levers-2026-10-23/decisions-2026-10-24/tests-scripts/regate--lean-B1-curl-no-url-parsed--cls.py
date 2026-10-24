import json,re,importlib.util,collections
spec=importlib.util.spec_from_file_location('cg','/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/curl-gate.da7cb10ba.py')
cg=importlib.util.module_from_spec(spec); spec.loader.exec_module(cg)
rows=json.load(open('/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/nourl.json'))
VAL={'-o','--output','-A','--user-agent','-w','--write-out','-e','--referer','-H','--header','-u','--user','--data-urlencode','-d','--data','-b','--cookie','--max-time','-m','-x','--connect-timeout','-r','-c','-T','-F','-X'}
res=[]
for i,r in enumerate(rows):
    c=r['cmd_redacted']
    invs=cg.curl_invocations(c) or cg.curl_invocations_by_segment(c) or []
    urltoks=[]
    for a in invs:
        p=cg.parse_argv(a,c); 
        if p.get('urls'): continue
        skip=False
        for t in a[1:]:
            if skip: skip=False; continue
            if t in VAL: skip=True; continue
            if t.startswith('-'): continue
            urltoks.append(t)
    names=set()
    for t in urltoks:
        m=re.search(r'\$\{?([A-Za-z_]\w*|\d)',t)
        if m: names.add(m.group(1))
        elif '$(' in t: names.add('$(')
    shape=[]
    for n in names:
        if n=='$(': shape.append('inline$()'); continue
        if n.isdigit(): shape.append('positional$'+n); continue
        fm=re.search(r'for\s+'+n+r'\s+in\s+([^;\n]*?)\s*(;|\n)\s*do',c)
        if fm:
            lst=fm.group(1)
            shape.append('for-dyn' if re.search(r'\$|`',lst) or re.search(r'(^|\s)[^"\'\s]*[*][^\s]*',lst) else 'for-lit'); continue
        if re.search(r'read\b[^;\n|]*\b'+n+r'\b',c): shape.append('while-read'); continue
        am=re.search(r'(?:^|[\s;&|(])'+n+r'=(\S{0,3})',c)
        if am: shape.append('assign$()' if am.group(1).startswith('$(') or am.group(1).startswith('"$(') else 'assign:'+am.group(1)); continue
        shape.append('unbound:'+n)
    res.append((i,sorted(set(shape)),urltoks[:3]))
for x in res: print(x[0],x[1],[t[:60] for t in x[2]])
json.dump(res,open('/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/cls.json','w'))
