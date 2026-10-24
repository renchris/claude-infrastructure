#!/usr/bin/env python3
"""Draw 20 lean and 20 default read-only check slots with similar briefs (role verify / skeptic /
refute / critic / judge / review; refined class `none`, i.e. no Skill/MCP/git mutation/code write),
seed 20261024. Default side: 10 from the agentsync B13 rounds and 10 from other workflows, because
B13 is 68% of default slots. Prints one card per slot: brief head, outcome counters, final return.
Writes sample.jsonl. Read-only."""

import json, os, re, random, collections

D = os.path.dirname(os.path.abspath(__file__))
runs = {
    json.loads(l)["runId"]: json.loads(l) for l in open(os.path.join(D, "runs.jsonl"))
}
rows = [json.loads(l) for l in open(os.path.join(D, "slots.jsonl"))]
n2 = {
    json.loads(l)["aid"]: json.loads(l)["cls"]
    for l in open(os.path.join(D, "needs2.jsonl"))
}
ROLE = re.compile(r"^(verify|skeptic|refute|critic|judge|review)", re.I)


def eligible(r):
    if not ROLE.match(r["desc"] or ""):
        return False
    if r["agentType"] == "workflow-subagent":
        return n2.get(r["aid"]) == "none"
    if r["agentType"] == "workflow-lean":
        return not (r["git_mut_real"] or r["writes_repo_code"] or r["git_mut_sandbox"])
    return False


def name(r):
    return (runs.get(r["wf"]) or {}).get("name") or "?"


def last_so(path):
    so = None
    so_err = None
    with open(path, "rb") as fh:
        for line in fh:
            if b"StructuredOutput" not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            for c in (d.get("message") or {}).get("content") or []:
                if (
                    isinstance(c, dict)
                    and c.get("type") == "tool_use"
                    and c.get("name") == "StructuredOutput"
                ):
                    so = c.get("input")
    return so


random.seed(20261024)
lean = [r for r in rows if r["agentType"] == "workflow-lean" and eligible(r)]
dflt = [r for r in rows if r["agentType"] == "workflow-subagent" and eligible(r)]
b13 = [r for r in dflt if re.match(r"b\d+-round", name(r))]
oth = [r for r in dflt if not re.match(r"b\d+-round", name(r))]
print(f"pool: lean {len(lean)}, default {len(dflt)} (b13 {len(b13)}, other {len(oth)})")
pick = (
    [("lean", r) for r in random.sample(lean, 20)]
    + [("default-b13", r) for r in random.sample(b13, 10)]
    + [("default-other", r) for r in random.sample(oth, 10)]
)
out = open(os.path.join(D, "sample.jsonl"), "w")
for arm, r in pick:
    so = last_so(r["path"])
    card = {
        "arm": arm,
        "aid": r["aid"],
        "wf": r["wf"],
        "name": name(r),
        "desc": r["desc"],
        "nreq": r["nreq"],
        "first_tokens": r["first_tokens"],
        "tool_errors": r["tool_errors"],
        "denials": r["safety_denials"] + r["cls_denials"] + r["user_rejects"],
        "hook_blocks": r["hook_blocks"],
        "interrupts": r["interrupts"],
        "api_errors": r["api_errors"],
        "so_errors": r["so_errors"],
        "bash_long_fg": r["bash_long_fg"],
        "final_kind": r["final_kind"],
        "err_samples": r["err_samples"],
        "brief_head": " ".join(r["brief"].split())[:700],
        "so": so,
        "final_text": r["final_text"][:400],
        "path": r["path"],
    }
    out.write(json.dumps(card) + "\n")
    print(
        f"\n### [{arm}] {card['name']} :: {card['desc']} nreq={card['nreq']} first={card['first_tokens']} err={card['tool_errors']} deny={card['denials']} hook={card['hook_blocks']} intr={card['interrupts']} api={card['api_errors']} so_err={card['so_errors']} longfg={card['bash_long_fg']} final={card['final_kind']}"
    )
    print("  BRIEF:", card["brief_head"][:420])
    print("  RETURN:", (json.dumps(so)[:600] if so else card["final_text"][:400]))
    if card["err_samples"]:
        print("  ERRS:", " || ".join(e[:160] for e in card["err_samples"][:3]))
