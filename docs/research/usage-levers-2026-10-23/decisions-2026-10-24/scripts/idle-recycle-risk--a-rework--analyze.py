#!/usr/bin/env python3
# Rework a recycle successor does in its first N requests, priced in pp of weekly quota.
# usage: python3 -I analyze.py <workdir> [N_FIRST=10] [N_PRED=50]
# Turn = one assistant API request (requestId). Repeat = successor tool call in its first N_FIRST requests
# whose key matches a predecessor call in the predecessor's last N_PRED requests before the brief:
#   Read: same file_path (any offset/limit) · Bash: same command, whitespace-collapsed · Grep/Glob: same
#   (pattern, path, glob, type, mode) tuple. Tokens of a repeat = its tool_result chars / 4 (ESTIMATE).
# Pricing (pp per Mtok): write 0.245, read 0.0067, output 0.404. A repeat result is written once and then
# read by every later request while it stays in context:
#   life_end = until the successor's first compaction or its end (upper)
#   life_pol = until the first point the 150k/15m policy would recycle the successor again (lower)
# A request whose every tool call is a repeat is an extra request: its cache read + output are charged too.
# Controls: fresh sessions in the same cwds vs the previous session in that cwd (controls.jsonl).
import glob, json, os, random, re, statistics as st, sys
from datetime import datetime

W = sys.argv[1]
NF = int(sys.argv[2]) if len(sys.argv) > 2 else 10
NP = int(sys.argv[3]) if len(sys.argv) > 3 else 50
WR, RD, OUT = 0.245e-6, 0.0067e-6, 0.404e-6
PER_WEEK = 310 / 2.0  # 310 mid-session recycles per 14 days
K_POL, N_POL = 150000, 900


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


EV = {}
for f in glob.glob(os.path.join(W, "ev.*.jsonl")):
    for l in open(f):
        e = json.loads(l)
        EV[e["path"]] = e
pairs = [json.loads(l) for l in open(os.path.join(W, "pairs.jsonl"))]
ctls = [json.loads(l) for l in open(os.path.join(W, "controls.jsonl"))]

WS = re.compile(r"\s+")
REVERT_BASH = re.compile(
    r"git (?:checkout -- |checkout [^ ]+ -- |restore |revert |reset --hard|stash)"
)


def bkey(c):
    return WS.sub(" ", c).strip()


def loose(c):
    c = bkey(c)
    c = re.sub(r"^cd [^ ;&]+ *(?:&&|;) *", "", c)
    c = re.sub(r" *2>&1", "", c)
    c = re.sub(r"( *\| *(?:head|tail)(?: -n)? *-?\d+)+$", "", c)
    return c


def calls(e, lo, hi):
    for i in range(max(0, lo), min(hi, len(e["reqs"]))):
        for tid, nm, key in e["reqs"][i]["tools"]:
            yield i, tid, nm, key


def keyset(e, lo, hi):
    S = {"Read": set(), "Bash": set(), "BashL": set(), "GG": set(), "Edit": set()}
    for i, tid, nm, key in calls(e, lo, hi):
        if nm == "Read":
            S["Read"].add(os.path.normpath(key))
        elif nm == "Bash":
            S["Bash"].add(bkey(key))
            S["BashL"].add(loose(key))
        elif nm in ("Grep", "Glob"):
            S["GG"].add(nm + key)
        elif nm in ("Edit", "MultiEdit"):
            S["Edit"].add(key)
    return S


def pol_points(e, start):
    """request indexes >= start where the 150k/15m policy would recycle (turn start after >=15m idle at >=150k)."""
    pr = {p[1] for p in e["prompts"]}
    R = e["reqs"]
    out = []
    for i in range(max(1, start), len(R)):
        if i in pr:
            a, b = ep(R[i - 1]["ts"] or ""), ep(R[i]["ts"] or "")
            if a and b and b - a >= N_POL and R[i - 1]["ctx"] >= K_POL:
                out.append(i)
    return out


