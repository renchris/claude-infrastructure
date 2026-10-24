import pickle,collections,math,re
src=open('/tmp/usage-audit/final2.py').read(); exec(src[src.index('W=lambda'):src.index('accts=')])
def corr(x,y):
  n=len(x); mx=sum(x)/n; my=sum(y)/n
  sx=math.sqrt(sum((a-mx)**2 for a in x)); sy=math.sqrt(sum((b-my)**2 for b in y))
  return sum((a-mx)*(b-my) for a,b in zip(x,y))/(sx*sy)
def rank(v):
  o=sorted(range(len(v)),key=lambda i:v[i]); r=[0]*len(v)
  for k,i in enumerate(o): r[i]=k
  return r
for a in ['next','next2','next3','next4']:
  R=pickle.load(open(f'/tmp/usage-audit/{a}.v2.pkl','rb'))['reqs']
  sp={}
  for r in R:
    f,l=sp.get(r[8],(r[0],r[0])); sp[r[8]]=(min(f,r[0]),max(l,r[0]))
  M=[r for r in R if r[7]=='main']
  age=[(r[0]-sp[r[8]][0])/3600 for r in M]; ctx=[r[1] for r in M]
  out=[]
  for lab,sel in (('8h+',lambda r: sp[r[8]][1]-sp[r[8]][0]>=8*3600),('<8h',lambda r: sp[r[8]][1]-sp[r[8]][0]<8*3600)):
    X=[r for r in R if sel(r)]; TW=sum(W(r) for r in X)
    mw=sum(W(r) for r in X if grp(r[6])[0]=='M'); dw=sum(W(r) for r in X if grp(r[6])[0]=='D'); hw=sum(W(r) for r in X if grp(r[6])[0]=='H')
    sch=sum(W(r) for r in X if 'scheduled' in grp(r[6]))
    Xm=[r for r in X if r[7]=='main']
    out.append(f'{lab}: machine {100*mw/TW:.0f}% / dispatched {100*dw/TW:.0f}% / operator {100*hw/TW:.0f}% of weight; scheduled {100*sch/TW:.1f}%; subagent share {100*sum(W(r) for r in X if r[7]=="sub")/TW:.0f}%; weight/main-req {TW/max(len(Xm),1)/1e3:.0f}k')
  print(f'{a}: main reqs {len(M)}; pearson(age,ctx)={corr(age,ctx):.2f} spearman={corr(rank(age),rank(ctx)):.2f}\n  '+'\n  '.join(out))
