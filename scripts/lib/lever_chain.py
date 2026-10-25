#!/usr/bin/env python3
"""lever_chain.py — D1's chain accounting (docs/plans/USAGE_LEVERS.md § W7+ §2 D1 "Metric", "Model
check", "Arm"; wave S8). Library only; bin/cc-lever-score scores D1 through it.

THE METRIC: net pp per treated recycle. A recycle at an idle point hands the predecessor's work to a
successor with a small context. What it saved is the successor's work priced at the context the
predecessor WOULD have carried, less what it actually cost:

  net = CF − ACT − wake − handoff − rework            (per read end lo/mid/hi)

  CF       the successor's main-thread requests within 24 h after its first turn, re-priced at the
           predecessor's projected context (project() below, on tools/lever-evals/d1_recycle/sim.py's
           own primitives: its cost(), READS, TTL, compaction and rebuild rules — the model the
           decision was made on; nothing of it is re-implemented here)
  ACT      the same requests at their actual price, PLUS the successor's whole first turn (the
           re-prime and the orientation, which the counterfactual never runs). The first turn is
           also reported split as reprime (up to the median fresh session's first turn) and
           orient_excess ("orientation beyond the median fresh session"), never subtracted twice
  wake     the predecessor's first request after the idle point (the turn the due time woke)
  handoff  the predecessor's remaining requests after it (the handoff turn writing the bridge)
  rework   the successor re-reading, within 24 h, files the predecessor had touched: Read results
           on those paths, tokens est. at 4 chars each, priced as cache writes

A turn is cut at the first inter-request gap of TURN_GAP_S or more (est.: the request index carries
no turn flag). The idle point is the D1 event's t − gap_s: the predecessor's last request before the
gap. Wave S12's treated recycle must therefore log its D1 event with turn_start = the due time and
gap_s = the idle seconds at it, which is the IRS row's existing shape.

THE MODEL CHECK, on CONTROL-arm would-recycle points (no recycle happened, so the continuation was
observed at full context): the continuation's requests within 24 h are re-priced by the same
project() from the event's ctx (ctx_at_idle, the context the lever decides on and the chain re-prices
with) plus their own growth, against their actual price. Σprojected / Σactual outside 1 ± 0.25 is
PLUMBING: the projection the treated arm is scored by does not hold where it can be seen.

LINEAGE: edges (predecessor → successor) are consecutive sessions of one lineage root in
lever-arms.jsonl's kind=session rows, the root S1's resolver wrote (env CC_LEVER_LINEAGE, then
lineage/<pane>.json, then the process cache, then the sid). Repair, offline: a session rooted at
itself whose pane held another session that went quiet within REPAIR_GAP_S before it started, and
whose first prompt carries a successor marker (sim.SUCC), is joined to that pane predecessor. Arms
of an edge must agree on >= 95% of edges, else PLUMBING — a repaired edge is exactly where they can
differ, since its successor hashed its own sid.
"""

import importlib.util
import json
import math
import os
import random
import statistics
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import lever_events as le  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    "lever_chain_d1_sim",
    os.path.join(REPO, "tools", "lever-evals", "d1_recycle", "sim.py"),
)
sim = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sim)

HORIZON_S = 86400
TURN_GAP_S = 120  # est.: a turn ends where the model stopped and waited
REPAIR_GAP_S = 1800
COMPACT = 0.6  # sim.simulate: a context below 60% of the previous request resets off
REBUILD = 0.5  # sim.simulate's rebuild_avoided_n: a write over half the context
CHARS_PER_TOKEN = 4  # est.
END_READS = {"lo": "low", "mid": "mid", "hi": "high"}
ENDS = ("lo", "mid", "hi")
TOUCH_KEYS = ("file_path", "path", "notebook_path")


def _wr(end):
    return sim.READS[END_READS[end]]


def ctx_of(q):
    return q[2] + q[3]


def is_main(q):
    return len(q) < 6 or bool(q[5])


def price(q, end):
    """A request's actual pp: uncached input folds into the write class, as lever_events prices it."""
    return sim.cost(_wr(end), 0, q[2], q[3], q[4], ctx_of(q))


def stream(reqs, sid, t0, t1):
    return [q for q in reqs.get(sid, ()) if is_main(q) and t0 <= q[0] < t1]


def split_turn(rs):
    """→ (first turn, the rest): the first turn ends at the first gap >= TURN_GAP_S."""
    for i in range(1, len(rs)):
        if rs[i][0] - rs[i - 1][0] >= TURN_GAP_S:
            return rs[:i], rs[i:]
    return list(rs), []


