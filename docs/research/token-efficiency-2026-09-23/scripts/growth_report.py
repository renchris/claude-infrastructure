#!/usr/bin/env python3
"""Assemble measure/growth.json (and print markdown tables) from the growth_work/ outputs.

Inputs: growth_work/{fit.json, cost_by_source.json, per_file.tsv, sample.tsv, raw_read.json,
raw_labels.tsv, top_items.json, hook_signatures.json, skill_bodies.json} + extract.sqlite.
Usage: cd /tmp && nice -n 10 python3 <dir>/scripts/growth_report.py > <dir>/measure/growth_work/tables.md
"""

import json, os, csv, collections, sqlite3, re, statistics

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
W = os.path.join(ROOT, "measure", "growth_work")
DB = os.path.join(ROOT, "data", "extract.sqlite")
fit = json.load(open(os.path.join(W, "fit.json")))
cost = json.load(open(os.path.join(W, "cost_by_source.json")))
rawread = json.load(open(os.path.join(W, "raw_read.json")))
top = json.load(open(os.path.join(W, "top_items.json")))
hooks = json.load(open(os.path.join(W, "hook_signatures.json")))
skills = json.load(open(os.path.join(W, "skill_bodies.json")))
labels = dict(
    l.rstrip("\n").split("\t") for l in open(os.path.join(W, "raw_labels.tsv"))
)
c = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
out = {}


# ---------- 1. ratios
def coef(tag, model):
    return {k: round(v[0], 4) for k, v in fit[tag][model]["coef"].items()}


out["calibration"] = {
    "method": "robust OLS of the MEASURED prefix delta D=P(s+1)-P(s) on appended model-visible chars per class "
    "(scripts/growth_fit.py); B: D-out(s) on user-side classes, C: out(s) on assistant text/tool-call chars "
    "for responses without thinking",
    "tokens_per_char_all": {
        **coef("all", "B_user_side"),
        **{
            "assistant_" + k: v
            for k, v in coef("all", "C_assistant_side_no_thinking").items()
        },
    },
    "tokens_per_char_sample": {
        **coef("sample", "B_user_side"),
        **{
            "assistant_" + k: v
            for k, v in coef("sample", "C_assistant_side_no_thinking").items()
        },
    },
    "pairs_all": fit["all"]["B_user_side"]["n"],
    "pairs_sample": fit["sample"]["B_user_side"]["n"],
    "pred_over_obs_all": fit["all"]["B_user_side"]["sum_pred_over_obs_all_rows"],
    "thinking_test": {
        k: {
            "n": v["n"],
            "coef_out": round(v["coef"]["out"][0], 4),
            "coef_atext": round(v["coef"]["atext"][0], 4),
            "coef_tui": round(v["coef"]["tui"][0], 4),
        }
        for k, v in fit["all"].items()
        if k.startswith("A_")
    },
    "cross_check": "headless /context counts ~/.claude-secondary/CLAUDE.md at 40.4k tokens for 105,278 chars = 0.384 tok/char; "
    "mission board 5.5k/13,884 = 0.396; agent-operating-lessons 2.4k/6,276 = 0.382 (fitted attachment ratio 0.377)",
    "image_tokens_per_block_median": round(cost["img_tok_measured_median"], 0),
    "image_groups": cost["img_tok_measured_groups"],
}

# ---------- 2. totals by ctx
T = collections.defaultdict(lambda: collections.Counter())
rows = list(csv.DictReader(open(os.path.join(W, "per_file.tsv")), delimiter="\t"))
for r in rows:
    for k in (
        "usd_input_side",
        "usd_initial",
        "usd_growth",
        "usd55_input_side",
        "usd55_initial",
        "usd55_growth",
        "growth_tok",
    ):
        T[r["ctx"]][k] += float(r[k])
        T["ALL"][k] += float(r[k])
    T[r["ctx"]]["files"] += 1
    T["ALL"]["files"] += 1
fleet_total = {
    r[0]: (r[1], r[2])
    for r in c.execute(
        "select 'all', sum(usd_total), sum(usd_total_at_opus55) from resp_priced where xdup=0"
    )
}["all"]
out["totals"] = {k: dict(v) for k, v in T.items()}
out["fleet_total_usd"] = fleet_total

# ---------- 3. by source
A = collections.defaultdict(lambda: collections.Counter())
AC = collections.defaultdict(lambda: collections.Counter())
AS = collections.defaultdict(lambda: collections.Counter())
for r in cost["agg"]:
    num = {k: v for k, v in r.items() if isinstance(v, (int, float))}
    if r["scope"] == "all":
        A[r["source"]].update(num)
        AC[(r["ctx"], r["source"])].update(num)
    else:
        AS[r["source"]].update(num)
gtot = sum(v["usd"] for v in A.values())
gtot55 = sum(v["usd55"] for v in A.values())


