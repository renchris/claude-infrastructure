#!/usr/bin/env python3
"""sim.py — the D1 K/N replay: what an earlier IDLE recycle would have saved (plan § W7+ §2 D1
"Offline (programmatic)"). A port of docs/research/usage-levers-2026-10-23/w4/sim.py, the model
the decision was made on, restated as a library over per-session cases so the hillclimb split, the
reproduction and the bats fixture all run ONE engine.

THE MODEL (unchanged from W4; one case = one sessionId, requests merged across accounts):
  * A recycle point is a TURN-START request whose gap from the previous request is ≥ N minutes,
    with the counterfactual context at that idle point ≥ K tokens. Mid-turn gaps never qualify,
    and a non-watcher background job running at idle minute N makes the session busy there.
  * At a recycle the predecessor spends one handoff request (a read of its context if the cache is
    still warm at minute N ≤ 55, else a rewrite) plus 1,500 output tokens; the successor pays the
    re-prime; if the real gap outlives the 1 h TTL past N, it rewrites its re-prime.
  * Every later request then runs at c − off; its cache write is unchanged (capped by the smaller
    context), the rest is a read. A compaction (context < 60% of the previous request) resets off.
  * Terminal idle: a last request at ≥ K, idle ≥ N before the window end, in a session with no
    close mark, is charged one recycle with no benefit.

THE ANCHOR. decisions-2026-10-24/REPORT.md §1: with the measured p90 re-prime (rp90.py), 150k/15
saves 16.36 pp/week gross and 200k/15 saves 15.39 (mid read weight). flow.check_repro holds this
port to both within ±5%.

CASES (see from_rows): {case_id, sid, acct, E, closed, jobs [[start, end]], r [[ts, acct_index,
inp, cw, cr, out, turn]]}; the window, the re-prime sample and both re-prime settings live in meta.
Stdlib only, Python 3.9-safe.
"""

import collections
import csv
import json
import os
import statistics

ACCTS = ["next", "next2", "next3", "next4"]
TTL = 3600  # main sessions write the 1h cache tier
WARM_N = 55 * 60  # a handoff turn at idle minute <= 55 still reads a warm cache
HANDOFF_OUT = 1500
W_INP, W_CW, W_OUT = 389.0, 0.245, 0.404
READS = {
    "mid": lambda ctx: 0.0067,
    "low": lambda ctx: 0.0057,
    "high": lambda ctx: 0.0076,
    "tiered": lambda ctx: 0.0048 if ctx <= 200_000 else 0.0067,
}
SUCC = (
    "self-recycle",
    "resumed by a deterministic",
    "predecessor",
    "handoff",
    "successor",
    "recycled",
    "continuation bridge",
    "HANDOFF-ENGAGE",
)
# reqs row layout
TS, AI, INP, CW, CR, OUT, TURN = range(7)


def cost(wr, inp, cw, cr, out, ctx):
    return (W_INP * inp + W_CW * cw + wr(ctx) * cr + W_OUT * out) / 1e6


def med(xs):
    return statistics.median(xs) if xs else 0


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p / 100.0 * len(xs)))] if xs else 0


def first_line_ts(path):
    from datetime import datetime

    try:
        with open(path, "rb") as fh:
            for n, line in enumerate(fh):
                if n > 50:
                    break
                i = line.find(b'"timestamp":"')
                if i >= 0:
                    s = line[i + 13 : i + 37].decode(errors="ignore").split('"')[0]
                    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except (OSError, ValueError):
        pass
    return None


