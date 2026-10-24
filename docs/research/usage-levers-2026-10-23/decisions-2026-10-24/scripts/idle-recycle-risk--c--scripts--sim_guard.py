#!/usr/bin/env python3
# W4 simulation: what an EARLIER IDLE recycle would have saved over 14 days of main sessions.
# usage: python3 -I sim.py <rows_dir> [--json out.json]
# Reads rows_<acct>.tsv + .files written by scan.py. Prints the report tables; --json writes them.
#
# Model (one session = one sessionId, requests merged across accounts, deduped by requestId):
#   * A recycle point is a TURN-START request (a prompt or notification, never a tool_result) whose
#     gap from the previous request is >= N minutes, with the counterfactual context at that idle
#     point >= K tokens. Mid-turn gaps (a long tool call) are never recycle points, so a busy session
#     is never drained.
#   * At a recycle the predecessor spends one handoff request (a read of its context if the cache is
#     still warm at minute N, else a rewrite) plus HANDOFF_OUT output; the successor pays the measured
#     re-prime (first request of a fresh session: its write, read and output, medians); if the
#     successor then idles past the 1h cache TTL before the next prompt it rewrites its re-prime.
#   * After a recycle every later request in the session runs at context c - off, where
#     off = (original context at the turn start) - (re-prime + the turn's new tokens). Its new content
#     (cache write) is unchanged, capped by the smaller context; the rest is a read. A compaction in
#     the original (context drops below 60% of the previous request) resets off to 0.
#   * Terminal idle: a session whose last request sits at >= K, idle >= N before the window end, with
#     no self-close/recycle/exit mark in its tail, is charged one recycle with no benefit.
import collections
import csv
import json
import os
import statistics
import sys

rows_dir = sys.argv[1]
json_out = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
ACCTS = ["next", "next2", "next3", "next4"]
S, E = (float(x) for x in open(os.path.join(rows_dir, "window")).read().split())
DAYS = (E - S) / 86400.0
TTL = 3600  # main sessions write the 1h cache tier
WARM_N = 55 * 60  # a handoff turn at idle minute <= 55 still reads a warm cache
HANDOFF_OUT = 1500

# Weekly-meter weights, pp per Mtok (round 2 fit4 for input/write/output; round 3 probe for reads).
W_INP, W_CW, W_OUT = 389.0, 0.245, 0.404
READS = {
    "mid": lambda ctx: 0.0067,  # round 3 midpoint, measured at 459k context
    "low": lambda ctx: 0.0057,  # round 3 low end
    "high": lambda ctx: 0.0076,  # round 3 high end
    "tiered": lambda ctx: (
        0.0048 if ctx <= 200_000 else 0.0067
    ),  # long-context premium hypothesis
}


def cost(wr, inp, cw, cr, out, ctx):
    return (W_INP * inp + W_CW * cw + wr(ctx) * cr + W_OUT * out) / 1e6


# ---- load, dedupe, attribute ------------------------------------------------------------------
files = {}
for a in ACCTS:
    for line in open(os.path.join(rows_dir, "rows_%s.tsv.files" % a)):
        fi, mt, sz, sid, closed, path, fp = (line.rstrip("\n").split("\t", 6) + [""])[
            :7
        ]
        files[(a, int(fi))] = dict(
            mtime=float(mt), sid=sid, closed=int(closed), path=path, fp=fp
        )

occ = collections.defaultdict(list)  # req -> [(file mtime, acct, row)]
for a in ACCTS:
    with open(os.path.join(rows_dir, "rows_%s.tsv" % a)) as f:
        r = csv.reader(f, delimiter="\t")
        next(r)
        for x in r:
            fi = int(x[1])
            occ[x[4]].append((files[(a, fi)]["mtime"], a, x))
n_rows = sum(len(v) for v in occ.values())
n_dup = sum(1 for v in occ.values() if len(v) > 1)
n_dup_x = sum(1 for v in occ.values() if len(set(e[1] for e in v)) > 1)

