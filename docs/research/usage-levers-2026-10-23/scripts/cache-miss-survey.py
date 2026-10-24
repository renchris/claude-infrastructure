import gzip,csv,collections,sys
csv.field_size_limit(10**9)
for a in ['next','next2','next3','next4']:
    c=collections.Counter(); t=collections.Counter(); n=0
    for r in csv.DictReader(gzip.open(f'/tmp/usage-audit/rows-{a}.tsv.gz','rt'),delimiter='\t'):
        n+=1
        if r['miss']: c[r['miss'][:120]]+=1; t[r['miss'][:120]]+=int(r['cc'])
    print(a,n,'rows with miss reason',sum(c.values()))
    for k,v in c.most_common(15): print('  ',v,t[k],k)
