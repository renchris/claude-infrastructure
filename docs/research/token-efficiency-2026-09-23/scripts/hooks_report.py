#!/usr/bin/env python3
"""Assemble measure/hooks.json from the hook inventory (hooks_enumerate.py), the cost pass
(hooks_cost.py -> measure/hooks_cost.json), the SessionStart audit, the repeat-rate pass and the
ranked cuts; also write measure/hooks_inventory_table.md (the 104-row hook table for hooks.md).
Run after the other hooks_*.py scripts:
  cd /tmp && python3 hooks_enumerate.py > /tmp/hooks_enum.json && python3 hooks_report.py
"""

import json
import re
import subprocess
import sys

BASE = "/Users/chrisren/Development/.worktrees/wt-feat-token-efficiency-2026-09-23/docs/research/token-efficiency-2026-09-23"
enum = json.loads(
    subprocess.run(
        [sys.executable, f"{BASE}/scripts/hooks_enumerate.py"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
)
cost = json.load(open(f"{BASE}/measure/hooks_cost.json"))
audit = json.load(open(f"{BASE}/measure/hooks_sessionstart_audit.json"))
rep = json.load(open(f"{BASE}/measure/hooks_repeat_rate.json"))

inj_by_script = {}
for k, v in cost["injections"].items():
    base = k.split(" [")[0]
    d = inj_by_script.setdefault(base, dict(n=0, usd=0.0, usd55=0.0))
    d["n"] += v["n"]
    d["usd"] += v["usd"]
    d["usd55"] += v["usd_at_opus55"]
forced_by_script = {k: v for k, v in cost["forced"].items()}
EMITS = {}
for h in enum["hooks"]:
    s = h.get("script")
    if not s:
        continue
    try:
        src = (
            open(f"/Users/chrisren/Development/claude-infrastructure/hooks/{s}").read()
            if h["in_repo"]
            else open(f"/Users/chrisren/.claude/hooks/{s}").read()
        )
    except OSError:
        src = ""
    EMITS[s] = ",".join(
        t
        for t, rx in [
            ("additionalContext", r"additionalContext"),
            ("decision:block", r"decision[\"']?\s*:\s*[\"']?block|decision:\"block\""),
            ("systemMessage", r"systemMessage"),
            ("exit2", r"\bexit 2\b"),
            ("permissionDecision", r"permissionDecision"),
        ]
        if re.search(rx, src)
    )
rows = []
for h in enum["hooks"]:
    s = h.get("script")
    i = inj_by_script.get(s, {})
    f = forced_by_script.get(s, {})
    t = cost["cancelled_timeouts"].get(s, 0)
    rows.append(
        dict(
            event=h["event"],
            matcher=h["matcher"] or "*",
            command=h["command"],
            script=s,
            repo_path=h["resolves_to"],
            in_repo=h["in_repo"],
            timeout_s=h["timeout"],
            emits=EMITS.get(s, ""),
            visible_injections_14d=i.get("n", 0),
            injection_usd_14d=round(i.get("usd", 0), 2),
            injection_usd_14d_at_opus55=round(i.get("usd55", 0), 2),
            forced_turns_14d=f.get("n", 0),
            forced_usd_14d=f.get("usd", 0),
            forced_usd_14d_at_opus55=f.get("usd_at_opus55", 0),
            timeouts_14d_incl_copies=t,
        )
    )
with open(f"{BASE}/measure/hooks_inventory_table.md", "w") as fh:
    fh.write(
        "| event | matcher | script (repo `hooks/`) | emits to model | visible inj. 14d | inj. $ own / @5.5 | forced turns | forced $ own / @5.5 | timeouts |\n"
    )
    fh.write("|---|---|---|---|---:|---:|---:|---:|---:|\n")
    for r in rows:
        name = r["script"] or ("`" + r["command"][:48] + "`")
        if r["script"] and not r["in_repo"]:
            name += " (NOT in repo: real file in ~/.claude/hooks)"
        m = r["matcher"] if len(r["matcher"]) < 40 else r["matcher"][:37] + "…"
        fh.write(
            f"| {r['event']} | {m} | {name} | {r['emits'] or '-'} | {r['visible_injections_14d'] or ''} | "
            f"{('%.2f / %.2f' % (r['injection_usd_14d'], r['injection_usd_14d_at_opus55'])) if r['visible_injections_14d'] else ''} | "
            f"{('%.0f' % r['forced_turns_14d']) if r['forced_turns_14d'] else ''} | "
            f"{('%.0f / %.0f' % (r['forced_usd_14d'], r['forced_usd_14d_at_opus55'])) if r['forced_turns_14d'] else ''} | "
            f"{r['timeouts_14d_incl_copies'] or ''} |\n"
        )
cuts = json.load(open(f"{BASE}/measure/hooks_cuts.json"))
out = dict(
    window="2026-09-09T00:00Z .. 2026-09-23T23:02Z (14 d), xdup=0",
    basis_note="counts/chars MEASURED from data/extract.sqlite + data/hooks.sqlite; $ = list-price weights (subscription-billed fleet), "
    "tokens = chars/2.5 (ESTIMATED, fitted in scripts/probe_stop_block_double.py)",
    inventory=dict(
        n_hooks=enum["n_hooks"],
        n_distinct_scripts=enum["n_distinct_scripts"],
        count_by_event=enum["count_by_event"],
        per_config_dir=enum["per_dir"],
        not_in_repo=enum["not_in_repo"],
        hooks=rows,
    ),
    injections=cost["injections"],
    forced_turns=cost["forced"],
    nonvisible=cost["nonvisible"],
    timeouts_incl_copies=cost["cancelled_timeouts"],
    sessionstart_audit=audit,
    repeat_rate=rep,
    cuts=cuts,
)
json.dump(out, open(f"{BASE}/measure/hooks.json", "w"), indent=1, default=str)
print("wrote hooks.json and hooks_inventory_table.md;", len(rows), "hooks")