def family(s):
    if s.startswith("tool_result:mcp:") or s.startswith("tool_use_input:mcp:"):
        return s.split(":")[0] + ":mcp"
    if s.startswith("attachment:hook_"):
        return "attachment:hooks"
    if s.startswith("user_prompt:task_notification"):
        return "user_prompt:task_notification"
    return s


fam = collections.defaultdict(lambda: collections.Counter())
for s, v in A.items():
    fam[family(s)].update(v)
out["growth_total_usd"] = gtot
out["growth_total_usd55"] = gtot55
out["by_source"] = [
    {
        "source": s,
        "items": int(v["n"]),
        "tokens_appended": round(v["tok"]),
        "token_reads": round(v["tok_reads"]),
        "usd": round(v["usd"], 2),
        "usd_write": round(v["usd_w"], 2),
        "usd_read": round(v["usd_r"], 2),
        "usd_uncached": round(v["usd_i"], 2),
        "usd55": round(v["usd55"], 2),
        "share_growth_usd": round(v["usd"] / gtot, 4),
        "chars": int(v["chars"]),
        "tokens_never_reread": round(v["tok_never_read"]),
    }
    for s, v in sorted(A.items(), key=lambda kv: -kv[1]["usd"])
]
out["by_source_ctx"] = [
    {
        "ctx": k[0],
        "source": k[1],
        "tokens_appended": round(v["tok"]),
        "usd": round(v["usd"], 2),
        "usd55": round(v["usd55"], 2),
    }
    for k, v in sorted(AC.items(), key=lambda kv: -kv[1]["usd"])
    if v["usd"] >= 1
]
ss = sum(v["usd"] for v in AS.values())
out["sample_share_vs_fleet"] = [
    {
        "source": s,
        "fleet_share": round(A[s]["usd"] / gtot, 4),
        "sample_share": round(AS[s]["usd"] / ss, 4) if ss else None,
    }
    for s, _ in sorted(A.items(), key=lambda kv: -kv[1]["usd"])[:20]
]

# ---------- 4. sample extrapolation by strata (ctx x size quartile, population = files n_resp_xdup=0, n_resp>=3)
pop = c.execute(
    "select file, ctx_type, n_resp from ctx where n_resp_xdup=0 and n_resp>=3"
).fetchall()
pf = {r["file"]: r for r in rows}
samp = [
    l.rstrip("\n").split("\t") for l in list(open(os.path.join(W, "sample.tsv")))[1:]
]
sq = {s[0]: int(s[2]) for s in samp}
ext = {}
for ct in ("main", "subagent", "workflow_agent"):
    fs = sorted([r for r in pop if r[1] == ct], key=lambda r: r[2])
    q = len(fs) // 4
    est = direct = 0.0
    est55 = direct55 = 0.0
    for qi in range(4):
        bucket = fs[qi * q : (qi + 1) * q] if qi < 3 else fs[3 * q :]
        sfiles = [f for f in sq if sq[f] == qi and f in {b[0] for b in bucket}]
        sv = [float(pf[f]["usd_growth"]) for f in sfiles if f in pf]
        sv55 = [float(pf[f]["usd55_growth"]) for f in sfiles if f in pf]
        dv = [float(pf[b[0]]["usd_growth"]) for b in bucket if b[0] in pf]
        dv55 = [float(pf[b[0]]["usd55_growth"]) for b in bucket if b[0] in pf]
        if sv:
            est += statistics.mean(sv) * len(bucket)
            est55 += statistics.mean(sv55) * len(bucket)
        direct += sum(dv)
        direct55 += sum(dv55)
    ext[ct] = {
        "sample_extrapolated_usd": round(est),
        "direct_full_population_usd": round(direct),
        "ratio": round(est / direct, 3) if direct else None,
        "sample_extrapolated_usd55": round(est55),
        "direct_usd55": round(direct55),
    }
out["extrapolation_check"] = ext
out["sample"] = {
    "files": len(samp),
    "by_ctx": dict(collections.Counter(s[1] for s in samp)),
    "projects": len(set(s[3] for s in samp)),
    "n_resp_range": [min(int(s[4]) for s in samp), max(int(s[4]) for s in samp)],
}

