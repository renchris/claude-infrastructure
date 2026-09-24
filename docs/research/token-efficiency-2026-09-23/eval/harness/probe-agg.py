#!/usr/bin/env python3
"""probe-agg.py — tally the post-gate mechanism probes by arm, from the mixed blind re-judging.
Reads eval/gate/probes/{verdicts.json,keys/*.json}; prints markdown. Not part of the gate verdict."""

import json, os, statistics as st
from collections import defaultdict
from scipy.stats import fisher_exact

H = os.path.dirname(os.path.abspath(__file__))
GATE = os.environ.get("GATE_DIR", os.path.join(os.path.dirname(H), "gate"))
P = f"{GATE}/probes"
V = json.load(open(f"{P}/verdicts.json"))
f1runs = {
    (r["task"], r["rep"]): r for r in map(json.loads, open(f"{GATE}/f1/runs.jsonl"))
}
probe_f1 = {}
G = os.environ.get("GATE_ROOT", "/tmp/tokeff-gate")
for t in ("T08-close-dirty", "T10-status-plan"):
    for rep in range(11, 16):
        probe_f1[(t, rep)] = json.load(open(f"{G}/runs/{t}/r{rep}/out/metrics.json"))
f2m = {(s["brief"], s["rep"]): s for s in json.load(open(f"{GATE}/f2/metrics.json"))}
f2m.update(
    {
        (s["brief"], s["rep"]): s
        for s in json.load(open(f"{P}/f2-scope-collect/metrics.json"))
    }
)
out = []
for g in V:
    unit = g["id"].replace("probe-", "")
    keys = json.load(open(f"{P}/keys/{unit}.json"))["dossiers"]
    by = defaultdict(list)
    for v in g["verdicts"]:
        k = keys[v["dossier"]]
        arm = {"workflow-lean": "lean", "workflow-subagent": "default"}.get(
            k["arm"], k["arm"]
        )
        m = (
            (probe_f1.get((unit, k["rep"])) or f1runs.get((unit, k["rep"])))
            if unit.startswith("T")
            else f2m.get((unit, k["rep"]))
        )
        by[arm].append((v, m or {}))
    out.append(f"\n### {unit}\n")
    n_items = len(g["verdicts"][0]["items"])
    out.append(
        "| arm | n | success | "
        + " | ".join(f"item {i + 1}" for i in range(n_items))
        + " | quality | $ mean | turns |"
    )
    out.append("|---|---|---|" + "---|" * n_items + "---|---|---|")
    for arm in sorted(by):
        rs = by[arm]
        cost = [m.get("cost_usd") for _, m in rs if m.get("cost_usd") is not None]
        turns = [
            m.get("turns", m.get("responses"))
            for _, m in rs
            if m.get("turns", m.get("responses")) is not None
        ]
        out.append(
            f"| {arm} | {len(rs)} | {sum(v['success'] for v, _ in rs)}/{len(rs)} | "
            + " | ".join(
                f"{sum(v['items'][i] for v, _ in rs)}/{len(rs)}" for i in range(n_items)
            )
            + f" | {st.mean(v['quality'] for v, _ in rs):.1f} | {st.mean(cost) if cost else float('nan'):.3f} | "
            f"{st.mean(turns) if turns else float('nan'):.1f} |"
        )
print("\n".join(out))
