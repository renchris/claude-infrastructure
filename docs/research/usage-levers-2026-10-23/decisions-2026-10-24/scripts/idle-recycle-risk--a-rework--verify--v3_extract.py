#!/usr/bin/env python3
# Verifier extraction. usage: python3 -I v3_extract.py <verify_dir> <nproc>
# For each recycle pair (vpairs.jsonl) and for idle-return points inside the same transcripts:
#  - CONTENT-OVERLAP rework: a successor tool result line (normalised, >=20 chars, Read line-number prefix
#    stripped) that already sat in the predecessor's context (since its last compaction, before the brief):
#    tool results, tool inputs (Write/Edit/Bash), assistant text, user text, attachments. Redundant chars of a
#    result = its chars x (matched long-line chars / long-line chars). Tokens = chars/4 (ESTIMATE).
#  - IDLE-RETURN CONTROL: in every transcript of the pair set, each turn start after >=900 s idle at >=150k
#    context (no recycle happened): the same measure for the next N requests against the session's OWN
#    context since its last compaction. This is the counterfactual "the session simply continued".
#  - Turn 1 of the successor (requests before the first later user message), its growth and whether it edited.
#  - Subagent transcripts (<sid>/subagents/**) whose first record falls inside the measured window, priced.
# Output: v3.pairs.jsonl, v3.idle.jsonl
import glob, json, os, re, sys
from datetime import datetime
from multiprocessing import Pool

V = sys.argv[1]
NPROC = int(sys.argv[2]) if len(sys.argv) > 2 else 6
WINS = (10, 30)
LN = re.compile(r"^\s*\d+[\t→]")
WS = re.compile(r"\s+")