def measure(s, p, cut_ts, start_s=0):
    """s = successor/control events, p = predecessor events; cut_ts = predecessor requests before this ts."""
    cut = ep(cut_ts or "") or 1e18
    pr = [i for i, q in enumerate(p["reqs"]) if (ep(q["ts"] or "") or 0) < cut]
    if not pr:
        return None
    pend = pr[-1] + 1
    comp = [c for c in p["compacts"] if c < pend]
    plo = comp[-1] if comp else 0
    P50 = keyset(p, pend - NP, pend)
    PALL = keyset(p, plo, pend)
    R = s["reqs"]
    if len(R) < 2:
        return None
    hi = min(len(R), start_s + NF)
    scomp = [c for c in s["compacts"] if c > start_s]
    end_life = scomp[0] if scomp else len(R)
    pp = [x for x in pol_points(s, start_s + 1)]
    pol_life = min([end_life] + pp)
    m = dict(
        n_req=len(R),
        n_first=hi - start_s,
        pred_ctx=p["reqs"][pend - 1]["ctx"],
        pred_nreq=pend,
        rep=dict(Read=[0, 0], Bash=[0, 0], BashL=[0, 0], GG=[0, 0]),
        rep_all=dict(Read=[0, 0], Bash=[0, 0], GG=[0, 0]),
        calls=0,
        res_tok=0,
        rep_tok=0,
        rep_tok_all=0,
        rep_only_req=0,
        wr_pp=0.0,
        rd_end_pp=0.0,
        rd_pol_pp=0.0,
        xreq_pp=0.0,
        growth=R[hi - 1]["ctx"] - R[start_s]["ctx"],
        first_ctx=R[start_s]["ctx"],
        life_end=end_life - start_s,
        life_pol=pol_life - start_s,
    )
    for i in range(start_s, hi):
        q = R[i]
        nrep = 0
        for tid, nm, key in q["tools"]:
            m["calls"] += 1
            chars, err = s["results"].get(tid, [0, False])
            tok = chars / 4.0
            m["res_tok"] += tok
            hit = hit_all = False
            if nm == "Read":
                k = os.path.normpath(key)
                hit, hit_all = k in P50["Read"], k in PALL["Read"]
                cat = "Read"
            elif nm == "Bash":
                hit, hit_all = bkey(key) in P50["Bash"], bkey(key) in PALL["Bash"]
                if loose(key) in P50["BashL"]:
                    m["rep"]["BashL"][0] += 1
                    m["rep"]["BashL"][1] += tok
                cat = "Bash"
            elif nm in ("Grep", "Glob"):
                hit, hit_all = (nm + key) in P50["GG"], (nm + key) in PALL["GG"]
                cat = "GG"
            else:
                continue
            if hit:
                nrep += 1
                m["rep"][cat][0] += 1
                m["rep"][cat][1] += tok
                m["rep_tok"] += tok
                m["wr_pp"] += tok * WR
                m["rd_end_pp"] += tok * max(0, end_life - i - 1) * RD
                m["rd_pol_pp"] += tok * max(0, pol_life - i - 1) * RD
            if hit_all:
                m["rep_all"][cat][0] += 1
                m["rep_all"][cat][1] += tok
                m["rep_tok_all"] += tok
        if q["tools"] and nrep == len(q["tools"]):
            m["rep_only_req"] += 1
            m["xreq_pp"] += q["cr"] * RD + q["out"] * OUT
    return m


def quality(e, lo, hi, other=None):
    n_res = n_err = n_loss = n_rev_bash = n_rev_edit = 0
    oth_edits = keyset(other, 0, len(other["reqs"]))["Edit"] if other else set()
    own_edits = set()
    for i in range(max(0, lo), min(hi, len(e["reqs"]))):
        q = e["reqs"][i]
        n_loss += len(q["loss"])
        for tid, nm, key in q["tools"]:
            r = e["results"].get(tid)
            if r:
                n_res += 1
                n_err += int(r[1])
            if nm == "Bash" and REVERT_BASH.search(key):
                n_rev_bash += 1
            if nm in ("Edit", "MultiEdit"):
                f, a, b, ra = json.loads(key)
                rev = json.dumps([f, b, a, ra])
                if rev in oth_edits or rev in own_edits:
                    n_rev_edit += 1
                own_edits.add(key)
    return dict(
        n_req=max(0, min(hi, len(e["reqs"])) - max(0, lo)),
        n_res=n_res,
        n_err=n_err,
        n_loss=n_loss,
        n_rev_bash=n_rev_bash,
        n_rev_edit=n_rev_edit,
    )


