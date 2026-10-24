#!/usr/bin/env python3
# Looser rework tiers on the stage-2 events (complements analyze.py's strict T1).
# usage: python3 -I analyze2.py <workdir> [N_FIRST=10] [N_PRED=50]
# T2 file-touch: a successor call (Read / Bash / Grep / Glob) that references a file key the predecessor
#    referenced in ANY tool (Read/Edit/Write/Bash/Grep/Glob) in its window, or that reads the predecessor's
#    own transcript / tool-results (its sid appears in the call). File key = last two path components of
#    a path-like token with a file extension that is not the executed program. Tokens = whole result / 4.
# T3 upper bound: every tool result in the successor's first N requests is rework, and every one of those
#    requests is an extra request (its cache read + output charged).
# Pricing as analyze.py: write 0.245, read 0.0067, output 0.404 pp/Mtok; result tokens stay in context until
#    the successor's first compaction/end (life_end) or the next 150k/15m policy point (life_pol).
import glob, json, os, random, re, statistics as st, sys
from datetime import datetime

W = sys.argv[1]
NF = int(sys.argv[2]) if len(sys.argv) > 2 else 10
NP = int(sys.argv[3]) if len(sys.argv) > 3 else 50
WR, RD, OUT = 0.245e-6, 0.0067e-6, 0.404e-6
PER_WEEK = 155.0
K_POL, N_POL = 150000, 900
EXT = re.compile(
    r"\.(?:md|py|sh|ts|tsx|js|mjs|cjs|json|jsonl|txt|ya?ml|bats|toml|log|out|tsv|csv|html|css|sql|swift|rs|go|zsh|plist|conf|cfg|ini)$"
)
TOK = re.compile(r"[A-Za-z0-9_~.$/{}@+-]*/[A-Za-z0-9_.@+-]+")
SEG = re.compile(r"(?:^|[;&|(]|\$\(|&&|\|\|)\s*(?:[A-Z_]+=\S+\s+)*([^\s;&|()]+)")


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def fkey(p):
    p = p.strip("'\"`,:()[]{}")
    if "=" in p:
        p = p.split("=", 1)[1]
    if not EXT.search(p):
        return None
    parts = [x for x in p.split("/") if x]
    return "/".join(parts[-2:]) if len(parts) >= 2 else (parts[0] if parts else None)


def files_of(nm, key):
    out = set()
    if nm == "Read":
        k = fkey(key)
        if k:
            out.add(k)
    elif nm in ("Edit", "MultiEdit", "Write"):
        k = fkey(json.loads(key)[0])
        if k:
            out.add(k)
    elif nm in ("Grep", "Glob"):
        d = json.loads(key)
        for v in (d.get("path"), d.get("pattern") if nm == "Glob" else None):
            if v:
                k = fkey(v)
                if k:
                    out.add(k)
    elif nm == "Bash":
        progs = {m.group(1) for m in SEG.finditer(key)}
        for t in TOK.findall(key):
            if t in progs:
                continue
            k = fkey(t)
            if k:
                out.add(k)
    return out


EV = {}
for f in glob.glob(os.path.join(W, "ev.*.jsonl")):
    for l in open(f):
        e = json.loads(l)
        EV[e["path"]] = e
pairs = [json.loads(l) for l in open(os.path.join(W, "pairs.jsonl"))]
ctls = [json.loads(l) for l in open(os.path.join(W, "controls.jsonl"))]


def pol_life(e, start, end_life):
    pr = {p[1] for p in e["prompts"]}
    R = e["reqs"]
    for i in range(max(1, start + 1), end_life):
        if i in pr:
            a, b = ep(R[i - 1]["ts"] or ""), ep(R[i]["ts"] or "")
            if a and b and b - a >= N_POL and R[i - 1]["ctx"] >= K_POL:
                return i
    return end_life