# ---------- 5. Read line prefixes
rr = rawread
saving_chars = rr["prefix_chars"] - rr["prefix_chars_every10"]
read_tok_ratio = fit["all"]["B_user_side"]["coef"]["tr_read"][0]
read_usd = A["tool_result:Read"]["usd"]
read_tok = A["tool_result:Read"]["tok"]
read55 = A["tool_result:Read"]["usd55"]
sav_tok_lo = (rr["numbered_lines"] * 0.9) * 1.0
sav_tok_hi = (rr["numbered_lines"] * 0.9) * 2.0
out["read_line_prefix"] = {
    "read_results": rr["results"],
    "read_chars": rr["chars"],
    "numbered_lines": rr["numbered_lines"],
    "prefix_chars": rr["prefix_chars"],
    "prefix_share_of_read_chars": round(rr["prefix_chars"] / rr["chars"], 4),
    "prefix_chars_if_every_10th": rr["prefix_chars_every10"],
    "saving_chars": saving_chars,
    "saving_share_of_read_chars": round(saving_chars / rr["chars"], 4),
    "saving_tokens_est_char_ratio": round(saving_chars * read_tok_ratio),
    "saving_tokens_est_range_1to2_per_prefix": [round(sav_tok_lo), round(sav_tok_hi)],
    "read_growth_usd": round(read_usd, 1),
    "read_growth_tokens": round(read_tok),
    "saving_usd_est": round(read_usd * saving_chars * read_tok_ratio / read_tok, 1),
    "saving_usd55_est": round(read55 * saving_chars * read_tok_ratio / read_tok, 1),
    "read_result_size_p50_p90_p99": [rr["size_p50"], rr["size_p90"], rr["size_p99"]],
    "system_reminder_blocks_in_read_results": rr["sysrem_n"],
    "system_reminder_chars": rr["sysrem_chars"],
}
nimg_read = c.execute(
    "select count(*), sum(n_images>0) from item where kind='tool_result' and subkind='Read' and xdup=0"
).fetchone()
out["read_line_prefix"]["read_results_with_images"] = nimg_read[1]


# ---------- 6. subagent / workflow returns
def q(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(p * len(v)))] if v else None


ret = collections.defaultdict(list)
for (
    kind,
    sub,
    uid,
    tid,
    ch,
) in c.execute("""select kind, subkind, uid, tool_use_id, chars from item where xdup=0 and visible=1 and (
        (kind='tool_result' and subkind in ('Agent','Workflow','TaskOutput')) or (kind='user_prompt' and subkind='task_notification'))"""):
    lab = (
        labels.get(tid, sub)
        if kind == "tool_result"
        else labels.get(uid.split("#")[0], "task_notification:?")
    )
    if kind == "tool_result" and sub == "TaskOutput":
        lab = "TaskOutput"
    ret[lab].append(ch)
out["returns"] = {
    k: {
        "n": len(v),
        "chars_total": sum(v),
        "p50": q(v, 0.5),
        "p90": q(v, 0.9),
        "p99": q(v, 0.99),
        "max": max(v),
        "tokens_est_total": round(
            sum(v)
            * fit["all"]["B_user_side"]["coef"][
                "prompt" if "task_notification" in k else "tr_other"
            ][0]
        ),
    }
    for k, v in sorted(ret.items(), key=lambda kv: -sum(kv[1]))
}
main_growth = sum(v["usd"] for (ctx, s), v in AC.items() if ctx == "main")
main_growth55 = sum(v["usd55"] for (ctx, s), v in AC.items() if ctx == "main")
ret_src = [
    s
    for s in A
    if s.startswith("tool_result:Agent")
    or s.startswith("tool_result:Workflow")
    or s.startswith("user_prompt:task_notification:subagent")
    or s.startswith("user_prompt:task_notification:workflow")
    or s == "tool_result:TaskOutput"
]
brief_src = [
    "tool_use_input:Agent",
    "tool_use_input:Workflow",
    "tool_use_input:SendMessage",
]
out["returns_share_of_main_growth"] = {
    "main_growth_usd": round(main_growth, 1),
    "main_growth_usd55": round(main_growth55, 1),
    "returns_usd": round(sum(AC[("main", s)]["usd"] for s in ret_src), 1),
    "returns_tokens": round(sum(AC[("main", s)]["tok"] for s in ret_src)),
    "returns_share": round(
        sum(AC[("main", s)]["usd"] for s in ret_src) / main_growth, 4
    ),
    "briefs_usd": round(sum(AC[("main", s)]["usd"] for s in brief_src), 1),
    "briefs_share": round(
        sum(AC[("main", s)]["usd"] for s in brief_src) / main_growth, 4
    ),
    "sources": ret_src,
}

# ---------- 7. skills
sk = []
for k, v in skills.items():
    sk.append(
        {
            "skill": k,
            "loads": len(v),
            "chars_mean": round(statistics.mean(x[0] for x in v)),
            "chars_max": max(x[0] for x in v),
            "tokens_est_mean": round(statistics.mean(x[1] for x in v)),
            "growth_usd": round(sum(x[2] for x in v), 2),
        }
    )
