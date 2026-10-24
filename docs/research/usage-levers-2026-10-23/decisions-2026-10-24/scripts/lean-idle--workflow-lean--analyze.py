#!/usr/bin/env python3
"""Aggregate runs.jsonl + slots.jsonl from replay.py into the decision numbers.
Weights (weekly pp per Mtok, one account's meter): writes 0.245, output 0.404 (round 2 fit4, used by
round 3), reads 0.0057 / 0.0076 (round 3 probe low / high). Lean counterfactual per eligible default
slot: prefix delta D = first_tokens - 9.2k removed from every request (first request: written part
first, rest read; later requests: read), then the remainder scaled by 1.195 (lean +19.5% turns,
GATE.md re-gate)."""

import collections
import json
import statistics as st
import sys
from datetime import datetime, timezone

W = "/tmp/lean-idle/workflow-lean"
runs = {json.loads(l)["runId"]: json.loads(l) for l in open(f"{W}/runs.jsonl")}
slots = [json.loads(l) for l in open(f"{W}/slots.jsonl")]
HARD = {"skill", "mcp", "agent_tool", "ship", "git_real", "claude_home_write"}
BORDER = {"house_tool", "repo_code_write", "git_sandbox"}
WW, WO = 0.245, 0.404
LEAN_FIRST = 9200
TURNS = 1.195


def pp(cw, cr, out, inp, wr):
    return (WW * (cw + inp) + wr * cr + WO * out) / 1e6


def lean_cf(s):
    d = max(0, (s["first_tokens"] or 0) - LEAN_FIRST)
    fw = s["first_cw"] or 0
    w_saved = min(fw, d)
    r_saved = (d - w_saved) + d * max(0, s["nreq"] - 1)
    cw = max(0, s["cw"] - w_saved) * TURNS
    cr = max(0, s["cr"] - r_saved) * TURNS
    return cw, cr, s["out"] * TURNS, s["inp"] * TURNS


def week(ts):
    if not ts:
        return None
    t = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    d = (datetime(2026, 10, 24, 23, 59, tzinfo=timezone.utc) - t).days
    return f"wk-{d // 7}"  # wk-0 = last 7 days


def q(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))] if xs else None


out = {}
# ---------- first-request sizes on 2.1.293 ----------
fr = collections.defaultdict(list)
for s in slots:
    if s["version"] == "2.1.293" and s["first_tokens"]:
        fr[s["agentType"]].append(s["first_tokens"])
out["first_request_2.1.293"] = {
    k: dict(n=len(v), median=st.median(v), p10=q(v, 0.1), p90=q(v, 0.9))
    for k, v in fr.items()
    if len(v) > 5
}
turns = collections.defaultdict(list)
for s in slots:
    if s["version"] == "2.1.293" and s["nreq"]:
        turns[s["agentType"]].append(s["nreq"])
out["nreq_2.1.293"] = {
    k: dict(n=len(v), mean=round(st.mean(v), 2), median=st.median(v))
    for k, v in turns.items()
    if len(v) > 5
}

# ---------- run / script verdicts ----------
by_run = collections.defaultdict(list)
for s in slots:
    by_run[s["runId"]].append(s)
rv = collections.Counter()
script_v = {}
for rid, r in runs.items():
    if not r.get("sha"):
        rv["no-script"] += 1
        continue
    v = (
        "would-deny"
        if r["would_deny"]
        else (
            "allow-has-type"
            if r["verdicts"].get("has-agent-type") == r["n_sites"]
            else "allow-other"
        )
    )
    rv[v] += 1
    script_v[r["sha"]] = r["would_deny"]
out["runs"] = dict(rv)
out["unique_scripts"] = dict(n=len(script_v), would_deny=sum(script_v.values()))
site_v = collections.Counter()
for r in runs.values():
    for s in r.get("sites") or []:
        site_v[s["verdict"]] += 1
out["call_sites_by_verdict"] = dict(site_v)

# ---------- slot classes at each site verdict (default slots) ----------
tab = collections.defaultdict(collections.Counter)
for s in slots:
    if s["agentType"] != "workflow-subagent":
        continue
    tab[s["site_verdict"] or "unmapped"][s["cls"]] += 1
out["default_slots_cls_by_site_verdict"] = {k: dict(v) for k, v in tab.items()}

