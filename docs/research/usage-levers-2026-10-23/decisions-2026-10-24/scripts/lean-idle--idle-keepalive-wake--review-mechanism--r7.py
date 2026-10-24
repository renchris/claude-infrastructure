# Which long gaps belong to agent-team TEAMMATES (agentName != team-lead)? A woken teammate's Stop sends the lead an
# idle notification, i.e. a lead wake the replay never charges.
import csv, json, re, collections, os
D='/tmp/lean-idle/idle-keepalive-wake/'
role={}
rx=re.compile(rb'"agentName":"([^"]+)"')
for p in open(D+'review-mechanism/team_files.txt'):
    p=p.strip(); sid=os.path.basename(p)[:-6]
    with open(p,'rb') as fh:
        for i,line in enumerate(fh):
            m=rx.search(line)
            if m: role[sid]=m.group(1).decode(); break
            if i>400: break
G=list(csv.DictReader(open(D+'gaps.tsv'),delimiter='\t'))
c=collections.Counter()
for g in G:
    d=float(g['dur'])
    if d<3300: continue
    r=role.get(g['sid'])
    k='teammate' if r and r!='team-lead' else ('lead' if r=='team-lead' else 'solo')
    c[(k,'terminal' if g['terminal']=='1' else 'mid')]+=1
    if g['terminal']=='0' and g['busy_at_wake']=='1': c[(k,'R2-woken')]+=1
    if g['terminal']=='0' and not (g['first_ev_t'] and float(g['first_ev_t'])<min(float(g['end'])-5,float(g['start'])+3300)): c[(k,'as-coded-timer-survives')]+=1
print('roles seen',collections.Counter('teammate' if v!='team-lead' else 'lead' for v in role.values()))
for k in sorted(c): print(k,c[k])
