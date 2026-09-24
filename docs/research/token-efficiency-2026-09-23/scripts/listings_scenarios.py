#!/usr/bin/env python3
"""Listing-size scenarios on the latest real claude-infrastructure main listing (ESTIMATED).

S0 current · S1 the 20 proposed descriptions · S2 S1 + every other own description cut to 250
chars (proxy for a rewrite) · S3 S2 + skillOverrides name-only for 8 bundled skills with 0
invocations in 14 d · S4 S1 with skillListingBudgetFraction 0.005 (15,000-char budget).
Reuses simulate() and PROPOSED from listings_simulate.py.
Usage: python3 listings_scenarios.py <raw_dir> <claude.json> <cost.json> <out.json>
"""

import importlib.util, json, os, sys

RAW, CJ, COST, OUT = sys.argv[1:5]
here = os.path.dirname(os.path.abspath(__file__))
argv = sys.argv
sys.argv = ["x", RAW, CJ, os.devnull]
spec = importlib.util.spec_from_file_location(
    "sim", os.path.join(here, "listings_simulate.py")
)
sim = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sim)
sys.argv = argv

lat = json.load(open(os.path.join(RAW, "latest_listing_entries.json")))
fm = {
    x["name"]: x
    for x in sorted(json.load(open(os.path.join(RAW, "frontmatter.json"))), key=lambda x: x["kind"] == "skill")  # skill beats same-named command
    if x["kind"] != "agent"
}
score = sim.score_map(CJ)
ents = [e["name"] for e in lat["entries"]]
BUNDLED = {
    "dataviz",
    "update-config",
    "keybindings-help",
    "code-review",
    "simplify",
    "fewer-permission-prompts",
    "loop",
    "schedule",
    "claude-api",
    "workflow-authoring",
    "claude-in-chrome",
    "run",
}
UNUSED_BUNDLED = [
    "dataviz",
    "keybindings-help",
    "fewer-permission-prompts",
    "loop",
    "schedule",
    "run",
    "claude-in-chrome",
    "simplify",
]
fixed0 = {
    e
    for e in ents
    if e.startswith("anthropic-skills:") or e in ("init", "security-review")
}
actual = {e["name"]: e for e in lat["entries"]}


def full(name, d=None, cap=None):
    if name in fm:
        x = fm[name]
        s = (
            d
            if d is not None
            else (
                x["description"]
                + (" - " + x["when_to_use"] if x["when_to_use"] else "")
            )
            or x["first_heading"][:100]
        )
        if cap:
            s = s[:cap]
        return len(name) + 4 + min(len(s), sim.MAXD)
    return actual[name]["chars"]


def run(lens, fixed, budget):
    sim.BUDGET = budget
    got, total, mode = sim.simulate(ents, lens, BUNDLED - fixed, fixed, score)
    return dict(
        mode=mode,
        entry_chars=total,
        described=len(got),
        nameonly=sorted(e for e in ents if e not in got and e not in fixed0),
    )


base = {e: full(e) for e in ents}
s1 = dict(base)
s1.update({k: full(k, v) for k, v in sim.PROPOSED.items() if k in s1})
s2 = {
    e: (s1[e] if e in sim.PROPOSED or e not in fm else full(e, cap=250)) for e in ents
}
s3 = dict(s2)
s3.update({e: len(e) + 2 for e in UNUSED_BUNDLED})
res = {
    "S0_current": run(base, fixed0, 30000),
    "S1_20_proposals": run(s1, fixed0, 30000),
    "S2_all_own_le_250": run(s2, fixed0, 30000),
    "S3_S2_plus_nameonly_unused_bundled": run(s3, fixed0 | set(UNUSED_BUNDLED), 30000),
    "S4_S1_budget_fraction_0.005": run(s1, fixed0, 15000),
    "S5_S2_budget_fraction_0.005": run(s2, fixed0, 15000),
}
res["S0_current"]["note"] = (
    "real rendered listing: 30,103 chars incl. an ~82-char header; the simulation is len()-based, the binary uses Bun.stringWidth"
)
cost = json.load(open(COST))["static_token_value"]["all"]
for k, v in res.items():
    d = res["S0_current"]["entry_chars"] - v["entry_chars"]
    v["chars_saved_vs_S0"] = d
    v["tokens_saved_per_context@3cpt"] = round(d / 3)
    v["usd14d_saved_if_all_contexts_own"] = round(
        d / 3 / 1000 * cost["usd_per_1k_tokens_own"], 1
    )
    v["usd14d_saved_if_all_contexts_o55"] = round(
        d / 3 / 1000 * cost["usd_per_1k_tokens_o55"], 1
    )
json.dump(res, open(OUT, "w"), indent=1)
for k, v in res.items():
    print(k, {x: v[x] for x in v if x != "nameonly"}, "nameonly:", len(v["nameonly"]))
