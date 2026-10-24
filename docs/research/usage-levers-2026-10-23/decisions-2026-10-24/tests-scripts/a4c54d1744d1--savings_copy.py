#!/usr/bin/env python3
"""Reviewer: re-derive the gross pp/week saving of converting would-deny default slots to
workflow-lean, from review-numbers/scan.py output, with the researcher's model (V0) and corrections.

Weights: weekly pp per Mtok on one account's meter, summed over accounts (fleet = 400 pp/week).
  writes 0.245 (cw), output 0.404, reads 0.0057/0.0076 (round 3) or 0.0048 (round 2 short-context fit)
  per-request 0.0006 pp (round 2 fit4: 'uncached input ... read it as a per-request cost')
Slot -> site mapping: own (uniform verdict among untyped sites, else label match), else unmapped."""

import collections
import json
import re
import sys
from datetime import datetime, timezone

O = "/tmp/lean-idle/workflow-lean/review-numbers"
END = datetime(2026, 10, 24, 23, 59, tzinfo=timezone.utc)
CUT = "2026-09-24T05"
WW, WO = 0.245, 0.404
PERREQ = 0.0006
D293 = 40000  # 2.1.293 default-minus-lean prefix: 39,085 (median method) .. 42,565 (intercepts), prefix.py
runs = {}
for l in open(f"{O}/runs.jsonl"):
    r = json.loads(l)
    runs[r["runId"]] = r
S = [json.loads(l) for l in open(f"{O}/slots.jsonl")]
S = [s for s in S if s["nreq"] and s["first_ts"] and s["first_ts"] >= CUT]
HARD_KEYS = ("skill", "mcp", "agent", "git_real", "ship", "home_claude_write")


try:
    HMAP = json.load(
        open(f"{O}/hardmap.json")
    )  # tight classifier (fd2.py); loose scan otherwise
except OSError:
    HMAP = None


def hard(s):
    loose = any(s["need"].get(k) for k in HARD_KEYS)
    if HMAP is None or not loose:
        return loose
    return HMAP.get(s["aid"], loose)


def label_rx(label):
    parts = re.split(r"\$\{[^}]*\}?", label)
    try:
        return re.compile(
            ".*?".join(re.escape(p) for p in parts) + ("" if len(label) < 80 else ".*"),
            re.S,
        )
    except re.error:
        return None


def site_verdict(s):
    r = runs.get(s["runId"])
    if not r or not r.get("sites"):
        return None, "no-sites"
    if s["agentType"] != "workflow-subagent":
        return "typed", "typed"
    cands = [
        x
        for x in r["sites"]
        if x["agent_type"] in (None, "opaque", "workflow-subagent")
    ]
    vs = {x["verdict"] for x in cands}
    if len(vs) == 1:
        return vs.pop(), "uniform"
    lab = s.get("label") or s.get("desc") or ""
    m = [
        x
        for x in cands
        if x.get("label") and (rx := label_rx(x["label"])) and rx.fullmatch(lab)
    ]
    vs = {x["verdict"] for x in m}
    if len(vs) == 1:
        return vs.pop(), "label"
    return None, "unmapped"


def week(ts):
    return (END - datetime.fromisoformat(ts.replace("Z", "+00:00"))).days // 7


def ft(s):
    return s["first_cw"] + s["first_cr"] + s["first_in"]


def strip_prefix(s, D):
    """tokens after removing D prefix tokens from every request: written part on request 1, read after."""
    w = min(s["first_cw"], D)
    rd = (D - w) + D * (s["nreq"] - 1)
    return max(0, s["cw"] - w), max(0, s["cr"] - rd)


def cost(cw, cr, out, nreq, wr, perreq):
    return (WW * cw + wr * cr + WO * out) / 1e6 + (PERREQ * nreq if perreq else 0)


