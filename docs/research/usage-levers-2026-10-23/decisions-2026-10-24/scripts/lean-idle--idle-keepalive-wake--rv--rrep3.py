import importlib.util,sys,json
for term in ('low','high'):
    spec=importlib.util.spec_from_file_location('rrep','/tmp/lean-idle/idle-keepalive-wake/rv/rrep.py')
    sys.argv=['rrep.py','/tmp/lean-idle/idle-keepalive-wake/rv',term]
    m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    print('TERM',term,'AS CODED with conditional chain survival s=0.89 (P(kill2|no kill1)=0.11, n=184)')
    for pn in ('min','med','mean'):
        for rn,r in (('low',0.0057),('high',0.0076)):
            print(m.line('  s=0.89 %s %s'%(pn,rn),m.run('literal',r,pn,s_chain=0.89)))
    for rn,r in (('low',0.0057),('high',0.0076)):
        print(m.line('  s=0.89 med %s W1h=0.3325'%rn,m.run('literal',r,'med',s_chain=0.89,W=0.3325)))
