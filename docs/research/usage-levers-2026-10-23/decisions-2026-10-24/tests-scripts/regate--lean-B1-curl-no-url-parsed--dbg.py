import json,re,importlib.util
spec=importlib.util.spec_from_file_location('cg','/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/curl-gate.da7cb10ba.py')
cg=importlib.util.module_from_spec(spec); spec.loader.exec_module(cg)
rows=json.load(open('/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/nourl.json'))
for i in map(int,__import__('sys').argv[1:]):
    c=rows[i]['cmd_redacted']
    fors=[(m.group(1),m.group(2)[:80]) for m in cg._FOR_RE.finditer(c)]
    asg=[(m.group(1),m.group(4)[:40]) for m in cg._ASSIGN_RE.finditer(c)]
    b=cg.shell_bindings(c)
    print(i,'FOR',fors); print('  ASSIGN',asg); print('  BOUND',{k:(v[0], (v[1][:2] if isinstance(v[1],list) else v[1][:40])) for k,v in b.items()})
    print('  exp $u',cg.expand_token('$u',b) and len(cg.expand_token('$u',b)))