def saving(s, wr, mode, turns=1.195, perreq=False):
    out = s["out"]
    if mode == "researcher":  # d = first - 9200, recorded cost as baseline
        d = max(0, ft(s) - 9200)
        base = cost(s["cw"], s["cr"], out, s["nreq"], wr, perreq) + (
            WW * s["inp"] / 1e6 if not perreq else 0
        )
        cw, cr = strip_prefix(s, d)
        lean = cost(
            cw * turns, cr * turns, out * turns, s["nreq"] * turns, wr, perreq
        ) + (WW * s["inp"] * turns / 1e6 if not perreq else 0)
        return base - lean
    # forward: re-price the slot on 2.1.293 (strip any excess old-binary prefix), then convert
    d_now = max(0, ft(s) - 9200)
    excess = max(0, d_now - D293) if s["version"] != "2.1.293" else 0
    cw0, cr0 = strip_prefix(s, excess)
    s2 = dict(
        s, cw=cw0, cr=cr0, first_cw=max(0, s["first_cw"] - min(s["first_cw"], excess))
    )
    D = (
        min(D293, max(0, d_now - excess))
        if mode == "fwd-const"
        else max(0, d_now - excess)
    )
    base = cost(cw0, cr0, out, s["nreq"], wr, perreq)
    cw, cr = strip_prefix(s2, D)
    lean = cost(cw * turns, cr * turns, out * turns, s["nreq"] * turns, wr, perreq)
    return base - lean


mapc = collections.Counter()
elig = []
hard_wd = []
for s in S:
    v, how = site_verdict(s)
    s["sv"] = v
    if s["agentType"] == "workflow-subagent":
        mapc[how] += 1
        if v == "would-deny":
            (hard_wd if hard(s) else elig).append(s)
print("default-slot mapping", dict(mapc))
print(
    "eligible (would-deny site, default, no hard need)",
    len(elig),
    "hard at would-deny",
    len(hard_wd),
)
b13 = lambda s: (runs[s["runId"]].get("name") or "").startswith("b13")
variants = [
    ("V0 researcher model, reads .0057", dict(wr=0.0057, mode="researcher")),
    ("V0 researcher model, reads .0076", dict(wr=0.0076, mode="researcher")),
    ("V1 +per-request cost, .0057", dict(wr=0.0057, mode="researcher", perreq=True)),
    ("V1 +per-request cost, .0076", dict(wr=0.0076, mode="researcher", perreq=True)),
    ("V2 fwd 2.1.293 prefix, .0057", dict(wr=0.0057, mode="fwd-const")),
    ("V2 fwd 2.1.293 prefix, .0076", dict(wr=0.0076, mode="fwd-const")),
    ("V3 fwd + per-request, .0057", dict(wr=0.0057, mode="fwd-const", perreq=True)),
    ("V3 fwd + per-request, .0076", dict(wr=0.0076, mode="fwd-const", perreq=True)),
    ("V3 fwd + per-request, .0048", dict(wr=0.0048, mode="fwd-const", perreq=True)),
    (
        "V3 fwd + per-req, .0076, turns 1.0",
        dict(wr=0.0076, mode="fwd-const", perreq=True, turns=1.0),
    ),
    (
        "V3 fwd + per-req, .0057, turns 1.35",
        dict(wr=0.0057, mode="fwd-const", perreq=True, turns=1.35),
    ),
]
res = {}
for name, kw in variants:
    wk = collections.Counter()
    wk_b13 = collections.Counter()
    for s in elig:
        v = saving(s, **kw)
        w = week(s["first_ts"])
        wk[w] += v
        if b13(s):
            wk_b13[w] += v
    tot = sum(wk.values())
    res[name] = dict(
        total30=round(tot, 1),
        per_week_30d=round(tot / 30 * 7, 1),
        by_week={k: round(wk[k], 1) for k in sorted(wk)},
        b13={k: round(wk_b13[k], 1) for k in sorted(wk_b13)},
    )
    print(
        f"{name:40s} 30d={tot:6.1f} /wk={tot / 30 * 7:5.1f} weeks={[round(wk[k], 1) for k in range(5)]} b13={[round(wk_b13[k], 1) for k in range(5)]}"
    )
# share of eligible default cost that is the 2.1.293 prefix, wk0+wk1
base = pre = 0
for s in elig:
    if week(s["first_ts"]) > 1:
        continue
    base += cost(s["cw"], s["cr"], s["out"], s["nreq"], 0.0057, True)
    cw, cr = strip_prefix(s, D293)
    pre += (WW * (s["cw"] - cw) + 0.0057 * (s["cr"] - cr)) / 1e6
print(
    f"wk0-1 eligible cost (with per-request) {base:.1f} pp, prefix part {pre:.1f} ({100 * pre / base:.0f}%)"
)
nreq = sum(s["nreq"] for s in elig if week(s["first_ts"]) <= 1)
print(
    "wk0-1 eligible requests",
    nreq,
    "-> per-request share",
    round(PERREQ * nreq, 1),
    "pp; 19.5% extra turns cost",
    round(0.195 * PERREQ * nreq, 1),
)
json.dump(res, open("/tmp/conv-tests/a4c54d1744d1/savings.json", "w"), indent=1)
