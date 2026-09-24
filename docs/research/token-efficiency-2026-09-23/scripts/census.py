#!/usr/bin/env python3
"""Census: the fleet baseline by billing type (token-efficiency study, 2026-09-23).

Reads data/extract.sqlite (read-only), filters xdup=0, and writes measure/census.json.
measure/census.md is rendered from that JSON by render_census_md().

Every figure here is MEASURED from the extract (resp_priced view, item and ctx tables)
except output, which uses output_est (ESTIMATED for ~11% of responses; see EXTRACT.md L2).
Dollar figures are LIST-PRICE WEIGHTS (the fleet is billed by subscription quota).

Usage:  cd /tmp && nice -n 10 python3 <dir>/scripts/census.py
"""

import json, os, sqlite3, statistics, sys
from collections import defaultdict

D = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(D, "data", "extract.sqlite")
OUT_JSON = os.path.join(D, "measure", "census.json")
OUT_MD = os.path.join(D, "measure", "census.md")

# Billing classes: (label, token column, usd column at own model, usd formula at opus 5.5)
CLASSES = [
    ("uncached_input", "input_tokens", "usd_input", "input_tokens*4.0/1e6"),
    ("cache_write_5m", "cc_5m", "usd_cw5m", "cc_5m*4.0*1.25/1e6"),
    ("cache_write_1h", "cc_1h", "usd_cw1h", "cc_1h*4.0*2.0/1e6"),
    ("cache_read", "cache_read", "usd_cache_read", "cache_read*4.0*0.05/1e6"),
    ("output_est", "output_est", "usd_output_est", "output_est*20.0/1e6"),
]
# Human-or-fired prompt subkinds in a MAIN thread (excludes agent briefs, task/teammate/peer
# notifications and interrupts, which are machine-generated or not prompts).
HUMAN_PROMPT_SUBKINDS = ("plain", "command", "pasted", "bash_mode")


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    k = (len(xs) - 1) * p
    f = int(k)
    c = min(f + 1, len(xs) - 1)
    return xs[f] + (xs[c] - xs[f]) * (k - f)


def dist(xs):
    xs = list(xs)
    if not xs:
        return {}
    return {
        "n": len(xs),
        "mean": sum(xs) / len(xs),
        "median": pct(xs, 0.5),
        "p75": pct(xs, 0.75),
        "p90": pct(xs, 0.9),
        "p99": pct(xs, 0.99),
        "max": max(xs),
        "sum": sum(xs),
    }


def grouped(c, group_expr, where="1=1"):
    sel = ", ".join(
        f"SUM({tok}), SUM({usd}), SUM({o55})" for _, tok, usd, o55 in CLASSES
    )
    q = (
        f"SELECT {group_expr} AS g, COUNT(*), COUNT(DISTINCT file), {sel}, "
        f"SUM(usd_total), SUM(usd_total_at_opus55), SUM(output_tokens), SUM(output_est_method!='recorded') "
        f"FROM resp_priced WHERE xdup=0 AND {where} GROUP BY 1 ORDER BY SUM(usd_total) DESC"
    )
    out = {}
    for row in c.execute(q):
        g, n, nf = row[0], row[1], row[2]
        rest = row[3:]
        d = {
            "responses": n,
            "contexts": nf,
            "tokens": {},
            "usd": {},
            "usd_at_opus55": {},
        }
        for i, (lab, *_r) in enumerate(CLASSES):
            d["tokens"][lab] = rest[3 * i] or 0
            d["usd"][lab] = rest[3 * i + 1] or 0.0
            d["usd_at_opus55"][lab] = rest[3 * i + 2] or 0.0
        d["usd_total"] = rest[15] or 0.0
        d["usd_total_at_opus55"] = rest[16] or 0.0
        d["output_recorded_final"] = rest[17] or 0
        d["responses_output_imputed"] = rest[18] or 0
        t = d["tokens"]
        denom = (
            t["uncached_input"]
            + t["cache_write_5m"]
            + t["cache_write_1h"]
            + t["cache_read"]
        )
        d["cache_hit_rate"] = t["cache_read"] / denom if denom else None
        d["mean_prefix_tokens"] = denom / n if n else None
        d["usd_share"] = {
            k: (v / d["usd_total"] if d["usd_total"] else None)
            for k, v in d["usd"].items()
        }
        out[g if g is not None else "NULL"] = d
    return out


