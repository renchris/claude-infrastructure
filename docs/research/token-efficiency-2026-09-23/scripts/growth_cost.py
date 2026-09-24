#!/usr/bin/env python3
"""Persistence-weighted cost of everything appended to a context after its first response.

For every file (full population, and flagged for the stratified sample), responses are walked in
seq order. The items arriving before real response a occupy prompt positions [P(a-1), P(a)),
where P = input + cache_creation + cache_read (MEASURED). Their token total is the MEASURED delta
D = P(a) - P(a-1); it is split across the items with the chars->tokens ratios fitted by
growth_fit.py (ESTIMATED split, measured total). Thinking is not in the transcript (EXTRACT L3), but
the fit shows the whole assistant message incl. thinking is re-sent, so thinking = the response's
recorded output minus its visible text/tool-call tokens (when output is final) or the delta's
residual (when it is not).

Cost per token of a group = sum over every later response k >= a in the same file (xdup=0 readers
only) of: the overlap of [P(a-1),P(a)) with k's cache_read span [0,cr) at k's read price, with k's
cache_creation span [cr,cr+cc) at k's write price (its own 5m/1h mix), and with k's uncached span at
the input price. So the first reader normally writes it, later readers read it, and a cache miss
re-writes it: this is the exact billing of those prompt positions, not a model of it. Also priced
with every reader re-priced at Opus 5.5 ($4 in, 0.05x read, 1.25x/2x write).

Writes measure/growth_work/cost_by_source.json, top_items.json, per_file.tsv.
Usage: cd /tmp && nice -n 10 python3 <dir>/scripts/growth_cost.py
"""

import sqlite3, os, json, re, collections, heapq, numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DB = os.path.join(ROOT, "data", "extract.sqlite")
W = os.path.join(ROOT, "measure", "growth_work")
fit = json.load(open(os.path.join(W, "fit.json")))
B = {k: v[0] for k, v in fit["all"]["B_user_side"]["coef"].items()}
C = {k: v[0] for k, v in fit["all"]["C_assistant_side_no_thinking"]["coef"].items()}
RATIO = {
    "tr_read": B["tr_read"],
    "tr_bash": B["tr_bash"],
    "tr_web": B["tr_web"],
    "tr_mcp": B["tr_mcp"],
    "tr_other": B["tr_other"],
    "att": B["att"],
    "prompt": B["prompt"],
    "meta": B["meta"],
    "atext": C["atext"],
    "tui": C["tui"],
}
OVH = {
    "tool_result": max(0.0, B["n_tr"]),
    "attachment": 0.0,
    "user_prompt": max(0.0, B["n_up"]),
    "meta_user": max(0.0, B["n_up"]),
    "tool_use_input": C["n_tui"],
    "assistant_text": 0.0,
}
RESP_CONST = max(0.0, C["const"])

sample = set(l.split("\t")[0] for l in list(open(os.path.join(W, "sample.tsv")))[1:])
labels = {}
for l in open(os.path.join(W, "raw_labels.tsv")):
    a, b = l.rstrip("\n").split("\t")
    labels[a] = b

c = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
price = {
    m: (i, o, cr)
    for m, i, o, cr in c.execute(
        "select model,in_per_mtok,out_per_mtok,cr_mult from price"
    )
}
ctx = {
    f: (ct, ps, nr)
    for f, ct, ps, nr in c.execute(
        "select file, ctx_type, project_slug, n_resp from ctx"
    )
}


def tr_class(sub):
    if sub == "Read":
        return "tr_read"
    if sub == "Bash":
        return "tr_bash"
    if sub in ("WebFetch", "WebSearch"):
        return "tr_web"
    if sub.startswith("mcp__"):
        return "tr_mcp"
    return "tr_other"


