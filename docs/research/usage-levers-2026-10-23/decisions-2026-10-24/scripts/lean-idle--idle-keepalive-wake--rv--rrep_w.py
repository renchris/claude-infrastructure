import importlib.util,sys
spec=importlib.util.spec_from_file_location('rrep','/tmp/lean-idle/idle-keepalive-wake/rv/rrep.py')
sys.argv=['rrep.py','/tmp/lean-idle/idle-keepalive-wake/rv','low']
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
busy=lambda g:g['busy']
print('1h-write weight sensitivity (W=0.3325 if 1h:5m follows list 2.0:1.25 and fit4 blend is 30% 1h / 70% 5m by tokens)')
for W in (0.245,0.3325):
  for pol,sel,lab in (('literal',None,'AS CODED'),('chain',busy,'R2 busy chain')):
    for pn in ('min','med','mean'):
      for rn,r in (('low',0.0057),('high',0.0076)):
        print(m.line('W=%.4f %s %s %s'%(W,lab,pn,rn), m.run(pol,r,pn,W=W,sel=sel)))
print()
print('chain survival sensitivity for AS CODED (s = P(no transcript write in the 55 min after a wake turn))')
for s in (0.36,0.43,0.6,0.8,1.0):
  for rn,r in (('low',0.0057),('high',0.0076)):
    print(m.line('s=%.2f AS CODED med %s'%(s,rn), m.run('literal',r,'med',s_chain=s)))
