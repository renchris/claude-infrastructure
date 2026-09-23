#!/usr/bin/env python3
"""Build the --agents JSON for the omitClaudeMd A/B probe (lever 3).

Each candidate agent in agents/ is emitted twice with an IDENTICAL body, tools and model:
  <name>-base   (no omitClaudeMd)      <name>-omit   (omitClaudeMd: true)
so the only difference between the arms is whether CLAUDE.md/rules/MEMORY.md load.
Usage: omit-probe-agents.py <repo> > agents.json
"""
import json, re, sys, pathlib
repo = pathlib.Path(sys.argv[1])
CANDS = ["deep-research", "deep-research-sonnet", "frontier-derivation", "research-decomposition-critic"]
out = {}
for name in CANDS:
    txt = (repo / "agents" / f"{name}.md").read_text()
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", txt, re.S)
    fm, body = m.group(1), m.group(2)
    def field(k):
        mm = re.search(rf"^{k}:\s*(.*)$", fm, re.M)
        return mm.group(1).strip() if mm else None
    tools = [t.strip() for t in (field("tools") or "").split(",") if t.strip()]
    for arm in ("base", "omit"):
        d = {"description": f"probe arm {arm} of {name}; never use for real work", "prompt": body,
             "tools": tools, "model": field("model") or "inherit"}
        if arm == "omit":
            d["omitClaudeMd"] = True
        out[f"{name}-{arm}"] = d
json.dump(out, sys.stdout)
