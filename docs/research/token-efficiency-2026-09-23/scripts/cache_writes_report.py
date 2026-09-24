#!/usr/bin/env python3
"""Aggregate data/cache_walk.sqlite (built by scripts/cache_walk.py) into measure/cache-writes.json.

Every figure is MEASURED from the extract except where a key says `estimated` (the TTL
counterfactuals). Prices are list-price weights (the fleet is subscription-billed):
write = input price x 1.25 (5m TTL) or x 2 (1h TTL); read = input x cr_mult.
Costs are reported at each response's own model (`usd`) and re-priced at Opus 5.5 (`usd55`,
$4/MTok input, read 0.05x). All aggregates filter xdup = 0.

Usage: cd /tmp && nice -n 10 python3 <dir>/scripts/cache_writes_report.py [--no-raw]
  --no-raw skips the raw-transcript scan that sub-classifies wake prompts.
"""

import collections
import json
import os
import re
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EX = os.path.join(ROOT, "data", "extract.sqlite")
WALK = os.path.join(ROOT, "data", "cache_walk.sqlite")
OUTJ = os.path.join(ROOT, "measure", "cache-writes.json")
P55 = 4.0
CR55 = 0.05

db = sqlite3.connect(f"file:{WALK}?mode=ro", uri=True)
db.execute(f"ATTACH 'file:{EX}?mode=ro' AS x")
price = {
    m: (i, c)
    for m, i, c in db.execute("SELECT model, in_per_mtok, cr_mult FROM x.price")
}

cols = (
    "file ctx_type session_id seq ts model prev_model prev_seq input_tokens cc_5m cc_1h cc_total "
    "cache_read prefix prev_prefix prev_ttl gap_s cls sub first_cache_read"
).split()
rows = [
    dict(zip(cols, r))
    for r in db.execute(
        f"SELECT {','.join(cols)} FROM walk WHERE xdup=0 ORDER BY file, seq"
    )
]

span = db.execute(
    "SELECT (julianday(max(ts))-julianday(min(ts))) FROM walk WHERE xdup=0"
).fetchone()[0]
PER14 = 14.0 / span


import datetime as _dt0


def _t0(s):
    return _dt0.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def w_usd(r, m5=1.25, m1=2.0, at55=False):
    p = P55 if at55 else price[r["model"]][0]
    return ((r["cc_5m"] or 0) * m5 + (r["cc_1h"] or 0) * m1) * p / 1e6


def full_usd(inp, w5, w1, cr, model, at55=False):
    p, crm = (P55, CR55) if at55 else price[model]
    return (inp + w5 * 1.25 + w1 * 2.0 + cr * crm) * p / 1e6


def label(r):
    if r["cls"] == "REWRITE":
        return "REWRITE:" + r["sub"]
    return r["cls"]


def agg(keyf):
    out = collections.defaultdict(lambda: collections.Counter())
    for r in rows:
        k = keyf(r)
        if k is None:
            continue
        c = out[k]
        c["n"] += 1
        c["w5m_tok"] += r["cc_5m"] or 0
        c["w1h_tok"] += r["cc_1h"] or 0
        c["write_usd"] += w_usd(r)
        c["write_usd55"] += w_usd(r, at55=True)
        c["read_tok"] += r["cache_read"] or 0
        c["read_usd"] += (
            (r["cache_read"] or 0) * price[r["model"]][0] * price[r["model"]][1] / 1e6
        )
        c["read_usd55"] += (r["cache_read"] or 0) * P55 * CR55 / 1e6
    return {
        ("|".join(k) if isinstance(k, tuple) else k): {
            kk: round(v, 2) for kk, v in c.items()
        }
        for k, c in sorted(out.items())
    }


res = {
    "source": "scripts/cache_walk.py + scripts/cache_writes_report.py over data/extract.sqlite (xdup=0)",
    "window_days": round(span, 3),
    "per14_scale": round(PER14, 4),
    "hit_rule": "INCREMENTAL if cache_read_i >= 0.9 x prefix_(i-1); ratio is bimodal (0 rows in [0.5,0.9))",
    "prices": "list-price weights; write 1.25x (5m) / 2x (1h) input; usd = own model, usd55 = Opus 5.5 $4, read 0.05x",
}

