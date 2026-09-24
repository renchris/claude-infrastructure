#!/usr/bin/env python3
"""Add the curated sections (top-10 with fixes, hook false-positive $, harness-bug candidates) to
measure/tool-errors.json. Run AFTER tool_errors.py and hook_deny_false_positives.py.

The $ figures are read from the JSON (MEASURED counts, ESTIMATED $ per tool_errors.py's method).
The fix text and the removable fraction are judgement calls (ESTIMATED), stated per row.
"""

import json, os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
P = os.path.join(BASE, "measure", "tool-errors.json")
d = json.load(open(P))
fp = json.load(open(os.path.join(BASE, "measure", "tool-errors-hook-fp.json")))
pat = {x["key"]: x for x in d["by_pattern"]}

GENERIC_BASH = {
    "other (command output)",
    "python traceback",
    "no output",
    "git fatal",
    "command not found",
    "pre-commit hook",
    "ImageMagick",
}

FIXES = {
    "permission_denied | deny rule / non-interactive ask": dict(
        fix="Permission 'ask'/deny rules fire on compound commands (cd <worktree> && ..., scratchpad "
        "writes under /private/tmp/claude-*, rm -rf of /tmp dirs, .env reads). In workflow agents and "
        "subagents nobody can answer an ask, so every hit is a denial plus a retry. Operator reviews "
        "cc-permission-audit / the fewer-permission-prompts scan and adds narrow allow rules for the "
        "recurring safe shapes; agent briefs stop requesting ask-gated actions.",
        category="propose",
        removable=(0.4, 0.6),
        why="authorization is operator-owned (CLAUDE.md § Manual-Command Delivery)",
    ),
    "auto_mode_classifier_denial | classifier deny": dict(
        fix="Classifier denials concentrate in main threads (204 of 230), 24 contexts hit it 3+ times. "
        "Review the denied command shapes and allow-list the recurring safe ones; nothing to add to "
        "the prompt (the harness text already says to try another route).",
        category="propose",
        removable=(0.3, 0.5),
        why="changes what auto mode may run",
    ),
    "harness_guard | sleep N followed by (built-in)": dict(
        fix="The model polls background output with `sleep N; cat|tail <output file>`, which 2.1.280 "
        "refuses. Add one plain line to CLAUDE.md: 'The Bash tool refuses `sleep N` followed by "
        "another command. Wait for background work with Monitor (until-loop) or the automatic "
        "completion notification.' ~40 resident tokens (~$3/14 d of cache reads at fleet volume).",
        category="flag",
        removable=(0.7, 0.9),
        why="system prompt edit",
    ),
    "hook_deny | agent-teams-enforce.sh: capacity-admit refusal": dict(
        fix="agent-teams-enforce.sh refuses Agent spawns under machine load; 13 of 32 contexts retried "
        "3+ times (max 12). Make the hook wait-then-admit (bounded queue) instead of refusing, or have "
        "the refusal state when capacity is expected back and say 'do this step in-session now', so a "
        "refusal does not cost a full-context retry turn.",
        category="direct",
        removable=(0.5, 0.7),
        why="fix for a recurring tool error; hook-local, revertible",
    ),
    "file_not_read | edit/write before read": dict(
        fix="79 of 109 hit a file this context had already read through Bash (cat/sed/grep): auto mode "
        "tells the model to read with cat/sed, and Edit/Write accept only files opened with Read. Add "
        "one line: 'Edit and Write accept only files opened with the Read tool in this context; a "
        "Bash cat/sed read does not count.'",
        category="flag",
        removable=(0.7, 0.8),
        why="system prompt edit",
    ),
    "structured_output_schema | required property missing": dict(
        fix="Workflow agents' final StructuredOutput omits required properties (headline/findings/...), "
        "costing one extra full-context response each. Workflow scripts should name the required "
        "fields in the agent prompt (the workflow-authoring skill can say so) and keep schemas flat.",
        category="flag",
        removable=(0.4, 0.6),
        why="subagent prompting",
    ),
    "bash_nonzero_exit | zsh (eval) parse / alias / not-found": dict(
        fix="The Bash tool runs zsh with the user's aliases: 34 errors are 'defining function based on "
        "alias' (g, t, gg, rd), the rest bash-isms zsh rejects. Guard those aliases for Claude Code "
        "shells (CLAUDECODE is set) and test CLAUDE_CODE_SHELL=/bin/bash for agent contexts "
        "(present in the 2.1.280 binary; operator helpers are zsh functions, so test first).",
        category="flag",
        removable=(0.3, 0.6),
        why="changes the execution environment",
    ),
    "hook_deny | validate-bash.sh: dangerous pattern (rm -rf / sudo rm)": dict(
        fix="13 of 24 denies had the trigger text only inside a heredoc or a quoted string (writing a test "
        "or script file). Strip heredoc bodies and quoted literals before matching (same defect in "
        "the git-identity, git add -f, git commit -n and DDL rules).",
        category="direct",
        removable=(0.5, 0.55),
        why="fix for a recurring hook false positive; covered by the hook's bats suites",
    ),
    "hook_deny | validate-bash.sh: background park under live /goal": dict(
        fix="The hook denies a backgrounded wait under a live /goal; the CLAUDE.md recipe block still "
        "shows the backgrounded cc-await-ping line, and the model copies it. Drop that line from "
        "the default recipe (keep it in the handoff command doc).",
        category="flag",
        removable=(0.5, 0.7),
        why="system prompt edit",
    ),
    "input_validation | stale task id / missing param / binary read": dict(
        fix="TaskStop/TaskOutput on finished or unknown task ids. Expected error; one context carries "
        "most of the recovery $ (10-response window). No harness change proposed.",
        category=None,
        removable=(0, 0),
        why="expected, low volume",
    ),
}

