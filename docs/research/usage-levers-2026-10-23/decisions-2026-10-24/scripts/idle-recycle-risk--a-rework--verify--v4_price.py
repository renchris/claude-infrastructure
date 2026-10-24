#!/usr/bin/env python3
# Price verifier metrics. usage: python3 -I v4_price.py <verify_dir>
# Weights (pp per Mtok, the sim's mid set): write 0.245, read 0.0067, output 0.404, uncached input 389.
# A redundant result token is written once and read by every later request until `life` (life_pol: the
# next 150k/15m policy point, compaction or end; life_end: compaction or end). A request whose every tool
# result is >=90% redundant is an extra request: its cache read + output + input are charged too.
# pp/week = mean per recycle x 155 (310 mid-session recycles / 14 days).
import json, os, random, statistics as st, sys

V = sys.argv[1]
WR, RD, OUT, INP = 0.245e-6, 0.0067e-6, 0.404e-6, 389e-6
PW = 155.0
P = [json.loads(l) for l in open(os.path.join(V, "v3.pairs.jsonl"))]
P = [p for p in P if "win" in p]
C = [json.loads(l) for l in open(os.path.join(V, "v3.idle.jsonl"))]


def red_cost(w, N, life_key, tok_key="red_tok", t_end=None):
    life = w[life_key] if life_key != "life_end" else w["end"]
    s = w["start"]
    tot = 0.0
    toks = 0.0
    for x in w["per"]:
        if x["i"] >= s + N or (t_end is not None and x["i"] >= t_end):
            break
        r = x.get(tok_key, x["red_tok"])
        toks += r
        tot += r * (WR + RD * max(0, life - x["i"] - 1))
        if x["all_red"]:
            tot += x["cr"] * RD + x["out"] * OUT + x["inp"] * INP
    return tot, toks


def boot(xs, n=2000):
    random.seed(11)
    b = sorted(sum(random.choice(xs) for _ in xs) / len(xs) for _ in range(n))
    return b[int(0.05 * n)] * PW, b[int(0.95 * n)] * PW


def line(label, rows, f):
    vals = [f(r) for r in rows]
    c = [v[0] for v in vals]
    t = [v[1] for v in vals]
    lo, hi = boot(c)
    print(
        "  %-58s n=%4d  tok/rec mean %6.0f median %6.0f  pp/wk %.2f [%.2f-%.2f]"
        % (
            label,
            len(rows),
            sum(t) / len(t),
            st.median(t),
            sum(c) / len(c) * PW,
            lo,
            hi,
        )
    )
    return sum(c) / len(c) * PW


print(
    "== CONTENT-OVERLAP rework (successor tool output already in predecessor context since its last compaction)"
)
res = {}
for N in (10, 30):
    for lk in ("life_pol", "life_end"):
        res[("succ", N, lk)] = line(
            "successors first %d, %s" % (N, lk), P, lambda p: red_cost(p["win"], N, lk)
        )
        res[("idle", N, lk)] = line(
            "idle-return controls next %d, %s" % (N, lk),
            C,
            lambda c: red_cost(c["win"], N, lk),
        )
    line(
        "successors first %d, life_end, pred last-50-request set only" % N,
        P,
        lambda p: red_cost(p["win"], N, "life_end", "red50_tok"),
    )
print("\n  attributable (successor - idle control):")
for N in (10, 30):
    for lk in ("life_pol", "life_end"):
        print(
            "    N=%d %s: %.2f pp/week"
            % (N, lk, res[("succ", N, lk)] - res[("idle", N, lk)])
        )

# strata like the original's
print("\n== strata (content overlap, N=10 and 30, life_end)")
for nm, f in (
    ("pred ctx 150-350k", lambda p: 150e3 <= p["pred_ctx"] < 350e3),
    ("pred ctx >=350k", lambda p: p["pred_ctx"] >= 350e3),
    ("pred idle >=15m before recycle turn", lambda p: (p["pred_gap"] or 0) >= 900),
    ("pred idle <15m", lambda p: p["pred_gap"] is not None and p["pred_gap"] < 900),
    (
        "idle>=15m & 150-350k",
        lambda p: (p["pred_gap"] or 0) >= 900 and 150e3 <= p["pred_ctx"] < 350e3,
    ),
):
    X = [p for p in P if f(p)]
    for N in (10, 30):
        line("%s N=%d" % (nm, N), X, lambda p: red_cost(p["win"], N, "life_end"))