res["by_ctx_class"] = agg(lambda r: (r["ctx_type"], label(r)))
res["by_class"] = agg(label)
res["by_model_class"] = agg(lambda r: (r["model"], label(r)))
res["by_ctx"] = agg(lambda r: r["ctx_type"])
tot = agg(lambda r: "all")["all"]
res["total"] = tot


# ---- gap histogram (non-START responses) ------------------------------------------------
def gapb(g):
    return "a_lt5m" if g <= 300 else ("b_5_60m" if g <= 3600 else "c_gt60m")


res["gap_hist"] = agg(
    lambda r: (
        None
        if r["gap_s"] is None
        else (
            r["ctx_type"],
            gapb(r["gap_s"]),
            "hit" if r["cls"] == "INCREMENTAL" else "miss",
        )
    )
)
# hit rate by finer gap bucket and the TTL that was live: validates the TTL model empirically
FB = [
    (0, 240),
    (240, 300),
    (300, 360),
    (360, 900),
    (900, 3300),
    (3300, 3600),
    (3600, 3900),
    (3900, 1e12),
]
fine = collections.defaultdict(lambda: [0, 0])
for r in rows:
    if (
        r["gap_s"] is None
        or r["cls"] == "REWRITE"
        and r["sub"] in ("model_switch", "shrink")
    ):
        continue
    for lo, hi in FB:
        if lo < r["gap_s"] <= hi or (lo == 0 and r["gap_s"] <= hi):
            k = f"{r['ctx_type']}|ttl={r['prev_ttl']}|{int(lo)}-{int(hi) if hi < 1e11 else 'inf'}s"
            fine[k][0] += 1
            fine[k][1] += r["cls"] == "INCREMENTAL"
            break
res["hit_rate_by_gap_and_live_ttl"] = {
    k: {"n": v[0], "hits": v[1], "hit_rate": round(v[1] / v[0], 3)}
    for k, v in sorted(fine.items())
}


# ---- TTL counterfactual (ESTIMATED) -----------------------------------------------------
# Model: the cache entry written by request i-1 is alive at request i iff gap_i <= TTL.
# A hit that would miss becomes a full rewrite of prefix_i minus uncached input minus S, where
# S = the file's first-request cache_read (system + tools, shared across the fleet and assumed
# still warm). A real miss stays a miss (same tokens) whatever the TTL, except that a
# REWRITE:gap_5m_1h behind a live 5m entry becomes a hit under all-1h.
def cf(ctx_filter):
    s = collections.Counter()
    for r in rows:
        if not ctx_filter(r):
            continue
        m, inp, cr, pre = (
            r["model"],
            r["input_tokens"] or 0,
            r["cache_read"] or 0,
            r["prefix"],
        )
        w = (r["cc_5m"] or 0) + (r["cc_1h"] or 0)
        S = min(r["first_cache_read"] or 0, pre - inp)
        for at55, suf in ((False, ""), (True, "55")):
            s["asis" + suf] += full_usd(
                inp, r["cc_5m"] or 0, r["cc_1h"] or 0, cr, m, at55
            )
            # all-5m
            if (
                r["cls"] == "INCREMENTAL"
                and r["gap_s"] is not None
                and r["gap_s"] > 300
            ):
                s["all5m" + suf] += full_usd(inp, pre - inp - S, 0, S, m, at55)
                if not at55:
                    s["all5m_converted_hits"] += 1
                    s["all5m_converted_tok"] += pre - inp - S
            else:
                s["all5m" + suf] += full_usd(inp, w, 0, cr, m, at55)
            # all-1h
            if (
                r["cls"] == "REWRITE"
                and r["sub"] == "gap_5m_1h"
                and r["prev_ttl"] == "5m"
            ):
                nw = max(pre - inp - r["prev_prefix"], 0)
                s["all1h" + suf] += full_usd(
                    inp, 0, nw, min(r["prev_prefix"], pre - inp), m, at55
                )
                if not at55:
                    s["all1h_converted_misses"] += 1
            else:
                s["all1h" + suf] += full_usd(inp, 0, w, cr, m, at55)
    return {k: round(v, 2) for k, v in s.items()}


