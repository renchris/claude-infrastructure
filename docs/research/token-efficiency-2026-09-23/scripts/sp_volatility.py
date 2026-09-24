#!/usr/bin/env python3
"""Volatility of static-prefix blocks (content hashes only; never content).
Inputs: data/sp_composition.jsonl, data/extract.sqlite (ctx.first_ts, workflow_id, session_id).
Reports per block class:
  distinct   = number of distinct content hashes over the window
  chg_consec = share of chronologically consecutive contexts (same class key) whose hash differs
  per_day    = mean distinct hashes per calendar day (UTC)
and, for the memory block: file order (position of each class), and for sibling workflow agents in one
workflow run: share of runs whose agents all carry a byte-identical memory block / skill listing / full
setup (the precondition for any shared cache breakpoint after the setup attachments)."""

import json, os, sqlite3, re
from collections import defaultdict, Counter

sys_path = os.path.dirname(os.path.abspath(__file__))
import importlib.util

spec = importlib.util.spec_from_file_location(
    "spc", os.path.join(sys_path, "sp_cost.py")
)
spc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(spc)
BASE = os.path.join(sys_path, "..")
DB = os.path.join(BASE, "data", "extract.sqlite")
COMP = os.path.join(BASE, "data", "sp_composition.jsonl")
OUTJ = os.path.join(BASE, "measure", "static-prefix-volatility.json")

c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
meta = {
    f: (ct, slug, wf, sid, ts, cfg)
    for f, ct, slug, wf, sid, ts, cfg in c.execute(
        "select file, ctx_type, project_slug, workflow_id, session_id, first_ts, config_dir from ctx"
    )
}
BLOCKS = {
    "skill_listing": "skill listing",
    "agent_listing_delta": "agent listing",
    "deferred_tools_delta": "deferred tool names",
    "mcp_instructions_delta": "MCP server instructions",
    "hook_additional_context:SessionStart": "SessionStart hook context",
    "session_context": "session_context",
    "environment": "environment",
    "date": "date",
    "auto_mode": "auto_mode",
}
series = defaultdict(list)  # class -> [(ts, key, sha)]
pos = defaultdict(Counter)  # class -> Counter(position in memory block)
wf = defaultdict(list)  # workflow_id -> [(instr_sha, skill_sha, setup_sha)]
for ln in open(COMP):
    rec = json.loads(ln)
    if "blocks" not in rec or rec["file"] not in meta:
        continue
    ct, slug, wid, sid, ts, cfg = meta[rec["file"]]
    repo = spc.repo_of(rec["instr"], slug)
    for i, fi in enumerate(rec["instr"]):
        k = spc.classify_file(fi["path"], repo)
        series[k].append((ts, repo, fi["sha"]))
        pos[k][i] += 1
    shas = {}
    for b in rec["blocks"]:
        if b["t"] in BLOCKS:
            shas[b["t"]] = shas.get(b["t"], "") + b["sha"]
    for t, s in shas.items():
        series[BLOCKS[t]].append(
            (ts, ct if t in ("skill_listing", "deferred_tools_delta") else repo, s)
        )
    if ct == "workflow_agent" and wid:
        ish = "|".join(fi["sha"] for fi in rec["instr"])
        wf[wid].append(
            (
                ish,
                shas.get("skill_listing", ""),
                ish
                + shas.get("skill_listing", "")
                + shas.get("deferred_tools_delta", "")
                + shas.get("session_context", "")
                + shas.get("date", ""),
            )
        )
out = {"classes": {}, "memory_block_positions": {}, "workflow_siblings": {}}
for k, v in sorted(series.items(), key=lambda kv: -len(kv[1])):
    if len(v) < 20:
        continue
    v.sort()
    byk = defaultdict(list)
    for ts, key, s in v:
        byk[key].append(s)
    chg = sum(1 for lst in byk.values() for a, b in zip(lst, lst[1:]) if a != b)
    pairs = sum(max(0, len(lst) - 1) for lst in byk.values())
    days = defaultdict(set)
    for ts, key, s in v:
        days[(ts or "")[:10]].add(s)
    out["classes"][k] = {
        "contexts": len(v),
        "distinct": len({s for _, _, s in v}),
        "chg_consec": round(chg / pairs, 3) if pairs else None,
        "distinct_per_day_mean": round(
            sum(len(x) for x in days.values()) / len(days), 1
        ),
    }
for k, cnt in pos.items():
    if sum(cnt.values()) >= 20:
        out["memory_block_positions"][k] = dict(sorted(cnt.items()))
n = len(wf)
multi = [a for a in wf.values() if len(a) >= 2]


def same(idx):
    return sum(1 for a in multi if len({x[idx] for x in a}) == 1)


out["workflow_siblings"] = {
    "workflow_runs": n,
    "runs_with_2plus_agents": len(multi),
    "identical_memory_block": same(0),
    "identical_skill_listing": same(1),
    "identical_full_setup": same(2),
    "agents_in_multi_runs": sum(len(a) for a in multi),
    "agents_matching_run_majority_setup": sum(
        Counter(x[2] for x in a).most_common(1)[0][1] for a in multi
    ),
}
json.dump(out, open(OUTJ, "w"), indent=1)
for k, d in out["classes"].items():
    print(f"{k[:60]:60s} {d}")
print("positions:")
[print(" ", k[:60], d) for k, d in out["memory_block_positions"].items()]
print("workflow siblings:", out["workflow_siblings"])
