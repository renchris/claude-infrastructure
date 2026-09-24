#!/usr/bin/env python3
"""Synthesis: savings arithmetic for OPPORTUNITIES.md (overlaps, bundles, long-context tax).

Run:  cd /tmp && nice -n 10 python3 <dir>/scripts/synth_opportunities.py
Writes: <dir>/data/synth_opportunities.json

Inputs: measure/static-prefix-cost.json (per-source $ by ctx type), audit/*.slim.md vs originals
(char cut fractions), data/extract.sqlite (main-thread cache reads above a prefix threshold).
All savings are ESTIMATED (row $ x fraction removed); list-price weights, window 2026-09-09..23.
"""

import json, os, sqlite3

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WT = os.path.abspath(os.path.join(BASE, "..", "..", ".."))  # worktree root
M, D, A = (os.path.join(BASE, x) for x in ("measure", "data", "audit"))
spc = json.load(open(os.path.join(M, "static-prefix-cost.json")))
FLEET, FLEET55 = spc["fleet_usd_own"], spc["fleet_usd_opus55"]
rows = {r["source"]: r for r in spc["rows"]}
out = {"fleet_own": FLEET, "fleet_o55": FLEET55}


def row(name):
    r = rows[name]
    own55 = r["usd_observed_own_by_ctx_type"], r["usd_observed_opus55_by_ctx_type"]
    main = (own55[0].get("main", 0.0), own55[1].get("main", 0.0))
    agents = (r["usd_observed_own"] - main[0], r["usd_observed_opus55"] - main[1])
    return {
        "own": r["usd_observed_own"],
        "o55": r["usd_observed_opus55"],
        "main": main,
        "agents": agents,
    }


# ---- char cut fractions from the audit slims (MEASURED sizes)
glob = open(os.path.join(WT, "CLAUDE.global.md"), encoding="utf-8").read().split("\n")
rng = {
    "C1": (1, 159),
    "C2": (160, 331),
    "C3": (332, 451),
    "C4": (452, 805),
    "C5": (806, 1061),
    "C6": (1062, 1077),
}
o = s = 0
for c, (a, b) in rng.items():
    o += len("\n".join(glob[a - 1 : b]))
    s += len(open(os.path.join(A, f"{c}.slim.md"), encoding="utf-8").read())
cut = {
    "global CLAUDE.md": 1 - s / o,
    "project CLAUDE.md [infra]": 1
    - len(open(os.path.join(A, "C6.project-claudemd.slim.md"), encoding="utf-8").read())
    / len(open(os.path.join(WT, ".claude", "CLAUDE.md"), encoding="utf-8").read()),
    "project rules agent-operating-lessons.md [infra]": 1
    - len(open(os.path.join(A, "C7.slim.md"), encoding="utf-8").read())
    / len(
        open(
            os.path.join(WT, ".claude", "rules", "agent-operating-lessons.md"),
            encoding="utf-8",
        ).read()
    ),
    "mission board (~/.claude/rules/00-mission-board.md)": 1
    - 970 / 5500,  # C6.mission-board.md token table (MEASURED /context)
    "global rules essay (~/.claude/rules/agent-operating-lessons.md)": 1.0,  # C6.rules-essay.md: remove whole file
}
out["audit_cut_fraction"] = cut

memrows = [
    r
    for r in rows
    if r.startswith(
        (
            "global CLAUDE.md",
            "project",
            "MEMORY.md",
            "mission board",
            "global rules",
            "memory-block",
        )
    )
]
mem_total = [
    sum(rows[r]["usd_observed_own"] for r in memrows),
    sum(rows[r]["usd_observed_opus55"] for r in memrows),
]
mem_agents = [
    sum(row(r)["agents"][0] for r in memrows),
    sum(row(r)["agents"][1] for r in memrows),
]
out["memory_files"] = {
    "own": mem_total[0],
    "o55": mem_total[1],
    "agents_own": mem_agents[0],
    "agents_o55": mem_agents[1],
}

# ---- standalone slim savings (all contexts) and main-only (incremental after lean agents)
slim = {}
for name, f in cut.items():
    r = row(name)
    slim[name] = {
        "cut": f,
        "standalone_own": r["own"] * f,
        "standalone_o55": r["o55"] * f,
        "main_only_own": r["main"][0] * f,
        "main_only_o55": r["main"][1] * f,
    }