# ── rows (W4 scan.py output) → cases ─────────────────────────────────────────────────────────────
def from_rows(rows_dir):
    """→ (cases, meta). Reads rows_<acct>.tsv{,.files,.jobs} and `window`, deduping and attributing
    exactly as W4 sim.py did. The re-prime sample reads each session's transcript first line (its
    start time), so it is measured here once and carried in meta."""
    with open(os.path.join(rows_dir, "window")) as fh:
        S, E = (float(x) for x in fh.read().split())
    files = {}
    for a in ACCTS:
        with open(os.path.join(rows_dir, "rows_%s.tsv.files" % a)) as fh:
            for line in fh:
                fi, mt, _sz, sid, closed, path, fp = (
                    line.rstrip("\n").split("\t", 6) + [""]
                )[:7]
                files[(a, int(fi))] = dict(
                    mtime=float(mt), sid=sid, closed=int(closed), path=path, fp=fp
                )
    occ = collections.defaultdict(list)
    for a in ACCTS:
        with open(os.path.join(rows_dir, "rows_%s.tsv" % a)) as fh:
            r = csv.reader(fh, delimiter="\t")
            next(r)
            for x in r:
                occ[x[4]].append((files[(a, int(x[1]))]["mtime"], a, x))
    n_rows = sum(len(v) for v in occ.values())
    # a request copied into another account's file is charged to the copy that stopped growing first
    sess = collections.defaultdict(list)
    sess_files = collections.defaultdict(set)
    for _req, v in occ.items():
        v.sort(key=lambda e: e[0])
        _mt, a, x = v[0]
        out = max(int(e[2][11]) for e in v)
        sess[x[2]].append(
            [
                float(x[3]),
                ACCTS.index(a),
                int(x[6]),
                int(x[7]),
                int(x[10]),
                out,
                int(x[12]),
            ]
        )
        for e in v:
            sess_files[x[2]].add((e[1], int(e[2][1])))
    for k in sess:
        sess[k].sort(key=lambda r: r[TS])
    jobs = collections.defaultdict(dict)
    for a in ACCTS:
        with open(os.path.join(rows_dir, "rows_%s.tsv.jobs" % a)) as fh:
            for line in fh:
                _fi, sid, tu, _nm, w, js, je = line.rstrip("\n").split("\t")
                if int(w) or not js:
                    continue
                jobs[sid][tu] = (float(js), float(je) if je else None)
    # the re-prime sample: first request of sessions that START inside the window
    first, fresh_t1, succ_t1 = [], [], []
    for k, L in sess.items():
        fl = [files[f] for f in sess_files[k]]
        starts = [s for s in (first_line_ts(f["path"]) for f in fl) if s is not None]
        if not starts or min(starts) < S + 600 or L[0][TS] - min(starts) > 3600:
            continue
        fp = " ".join(f["fp"] for f in fl).lower()
        t1 = [L[0]]
        for r in L[1:]:
            if r[TURN]:
                break
            t1.append(r)
        first.append(L[0][INP : OUT + 1])
        ctxs = [x[INP] + x[CW] + x[CR] for x in t1]
        (succ_t1 if any(p.lower() in fp for p in SUCC) else fresh_t1).append(
            ctxs[-1] - ctxs[0]
        )
    cases = []
    for k, L in sess.items():
        last = L[-1][TS]
        J = [
            [js, je if je is not None else last] for js, je in jobs.get(k, {}).values()
        ]
        cases.append(
            dict(
                case_id=k,
                sid=k,
                acct=ACCTS[L[0][AI]],
                E=E,
                closed=any(files[f]["closed"] for f in sess_files[k]),
                jobs=J,
                r=L,
            )
        )
    meta = dict(
        schema=2,
        flow="d1_recycle",
        source=rows_dir,
        start=S,
        end=E,
        window_s=E - S,
        rows=n_rows,
        unique_requests=len(occ),
        sessions=len(sess),
        first_reqs=first,
        reorient=max(0, med(succ_t1) - med(fresh_t1)),
    )
    meta.update(reprimes(first))
    return cases, meta


def reprimes(first):
    """The median re-prime and the measured p90 one (rp90.py: cw at its p90, ctx moved with it)."""
    rp = dict(
        inp=med([r[0] for r in first]),
        cw=med([r[1] for r in first]),
        cr=med([r[2] for r in first]),
        out=med([r[3] for r in first]),
    )
    rp["ctx"] = rp["inp"] + rp["cw"] + rp["cr"]
    cw90 = pct([r[1] for r in first], 90)
    return dict(rp_med=rp, rp_p90=dict(rp, cw=cw90, ctx=rp["ctx"] - rp["cw"] + cw90))


