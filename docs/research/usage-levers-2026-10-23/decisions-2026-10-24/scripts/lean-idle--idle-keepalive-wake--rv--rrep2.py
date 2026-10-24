import importlib.util,sys,json
spec=importlib.util.spec_from_file_location('rrep','/tmp/lean-idle/idle-keepalive-wake/rv/rrep.py')
sys.argv=['rrep.py','/tmp/lean-idle/idle-keepalive-wake/rv','low']
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
m.G[:]=json.load(open('/tmp/lean-idle/idle-keepalive-wake/rv/G2.json'))
for lab,sel in (('R2 busy (scan as in brief: TaskStop/denied jobs run to session end)',lambda g:g['busy']),
                ('R2 busy2 (job ends at notification/TaskStop; denied launches dropped)',lambda g:g['busy2']),
                ('R2 busy2_ub (unknown-end jobs alive to session end)',lambda g:g['busy2_ub']),
                ('R4 busy2 and no model watcher armed',lambda g:g['busy2'] and not g['watch2'])):
    print(lab)
    for pn in ('min','med','mean'):
        for rn,r in (('low',0.0057),('high',0.0076)):
            print(m.line('  %s %s'%(pn,rn),m.run('chain',r,pn,sel=sel)))
    for rn,r in (('low',0.0057),('high',0.0076)):
        print(m.line('  med %s W1h=0.3325'%rn,m.run('chain',r,'med',sel=sel,W=0.3325)))
