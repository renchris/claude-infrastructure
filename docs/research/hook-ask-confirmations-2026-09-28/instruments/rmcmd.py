import json,re,collections
asks=json.load(open('asks.json'))
want={}
for k,v in asks.items():
    if v['hook']=='validate-bash.sh' and v['reason'].startswith('rm -r on non-build'):
        want[k.split('|')[0]]=v
files=set(v['file'] for v in want.values())
cmds={}
for f in files:
    for line in open(f,errors='replace'):
        if '"tool_use"' not in line: continue
        try: r=json.loads(line)
        except Exception: continue
        c=(r.get('message') or {}).get('content')
        if isinstance(c,list):
            for b in c:
                if isinstance(b,dict) and b.get('type')=='tool_use' and b.get('id') in want:
                    cmds[b['id']]=(b.get('input') or {}).get('command','')
print('rm asks',len(want),'cmds found',len(cmds))
cls=collections.Counter(); ex=collections.defaultdict(list)
for tid,v in want.items():
    m=re.match(r"rm -r on non-build-artifact target: '(.*)'\. Verify",v['reason'],re.S)
    t=m.group(1) if m else ''
    cmd=cmds.get(tid,'')
    if t.startswith('$') or t.startswith('"$'):
        name=re.match(r'"?\$\{?([A-Za-z_][A-Za-z0-9_]*)',t)
        n=name.group(1) if name else None
        bind=re.search(r'(^|[\s;&|(])'+re.escape(n or 'ZZZ')+r'=("?)([^\s;&|]*)',cmd) if n else None
        val=bind.group(3) if bind else ''
        if 'mktemp' in val: k='var=mktemp'
        elif val.startswith('/tmp') or val.startswith('/private/tmp') or val.startswith('"/tmp') or 'TMPDIR' in val: k='var=/tmp-ish'
        elif bind: k='var=other-literal'
        else: k='var-unbound-in-cmd'
    elif t.startswith('/'):
        k='abs-tmp' if re.match(r'/(private/)?tmp|/var/folders',t) else 'abs-other'
    else:
        k='rel-after-cd-tmp' if re.search(r'cd\s+"?(/private)?/tmp|cd\s+"?\$\(mktemp|cd\s+"?\$(TMPDIR|T|D|TMP)\b',cmd) else 'rel-other'
    cls[(k,v["outcome"])]+=1; ex[k].append(cmd[:160].replace("\n"," "))
    if k=="var=mktemp": cls[("mktemp-after-fix" if (v["ts"] or "")>="2026-09-10T21:03" else "mktemp-before-fix")]+=1
for x in sorted(cls.items(), key=str): print(x)
json.dump(ex,open('rm_ex.json','w'))
