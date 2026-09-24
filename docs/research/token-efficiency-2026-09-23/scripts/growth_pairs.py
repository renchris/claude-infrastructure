#!/usr/bin/env python3
"""Build the per-pair growth dataset from extract.sqlite (read-only) and the stratified sample.

A "pair" is two consecutive real responses s, s+1 in one transcript file. Its prefix delta
D = P(s+1) - P(s), with P = input_tokens + cache_creation + cache_read (the whole prompt), is the
number of tokens appended between the two requests (MEASURED). The features are the model-visible
chars of the items appended in between (item.resp_before = s), split by content class.

Outputs (under ../measure/growth_work/):
  sample.tsv  - the stratified sample of files (ctx_type, size quartile, project)
  pairs.npz   - numpy arrays: one row per clean pair, all files (xdup=0 responses)

Usage: cd /tmp && nice -n 10 python3 <dir>/scripts/growth_pairs.py
"""

import sqlite3, os, collections, random, numpy as np, json

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DB = os.path.join(ROOT, "data", "extract.sqlite")
OUT = os.path.join(ROOT, "measure", "growth_work")
os.makedirs(OUT, exist_ok=True)

# content classes for the chars->tokens fit
CLASSES = [
    "tr_read",
    "tr_bash",
    "tr_web",
    "tr_mcp",
    "tr_other",
    "tui",
    "atext",
    "att_ttr",
    "att_other",
    "prompt",
    "meta",
]
COUNTS = ["n_tr", "n_tui", "n_att", "n_up"]


def item_class(kind, sub):
    if kind == "tool_result":
        if sub == "Read":
            return "tr_read"
        if sub == "Bash":
            return "tr_bash"
        if sub in ("WebFetch", "WebSearch"):
            return "tr_web"
        if sub.startswith("mcp__"):
            return "tr_mcp"
        return "tr_other"
    if kind == "tool_use_input":
        return "tui"
    if kind == "assistant_text":
        return "atext"
    if kind == "assistant_thinking":
        return None  # chars ~always 0 (EXTRACT L3)
    if kind == "attachment":
        return "att_ttr" if sub == "total_tokens_reminder" else "att_other"
    if kind == "user_prompt":
        return "prompt"
    if kind == "meta_user":
        return "meta"
    return None


def count_class(kind):
    return {
        "tool_result": "n_tr",
        "tool_use_input": "n_tui",
        "attachment": "n_att",
        "user_prompt": "n_up",
        "meta_user": "n_up",
    }.get(kind)


def pick_sample(c, per_type=60, seed=20260923):
    rng = random.Random(seed)
    rows = c.execute("""select file, ctx_type, project_slug, n_resp from ctx
                        where n_resp_xdup=0 and n_resp>=3""").fetchall()
    out = []
    for ct in ("main", "subagent", "workflow_agent"):
        fs = sorted([r for r in rows if r[1] == ct], key=lambda r: r[3])
        q = len(fs) // 4
        for qi in range(4):
            bucket = fs[qi * q : (qi + 1) * q] if qi < 3 else fs[3 * q :]
            byproj = collections.defaultdict(list)
            for r in bucket:
                byproj[r[2]].append(r)
            projs = list(byproj)
            rng.shuffle(projs)
            for p in projs:
                rng.shuffle(byproj[p])
            chosen = []
            while len(chosen) < per_type // 4 and any(byproj[p] for p in projs):
                for p in projs:
                    if byproj[p] and len(chosen) < per_type // 4:
                        chosen.append(byproj[p].pop())
            out += [(r[0], ct, qi, r[2], r[3]) for r in chosen]
    return out


def main():
    c = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
    sample = pick_sample(c)
    with open(os.path.join(OUT, "sample.tsv"), "w") as fh:
        fh.write("file\tctx_type\tsize_quartile\tproject\tn_resp\n")
        for r in sample:
            fh.write("\t".join(map(str, r)) + "\n")
    sset = {r[0] for r in sample}

    # items grouped by (file, resp_before), visible only
    feats = collections.defaultdict(lambda: collections.Counter())
    for f, rb, kind, sub, ch, nim in c.execute(
        "select file, resp_before, kind, subkind, chars, n_images from item where visible=1 and resp_before>=0"
    ):
        k = (f, rb)
        cl = item_class(kind, sub or "")
        if cl:
            feats[k][cl] += ch or 0
        cc = count_class(kind)
        if cc:
            feats[k][cc] += 1
        if nim:
            feats[k]["n_img"] += nim
        if kind == "user_prompt":
            feats[k]["has_prompt"] = 1
        if kind == "meta_user" and sub == "compact_summary":
            feats[k]["compact"] = 1

    ctxmap = dict(c.execute("select file, ctx_type from ctx"))
    rows = c.execute("""select file, seq, model, input_tokens+cc_total+cache_read, xdup, output_tokens,
                        output_final, has_thinking, text_chars, tool_input_chars, is_api_error, version
                        from resp order by file, seq""").fetchall()
    rec = collections.defaultdict(list)
    prev = None
    for r in rows:
        f, seq, model, P, x, out, fin, th, tch, tic, err, ver = r
        if (
            prev
            and prev[0] == f
            and prev[1] == seq - 1
            and model != "<synthetic>"
            and prev[2] != "<synthetic>"
            and x == 0
            and prev[4] == 0
            and not err
            and not prev[10]
        ):
            ft = feats.get((f, prev[1]), {})
            if ft.get("n_img") or ft.get("compact"):
                prev = r
                continue
            rec["D"].append(P - prev[3])
            rec["P0"].append(prev[3])
            for cl in CLASSES + COUNTS:
                rec[cl].append(ft.get(cl, 0))
            rec["has_prompt"].append(ft.get("has_prompt", 0))
            rec["out"].append(prev[5])
            rec["out_final"].append(prev[6])
            rec["think"].append(prev[7])
            rec["ctx"].append(["main", "subagent", "workflow_agent"].index(ctxmap[f]))
            rec["sample"].append(1 if f in sset else 0)
            rec["fileidx"].append(hash(f) & 0x7FFFFFFF)
            rec["v280"].append(1 if (prev[11] or "").startswith("2.1.280") else 0)
        prev = r
    np.savez_compressed(
        os.path.join(OUT, "pairs.npz"), **{k: np.array(v) for k, v in rec.items()}
    )
    n = len(rec["D"])
    print(
        json.dumps(
            {
                "pairs": n,
                "sample_files": len(sample),
                "sample_pairs": int(sum(rec["sample"])),
                "by_ctx_sample": collections.Counter(r[1] for r in sample),
            },
            default=str,
        )
    )


if __name__ == "__main__":
    main()
