import re,json,sys
def strip(src):
    out=[];i=0;n=len(src)
    while i<n:
        c=src[i];d=src[i+1] if i+1<n else ''
        if c=='/' and d=='/':
            while i<n and src[i]!='\n': i+=1
            continue
        if c=='/' and d=='*':
            i+=2
            while i<n-1 and not(src[i]=='*' and src[i+1]=='/'): i+=1
            i+=2; continue
        if c in '"\'':
            q=c;i+=1
            while i<n:
                if src[i]=='\\': i+=2; continue
                if src[i]==q: i+=1; break
                i+=1
            out.append(' "S" '); continue
        if c=='`':
            i+=1
            while i<n:
                if src[i]=='\\': i+=2; continue
                if src[i]=='$' and i+1<n and src[i+1]=='{':
                    i+=2; br=1; e=[]
                    while i<n and br>0:
                        if src[i]=='{': br+=1
                        elif src[i]=='}': br-=1
                        if br>0: e.append(src[i])
                        i+=1
                    out.append(' INTERP{'+''.join(e)+'} '); continue
                if src[i]=='`': i+=1; break
                i+=1
            out.append(' `T` '); continue
        out.append(c); i+=1
    return ''.join(out)

def matched(s,start,op='(',cl=')'):
    d=0;i=start
    while i<len(s):
        if s[i]==op: d+=1
        elif s[i]==cl:
            d-=1
            if d==0: return s[start:i+1],i
        i+=1
    return s[start:],len(s)-1

rows=[]
for p in [l.strip() for l in open('uniq-paths.txt') if l.strip()]:
    src=open(p,encoding='utf8',errors='replace').read(); s=strip(src)
    # result vars
    names=set()
    for m in re.finditer(r'(?:const|let|var)\s*(?:\{([^}]*)\}|\[([^\]]*)\]|([A-Za-z_$][\w$]*))\s*=\s*await\s+(agent|parallel|pipeline|Promise\.all)', s):
        g=m.group(1) or m.group(2) or m.group(3) or ''
        for t in g.split(','):
            nm=re.sub(r'[^\w$]','',t.split(':')[-1]).strip()
            if nm: names.add(nm)
    # parallel/pipeline argument shapes
    shapes=[]
    for m in re.finditer(r'\b(parallel|pipeline)\s*\(', s):
        arg,_=matched(s,m.end()-1)
        inner=arg[1:-1]
        kind='literal-array' if inner.lstrip().startswith('[') else ('map-over-var' if '.map(' in inner[:200] else 'other')
        src_var=None
        mm=re.match(r'\s*([A-Za-z_$][\w$]*)\s*\.\s*map\s*\(', inner)
        if mm: src_var=mm.group(1); kind='map-over-'+('RESULT' if src_var in names else 'literal')
        shapes.append(kind)
    # agent() inside a map over a RESULT var
    dyn_fanout=False
    for nm in names:
        for m in re.finditer(re.escape(nm)+r'\s*\.\s*(map|flatMap|filter)\s*\(', s):
            body,_=matched(s,m.end()-1)
            if re.search(r'\bagent\s*\(', body): dyn_fanout=True
    # agent() inside an if / ternary
    cond=False
    for m in re.finditer(r'(^|[^\w.$])if\s*\(', s):
        # find the block after the condition
        op=s.index('(',m.end()-1)
        _,close=matched(s,op)
        rest=s[close+1:close+4000]
        rs=rest.lstrip()
        if rs.startswith('{'):
            body,_=matched(s,close+1+(len(rest)-len(rs)),'{','}')
            if re.search(r'\bagent\s*\(',body): cond=True
    # ternary that selects between agent prompts
    rows.append(dict(file=p.split('/')[-1], path=p, resultVars=len(names),
        parallelShapes=shapes, dynFanout=dyn_fanout, condAgent=cond,
        interpFromResult=sum(1 for e in re.findall(r'INTERP\{([^}]*)\}', s)
                             if any(re.search(r'\b'+re.escape(nm)+r'\b',e) for nm in names)),
        stages=len(re.findall(r'\bawait\s+(?:parallel|pipeline)\s*\(', s)),
        agentCalls=len(re.findall(r'\bagent\s*\(', s))))
json.dump(rows,open('dyn2.json','w'),indent=1)
import collections
allsh=collections.Counter(k for r in rows for k in r['parallelShapes'])
print('n=',len(rows))
print('parallel/pipeline arg shapes:',dict(allsh))
print('files with agent() inside a .map over a RESULT var (runtime-derived FAN-OUT WIDTH):', sum(1 for r in rows if r['dynFanout']))
print('files with agent() inside an if-block (conditional spawn):', sum(1 for r in rows if r['condAgent']))
print('files where a later prompt INTERPOLATES an earlier result:', sum(1 for r in rows if r['interpFromResult']>0))
print('files with 0 result vars at all (pure blind fan-out):', sum(1 for r in rows if r['resultVars']==0))
u=[r for r in rows if r['dynFanout'] or r['condAgent']]
print('UNION dynFanout|condAgent =',len(u), [r['file'] for r in u])
