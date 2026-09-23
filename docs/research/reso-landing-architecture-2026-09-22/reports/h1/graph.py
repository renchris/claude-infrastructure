import subprocess, re, os, json, posixpath, pickle
R='/Users/chrisren/Development/reso-management-app'
ls=subprocess.run(['git','-C',R,'ls-tree','-r','origin/main'],capture_output=True,text=True).stdout.splitlines()
ents=[]
for l in ls:
    meta,path=l.split('\t',1); _,typ,sha=meta.split()
    if typ=='blob' and re.search(r'\.(ts|tsx|mts|cts|js|mjs|jsx|cjs)$',path) and not path.startswith(('node_modules/','.next/')):
        ents.append((path,sha))
allpaths=set(p for p,_ in subprocess.run(['git','-C',R,'ls-tree','-r','--name-only','origin/main'],capture_output=True,text=True).stdout.splitlines() and [(x,0) for x in subprocess.run(['git','-C',R,'ls-tree','-r','--name-only','origin/main'],capture_output=True,text=True).stdout.splitlines()])
inp=''.join(s+'\n' for _,s in ents).encode()
out=subprocess.run(['git','-C',R,'cat-file','--batch'],input=inp,capture_output=True).stdout
src={}; pos=0
for p,s in ents:
    nl=out.index(b'\n',pos); hdr=out[pos:nl].split(); size=int(hdr[2]); body=out[nl+1:nl+1+size]; pos=nl+1+size+1
    src[p]=body.decode('utf-8','replace')
IMP=re.compile(r'''(?:import|export)\s[^'"]*?from\s*['"]([^'"]+)['"]|import\s*['"]([^'"]+)['"]|import\(\s*['"]([^'"]+)['"]\s*\)|require\(\s*['"]([^'"]+)['"]\s*\)|vi\.mock\(\s*['"]([^'"]+)['"]''')
ALIAS=[('@replicache/','replicache/'),('@app/','src/app/'),('@components/','src/components/'),('@lib/','lib/'),('@actions/','src/app/actions/'),('@hooks/','src/hooks/'),('@styled-system/','styled-system/'),('drizzle/','drizzle/'),('styled-system/','styled-system/'),('src/','src/'),('recipes/','recipes/'),('replicache/','replicache/')]
EXT=['','.ts','.tsx','.js','.mjs','.mts','.cts','.jsx','.json','/index.ts','/index.tsx','/index.js']
def resolve(frm,spec):
    if spec.startswith('.'): base=posixpath.normpath(posixpath.join(posixpath.dirname(frm),spec))
    else:
        base=None
        for a,b in ALIAS:
            if spec.startswith(a): base=b+spec[len(a):]; break
        if spec=='theme': base='theme'
        if base is None: return None
    if base.endswith('.js'):
        for e in ('.ts','.tsx'):
            if base[:-3]+e in allpaths: return base[:-3]+e
    for e in EXT:
        if base+e in allpaths: return base+e
    return None
deps={}
for p,body in src.items():
    d=set()
    for m in IMP.finditer(body):
        spec=next(g for g in m.groups() if g)
        r=resolve(p,spec)
        if r: d.add(r)
    deps[p]=d
pickle.dump({'deps':deps,'allpaths':allpaths},open('/tmp/rla/wave1/h1/graph.pkl','wb'))
print('files',len(deps),'edges',sum(len(v) for v in deps.values()))