# A request copied into another account's file (a session moved between accounts) is charged to the
# account whose copy stopped growing first: the original stops being written when the session moves.
sess = collections.defaultdict(list)
sess_files = collections.defaultdict(set)
for req, v in occ.items():
    v.sort(key=lambda e: e[0])
    mt, a, x = v[0]
    out = max(int(e[2][11]) for e in v)
    rec = dict(
        ts=float(x[3]),
        acct=a,
        inp=int(x[6]),
        cw=int(x[7]),
        cr=int(x[10]),
        out=out,
        turn=int(x[12]),
        model=x[5],
        req=x[4],
    )
    rec["ctx"] = rec["inp"] + rec["cw"] + rec["cr"]
    sess[x[2]].append(rec)
    for e in v:
        sess_files[x[2]].add((e[1], int(e[2][1])))
for k in sess:
    sess[k].sort(key=lambda r: r["ts"])

# Background jobs (scan.py .jobs): a non-watcher job running at idle minute N makes the session BUSY
# there — a recycle would kill it, and handoff-fire holds on it. cc-await-ping watchers and Monitors
# are wake mechanisms, not work, so they never block. A job with no notice runs to the session end.
jobs = collections.defaultdict(dict)
for a in ACCTS:
    for line in open(os.path.join(rows_dir, "rows_%s.tsv.jobs" % a)):
        fi, sid, tu, nm, w, js, je = line.rstrip("\n").split("\t")
        if int(w) or not js:
            continue
        jobs[sid][tu] = (float(js), float(je) if je else None)
JOBS = {}
for sid, d in jobs.items():
    last = sess[sid][-1]["ts"] if sess.get(sid) else float("inf")
    JOBS[sid] = [(js, je if je is not None else last) for js, je in d.values()]


def busy(sid, t):
    return any(js <= t < je for js, je in JOBS.get(sid, ()))


def first_line_ts(path):
    try:
        with open(path, "rb") as fh:
            for n, line in enumerate(fh):
                if n > 50:
                    break
                i = line.find(b'"timestamp":"')
                if i >= 0:
                    from datetime import datetime

                    s = line[i + 13 : i + 37].decode(errors="ignore").split('"')[0]
                    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except OSError:
        pass
    return None


# ---- re-prime measurement: first request of sessions that START inside the window -------------
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
fresh_first, succ_first, succ_turn1, fresh_turn1 = [], [], [], []
for k, L in sess.items():
    fl = [files[f] for f in sess_files[k]]
    starts = [first_line_ts(f["path"]) for f in fl]
    starts = [s for s in starts if s is not None]
    if not starts or min(starts) < S + 600 or L[0]["ts"] - min(starts) > 3600:
        continue
    fp = " ".join(f["fp"] for f in fl)
    is_succ = any(p.lower() in fp.lower() for p in SUCC)
    t1 = [L[0]]
    for r in L[1:]:
        if r["turn"]:
            break
        t1.append(r)
    (succ_first if is_succ else fresh_first).append(L[0])
    (succ_turn1 if is_succ else fresh_turn1).append(t1)


def med(xs):
    return statistics.median(xs) if xs else 0


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p / 100.0 * len(xs)))] if xs else 0


allfirst = fresh_first + succ_first
RP = dict(
    inp=med([r["inp"] for r in allfirst]),
    cw=med([r["cw"] for r in allfirst]),
    cr=med([r["cr"] for r in allfirst]),
    out=med([r["out"] for r in allfirst]),
)
RP["ctx"] = RP["inp"] + RP["cw"] + RP["cr"]
# Re-orientation surcharge (variant): how much more a successor's first turn grows than a fresh one's.
g_s = med([t[-1]["ctx"] - t[0]["ctx"] for t in succ_turn1])
g_f = med([t[-1]["ctx"] - t[0]["ctx"] for t in fresh_turn1])
REORIENT = max(0, g_s - g_f)


