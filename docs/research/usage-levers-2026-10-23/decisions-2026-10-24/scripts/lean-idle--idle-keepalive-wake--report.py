import importlib.util, sys, os, json
os.environ.setdefault("TERM_MODE","low")
spec=importlib.util.spec_from_file_location("sim","/tmp/lean-idle/idle-keepalive-wake/sim.py")
sys.argv=["sim.py","/tmp/lean-idle/idle-keepalive-wake"]
sim=importlib.util.module_from_spec(spec); spec.loader.exec_module(sim)
A=sim.ACCTS
def line(lab,res):
    T=res["total"]
    return "%-44s | %s | %6.2f | wakes %6.1f rescued %5.1f cost %5.2f ben %5.2f | term wakes %5.1f | pre-TTL wakes %5.1f" % (lab," ".join("%6.2f"%res[a]["net"] for a in A),T["net"],T.get("wakes",0),T.get("rescued",0),T.get("cost",0),T.get("benefit",0),T.get("term_wakes",0),T.get("pre_ttl_wakes",0))
print("TERM_MODE",os.environ["TERM_MODE"])
print("%-44s | %s |  total"%("scenario"," ".join("%6s"%a for a in A)))
base=sim.run("once","low","brief_min")
print("pool (all rebuilds, pp/wk at low reads):", {a:round(base[a].get("rebuild_pp",0),2) for a in A}, "total", base["total"].get("rebuild_pp"), "rebuild gaps/wk", base["total"].get("rebuilds"), "gaps>=3300/wk", base["total"].get("gaps_ge_3300"))
for pol in ("literal","once","chain"):
  for prof in ("brief_min","proxy_med","proxy_mean"):
    for w4 in (False,True):
      for r in ("low","high"):
        print(line("%s %s %s reads=%s"%(pol,prof,"W4" if w4 else "noW4",r), sim.run(pol,r,prof,False,w4)))
print("\n-- splits (once/literal, proxy_med, low reads, noW4) --")
sels={"goal sessions":lambda g:g["goal"]=="1","non-goal":lambda g:g["goal"]=="0","watcher armed at wake":lambda g:g["watcher_at_wake"]=="1","no watcher at wake":lambda g:g["watcher_at_wake"]=="0","own job running at wake":lambda g:g["busy_at_wake"]=="1","idle (no own job)":lambda g:g["busy_at_wake"]=="0","never resumed (terminal)":lambda g:g["terminal"]=="1","gaps >= 3h":lambda g:float(g["dur"])>=10800,"gaps 55-60 min":lambda g:3300<=float(g["dur"])<3600,"gaps 60-115 min":lambda g:3600<=float(g["dur"])<6900}
for pol in ("literal","once","chain"):
  for k,f in sels.items():
    print(line("%s proxy_med low | %s"%(pol,k), sim.run(pol,"low","proxy_med",False,False,f)))
print("\n-- per-request input term on (fit4 W_INP 389), proxy_med --")
for pol in ("literal","once","chain"):
  for r in ("low","high"):
    print(line("%s proxy_med +inp reads=%s"%(pol,r), sim.run(pol,r,"proxy_med",True,False)))
