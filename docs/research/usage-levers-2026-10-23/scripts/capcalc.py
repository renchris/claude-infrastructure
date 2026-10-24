import pickle
W=lambda r: r[2]+1.25*r[3]+0.1*r[4]+5*r[5]
T=0; ex={200:0,250:0}; wk=0; wn=0; wc=0
for a in ['next','next2','next3','next4']:
  R=pickle.load(open(f'/tmp/usage-audit/{a}.v2.pkl','rb'))['reqs']
  for r in R:
    T+=W(r)
    if r[7]=='main':
      for c in ex: ex[c]+=0.1*max(0,r[1]-c*1000)
for c,v in ex.items(): print(f'main-thread cache-read weight above {c}k ctx: {v/1e9:.3f}B = {100*v/T:.1f}% of total est-weight')
