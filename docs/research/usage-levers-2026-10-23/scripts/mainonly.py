import pickle,sys,collections
sys.argv=[sys.argv[0]]+sys.argv[1:]
exec(open('/tmp/usage-audit/roll.py').read().split('T=0;')[0])
exec(open('/tmp/usage-audit/final2.py').read().split('accts=sys.argv')[0].split('W=lambda')[1].join(['W=lambda',''])) if False else None
src=open('/tmp/usage-audit/final2.py').read(); g_src=src[src.index('def grp'):src.index('accts=')]
exec(g_src)
T=0; A=collections.defaultdict(lambda:[0,0.0,0,0.0])
for a in ['next','next2','next3','next4']:
  for r in pickle.load(open(f'/tmp/usage-audit/{a}.v2.pkl','rb'))['reqs']:
    w=W(r); T+=w
    k=fam(r[6]) or grp(r[6])
    if r[7]=='main': A[k][0]+=1; A[k][1]+=w; A[k][2]+=r[1]
    else: A[k][3]+=w
print('group | main req | main weight% | main mean ctx | subagent weight% launched from these turns')
for k,(n,w,c,sw) in sorted(A.items(), key=lambda x:-(x[1][1]+x[1][3]))[:16]:
  print(f'{k} | {n} | {100*w/T:.1f} | {c/max(n,1)/1e3:.0f}k | {100*sw/T:.1f}')
