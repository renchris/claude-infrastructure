#!/usr/bin/env python3
"""Synthesis: one reconciled cost table by SOURCE x BILLING TYPE, built from the measure/ reports.

Run:  cd /tmp && nice -n 10 python3 <dir>/scripts/synth_baseline.py
Writes: <dir>/data/synth_baseline.json  (every number in BASELINE.md's reconciled table)

Partition (list-price weights, xdup=0, 2026-09-09..23):
  fleet $  = input side (census)                 + output (census, output_est)
  input    = initial prefix (growth.json totals)  + growth (growth.json by_source; conserves to 1.0000)
  initial  = static rows (static-prefix-cost.json, 'observed' method)
           + first prompt / brief (priced here with output-formats' W weights, same persistence model)
           + reconciliation residual (method gap, shown, not hidden)
Billing split per row:
  growth rows: usd_write / usd_read / usd_uncached as measured by growth_cost.py
  static rows: write share = spec first-write / spec total (static-prefix-cost.json), applied to 'observed' (ESTIMATED)
  T0 (system+tools): write = zero-read first requests + mid-session rewrites x T0 tokens (ESTIMATED)
  output: census output_est $, split by the token shares of thinking / text / tool_use in growth.json (ESTIMATED)
"""

import json, os, sqlite3

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
M = os.path.join(BASE, "measure")
D = os.path.join(BASE, "data")
J = lambda f: json.load(open(os.path.join(M, f)))

census = J("census.json")
growth = J("growth.json")
spc = J("static-prefix-cost.json")

fleet_own, fleet_55 = spc["fleet_usd_own"], spc["fleet_usd_opus55"]
fl = census["fleet"]


out = {}

# ---------------------------------------------------------------- growth partition
gt = growth["totals"]["ALL"]
initial_own, initial_55 = gt["usd_initial"], gt["usd55_initial"]
growth_own, growth_55 = gt["usd_growth"], gt["usd55_growth"]
input_own, input_55 = gt["usd_input_side"], gt["usd55_input_side"]

# Bash result split by program class (output_formats.sqlite: chars x W, shares only)
of = sqlite3.connect(os.path.join(D, "output_formats.sqlite"))
FILE_READ = {"sed", "cat", "head", "tail", "awk", "nl", "less", "git show", "bat"}
SEARCH = {"grep", "rg", "find", "ls", "fd", "tree", "egrep", "fgrep", "git grep"}
# resp_before is not in tr: join through the extract item table
of.execute("ATTACH ? AS x", (os.path.join(D, "extract.sqlite"),))
rows = of.execute(
    "SELECT t.program, SUM(t.chars*w.w_own), SUM(t.chars*w.w_o55) FROM tr t "
    "JOIN x.item i ON i.file=t.file AND i.tool_use_id=t.tool_use_id AND i.kind='tool_result' "
    "JOIN w ON w.file=i.file AND w.s=i.resp_before WHERE t.tool='Bash' GROUP BY 1"
).fetchall()
cls = {"file_read": [0, 0], "search_list": [0, 0], "other": [0, 0]}
for p, wo, w5 in rows:
    p = (p or "").strip()
    c = "file_read" if p in FILE_READ else "search_list" if p in SEARCH else "other"
    cls[c][0] += wo or 0
    cls[c][1] += w5 or 0
tot_o = sum(v[0] for v in cls.values())
tot_5 = sum(v[1] for v in cls.values())
bash_share = {k: (v[0] / tot_o, v[1] / tot_5) for k, v in cls.items()}
out["bash_result_program_share"] = bash_share

# first prompt / brief (items before response 0), priced with W at fitted tokens/char
TPC = {"user_prompt": 0.440, "meta_user": 0.393}
fp = of.execute(
    "SELECT c.ctx_type, i.kind, SUM(i.chars*w.w_own), SUM(i.chars*w.w_o55), SUM(i.chars), COUNT(*) "
    "FROM x.item i JOIN x.ctx c ON c.file=i.file JOIN w ON w.file=i.file AND w.s=i.resp_before "
    "WHERE i.resp_before=-1 AND i.visible=1 AND i.xdup=0 AND i.kind IN ('user_prompt','meta_user') GROUP BY 1,2"
).fetchall()
first_prompt = {"own": 0.0, "o55": 0.0, "by": []}
for ct, k, wo, w5, ch, n in fp:
    # W is $/token-position; of_analyze divides chars*W by chars/token (c); here tokens = chars*tpc
    first_prompt["own"] += (wo or 0) * TPC[k]
    first_prompt["o55"] += (w5 or 0) * TPC[k]
    first_prompt["by"].append(
        {
            "ctx": ct,
            "kind": k,
            "chars": ch,
            "n": n,
            "usd_own": (wo or 0) * TPC[k],
            "usd_o55": (w5 or 0) * TPC[k],
        }
    )