res["ttl_counterfactual"] = {
    "method": "ESTIMATED: replay each response's actual tokens under a uniform TTL; see script docstring for the rules",
    "main": cf(lambda r: r["ctx_type"] == "main"),
    "subagent": cf(lambda r: r["ctx_type"] == "subagent"),
    "workflow_agent": cf(lambda r: r["ctx_type"] == "workflow_agent"),
}
# the 1h premium vs its payoff on main threads, decomposed
prem = collections.Counter()
for r in rows:
    if r["ctx_type"] != "main":
        continue
    for at55, suf in ((False, ""), (True, "55")):
        p, crm = (P55, CR55) if at55 else price[r["model"]]
        prem["premium_usd" + suf] += (r["cc_1h"] or 0) * 0.75 * p / 1e6
        if r["cls"] == "INCREMENTAL" and r["gap_s"] is not None and r["gap_s"] > 300:
            inp = r["input_tokens"] or 0
            S = min(r["first_cache_read"] or 0, r["prefix"] - inp)
            re_tok = r["prefix"] - inp - S
            w = (r["cc_5m"] or 0) + (r["cc_1h"] or 0)
            prem["payoff_usd" + suf] += ((re_tok * 1.25 + S * crm) - (w * 1.25 + (r["cache_read"] or 0) * crm)) * p / 1e6
            if not at55:
                prem["n_hits_gap_gt_5m"] += 1
                prem["n_hits_gap_gt_1h"] += r["gap_s"] > 3600
res["ttl_1h_premium_vs_payoff_main"] = {k: round(v, 2) for k, v in prem.items()}

# ---- START writes -----------------------------------------------------------------------
st = collections.defaultdict(lambda: collections.Counter())
for r in rows:
    if r["cls"] != "START":
        continue
    c = st[r["ctx_type"]]
    c["n"] += 1
    c["prefix"] += r["prefix"]
    c["cache_read"] += r["cache_read"] or 0
    c["written"] += r["cc_total"] or 0
    c["zero_read"] += (r["cache_read"] or 0) == 0
    c["write_usd"] += w_usd(r)
    c["write_usd55"] += w_usd(r, at55=True)
res["start"] = {
    k: {
        "n": c["n"],
        "mean_prefix": round(c["prefix"] / c["n"]),
        "mean_cache_read": round(c["cache_read"] / c["n"]),
        "mean_written": round(c["written"] / c["n"]),
        "read_share_of_prefix": round(c["cache_read"] / c["prefix"], 4),
        "share_zero_read": round(c["zero_read"] / c["n"], 4),
        "write_usd_window": round(c["write_usd"], 2),
        "write_usd55_window": round(c["write_usd55"], 2),
        "write_usd_per14d": round(c["write_usd"] * PER14, 2),
        "write_usd55_per14d": round(c["write_usd55"] * PER14, 2),
    }
    for k, c in st.items()
}

# ---- START decomposition for agents (ESTIMATED shared-setup share) ----------------------
# Setup = memory files (instructions) + skill_listing + deferred_tools_delta in the first user
# message: identical across a parent's agents. shared_tok_est = cc_total x setup_chars / all
# visible first-message chars (a char-share split of measured tokens). "warm sibling" = another
# START of the same parent session and model within the previous 300 s (MEASURED), i.e. a
# request that could have read the setup from cache if a breakpoint sat after it.
SETUP = ("instructions", "skill_listing", "deferred_tools_delta")
fm = collections.defaultdict(lambda: [0, 0])
for f, sk, ch in db.execute("""SELECT i.file, i.subkind, i.chars FROM x.item i JOIN x.ctx c ON c.file=i.file
                               WHERE i.resp_before=-1 AND i.visible=1 AND c.ctx_type!='main'"""):
    fm[f][1] += ch or 0
    if sk in SETUP:
        fm[f][0] += ch or 0
