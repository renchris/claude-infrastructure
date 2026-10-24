import os,re,sys
roots=sys.argv[1:]
# patterns of invoking a bare `claude` as a command
shell_pats=[
 re.compile(r'(^|[;&|(`]|\$\(|\bthen\b|\bdo\b|\belse\b|&&|\|\||\bexec\b|\bcommand\b|\btimeout\s+\S+|\bnohup\b|\benv\b(\s+\w+=\S+)*|^\s*(\w+=\S+\s+)+)\s*claude(\s|$|["\')])'),
]
py_pats=[re.compile(r'''\[\s*["']claude["']\s*,'''), re.compile(r'''(shutil\.which|which)\(\s*["']claude["']\s*\)'''), re.compile(r'''["']claude["']\s*\]''')]
js_pats=[re.compile(r'''(spawn|execFile|exec|execa)\w*\(\s*["'`]claude["'`\s]''')]
hits=[]
for root in roots:
    for dp,dn,fn in os.walk(root):
        dn[:]=[d for d in dn if d not in('node_modules','.git','vendor','tests','test','fixtures','__pycache__')]
        for f in fn:
            p=os.path.join(dp,f)
            if f.endswith(('.md','.jsonl','.json','.txt','.bats','.png','.svg','.lock','.yaml','.yml')): continue
            try:
                with open(p,'r',errors='strict') as fh: lines=fh.readlines()
            except Exception: continue
            is_py = f.endswith('.py') or (lines and 'python' in lines[0])
            is_js = f.endswith(('.js','.mjs','.ts'))
            for i,l in enumerate(lines,1):
                s=l.strip()
                if s.startswith('#') or s.startswith('//') : continue
                if is_py: pats=py_pats
                elif is_js: pats=js_pats
                else: pats=shell_pats
                for pat in pats:
                    if pat.search(l):
                        hits.append(f"{p}:{i}: {s[:160]}"); break
for h in hits: print(h)
print("TOTAL",len(hits),file=sys.stderr)
