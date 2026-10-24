# Cross-session effect the replay cannot see: every keepalive wake of a TEAMMATE ends in a Stop that sends the LEAD an
# idle_notification, which opens a lead turn when the lead is idle. Price those lead turns (proxy_med wake on the
# lead's context) and the lead rebuilds they would incidentally rescue. R2 = busy-scoped chain; also as-coded literal-ish.
import csv, re, os, collections, bisect
D='/tmp/lean-idle/idle-keepalive-wake/'
S,E=(float(x) for x in open(D+'window').read().split()); WK=7/((E-S)/86400)
rx_t=re.compile(rb'"teamName":"([^"]+)"'); rx_a=re.compile(rb'"agentName":"([^"]+)"')
team={}
for p in open(D+'review-mechanism/team_files.txt'):
    p=p.strip(); sid=os.path.basename(p)[:-6]
    with open(p,'rb') as fh:
        for i,line in enumerate(fh):
            m=rx_t.search(line); a=rx_a.search(line)
            if m and a: team[sid]=(m.group(1).decode(),a.group(1).decode()); break
            if i>400: break
G=list(csv.DictReader(open(D+'gaps.tsv'),delimiter='\t'))
bysid=collections.defaultdict(list)
for g in G: bysid[g['sid']].append(g)
sids=list(bysid)
def lead_of(tn):
    m=re.match(r'session-([0-9a-f]{8})',tn)
    if not m: return None
    c=[s for s in sids if s.startswith(m.group(1))]
    return c[0] if c else None
W,O=0.245,0.404
res=collections.Counter(); unresolved=0
for rn,r in (('low',0.0057),('high',0.0076)):
  for pol in ('R2','literal-first-wake'):
    cost=ben=n=0.0; nolead=0
    for g in G:
        tm=team.get(g['sid'])
        if not tm or tm[1]=='team-lead' or g['terminal']=='1': continue
        st,end=float(g['start']),float(g['end'])
        if pol=='R2':
            if g['busy_at_wake']!='1': continue
            ws=[]; t=st+3300
            while t<end: ws.append(t); t+=3330
        else:
            if g['first_ev_t'] and float(g['first_ev_t'])<min(end-5,st+3300): continue
            ws=[st+3300] if st+3300<end else []
        L=lead_of(tm[0])
        if not L: nolead+=len(ws); continue
        for t in ws:
            for lg in bysid[L]:
                ls,le=float(lg['start']),float(lg['end'])
                if ls<=t<le and t-ls>60:
                    n+=1; ctx=int(lg['ctx'])
                    cost+=((3+0.64)*ctx*r+1515*W+522*O)/1e6
                    if lg['rebuild']=='1' and le-t<3600: ben+=int(lg['saved_tok'])*(W-r)/1e6
                    break
    print('%-18s %-4s lead wakes/wk %5.1f cost %5.2f pp/wk incidental lead rescues %5.2f pp/wk net %+5.2f | teammate wakes w/o resolvable lead: %.1f/wk'%(pol,rn,n*WK,cost*WK,ben*WK,(ben-cost)*WK,nolead*WK))
