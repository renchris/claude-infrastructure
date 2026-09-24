#!/usr/bin/env python3
"""Usage side of the listings study, from extract.sqlite only (xdup=0 everywhere). MEASURED.

- Skill tool calls by skill (tool_use_input subkind='Skill', detail = skill name) and slash-command
  prompts (user_prompt subkind='command', detail = command name), per ctx_type; the share of
  main sessions using each at least once; Skill tool error rate.
- Agent spawns by subagent_type (Agent/Task tool_use_input detail = 'subagent_type/name') and
  workflow agents by ctx.agent_type.
- MCP: calls and error rate per server (tool_result subkind 'mcp__<server>__<tool>'), share of main
  sessions calling each server, ToolSearch calls + queries, mcp_instructions_delta and
  deferred_tools_delta chars.
Usage: python3 listings_usage.py <extract.sqlite> <out.json>
"""

import json, sqlite3, sys, collections

DB, OUT = sys.argv[1], sys.argv[2]
con = sqlite3.connect(DB)
q = lambda s, *a: con.execute(s, a).fetchall()

MAIN = """(select file, session_id from ctx where ctx_type='main' and n_resp>0 and n_resp_xdup<n_resp)"""
n_main = q(f"select count(distinct session_id) from {MAIN}")[0][0]
out = dict(n_main_sessions=n_main)


def norm(s):
    s = (s or "").strip()
    return s[1:] if s.startswith("/") else s


# ---- skills
skill = collections.defaultdict(
    lambda: dict(
        skill_calls=0,
        skill_calls_main=0,
        skill_calls_agent=0,
        slash=0,
        main_sessions=set(),
        errors=0,
    )
)
for (
    d,
    ct,
    sid,
    n,
) in q("""select i.detail, c.ctx_type, c.session_id, count(*) from item i join ctx c on c.file=i.file
        where i.kind='tool_use_input' and i.subkind='Skill' and i.xdup=0 group by 1,2,3"""):
    k = norm(d)
    skill[k]["skill_calls"] += n
    skill[k]["skill_calls_main" if ct == "main" else "skill_calls_agent"] += n
    skill[k]["main_sessions"].add(sid)  # agent calls attribute to the parent session
for d, n in q(
    """select i.detail, sum(i.is_error) from item i where i.kind='tool_result' and i.subkind='Skill' and i.xdup=0 group by 1"""
):
    skill[norm(d)]["errors"] += n or 0
for (
    d,
    sid,
    n,
) in (
    q("""select i.detail, c.session_id, count(*) from item i join ctx c on c.file=i.file
        where i.kind='user_prompt' and i.subkind='command' and i.xdup=0 group by 1,2""")
):
    k = norm(d) or "(unnamed local-command output)"
    skill[k]["slash"] += n
    skill[k]["main_sessions"].add(sid)
out["skills"] = {
    k: dict(
        v,
        main_sessions=len(v["main_sessions"]),
        main_session_share=round(len(v["main_sessions"]) / n_main, 4),
    )
    for k, v in sorted(
        skill.items(), key=lambda kv: -(kv[1]["skill_calls"] + kv[1]["slash"])
    )
}
out["skill_tool_total"] = sum(v["skill_calls"] for v in out["skills"].values())
out["skill_tool_errors"] = sum(v["errors"] for v in out["skills"].values())
out["main_sessions_with_any_skill_call"] = (
    q(f"""select count(distinct c.session_id) from item i join ctx c on c.file=i.file
    where i.kind='tool_use_input' and i.subkind='Skill' and i.xdup=0 and c.ctx_type='main'""")[
        0
    ][0]
)

# ---- agents
ag = collections.Counter()
for d, n in q(
    """select i.detail, count(*) from item i where i.kind='tool_use_input' and i.subkind in ('Agent','Task') and i.xdup=0 group by 1"""
):
    ag[(d or "").split("/")[0] or "(none)"] += n
