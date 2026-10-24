#!/usr/bin/env python3
# Join headscan (first-request composition) with perfile (7d request counts).
# Token estimates for components use chars/4. Baseline B = first-request input-side total
# minus the first user prompt (chars/4). Weekly baseline volume = sum(B * requests_in_file).
import json, collections

hs = {}
for l in open("/tmp/usage-audit/headscan.jsonl"):
    r = json.loads(l)
    hs[r["path"]] = r
pf = [json.loads(l) for l in open("/tmp/usage-audit/baseline_perfile.jsonl")]
full = json.load(open("/tmp/usage-audit/fullscan.json"))["agg"]
tot_cr = sum(v["cr"] for v in full.values())
tot_cc = sum(v["cc"] for v in full.values())
tot_req = sum(v["req"] for v in full.values())
print(
    f"7d totals (fullscan.json): requests={tot_req} cache_read={tot_cr} cache_create={tot_cc}"
)
comp = collections.Counter()
acct_b = collections.Counter()
acct_req = collections.Counter()
acct_cr = collections.Counter()
kind_b = collections.Counter()
kind_req = collections.Counter()
nomatch = 0
bvol = 0
req_cov = 0


def cat_instr(p, ty):
    p = p or ""
    if p.endswith("/rules/10-session-close.md"):
        return "rules/10-session-close.md (User)"
    if p.endswith("/rules/00-mission-board.md"):
        return "rules/00-mission-board.md (User)"
    if ty == "User" and p.endswith("CLAUDE.md"):
        return "~/.claude/CLAUDE.md (User, via each config dir)"
    if ty == "AutoMem":
        return (
            "MEMORY.md auto-memory ("
            + (
                "claude-infrastructure"
                if "claude-infrastructure" in p
                else "other projects"
            )
            + ")"
        )
    if p.endswith("agent-operating-lessons.md"):
        return "project rules/agent-operating-lessons.md"
    if ty == "Project" and p.endswith("CLAUDE.md"):
        return "project CLAUDE.md"
    return "other project rules"


for f in pf:
    r = hs.get(f["path"])
    acct_req[f["acct"]] += f["req"]
    acct_cr[f["acct"]] += f["cr"]
    if not r or "u" not in r or f["req"] == 0:
        nomatch += 1
        continue
    u = r["u"]
    T = u[0] + u[1] + u[2]
    P = r["prompt_chars"] // 4
    B = max(0, T - P)
    n = f["req"]
    req_cov += n
    bvol += B * n
    acct_b[r["acct"]] += B * n
    kind = "sub:" + str(r.get("agentType")) if r["sub"] else "main"
    kind_b[kind] += B * n
    kind_req[kind] += n
    known = 0
    for p, ty, c in r["instr"]:
        comp[cat_instr(p, ty)] += c / 4 * n
        known += c / 4
    for t, c in r["att"].items():
        name = {
            "skill_listing": "skill_listing attachment",
            "prompt_snapshot": "system prompt text (prompt_snapshot)",
            "agent_listing_delta": "agent_listing attachment",
            "deferred_tools_delta": "deferred_tools_delta attachment",
            "mcp_instructions_delta": "MCP server instructions",
        }.get(t, "other small attachments")
        comp[name] += c / 4 * n
        known += c / 4
    hk = 0
    for at, ev, hn, cmd, c in r["hooks"]:
        if at == "hook_success" and ev == "SessionStart":
            continue  # stdout of SessionStart is surfaced via additional_context/system_message records; avoid double count
        hk += c / 4
    comp["SessionStart+UserPromptSubmit hook injections"] += hk * n
    known += hk
    comp["residual: tool schemas + unlogged system prompt"] += max(0, B - known) * n
print(
    f"files without usage/match: {nomatch}; requests covered by joined files: {req_cov} of {tot_req}"
)
print(
    f"weekly baseline volume sum(B*req) = {bvol / 1e9:.2f}B tokens = {100 * bvol / tot_cr:.1f}% of 7d cache_read ({tot_cr / 1e9:.2f}B)"
)
for a in sorted(acct_b):
    print(
        f"  {a}: baseline vol {acct_b[a] / 1e9:.2f}B, requests {acct_req[a]}, cache_read {acct_cr[a] / 1e9:.2f}B, share {100 * acct_b[a] / max(1, acct_cr[a]):.1f}%, mean B/request {acct_b[a] / max(1, acct_req[a]):.0f}"
    )
print("\nby kind (weekly baseline volume, requests, mean B/request)")
for k, v in kind_b.most_common(10):
    print(f"  {k:28} {v / 1e9:6.2f}B  req={kind_req[k]:6}  meanB={v / kind_req[k]:.0f}")
print(
    "\nTOP components (weekly tokens, chars/4; % of baseline volume; % of cache_read)"
)
for i, (k, v) in enumerate(comp.most_common(14), 1):
    print(
        f"{i:2}. {k:52} {v / 1e9:6.2f}B  {100 * v / bvol:5.1f}% of baseline  {100 * v / tot_cr:5.1f}% of cache_read  per-req avg {v / req_cov:7.0f} tok"
    )