def source(kind, sub, uid, tid):
    sub = sub or ""
    if kind in ("tool_result", "tool_use_input"):
        if sub.startswith("mcp__"):
            base = "mcp:" + sub.split("__")[1]
        else:
            base = sub
        if kind == "tool_result" and sub in ("Agent", "Workflow"):
            base = labels.get(tid, sub + ":unlabelled").replace(sub + ":", sub + ":")
        return kind + ":" + base
    if kind == "user_prompt":
        if sub == "task_notification":
            return "user_prompt:" + labels.get(uid.split("#")[0], "task_notification:?")
        return "user_prompt:" + sub
    if kind == "meta_user":
        return "meta_user:" + sub
    if kind == "attachment":
        return "attachment:" + sub
    return kind


def pred_tokens(kind, sub, chars, nimg, img_tok):
    ch = chars or 0
    if kind == "tool_result":
        t = RATIO[tr_class(sub or "")] * ch + OVH["tool_result"]
    elif kind == "attachment":
        t = RATIO["att"] * ch
    elif kind == "user_prompt":
        t = RATIO["prompt"] * ch + OVH["user_prompt"]
    elif kind == "meta_user":
        t = RATIO["meta"] * ch + OVH["meta_user"]
    elif kind == "tool_use_input":
        t = RATIO["tui"] * ch + OVH["tool_use_input"]
    elif kind == "assistant_text":
        t = RATIO["atext"] * ch
    else:
        t = 0.0
    return t + (nimg or 0) * img_tok


# ---- per-image tokens: from clean pairs whose only unexplained content is images (ESTIMATED)
IMG_TOK = 1022.0  # MEASURED median residual per image block over 3,889 clean groups (img_tok_measured_median)

agg = collections.defaultdict(
    lambda: collections.defaultdict(float)
)  # (scope, ctx, source) -> metrics
top = []  # heap of (cost, desc)
perfile = []
hooksig = collections.defaultdict(lambda: [0, 0.0, 0.0])
skillsz = collections.defaultdict(list)
img_resid = []
SIZED = {"tool_result:Bash", "tool_result:Read", "tool_result:WebFetch", "tool_use_input:Bash", "tool_use_input:Write"}
BUCKETS = [(1000, "<1k"), (5000, "1-5k"), (20000, "5-20k"), (50000, "20-50k"), (10**12, ">=50k")]
aggsz = collections.defaultdict(lambda: collections.defaultdict(float))
check = collections.Counter()