def ep(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def norm_lines(t):
    for raw in t.split("\n"):
        x = WS.sub(" ", LN.sub("", raw)).strip()
        if len(x) >= 20:
            yield raw, hash(x)


def text_of(c):
    if isinstance(c, list):
        out = []
        for b in c:
            if isinstance(b, dict):
                if b.get("type") == "text":
                    out.append(b.get("text", ""))
                elif b.get("type") == "image":
                    out.append("\x00" * 6000)
                elif b.get("type") == "tool_reference":
                    out.append(str(b))
        return "\n".join(out)
    return c if isinstance(c, str) else ""


def parse(path):
    reqs, idx, results, prompts, compacts, events = [], {}, {}, [], [], []
    with open(path, "rb") as fh:
        for line in fh:
            if b'"isSidechain":true' in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            t = r.get("type")
            if t == "system" and r.get("subtype") == "compact_boundary":
                compacts.append(len(reqs))
                continue
            if t == "attachment":
                events.append((len(reqs), json.dumps(r.get("attachment"))[:200000]))
                continue
            if t == "user":
                if r.get("isCompactSummary"):
                    compacts.append(len(reqs))
                    continue
                c = (r.get("message") or {}).get("content")
                if isinstance(c, list) and any(
                    isinstance(b, dict) and b.get("type") == "tool_result" for b in c
                ):
                    for b in c:
                        if isinstance(b, dict) and b.get("type") == "tool_result":
                            tx = text_of(b.get("content"))
                            results[b.get("tool_use_id")] = (
                                tx,
                                bool(b.get("is_error")),
                                len(reqs),
                            )
                            events.append((len(reqs), tx))
                    continue
                tx = text_of(c)
                if tx:
                    events.append((len(reqs), tx))
                    if not r.get("isMeta"):
                        prompts.append((r.get("timestamp"), len(reqs), tx[:160]))
                continue
            if t != "assistant":
                continue
            m = r.get("message") or {}
            if m.get("model") == "<synthetic>" or r.get("isApiErrorMessage"):
                continue
            u = m.get("usage") or {}
            k = r.get("requestId") or m.get("id") or r.get("uuid")
            if k not in idx:
                idx[k] = len(reqs)
                inp, cw, cr = (
                    u.get("input_tokens") or 0,
                    u.get("cache_creation_input_tokens") or 0,
                    u.get("cache_read_input_tokens") or 0,
                )
                reqs.append(
                    dict(
                        ts=r.get("timestamp"),
                        inp=inp,
                        cw=cw,
                        cr=cr,
                        out=0,
                        ctx=inp + cw + cr,
                        tools=[],
                    )
                )
            q = reqs[idx[k]]
            q["out"] = max(q["out"], u.get("output_tokens") or 0)
            for b in m.get("content") or []:
                if not isinstance(b, dict):
                    continue
                if b.get("type") == "tool_use":
                    i = b.get("input") or {}
                    q["tools"].append((b.get("id"), b.get("name"), i))
                    s = ""
                    if b.get("name") == "Write":
                        s = str(i.get("content", ""))
                    elif b.get("name") == "Edit":
                        s = str(i.get("new_string", ""))
                    elif b.get("name") == "MultiEdit":
                        s = "\n".join(
                            str(e.get("new_string", "")) for e in i.get("edits") or []
                        )
                    elif b.get("name") == "Bash":
                        s = str(i.get("command", ""))
                    if s:
                        events.append((idx[k], s))
                elif b.get("type") == "text":
                    events.append((idx[k], b.get("text", "")))
    return dict(
        reqs=reqs, results=results, prompts=prompts, compacts=compacts, events=events
    )


def content_set(e, lo, hi):
    S = set()
    for ri, tx in e["events"]:
        if lo <= ri < hi:
            for _, h in norm_lines(tx):
                S.add(h)
    return S


def red_chars(tx, S):
    tot = mat = 0
    for raw, h in norm_lines(tx):
        tot += len(raw)
        if h in S:
            mat += len(raw)
    return len(tx) * (mat / tot) if tot else 0.0


def pol_point_after(e, start):
    """first turn-start index > start where the 150k/15m policy fires on the ACTUAL context; else None."""
    pr = {p[1] for p in e["prompts"]}
    R = e["reqs"]
    for i in range(start + 1, len(R)):
        if i in pr:
            a, b = ep(R[i - 1]["ts"]), ep(R[i]["ts"])
            if a and b and b - a >= 900 and R[i - 1]["ctx"] >= 150000:
                return i
    return None


def window_metrics(e, s, S, sub_dir=None):
    """requests s.. of e: per-request redundant tokens etc. Returns per-request lists for N=30 (caller slices)."""
    R = e["reqs"]
    comp = [c for c in e["compacts"] if c > s]
    end = min([len(R)] + comp)
    pp = pol_point_after(e, s)
    life_pol = min(end, pp) if pp else end
    per = []
    for i in range(s, min(len(R), s + max(WINS))):
        q = R[i]
        res_tok = red_tok = 0.0
        n_t = n_red_full = 0
        names = []
        for tid, nm, inp in q["tools"]:
            names.append(nm)
            r = e["results"].get(tid)
            if not r:
                continue
            n_t += 1
            ch = len(r[0])
            rc = red_chars(r[0], S)
            res_tok += ch / 4.0
            red_tok += rc / 4.0
            if ch and rc >= 0.9 * ch:
                n_red_full += 1
        per.append(
            dict(
                i=i,
                ts=q["ts"],
                ctx=q["ctx"],
                cr=q["cr"],
                cw=q["cw"],
                inp=q["inp"],
                out=q["out"],
                res_tok=res_tok,
                red_tok=red_tok,
                all_red=bool(n_t) and n_red_full == n_t,
                names=names,
            )
        )
    return dict(start=s, end=end, life_pol=life_pol, n_req=len(R), per=per)


def subagent_cost(sess_dir, t_lo, t_hi):
    """subagent transcripts under sess_dir whose first timestamp is in [t_lo, t_hi]: count + weighted cost (pp)."""
    n = 0
    pp = 0.0
    if not sess_dir or not os.path.isdir(sess_dir):
        return 0, 0.0
    for f in glob.glob(os.path.join(sess_dir, "**", "*.jsonl"), recursive=True):
        first = None
        seen = {}
        with open(f, "rb") as fh:
            for line in fh:
                if first is None:
                    j = line.find(b'"timestamp":"')
                    if j >= 0:
                        first = ep(line[j + 13 : j + 41].split(b'"')[0].decode())
                        if first is None or not (t_lo <= first <= t_hi):
                            break
                if b'"type":"assistant"' not in line or b'"usage"' not in line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                m = r.get("message") or {}
                u = m.get("usage") or {}
                k = r.get("requestId") or m.get("id")
                seen[k] = (
                    u.get("input_tokens") or 0,
                    u.get("cache_creation_input_tokens") or 0,
                    u.get("cache_read_input_tokens") or 0,
                    max(u.get("output_tokens") or 0, seen.get(k, (0, 0, 0, 0))[3]),
                )
        if first is not None and t_lo <= first <= t_hi:
            n += 1
            for inp, cw, cr, out in seen.values():
                pp += (389.0 * inp + 0.245 * cw + 0.0067 * cr + 0.404 * out) / 1e6
    return n, pp


def idle_points(e, skip_first=0):
    pr = {p[1] for p in e["prompts"]}
    R = e["reqs"]
    out = []
    for i in range(max(1, skip_first), len(R) - 1):
        if i in pr:
            a, b = ep(R[i - 1]["ts"]), ep(R[i]["ts"])
            if a and b and b - a >= 900 and R[i - 1]["ctx"] >= 150000:
                out.append(i)
    return out


def do_pair(p):
    try:
        s = parse(p["succ_path"])
        q = parse(p["pred_path"])
    except Exception as ex:
        return dict(err=str(ex), succ=p["succ"]), []
    cut = ep(p["brief_ts"]) or 1e18
    pend = len([r for r in q["reqs"] if (ep(r["ts"]) or 0) < cut])
    if pend == 0 or len(s["reqs"]) < 2:
        return dict(skip=True, succ=p["succ"]), []
    comp = [c for c in q["compacts"] if c <= pend]
    plo = comp[-1] if comp else 0
    S = content_set(q, plo, pend + 1)
    S50 = content_set(q, max(plo, pend - 50), pend + 1)
    w = window_metrics(s, 0, S)
    w50 = window_metrics(s, 0, S50)
    for a, b in zip(w["per"], w50["per"]):
        a["red50_tok"] = b["red_tok"]
    # turn 1 = requests before the first user message after the brief (prompts[0] is the brief itself)
    later = [x for x in s["prompts"] if x[1] > 0]
    t1_end = later[0][1] if later else len(s["reqs"])
    t1_next_gap = (
        (ep(later[0][0]) - ep(s["reqs"][t1_end - 1]["ts"]))
        if later and t1_end > 0
        else None
    )
    t1_edit = any(
        nm in ("Edit", "MultiEdit", "Write", "NotebookEdit")
        for r in s["reqs"][:t1_end]
        for _, nm, _ in r["tools"]
    )
    first_edit = next(
        (
            i
            for i, r in enumerate(s["reqs"])
            if any(
                nm in ("Edit", "MultiEdit", "Write", "NotebookEdit")
                for _, nm, _ in r["tools"]
            )
        ),
        None,
    )
    R = s["reqs"]
    sess_dir = os.path.join(os.path.dirname(p["succ_path"]), p["succ"], "subagents")
    sub = {}
    for N in WINS:
        hi = min(len(R), N) - 1
        sub[N] = subagent_cost(sess_dir, ep(R[0]["ts"]) - 1, ep(R[hi]["ts"]) + 1)
    # predecessor's idle gap before the turn in which it recycled
    ppr = [x for x in q["prompts"] if 0 < x[1] < pend]
    pgap = None
    if ppr:
        i = ppr[-1][1]
        pgap = (ep(q["reqs"][i]["ts"]) or 0) - (ep(q["reqs"][i - 1]["ts"]) or 0)
    row = dict(
        succ=p["succ"],
        pred=p["pred"],
        pred_ctx=q["reqs"][pend - 1]["ctx"],
        pred_gap=pgap,
        set_size=len(S),
        win=w,
        t1_end=t1_end,
        t1_next_gap=t1_next_gap,
        t1_edit=t1_edit,
        first_edit=first_edit,
        sub={str(k): v for k, v in sub.items()},
    )
    # idle-return controls inside both transcripts (successor: only after its first 30 requests)
    ctl = []
    for e, path, sid, skip in (
        (q, p["pred_path"], p["pred"], 0),
        (s, p["succ_path"], p["succ"], 30),
    ):
        for j in idle_points(e, skip):
            if path == p["pred_path"] and j >= pend:
                continue  # predecessor activity after the brief is not a no-recycle continuation
            comp = [c for c in e["compacts"] if c <= j]
            lo = comp[-1] if comp else 0
            Sj = content_set(e, lo, j)
            wj = window_metrics(e, j, Sj)
            sd = os.path.join(os.path.dirname(path), sid, "subagents")
            Rj = e["reqs"]
            subj = {}
            for N in WINS:
                hi = min(len(Rj), j + N) - 1
                subj[str(N)] = subagent_cost(
                    sd, ep(Rj[j]["ts"]) - 1, ep(Rj[hi]["ts"]) + 1
                )
            ctl.append(
                dict(
                    sid=sid,
                    j=j,
                    ctx_prev=e["reqs"][j - 1]["ctx"],
                    win=wj,
                    sub=subj,
                    role="pred" if e is q else "succ",
                )
            )
    return row, ctl


if __name__ == "__main__":
    P = [json.loads(l) for l in open(os.path.join(V, "vpairs.jsonl"))]
    P = [p for p in P if p.get("pred_path")]
    seen_ctl = set()
    with (
        Pool(NPROC) as pool,
        open(os.path.join(V, "v3.pairs.jsonl"), "w") as fo,
        open(os.path.join(V, "v3.idle.jsonl"), "w") as fc,
    ):
        for row, ctl in pool.imap_unordered(do_pair, P, chunksize=1):
            fo.write(json.dumps(row) + "\n")
            for c in ctl:
                k = (c["sid"], c["j"])
                if k in seen_ctl:
                    continue  # a session can be both a successor and a predecessor
                seen_ctl.add(k)
                fc.write(json.dumps(c) + "\n")
    sys.stderr.write("V3DONE pairs=%d idle_points=%d\n" % (len(P), len(seen_ctl)))