out["skill_bodies"] = sorted(sk, key=lambda x: -x["chars_mean"] * x["loads"])
allsk = [x[0] for v in skills.values() for x in v]
out["skill_body_size_dist_chars"] = {
    "n": len(allsk),
    "p50": q(allsk, 0.5),
    "p90": q(allsk, 0.9),
    "max": max(allsk) if allsk else None,
}
out["skill_tool_results"] = c.execute(
    "select count(*), sum(chars), max(chars) from item where kind='tool_result' and subkind='Skill' and xdup=0"
).fetchone()

# ---------- 8. top items, hooks
out["top_items_by_usd"] = top[:30]
out["hook_signatures_top"] = [
    {"signature": k, "n": v[0], "tokens": round(v[1]), "usd": round(v[2], 2)}
    for k, v in list(hooks.items())[:25]
]
out["checks"] = cost["check"]
sz = os.path.join(W, "cost_by_size.json")
if os.path.exists(sz):
    SZ = collections.defaultdict(lambda: collections.Counter())
    for r in json.load(open(sz)):
        SZ[(r["source"], r["bucket"])].update({k: v for k, v in r.items() if isinstance(v, (int, float))})
    out["by_size_bucket"] = [dict(source=k[0], bucket=k[1], n=int(v["n"]), chars=int(v["chars"]), tokens=round(v["tok"]),
                                  usd=round(v["usd"], 1), usd55=round(v["usd55"], 1)) for k, v in sorted(SZ.items())]
bc = os.path.join(W, "bash_classes.json")
if os.path.exists(bc):  # scripts/growth_bash_classes.py (run it first)
    out["bash_classes"] = json.load(open(bc))
json.dump(
    out, open(os.path.join(ROOT, "measure", "growth.json"), "w"), indent=1, default=str
)

# ---------- markdown tables to stdout
p = print
p("## totals")
p(
    "| ctx | files | input-side $ | initial prefix $ | growth $ | growth share | growth $ @O5.5 | growth tokens |"
)
p("|---|---:|---:|---:|---:|---:|---:|---:|")
for k in ("main", "subagent", "workflow_agent", "ALL"):
    v = T[k]
    p(
        "| %s | %d | %.0f | %.0f | %.0f | %.1f%% | %.0f | %.1fM |"
        % (
            k,
            v["files"],
            v["usd_input_side"],
            v["usd_initial"],
            v["usd_growth"],
            100 * v["usd_growth"] / v["usd_input_side"],
            v["usd55_growth"],
            v["growth_tok"] / 1e6,
        )
    )
p("\n## families")
p("| source | tokens appended | token-reads | $ | share | write $ | read $ | $ @O5.5 |")
p("|---|---:|---:|---:|---:|---:|---:|---:|")
for s, v in sorted(fam.items(), key=lambda kv: -kv[1]["usd"])[:40]:
    p(
        "| %s | %.2fM | %.0fM | %.0f | %.1f%% | %.0f | %.0f | %.0f |"
        % (
            s,
            v["tok"] / 1e6,
            v["tok_reads"] / 1e6,
            v["usd"],
            100 * v["usd"] / gtot,
            v["usd_w"],
            v["usd_r"],
            v["usd55"],
        )
    )
p("\n## by ctx top")
for ct in ("main", "subagent", "workflow_agent"):
    tot_ct = sum(v["usd"] for (x, s), v in AC.items() if x == ct)
    p("\n### " + ct + " (growth $%.0f)" % tot_ct)
    p("| source | tokens | $ | share |")
    p("|---|---:|---:|---:|")
    for (x, s), v in sorted(AC.items(), key=lambda kv: -kv[1]["usd"]):
        if x == ct and v["usd"] / tot_ct > 0.005:
            p(
                "| %s | %.2fM | %.0f | %.1f%% |"
                % (s, v["tok"] / 1e6, v["usd"], 100 * v["usd"] / tot_ct)
            )
p("\n## sample vs fleet")
p(json.dumps(out["sample_share_vs_fleet"]))
p(json.dumps(ext))
p(json.dumps(out["sample"]))
p("\n## read")
p(json.dumps(out["read_line_prefix"]))
p("\n## returns")
p(json.dumps(out["returns"], indent=0))
p(json.dumps(out["returns_share_of_main_growth"]))
p("\n## skills")
p(json.dumps(out["skill_bodies"][:15]))
p(json.dumps(out["skill_body_size_dist_chars"]))
p(out["skill_tool_results"])
p("\n## hooks")
[
    p("%6d %6.0f $%.1f %s" % (h["n"], h["tokens"], h["usd"], h["signature"]))
    for h in out["hook_signatures_top"]
]
p("\n## top items")
[
    p(
        "$%.1f tok=%d readers=%.0f %s %s %s"
        % (t["usd"], t["tok"], t["readers"], t["ctx"], t["source"], t["detail"][:70])
    )
    for t in top[:20]
]
p("\n## calibration")
p(json.dumps(out["calibration"], indent=0))
