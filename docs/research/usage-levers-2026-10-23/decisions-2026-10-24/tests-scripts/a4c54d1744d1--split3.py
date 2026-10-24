"""Copy of review-numbers/split2.py model (sv) run at the re-gate's measured turn ratios.
Imports savings_copy.py (identical to savings.py except its json.dump goes to this dir).
Prints wk-0/wk-1 per-week gross saving for b13 and non-b13 eligible slots."""
import runpy, sys
sys.argv = ["x"]
g = runpy.run_path("/tmp/conv-tests/a4c54d1744d1/savings_copy.py", run_name="lib")
elig, week, strip_prefix, runs = g["elig"], g["week"], g["strip_prefix"], g["runs"]
WW, WO = 0.245, 0.404
def sv(s, wr, k, turns, perreq=0.0006):
    ft = s["first_cw"] + s["first_cr"] + s["first_in"]
    D = max(0, ft - k * s["brief_chars"] - 6500)
    base = (WW * s["cw"] + wr * s["cr"] + WO * s["out"]) / 1e6 + perreq * s["nreq"]
    cw, cr = strip_prefix(s, D)
    resid = (WW * cw + wr * cr + WO * s["out"]) / 1e6 + perreq * s["nreq"]
    return base - resid * turns
rec = [s for s in elig if week(s["first_ts"]) <= 1]
isb = lambda s: (runs[s["runId"]].get("name") or "").startswith("b13")
B = [s for s in rec if isb(s)]; R = [s for s in rec if not isb(s)]
print("slots b13", len(B), "rest", len(R))
for turns in (0.667, 0.79, 1.045, 1.195, 1.30):
    for k in (0.30, 0.41):
        for wr in (0.0057, 0.0067, 0.0076):
            for pr in (0.0006, 0.0):
                print(f"turns={turns} k={k} reads={wr} perreq={pr}: b13 {sum(sv(s,wr,k,turns,pr) for s in B)/2:5.1f} rest {sum(sv(s,wr,k,turns,pr) for s in R)/2:5.1f} pp/week")
