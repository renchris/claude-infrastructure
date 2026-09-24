#!/usr/bin/env python3
"""Assemble measure/listings.json from the raw outputs in measure/listings_raw/.
Usage: python3 listings_assemble.py <measure_dir>"""

import json, os, re, sys

M = sys.argv[1]
R = os.path.join(M, "listings_raw")
L = lambda n: json.load(open(os.path.join(R, n)))


def parse_context(path):
    out = dict(categories={}, skills={}, agents={}, memory={}, mcp_loaded_note="")
    sec = None
    for l in open(path):
        if l.startswith("### "):
            sec = l[4:].strip()
            continue
        m = re.match(r"^\| (.+?) \| (.+?) \| (.+?) \|", l)
        if (
            not m
            or m.group(1) in ("Category", "Skill", "Agent Type", "Type", "Tool")
            or m.group(1).startswith("-")
        ):
            continue
        a, b, c = m.group(1).strip(), m.group(2).strip(), m.group(3).strip()
        if sec == "Estimated usage by category":
            out["categories"][a] = b
        elif sec == "Skills":
            out["skills"][a] = dict(source=b, tokens=c)
        elif sec == "Custom Agents":
            out["agents"][a] = dict(source=b, tokens=c)
        elif sec == "Memory Files":
            out["memory"][b] = c
    return out


fm = L("frontmatter.json")
usage = L("usage.json")
render = L("skill_render.json")
trig = L("triggers.json")
ctx = parse_context(os.path.join(R, "context_tmp.txt"))
ctx1 = parse_context(os.path.join(R, "context_tmp_budget1.txt"))
sim = L("simulate.json")
scen = L("scenarios.json")
cost = L("cost.json")
mcp = L("mcp_blocks.json")

skills = []
for x in fm:
    if x["kind"] == "agent":
        continue
    n = x["name"]
    u = usage["skills"].get(n, {})
    ps = render["per_skill"].get(n, {})
    d = sum(v["described"] for v in ps.values())
    no = sum(v["nameonly"] for v in ps.values())
    t = trig["triggers"].get(f"{x['kind']}:{n}", {})
    skills.append(
        dict(
            name=n,
            kind=x["kind"],
            path=x["realpath"],
            frontmatter_desc_chars=x["desc_chars"],
            when_to_use_chars=x["when_to_use_chars"],
            listing_desc_chars=x["listing_desc_chars"],
            strict_yaml_fails=bool(x["yaml_error"]),
            has_frontmatter=x["has_frontmatter"],
            context_tmp_tokens=ctx["skills"].get(n, {}).get("tokens"),
            rendered_listings_described=d,
            rendered_listings_nameonly=no,
            described_share=round(d / (d + no), 3) if d + no else None,
            skill_tool_calls_14d=u.get("skill_calls", 0),
            slash_invocations_14d=u.get("slash", 0),
            main_sessions_using=u.get("main_sessions", 0),
            main_session_share=u.get("main_session_share", 0.0),
            declared_trigger_phrases=t.get("declared_triggers"),
            trigger_phrases_seen_in_prompts=len(t.get("triggers_seen", [])),
            name_mentioned_sessions=t.get("name_mentioned_sessions"),
        )
    )
skills.sort(key=lambda s: -s["listing_desc_chars"])
agents = []
for x in fm:
    if x["kind"] != "agent":
        continue
    n = x["name"]
    agents.append(
        dict(
            name=n,
            desc_chars=x["desc_chars"],
            context_tmp_tokens=ctx["agents"].get(n, {}).get("tokens"),
            listing_entry_median_chars=trig["agent_listing"]["per_agent"]
            .get(n, {})
            .get("median_chars"),
            agent_tool_spawns_14d=usage["agent_tool_spawns_by_type"].get(n, 0),
            workflow_agent_files_14d=usage["agent_files_by_type"].get(
                f"workflow_agent:{n}", 0
            ),
            subagent_files_14d=usage["agent_files_by_type"].get(f"subagent:{n}", 0),
            omitClaudeMd=x["omitClaudeMd"],
            model=x["model"],
            in_repo=os.path.exists(
                f"/Users/chrisren/Development/claude-infrastructure/agents/{n}.md"
            ),
        )
    )