def main():
    c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    meta = (
        dict(c.execute("SELECT * FROM meta").fetchall())
        if c.execute("SELECT count(*) FROM sqlite_master WHERE name='meta'").fetchone()[
            0
        ]
        else {}
    )
    res = {
        "source": DB,
        "built_at": meta.get("built_at"),
        "since": meta.get("since"),
        "method": {
            "filter": "xdup=0 (cross-config-dir copies removed)",
            "output": "output_est (recorded final where present, stratified imputation otherwise; ESTIMATED for imputed rows)",
            "prices": "list-price weights from model-config.yaml pricing_per_mtok via extract price table; cache write 1.25x (5m) / 2x (1h); cache read cr_mult x input",
            "opus55_reprice": "same tokens at $4/$20, cache read 0.05x",
            "task": "session tree = main transcript + every subagent/workflow agent sharing its session_id",
            "human_prompts": "main-thread user_prompt items with subkind in "
            + ",".join(HUMAN_PROMPT_SUBKINDS),
        },
    }

    # 1. fleet totals
    res["fleet"] = grouped(c, "'all'")["all"]
    # 2. splits
    res["by_ctx_type"] = grouped(c, "ctx_type")
    res["by_model"] = grouped(c, "model")
    res["by_ctx_type_model"] = grouped(c, "ctx_type||' | '||model")
    res["main_by_entrypoint"] = grouped(
        c, "COALESCE(entrypoint,'NULL')", "ctx_type='main'"
    )
    # headless main sessions also spawn agents: split trees by the MAIN thread's entrypoint
    main_ep = {}
    for sid, ep in c.execute(
        "SELECT session_id, entrypoint FROM resp WHERE xdup=0 AND ctx_type='main' "
        "GROUP BY session_id, entrypoint ORDER BY COUNT(*)"
    ):
        main_ep[sid] = ep  # last = most frequent
    # 3. per task
    tree = defaultdict(
        lambda: {
            "usd": 0.0,
            "usd55": 0.0,
            "resp": 0,
            "files": set(),
            "worker_usd": 0.0,
            "cls": defaultdict(float),
            "project": None,
            "main_files": set(),
            "n_sub": 0,
            "n_wf": 0,
        }
    )
    q = (
        "SELECT session_id, ctx_type, file, project_slug, usd_total, usd_total_at_opus55, "
        "usd_input, usd_cw5m, usd_cw1h, usd_cache_read, usd_output_est FROM resp_priced WHERE xdup=0"
    )
    for sid, ct, f, proj, u, u55, ui, u5, u1, ucr, uo in c.execute(q):
        t = tree[sid]
        t["usd"] += u or 0
        t["usd55"] += u55 or 0
        t["resp"] += 1
        t["files"].add(f)
        if ct != "main":
            t["worker_usd"] += u or 0
        else:
            t["main_files"].add(f)
            t["project"] = proj
        for lab, v in zip([k for k, *_ in CLASSES], (ui, u5, u1, ucr, uo)):
            t["cls"][lab] += v or 0
    for sid, t in tree.items():
        if t["project"] is None:
            t["project"] = c.execute(
                "SELECT project_slug FROM resp WHERE session_id=? LIMIT 1", (sid,)
            ).fetchone()[0]
    # prompts per task
    hp = defaultdict(int)
    allp = defaultdict(int)
    q = (
        "SELECT r.session_id, i.subkind, COUNT(*) FROM item i JOIN ctx r ON r.file=i.file "
        "WHERE i.kind='user_prompt' AND i.xdup=0 AND r.ctx_type='main' GROUP BY 1,2"
    )
    for sid, sk, n in c.execute(q):
        allp[sid] += n
        if sk in HUMAN_PROMPT_SUBKINDS:
            hp[sid] += n
    trees = list(tree.items())
    tot = sum(t["usd"] for _, t in trees)
    per_task = {
        "n_tasks": len(trees),
        "usd_per_task": dist(t["usd"] for _, t in trees),
        "usd_per_task_at_opus55": dist(t["usd55"] for _, t in trees),
        "responses_per_task": dist(t["resp"] for _, t in trees),
        "contexts_per_task": dist(len(t["files"]) for _, t in trees),
        "human_prompts_per_task": dist(hp.get(s, 0) for s, _ in trees),
        "all_main_user_prompts_per_task": dist(allp.get(s, 0) for s, _ in trees),
        "tasks_with_zero_human_prompts_in_window": sum(
            1 for s, _ in trees if hp.get(s, 0) == 0
        ),
        "tasks_with_any_worker": sum(
            1 for _, t in trees if len(t["files"]) > len(t["main_files"])
        ),
        "worker_share_fleet": sum(t["worker_usd"] for _, t in trees) / tot,
        "worker_share_per_task": dist(
            t["worker_usd"] / t["usd"] for _, t in trees if t["usd"] > 0
        ),
        "worker_share_per_task_with_workers": dist(
            t["worker_usd"] / t["usd"]
            for _, t in trees
            if t["usd"] > 0 and len(t["files"]) > len(t["main_files"])
        ),
    }
    nhp = sum(hp.values())
    per_task["usd_per_human_prompt_fleet"] = tot / nhp if nhp else None
    per_task["usd_per_human_prompt_per_task"] = dist(
        t["usd"] / hp[s] for s, t in trees if hp.get(s, 0) > 0
    )
    per_task["total_human_prompts"] = nhp
    # concentration
    us = sorted((t["usd"] for _, t in trees), reverse=True)
    per_task["concentration"] = {
        f"top_{k}_share": sum(us[:k]) / tot for k in (1, 10, 15, 50, 100)
    }
    per_task["concentration"]["top_10pct_share"] = (
        sum(us[: max(1, len(us) // 10)]) / tot
    )
    # by main entrypoint
    by_ep = defaultdict(list)
    for s, t in trees:
        by_ep[main_ep.get(s) or "NULL"].append((s, t))
    per_task["by_main_entrypoint"] = {
        ep: {
            "n_tasks": len(v),
            "usd_total": sum(t["usd"] for _, t in v),
            "usd_per_task": dist(t["usd"] for _, t in v),
            "worker_share": (
                sum(t["worker_usd"] for _, t in v) / sum(t["usd"] for _, t in v)
            )
            if sum(t["usd"] for _, t in v)
            else None,
        }
        for ep, v in by_ep.items()
    }
    res["per_task"] = per_task
    # per-response prefix distribution by ctx_type (the context length re-read each turn)
    pref = {}
    for ct in ("main", "subagent", "workflow_agent"):
        xs = [
            r[0]
            for r in c.execute(
                "SELECT input_tokens+cc_total+cache_read FROM resp WHERE xdup=0 AND ctx_type=? AND model!='<synthetic>'",
                (ct,),
            )
        ]
        pref[ct] = dist(xs)
        first = [
            r[0]
            for r in c.execute(
                "SELECT input_tokens+cc_total+cache_read FROM resp r WHERE xdup=0 AND ctx_type=? AND seq=0 AND model!='<synthetic>'",
                (ct,),
            )
        ]
        pref[ct + "_first_request"] = dist(first)
    res["prefix_tokens_per_response"] = pref
    # cache hit rate on first requests vs later
    hr = {}
    for ct in ("main", "subagent", "workflow_agent"):
        for lab, cond in (("first_request", "seq=0"), ("later_requests", "seq>0")):
            a = c.execute(
                f"SELECT SUM(cache_read), SUM(cache_read+cc_total+input_tokens) FROM resp WHERE xdup=0 AND ctx_type=? AND {cond}",
                (ct,),
            ).fetchone()
            hr[f"{ct}:{lab}"] = a[0] / a[1] if a[1] else None
    res["cache_hit_rate_by_position"] = hr
    # 5. top 15 trees
    top = sorted(trees, key=lambda x: -x[1]["usd"])[:15]
    res["top15_trees"] = [
        {
            "session_id": s,
            "project": t["project"],
            "main_entrypoint": main_ep.get(s),
            "usd": t["usd"],
            "usd_at_opus55": t["usd55"],
            "share_of_fleet": t["usd"] / tot,
            "responses": t["resp"],
            "contexts": len(t["files"]),
            "human_prompts": hp.get(s, 0),
            "worker_share": t["worker_usd"] / t["usd"] if t["usd"] else None,
            "dominant_billing_type": max(t["cls"].items(), key=lambda kv: kv[1])[0],
            "dominant_share": max(t["cls"].values()) / t["usd"] if t["usd"] else None,
            "usd_by_class": dict(t["cls"]),
        }
        for s, t in top
    ]
    # project rollup (top 10)
    proj = defaultdict(lambda: [0.0, 0])
    for s, t in trees:
        proj[t["project"]][0] += t["usd"]
        proj[t["project"]][1] += 1
    res["by_project_top10"] = [
        {"project": p, "usd": v[0], "share": v[0] / tot, "tasks": v[1]}
        for p, v in sorted(proj.items(), key=lambda kv: -kv[1][0])[:10]
    ]
    with open(OUT_JSON, "w") as fh:
        json.dump(res, fh, indent=1, default=str)
    print("wrote", OUT_JSON)


if __name__ == "__main__":
    main()
