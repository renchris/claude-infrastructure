import importlib.util, sys, os
spec=importlib.util.spec_from_file_location("sim","/tmp/lean-idle/idle-keepalive-wake/sim.py")
sys.argv=["sim.py","/tmp/lean-idle/idle-keepalive-wake"]
sim=importlib.util.module_from_spec(spec); spec.loader.exec_module(sim)
A=sim.ACCTS
def line(lab,res):
    T=res["total"]
    return "%-52s | %s | %6.2f | wakes %6.1f rescued %5.1f cost %5.2f ben %5.2f" % (lab," ".join("%6.2f"%res[a]["net"] for a in A),T["net"],T.get("wakes",0),T.get("rescued",0),T.get("cost",0),T.get("benefit",0))
print("TERM_MODE",os.environ.get("TERM_MODE"))
V={"R1 once, skip if model watcher armed":("once",lambda g:g["watcher_at_wake"]=="0"),
   "R2 chain, only while own job runs":("chain",lambda g:g["busy_at_wake"]=="1"),
   "R3 once, only while own job runs":("once",lambda g:g["busy_at_wake"]=="1"),
   "R4 chain, own job runs & no model watcher":("chain",lambda g:g["busy_at_wake"]=="1" and g["watcher_at_wake"]=="0")}
for k,(pol,f) in V.items():
  for prof in ("brief_min","proxy_med","proxy_mean"):
    for w4 in (False,True):
      for r in ("low","high"):
        print(line("%s | %s %s %s"%(k,prof,"W4" if w4 else "-",r), sim.run(pol,r,prof,False,w4,f)))