starts = sorted([r for r in rows if r["cls"] == "START" and r["ctx_type"] != "main"], key=lambda r: r["ts"])
last_start = {}
sd = collections.defaultdict(lambda: collections.Counter())
for r in starts:
    t = _t0(r["ts"])
    key = (r["session_id"], r["model"])
    warm = key in last_start and t - last_start[key] <= 300
    last_start[key] = t
    a, b = fm.get(r["file"], [0, 0])
    share = a / b if b else 0
    sh = (r["cc_total"] or 0) * share
    c = sd[r["ctx_type"]]
    c["n"] += 1
    c["setup_char_share_sum"] += share
    c["shared_tok_est"] += sh
    c["warm_sibling_n"] += warm
    if warm:
        c["warm_shared_tok_est"] += sh
        c["saving_usd55_est"] += sh * (1.25 - CR55) * P55 / 1e6
        c["saving_usd_est"] += sh * (1.25 - price[r["model"]][1]) * price[r["model"]][0] / 1e6
res["start_shared_setup_agents"] = {k: {"n": c["n"], "mean_setup_char_share": round(c["setup_char_share_sum"] / c["n"], 3),
                                        "shared_tok_est": int(c["shared_tok_est"]), "warm_sibling_n": c["warm_sibling_n"],
                                        "warm_shared_tok_est": int(c["warm_shared_tok_est"]),
                                        "saving_usd_window_est": round(c["saving_usd_est"], 2),
                                        "saving_usd55_window_est": round(c["saving_usd55_est"], 2),
                                        "saving_usd55_per14d_est": round(c["saving_usd55_est"] * PER14, 2)}
                                    for k, c in sd.items()}

# ---- wake sources for REWRITE gaps (> 1h everywhere; 5m-1h too, for agents) --------------
ASSIST = ("assistant_text", "assistant_thinking", "tool_use_input")
item_q = """SELECT item_seq, kind, subkind, detail, uid, chars FROM x.item
            WHERE file=? AND resp_before>=? AND resp_before<? ORDER BY item_seq"""


def wake(r):
    its = [
        i
        for i in db.execute(item_q, (r["file"], r["prev_seq"], r["seq"]))
        if i[1] not in ASSIST
    ]
    resumed = any(i[1] == "attachment" and ":SessionStart" in (i[2] or "") for i in its)
    trig = None
    for i in its:
        if i[1] == "user_prompt" or (i[1] == "attachment" and i[2] == "queued_command"):
            trig = i
    if trig is None:
        for i in its:
            if i[1] == "tool_result" or (
                i[1] == "meta_user" and i[2] in ("continue", "stop_hook_feedback")
            ):
                trig = i
    if trig is None:
        src = "none_found"
    elif trig[1] == "user_prompt":
        src = "prompt:" + trig[2]
    elif trig[1] == "tool_result":
        src = "tool_result:" + trig[2]
    else:
        src = trig[1] + ":" + trig[2]
    return src, resumed, trig


targets = [
    r
    for r in rows
    if r["cls"] == "REWRITE" and (r["sub"] == "gap_gt_1h" or (r["sub"] == "gap_5m_1h"))
]
wk = []
for r in targets:
    src, resumed, trig = wake(r)
    wk.append((r, src, resumed, trig))
# main hits with gap > 50 min: classified too (not part of wake_sources), for the watcher histogram
wk_hits = []
for r in rows:
    if r["ctx_type"] == "main" and r["cls"] == "INCREMENTAL" and r["gap_s"] is not None and r["gap_s"] > 3000:
        src, resumed, trig = wake(r)
        wk_hits.append((r, src, resumed, trig))

# raw scan: summary tag / promptSource / 100-char head for prompt triggers
raw = {}
if "--no-raw" not in sys.argv:
    need = collections.defaultdict(set)
    for r, src, resumed, trig in wk + wk_hits:
        if trig and trig[1] == "user_prompt":
            need[r["file"]].add(trig[4].split("#")[0])
    for f, uu in need.items():
        pats = {u: f'"uuid":"{u}"' for u in uu}
        with open(f, "r", errors="replace") as fh:
            for line in fh:
                for u, p in pats.items():
                    if p in line:
                        try:
                            o = json.loads(line)
                        except Exception:
                            continue
                        c = o.get("message", {}).get("content")
                        s = (
                            c
                            if isinstance(c, str)
                            else " ".join(
                                b.get("text", "")
                                for b in (c or [])
                                if isinstance(b, dict)
                            )
                        )
                        m = re.search(r"<summary>(.*?)</summary>", s, re.S)
                        raw[u] = {
                            "promptSource": o.get("promptSource"),
                            "origin": (o.get("origin") or {}).get("kind"),
                            "summary": (m.group(1)[:140] if m else None),
                            "head": re.sub(r"\s+", " ", s)[:110],
                        }