# ---------- false deny ----------
fd = collections.Counter()
fd_runs = []
fd_scripts = collections.defaultdict(set)
for rid, r in runs.items():
    if not r.get("would_deny"):
        continue
    ss = [s for s in by_run[rid] if s["agentType"] == "workflow-subagent"]
    at_wd = [s for s in ss if s["site_verdict"] == "would-deny"]
    unm = [s for s in ss if s["site"] is None]
    hard = [s for s in at_wd if s["cls"] in HARD]
    border = [s for s in at_wd if s["cls"] in BORDER]
    hard_unm = [s for s in unm if s["cls"] in HARD]
    fd["denied_runs"] += 1
    fd["denied_runs_with_wd_default_slots"] += bool(at_wd)
    fd["false_strict"] += bool(hard)
    fd["false_broad"] += bool(hard or border)
    fd["false_strict_upper_incl_unmapped"] += bool(hard or hard_unm)
    fd["wd_default_slots"] += len(at_wd)
    fd["wd_default_slots_hard"] += len(hard)
    fd["wd_default_slots_border"] += len(border)
    fd_scripts[r["sha"]].add(bool(hard))
    if hard:
        fd_runs.append(
            (
                rid,
                r.get("name"),
                r["acct"],
                sorted({s["cls"] for s in hard}),
                [s["label"] for s in hard][:4],
            )
        )
out["false_deny"] = dict(fd)
out["false_deny_unique_scripts"] = dict(
    denied=len(fd_scripts), false_strict=sum(any(v) for v in fd_scripts.values())
)
out["false_deny_runs_sample"] = fd_runs[:40]

# ---------- savings per week ----------
sav = collections.defaultdict(lambda: collections.Counter())
for s in slots:
    wk = week(s["first_ts"])
    if wk is None or s["nreq"] == 0:
        continue
    for wr, tag in ((0.0057, "lo"), (0.0076, "hi")):
        dflt = pp(s["cw"], s["cr"], s["out"], s["inp"], wr)
        sav[wk][f"all_{tag}"] += dflt
        if s["agentType"] == "workflow-subagent":
            sav[wk][f"default_{tag}"] += dflt
            if s["site_verdict"] == "would-deny":
                sav[wk][f"wd_{tag}"] += dflt
                if s["cls"] not in HARD:
                    lcw, lcr, lo, li = lean_cf(s)
                    sav[wk][f"save_strict_{tag}"] += dflt - pp(lcw, lcr, lo, li, wr)
                    if s["cls"] not in BORDER:
                        sav[wk][f"save_broad_{tag}"] += dflt - pp(lcw, lcr, lo, li, wr)
                else:
                    sav[wk][f"hard_wd_cost_{tag}"] += dflt
            if s["site_verdict"] == "keep-default" and s["cls"] not in HARD | BORDER:
                lcw, lcr, lo, li = lean_cf(s)
                sav[wk][f"missed_keepdefault_{tag}"] += dflt - pp(lcw, lcr, lo, li, wr)
            if s["site_verdict"] == "unknown" and s["cls"] not in HARD | BORDER:
                lcw, lcr, lo, li = lean_cf(s)
                sav[wk][f"missed_unknown_{tag}"] += dflt - pp(lcw, lcr, lo, li, wr)
    if s["agentType"] == "workflow-subagent":
        sav[wk]["n_default"] += 1
        sav[wk]["n_wd"] += s["site_verdict"] == "would-deny"
    elif s["agentType"] == "workflow-lean":
        sav[wk]["n_lean"] += 1
out["by_week_pp_fleet"] = {
    k: {kk: round(vv, 3) for kk, vv in sorted(v.items())}
    for k, v in sorted(sav.items())
}

# denied runs per week + deny overhead estimate
dr = collections.Counter()
for rid, r in runs.items():
    if r.get("would_deny"):
        ts = min((s["first_ts"] for s in by_run[rid] if s["first_ts"]), default=None)
        dr[week(ts)] += 1
out["denied_runs_by_week"] = dict(dr)

# repeat authors: would-deny runs that are 2nd+ would-deny in same session dir
sess = collections.defaultdict(list)
for rid, r in runs.items():
    if r.get("would_deny") and r.get("dir"):
        sid = r["dir"].split("/subagents/")[0]
        sess[sid].append(r.get("start") or 0)
out["wd_sessions"] = dict(
    sessions=len(sess),
    runs=sum(len(v) for v in sess.values()),
    runs_after_first_in_session=sum(len(v) - 1 for v in sess.values()),
)
# top names among would-deny
nm = collections.Counter()
for r in runs.values():
    if r.get("would_deny"):
        nm[(r.get("name") or "?")[:40]] += 1
out["wd_top_names"] = nm.most_common(15)
json.dump(out, open(f"{W}/analysis.json", "w"), indent=1, default=str)
print(json.dumps(out, indent=1, default=str)[:20000])
