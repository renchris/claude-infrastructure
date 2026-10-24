import csv,collections
target={'next':69,'next2':62,'next3':66,'next4':58}
R=[(r['acct'],int(r['inp']),int(r['cr']),int(r['cc']),int(r['outp'])) for r in csv.DictReader(open('/tmp/usage-audit/requests.csv'))]
for wcr in [0.1,0.125,0.15,0.2]:
  for wcc in [1.25,2.0]:
    for wo in [5.0]:
      agg=collections.defaultdict(lambda:[0,0])
      for a,i,cr,cc,o in R:
        w=i+wcr*cr+wcc*cc+wo*o; agg[a][0]+=w; agg[a][1]+=w*((i+cr+cc)>150000)
      s={a:100*v[1]/v[0] for a,v in agg.items()}
      err=sum(abs(s[a]-target[a]) for a in target)/4
      print(wcr,wcc,wo,' '.join('%s=%.0f'%(a,s[a]) for a in sorted(s)),'MAE=%.1f'%err)
