#!/usr/bin/env python3
# D4 event-level noise: each subagent Bash poll-loop call (POLL regex as scan.py) -> the next request in that
# file: wall gap from the calling request, its cache-write pp, and the calling request's context.
# Only subagent files with poll_loops > 0 in <acct>.files.tsv are reread; a request id already seen is skipped.
# usage: python3 -I d4events.py <data_dir>
import json, math, os, re, sys
from datetime import datetime
D = sys.argv[1]; S = 1790398800; E = S + 28 * 86400
Z = 1.959964 + 0.841621
POLL = re.compile(r"\b(until|while)\b[\s\S]{0,600}?\bsleep\b|select\(undef|time\.sleep\(")
def ep(s):
    try: return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception: return None
seen_paths = set(); ev = []; seen_req = set()
for a in ["next", "next2", "next3", "next4"]:
    with open(os.path.join(D, a + ".files.tsv")) as fh:
        hdr = fh.readline().rstrip("\n").split("\t")
        for line in fh:
            r = dict(zip(hdr, line.rstrip("\n").split("\t")))
            if r["is_sub"] != "1" or int(r["poll_loops"]) == 0: continue
            tail = r["path"].split("/projects/")[1]
            if tail in seen_paths: continue  # cross-account copy of the same subagent file
            seen_paths.add(tail)
            reqs = []  # (ts, ctx, cc, has_poll, reqid)
            with open(r["path"], "rb") as f:
                for l in f:
                    if b'"usage"' not in l or b'"assistant"' not in l[:1500]: continue
                    try: j = json.loads(l)
                    except Exception: continue
                    m = j.get("message") or {}; u = m.get("usage")
                    if j.get("type") != "assistant" or not isinstance(u, dict) or m.get("model") == "<synthetic>": continue
                    rid = j.get("requestId") or m.get("id")
                    t = ep(j.get("timestamp", ""))
                    poll = any(isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") == "Bash"
                               and POLL.search(str((b.get("input") or {}).get("command", ""))) for b in m.get("content") or [])
                    if reqs and reqs[-1][4] == rid:
                        reqs[-1] = (reqs[-1][0], reqs[-1][1], reqs[-1][2], reqs[-1][3] or poll, rid); continue
                    reqs.append((t, (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0) + (u.get("cache_read_input_tokens") or 0),
                                 u.get("cache_creation_input_tokens") or 0, poll, rid))
            for i in range(len(reqs) - 1):
                t, ctx, cc, poll, rid = reqs[i]
                if not poll or t is None or t < S or t >= E or rid in seen_req: continue
                seen_req.add(rid)
                t2, ctx2, cc2, _, _ = reqs[i + 1]
                if t2 is None: continue
                ev.append((t2 - t, ctx / 1e6, cc2 * 0.245 / 1e6))
n = len(ev); nw = n / 4
long_ = [e for e in ev if e[0] > 300]
print("poll-loop events n_28d=%d per_week=%.0f; gap>300s n_28d=%d per_week=%.0f" % (n, nw, len(long_), len(long_) / 4))
y = [e[2] for e in ev]; m = sum(y) / n; vy = sum((x - m) ** 2 for x in y) / (n - 1)
# regression on ctx * (gap>300) and ctx: pre-treatment ctx; the gap is itself what the deny changes, so the
# adjusted variant uses ctx only (pre-treatment) and ctx x (gap>300) as an upper bound on adjustability.
def resid(X, y):
    k = len(X[0]) + 1; A = [[0.0] * k for _ in range(k)]; b = [0.0] * k
    for xi, yi in zip(X, y):
        rr = [1.0] + list(xi)
        for i in range(k):
            b[i] += rr[i] * yi
            for j in range(k): A[i][j] += rr[i] * rr[j]
    M = [A[i] + [b[i]] for i in range(k)]
    for c in range(k):
        p = max(range(c, k), key=lambda r_: abs(M[r_][c])); M[c], M[p] = M[p], M[c]
        pv = M[c][c]
        if abs(pv) < 1e-18: continue
        M[c] = [x / pv for x in M[c]]
        for r_ in range(k):
            if r_ != c:
                f_ = M[r_][c]; M[r_] = [x - f_ * yy for x, yy in zip(M[r_], M[c])]
    be = [M[i][k] for i in range(k)]
    res = [yi - (be[0] + sum(bj * xj for bj, xj in zip(be[1:], xi))) for xi, yi in zip(X, y)]
    return sum(r_ * r_ for r_ in res) / (len(y) - k)
v_ctx = resid([(e[1],) for e in ev], y)
for wk in (1, 2, 4):
    nn = nw * wk
    f = lambda v: Z * math.sqrt(2 * v / (nn / 2)) * nw
    print("D4 weeks=%d mean_rebuild_pp=%.4f raw_MDE_pp/wk=%.2f ctx_adj_MDE_pp/wk=%.2f (R2=%.2f) expected=1.4-5.2" % (wk, m, f(vy), f(v_ctx), 1 - v_ctx / vy))
