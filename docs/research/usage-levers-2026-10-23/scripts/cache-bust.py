import gzip,csv,collections,sys,json,pickle
from datetime import datetime
csv.field_size_limit(10**9)
def T(s): return datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
ALL=[]
for a in ['next','next2','next3','next4']:
    files=collections.defaultdict(list)
    for r in csv.DictReader(gzip.open(f'/tmp/usage-audit/rows-{a}.tsv.gz','rt'),delimiter='\t'):
        for k in ('in','cc','cr','out','cc1h','cc5m','sub','side'): r[k]=int(r[k])
        r['t']=T(r['ts']); files[r['file']].append(r)
    for f,rs in files.items():
        rs.sort(key=lambda r:r['t'])
        prev=None
        for i,r in enumerate(rs):
            r['idx']=i
            if prev is None:
                r['kind']='first'; r['gap']=None; r['lost']=0
            else:
                exp=prev['cr']+prev['cc']+prev['in']
                r['gap']=r['t']-prev['t']
                lost=exp-r['cr']
                r['lost']=lost
                tot=r['cr']+r['cc']+r['in']
                r['shrink']= tot < 0.7*exp
                if lost>20000 and r['cc']>20000:
                    r['kind']='bust'
                else: r['kind']='normal'
                r['pmodel']=prev['model']; r['peff']=prev['effort']; r['pver']=prev['ver']
            prev=r
            ALL.append(r)
pickle.dump(ALL,open('/tmp/usage-audit/cache-rows.pkl','wb'))
print(len(ALL))
