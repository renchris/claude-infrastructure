"""(1) Default-B2 rebuild excess: for each request with cr==0 after request 0, the prior cached prefix
(cr+cw of the previous request) would have been read, not written. Excess = prefix*(0.245-0.0067)/1e6.
(2) Turn-ratio uncertainty: t-interval on per-brief log(lean/default) requests (n=3).
Usage: python3 -I adjust.py <wf_dir>"""
import json, sys, math, os
WR, WW = 0.0067, 0.245
wf = sys.argv[1]
def reqs(aid):
    R = {}; o = []
    for l in open(os.path.join(wf, f"agent-{aid}.jsonl")):
        r = json.loads(l)
        if r.get("type") != "assistant": continue
        u = r["message"].get("usage") or {}; rid = r["requestId"]
        if rid not in R: o.append(rid); R[rid] = [0, 0]
        R[rid][0] = max(R[rid][0], u.get("cache_creation_input_tokens", 0)); R[rid][1] = max(R[rid][1], u.get("cache_read_input_tokens", 0))
    return [R[x] for x in o]
for aid, lab in (("a84e22c362fa90b01", "default:B2"),):
    q = reqs(aid); ex = 0; n = 0
    for i in range(1, len(q)):
        if q[i][1] == 0:
            pre = q[i-1][0] + q[i-1][1]; ex += pre; n += 1
    print(f"{lab}: rebuilds {n}, rebuilt prefix tokens {ex}, excess pp {ex*(WW-WR)/1e6:.4f}")
pairs = {"B1": (19, 26), "B2": (22, 33), "B3": (23, 22)}
ls = [math.log(a / b) for a, b in pairs.values()]
m = sum(ls) / 3; sd = math.sqrt(sum((x - m) ** 2 for x in ls) / 2); se = sd / math.sqrt(3)
print(f"geo-mean turn ratio {math.exp(m):.3f}; one-sided 95% upper (t2=2.920) {math.exp(m+2.920*se):.3f}; two-sided 95% (t2=4.303) {math.exp(m-4.303*se):.3f}-{math.exp(m+4.303*se):.3f}")
