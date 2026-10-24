#!/usr/bin/env python3
# Break-even and policy simulation for a 55-minute idle keepalive on MAIN sessions.
# Inputs (all measured): mainstate.jsonl (every main gap > 45 min in yesterday's 7-day window, with state),
# wakes.jsonl (cost of a warm cc-await-ping timeout wake turn). Weights: the three sets yesterday reported.
import json, statistics as S, collections

R = [json.loads(l) for l in open("/tmp/usage-audit/r2/cache-rebuilds/mainstate.jsonl")]
W = [json.loads(l) for l in open("/tmp/usage-audit/r2/cache-rebuilds/wakes.jsonl")]
wt = [
    w
    for w in W
    if w["kind"] == "watcher_timeout" and w["gap"] < 3600 and w["prev_pp"] > 20000
]
READ_X = S.mean(w["cr"] / w["prev_pp"] for w in wt)  # context re-reads per wake turn
CC_W = S.mean(w["cc"] for w in wt)
OUT_W = S.mean(w["out"] for w in wt)
print(
    f"warm watcher-timeout wake turns n={len(wt)}: reads={READ_X:.2f}x context, write={CC_W:.0f} tok, output={OUT_W:.0f} tok (means)"
)

# weights per token; totals = deduped 7-day token totals from /tmp/usage-audit/sk-cache-an.out [2]
TOT = dict(inp=0.5e6, cc5=536.8e6, cc1=308.2e6, cr=37101.8e6, out=87.9e6)
WS = {
    "API list (reads count, r/w1h=0.05)": dict(
        inp=1, cc5=1.25, cc1=2.0, cr=0.1, out=5.0
    ),
    "meter fit, reads count (sk_bc_meter2 weekly)": dict(
        inp=0, cc5=0.3473, cc1=0.2896, cr=0.0067, out=0.9248
    ),
    "meter fit, reads count (sk_bc_meter2 5h)": dict(
        inp=0, cc5=1.3958, cc1=1.2772, cr=0.0252, out=3.0452
    ),
    "meter, reads at repo upper bound 0.049": dict(
        inp=0, cc5=0.2848, cc1=1.0678, cr=0.049, out=0.4731
    ),
    "meter fit, reads free (sk-cache-ttlfit2)": dict(
        inp=0, cc5=0.2852, cc1=1.0767, cr=0.0, out=0.4519
    ),
}


def total(w):
    return sum(TOT[k] * w[k] for k in TOT)


C_MED = S.median(w["prev_pp"] for w in wt)
print(
    f"median context at a wake = {C_MED / 1e3:.0f}k; 1-2h bust mean rebuild = {S.mean(r['cc'] for r in R if r['bust'] and 3600 < r['gap'] <= 7200) / 1e3:.0f}k"
)
print(
    "\nBREAK-EVEN: wakes per avoided rebuild (k*) = C(w1h - r) / (READ_X*C*r + CC_W*w1h + OUT_W*w_out), C = 262k"
)
for name, w in WS.items():
    C = 262e3
    save = C * (w["cc1"] - w["cr"])
    cost = READ_X * C * w["cr"] + CC_W * w["cc1"] + OUT_W * w["out"]
    print(
        f"  {name:48s} k* = {save / cost:5.1f}   one wake = {cost / (C * w['cc1']):.1%} of a rebuild"
    )


def sim(H, eligible, w):
    saved = cost = 0.0
    nw = nsaved = nwasted_gaps = 0
    for r in R:
        st = state(r)
        G = r["gap"]
        if st not in eligible or G <= 3300:
            continue
        if G < 3600 and r["trig"].startswith("task_notif:watcher"):
            continue  # already kept warm by an existing 55-min watcher wake: no incremental cost
        C = r["pp"]
        k = 0
        t = 3300
        while t < G and t <= H:
            k += 1
            t += 3300
        if k == 0:
            continue
        tk = 3300 * k
        c1 = k * (READ_X * C * w["cr"] + CC_W * w["cc1"] + OUT_W * w["out"])
        cost += c1
        nw += k
        if r["bust"] and G - tk < 3600:
            saved += r["cc"] * (w["cc1"] - w["cr"])
            nsaved += 1
        elif not r["bust"] or G - tk >= 3600:
            nwasted_gaps += 1
    return saved, cost, nw, nsaved, nwasted_gaps


def state(r):
    if r["fg_pending"]:
        return "A"
    if any(x["kind"] == "watcher" for x in r["live"]):
        return "B"
    if r["live"]:
        return "C"
    return "D"


cnt = collections.Counter(
    (state(r), "1-2h" if r["gap"] <= 7200 else "2-8h" if r["gap"] <= 28800 else ">8h")
    for r in R
    if r["gap"] > 3600
)
print("\nmain gaps >1h by state (all gaps, bust or not):", dict(sorted(cnt.items())))
POL = [
    ("all idle (B,C,D), cap 2h", 7200, {"B", "C", "D"}),
    ("all idle (B,C,D), cap 4h", 14400, {"B", "C", "D"}),
    ("all idle (B,C,D), cap 24h", 86400, {"B", "C", "D"}),
    ("own bg job running only (C), cap 2h", 7200, {"C"}),
    ("own bg job running only (C), cap 4h", 14400, {"C"}),
    ("C + model-watcher (B,C), cap 4h", 14400, {"B", "C"}),
]
print(
    "\nPOLICY SIMULATION over the 7-day window (net = saved - cost, as % of that weight set's weekly total)"
)
for name, w in WS.items():
    T = total(w)
    print(f"  [{name}] weekly total = {T / 1e6:,.1f} units/Mtok-scaled")
    for pn, H, el in POL:
        s, c, nw, ns, nwg = sim(H, el, w)
        print(
            f"     {pn:40s} wakes={nw:4d} rebuilds avoided={ns:3d} saved={s / T:6.2%} cost={c / T:6.2%} net={(s - c) / T:+6.2%}"
        )