def project(rs, off, prev_t, prev_ctx, end):
    """Re-price a main-thread stream with its context shifted by `off` tokens (sim's rule, run the
    other way): the cache write is unchanged, capped by the context, and the rest is a read; a
    request after a gap past the cache TTL, or one that rewrote over half its context, rewrites the
    whole shifted context; a compaction resets the shift. → (projected pp, actual pp)."""
    proj = act = 0.0
    pt, pc = prev_t, prev_ctx
    for q in rs:
        c = ctx_of(q)
        if pc and c < COMPACT * pc:
            off = 0
        eff = max(1, c + off)
        if (pt is not None and q[0] - pt > sim.TTL) or q[2] > REBUILD * max(c, 1):
            cw, cr = eff, 0
        else:
            cw = min(q[2], eff)
            cr = max(0, eff - cw)
        proj += sim.cost(_wr(end), 0, cw, cr, q[4], eff)
        act += price(q, end)
        pt, pc = q[0], c
    return proj, act


# ── lineage ───────────────────────────────────────────────────────────────────────────────────
def _first_rows(arm_rows):
    first = {}
    for r in sorted(arm_rows, key=lambda r: r["_t"]):
        if r.get("kind") == "session" and isinstance(r.get("sid"), str) and r["sid"]:
            first.setdefault(r["sid"], r)
    return first


def _succ_marked(paths):
    """sim's successor detection: a SUCC phrase in the first 50 lines of the session's transcript."""
    for p in paths or ():
        try:
            with open(p, "rb") as fh:
                head = (
                    b"".join(line for _, line in zip(range(50), fh))
                    .decode("utf-8", "ignore")
                    .lower()
                )
        except OSError:
            continue
        if any(m.lower() in head for m in sim.SUCC):
            return True
    return False


def edges(arm_rows, sess, repair_gap_s=REPAIR_GAP_S):
    """→ [{pred, succ, src lineage|repair, lineage}] over the window's session stamps."""
    first = _first_rows(arm_rows)
    by_lin, by_pane = {}, {}
    for r in first.values():
        by_lin.setdefault(str(r.get("lineage") or r["sid"]), []).append(r)
        if r.get("pane"):
            by_pane.setdefault(str(r["pane"]), []).append(r)
    out = []
    for lin, rs in sorted(by_lin.items()):
        rs.sort(key=lambda r: (r["_t"], r["sid"]))
        for a, b in zip(rs, rs[1:]):
            out.append(
                {"pred": a["sid"], "succ": b["sid"], "src": "lineage", "lineage": lin}
            )
    succs = {e["succ"] for e in out}
    for pane, rs in sorted(by_pane.items()):
        rs.sort(key=lambda r: (r["_t"], r["sid"]))
        for i, b in enumerate(rs):
            if (
                b["sid"] in succs
                or b.get("lineage_src") != "self"
                or len(by_lin.get(b["sid"], ())) > 1
            ):
                continue
            for a in reversed(rs[:i]):
                last = (
                    le.parse_ts(((sess.get(a["sid"]) or {}).get("last_ts") or "") + "Z")
                    or a["_t"]
                )
                if 0 <= b["_t"] - last <= repair_gap_s:
                    if _succ_marked((sess.get(b["sid"]) or {}).get("main_paths")):
                        out.append(
                            {
                                "pred": a["sid"],
                                "succ": b["sid"],
                                "src": "repair",
                                "lineage": str(a.get("lineage") or a["sid"]),
                            }
                        )
                    break
    return out


def d1_arm(arms, sid):
    s = arms.session.get(sid) or {}
    a = ((s.get("arms") or {}).get("D1") or {}).get("arm")
    return "ctrl" if a == "holdback" else a


def arm_agreement(arms, eds):
    """→ (agreeing, comparable) edges: both ends carry a logged D1 arm."""
    x = n = 0
    for e in eds:
        a, b = d1_arm(arms, e["pred"]), d1_arm(arms, e["succ"])
        if a and b:
            n += 1
            x += a == b
    return x, n