def measure(s, p, cut_ts, psid):
    cut = ep(cut_ts or "") or 1e18
    pend = len([q for q in p["reqs"] if (ep(q["ts"] or "") or 0) < cut])
    if pend == 0 or len(s["reqs"]) < 2:
        return None
    comp = [c for c in p["compacts"] if c < pend]
    plo = comp[-1] if comp else 0
    F50, FALL = set(), set()
    for i in range(plo, pend):
        for tid, nm, key in p["reqs"][i]["tools"]:
            fs = files_of(nm, key)
            FALL |= fs
            if i >= pend - NP:
                F50 |= fs
    R = s["reqs"]
    hi = min(len(R), NF)
    scomp = [c for c in s["compacts"] if c > 0]
    le = scomp[0] if scomp else len(R)
    lp = pol_life(s, 0, le)
    m = dict(
        t2_tok=0.0,
        t2all_tok=0.0,
        t2_calls=0,
        tx_calls=0,
        tx_tok=0.0,
        t3_tok=0.0,
        t2_pp_end=0.0,
        t2_pp_pol=0.0,
        t2all_pp_end=0.0,
        t3_pp_end=0.0,
        t3_pp_pol=0.0,
        life_end=le,
        life_pol=lp,
        pred_ctx=p["reqs"][pend - 1]["ctx"],
        first_ctx=R[0]["ctx"],
    )
    short = psid[:8] if psid else None
    for i in range(hi):
        q = R[i]
        allrep = bool(q["tools"])
        for tid, nm, key in q["tools"]:
            tok = s["results"].get(tid, [0, False])[0] / 4.0
            m["t3_tok"] += tok
            m["t3_pp_end"] += tok * (WR + max(0, le - i - 1) * RD)
            m["t3_pp_pol"] += tok * (WR + max(0, lp - i - 1) * RD)
            if nm not in ("Read", "Bash", "Grep", "Glob"):
                allrep = False
                continue
            fs = files_of(nm, key)
            tx = bool(short and short in key)
            if tx:
                m["tx_calls"] += 1
                m["tx_tok"] += tok
            hit = tx or bool(fs & F50)
            hit_all = tx or bool(fs & FALL)
            if hit:
                m["t2_calls"] += 1
                m["t2_tok"] += tok
                m["t2_pp_end"] += tok * (WR + max(0, le - i - 1) * RD)
                m["t2_pp_pol"] += tok * (WR + max(0, lp - i - 1) * RD)
            else:
                allrep = False
            if hit_all:
                m["t2all_tok"] += tok
                m["t2all_pp_end"] += tok * (WR + max(0, le - i - 1) * RD)
        xr = q["cr"] * RD + q["out"] * OUT
        m["t3_pp_end"] += xr
        m["t3_pp_pol"] += xr
        if allrep:
            m["t2_pp_end"] += xr
            m["t2_pp_pol"] += xr
            m["t2all_pp_end"] += xr
    return m


rows, crows = [], []
for pr in pairs:
    s, p = EV.get(pr["succ_path"]), EV.get(pr["pred_path"] or "")
    if s and p:
        m = measure(s, p, pr["brief_ts"], pr["pred"])
        if m:
            m["succ"] = pr["succ"]
            rows.append(m)
for c in ctls:
    s, p = EV.get(c["ctl_path"]), EV.get(c["prev_path"])
    if (
        not s
        or not p
        or not s["reqs"]
        or s["reqs"][0]["ctx"] > 100000
        or len(s["reqs"]) < NF
    ):
        continue
    if s["prompts"] and s["prompts"][0][2].startswith("Reply with exactly"):
        continue
    m = measure(s, p, c["fp_ts"], c["prev"])
    if m:
        m["teammate"] = c["ctl_first_prompt"].startswith("<teammate-message")
        crows.append(m)


def boot(xs, n=2000):
    random.seed(7)
    b = sorted(sum(random.choice(xs) for _ in xs) / len(xs) for _ in range(n))
    return [b[int(0.05 * n)], b[int(0.95 * n)]]


def summ(rs, label):
    n = len(rs)
    mean = lambda k: sum(r[k] for r in rs) / n
    out = {
        k: mean(k)
        for k in (
            "t2_calls",
            "t2_tok",
            "t2all_tok",
            "tx_calls",
            "tx_tok",
            "t3_tok",
            "t2_pp_end",
            "t2_pp_pol",
            "t2all_pp_end",
            "t3_pp_end",
            "t3_pp_pol",
        )
    }
    out["n"] = n
    out["sessions_reading_pred_transcript"] = sum(1 for r in rs if r["tx_calls"])
    out["t2_tok_median"] = st.median(r["t2_tok"] for r in rs)
    out["first_ctx_median"] = st.median(r["first_ctx"] for r in rs)
    for k in ("t2_pp_end", "t2_pp_pol", "t2all_pp_end", "t3_pp_end", "t3_pp_pol"):
        out[k + "_week"] = out[k] * PER_WEEK
    out["t2_pp_end_week_ci90"] = [
        x * PER_WEEK for x in boot([r["t2_pp_end"] for r in rs])
    ]
    out["t3_pp_end_week_ci90"] = [
        x * PER_WEEK for x in boot([r["t3_pp_end"] for r in rs])
    ]
    print("\n== %s n=%d (first %d vs last %d)" % (label, n, NF, NP))
    for k, v in out.items():
        print("  %-34s %s" % (k, ("%.4g" % v) if isinstance(v, float) else v))
    return out


res = dict(
    succ=summ(rows, "SUCCESSORS"),
    succ150=summ([r for r in rows if r["pred_ctx"] >= K_POL], "SUCCESSORS pred>=150k"),
    ctl=summ(crows, "CONTROLS"),
    ctl_nonteam=summ([r for r in crows if not r["teammate"]], "CONTROLS non-teammate"),
)
json.dump(
    dict(res=res, rows=rows, crows=crows),
    open(os.path.join(W, "analysis2.N%d.P%d.json" % (NF, NP)), "w"),
)
