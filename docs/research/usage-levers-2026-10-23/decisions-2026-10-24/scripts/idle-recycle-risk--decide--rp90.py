# Run W4 sim.row() at several K/N with the p90 re-prime (as sim.py's reprime_p90 variant), mid weights.
import sys, importlib.util, json
SIM = "/Users/chrisren/Development/claude-infrastructure/docs/research/usage-levers-2026-10-23/w4/sim.py"
sys.argv = [SIM, sys.argv[1]]
spec = importlib.util.spec_from_file_location("w4sim", SIM)
sim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sim)
cw90 = sim.pct([r["cw"] for r in sim.allfirst], 90)
rp90 = dict(sim.RP, cw=cw90, ctx=sim.RP["ctx"] - sim.RP["cw"] + cw90)
print("RP", sim.RP, "rp90", rp90)
for K, N in [(150_000, 15), (200_000, 15), (250_000, 15), (300_000, 15), (350_000, 15)]:
    for lab, kw in (("rp_med", {}), ("rp_p90", {"rp": rp90})):
        r = sim.row(K, N, "mid", **kw)
        print(K, N, lab, json.dumps({k: v for k, v in r.items() if not isinstance(v, (list,)) }, default=str)[:600])
r = sim.row(350_000, 15, "mid", rules=[(350_000, 15), (250_000, 60)], rp=rp90)
print("current_practice rp_p90", json.dumps(r, default=str)[:600])
