#!/usr/bin/env python3
# Extra cuts. usage: python3 -I v5_extra.py <verify_dir>
# (1) turn-1 cost decomposition for orientation-only successors; (2) content-overlap rework AFTER turn 1
# (requests t1_end .. t1_end+N) vs idle-return controls; (3) Agent/Task/Workflow launch counts;
# (4) successor first-request context.
import json, os, random, statistics as st, sys

V = sys.argv[1]
WR, RD, OUT, INP = 0.245e-6, 0.0067e-6, 0.404e-6, 389e-6
PW = 155.0
P = [json.loads(l) for l in open(os.path.join(V, "v3.pairs.jsonl"))]
P = [p for p in P if "win" in p]
C = [json.loads(l) for l in open(os.path.join(V, "v3.idle.jsonl"))]
OO = [
    p
    for p in P
    if not p["t1_edit"] and 1 <= p["t1_end"] <= 30 and (p["t1_next_gap"] or 0) >= 60
]


def boot(xs, n=2000):
    random.seed(11)
    b = sorted(sum(random.choice(xs) for _ in xs) / len(xs) for _ in range(n))
    return b[int(0.05 * n)] * PW, b[int(0.95 * n)] * PW


print(
    "(4) successor first-request context: median %.0f (n=%d); orientation-only subset median %.0f"
    % (
        st.median(p["win"]["per"][0]["ctx"] for p in P),
        len(P),
        st.median(p["win"]["per"][0]["ctx"] for p in OO),
    )
)

print(
    "\n(1) orientation-only turn 1 (n=%d), pp/week by component (life_pol | life_end):"
    % len(OO)
)
comp = {k: [0.0, 0.0] for k in ("read", "write", "output", "input_proxy", "carry")}
for p in OO:
    w = p["win"]
    per = w["per"]
    k = min(p["t1_end"], len(per))
    for x in per[1:k]:
        for j in (0, 1):
            comp["read"][j] += x["cr"] * RD
            comp["write"][j] += x["cw"] * WR
            comp["output"][j] += x["out"] * OUT
            comp["input_proxy"][j] += x["inp"] * INP
    last = per[k - 1]
    grow = max(0, last["ctx"] + last["out"] - per[0]["ctx"])
    comp["carry"][0] += grow * RD * max(0, w["life_pol"] - k)
    comp["carry"][1] += grow * RD * max(0, w["end"] - k)
for k, v in comp.items():
    print("   %-12s %.2f | %.2f" % (k, v[0] / len(OO) * PW, v[1] / len(OO) * PW))
tot = [sum(v[j] for v in comp.values()) / len(OO) * PW for j in (0, 1)]
nop = [tot[j] - comp["input_proxy"][j] / len(OO) * PW for j in (0, 1)]
print(
    "   total %.2f | %.2f ; without the 389/Mtok per-request input proxy %.2f | %.2f"
    % (tot[0], tot[1], nop[0], nop[1])
)


# (2) overlap rework after turn 1 (the operator-return phase) for orientation-only successors
def red_after(w, a, N, life_key):
    life = w["life_pol"] if life_key == "life_pol" else w["end"]
    c = t = 0.0
    for x in w["per"]:
        if a <= x["i"] < a + N:
            t += x["red_tok"]
            c += x["red_tok"] * (WR + RD * max(0, life - x["i"] - 1))
            if x["all_red"]:
                c += x["cr"] * RD + x["out"] * OUT + x["inp"] * INP
    return c, t


print(
    "\n(2) content-overlap rework AFTER turn 1 (orientation-only successors, window capped at request 30) vs idle-return controls"
)
for N in (10, 30):
    X = [
        p
        for p in OO
        if p["t1_end"] + N <= len(p["win"]["per"]) or p["win"]["n_req"] <= 30
    ]
    for lk in ("life_pol", "life_end"):
        sv = [red_after(p["win"], p["t1_end"], N, lk) for p in X]
        cv = [red_after(c["win"], c["win"]["start"], N, lk) for c in C]
        s_pp = sum(v[0] for v in sv) / len(sv) * PW
        c_pp = sum(v[0] for v in cv) / len(cv) * PW
        print(
            "   N=%d %s: successors n=%d %.0f tok/rec, %.2f pp/wk | controls %.0f tok, %.2f pp/wk | attributable %.2f"
            % (
                N,
                lk,
                len(X),
                sum(v[1] for v in sv) / len(sv),
                s_pp,
                sum(v[1] for v in cv) / len(cv),
                c_pp,
                s_pp - c_pp,
            )
        )

# (3) launches
LN = ("Agent", "Task", "Workflow")


def launches(w, a, N):
    return sum(
        1 for x in w["per"] if a <= x["i"] < a + N for nm in x["names"] if nm in LN
    )


print("\n(3) Agent/Task/Workflow launches per window")
for N in (10, 30):
    s = [launches(p["win"], 0, N) for p in P]
    c = [launches(c["win"], c["win"]["start"], N) for c in C]
    print(
        "   N=%d successors %.2f/session (%d of %d with any) | idle-return controls %.2f (%d of %d)"
        % (
            N,
            sum(s) / len(s),
            sum(1 for x in s if x),
            len(s),
            sum(c) / len(c),
            sum(1 for x in c if x),
            len(c),
        )
    )
for N in ("10", "30"):
    s = [p["sub"][N][1] for p in P]
    c = [c["sub"][N][1] for c in C]
    print(
        "   subagent pp/recycle N=%s: successors median %.4f mean %.4f | controls median %.4f mean %.4f"
        % (N, st.median(s), sum(s) / len(s), st.median(c), sum(c) / len(c))
    )
    so = [p["sub"][N][1] for p in OO]
    print(
        "   orientation-only successors N=%s: mean %.4f pp/recycle -> %.2f pp/week, agents %.2f"
        % (
            N,
            sum(so) / len(so),
            sum(so) / len(so) * PW,
            sum(p["sub"][N][0] for p in OO) / len(OO),
        )
    )