out["first_prompt_brief"] = first_prompt


# ---------------------------------------------------------------- category map
def cat_growth(src):
    s = src
    if s == "tool_result:Bash":
        return None  # split below
    if s == "tool_result:Read":
        return "file reads"
    if s in (
        "tool_result:WebSearch",
        "tool_result:WebFetch",
        "tool_result:ToolSearch",
        "tool_result:Grep",
        "tool_result:Glob",
    ):
        return "search + web results"
    if (
        s.startswith("tool_result:Agent")
        or s.startswith("tool_result:Workflow")
        or s
        in (
            "user_prompt:task_notification:workflow",
            "user_prompt:task_notification:subagent",
            "tool_result:SendMessage",
            "tool_result:SubagentHandback",
            "tool_result:TaskOutput",
            "tool_result:ListAgents",
        )
    ):
        return "subagent / workflow returns"
    if s.startswith("tool_result:"):
        return "command + other tool output"
    if s in (
        "user_prompt:task_notification:bash",
        "user_prompt:task_notification:monitor",
    ):
        return "command + other tool output"
    if s == "assistant_thinking":
        return "assistant re-read: thinking"
    if s == "assistant_text":
        return "assistant re-read: text"
    if s == "tool_use_input:Bash":
        return "assistant re-read: Bash commands"
    if s.startswith("tool_use_input:"):
        return "assistant re-read: other tool inputs + briefs"
    if s.startswith("attachment:hook_") or s == "meta_user:stop_hook_feedback":
        return "hook injections"
    if s in ("attachment:instructions", "attachment:nested_memory"):
        return "memory files re-attached mid-session"
    if s in (
        "attachment:skill_listing",
        "attachment:mcp_instructions_delta",
        "attachment:deferred_tools_delta",
        "attachment:agent_listing_delta",
        "meta_user:skill_body",
    ):
        return "listings re-sent + skill bodies"
    if s == "context_rewrite_carryover":
        return "history carry-over after context shrink"
    if s == "residual_unattributed":
        return "reconciliation residual"
    if s.startswith("user_prompt:") or s in (
        "meta_user:command_body",
        "attachment:queued_command",
        "meta_user:image_meta",
        "meta_user:local_command_caveat",
        "meta_user:command_marker",
        "meta_user:continue",
    ):
        return "user messages (prompts, commands, peer/teammate mail)"
    return "harness notices (token reminder, edited-file, env, other)"


def cat_static(src):
    if src.startswith("system prompt"):
        return "system prompt + tool schemas"
    if src == "global CLAUDE.md":
        return "memory: global CLAUDE.md"
    if src.startswith("mission board") or src.startswith("global rules"):
        return "memory: global rules (mission board, rules essay)"
    if src.startswith("MEMORY.md"):
        return "memory: MEMORY.md (auto-memory)"
    if src.startswith("project"):
        return "memory: project CLAUDE.md + rules"
    if src == "memory-block wrapper text":
        return "memory: global CLAUDE.md"
    if src in (
        "skill listing",
        "deferred tool names",
        "agent listing",
        "MCP server instructions",
    ):
        return "listings: skills / agents / MCP / deferred names"
    if src.startswith("SessionStart hook") or src.startswith("UserPromptSubmit hook"):
        return "hook injections"
    return "harness notices (token reminder, edited-file, env, other)"


table = {}


def add(cat, part, w=0.0, r=0.0, u=0.0, o=0.0, own=None, o55=0.0):
    t = table.setdefault(
        cat,
        {
            "write": 0.0,
            "read": 0.0,
            "uncached": 0.0,
            "output": 0.0,
            "own": 0.0,
            "o55": 0.0,
            "initial": 0.0,
            "growth": 0.0,
        },
    )
    t["write"] += w
    t["read"] += r
    t["uncached"] += u
    t["output"] += o
    tot = (w + r + u + o) if own is None else own
    t["own"] += tot
    t["o55"] += o55
    t[part] = t.get(part, 0.0) + tot


