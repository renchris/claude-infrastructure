import json,collections,sys,re,itertools
sys.path.insert(0,'.')
from detect2 import scripts,nan,hin,HIN_RE,segs,WRAP
C=json.load(open('corpus.json'))
def feats(sc):
    f=set()
    if re.search(r'\w\s*\(\s*\)',sc) or re.search(r'\bfunction\b',sc): f.add('func')
    assigned=set(re.findall(r'(?:^|[\s;&|(])([A-Za-z_]\w*)=',sc))
    for toks in segs(sc):
        k=0
        while k<len(toks) and (toks[k] in WRAP or re.match(r'^(?:-|\d+$)',toks[k]) or re.match(r'^\w+=',toks[k])): k+=1
        if k>=len(toks): continue
        w=toks[k].strip('"\'')
        m=re.match(r'^\$\{?([A-Za-z_]\w*)',w)
        if m: f.add('dollar_cmd_assigned' if m.group(1) in assigned else 'dollar_cmd_unassigned')
        if re.match(r'^\$\(',w): f.add('cmdsub_cmd')
        if w in('source','.'): f.add('source')
        if w=='eval': f.add('eval')
        if w in('shift','trap'): f.add('shift_trap')
        if w=='set' and any(t in('-','--') or not re.match(r'^[-+]',t) for t in toks[k+1:]): f.add('set_args')
    if re.search(r'"\$@"|\$@|\$\*',sc): f.add('dollar_at')
    if re.search(r'\bIFS\b',sc): f.add('IFS')
    if re.search(r'(?:^|[^\w.-])rm(?:dir)?(?![\w.-])',re.sub(r'''['"\\]''','',sc),re.I): f.add('rmword')
    if re.search(r'\{[^{}\s]*(?:,|\.\.)',re.sub(r'''['"\\]''','',sc)): f.add('brace')
    if re.search(r'(?:^|[\s;&|(){}])(?:argv|[0-9]+)(?:\[[^\]]*\])?=',sc): f.add('posassign')
    if re.search(r'(?:^|[\s;&|(){}!])set\s[^;&|\n]*(?:\$\(|`)',sc): f.add('set_cmdsub')
    if "'" in sc: f.add('has_squote')
    if re.search(r'\$(?:\{[!#@*0-9]|[#@*0-9])',sc): f.add('positional')
    return f
rows=[]
for o in C:
    if o['ver']!='2.1.293': continue
    sc=list(scripts(o['cmd']))
    if not sc: continue
    F=set()
    for s in sc:
        if nan(s) or "$'" in s: F|=feats(s)|{'nan'}
    if 'nan' not in F: continue
    lab='pos' if o['safety'] else 'ans' if o['pdsrc']=='user_temporary' else 'neg'
    rows.append((F,lab,o))
print('rows',len(rows),collections.Counter(l for F,l,o in rows))
fc=collections.defaultdict(collections.Counter)
for F,l,o in rows:
    for x in F: fc[x][l]+=1
for x,c in sorted(fc.items(),key=lambda kv:-(kv[1]['pos'])): print('%-22s pos %3d ans %3d neg %3d'%(x,c['pos'],c['ans'],c['neg']))
json.dump([(sorted(F),l,o['cmd'][:400]) for F,l,o in rows],open('feat_rows.json','w'),indent=0)