EXTRA = {
    "harness_guard | subagent report-file Write blocked (built-in)": dict(
        fix="skills/research-subagents/SKILL.md:237 tells subagents to write /abs/path/report-<agent>.md; "
        "2.1.280 blocks subagent writes matching ^(REPORT|SUMMARY|FINDINGS|ANALYSIS).*\\.md "
        "(tengu_subagent_md_report_blocked; lowercase 'report-' is blocked too), so the findings come "
        "back inline instead. Rename the artifact (e.g. <agent>.notes.md).",
        category="direct",
        removable=(0.9, 1.0),
        why="skill text conflicts with a harness built-in",
    ),
    "hook_deny | curl-gate.py: curl-gate parse/internal failure": dict(
        fix="curl-gate.py fails closed when shlex cannot parse the command (21 denies). Fall back to a "
        "token scan instead of denying.",
        category="direct",
        removable=(0.8, 1.0),
        why="hook bug",
    ),
}

top = []
for x in d["by_pattern"]:
    cat, sub = x["key"].split(" | ", 1)
    if cat == "bash_nonzero_exit" and sub in GENERIC_BASH:
        continue
    top.append(x)
top10 = top[:10]
rows = []
for x in top10 + [pat[k] for k in EXTRA if k in pat]:
    f = FIXES.get(x["key"]) or EXTRA.get(x["key"]) or {}
    lo, hi = f.get("removable", (0, 0))
    rows.append(
        dict(
            pattern=x["key"],
            count=x["count"],
            contexts=x["contexts"],
            by_ctx_type=x["by_ctx_type"],
            usd_error_result=x["usd_error_result"],
            usd_recovery=x["usd_recovery"],
            usd_recovery_lower_bound=x["usd_recovery_lower_bound"],
            recovery_responses=x["recovery_responses"],
            usd_total=x["usd_total"],
            usd_total_at_opus55=x["usd_total_at_opus55"],
            fix=f.get("fix"),
            category=f.get("category"),
            category_why=f.get("why"),
            removable_fraction=[lo, hi],
            est_saving_usd_14d=[
                round(x["usd_total"] * lo, 2),
                round(x["usd_total"] * hi, 2),
            ],
            est_saving_usd_14d_at_opus55=[
                round(x["usd_total_at_opus55"] * lo, 2),
                round(x["usd_total_at_opus55"] * hi, 2),
            ],
            in_top10=x in top10,
        )
    )
d["top10_non_generic"] = rows

FP_MAP = {
    "Dangerous command pattern blocked": "hook_deny | validate-bash.sh: dangerous pattern (rm -rf / sudo rm)",
    "git identity write": "hook_deny | validate-bash.sh: git identity write",
    "git add -f blocked": "hook_deny | validate-bash.sh: git add -f",
    "git add --force blocked": "hook_deny | validate-bash.sh: git add -f",
    "git commit -n blocked": "hook_deny | validate-bash.sh: git commit -n",
    "DDL blocked": "hook_deny | validate-bash.sh: DDL keyword (Drizzle rule)",
    "--no-verify blocked": "hook_deny | validate-bash.sh: --no-verify",
}
fps, agg = [], {}
for rule, key in FP_MAP.items():
    if rule not in fp or key not in pat:
        continue
    r = fp[rule]
    n_fp = r.get("only inside quotes/heredoc", 0) + r.get("act absent", 0)
    a = agg.setdefault(key, [0, 0])
    a[0] += r["n"]
    a[1] += n_fp