# static rows
T0 = spc["T0_median"]
ctxn = spc["contexts"]
static_sum_own = static_sum_55 = 0.0
init_entries = []  # [category, est. write, est. read, own $, o55 $]
for row in spc["rows"]:
    own, o55 = row["usd_observed_own"], row["usd_observed_opus55"]
    static_sum_own += own
    static_sum_55 += o55
    if row["source"].startswith("system prompt"):
        # ESTIMATED write: zero-read first requests (main 12%, sub 27%, wf 15%) + mid-session rewrites
        # (static-prefix-cost.json rewrites.static_mostly_rewritten) x T0 tokens x write price at $5 (Opus 5)
        zr = {"main": 0.12, "subagent": 0.27, "workflow_agent": 0.15}
        wm = {"main": 2.0, "subagent": 1.25, "workflow_agent": 1.25}
        t0 = {"main": 20000, "subagent": 9200, "workflow_agent": 15000}
        wr = 0.0
        for c in zr:
            n_zero = zr[c] * ctxn[c]
            n_rw = spc["rewrites"][c]["static_mostly_rewritten"]
            wr += (n_zero + n_rw) * t0[c] * wm[c] * 5.0 / 1e6
        w = min(wr, own)
    else:
        f = (
            row["usd_spec_first_write_own"] / row["usd_spec_own"]
            if row["usd_spec_own"]
            else 0.3
        )
        w = own * f
    init_entries.append([cat_static(row["source"]), w, own - w, own, o55])

# first prompt / brief
fp_own, fp_55 = first_prompt["own"], first_prompt["o55"]
init_entries.append(
    [
        "user messages (prompts, commands, peer/teammate mail)",
        fp_own * 0.3,
        fp_own * 0.7,
        fp_own,
        fp_55,
    ]
)
init_resid_own = initial_own - static_sum_own - fp_own
init_resid_55 = initial_55 - static_sum_55 - fp_55

# Billing reconciliation: the initial partition's write / read / uncached totals are FORCED to equal
# census billing totals minus the growth partition's MEASURED split. The estimated per-row split is
# corrected by moving read -> write in proportion to each row's estimated read (rewrites after TTL
# expiry are writes the spec-formula split does not see).
fb = census["fleet"]["usd"]
tgt_w = (
    fb["cache_write_5m"]
    + fb["cache_write_1h"]
    - sum(x["usd_write"] for x in growth["by_source"])
)
tgt_u = fb["uncached_input"] - sum(x["usd_uncached"] for x in growth["by_source"])
sum_w = sum(e[1] for e in init_entries)
sum_r = sum(e[2] for e in init_entries)
delta = tgt_w - sum_w
for e in init_entries:
    mv = delta * e[2] / sum_r
    add(e[0], "initial", w=e[1] + mv, r=e[2] - mv, own=e[3], o55=e[4])
tgt_r = initial_own - tgt_w - tgt_u
resid_r = tgt_r - (sum_r - delta)
add(
    "reconciliation residual",
    "initial",
    r=resid_r,
    u=tgt_u,
    own=init_resid_own,
    o55=init_resid_55,
)
out["billing_reconciliation"] = {
    "initial_write_target": tgt_w,
    "initial_write_estimated": sum_w,
    "moved_read_to_write": delta,
    "initial_uncached": tgt_u,
}

# growth rows
for x in growth["by_source"]:
    s = x["source"]
    if s == "tool_result:Bash":
        for k, lab in (
            ("file_read", "file reads"),
            ("search_list", "search + web results"),
            ("other", "command + other tool output"),
        ):
            so, s5 = bash_share[k]
            add(
                lab,
                "growth",
                w=x["usd_write"] * so,
                r=x["usd_read"] * so,
                u=x["usd_uncached"] * so,
                own=x["usd"] * so,
                o55=x["usd55"] * s5,
            )
        continue
    add(
        cat_growth(s),
        "growth",
        w=x["usd_write"],
        r=x["usd_read"],
        u=x["usd_uncached"],
        own=x["usd"],
        o55=x["usd55"],
    )