out["slim"] = slim

# ---- lean agent type: 80% of agent memory $ (static-prefix method) + agent skill listing + agent deferred names
sk = row("skill listing")["agents"]
dn = row("deferred tool names")["agents"]
lean = {
    "memory_own": 0.8 * mem_agents[0],
    "memory_o55": 0.8 * mem_agents[1],
    "skill_listing_own": sk[0],
    "skill_listing_o55": sk[1],
    "deferred_names_own": dn[0],
    "deferred_names_o55": dn[1],
    "mcp_instructions_growth_own": 86.0 * 3.3 / 4.3,
    "mcp_instructions_growth_o55": 47.8 * 3.3 / 4.3,
}
lean["total_own"] = sum(v for k, v in lean.items() if k.endswith("_own"))
lean["total_o55"] = sum(v for k, v in lean.items() if k.endswith("_o55"))
out["lean_agent_type"] = lean

# ---- memory bundle = lean agents + slims applied to main contexts only (no double count)
b_own = lean["total_own"] + sum(v["main_only_own"] for v in slim.values())
b_55 = lean["total_o55"] + sum(v["main_only_o55"] for v in slim.values())
out["memory_bundle"] = {
    "own": b_own,
    "o55": b_55,
    "share_own": b_own / FLEET,
    "share_o55": b_55 / FLEET55,
}

# ---- long-context tax: main-thread cache-read $ above a prefix threshold (upper bound on what a
#      recycle-at-threshold could remove, before the recycle's own START write + brief)
x = sqlite3.connect(os.path.join(D, "extract.sqlite"))
tax = {}
for T in (200_000, 300_000, 400_000, 500_000):
    q = x.execute(
        "SELECT SUM(MAX(cache_read-?,0)*in_per_mtok*cr_mult/1e6), "
        "SUM(MAX(cache_read-?,0)*4.0*0.05/1e6), SUM(CASE WHEN cache_read>? THEN 1 ELSE 0 END) "
        "FROM resp_priced WHERE xdup=0 AND ctx_type='main'",
        (T, T, T),
    ).fetchone()
    # recycles needed: one per main context whose max prefix exceeds T, per (max-T)/(T-124k) extra laps
    q2 = x.execute(
        "SELECT SUM(1 + (mx-?)/(?-124000)) FROM (SELECT file, MAX(input_tokens+cc_total+cache_read) mx "
        "FROM resp WHERE xdup=0 AND ctx_type='main' GROUP BY file) WHERE mx>?",
        (T, T, T),
    ).fetchone()
    n_rec = q2[0] or 0
    # each recycle: a fresh ~124k START at 1h write (2x) on Opus 5 ($5) / Opus 5.5 ($4)
    rec_own, rec_55 = n_rec * 124_000 * 2 * 5.0 / 1e6, n_rec * 124_000 * 2 * 4.0 / 1e6
    tax[T] = {
        "reads_above_own": q[0],
        "reads_above_o55": q[1],
        "responses_above": q[2],
        "recycles": n_rec,
        "recycle_start_cost_own": rec_own,
        "recycle_start_cost_o55": rec_55,
        "net_upper_own": (q[0] or 0) - rec_own,
        "net_upper_o55": (q[1] or 0) - rec_55,
    }
out["long_context_tax_main"] = tax

json.dump(out, open(os.path.join(D, "synth_opportunities.json"), "w"), indent=1)
print("cut fractions", {k[:30]: round(v, 3) for k, v in cut.items()})
print("memory files", {k: round(v) for k, v in out["memory_files"].items()})
for k, v in slim.items():
    print(
        f"slim {k[:45]:45s} standalone {v['standalone_own']:7.0f}/{v['standalone_o55']:6.0f}  main-only {v['main_only_own']:6.0f}/{v['main_only_o55']:6.0f}"
    )
print("lean agent type", {k: round(v) for k, v in lean.items()})
print("memory bundle", {k: round(v, 3) for k, v in out["memory_bundle"].items()})
for T, v in tax.items():
    print(T, {k: round(v2 or 0) for k, v2 in v.items()})