def refine(src, trig):
    if not trig or trig[1] != "user_prompt":
        return src
    info = raw.get(trig[4].split("#")[0], {})
    if src == "prompt:task_notification":
        sm = (info.get("summary") or "").lower()
        if "goal check-in" in sm:
            return "task_notification:goal_check_in"
        if "workflow" in sm:
            return "task_notification:workflow_done"
        if "agent" in sm:
            return "task_notification:agent_done"
        if "no completion record" in sm:
            return "task_notification:bg_orphan_after_resume"
        if "background command" in sm or "command" in sm or "monitor" in sm:
            if re.search(r"watch|await|ping|inbox|wake|mail", sm):
                return "task_notification:bg_wake_watcher" + (":failed" if "failed" in sm else "")
            if re.search(r"ship|land|deploy", sm):
                return "task_notification:bg_ship_land"
            if re.search(r"bats|test|gate|lint|check", sm):
                return "task_notification:bg_test_gate"
            return "task_notification:bg_command_other"
        return "task_notification:other"
    if src == "prompt:command":
        m = re.search(r"<command-name>\s*(/?[\w:-]+)", info.get("head") or "")
        return f"prompt:command[{m.group(1) if m else '?'}]"
    if src in ("prompt:plain", "prompt:pasted", "prompt:bash_mode"):
        ps = info.get("promptSource") or "?"
        return f"{src}[{ps}]"
    return src


wake_agg = collections.defaultdict(lambda: collections.Counter())
samples = []
for r, src, resumed, trig in wk:
    src2 = refine(src, trig)
    key = (r["ctx_type"], r["sub"], src2 + (" +resumed" if resumed else ""))
    c = wake_agg[key]
    c["n"] += 1
    c["write_tok"] += r["cc_total"] or 0
    c["write_usd"] += w_usd(r)
    c["write_usd55"] += w_usd(r, at55=True)
    c["gap_h_sum"] += r["gap_s"] / 3600
    if r["ctx_type"] == "main" and r["sub"] == "gap_gt_1h":
        info = (
            raw.get(trig[4].split("#")[0], {})
            if trig and trig[1] == "user_prompt"
            else {}
        )
        samples.append(
            {
                "file": os.path.basename(r["file"]),
                "project": r["file"].split("/projects/")[1].split("/")[0][-40:],
                "seq": r["seq"],
                "gap_h": round(r["gap_s"] / 3600, 2),
                "prefix": r["prefix"],
                "written": r["cc_total"],
                "write_usd55": round(w_usd(r, at55=True), 2),
                "wake": src2,
                "resumed": resumed,
                "trigger_detail": (trig[3] if trig else None),
                "summary": info.get("summary"),
                "head": info.get("head"),
            }
        )