# ---- the policy simulation ---------------------------------------------------------------------
def simulate(rules, wr, terminal=True, reorient=0, rp=RP, honor_busy=True):
    """rules: [(K tokens, N minutes)], any one of which fires (the one with the smallest N wins).
    Return per-account base/new cost (pp over the window) and recycle counts."""
    rules = sorted(rules, key=lambda kn: kn[1])

    def fires(sid, ctx, idle_s, t0):
        for K, N in rules:
            if idle_s >= N * 60 and ctx >= K and not (honor_busy and busy(sid, t0 + N * 60)):
                return N * 60
        return None

    base = collections.Counter()
    new = collections.Counter()
    nrec = collections.Counter()
    term = collections.Counter()
    per_sess = []
    parts = collections.Counter()
    rp_cost = lambda a: cost(
        wr, rp["inp"], rp["cw"] + reorient, rp["cr"], rp["out"], rp["ctx"]
    )
    for k, L in sess.items():
        off = 0
        prev = None
        n_here = 0
        for r in L:
            a = r["acct"]
            bc = cost(wr, r["inp"], r["cw"], r["cr"], r["out"], r["ctx"])
            base[a] += bc
            if prev is not None and r["ctx"] < 0.6 * prev["ctx"]:
                off = 0
            eff_prev = (prev["ctx"] - off) if prev is not None else 0
            gap = (r["ts"] - prev["ts"]) if prev is not None else 0
            N_s = fires(k, eff_prev, gap, prev["ts"]) if (prev is not None and r["turn"] and prev["req"] not in BLOCK) else None
            if N_s is not None:
                n_here += 1
                c0 = new[a]
                nrec[a] += 1
                # predecessor's handoff turn at idle minute N
                if N_s <= WARM_N:
                    new[a] += cost(wr, 0, HANDOFF_OUT, eff_prev, HANDOFF_OUT, eff_prev)
                else:
                    new[a] += cost(
                        wr, 0, eff_prev + HANDOFF_OUT, 0, HANDOFF_OUT, eff_prev
                    )
                new[a] += rp_cost(a)
                rebuild = (gap - N_s) > TTL
                grow = min(max(0, r["ctx"] - prev["ctx"]), r["cw"] + r["inp"])
                ctx_new = rp["ctx"] + reorient + grow
                cw = grow + (rp["ctx"] + reorient if rebuild else 0)
                cw = min(cw, ctx_new)
                cr = max(0, ctx_new - cw - r["inp"])
                new[a] += cost(wr, r["inp"], cw, cr, r["out"], ctx_new)
                off = r["ctx"] - ctx_new
                parts["recycle_turn"] += bc - (new[a] - c0)
                parts["rebuild_avoided_n"] += int(r["cw"] > 0.5 * r["ctx"])
            elif off > 0:
                eff = max(1, r["ctx"] - off)
                cw = min(r["cw"], eff)
                cr = max(0, eff - cw - r["inp"])
                c1 = cost(wr, r["inp"], cw, cr, r["out"], eff)
                new[a] += c1
                parts["later_requests"] += bc - c1
            else:
                new[a] += bc
            prev = r
        if terminal and prev is not None:
            eff_last = prev["ctx"] - off
            closed = any(files[f]["closed"] for f in sess_files[k])
            N_s = None if (closed or prev["req"] in BLOCK) else fires(k, eff_last, E - prev["ts"], prev["ts"])
            if N_s is not None:
                a = prev["acct"]
                c0 = new[a]
                term[a] += 1
                n_here += 1
                if N_s <= WARM_N:
                    new[a] += cost(wr, 0, HANDOFF_OUT, eff_last, HANDOFF_OUT, eff_last)
                else:
                    new[a] += cost(
                        wr, 0, eff_last + HANDOFF_OUT, 0, HANDOFF_OUT, eff_last
                    )
                new[a] += rp_cost(a)
                parts["terminal"] -= new[a] - c0
        per_sess.append(n_here)
    return base, new, nrec, term, per_sess, parts


def row(K, N, wname, rules=None, **kw):
    base, new, nrec, term, per_sess, parts = simulate(rules or [(K, N)], READS[wname], **kw)
    wk = 7.0 / DAYS
    acct = {a: round((base[a] - new[a]) * wk, 2) for a in ACCTS}
    hit = [n for n in per_sess if n]
    return dict(
        K=K,
        N=N,
        weights=wname,
        saved_pp_week=acct,
        saved_pp_week_total=round(sum(acct.values()), 2),
        base_main_pp_week={a: round(base[a] * wk, 1) for a in ACCTS},
        recycles_14d=sum(nrec.values()),
        terminal_recycles_14d=sum(term.values()),
        sessions=len(per_sess),
        sessions_recycled=len(hit),
        extra_recycles_per_session=round(sum(per_sess) / max(1, len(per_sess)), 3),
        extra_recycles_per_recycled_session_median=med(hit),
        max_per_session=max(per_sess or [0]),
        parts_pp_week={
            p: (v if p.endswith("_n") else round(v * wk, 2)) for p, v in parts.items()
        },
    )