# ── rework ────────────────────────────────────────────────────────────────────────────────────
def _tool_events(paths, t0=None, t1=None):
    """→ (touched paths, [(t, path, result chars)] for Read calls) from main-thread transcripts."""
    touched, reads, want = set(), [], {}
    for p in paths or ():
        try:
            fh = open(p, "rb")
        except OSError:
            continue
        with fh:
            for raw in fh:
                if b'"tool_use"' not in raw and b'"tool_result"' not in raw:
                    continue
                try:
                    x = json.loads(raw)
                except ValueError:
                    continue
                if not isinstance(x, dict) or x.get("isSidechain"):
                    continue
                t = le.parse_ts(x.get("timestamp"))
                if t is None or (t0 is not None and not t0 <= t < t1):
                    continue
                for b in (
                    ((x.get("message") or {}).get("content") or ())
                    if isinstance((x.get("message") or {}).get("content"), list)
                    else ()
                ):
                    if not isinstance(b, dict):
                        continue
                    if b.get("type") == "tool_use":
                        inp = b.get("input") or {}
                        fp = next(
                            (inp[k] for k in TOUCH_KEYS if isinstance(inp.get(k), str)),
                            None,
                        )
                        if fp:
                            touched.add(fp)
                            if b.get("name") == "Read":
                                want[b.get("id")] = (t, fp)
                    elif (
                        b.get("type") == "tool_result" and b.get("tool_use_id") in want
                    ):
                        c = b.get("content")
                        n = (
                            len(c)
                            if isinstance(c, str)
                            else sum(
                                len(z.get("text") or "")
                                for z in c
                                if isinstance(z, dict)
                            )
                            if isinstance(c, list)
                            else 0
                        )
                        tt, fp = want.pop(b["tool_use_id"])
                        reads.append((tt, fp, n))
    return touched, reads


def rework(pred_paths, succ_paths, t0, t1=None):
    """→ (tokens, pp): the successor's Reads of files the predecessor touched, t0 <= t < t1."""
    touched, _ = _tool_events(pred_paths)
    _, reads = _tool_events(succ_paths, t0, t1 if t1 is not None else t0 + HORIZON_S)
    tok = sum(n for _, fp, n in reads if fp in touched) // CHARS_PER_TOKEN
    return tok, tok * le.W_WRITE / 1e6


# ── the chain ─────────────────────────────────────────────────────────────────────────────────
def idle_point(e):
    g = e.get("gap_s")
    return e["t"] - (g if isinstance(g, (int, float)) and g > 0 else 0)


def fresh_first_turn(c, eds):
    """{end: median pp of a fresh session's first turn}: sessions that are their own lineage root,
    no edge's successor, and whose first main request falls 10 min or more inside the window."""
    succs = {e["succ"] for e in eds}
    vals = {end: [] for end in ENDS}
    for sid, rq in sorted(c["reqs"].items()):
        lin, _ = c["arms"].lineage(sid)
        if sid in succs or lin != sid:
            continue
        rs = [q for q in rq if is_main(q)]
        if not rs or rs[0][0] < c["since"] + 600:
            continue
        ft, _ = split_turn(rs)
        for end in ENDS:
            vals[end].append(sum(price(q, end) for q in ft))
    return {end: (statistics.median(v) if v else None) for end, v in vals.items()}


def recycle(c, e, succ, fresh, rework_fn=rework):
    """One treated recycle → {net: {end: pp}, parts…} or {missing: why}."""
    t_idle = idle_point(e)
    reqs, sess = c["reqs"], c["sess"]
    before = [q for q in reqs.get(e["sid"], ()) if is_main(q) and q[0] <= t_idle + 0.5]
    after = stream(reqs, e["sid"], t_idle + 0.5, t_idle + HORIZON_S)
    if succ is None:
        return {"missing": "no successor"}
    rs = stream(reqs, succ, t_idle, t_idle + HORIZON_S)
    if not rs:
        return {"missing": "successor made no request within 24 h"}
    rs = stream(
        reqs, succ, rs[0][0], rs[0][0] + HORIZON_S
    )  # 24 h from the successor's start
    first, rest = split_turn(rs)
    c0 = (
        e.get("ctx")
        if isinstance(e.get("ctx"), (int, float))
        else (ctx_of(before[-1]) if before else None)
    )
    if c0 is None:
        return {"missing": "no context at the idle point"}
    rtok, rpp = rework_fn(
        (sess.get(e["sid"]) or {}).get("main_paths"),
        (sess.get(succ) or {}).get("main_paths"),
        rs[0][0],
    )
    out = {
        "sid": e["sid"],
        "succ": succ,
        "lineage": e.get("lineage"),
        "acct": e.get("acct"),
        "t": e["t"],
        "c0": c0,
        "first_reqs": len(first),
        "rest_reqs": len(rest),
        "rework_tok": rtok,
        "net": {},
        "parts": {},
    }
    for end in ENDS:
        cf, act_rest = project(
            rest, c0 - ctx_of(first[-1]), t_idle, ctx_of(first[-1]), end
        )
        ft = sum(price(q, end) for q in first)
        wake = price(after[0], end) if after else 0.0
        hand = sum(price(q, end) for q in after[1:])
        fm = fresh.get(end)
        out["parts"][end] = {
            "cf": cf,
            "act": act_rest + ft,
            "first_turn": ft,
            "wake": wake,
            "handoff": hand,
            "rework": rpp,
            "reprime": min(ft, fm) if fm is not None else None,
            "orient_excess": max(0.0, ft - fm) if fm is not None else None,
        }
        out["net"][end] = cf - act_rest - ft - wake - hand - rpp
    return out