# Turn 1 = the successor's response to the brief, before the next user message
print("\n== successor TURN 1 (response to the brief, before any later user message)")
t1n = [p["t1_end"] for p in P]
print(
    "  turn-1 requests: median %d, p25 %d, p75 %d, p90 %d; <=10: %d, <=30: %d of %d"
    % (
        st.median(t1n),
        sorted(t1n)[len(t1n) // 4],
        sorted(t1n)[3 * len(t1n) // 4],
        sorted(t1n)[int(0.9 * len(t1n))],
        sum(1 for x in t1n if x <= 10),
        sum(1 for x in t1n if x <= 30),
        len(t1n),
    )
)
print(
    "  turn 1 contains an Edit/Write: %d of %d"
    % (sum(1 for p in P if p["t1_edit"]), len(P))
)
# orientation-only analogue of an idle recycle: turn 1 has no edit, ends within 30 requests, then waits >=60 s for a user message
OO = [
    p
    for p in P
    if not p["t1_edit"] and 1 <= p["t1_end"] <= 30 and (p["t1_next_gap"] or 0) >= 60
]
print(
    "  orientation-only turn 1 (no edit, <=30 requests, then >=60 s until the next user message): n=%d"
    % len(OO)
)


def t1_cost(p, life_key):
    """everything turn 1 adds beyond request 0 (which the sim prices as the re-prime): requests 1..t1_end-1
    (their read, write, output, input) + the context it leaves behind, read by every later request to life."""
    w = p["win"]
    per = w["per"]
    k = min(p["t1_end"], len(per))
    if k < 1:
        return 0.0, 0.0
    life = w[life_key] if life_key != "life_end" else w["end"]
    c = 0.0
    for x in per[1:k]:
        c += x["cr"] * RD + x["cw"] * WR + x["out"] * OUT + x["inp"] * INP
    last = per[k - 1]
    grow = max(
        0, last["ctx"] + last["out"] - per[0]["ctx"]
    )  # context left behind by turn 1 (estimate: + last output)
    c += grow * RD * max(0, life - k)
    return c, grow


for lk in ("life_pol", "life_end"):
    line(
        "orientation-only turn 1, all of it as overhead, %s" % lk,
        OO,
        lambda p: t1_cost(p, lk),
    )
    line(
        "all successors, turn 1 capped at 30 requests, %s" % lk,
        P,
        lambda p: t1_cost(dict(p, t1_end=min(p["t1_end"], 30)), lk),
    )
print(
    "  orientation-only turn-1 growth tokens: median %.0f, p75 %.0f"
    % (
        st.median([t1_cost(p, "life_pol")[1] for p in OO]),
        sorted(t1_cost(p, "life_pol")[1] for p in OO)[3 * len(OO) // 4],
    )
)
print(
    "  orientation-only turn-1 requests: median %d"
    % st.median([p["t1_end"] for p in OO])
)
print(
    "  orientation-only: overlap share of turn-1 result tokens: %.2f"
    % (
        sum(x["red_tok"] for p in OO for x in p["win"]["per"][: p["t1_end"]])
        / max(1, sum(x["res_tok"] for p in OO for x in p["win"]["per"][: p["t1_end"]]))
    )
)
lives = [p["win"]["life_pol"] for p in P]
print(
    "  successor life_pol (requests to the next policy point/compaction/end): median %d, mean %.0f; life_end median %d, mean %.0f"
    % (
        st.median(lives),
        sum(lives) / len(lives),
        st.median([p["win"]["end"] for p in P]),
        sum(p["win"]["end"] for p in P) / len(P),
    )
)

# Subagents/workflows launched inside the window, priced from their own transcripts
print(
    "\n== subagents + workflow agents started inside the window (their own transcripts, priced)"
)
for N in ("10", "30"):
    sn = [p["sub"][N][0] for p in P]
    sc = [p["sub"][N][1] for p in P]
    cn = [c["sub"][N][0] for c in C]
    cc = [c["sub"][N][1] for c in C]
    print(
        "  N=%s successors: %.2f agents/recycle, %.4f pp/recycle -> %.2f pp/week | idle-return controls: %.2f agents, %.4f pp -> %.2f pp/week | diff %.2f pp/week"
        % (
            N,
            sum(sn) / len(sn),
            sum(sc) / len(sc),
            sum(sc) / len(sc) * PW,
            sum(cn) / len(cn),
            sum(cc) / len(cc),
            sum(cc) / len(cc) * PW,
            (sum(sc) / len(sc) - sum(cc) / len(cc)) * PW,
        )
    )
    lo, hi = boot([a - sum(cc) / len(cc) for a in sc])
    print("     successor-minus-control 90%% interval [%.2f-%.2f] pp/week" % (lo, hi))
print(
    "\n  idle-return controls: n=%d from %d sessions; ctx_prev median %.0f"
    % (len(C), len({c["sid"] for c in C}), st.median(c["ctx_prev"] for c in C))
)
