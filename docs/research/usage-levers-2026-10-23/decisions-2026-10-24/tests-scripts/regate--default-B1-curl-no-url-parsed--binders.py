import json, re
nu = sorted(json.load(open('nourl.json')), key=lambda r: r['ts'])
toks = json.load(open('urltoks.json'))
fix = {20:'thumb',21:'thumb'}
for i,(r,t) in enumerate(zip(nu,toks)):
    cmd=r['cmd_redacted']
    names=set()
    for tok in t['urltoks']:
        m=re.match(r"\$\{?([A-Za-z_][A-Za-z0-9_]*|\d)", tok)
        if m: names.add(m.group(1))
        elif tok.startswith('$('): names.add('$(')
    if i in fix: names={fix[i]}
    print(f"=== {i} names={sorted(names)} len={len(cmd)}")
    for n in sorted(names):
        if n=='$(' or n.isdigit(): continue
        for m in re.finditer(r"for\s+%s\s+in\s+([^;\n]{0,160})"%re.escape(n), cmd): print("   FOR:", m.group(0)[:200])
        for m in re.finditer(r"(while[^;\n]{0,60})?read\b[^;\n|]*\b%s\b[^;\n]{0,10}"%re.escape(n), cmd): print("   READ:", m.group(0)[:160])
        for m in re.finditer(r"(?<![\w$])%s=([^;\n]{0,120})"%re.escape(n), cmd): print("   ASSIGN:", m.group(0)[:160])
        for m in re.finditer(r"xargs[^;\n|]{0,60}", cmd): print("   XARGS:", m.group(0))
    if any(n.isdigit() for n in names):
        for m in re.finditer(r"(?:xargs[^;\n|]{0,60}|/[\w./-]+\.sh [^;\n|]{0,100}|\./[\w.-]+\.sh[^;\n|]{0,80}|\.\./[\w.-]+\.sh[^;\n|]{0,80}|\$\w+/[\w.]+\.sh[^;\n|]{0,80})", cmd.split('EOF')[-1]): print("   SCRIPT-CALL:", m.group(0)[:160])