g_sum = sum(x["usd"] for x in growth["by_source"])
add("reconciliation residual", "growth", own=growth_own - g_sum, o55=0.0)

# output generation split by growth token shares
tok = {"think": 0.0, "text": 0.0, "tool": 0.0}
for x in growth["by_source"]:
    s = x["source"]
    if s == "assistant_thinking":
        tok["think"] += x["tokens_appended"]
    elif s == "assistant_text":
        tok["text"] += x["tokens_appended"]
    elif s.startswith("tool_use_input:"):
        tok["tool"] += x["tokens_appended"]
T = sum(tok.values())
out_own = fleet_own - input_own
out_55 = fleet_55 - input_55
labels = {
    "think": "output generated: thinking",
    "text": "output generated: visible text",
    "tool": "output generated: tool calls (commands, file writes, briefs)",
}
for k, lab in labels.items():
    add(
        lab,
        "generation",  # partition name; must not collide with the 'output' billing column
        o=out_own * tok[k] / T,
        own=out_own * tok[k] / T,
        o55=out_55 * tok[k] / T,
    )

# ---------------------------------------------------------------- emit
rows_out = []
for cat, t in table.items():
    rows_out.append(
        dict(
            source=cat,
            **{k: round(v, 2) for k, v in t.items()},
            share_own=round(t["own"] / fleet_own, 4),
            share_o55=round(t["o55"] / fleet_55, 4),
        )
    )
rows_out.sort(key=lambda r: -r["own"])
col = {k: sum(r[k] for r in rows_out) for k in ("write", "read", "uncached", "output")}
out["column_sums_own"] = col
out["census_billing_own"] = {
    "write": fb["cache_write_5m"] + fb["cache_write_1h"],
    "read": fb["cache_read"],
    "uncached": fb["uncached_input"],
    "output": fb["output_est"],
}
print(
    "column sums",
    {k: round(v, 1) for k, v in col.items()},
    "census",
    {k: round(v, 1) for k, v in out["census_billing_own"].items()},
)
out.update(
    {
        "fleet_own": fleet_own,
        "fleet_o55": fleet_55,
        "input_own": input_own,
        "input_o55": input_55,
        "output_own": out_own,
        "output_o55": out_55,
        "initial_own": initial_own,
        "initial_o55": initial_55,
        "growth_own": growth_own,
        "growth_o55": growth_55,
        "static_rows_sum_own": static_sum_own,
        "static_rows_sum_o55": static_sum_55,
        "initial_residual_own": init_resid_own,
        "initial_residual_o55": init_resid_55,
        "growth_rows_sum_own": g_sum,
        "output_token_shares": {k: tok[k] / T for k in tok},
        "table": rows_out,
        "table_sum_own": sum(r["own"] for r in rows_out),
        "table_sum_o55": sum(r["o55"] for r in rows_out),
    }
)
json.dump(out, open(os.path.join(D, "synth_baseline.json"), "w"), indent=1)
print(
    f"fleet own {fleet_own:,.0f} o55 {fleet_55:,.0f} | table sum own {out['table_sum_own']:,.0f} o55 {out['table_sum_o55']:,.0f}"
)
print(
    f"input {input_own:,.0f} = initial {initial_own:,.0f} + growth {growth_own:,.0f}; output {out_own:,.0f}"
)
print(
    f"static rows {static_sum_own:,.0f}/{static_sum_55:,.0f}; first prompt {fp_own:,.0f}/{fp_55:,.0f}; "
    f"initial residual {init_resid_own:,.0f}/{init_resid_55:,.0f}"
)
print("bash shares", {k: tuple(round(x, 3) for x in v) for k, v in bash_share.items()})
print("output token shares", {k: round(tok[k] / T, 3) for k in tok})
for r in rows_out:
    print(
        f"{r['source'][:62]:62s} {r['own']:9.0f} {r['share_own'] * 100:5.1f}% | w{r['write']:7.0f} r{r['read']:7.0f} "
        f"u{r['uncached']:5.0f} o{r['output']:6.0f} | 5.5 {r['o55']:7.0f} {r['share_o55'] * 100:5.1f}%"
    )
for b in first_prompt["by"]:
    print("  first-prompt", b)
