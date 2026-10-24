import json, importlib.util, sys
spec = importlib.util.spec_from_file_location("cg", "/tmp/conv-tests/regate/default-B1-curl-no-url-parsed/curl-gate.py")
cg = importlib.util.module_from_spec(spec); spec.loader.exec_module(cg)
from collections import Counter
nu = sorted(json.load(open('nourl.json')), key=lambda r: r['ts'])
c = Counter(); out=[]
for i, r in enumerate(nu):
    cmd = r['cmd_redacted'].strip()
    d, reason, meta = cg.decide_command(cmd)
    unseen = bool(cg._UNSEEN_BINDERS.search(cmd))
    m = cg._UNSEEN_BINDERS.search(cmd)
    b = cg.shell_bindings(cmd)
    c[(d, reason[:30])] += 1
    out.append(dict(i=i, decision=d, reason=reason[:60], unseen=m.group(0) if m else None, bindings=sorted(b)))
json.dump(out, open('replay.json','w'), indent=1)
print(c)
for o in out: print(o)
