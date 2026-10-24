import csv,collections,sys
R=list(csv.DictReader(open('gaps.tsv'),delimiter='\t'))
nt=[r for r in R if r['terminal']=='0']
print('nonterminal gaps',len(nt),'terminal',len(R)-len(nt))
B=[(0,600),(600,1800),(1800,3000),(3000,3300),(3300,3500),(3500,3600),(3600,3700),(3700,3900),(3900,4500),(4500,6900),(6900,10800),(10800,21600),(21600,86400),(86400,10**9)]
for lo,hi in B:
    g=[r for r in nt if lo<=float(r['dur'])<hi]
    rb=[r for r in g if r['rebuild']=='1']
    aw=[r for r in g if r['away_t']]
    ex=[r for r in g if r['exit_in_gap']=='1']
    print('%6d-%6d n=%5d rebuild=%5d (%.0f%%) saved_Mtok=%.1f away=%d exit_in_gap=%d'%(lo,hi,len(g),len(rb),100*len(rb)/max(1,len(g)),sum(int(r['saved_tok']) for r in rb)/1e6,len(aw),len(ex)))
