import csv,collections,os
ALIVE=set(open('alive_sids.txt').read().split())
R=list(csv.DictReader(open('gaps.tsv'),delimiter='\t'))
A=['next','next2','next3','next4']
C={a:collections.Counter() for a in A+['all']}
for g in R:
    d=float(g['dur']); a=g['acct']
    for k in (a,'all'):
        c=C[k]
        if g['terminal']=='0':
            if d>=3300: c['gaps>=55m']+=1
            if d>=3600 and g['rebuild']=='1': c['rebuild>60m']+=1; c['rebuild_Mtok']+=int(g['saved_tok'])/1e6
            if d>=3600 and g['rebuild']=='0': c['>60m_no_rebuild']+=1
            if 3300<=d<3600: c['55-60m']+=1
            if 3600<=d<6900: c['60-115m']+=1
            if d>=6900: c['>=115m']+=1; c['chain_wakes>=115m']+=int(d//3330)
            if d>=10800: c['>=3h']+=1
            if d>=3300 and g['busy_at_wake']=='1': c['busy@55m']+=1
            if d>=3600 and g['rebuild']=='1' and g['busy_at_wake']=='1': c['rebuild_busy']+=1
            if d>=3300 and g['goal']=='1': c['goal>=55m']+=1
            if d>=3300 and g['exit_in_gap']=='1': c['exit_mid_gap']+=1
        else:
            c['terminal']+=1
            if g['end_kind']=='exit' and d>=3300: c['term_exit>=55m']+=1; c['term_exit_chain_wakes']+=int(d//3330)
            if g['end_kind']=='censored' and g['sid'] in ALIVE and d>=3300: c['term_alive>=55m']+=1; c['term_alive_chain_wakes']+=int(d//3330)
            if g['end_kind']=='censored' and g['sid'] not in ALIVE and g['closed']=='0' and d>=3300: c['term_dead_unknown>=55m']+=1; c['term_dead_unknown_wakes_to_E']+=int(d//3330)
keys=['gaps>=55m','55-60m','60-115m','>=115m','>=3h','rebuild>60m','rebuild_Mtok','>60m_no_rebuild','busy@55m','rebuild_busy','goal>=55m','exit_mid_gap','chain_wakes>=115m','terminal','term_exit>=55m','term_exit_chain_wakes','term_alive>=55m','term_alive_chain_wakes','term_dead_unknown>=55m','term_dead_unknown_wakes_to_E']
print('%-30s'%'14-day counts'+''.join('%9s'%a for a in A+['all']))
for k in keys: print('%-30s'%k+''.join(('%9.1f' if k=='rebuild_Mtok' else '%9d')%C[a][k] for a in A+['all']))
