import os,json,glob,time,sys
from collections import defaultdict
NOW=time.time(); WIN=7*86400
CFG={'next':os.path.expanduser('~/.claude'),'next2':os.path.expanduser('~/.claude-secondary'),
     'next3':os.path.expanduser('~/.claude-tertiary'),'next4':os.path.expanduser('~/.claude-quaternary')}
# list API prices $/Mtok: in, out, cache_write(1.25x in), cache_read
PRICE={'claude-opus-5':(5,25,6.25,0.5),'claude-opus-4-8':(5,25,6.25,0.5),
       'claude-fable-5-1':(10,50,12.5,0.25),'claude-fable-5':(10,50,12.5,1.0),
       'claude-sonnet-5':(2,10,2.5,0.2),'claude-haiku-4-5':(1,5,1.25,0.1)}
def price(m):
    for k,v in PRICE.items():
        if m.startswith(k): return v
    return None
res=defaultdict(lambda: defaultdict(float)); seen=set(); files=0; recs=0
for acct,root in CFG.items():
    pdir=os.path.join(root,'projects')
    if not os.path.isdir(pdir): continue
    for fp in glob.glob(pdir+'/**/*.jsonl',recursive=True):
        try:
            if os.path.getmtime(fp)<NOW-WIN: continue
        except OSError: continue
        files+=1
        try: fh=open(fp,errors='replace')
        except OSError: continue
        with fh:
            for line in fh:
                if '"usage"' not in line: continue
                try: d=json.loads(line)
                except Exception: continue
                msg=d.get('message') or {}
                u=msg.get('usage') or d.get('usage')
                if not isinstance(u,dict): continue
                ts=d.get('timestamp','')
                if ts:
                    try:
                        e=time.mktime(time.strptime(ts[:19],'%Y-%m-%dT%H:%M:%S'))
                        if e<NOW-WIN-86400: continue
                    except Exception: pass
                mid=msg.get('id') or d.get('requestId')
                if mid:
                    if mid in seen: continue
                    seen.add(mid)
                model=msg.get('model') or d.get('model') or 'unknown'
                recs+=1
                r=res[(acct,model)]
                r['in']+=u.get('input_tokens',0) or 0
                r['out']+=u.get('output_tokens',0) or 0
                r['cw']+=u.get('cache_creation_input_tokens',0) or 0
                r['cr']+=u.get('cache_read_input_tokens',0) or 0
                r['n']+=1
print(f"files_scanned={files} usage_records_deduped={recs} unique_msg_ids={len(seen)}")
tot=defaultdict(float)
print(f"{'acct':<7}{'model':<22}{'msgs':>7}{'in M':>9}{'out M':>9}{'cwrite M':>10}{'cread M':>10}{'$API':>10}")
for (a,m),r in sorted(res.items(), key=lambda x:-x[1]['out']):
    p=price(m)
    if not p:
        if r['n']>5: print(f"  (unpriced model {m}: {r['n']} msgs, {r['out']/1e6:.2f}M out)")
        continue
    d=r['in']/1e6*p[0]+r['out']/1e6*p[1]+r['cw']/1e6*p[2]+r['cr']/1e6*p[3]
    tot[a]+=d; tot['ALL']+=d
    tot[a+':out']+=r['out']
    if r['n']>20:
        print(f"{a:<7}{m:<22}{int(r['n']):>7}{r['in']/1e6:>9.2f}{r['out']/1e6:>9.2f}{r['cw']/1e6:>10.2f}{r['cr']/1e6:>10.1f}{d:>10.0f}")
print()
for a in ['next','next2','next3','next4']:
    print(f"{a}: ${tot[a]:,.0f} API-equivalent in last 7d   (output {tot[a+':out']/1e6:.1f}M tok)")
print(f"FLEET 7d: ${tot['ALL']:,.0f}")
