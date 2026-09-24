#!/usr/bin/env python3
"""Assemble measure/static-prefix.json from the /context captures, calibration counts, cost and volatility
outputs, and print the markdown source table used in measure/static-prefix.md."""

import json, os, re

B = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "measure")
RAW = os.path.join(B, "static-prefix-raw")


def parse_context(path):
    out = {
        "categories": {},
        "memory_files": [],
        "custom_agents": [],
        "skills": [],
        "mcp_tools_loaded": 0,
    }
    sec = None
    for ln in open(path):
        ln = ln.rstrip("\n")
        if ln.startswith("**Tokens:**"):
            out["total"] = ln.split("**Tokens:**")[1].strip()
        if ln.startswith("### "):
            sec = ln[4:].strip()
            continue
        if (
            not ln.startswith("| ")
            or ln.startswith("|--")
            or ln.startswith("| Category")
            or ln.startswith("| Tool ")
            or ln.startswith("| Type")
            or ln.startswith("| Agent Type")
            or ln.startswith("| Skill |")
        ):
            continue
        cells = [x.strip() for x in ln.strip("|").split("|")]
        if sec and sec.startswith("Estimated"):
            out["categories"][cells[0]] = cells[1]
        elif sec == "Memory Files":
            out["memory_files"].append(
                {"type": cells[0], "path": cells[1], "tokens": cells[2]}
            )
        elif sec == "Custom Agents":
            out["custom_agents"].append(
                {"agent": cells[0], "source": cells[1], "tokens": cells[2]}
            )
        elif sec == "Skills":
            out["skills"].append(
                {"skill": cells[0], "source": cells[1], "tokens": cells[2]}
            )
        elif sec == "MCP Tools":
            out["mcp_tools_loaded"] += 1
    return out


ctxs = {
    k: parse_context(os.path.join(RAW, f"context_{k}.txt"))
    for k in ("tmp", "infra", "reso")
}
calib = []
for ln in open(os.path.join(RAW, "calib_counts.txt")):
    m = re.match(r"(\S+) chars=(\d+) sysprompt= ([\d.]+)k", ln.strip())
    if m:
        tok = round(float(m.group(3)) * 1000 - 2200)
        calib.append(
            {
                "block": m.group(1),
                "chars": int(m.group(2)),
                "tokens": tok,
                "chars_per_token": round(int(m.group(2)) / tok, 2),
            }
        )
calib.append(
    {
        "block": "infra/skill_listing.md",
        "chars": 30103,
        "tokens": 11200,
        "chars_per_token": 2.69,
    }
)
cost = json.load(open(os.path.join(B, "static-prefix-cost.json")))
vol = json.load(open(os.path.join(B, "static-prefix-volatility.json")))


def where(r):
    ct = r["by_ctx_type"]
    s = r["source"]
    kinds = "+".join(
        k.replace("workflow_agent", "wf").replace("subagent", "sub")
        for k in ("main", "subagent", "workflow_agent")
        if ct.get(k)
    )
    scope = (
        "every context"
        if s.startswith(
            (
                "global",
                "mission",
                "system",
                "skill",
                "deferred",
                "session_context",
                "small",
                "memory-block",
            )
        )
        else (
            "this repo only"
            if "[" in s
            else ("main only" if kinds == "main" else kinds)
        )
    )
    return f"{scope} ({kinds})"


rows = cost["rows"]
fo, f5 = cost["fleet_usd_own"], cost["fleet_usd_opus55"]
print(
    "| source | tokens (median per context) | loaded where | contexts | $ / 14 d, own model | $ / 14 d, at Opus 5.5 | share of fleet $ | of which agents (own) |"
)
print("|---|---:|---|---:|---:|---:|---:|---:|")
for r in rows:
    if r["usd_observed_own"] < 1:
        continue
    ag = sum(v for k, v in r["usd_observed_own_by_ctx_type"].items() if k != "main")
    print(
        f"| {r['source']} | {r['tokens_median']:,} | {where(r)} | {r['contexts']:,} | {r['usd_observed_own']:,.0f} | {r['usd_observed_opus55']:,.0f} | "
        f"{100 * r['share_fleet_observed_own']:.1f}% | {ag:,.0f} |"
    )
st = cost["static_total"]
print(
    f"| **all static attachments (excl. system+tools)** | | | | **{st['usd_observed_own']:,.0f}** | **{st['usd_observed_opus55']:,.0f}** | "
    f"**{100 * st['usd_observed_own'] / fo:.1f}%** | |"
)
json.dump(
    {"context_captures": ctxs, "calibration": calib, "cost": cost, "volatility": vol},
    open(os.path.join(B, "static-prefix.json"), "w"),
    indent=1,
)
print("\nwrote static-prefix.json")