def treated_recycles(c, evs, eds, fresh, rework_fn=rework):
    """Treated would-recycle D1 events → per-recycle results. The successor is the first edge
    successor of the event's session whose first main request lands inside the 24 h after it."""
    succ_of = {}
    for e in eds:
        succ_of.setdefault(e["pred"], []).append(e["succ"])
    out = []
    for e in evs:
        if e["arm"] != "treat" or not e.get("would"):
            continue
        t_idle = idle_point(e)
        succ = None
        for s in succ_of.get(e["sid"], ()):
            if stream(c["reqs"], s, t_idle, t_idle + HORIZON_S):
                succ = s
                break
        r = recycle(c, e, succ, fresh, rework_fn)
        r.setdefault("sid", e["sid"])
        out.append(r)
    return out


def model_check(c, evs, tol=0.25, min_points=10, grace_s=5):
    """CONTROL-arm would-recycle points: the continuation re-priced from the event's ctx against its
    actual price. → {n, projected, actual, ratio, status pass|fail|no-data, detail}."""
    proj = act = 0.0
    n = skipped = 0
    for e in evs:
        if e["arm"] not in ("ctrl", "holdback") or not e.get("would"):
            continue
        rq = c["reqs"].get(e["sid"]) or ()
        before = [q for q in rq if is_main(q) and q[0] < e["t"] - grace_s]
        cont = stream(c["reqs"], e["sid"], e["t"] - grace_s, e["t"] + HORIZON_S)
        if not before or not cont:
            skipped += 1
            continue
        prev = before[-1]
        c0 = e.get("ctx") if isinstance(e.get("ctx"), (int, float)) else ctx_of(prev)
        p, a = project(cont, c0 - ctx_of(prev), prev[0], ctx_of(prev), "mid")
        proj += p
        act += a
        n += 1
    res = {
        "n": n,
        "skipped": skipped,
        "projected": round(proj, 6),
        "actual": round(act, 6),
        "ratio": None,
    }
    if n < min_points or act <= 0:
        res.update(
            status="no-data",
            detail="%d control would-recycle point(s) with a continuation "
            "(needs %d), %d without" % (n, min_points, skipped),
        )
        return res
    r = proj / act
    res["ratio"] = round(r, 4)
    res.update(
        status="pass" if abs(r - 1) <= tol else "fail",
        detail="projected %.3f / actual %.3f pp = %.3f over %d point(s) (tolerance ±%d%%)"
        % (proj, act, r, n, round(100 * tol)),
    )
    return res


def mean_ci(rows, reps=2000, seed=0):
    """Mean of `value` with sessions (clusters) resampled whole inside their account stratum.
    rows (stratum, cluster, value) → (mean, sd, n) or None."""
    st = {}
    for s, cl, v in rows:
        x = st.setdefault(s, {}).setdefault(cl, [0.0, 0])
        x[0] += v
        x[1] += 1
    cs = {s: [v[k] for k in sorted(v)] for s, v in sorted(st.items())}
    tot = sum(x[0] for v in cs.values() for x in v)
    n = sum(x[1] for v in cs.values() for x in v)
    if not n:
        return None
    rng = random.Random(seed)
    draws = []
    for _ in range(reps):
        a = b = 0.0
        for v in cs.values():
            k = len(v)
            for _j in range(k):
                x = v[rng.randrange(k)]
                a += x[0]
                b += x[1]
        if b:
            draws.append(a / b)
    m = sum(draws) / len(draws) if draws else 0.0
    sd = (
        math.sqrt(sum((d - m) ** 2 for d in draws) / (len(draws) - 1))
        if len(draws) > 1
        else 0.0
    )
    return tot / n, sd, n
