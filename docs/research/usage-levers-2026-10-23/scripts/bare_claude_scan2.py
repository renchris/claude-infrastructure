import os,re,sys
WRAP={'exec','command','nohup','env','time','sudo','builtin','then','do','else','if','while','until','!','{','('}
seg_split=re.compile(r'\|\||&&|[;|&`]|\$\(|\(')
assign=re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=')
py_pats=[re.compile(r'''\[\s*["']claude["']\s*[,\]]'''), re.compile(r'''which\(\s*["']claude["']\s*\)'''),
         re.compile(r'''(Popen|run|call|check_output|check_call)\(\s*["']claude[ "']''')]
js_pats=[re.compile(r'''(spawn|execFile|execSync|exec|execa)\w*\(\s*["'`]claude[ "'`]''')]
def shell_hit(line):
    s=line.strip()
    if not s or s.startswith('#'): return False
    # drop quoted strings' contents crudely: remove "..." and '...' spans
    t=re.sub(r'"(\\.|[^"\\])*"','""',s); t=re.sub(r"'[^']*'","''",t)
    for seg in seg_split.split(t):
        toks=seg.split()
        i=0
        while i<len(toks):
            w=toks[i]
            if assign.match(w) or w in WRAP: i+=1; continue
            if w=='timeout' or w=='gtimeout':
                i+=1
                while i<len(toks) and toks[i].startswith('-'): i+=1
                i+=1; continue
            break
        if i<len(toks) and toks[i] in ('claude','claude\\'): return True
    return False
out=[]
for root in sys.argv[1:]:
    for dp,dn,fn in os.walk(root):
        dn[:]=[d for d in dn if d not in('node_modules','.git','vendor','tests','test','fixtures','__pycache__','evolve-fixtures')]
        for f in fn:
            if f.endswith(('.md','.jsonl','.json','.txt','.bats','.png','.svg','.lock','.yaml','.yml','.swift','.plist')): continue
            p=os.path.join(dp,f)
            try: lines=open(p,errors='strict').readlines()
            except Exception: continue
            first=lines[0] if lines else ''
            is_py=f.endswith('.py') or 'python' in first
            is_js=f.endswith(('.js','.mjs','.ts','.cjs')) or 'node' in first
            for n,l in enumerate(lines,1):
                if is_py: hit=any(p_.search(l) for p_ in py_pats) and not l.strip().startswith('#')
                elif is_js: hit=any(p_.search(l) for p_ in js_pats) and not l.strip().startswith('//')
                else: hit=shell_hit(l)
                if hit: out.append(f"{p}:{n}: {l.strip()[:170]}")
print("\n".join(out)); print("TOTAL",len(out),file=sys.stderr)