rows, crows, qrows = [], [], []
for pr in pairs:
    s, p = EV.get(pr["succ_path"]), EV.get(pr["pred_path"] or "")
    if not s or not p:
        continue
    m = measure(s, p, pr["brief_ts"])
    if not m:
        continue
    m.update(
        succ=pr["succ"],
        pred=pr["pred"],
        cwd=pr["cwd"],
        join=pr["join"],
        same_cwd=pr["cwd"] == pr["pred_cwd"],
    )
    rows.append(m)
    cut = ep(pr["brief_ts"] or "") or 1e18
    pend = len([q for q in p["reqs"] if (ep(q["ts"] or "") or 0) < cut])
    qs = quality(s, 0, NF, p)
    qp = quality(p, pend - NF, pend)
    qrows.append(dict(succ=qs, pred=qp, succ_sid=pr["succ"], pred_ctx=m["pred_ctx"]))
for c in ctls:
    s, p = EV.get(c["ctl_path"]), EV.get(c["prev_path"])
    if not s or not p:
        continue
    if not s["reqs"] or s["reqs"][0]["ctx"] > 100000 or len(s["reqs"]) < NF:
        continue  # forks / probes / one-shot checks are not fresh working sessions
    if s["prompts"] and s["prompts"][0][2].startswith("Reply with exactly"):
        continue
    m = measure(s, p, c["fp_ts"])
    if not m:
        continue
    m.update(
        ctl=c["ctl"],
        cwd=c["cwd"],
        gap_s=c["gap_s"],
        teammate=c["ctl_first_prompt"].startswith("<teammate-message"),
    )
    m["q"] = quality(s, 0, NF, p)
    crows.append(m)


def summ(rs, label):
    if not rs:
        print(label, "n=0")
        return {}
    n = len(rs)
    f = lambda k: [r[k] for r in rs]
    tot = lambda k: sum(f(k))
    pprec_end = [r["wr_pp"] + r["rd_end_pp"] + r["xreq_pp"] for r in rs]
    pprec_pol = [r["wr_pp"] + r["rd_pol_pp"] + r["xreq_pp"] for r in rs]
    random.seed(7)
    boot = []
    for _ in range(2000):
        smp = [random.choice(pprec_end) for _ in range(n)]
        boot.append(sum(smp) / n)
    boot.sort()
    out = dict(
        n=n,
        with_any_repeat=sum(
            1
            for r in rs
            if r["rep_tok"] > 0
            or any(v[0] for k, v in r["rep"].items() if k != "BashL")
        ),
        calls_mean=tot("calls") / n,
        res_tok_mean=tot("res_tok") / n,
        growth_median=st.median(f("growth")),
        first_ctx_median=st.median(f("first_ctx")),
        read_rep_calls=sum(r["rep"]["Read"][0] for r in rs) / n,
        read_rep_tok=sum(r["rep"]["Read"][1] for r in rs) / n,
        bash_rep_calls=sum(r["rep"]["Bash"][0] for r in rs) / n,
        bash_rep_tok=sum(r["rep"]["Bash"][1] for r in rs) / n,
        bashL_rep_calls=sum(r["rep"]["BashL"][0] for r in rs) / n,
        bashL_rep_tok=sum(r["rep"]["BashL"][1] for r in rs) / n,
        gg_rep_calls=sum(r["rep"]["GG"][0] for r in rs) / n,
        gg_rep_tok=sum(r["rep"]["GG"][1] for r in rs) / n,
        rep_tok_mean=tot("rep_tok") / n,
        rep_tok_median=st.median(f("rep_tok")),
        rep_tok_p90=sorted(f("rep_tok"))[int(0.9 * (n - 1))],
        rep_tok_all_mean=tot("rep_tok_all") / n,
        rep_share_of_results=tot("rep_tok") / max(1, tot("res_tok")),
        rep_only_req_mean=tot("rep_only_req") / n,
        life_end_median=st.median(f("life_end")),
        life_pol_median=st.median(f("life_pol")),
        pp_rec_write=tot("wr_pp") / n,
        pp_rec_read_end=tot("rd_end_pp") / n,
        pp_rec_read_pol=tot("rd_pol_pp") / n,
        pp_rec_xreq=tot("xreq_pp") / n,
        pp_rec_end=sum(pprec_end) / n,
        pp_rec_pol=sum(pprec_pol) / n,
        pp_rec_end_ci90=[boot[100], boot[1899]],
        pp_week_end=sum(pprec_end) / n * PER_WEEK,
        pp_week_pol=sum(pprec_pol) / n * PER_WEEK,
        pp_week_end_ci90=[boot[100] * PER_WEEK, boot[1899] * PER_WEEK],
    )
    print("\n== %s (first %d requests vs other's last %d) n=%d" % (label, NF, NP, n))
    for k, v in out.items():
        print("  %-22s %s" % (k, ("%.4g" % v) if isinstance(v, float) else v))
    return out


