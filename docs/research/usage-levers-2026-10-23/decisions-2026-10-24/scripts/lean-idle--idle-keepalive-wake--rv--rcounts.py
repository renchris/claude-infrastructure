import csv,collections
A=['next','next2','next3','next4']
R=[r for r in csv.DictReader(open('rgaps.tsv'),delimiter='\t')]
C={a:collections.Counter() for a in A+['all']}
for g in R:
    d=float(g['dur']); a=g['acct']
    for k in (a,'all'):
        c=C[k]
        if g['term']=='0':
            c['gaps']+=1
            if d>=3300: c['gaps>=55m']+=1
            if 3300<=d<3600: c['55-60m']+=1
            if 3600<=d<6900: c['60-115m']+=1
            if d>=6900: c['>=115m']+=1
            if d>=3600 and g['rebuild']=='1': c['rebuild>60m']+=1; c['rebuild_Mtok']+=int(g['saved'])/1e6
            if d>=3600 and g['rebuild']=='0': c['>60m_no_rebuild']+=1
            if d<3600 and g['rebuild']=='1': c['rebuild<60m']+=1; c['rebuild<60m_Mtok']+=int(g['saved'])/1e6
            if d>=3300:
                kill=g['kill_t']!=''
                c['killed>=55m']+=kill; c['killed_by_away>=55m']+=(kill and g['kill_lab']=='sys:away_summary')
                c['busy@55m']+=g['busy']=='1'; c['watch@55m']+=g['watch']=='1'
            if d>=3600 and g['rebuild']=='1' and g['busy']=='1': c['rebuild_busy']+=1
            if d>=3300 and g['exit']: c['exit_mid_gap']+=1
        else:
            c['terminal']+=1
            if d>=3300: c['term>=55m']+=1
fmt=lambda k,v: '%9.1f'%v if 'Mtok' in k else '%9d'%v
keys=['gaps','gaps>=55m','55-60m','60-115m','>=115m','rebuild>60m','rebuild_Mtok','>60m_no_rebuild','rebuild<60m','rebuild<60m_Mtok','killed>=55m','killed_by_away>=55m','busy@55m','watch@55m','rebuild_busy','exit_mid_gap','terminal','term>=55m']
print('%-24s'%''+''.join('%9s'%a for a in A+['all']))
for k in keys: print('%-24s'%k+''.join(fmt(k,C[a][k]) for a in A+['all']))
W,r=0.245,0.0057
print('rebuild>60m pp/week at W-r(low):', round(C['all']['rebuild_Mtok']*(W-r)/2,2), 'high:', round(C['all']['rebuild_Mtok']*(W-0.0076)/2,2))
