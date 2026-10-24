import os,re,sys,time
S,E=1791655200,1792864800
RID=re.compile(rb'"requestId":"([^"]+)"'); E5=re.compile(rb'"ephemeral_5m_input_tokens":(\d+),"ephemeral_1h_input_tokens":(\d+)')
TS=re.compile(rb'"timestamp":"(2026-10-(\d\d)T(\d\d))')
tot={}
t0=time.time(); nb=0; nf=0
for root in sys.argv[1:]:
    seen=set(); a5=a1=0
    for dp,dn,fn in os.walk(root,followlinks=True):
        if 'subagents' not in dp: continue
        for f in fn:
            if not f.endswith('.jsonl'): continue
            p=os.path.join(dp,f)
            try: st=os.stat(p)
            except OSError: continue
            if st.st_mtime<S: continue
            nf+=1
            with open(p,'rb') as fh:
                for line in fh:
                    if b'"usage"' not in line: continue
                    nb+=len(line)
                    m=E5.search(line)
                    if not m: continue
                    t=TS.search(line)
                    if t:
                        d=int(t.group(2)); h=int(t.group(3))
                        if d<10 or (d==10 and h<18) or d>24 or (d==24 and h>=18): continue
                    r=RID.search(line); k=r.group(1) if r else None
                    if k in seen: continue
                    seen.add(k); a5+=int(m.group(1)); a1+=int(m.group(2))
    tot[root]=(a5/1e6,a1/1e6)
    print(root,'subagent writes 5m %.1fM 1h %.1fM'%(a5/1e6,a1/1e6),flush=True)
print('files',nf,'GB',nb/1e9,'secs',time.time()-t0)
