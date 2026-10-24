import csv,collections
R=list(csv.DictReader(open('gaps.tsv'),delimiter='\t'))
nt=[r for r in R if r['terminal']=='0']
B=[(0,3000),(3000,3300),(3300,3600),(3600,6900),(6900,21600),(21600,10**9)]
for lo,hi in B:
    g=[r for r in nt if lo<=float(r['dur'])<hi]
    c=collections.Counter(r['end_kind'] for r in g)
    print(lo,hi,len(g),dict(c.most_common()), 'goal',sum(r['goal']=='1' for r in g),'busy@55',sum(r['busy_at_wake']=='1' for r in g),'watch@55',sum(r['watcher_at_wake']=='1' for r in g))
