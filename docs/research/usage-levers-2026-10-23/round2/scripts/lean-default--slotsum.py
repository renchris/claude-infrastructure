#!/usr/bin/env python3
"""Summarise slots.jsonl: per agentType counts, needs-default classes, and outcome-failure rates.
Read-only. Usage: slotsum.py [slots.jsonl]"""

import json, sys, collections, re, os

P = (
    sys.argv[1]
    if len(sys.argv) > 1
    else os.path.join(os.path.dirname(os.path.abspath(__file__)), "slots.jsonl")
)
LEAN_TOOLS = {
    "Read",
    "Grep",
    "Glob",
    "Bash",
    "Write",
    "Edit",
    "WebFetch",
    "WebSearch",
    "StructuredOutput",
}
B13 = re.compile(r"^(?:b\d+-)?round\d+|^b13", re.I)


def needs(r):
    if r["skills"]:
        return "skill"
    if r["mcps"]:
        return "mcp"
    if r["agent_tool"]:
        return "agent_tool"
    if r["git_mut_real"]:
        return "git_real"
    if r["writes_repo_code"]:
        return "repo_code_write"
    if r["git_mut_sandbox"]:
        return "git_sandbox"
    extra = set(r["tools"]) - LEAN_TOOLS
    if extra:
        return "nonlean_tool:" + ",".join(sorted(extra))
    return "none"


def main():
    rows = [json.loads(l) for l in open(P)]
    by = collections.defaultdict(list)
    for r in rows:
        by[r["agentType"]].append(r)
    print(
        "slots by agentType",
        {k: len(v) for k, v in sorted(by.items(), key=lambda x: -len(x[1]))},
    )
    for at in ("workflow-subagent", "workflow-lean"):
        rs = by.get(at, [])
        if not rs:
            continue
        c = collections.Counter(needs(r).split(":")[0] for r in rs)
        print(f"\n[{at}] n={len(rs)} needs classes: {dict(c.most_common())}")
        extra = collections.Counter()
        for r in rs:
            for t in set(r["tools"]) - LEAN_TOOLS:
                extra[t] += 1
        print("  non-lean tools used (slots):", dict(extra.most_common(12)))

        def rate(key, cond=lambda v: v > 0):
            k = sum(1 for r in rs if cond(r[key]))
            return f"{k} ({100 * k / len(rs):.1f}%)"

        for key in (
            "tool_errors",
            "safety_denials",
            "timed_denials",
            "cls_denials",
            "user_rejects",
            "interrupts",
            "hook_blocks",
            "api_errors",
            "refusal",
            "bash_long_fg",
        ):
            print(f"  slots with {key}>0: {rate(key)}  total {sum(r[key] for r in rs)}")
        te = sum(r["tool_errors"] for r in rs)
        tc = sum(sum(r["tools"].values()) for r in rs)
        print(f"  tool error rate per call: {te}/{tc} = {100 * te / max(tc, 1):.2f}%")
        so = [r for r in rs if r["so_calls"]]
        print(
            f"  slots calling StructuredOutput: {len(so)}; with an SO validation error: {sum(1 for r in so if r['so_errors'])}"
        )
        fk = collections.Counter((r["final_kind"] or "NONE").split(",")[-1] for r in rs)
        print("  final message last block:", dict(fk.most_common(6)))
        v = collections.Counter()
        for r in rs:
            for k in r["viol"]:
                v[k] += 1
        print("  slots with rule-pattern commands:", dict(v.most_common()))


if __name__ == '__main__':
    main()
