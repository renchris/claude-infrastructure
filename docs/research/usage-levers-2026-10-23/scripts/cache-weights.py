import pickle,collections,re
R=pickle.load(open('/tmp/usage-audit/cache-rows.pkl','rb'))
def rel(p): return p.split('/projects/',1)[1]
seen=set(); U=[]
for r in R:
    k=(rel(r['file']),r['ts'],r['cc'])
    if k in seen: continue
    seen.add(k); U.append(r)
S=lambda k,f=lambda r:True: sum(r[k] for r in U if f(r))
w={'in':S('in')*1,'cc5m':S('cc5m')*1.25,'cc1h':S('cc1h')*2,'cr':S('cr')*0.1,'out':S('out')*5}
T=sum(w.values())
print('API-price-weighted shares (input=1, 5m write=1.25, 1h write=2, read=0.1, output=5):',{k:f"{v/T:.1%}" for k,v in w.items()})
b=lambda r:r['kind']=='bust'
wb=S('cc5m',b)*1.25+S('cc1h',b)*2
print(f"bust cc weighted share of total = {wb/T:.1%}; main-idle>1h={ (S('cc1h',lambda r:b(r) and not r['sub'] and r['gap']>3600)*2)/T:.1%}; sub idle>5m={(S('cc5m',lambda r:b(r) and r['sub'] and r['gap']>300)*1.25)/T:.1%}")
