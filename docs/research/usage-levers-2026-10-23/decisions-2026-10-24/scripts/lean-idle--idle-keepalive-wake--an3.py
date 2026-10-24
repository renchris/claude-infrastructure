import csv,collections
J={}
for a in ['next','next2','next3','next4']:
    for line in open(a+'.jobs'):
        fi,sid,tu,nm,w,js,je=line.rstrip('\n').split('\t')
        J[tu]=(nm,w,float(js) if js else None,float(je) if je else None)
# ops with job extra
O={}
for a in ['next','next2','next3','next4']:
    for line in open(a+'.op'):
        p=line.rstrip('\n').split('\t',5)
        if p[2]=='job': O[(p[1][:10])]=p
R=list(csv.DictReader(open('gaps.tsv'),delimiter='\t'))
# map gap end time to op extra
opx=collections.defaultdict(list)
for a in ['next','next2','next3','next4']:
    for line in open(a+'.op'):
        p=line.rstrip('\n').split('\t',5)
        if p[2]=='job': opx[int(float(p[1]))].append(p[4])
B=[(0,3000),(3000,3300),(3300,3600),(3600,6900),(6900,21600),(21600,10**9)]
for lo,hi in B:
    c=collections.Counter(); dl=[]
    for r in R:
        if r['terminal']=='1' or r['end_kind']!='job': continue
        d=float(r['dur'])
        if not lo<=d<hi: continue
        ex=(opx.get(int(r['end'])) or opx.get(int(r['end'])-1) or [''])[0]
        tu,_,st=ex.partition('|')
        j=J.get(tu)
        c[(j[0],j[1],st) if j else ('?','?',st)]+=1
        if j and j[2]: dl.append(round((j[3] or 0)-j[2]))
    dl.sort()
    print(lo,hi,dict(c.most_common(8)),'job-dur med',dl[len(dl)//2] if dl else None)
