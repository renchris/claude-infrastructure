import csv,collections
agg=collections.defaultdict(lambda:[0,0,0,0,0,0])
for r in csv.DictReader(open('/tmp/usage-audit/requests.csv')):
    i,cr,cc,o=int(r['inp']),int(r['cr']),int(r['cc']),int(r['outp'])
    c=i+cr+cc; w=i+0.1*cr+2*cc+5*o
    a=agg[r['acct']]; big=c>150000
    a[0]+=1; a[1]+=big; a[2]+=c; a[3]+=c*big; a[4]+=w; a[5]+=w*big
for k,a in sorted(agg.items()):
    print(k,'reqs=%d req>150k=%.0f%% rawtok>150k=%.0f%% priceweighted>150k=%.0f%%'%(a[0],100*a[1]/a[0],100*a[3]/a[2],100*a[5]/a[4]))
