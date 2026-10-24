#!/usr/bin/env python3
# Option A noise floor: the MDE of the D3 / D4 event outcomes when the ARM is assigned per SESSION
# (hash of session id), not per event. Events of one session share an arm, so the A/A spread is
# inflated by within-session correlation (design effect). Reads the noise-floor key's data, read-only.
# usage: python3 -I cluster_mde.py <noise-floor data dir> [--d4]
# Method: A/A permutation. Each rep draws a fresh salt, assigns every session (D3: main sid; D4: the
# PARENT main sid of the subagent file) to T with probability p, computes the per-event mean outcome
# difference C-T times events/week (= pp/week fleet), per calendar week and pooled; MDE = 2.80 * SD.
# Same reps with the arm drawn per EVENT reproduce the noise-floor key's event-level numbers (control).
import json, math, os, random, re, sys
from collections import defaultdict
from datetime import datetime

D = sys.argv[1]
DO_D4 = "--d4" in sys.argv
S = 1790398800
E = S + 28 * 86400
WK = 7 * 86400
W_READ, W_WRITE, W_OUT = 0.0067, 0.245, 0.404
Z = 1.959964 + 0.841621
R = 400


def load_d3():
    seen = set()
    rows = defaultdict(list)
    for a in ["next", "next2", "next3", "next4"]:
        with open(os.path.join(D, a + ".req.tsv")) as fh:
            fh.readline()
            for line in fh:
                v = line.rstrip("\n").split("\t")
                if v[2] != "0" or v[5] in seen:
                    continue
                seen.add(v[5])
                inp, cc, cr, out, turn = (
                    int(v[7]),
                    int(v[8]),
                    int(v[10]),
                    int(v[11]),
                    int(v[12]),
                )
                wpp = ((inp + cc) * W_WRITE + cr * W_READ + out * W_OUT) / 1e6
                rows[v[3]].append((float(v[4]), inp + cc + cr, turn, wpp))
    ev = []  # (cluster, week, y, x)
    for sid, rs in rows.items():
        rs.sort()
        for i in range(1, len(rs)):
            ts, ctx, turn, wpp = rs[i]
            if ts < S or ts >= E or not turn:
                continue
            if ts - rs[i - 1][0] >= 3300:
                g = ts - rs[i - 1][0]
                ex = 1.0 if g >= 3600 else 0.0
                pc = rs[i - 1][1] / 1e6
                ev.append((sid, int((ts - S) // WK), wpp, (pc, pc * ex, ex)))
    return ev


POLL = re.compile(
    r"\b(until|while)\b[\s\S]{0,600}?\bsleep\b|select\(undef|time\.sleep\("
)


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def load_d4():
    seen_paths, seen_req, ev = set(), set(), []
    for a in ["next", "next2", "next3", "next4"]:
        with open(os.path.join(D, a + ".files.tsv")) as fh:
            hdr = fh.readline().rstrip("\n").split("\t")
            for line in fh:
                r = dict(zip(hdr, line.rstrip("\n").split("\t")))
                if r["is_sub"] != "1" or int(r["poll_loops"]) == 0:
                    continue
                tail = r["path"].split("/projects/")[1]
                if tail in seen_paths:
                    continue
                seen_paths.add(tail)
                reqs = []
                try:
                    f = open(r["path"], "rb")
                except OSError:
                    continue
                with f:
                    for l in f:
                        if b'"usage"' not in l or b'"assistant"' not in l[:1500]:
                            continue
                        try:
                            j = json.loads(l)
                        except Exception:
                            continue
                        m = j.get("message") or {}
                        u = m.get("usage")
                        if (
                            j.get("type") != "assistant"
                            or not isinstance(u, dict)
                            or m.get("model") == "<synthetic>"
                        ):
                            continue
                        rid = j.get("requestId") or m.get("id")
                        t = ep(j.get("timestamp", ""))
                        poll = any(
                            isinstance(b, dict)
                            and b.get("type") == "tool_use"
                            and b.get("name") == "Bash"
                            and POLL.search(
                                str((b.get("input") or {}).get("command", ""))
                            )
                            for b in m.get("content") or []
                        )
                        ctx = (
                            (u.get("input_tokens") or 0)
                            + (u.get("cache_creation_input_tokens") or 0)
                            + (u.get("cache_read_input_tokens") or 0)
                        )
                        if reqs and reqs[-1][4] == rid:
                            reqs[-1] = (
                                reqs[-1][0],
                                reqs[-1][1],
                                reqs[-1][2],
                                reqs[-1][3] or poll,
                                rid,
                            )
                            continue
                        reqs.append(
                            (
                                t,
                                ctx,
                                u.get("cache_creation_input_tokens") or 0,
                                poll,
                                rid,
                            )
                        )
                for i in range(len(reqs) - 1):
                    t, ctx, cc, poll, rid = reqs[i]
                    if not poll or t is None or t < S or t >= E or rid in seen_req:
                        continue
                    seen_req.add(rid)
                    t2, _, cc2, _, _ = reqs[i + 1]
                    if t2 is None:
                        continue
                    ev.append(
                        (
                            r["parent_sid"],
                            int((t - S) // WK),
                            cc2 * W_WRITE / 1e6,
                            (
                                ctx / 1e6,
                                ctx / 1e6 * (1.0 if t2 - t > 300 else 0.0),
                                1.0 if t2 - t > 300 else 0.0,
                            ),
                        )
                    )
    return ev


def cuped(ev):
    # multi-covariate OLS residual (x = (ctx, ctx*1[gap>=3600], 1[gap>=3600])), mean added back
    X = [e[3] for e in ev]
    y = [e[2] for e in ev]
    k = len(X[0]) + 1
    A = [[0.0] * k for _ in range(k)]
    b = [0.0] * k
    for xi, yi in zip(X, y):
        r = [1.0] + list(xi)
        for i in range(k):
            b[i] += r[i] * yi
            for j in range(k):
                A[i][j] += r[i] * r[j]
    M = [A[i] + [b[i]] for i in range(k)]
    for c in range(k):
        p = max(range(c, k), key=lambda r_: abs(M[r_][c]))
        M[c], M[p] = M[p], M[c]
        pv = M[c][c]
        if abs(pv) < 1e-18:
            continue
        M[c] = [v / pv for v in M[c]]
        for r_ in range(k):
            if r_ != c:
                f_ = M[r_][c]
                M[r_] = [v - f_ * w for v, w in zip(M[r_], M[c])]
    be = [M[i][k] for i in range(k)]
    my = sum(y) / len(y)
    res = [
        yi - (be[0] + sum(bj * xj for bj, xj in zip(be[1:], xi))) + my
        for xi, yi in zip(X, y)
    ]
    vy = sum((v - my) ** 2 for v in y) / (len(y) - 1)
    vr = sum((v - my) ** 2 for v in res) / (len(y) - k)
    print("  R2=%.3f" % (1 - vr / vy))
    return [(e[0], e[1], r, e[3]) for e, r in zip(ev, res)]


def aa(ev, p, by_session, seed=7):
    """→ dict weeks->MDE pp/week, from R A/A reps."""
    rng = random.Random(seed)
    nweek = defaultdict(int)
    for e in ev:
        nweek[e[1]] += 1
    weeks = sorted(w for w in nweek if 0 <= w < 4)
    per_wk = len(ev) / 4.0
    d1 = defaultdict(list)  # week -> deltas
    d2, d4 = [], []
    clusters = sorted({e[0] for e in ev})
    for _ in range(R):
        if by_session:
            arm = {c: rng.random() < p for c in clusters}
            isT = [arm[e[0]] for e in ev]
        else:
            isT = [rng.random() < p for _ in ev]
        acc = defaultdict(lambda: [0.0, 0, 0.0, 0])  # week -> sumT, nT, sumC, nC
        for e, t in zip(ev, isT):
            a = acc[e[1]]
            if t:
                a[0] += e[2]
                a[1] += 1
            else:
                a[2] += e[2]
                a[3] += 1

        def delta(ws):
            sT = sum(acc[w][0] for w in ws)
            nT = sum(acc[w][1] for w in ws)
            sC = sum(acc[w][2] for w in ws)
            nC = sum(acc[w][3] for w in ws)
            if not nT or not nC:
                return None
            return (sC / nC - sT / nT) * per_wk

        for w in weeks:
            x = delta([w])
            if x is not None:
                d1[w].append(x)
        for ws in ([0, 1], [2, 3]):
            x = delta(ws)
            if x is not None:
                d2.append(x)
        x = delta(weeks)
        if x is not None:
            d4.append(x)

    def sd(v):
        m = sum(v) / len(v)
        return math.sqrt(sum((a - m) ** 2 for a in v) / (len(v) - 1))

    v1 = sum(sd(d1[w]) ** 2 for w in weeks) / len(weeks)
    return {1: Z * math.sqrt(v1), 2: Z * sd(d2), 4: Z * sd(d4)}


def report(label, ev, expected):
    per_sess = defaultdict(int)
    for e in ev:
        per_sess[e[0]] += 1
    m = sorted(per_sess.values())
    print(
        "%s events_28d=%d per_week=%.0f sessions=%d events/session mean=%.1f p50=%d p90=%d max=%d expected=%s"
        % (
            label,
            len(ev),
            len(ev) / 4.0,
            len(m),
            sum(m) / len(m),
            m[len(m) // 2],
            m[int(0.9 * len(m))],
            m[-1],
            expected,
        )
    )
    adj = cuped(ev)
    for p in (0.5, 0.25):
        ev_r = aa(ev, p, False)
        se_r = aa(ev, p, True)
        se_a = aa(adj, p, True)
        for wk in (1, 2, 4):
            print(
                "  %s p_treat=%.2f weeks=%d MDE_pp/wk event-randomized=%.2f session-randomized=%.2f session+ctx-adj=%.2f deff=%.2f"
                % (
                    label,
                    p,
                    wk,
                    ev_r[wk],
                    se_r[wk],
                    se_a[wk],
                    (se_r[wk] / ev_r[wk]) ** 2,
                )
            )
    sys.stdout.flush()


# D3 skipped in this variant: D4 with the external-wait covariate (wait > 300 s) as an adjustability bound
if DO_D4:
    report(
        "D4 subagent poll-loop call -> next request cache write", load_d4(), "1.4-5.2"
    )
print("DONE")
