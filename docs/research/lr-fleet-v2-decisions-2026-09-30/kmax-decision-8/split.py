import json, datetime as dt, os
exec(open('/tmp/kmaxq/count.py').read().split("print(f\"{'ts'")[0])
ep={}
for f in F:
    if f['top']:
        e=None
        for line in open(f['path']):
            try:o=json.loads(line)
            except: continue
            if o.get('entrypoint'): e=o['entrypoint']; break
        ep[f['path']]=e
n=0; walls=[]
for r in rows:
    kw=r['k_work']; k=r['k']
    if kw is None or kw<8: continue
    T=P(r['ts']); a=r['acct']
    hit=[f for f in F if f['acct']==a and any(T-600<t<=T for t in f['ts'])]
    cli=sum(1 for f in hit if f['top'] and ep[f['path']]!='sdk-cli')
    sdk=sum(1 for f in hit if f['top'] and ep[f['path']]=='sdk-cli')
    sub=sum(1 for f in hit if not f['top'])
    wfs=sum(1 for f in hit if not f['top'] and '/workflows/' in f['path'])
    a1=min(kw,k); a2=min(cli+sdk,k); a3=min(cli,k); a4=min(cli,k)+sub-wfs
    print(r['ts'][11:19],a,'kw',kw,'k',k,'| cli',cli,'sdk',sdk,'sub',sub,'(wf',wfs,') | kw_cap_k',a1,'top_capk',a2,'cli_capk',a3,'cli+agentsub',a4)
    walls.append((a1>=8,a2>=8,a3>=8,a4>=8))
print('rows',len(walls),'still-wall counts [kw capped at k, recon top capped at k, interactive top capped at k, interactive+Agent-tool subs (no workflow)]:',[sum(w[i] for w in walls) for i in range(4)])
