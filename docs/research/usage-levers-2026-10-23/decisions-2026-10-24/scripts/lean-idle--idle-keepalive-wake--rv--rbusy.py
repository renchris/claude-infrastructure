import importlib.util,sys,json,collections
spec=importlib.util.spec_from_file_location('rrep','/tmp/lean-idle/idle-keepalive-wake/rv/rrep.py')
sys.argv=['rrep.py','/tmp/lean-idle/idle-keepalive-wake/rv','low']
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
G=m.G
B=[g for g in G if g['busy'] and not g['term'] and g['stop']+3300<g['end']]
print('busy gaps woken (nonterminal):',len(B),' of which busy only via a job with no notification found:',sum(g['busy_nn'] for g in B))
print('busy rebuild gaps:',sum(g['reb'] for g in B),' rebuild & busy only via no-notification job:',sum(g['reb'] and g['busy_nn'] for g in B))
c=collections.Counter(); 
for g in B:
    if g['reb']: c[g.get('endk','?')]+=1
# R2 excluding no-notification-only busy
for lab,sel in (('R2 all busy',lambda g:g['busy']),('R2 busy excl. jobs w/o notification',lambda g:g['busy'] and not g['busy_nn'])):
    for rn,r in (('low',0.0057),('high',0.0076)):
        print(m.line('%s med %s'%(lab,rn),m.run('chain',r,'med',sel=sel)))
# growth x later share of as-coded cost
p=m.PROF['med']
tot=gro=0
for g in G:
    if g['term'] or g['kill'] is not None or g['stop']+3300>=m.end_eff(g): continue
    c1=m.wake_cost(g,0.0057,p,0.57,0.245); c0=m.wake_cost(g,0.0057,p,0.57,0.245,later=False)
    tot+=c1; gro+=c1-c0
print('as-coded first wakes: growth x later share of cost %.0f%% (median later_reqs among them: %d)'%(100*gro/tot, sorted(g['later'] for g in G if not g['term'] and g['kill'] is None and g['stop']+3300<g['end'])[len([1 for g in G if not g['term'] and g['kill'] is None and g['stop']+3300<g['end']])//2]))
