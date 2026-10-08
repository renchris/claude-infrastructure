import re,sys,json
py=re.compile(r'os\.environ\.get\(\s*"([A-Z_][A-Z0-9_]*)"\s*,\s*"([^"]*)"\s*\)')
start=re.compile(r'\$\{([A-Z_][A-Z0-9_]*):-')
def pairs(s):
    out={}
    for m in start.finditer(s):
        i=m.end(); d=1; j=i
        while j<len(s) and d>0:
            if s[j]=='{': d+=1
            elif s[j]=='}': d-=1
            j+=1
        out.setdefault(m.group(1), [])
        v=s[i:j-1]
        if v not in out[m.group(1)]: out[m.group(1)].append(v)
    for m in py.finditer(s):
        out.setdefault(m.group(1), [])
        if m.group(2) not in out[m.group(1)]: out[m.group(1)].append(m.group(2))
    return out
if __name__=="__main__":
    res={}
    for f in sys.argv[1:]:
        res[f]=pairs(open(f).read())
    json.dump(res, sys.stdout, indent=1)