# ── the replay ───────────────────────────────────────────────────────────────────────────────────
def simulate(
    cases,
    rules,
    wr,
    rp=None,
    terminal=True,
    reorient=0,
    honor_busy=True,
    per_case=None,
    detail=None,
):
    """rules: [(K tokens, N minutes)], any one of which fires (the smallest N wins). rp: the
    re-prime, or None to read each case's own `rp` (flow cases carry it, so a split half is
    self-contained). → (base, new, nrec, term, per_sess, parts), per account index, in pp over the
    window. per_case, when a dict, receives {case_id: base − new} (the session's net saving);
    detail, when a dict, {case_id: (request indices that fired, terminal fired)}."""
    rules = sorted(rules, key=lambda kn: kn[1])

    def fires(J, ctx, idle_s, t0):
        for K, N in rules:
            if (
                idle_s >= N * 60
                and ctx >= K
                and not (honor_busy and any(js <= t0 + N * 60 < je for js, je in J))
            ):
                return N * 60
        return None

    base, new = collections.Counter(), collections.Counter()
    nrec, term = collections.Counter(), collections.Counter()
    parts = collections.Counter()
    per_sess = []
    for g in cases:
        J = g["jobs"]
        rq = rp if rp is not None else g["rp"]
        rp_ctx = rq["ctx"] + reorient
        fired, tfired = [], False
        rpc = cost(wr, rq["inp"], rq["cw"] + reorient, rq["cr"], rq["out"], rq["ctx"])
        off = 0
        prev = None
        n_here = 0
        b0, n0 = sum(base.values()), sum(new.values())
        for i, r in enumerate(g["r"]):
            a = r[AI]
            ctx = r[INP] + r[CW] + r[CR]
            bc = cost(wr, r[INP], r[CW], r[CR], r[OUT], ctx)
            base[a] += bc
            pctx = (prev[INP] + prev[CW] + prev[CR]) if prev is not None else 0
            if prev is not None and ctx < 0.6 * pctx:
                off = 0
            eff_prev = (pctx - off) if prev is not None else 0
            gap = (r[TS] - prev[TS]) if prev is not None else 0
            N_s = (
                fires(J, eff_prev, gap, prev[TS])
                if (prev is not None and r[TURN])
                else None
            )
            if N_s is not None:
                n_here += 1
                fired.append(i)
                c0 = new[a]
                nrec[a] += 1
                if N_s <= WARM_N:
                    new[a] += cost(wr, 0, HANDOFF_OUT, eff_prev, HANDOFF_OUT, eff_prev)
                else:
                    new[a] += cost(
                        wr, 0, eff_prev + HANDOFF_OUT, 0, HANDOFF_OUT, eff_prev
                    )
                new[a] += rpc
                rebuild = (gap - N_s) > TTL
                grow = min(max(0, ctx - pctx), r[CW] + r[INP])
                ctx_new = rp_ctx + grow
                cw = grow + (rp_ctx if rebuild else 0)
                cw = min(cw, ctx_new)
                cr = max(0, ctx_new - cw - r[INP])
                new[a] += cost(wr, r[INP], cw, cr, r[OUT], ctx_new)
                off = ctx - ctx_new
                parts["recycle_turn"] += bc - (new[a] - c0)
                parts["rebuild_avoided_n"] += int(r[CW] > 0.5 * ctx)
            elif off > 0:
                eff = max(1, ctx - off)
                cw = min(r[CW], eff)
                cr = max(0, eff - cw - r[INP])
                c1 = cost(wr, r[INP], cw, cr, r[OUT], eff)
                new[a] += c1
                parts["later_requests"] += bc - c1
            else:
                new[a] += bc
            prev = r
        if terminal and prev is not None:
            eff_last = prev[INP] + prev[CW] + prev[CR] - off
            N_s = (
                None if g["closed"] else fires(J, eff_last, g["E"] - prev[TS], prev[TS])
            )
            if N_s is not None:
                a = prev[AI]
                c0 = new[a]
                term[a] += 1
                n_here += 1
                tfired = True
                if N_s <= WARM_N:
                    new[a] += cost(wr, 0, HANDOFF_OUT, eff_last, HANDOFF_OUT, eff_last)
                else:
                    new[a] += cost(
                        wr, 0, eff_last + HANDOFF_OUT, 0, HANDOFF_OUT, eff_last
                    )
                new[a] += rpc
                parts["terminal"] -= new[a] - c0
        per_sess.append(n_here)
        if per_case is not None:
            per_case[g["case_id"]] = (sum(base.values()) - b0) - (
                sum(new.values()) - n0
            )
        if detail is not None:
            detail[g["case_id"]] = (fired, tfired)
    return base, new, nrec, term, per_sess, parts


def row(cases, meta, K, N, wname, rules=None, rp="rp_p90", **kw):
    """One grid row, shaped as W4 sim.json's: saved pp/week per account and in total, recycles."""
    base, new, nrec, term, per_sess, parts = simulate(
        cases,
        rules or [(K, N)],
        READS[wname],
        meta[rp] if isinstance(rp, str) else rp,
        **kw,
    )
    wk = 7.0 * 86400 / float(meta["window_s"])
    acct = {a: round((base[i] - new[i]) * wk, 2) for i, a in enumerate(ACCTS)}
    hit = [n for n in per_sess if n]
    return dict(
        K=K,
        N=N,
        weights=wname,
        saved_pp_week=acct,
        saved_pp_week_total=round(sum(acct.values()), 2),
        saved_pp_week_exact=sum((base[i] - new[i]) for i in range(len(ACCTS))) * wk,
        recycles_14d=sum(nrec.values()),
        terminal_recycles_14d=sum(term.values()),
        sessions=len(per_sess),
        sessions_recycled=len(hit),
        max_per_session=max(per_sess or [0]),
        parts_pp_week={
            p: (v if p.endswith("_n") else round(v * wk, 2)) for p, v in parts.items()
        },
    )


def write_cases(path, cases, meta):
    """A cases file whose FIRST line is {"_meta": meta}; gzip when the path ends in .gz."""
    import gzip

    op = gzip.open if path.endswith(".gz") else open
    tmp = path + ".tmp%d" % os.getpid()
    with op(tmp, "wt") as fh:
        fh.write(json.dumps({"_meta": meta}, separators=(",", ":")) + "\n")
        for g in cases:
            fh.write(json.dumps(g, separators=(",", ":")) + "\n")
    os.replace(tmp, path)


def read_cases(path):
    """→ (cases, meta) from write_cases output (gz or plain)."""
    import gzip

    op = gzip.open if path.endswith(".gz") else open
    meta, cases = None, []
    with op(path, "rt") as fh:
        for ln in fh:
            if not ln.strip():
                continue
            j = json.loads(ln)
            if meta is None and "_meta" in j:
                meta = j["_meta"]
            else:
                cases.append(j)
    if meta is None:
        raise ValueError("%s: no _meta header line" % path)
    return cases, meta