files = [r[0] for r in c.execute("select file from ctx order by file")]
for fi, f in enumerate(files):
    ct, proj, nresp = ctx[f]
    R = c.execute(
        """select seq, model, input_tokens, cc_5m, cc_1h, cache_read, xdup, output_tokens, output_final,
                     has_thinking from resp where file=? and model!='<synthetic>' and has_usage=1 order by seq""",
        (f,),
    ).fetchall()
    if not R:
        continue
    seqs = np.array([r[0] for r in R])
    n = len(R)
    inp = np.array([r[2] for r in R], float)
    c5 = np.array([r[3] for r in R], float)
    c1 = np.array([r[4] for r in R], float)
    cr = np.array([r[5] for r in R], float)
    cc = c5 + c1
    P = inp + cc + cr
    xd = np.array([r[6] for r in R])
    reader = xd == 0
    ip = np.array([price.get(r[1], (5, 25, 0.1))[0] for r in R]) / 1e6
    rp = ip * np.array([price.get(r[1], (5, 25, 0.1))[2] for r in R])
    wp = np.where(
        cc > 0,
        ip * (1.25 * c5 + 2.0 * c1) / np.maximum(cc, 1),
        ip * (2.0 if ct == "main" else 1.25),
    )
    ip55 = np.full(n, 4e-6)
    rp55 = np.full(n, 0.2e-6)
    wp55 = np.where(
        cc > 0,
        4e-6 * (1.25 * c5 + 2.0 * c1) / np.maximum(cc, 1),
        4e-6 * (2.0 if ct == "main" else 1.25),
    )

    # total input-side cost of xdup=0 readers, and the part in the initial prefix [0, P0)
    tot = float(((inp * ip + cc * wp + cr * rp) * reader).sum())
    tot55 = float(((inp * ip55 + cc * wp55 + cr * rp55) * reader).sum())

    items = c.execute(
        """select resp_before, kind, subkind, chars, n_images, uid, tool_use_id, detail, snippet, visible
                         from item where file=? and resp_before>=0 and visible=1 order by item_seq""",
        (f,),
    ).fetchall()
    arr = (
        np.searchsorted(seqs, [it[0] for it in items], side="right")
        if items
        else np.array([], int)
    )
    groups = collections.defaultdict(list)
    for it, a in zip(items, arr):
        groups[int(a)].append(it)

    def overlap(lo, hi, a0, b0):
        return np.clip(np.minimum(hi, b0) - np.maximum(lo, a0), 0, None)

    growth_cost = 0.0
    growth_cost55 = 0.0
    growth_tok = 0.0
    Rl = R
    # context-shrink events (P drops by >1000, e.g. server-side clearing of old tool results): start a
    # new segment; earlier groups stop being read there, and the surviving prefix [0, P(a)) is
    # charged once to 'context_rewrite_carryover' for the readers of the new segment
    drops = [a for a in range(1, n) if P[a] < P[a - 1] - 1000]
    seg_end = np.full(n, n)
    for a in range(n - 1, -1, -1):
        if a + 1 < n:
            seg_end[a] = a + 1 if (a + 1) in drops else seg_end[a + 1]
    check["shrink_events"] += len(drops)
    for a in drops:
        groups.setdefault(a, [])
    for a, its in sorted(groups.items()):
        if a >= n:  # after the last response: never re-sent
            for it in its:
                t = pred_tokens(it[1], it[2], it[3], it[4], IMG_TOK)
                s = source(it[1], it[2], it[5], it[6])
                g = agg[("all", ct, s)]
                g["tok_never_read"] += t
            continue
        if a == 0:  # arrived before the first in-window response: part of the initial prefix
            check["groups_before_first_resp"] += 1
            continue
        rewrite = a in drops
        lo = P[a - 1] if (a >= 1 and not rewrite) else 0.0
        hi = P[a]
        D = hi - lo
        prev = Rl[a - 1] if a >= 1 else None
        # predicted tokens per item
        preds = [pred_tokens(it[1], it[2], it[3], it[4], IMG_TOK) for it in its]
        kinds = [it[1] for it in its]
        vis_asst = sum(
            p for p, k in zip(preds, kinds) if k in ("assistant_text", "tool_use_input")
        ) + (RESP_CONST if prev else 0)
        user_pred = sum(
            p
            for p, k in zip(preds, kinds)
            if k not in ("assistant_text", "tool_use_input")
        )
        think = 0.0
        if D <= 0:
            scale_u = scale_a = 0.0
            think = 0.0
        elif rewrite:
            tot_pred = user_pred + vis_asst
            scale_u = scale_a = min(1.0, D / tot_pred) if tot_pred > 0 else 0.0
            think = 0.0
        elif prev is not None and prev[8] == 1 and prev[7] <= D:
            out = float(prev[7])
            think = max(0.0, out - vis_asst)
            scale_a = min(1.0, out / vis_asst) if vis_asst > 0 else 0.0
            scale_u = (D - out) / user_pred if user_pred > 0 else 0.0
            if user_pred <= 0:
                think += (
                    D - out
                )  # nothing to carry the rest: keep it in the assistant part
            check["groups_final"] += 1
            nimg = sum((it[4] or 0) for it in its)
            if nimg:
                img_resid.append(((D - out - (user_pred - nimg * IMG_TOK)) / nimg, nimg))
        else:
            rest = D - user_pred - vis_asst
            if rest >= 0:
                think = rest
                scale_u = scale_a = 1.0
            else:
                s = D / (user_pred + vis_asst) if (user_pred + vis_asst) > 0 else 0.0
                scale_u = scale_a = s
            check["groups_nonfinal"] += 1
        # per-token cost of this region, readers k >= a
        ks = np.arange(a, int(seg_end[a]))
        o_r = overlap(lo, hi, 0.0, cr[ks])
        o_w = overlap(lo, hi, cr[ks], cr[ks] + cc[ks])
        o_i = overlap(lo, hi, cr[ks] + cc[ks], P[ks])
        m = reader[ks]
        if D > 0:
            cw = float((o_w * wp[ks] * m).sum()) / D
            crd = float((o_r * rp[ks] * m).sum()) / D
            ci = float((o_i * ip[ks] * m).sum()) / D
            c55 = (
                float(((o_w * wp55[ks] + o_r * rp55[ks] + o_i * ip55[ks]) * m).sum())
                / D
            )
            nread = (
                float(((o_r + o_w + o_i) * m).sum()) / D
            )  # responses that carried it
        else:
            cw = crd = ci = c55 = nread = 0.0
        cpt = cw + crd + ci
        growth_cost += cpt * max(D, 0)
        growth_cost55 += c55 * max(D, 0)
        growth_tok += max(D, 0)
        entries = []
        for it, p in zip(its, preds):
            k = it[1]
            tok = p * (
                scale_a if k in ("assistant_text", "tool_use_input") else scale_u
            )
            entries.append((source(k, it[2], it[5], it[6]), tok, it))
        if rewrite and D > 0:
            entries.append(("context_rewrite_carryover", max(0.0, D - (user_pred + vis_asst) * scale_u), None))
        elif prev is not None and D > 0:
            entries.append(
                (
                    "assistant_thinking" if prev[9] else "residual_unattributed",
                    think,
                    None,
                )
            )
            entries.append(
                ("assistant_text", RESP_CONST * scale_a, None)
            )  # per-message framing
        for s, tok, it in entries:
            if tok <= 0:
                continue
            for scope in ("all", "sample") if f in sample else ("all",):
                g = agg[(scope, ct, s)]
                g["n"] += 1 if it is not None else 0
                g["tok"] += tok
                g["tok_reads"] += tok * nread
                g["usd"] += tok * cpt
                g["usd_w"] += tok * cw
                g["usd_r"] += tok * crd
                g["usd_i"] += tok * ci
                g["usd55"] += tok * c55
                if it is not None:
                    g["chars"] += it[3] or 0
            if it is not None and s in SIZED:
                ch = it[3] or 0
                bk = next(lab for lim, lab in BUCKETS if ch < lim)
                z = aggsz[(ct, s, bk)]
                z["n"] += 1; z["chars"] += ch; z["tok"] += tok; z["usd"] += tok * cpt; z["usd55"] += tok * c55
                if s == "tool_use_input:Bash":
                    m_cd = re.match(r'^\s*\{"command":\s*"(cd\s+("[^"]*"|\S+)\s*(&&|;)\s*)', it[7] and '{"command": "' + it[7] or "")
                    if m_cd:
                        cdl = len(m_cd.group(1)); z2 = aggsz[(ct, "bash_cd_prefix", "all")]
                        z2["n"] += 1; z2["chars"] += cdl; z2["tok"] += cdl * RATIO["tui"]; z2["usd"] += cdl * RATIO["tui"] * cpt; z2["usd55"] += cdl * RATIO["tui"] * c55
            if it is not None:
                cost = tok * cpt
                desc = {
                    "ctx": ct,
                    "source": s,
                    "detail": (it[7] or "")[:120],
                    "chars": it[3],
                    "tok": round(tok),
                    "readers": round(nread, 1),
                    "usd": round(cost, 3),
                    "usd55": round(tok * c55, 3),
                    "file": f.replace(os.path.expanduser("~"), "~"),
                }
                if len(top) < 60:
                    heapq.heappush(top, (cost, id(desc), desc))
                elif cost > top[0][0]:
                    heapq.heapreplace(top, (cost, id(desc), desc))
                if it[1] == "attachment" and (it[2] or "").startswith("hook_"):
                    sn = it[8] or ""
                    body = sn.split(": ", 1)[1] if ": " in sn else sn
                    sig = (
                        (it[2] or "")
                        + " | "
                        + re.sub(r"\d+", "#", body.strip()[:60]).replace("\n", " ")
                    )
                    h = hooksig[sig]
                    h[0] += 1
                    h[1] += tok
                    h[2] += cost
                if it[1] == "meta_user" and it[2] == "skill_body":
                    skillsz[labels.get((it[5] or "").split("#")[0], "skill:?")].append(
                        (it[3], tok, cost)
                    )
    # skill bodies loaded before the first response are part of the initial prefix: sizes only
    P0 = P[0]
    r0 = reader & (np.arange(n) < (drops[0] if drops else n))  # initial prefix lives until the first shrink
    init = float(
        (
            (
                np.minimum(cr, P0) * rp
                + overlap(0, P0, cr, cr + cc) * wp
                + overlap(0, P0, cr + cc, P) * ip
            )
            * r0
        ).sum()
    )
    init55 = float(
        (
            (
                np.minimum(cr, P0) * rp55
                + overlap(0, P0, cr, cr + cc) * wp55
                + overlap(0, P0, cr + cc, P) * ip55
            )
            * r0
        ).sum()
    )
    perfile.append(
        (
            f,
            ct,
            proj,
            nresp,
            int(f in sample),
            tot,
            init,
            growth_cost,
            tot55,
            init55,
            growth_cost55,
            growth_tok,
            float(P[-1]),
            float(P0),
            int(reader.sum()),
        )
    )
    check["files"] += 1

