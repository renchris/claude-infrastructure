import importlib.util, sys, os
spec=importlib.util.spec_from_file_location("sim","/tmp/lean-idle/idle-keepalive-wake/sim.py")
sys.argv=["sim.py","/tmp/lean-idle/idle-keepalive-wake"]
sim=importlib.util.module_from_spec(spec); spec.loader.exec_module(sim)
sim.PROFILES["goal_med"]=dict(nreq=3,cw=3460,out=714,inp=8,grow=4831,away=sim.P_AWAY)
A=sim.ACCTS
for lab,pol,f in [("literal (as coded, exit 2)","literal",None),("R2 busy-scoped chain","chain",lambda g:g["busy_at_wake"]=="1")]:
  for w4 in (False,True):
    for r in ("low","high"):
      res=sim.run(pol,r,"goal_med",False,w4,f); T=res["total"]
      print("%-28s goal_med %-3s %-4s | %s | %6.2f"%(lab,"W4" if w4 else "-",r," ".join("%6.2f"%res[a]["net"] for a in A),T["net"]))
