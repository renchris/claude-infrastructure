import pickle,collections,os,sys
for a in sys.argv[1:]:
  D=pickle.load(open(f'/tmp/usage-audit/{a}.pkl','rb'))
  miss=[r for r in D['reqs'] if r[6]=='subagent:parent-not-in-window']
  sids=collections.Counter(r[8] for r in miss)
  ins=sum(1 for s in sids if s in D['sess'])
  paths=collections.Counter('/'.join(r[13].split('/projects/')[1].split('/')[2:-1]) for r in miss)
  ag=collections.Counter(r[9] for r in miss)
  print(a,'parents',len(sids),'of which main file seen',ins,'paths',paths.most_common(4),'agents',ag.most_common(5))
  print('  example',miss[0][13] if miss else None)