# initial-prefix skill bodies (resp_before = -1) for the size table
for f, uid, ch in c.execute(
    "select file, uid, chars from item where kind='meta_user' and subkind='skill_body' and xdup=0 and resp_before<0"
):
    skillsz[labels.get(uid.split("#")[0], "skill:?") + " (initial)"].append(
        (ch, RATIO["meta"] * ch, 0.0)
    )

out = {
    "ratios": RATIO,
    "overheads": OVH,
    "resp_const": RESP_CONST,
    "img_tok_assumed": IMG_TOK,
    "img_tok_measured_median": float(np.median([r for r, _ in img_resid])) if img_resid else None,
    "img_tok_measured_groups": len(img_resid),
    "check": check,
    "agg": [dict(scope=k[0], ctx=k[1], source=k[2], **v) for k, v in agg.items()],
}
json.dump(out, open(os.path.join(W, "cost_by_source.json"), "w"))
json.dump([dict(ctx=k[0], source=k[1], bucket=k[2], **v) for k, v in aggsz.items()], open(os.path.join(W, "cost_by_size.json"), "w"), indent=1)
json.dump(
    [d for _, _, d in sorted(top, key=lambda x: -x[0])],
    open(os.path.join(W, "top_items.json"), "w"),
    indent=1,
)
json.dump(
    {k: v for k, v in sorted(hooksig.items(), key=lambda kv: -kv[1][2])[:60]},
    open(os.path.join(W, "hook_signatures.json"), "w"),
    indent=1,
)
json.dump(
    {k: v for k, v in skillsz.items()}, open(os.path.join(W, "skill_bodies.json"), "w")
)
with open(os.path.join(W, "per_file.tsv"), "w") as fh:
    fh.write(
        "file\tctx\tproject\tn_resp\tsample\tusd_input_side\tusd_initial\tusd_growth\tusd55_input_side\tusd55_initial\tusd55_growth\tgrowth_tok\tP_last\tP0\tn_readers\n"
    )
    for r in perfile:
        fh.write("\t".join(map(str, r)) + "\n")
print(json.dumps(check))