res = dict(N_FIRST=NF, N_PRED=NP)
res["succ_all"] = summ(rows, "SUCCESSORS all pairs")
res["succ_150k"] = summ(
    [r for r in rows if r["pred_ctx"] >= K_POL],
    "SUCCESSORS, predecessor ctx >= 150k at recycle",
)
res["succ_lt150k"] = summ(
    [r for r in rows if r["pred_ctx"] < K_POL], "SUCCESSORS, predecessor ctx < 150k"
)
res["ctl_all"] = summ(crows, "CONTROLS fresh sessions same cwds")
res["ctl_nonteam"] = summ(
    [r for r in crows if not r["teammate"]], "CONTROLS excluding Agent-Teams teammates"
)
res["ctl_le1h"] = summ(
    [r for r in crows if r["gap_s"] <= 3600],
    "CONTROLS previous session ended <= 1h before",
)


def qsum(qs, label):
    a = {k: sum(q[k] for q in qs) for k in qs[0]}
    print(
        "  %-34s n=%d req=%d results=%d err=%d (%.2f%%) loss_phr=%d (%.2f/100req) rev_bash=%d rev_edit=%d"
        % (
            label,
            len(qs),
            a["n_req"],
            a["n_res"],
            a["n_err"],
            100.0 * a["n_err"] / max(1, a["n_res"]),
            a["n_loss"],
            100.0 * a["n_loss"] / max(1, a["n_req"]),
            a["n_rev_bash"],
            a["n_rev_edit"],
        )
    )
    a["err_rate"] = a["n_err"] / max(1, a["n_res"])
    a["sessions_with_err"] = sum(1 for q in qs if q["n_err"])
    return a


print(
    "\n== QUALITY (successor first %d vs predecessor last %d requests; controls first %d)"
    % (NF, NF, NF)
)
res["q_succ"] = qsum([q["succ"] for q in qrows], "successor first")
res["q_pred"] = qsum([q["pred"] for q in qrows], "predecessor last")
res["q_succ150"] = qsum(
    [q["succ"] for q in qrows if q["pred_ctx"] >= K_POL], "successor first (pred>=150k)"
)
res["q_pred150"] = qsum(
    [q["pred"] for q in qrows if q["pred_ctx"] >= K_POL],
    "predecessor last (pred>=150k)",
)
res["q_ctl"] = qsum([r["q"] for r in crows], "control first")
# paired sign test on per-pair error rates
d = [
    (q["succ"]["n_err"] / max(1, q["succ"]["n_res"]))
    - (q["pred"]["n_err"] / max(1, q["pred"]["n_res"]))
    for q in qrows
]
res["q_pair_succ_higher"] = sum(1 for x in d if x > 0)
res["q_pair_pred_higher"] = sum(1 for x in d if x < 0)
res["q_pair_tie"] = sum(1 for x in d if x == 0)
print(
    "  paired error-rate: successor higher %d, predecessor higher %d, tie %d"
    % (res["q_pair_succ_higher"], res["q_pair_pred_higher"], res["q_pair_tie"])
)
json.dump(
    dict(res=res, rows=rows, crows=crows, qrows=qrows),
    open(os.path.join(W, "analysis.N%d.P%d.json" % (NF, NP)), "w"),
)