BLOCK = set()
if False:
    out = dict(
        window=dict(start=S, end=E, days=round(DAYS, 2)),
        dedupe=dict(
            rows=n_rows,
            unique_requests=len(occ),
            dup_requests=n_dup,
            dup_across_accounts=n_dup_x,
            sessions=len(sess),
        ),
        reprime=dict(
            sessions_started_in_window=len(allfirst),
            successors=len(succ_first),
            first_request_median=RP,
            first_request_ctx_p90=pct([r["ctx"] for r in allfirst], 90),
            first_request_cw_p90=pct([r["cw"] for r in allfirst], 90),
            first_turn_growth_median=dict(successor=g_s, fresh=g_f),
            reorient_surcharge_tokens=REORIENT,
        ),
    )
    print(
        "window %.1f days; %d rows -> %d unique requests (%d in >1 file, %d across accounts); %d sessions"
        % (DAYS, n_rows, len(occ), n_dup, n_dup_x, len(sess))
    )
    print(
        "re-prime (median first request of %d sessions started in window): %s; p90 ctx %d"
        % (len(allfirst), RP, out["reprime"]["first_request_ctx_p90"])
    )
    print(
        "first-turn growth median: successor %d, fresh %d -> re-orientation surcharge %d tokens"
        % (g_s, g_f, REORIENT)
    )

    # idle-point census: how much main-session context sits at turn starts after an idle gap
    cen = collections.Counter()
    for L in sess.values():
        for p, r in zip(L, L[1:]):
            if r["turn"]:
                g = (r["ts"] - p["ts"]) / 60
                for K in (100_000, 150_000, 200_000, 250_000, 350_000):
                    for N in (5, 15, 30, 45, 55, 60, 120):
                        if p["ctx"] >= K and g >= N:
                            cen[(K, N)] += 1
    out["idle_points_14d"] = {
        "%dk/%dm" % (K // 1000, N): v for (K, N), v in sorted(cen.items())
    }

    grid = []
    for wname in ("mid", "low", "high", "tiered"):
        for K in (100_000, 150_000, 200_000, 250_000, 350_000):
            for N in (5, 15, 30, 45, 55, 60, 120):
                grid.append(row(K, N, wname))
    out["grid"] = grid
    best = max(
        (g for g in grid if g["weights"] == "mid"),
        key=lambda g: g["saved_pp_week_total"],
    )
    out["best_mid"] = best
    # THE CANDIDATE. Two rules the token price cannot see decide it. (1) N >= 15: the rails already
    # hold a recycle for 15 min after an interactive turn (boundary-handoff CONV_S=900) so a live
    # exchange is never cut; a 5-minute pause is usually the operator reading. (2) Every recycle risks
    # work the successor must redo, which no transcript prices, so among candidates within 5% of the
    # best saving take the one with the FEWEST recycles.
    pool = [g for g in grid if g["weights"] == "mid" and g["N"] >= 15]
    top = max(g["saved_pp_week_total"] for g in pool)
    cand = min((g for g in pool if g["saved_pp_week_total"] >= 0.95 * top),
               key=lambda g: (g["recycles_14d"] + g["terminal_recycles_14d"], -g["saved_pp_week_total"]))
    bK, bN = cand["K"], cand["N"]
    out["candidate"] = cand
    out["candidate_by_weights"] = {w: row(bK, bN, w) for w in ("low", "mid", "high", "tiered")}
    out["best_variants"] = dict(
        no_terminal=row(bK, bN, "mid", terminal=False),
        ignore_busy=row(bK, bN, "mid", honor_busy=False),
        reorient=row(bK, bN, "mid", reorient=REORIENT),
        reprime_p90=row(
            bK,
            bN,
            "mid",
            rp=dict(
                RP,
                cw=out["reprime"]["first_request_cw_p90"],
                ctx=RP["ctx"] - RP["cw"] + out["reprime"]["first_request_cw_p90"],
            ),
        ),
    )
    # "current practice, fully applied": 35% of a 1M window after a 15 min conversation hold, and
    # 25% after an hour idle. The live rails already act on part of this, so the transcripts are the
    # baseline that "keep" stands for; this row says what the stated practice would add if every
    # session obeyed it.
    out["current_practice"] = {w: row(350_000, 15, w, rules=[(350_000, 15), (250_000, 60)])
                               for w in ("low", "mid", "high", "tiered")}

    print("\nidle points (turn starts after >= N min idle at >= K context), 14 days:")
    print("  " + "  ".join("%s=%d" % kv for kv in out["idle_points_14d"].items()))
    print(
        "\n%-7s %5s %4s %8s | %s | %7s %6s %6s %5s"
        % (
            "weights",
            "K",
            "N",
            "pp/wk",
            " ".join("%7s" % a for a in ACCTS),
            "recyc",
            "term",
            "/sess",
            "max",
        )
    )
    for g in grid:
        print(
            "%-7s %4dk %3dm %8.2f | %s | %7d %6d %6.3f %5d"
            % (
                g["weights"],
                g["K"] // 1000,
                g["N"],
                g["saved_pp_week_total"],
                " ".join("%7.2f" % g["saved_pp_week"][a] for a in ACCTS),
                g["recycles_14d"],
                g["terminal_recycles_14d"],
                g["extra_recycles_per_session"],
                g["max_per_session"],
            )
        )
    def line(label, v):
        print("  %-26s %6.2f pp/wk %s  recycles %d (+%d terminal), %.3f/session, max %d"
              % (label, v["saved_pp_week_total"], v["saved_pp_week"], v["recycles_14d"],
                 v["terminal_recycles_14d"], v["extra_recycles_per_session"], v["max_per_session"]))

    print("\nbaseline main-session pp/week (mid weights):", best["base_main_pp_week"])
    line("max saving (any N), mid", best)
    print("\nCANDIDATE K=%dk N=%dm (N>=15, fewest recycles within 5%% of the best):" % (bK // 1000, bN))
    for w, v in out["candidate_by_weights"].items():
        line("weights " + w, v)
    print("  parts (mid):", cand["parts_pp_week"])
    for n, v in out["best_variants"].items():
        line("variant " + n, v)
    print("\nCURRENT PRACTICE fully applied (350k after 15m, or 250k after 60m):")
    for w, v in out["current_practice"].items():
        line("weights " + w, v)
    if json_out:
        json.dump(out, open(json_out, "w"), indent=1)

if __name__ == "__main__":
    mode = sys.argv[2]
    if mode == "candidates":   # every turn-start gap >= N min (any context) and every terminal tail
        N, out_path = int(sys.argv[3]), sys.argv[4]
        with open(out_path, "w") as o:
            o.write("kind\tsid\tacct\tprev_ts\tprev_req\tnext_ts\tnext_req\tgap_s\tctx\tnext_turn\tpaths\n")
            for k, L in sess.items():
                ps = "|".join(sorted(files[f]["path"] for f in sess_files[k]))
                for p, r in zip(L, L[1:]):
                    if r["turn"] and r["ts"] - p["ts"] >= N * 60:
                        o.write("\t".join(str(x) for x in ("mid", k, p["acct"], p["ts"], p["req"], r["ts"], r["req"], r["ts"] - p["ts"], p["ctx"], r["turn"])) + "\t" + ps + "\n")
                p = L[-1]
                if E - p["ts"] >= N * 60:
                    o.write("\t".join(str(x) for x in ("terminal", k, p["acct"], p["ts"], p["req"], "", "", E - p["ts"], p["ctx"], "")) + "\t" + ps + "\n")
    else:                      # guard: python3 sim_guard.py rows K N blockfile
        K, N = int(sys.argv[3]), int(sys.argv[4])
        if len(sys.argv) > 5:
            BLOCK.update(x.strip() for x in open(sys.argv[5]) if x.strip())
        wk = 7.0 / DAYS
        for w in ("mid", "low", "high"):
            base, new, nrec, term, per_sess, parts = simulate([(K, N)], READS[w])
            print("weights=%s K=%d N=%d block=%d saved_pp_week=%.2f mid=%d terminal=%d" % (
                w, K, N, len(BLOCK), sum((base[a] - new[a]) * wk for a in ACCTS), sum(nrec.values()), sum(term.values())))