out["agent_tool_spawns_by_type"] = dict(ag.most_common())
out["agent_files_by_type"] = {
    f"{ct}:{t}": n
    for ct, t, n in q(
        """select ctx_type, coalesce(agent_type,'?'), count(*) from ctx where ctx_type!='main' and n_resp_xdup<n_resp group by 1,2 order by 3 desc"""
    )
}
out["agent_listing_delta"] = [
    dict(ctx_type=ct, n=n, chars=c, avg=a)
    for ct, n, c, a in q(
        """select c.ctx_type, count(*), sum(i.chars), round(avg(i.chars)) from item i join ctx c on c.file=i.file
       where i.kind='attachment' and i.subkind='agent_listing_delta' and i.xdup=0 group by 1"""
    )
]

# ---- MCP servers
mcp = collections.defaultdict(
    lambda: dict(
        calls=0, errors=0, main_sessions=set(), files=set(), tools=collections.Counter()
    )
)
for (
    sub,
    sid,
    f,
    n,
    e,
) in q("""select i.subkind, c.session_id, i.file, count(*), sum(i.is_error) from item i join ctx c on c.file=i.file
        where i.kind='tool_result' and i.subkind like 'mcp\\_\\_%' escape '\\' and i.xdup=0 group by 1,2,3"""):
    parts = sub.split("__")
    srv = parts[1] if len(parts) > 2 else sub
    m = mcp[srv]
    m["calls"] += n
    m["errors"] += e or 0
    m["main_sessions"].add(sid)
    m["files"].add(f)
    m["tools"][parts[-1]] += n
out["mcp_servers"] = {
    k: dict(
        calls=v["calls"],
        errors=v["errors"],
        error_rate=round(v["errors"] / v["calls"], 4),
        sessions=len(v["main_sessions"]),
        session_share=round(len(v["main_sessions"]) / n_main, 4),
        top_tools=dict(v["tools"].most_common(8)),
    )
    for k, v in sorted(mcp.items(), key=lambda kv: -kv[1]["calls"])
}
out["mcp_instructions_delta"] = [
    dict(ctx_type=ct, n=n, chars=c, avg=a, max=mx)
    for ct, n, c, a, mx in q(
        """select c.ctx_type, count(*), sum(i.chars), round(avg(i.chars)), max(i.chars) from item i join ctx c on c.file=i.file
       where i.kind='attachment' and i.subkind='mcp_instructions_delta' and i.xdup=0 group by 1"""
    )
]
out["deferred_tools_delta"] = [
    dict(ctx_type=ct, n=n, chars=c, avg=a, max=mx)
    for ct, n, c, a, mx in q(
        """select c.ctx_type, count(*), sum(i.chars), round(avg(i.chars)), max(i.chars) from item i join ctx c on c.file=i.file
       where i.kind='attachment' and i.subkind='deferred_tools_delta' and i.xdup=0 group by 1"""
    )
]

# ---- ToolSearch
ts = q("""select c.ctx_type, count(*), count(distinct c.session_id) from item i join ctx c on c.file=i.file
        where i.kind='tool_use_input' and i.subkind='ToolSearch' and i.xdup=0 group by 1""")
out["toolsearch_calls"] = {ct: dict(calls=n, sessions=s) for ct, n, s in ts}
qs = collections.Counter()
for d, n in q(
    """select detail, count(*) from item where kind='tool_use_input' and subkind='ToolSearch' and xdup=0 group by 1"""
):
    d = d or ""
    if d.startswith("select:"):
        for name in d[7:].split(","):
            name = name.strip()
            key = (
                name.split("__")[1]
                if name.startswith("mcp__") and name.count("__") >= 2
                else name
            )
            qs["select:" + key] += n
    else:
        qs["keyword"] += n
out["toolsearch_targets"] = dict(qs.most_common(40))
out["toolsearch_errors"] = q(
    """select count(*), sum(is_error) from item where kind='tool_result' and subkind='ToolSearch' and xdup=0"""
)[0]

# ---- per-tool first-class: how many main sessions call any deferred (non-core) tool
json.dump(out, open(OUT, "w"), indent=1, default=list)
print(
    "main sessions",
    n_main,
    "skill calls",
    out["skill_tool_total"],
    "errors",
    out["skill_tool_errors"],
    "sessions w/ Skill call",
    out["main_sessions_with_any_skill_call"],
)