res["wake_sources"] = {
    "|".join(k): {
        "n": c["n"],
        "write_tok": c["write_tok"],
        "write_usd": round(c["write_usd"], 2),
        "write_usd55": round(c["write_usd55"], 2),
        "mean_gap_h": round(c["gap_h_sum"] / c["n"], 2),
    }
    for k, c in sorted(wake_agg.items(), key=lambda kv: -kv[1]["write_usd"])
}
samples.sort(key=lambda s: -s["write_usd55"])
# 10 samples: spread across the ranking (every k-th), so they are not only the biggest
k = max(1, len(samples) // 10)
res["long_gap_samples"] = samples[::k][:10]



def family(src):
    if src.startswith("prompt:plain") or src.startswith("prompt:pasted") or src.startswith("prompt:bash_mode"):
        return "operator_prompt (typed; includes keystroke-injected)"
    if src.startswith("prompt:command"):
        return "slash_command"
    if "bg_wake_watcher" in src:
        return "self_armed_wake_watcher (cc-await-ping / inbox watcher)"
    if src.startswith("task_notification:bg") :
        return "background_command_done"
    if src.startswith("task_notification:workflow") or src.startswith("task_notification:agent"):
        return "workflow_or_agent_done"
    if src.startswith("task_notification"):
        return "task_notification_other"
    if src.startswith("tool_result"):
        return "long_foreground_tool_call"
    if src in ("prompt:peer_message", "prompt:teammate_message"):
        return "peer_or_teammate_message"
    if "queued_command" in src:
        return "queued_prompt"
    return "other/none_found"


fam = collections.defaultdict(lambda: collections.Counter())
bashd = collections.defaultdict(lambda: collections.Counter())
for r, src, resumed, trig in wk:
    src2 = refine(src, trig)
    if r["sub"] == "gap_gt_1h":
        c = fam[(r["ctx_type"], family(src2))]
        c["n"] += 1
        c["resumed"] += resumed
        c["write_usd"] += w_usd(r)
        c["write_usd55"] += w_usd(r, at55=True)
        c["write_tok"] += r["cc_total"] or 0
    if r["ctx_type"] != "main" and src2 == "tool_result:Bash" and trig:
        d = re.sub(r"\s+", " ", trig[3] or "")
        d = re.sub(r"/Users/chrisren/Development/[^ ]*?/", "<dev>/", d)[:48]
        c = bashd[d]
        c["n"] += 1
        c["write_usd55"] += w_usd(r, at55=True)
        c["gap_min"] += r["gap_s"] / 60
res["wake_family_gap_gt_1h"] = {"|".join(k): {kk: round(v, 2) for kk, v in c.items()}
                                for k, c in sorted(fam.items(), key=lambda kv: -kv[1]["write_usd"])}
res["agent_long_bash_top"] = [{"cmd": k, "n": c["n"], "write_usd55": round(c["write_usd55"], 2),
                               "mean_gap_min": round(c["gap_min"] / c["n"], 1)}
                              for k, c in sorted(bashd.items(), key=lambda kv: -kv[1]["write_usd55"])[:15]]

# ---- keepalive counterfactual for main threads (ESTIMATED, proposal-grade) --------------
# A ping every PING s re-reads the cached prefix (0.05x at Opus 5.5) and keeps a 1h entry
# alive. Savings: every main REWRITE with gap in (1h, H] becomes an INCREMENTAL write of the
# new content only. Cost: pings during those gaps + pings during idle TAILS (last response
# of a file to the data end, capped at H), which is an UPPER bound because a closed session
# would not ping. Priced at Opus 5.5.
PING = 3300.0
end_ts = max(r["ts"] for r in rows)
import datetime as _dt
def _t(s):
    return _dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
END = _t(end_ts)
last = {}
for r in rows:
    if r["ctx_type"] == "main":
        last[r["file"]] = r
ka = {}
for H in (2, 4, 8, 24):
    Hs = H * 3600
    saved = pings_gap = pings_tail = n = 0.0
    for r in rows:
        if r["ctx_type"] != "main" or r["cls"] != "REWRITE" or r["sub"] != "gap_gt_1h" or r["gap_s"] > Hs:
            continue
        n += 1
        inp = r["input_tokens"] or 0
        new_tok = max(r["prefix"] - inp - r["prev_prefix"], 0)
        saved += ((r["cc_total"] or 0) * 2.0 + (r["cache_read"] or 0) * CR55
                  - (new_tok * 2.0 + r["prev_prefix"] * CR55)) * P55 / 1e6
        pings_gap += int(r["gap_s"] // PING) * r["prev_prefix"] * CR55 * P55 / 1e6
    for f, r in last.items():
        tail = min(max(END - _t(r["ts"]), 0), Hs)
        pings_tail += int(tail // PING) * r["prefix"] * CR55 * P55 / 1e6
    ka[f"H={H}h"] = {"rewrites_avoided": int(n), "saved_usd55": round(saved, 2),
                     "ping_cost_in_gaps_usd55": round(pings_gap, 2),
                     "ping_cost_idle_tails_upper_usd55": round(pings_tail, 2),
                     "net_usd55_worst_case": round(saved - pings_gap - pings_tail, 2)}
res["keepalive_counterfactual_main"] = ka

# ---- wake-watcher timeout wakes by gap (main, gap > 50 min, hits and misses) ------------
GB = [(3000, 3600), (3600, 3900), (3900, 7200), (7200, 14400), (14400, 1e12)]
wh = collections.defaultdict(lambda: collections.Counter())
for r, src, resumed, trig in [x for x in wk if x[0]["ctx_type"] == "main"] + wk_hits:
    if r["gap_s"] <= 3000:
        continue
    fam_ = family(refine(src, trig))
    for lo, hi in GB:
        if lo < r["gap_s"] <= hi:
            c = wh[f"{fam_}|{lo}-{int(hi) if hi < 1e11 else 'inf'}s"]
            c["n"] += 1
            c["hits"] += r["cls"] == "INCREMENTAL"
            c["write_usd55"] += w_usd(r, at55=True)
            break
# watcher term <= 55 min counterfactual (ESTIMATED): each watcher-woken miss with gap g > 3300 s
# becomes ceil(g/3300) timeout wakes that HIT; each wake is costed as REQS_PER_WAKE full-prefix
# reads (the woken turn + its re-arm tool round-trip) at Opus 5.5, plus writing only the new
# content (prefix_i - prefix_(i-1)) at 2x. The first wake is not extra (it happened anyway), but it
# is still charged, which keeps the estimate conservative.
import math
REQS_PER_WAKE = 2
wcf = collections.Counter()
for r, src, resumed, trig in wk:
    if r["ctx_type"] != "main" or r["sub"] != "gap_gt_1h" or "bg_wake_watcher" not in refine(src, trig):
        continue
    wakes = math.ceil(r["gap_s"] / 3300)
    inp = r["input_tokens"] or 0
    cf_cost = (wakes * REQS_PER_WAKE * r["prev_prefix"] * CR55
               + max(r["prefix"] - inp - r["prev_prefix"], 0) * 2.0) * P55 / 1e6
    act = ((r["cc_total"] or 0) * 2.0 + (r["cache_read"] or 0) * CR55) * P55 / 1e6
    wcf["n"] += 1
    wcf["wakes_cf"] += wakes
    wcf["actual_usd55"] += act
    wcf["cf_usd55"] += cf_cost
res["watcher_term_55min_counterfactual"] = {**{k: round(v, 2) for k, v in wcf.items()},
                                            "saving_usd55_window": round(wcf["actual_usd55"] - wcf["cf_usd55"], 2),
                                            "saving_usd55_per14d": round((wcf["actual_usd55"] - wcf["cf_usd55"]) * PER14, 2),
                                            "method": "ESTIMATED; see comment in scripts/cache_writes_report.py"}
# agents: a foreground tool call longer than the 5m TTL (ESTIMATED). Counterfactual = the agent
# waits in bounded slices of <= 270 s (background the command, poll its output), so each slice is
# one extra request reading the whole prefix at the agent's 5m TTL, and only new content is written.
acf = collections.Counter()
for r, src, resumed, trig in wk:
    if r["ctx_type"] == "main" or not src.startswith("tool_result:"):
        continue
    polls = math.ceil(r["gap_s"] / 270)
    inp = r["input_tokens"] or 0
    cf_cost = (polls * r["prev_prefix"] * CR55 + max(r["prefix"] - inp - r["prev_prefix"], 0) * 1.25) * P55 / 1e6
    act = ((r["cc_5m"] or 0) * 1.25 + (r["cc_1h"] or 0) * 2.0 + (r["cache_read"] or 0) * CR55) * P55 / 1e6
    acf["n"] += 1
    acf["polls_cf"] += polls
    acf["actual_usd55"] += act
    acf["cf_usd55"] += cf_cost
res["agent_long_tool_call_poll_counterfactual"] = {**{k: round(v, 2) for k, v in acf.items()},
                                                   "saving_usd55_window": round(acf["actual_usd55"] - acf["cf_usd55"], 2),
                                                   "saving_usd55_per14d": round((acf["actual_usd55"] - acf["cf_usd55"]) * PER14, 2),
                                                   "method": "ESTIMATED; see comment in scripts/cache_writes_report.py"}
res["main_wakes_gt_50min_by_family_and_gap"] = {k: {kk: round(v, 2) for kk, v in c.items()}
                                                for k, c in sorted(wh.items())}

# ---- REWRITE gap < 5m: what sits between the two responses (heuristic priority) ----------
lt = collections.defaultdict(lambda: collections.Counter())
for r in rows:
    if r["cls"] != "REWRITE" or r["sub"] != "gap_lt_5m":
        continue
    subs = {(k, sk or "") for (_, k, sk, _, _, _) in db.execute(item_q, (r["file"], r["prev_seq"], r["seq"]))}
    sks = {sk for _, sk in subs}
    if any(":SessionStart" in x for x in sks):
        cause = "session_resumed/transplanted (SessionStart hook in gap)"
    elif "thinking_drop" in sks:
        cause = "thinking_drop attachment (history mutation)"
    elif "teammate_message" in sks:
        cause = "teammate_message delivered"
    elif "instructions" in sks:
        cause = "instructions re-injected"
    elif r["prefix"] > 1.5 * r["prev_prefix"]:
        cause = "prefix grew >1.5x"
    else:
        cause = "unexplained"
    c = lt[(r["ctx_type"], cause)]
    c["n"] += 1
    c["write_usd55"] += w_usd(r, at55=True)
    c["write_usd"] += w_usd(r)
res["rewrite_lt5m_causes"] = {"|".join(k): {kk: round(v, 2) for kk, v in c.items()} for k, c in sorted(lt.items())}

# ---- machine sleep attribution (MEASURED where pmset covers the gap) --------------------
# data/pmset_sleepwake.txt = `pmset -g log | grep -E "^... (Sleep|Wake|DarkWake) "` (saved
# 2026-09-23; macOS keeps ~5 days, so coverage starts 2026-09-19). Asleep = from an
# "Entering Sleep state" line to the next full "Wake" line.
SLP = os.path.join(ROOT, "data", "pmset_sleepwake.txt")
intervals, cov_start = [], None
if os.path.exists(SLP):
    cur = None
    for line in open(SLP):
        m = re.match(r"(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) ([-+]\d{4}) (\w+)\s+\t?(.*)", line)
        if not m:
            continue
        t = _dt.datetime.strptime(m.group(1) + " " + m.group(2), "%Y-%m-%d %H:%M:%S %z").timestamp()
        cov_start = t if cov_start is None else min(cov_start, t)
        if m.group(3) == "Sleep" and m.group(4).startswith("Entering Sleep state") and cur is None:
            cur = t
        elif m.group(3) == "Wake" and cur is not None:
            intervals.append((cur, t))
            cur = None


def asleep(a, b):
    return sum(max(0, min(b, y) - max(a, x)) for x, y in intervals)


sl = collections.Counter()
sleep_files = set()
for r in rows:
    if r["ctx_type"] != "main" or r["cls"] != "REWRITE" or r["sub"] != "gap_gt_1h" or cov_start is None:
        continue
    b = _t(r["ts"]); a = b - r["gap_s"]
    if a < cov_start:
        continue
    frac = asleep(a, b) / r["gap_s"]
    k = "sleep_ge_50pct" if frac >= 0.5 else ("sleep_some" if frac > 0 else "awake")
    sl[k + "_n"] += 1
    sl[k + "_usd55"] += w_usd(r, at55=True)
    sl["covered_n"] += 1
res["machine_sleep_main_gap_gt_1h"] = {"coverage_start": _dt.datetime.utcfromtimestamp(cov_start).isoformat() + "Z" if cov_start else None,
                                        "sleep_intervals": len(intervals),
                                        **{k: round(v, 2) for k, v in sl.items()}}

os.makedirs(os.path.dirname(OUTJ), exist_ok=True)
with open(OUTJ, "w") as fh:
    json.dump(res, fh, indent=1)
print(f"wrote {OUTJ}", file=sys.stderr)