out = dict(
    generated_by="scripts/listings_assemble.py",
    window="2026-09-09T00:00Z .. 2026-09-23T23:02Z (extract build of record)",
    context_from_tmp=dict(
        default=ctx["categories"],
        budget_1_char=ctx1["categories"],
        note="headless /context from /tmp, claude 2.1.280, claude-opus-5-5[1m]; per-skill figures are Claude Code estimates (chars/3)",
    ),
    binary_listing_logic=dict(
        budget="SLASH_COMMAND_TOOL_CHAR_BUDGET if set, else floor(contextWindow * bytesPerToken * skillListingBudgetFraction)",
        defaults=dict(
            skillListingBudgetFraction=0.01,
            bytesPerToken="3 for Opus 5.x/Fable/Sonnet 5; 4 for pre-5 models",
            contextWindow_default=200000,
            skillListingMaxDescChars=1536,
        ),
        effective_budget_chars={
            "1M window, Opus 5.x/Fable": 30000,
            "200k window, Opus 5.x": 6000,
            "200k window, pre-5 model": 8000,
        },
        entry='"- name: " + (description [+ " - " + when_to_use]) cut to 1536 chars with an ellipsis',
        over_budget="bundled prompt skills keep full text; skillOverrides name-only stay name-only; all others start name-only and are given their full text greedily in usage-score order (usageCount * max(0.5^(days/7), 0.1), from <configdir>/.claude.json skillUsage) while the increment fits",
        settings=[
            "skillListingBudgetFraction",
            "skillListingMaxDescChars",
            "skillOverrides {name: on|name-only|user-invocable-only|off}",
            "disableBundledSkills",
        ],
        no_listing_when="the context tool set lacks the Skill tool (fn yCn returns [])",
        sources="claude.exe 2.1.280 fns nUe, JBt, yCn, Fmt, LYe, qke, xf (byte offsets ~178.77M, ~180.34M, ~180.44M)",
    ),
    rendered_listing_sizes=render["sizes"],
    rendered_listing_counts=render["listings"],
    skills=skills,
    agents=agents,
    agent_listing=trig["agent_listing"],
    usage_summary=dict(
        n_main_sessions=usage["n_main_sessions"],
        skill_tool_calls=usage["skill_tool_total"],
        skill_tool_errors=usage["skill_tool_errors"],
        main_sessions_with_skill_call=usage["main_sessions_with_any_skill_call"],
        slash_commands=usage["skills"].get("(unnamed local-command output)"),
    ),
    mcp=dict(
        servers=usage["mcp_servers"],
        instructions_delta=usage["mcp_instructions_delta"],
        deferred_tools_delta=usage["deferred_tools_delta"],
        per_ctx_blocks=mcp,
        loaded_tools_tokens=dict(
            total=629,
            tools=[
                "mcp__claude_ai_Claude_Docs__batch (156)",
                "guide (191)",
                "update (282)",
            ],
            calls_14d=0,
        ),
    ),
    toolsearch=dict(
        calls=usage["toolsearch_calls"],
        errors=usage["toolsearch_errors"],
        targets=usage["toolsearch_targets"],
        only_toolsearch_responses=cost["toolsearch_only_responses"],
    ),
    cost=dict(
        by_kind=cost["by_kind"],
        by_kind_ctx=cost["by_kind_ctx"],
        skill_listing_by_ctx_agent=cost["skill_listing_by_ctx_agent_project"],
        static_token_value=cost["static_token_value"],
        fleet_total=cost["fleet_total"],
        method=cost["method"],
    ),
    simulation=dict(
        validation=sim["validation"], after_20_proposals=sim["after"], scenarios=scen
    ),
    proposed_skill_descriptions=sim["proposals"],
    proposed_agent_descriptions=sim["agent_proposals"],
)
out["opportunities"] = [
    dict(rank=1, category="flag", change="Rewrite every own skill/command description to <=250 chars (20 drafted)", est_saving_14d="<=  own /  Opus 5.5 (S2); S1 alone /", quality_risk="low", all_skills_described=True),
    dict(rank=2, category="flag", change="Drop Skill from tools: of deep-research and deep-research-sonnet (no listing sent)", est_saving_14d=" own /  Opus 5.5", quality_risk="low", cost="3 Skill calls in 14 d"),
    dict(rank=3, category="propose", change="Lean custom agentType for Workflow slots (explicit tools, no Skill/MCP) instead of workflow-subagent tools:[*]", est_saving_14d="/ skill listing + <= / MCP blocks", quality_risk="medium"),
    dict(rank=4, category="flag", change="skillOverrides name-only for 8 bundled skills with 0 uses", est_saving_14d=" own /  Opus 5.5 beyond S2", quality_risk="low"),
    dict(rank=5, category="propose", change="Scope ms365 out of user MCP config (3.0% of main sessions use it)", est_saving_14d="~ own / ~ Opus 5.5", quality_risk="medium"),
    dict(rank=6, category="propose", change="Disable the unused claude.ai Claude Docs connector (629 loaded tool tokens + 1,895-char instructions)", est_saving_14d="~ own /  Opus 5.5 going forward", quality_risk="low"),
    dict(rank=7, category="flag", change="Tighten 3 agent descriptions (-2,203 chars)", est_saving_14d=" own /  Opus 5.5", quality_risk="low"),
    dict(rank=8, category="propose", change="Upstream: do not defer WebSearch/WebFetch for agents that list them in tools:", est_saving_14d=" own /  Opus 5.5 (412 ToolSearch-only turns)", quality_risk="low"),
]
json.dump(out, open(os.path.join(M, "listings.json"), "w"), indent=1)
print(
    "wrote",
    os.path.join(M, "listings.json"),
    len(skills),
    "skills",
    len(agents),
    "agents",
)
