# Detector v2: ports CC 2.1.293's nan() and Hin() regexes (verbatim from the binary) onto the -c script
# extracted with a shell-word reader; adds the rm-target shapes. Measured against corpus.json.
import re,json,collections,sys
SHELLS=r'(?:ba|z|da|k|rba)?sh'
INL=re.compile(r'(?:^|(?<=[\s;&|(`{]))(?:[\w./-]*/)?'+SHELLS+r'\s+((?:-[A-Za-z]+\s+|--[\w-]+\s+)*)-[A-Za-z]*c[A-Za-z]*\s+|(?:^|(?<=[\s;&|(`{]))"?\$\{?\w+\}?"?\s+-c\s+')
def read_word(s,i):
    out=[];n=len(s)
    while i<n:
        c=s[i]
        if c in ' \t\n;&|<>()': break
        if c=="'":
            j=s.find("'",i+1); j=n if j<0 else j; out.append(s[i+1:j]); i=j+1
        elif c=='$' and i+1<n and s[i+1]=="'":
            j=i+2
            while j<n and s[j]!="'":
                j+=2 if s[j]=='\\' else 1
            out.append(s[i+2:j]); i=j+1
        elif c=='"':
            j=i+1;buf=[]
            while j<n and s[j]!='"':
                if s[j]=='\\' and j+1<n and s[j+1] in '"\\$`\n': buf.append(s[j+1]); j+=2
                else: buf.append(s[j]); j+=1
            out.append(''.join(buf)); i=j+1
        elif c=='\\' and i+1<n: out.append(s[i+1]); i+=2
        else: out.append(c); i+=1
    return ''.join(out)
def scripts(cmd):
    for m in INL.finditer(cmd):
        yield read_word(cmd,m.end())
NAN1=re.compile(r'\{[^{}\s]*(?:,|\.\.)'); NAN2=re.compile(r'(?:^|[^\w.-])rm(?:dir)?(?![\w.-])',re.I); NAN3=re.compile(r'(?:^|[;&|(){}\n`!])\s*(?:\w+\+?=\S*\s+)*\$')
def nan(e):
    n=re.sub(r'''\$(?=['"])|['"\\]''','',e)
    return bool(NAN1.search(n) or NAN2.search(n) or NAN3.search(n))
HIN_RE=re.compile(r'''\bfunction\b|\balias\b|\bIFS\b|\w\s*\(\s*\)|(?:^|[\s;&|(){}])(?:argv|[0-9]+)(?:\[[^\]]*\])?=|(?:^|[\s;&|(){}!])set\s[^;&|\n]*(?:\$\(|`)''')
WRAP={'env','command','exec','nohup','nice','time','builtin','sudo','xargs','timeout','stdbuf','caffeinate','then','do','else','elif','if','while','until','!'}
def segs(e):
    for part in re.split(r'[;&|\n(){}`]+',e):
        toks=part.split()
        if toks: yield toks
def hin(e):
    if HIN_RE.search(e): return 'hin_re'
    for toks in segs(e):
        k=0
        while k<len(toks) and (toks[k] in WRAP or re.match(r'^(?:-|\d+$)',toks[k]) or re.match(r'^\w+=',toks[k])): k+=1
        if k>=len(toks): continue
        w=toks[k].strip('"\'')
        if re.match(r'^(?:shift|source|\.|eval|trap)$',w): return 'src_eval'
        if re.match(r'^\$(?!\{?[0-9@*#])',w): return 'dollar_cmd'
        if w=='set' and any(t in('-','--') or not re.match(r'^[-+]',t) for t in toks[k+1:]): return 'set_args'
    return None
RM_OCC=re.compile(r'''(?:^|[;&|\n({`]|&&|\|\||\bthen\b|\bdo\b|\belse\b)\s*(?:sudo\s+|command\s+|xargs\s+)?(?:/bin/|/usr/bin/)?(rm|rmdir)\s+([^;&|\n)]*)''')
VAR_SLASH=re.compile(r'''\$\{?([A-Za-z_]\w*|[0-9@*])\}?"?/(?:[*?\[$/"']|\s|$)''')
CD=re.compile(r'''(?:^|[;&|\n(]|&&)\s*(?:cd|pushd)\s+\S''')
def rm_targets(cmd):
    for m in RM_OCC.finditer(cmd):
        args=[a for a in m.group(2).split() if not a.startswith(('-','2>','>'))]
        yield m.group(1),args,m.start()
def unguarded_var(cmd):
    for v,args,pos in rm_targets(cmd):
        for a in args:
            if '${' in a and ':?' in a: continue
            if VAR_SLASH.search(a): return a
def cd_rel_glob(cmd):
    for v,args,pos in rm_targets(cmd):
        if not CD.search(cmd[:pos+1]): continue
        for a in args:
            s=a.strip('"\'')
            if s.startswith(('/','~','$')): continue
            if re.search(r'[*?\[]',s): return a
def classify(cmd):
    r=[]
    for sc in scripts(cmd):
        if nan(sc) or "$'" in sc:
            h=hin(sc)
            if h: r.append('inline_shell:'+h); break
    if unguarded_var(cmd): r.append('unguarded_var')
    if cd_rel_glob(cmd): r.append('cd_rel_glob')
    return r
if __name__=='__main__':
    C=json.load(open('/tmp/autodeny-census/final/corpus.json'))
    conf=collections.Counter(); fpx=collections.defaultdict(list); fns=[]
    for o in C:
        k=classify(o['cmd']); pos=o['safety']
        key=k[0] if k else None
        if k and pos: conf[('TP',key)]+=1
        elif k: conf[('FP',key)]+=1; fpx[key].append(o)
        elif pos: conf['FN']+=1; fns.append(o)
    tp=sum(v for k,v in conf.items() if k[0]=='TP'); fp=sum(v for k,v in conf.items() if k[0]=='FP')
    print('TP',tp,'FP',fp,'FN',conf['FN'],'precision %.3f recall %.3f'%(tp/max(1,tp+fp),tp/64))
    for k,v in sorted(conf.items(),key=str): print(' ',k,v)
    for o in fns: print('FN',o['flagged'][:90].replace('\n',' '),'||',o['cmd'][:220].replace('\n',' | '))
    json.dump({k:[o['cmd'][:500] for o in v] for k,v in fpx.items()},open('/tmp/autodeny-census/final/fps2.json','w'),indent=0)