for key, (n, n_fp) in agg.items():
    x = pat[key]
    fps.append(
        dict(
            pattern=key,
            checked=n,
            likely_false_positive=n_fp,
            usd_total=x["usd_total"],
            usd_false_positive_est=round(x["usd_total"] * n_fp / n, 2),
            usd_false_positive_est_at_opus55=round(
                x["usd_total_at_opus55"] * n_fp / n, 2
            ),
        )
    )
d["hook_false_positives"] = dict(
    method="scripts/hook_deny_false_positives.py: full command from the raw transcript; the act regex is run "
    "on the command with heredoc bodies and quoted strings stripped. 'only inside quotes/heredoc' or "
    "'act absent' = likely false positive (ESTIMATED; `sh -c '...'` would be a real act the strip hides). "
    "Rules whose act regex is too narrow to judge (pattern kill, git-worktree-guard) are excluded.",
    rows=fps,
    usd_total_est=round(sum(r["usd_false_positive_est"] for r in fps), 2),
    usd_total_est_at_opus55=round(
        sum(r["usd_false_positive_est_at_opus55"] for r in fps), 2
    ),
)

BUG_KEYS = [
    (
        "auto_mode_classifier_unavailable",
        "Auto-mode classifier model (claude-sonnet-5[1m]) timed out or lost its connection; the tool call is denied fail-closed and the model retries. Provider/harness error, not a model mistake.",
    ),
    (
        "hook_deny | curl-gate.py: curl-gate parse/internal failure",
        "curl-gate.py fails closed on a shlex parse error or an internal exception.",
    ),
    (
        "hook_false_positives",
        "validate-bash.sh matches trigger text inside heredocs/quoted strings; its git add -f rule fires on commands with no git add at all (e.g. rm -f + pgrep -f).",
    ),
    (
        "harness_guard | subagent report-file Write blocked (built-in)",
        "Harness built-in blocks a file name our own research-subagents skill prescribes.",
    ),
    (
        "unknown_tool",
        "Calls to tools absent from the context: Grep/Glob (not in 2.1.280's tool set here), WebFetch, SendMessage (disabled for the session).",
    ),
    (
        'input_validation | <tool_use_error>InputValidationError: [ { "code": "custom", ',
        "Bash InputValidationError 'command contains control characters that would be hidden in the approval dialog'.",
    ),
    (
        "hook_deny | (test probe): probe-ask-from-hook",
        "A test probe hook's ask message reached real sessions.",
    ),
    ("unclassified", "Residue the classifier could not place."),
]
bugs = []
for k, why in BUG_KEYS:
    if k == "hook_false_positives":
        h = d["hook_false_positives"]
        bugs.append(
            dict(
                key=k,
                count=sum(r["likely_false_positive"] for r in h["rows"]),
                usd_total=h["usd_total_est"],
                why=why,
            )
        )
        continue
    xs = [x for x in d["by_pattern"] if x["key"] == k or x["key"].startswith(k + " |")]
    if xs:
        bugs.append(
            dict(
                key=k,
                count=sum(x["count"] for x in xs),
                contexts=sum(x["contexts"] for x in xs),
                usd_total=round(sum(x["usd_total"] for x in xs), 2),
                detail=[(x["key"], x["count"], x["example"][:120]) for x in xs[:4]],
                why=why,
            )
        )
d["harness_bug_candidates"] = bugs
json.dump(d, open(P, "w"), indent=1, default=list)
for r in rows:
    print(
        f"{r['count']:5d} {r['contexts']:4d} ${r['usd_total']:7.2f} @55 ${r['usd_total_at_opus55']:6.2f} {r['category']} save={r['est_saving_usd_14d']} {r['pattern'][:80]}"
    )
print(
    "FP",
    d["hook_false_positives"]["usd_total_est"],
    d["hook_false_positives"]["usd_total_est_at_opus55"],
)
for r in fps:
    print("  ", r)
for b in bugs:
    print("BUG", b["key"][:60], b["count"], b["usd_total"])
