# Rank 2: the flag-level workaround for the missing setup breakpoint (wave 2, item 5, 2026-09-24)

**Verdict: the workaround works for default-type workflow agents and is NOT switched on. Conviction 85% that holding is
right.** Appending the memory files to the system prompt (`claudeMdExcludes` + `--append-system-prompt-file`, and
`CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT=1` + `--append-subagent-system-prompt-file` for agents) cut a cold 3-slot
workflow run's cache writes from 274k to 128k tokens (−53%, $1.67 → $0.82 by `cc-token-ledger --task`). But it moves
every session's always-loaded instructions (~70k tokens) from the first user message into the system role, which by
this wave's rule needs the full F1 quality gate before it ships (~200 runs), and it needs a `claudeMdExcludes` for
every account (a c10 settings change) plus per-cwd memory assembly in the launcher. Next step, not started: F1 with a
`sys` arm built by `eval/harness/r2-exp.sh`'s recipe.

## What the report assumed, re-measured on 2.1.280

The pass found sibling workflow agents sharing only the ~10-19k system+tools block, because the memory files ride in the
first user message after the only system breakpoint. Measured today over this machine's workflow runs (first request of
each agent, by agentType from `.meta.json`):

| agentType | position | n | first-request read (median) | write (median) | write < 5k |
|---|---|---:|---:|---:|---:|
| workflow-subagent (default) | first in run | 15 | 0 | 74,958 | 0% |
| workflow-subagent (default) | later sibling | 153 | 5,622 | 105,447 | 4% |
| workflow-lean | first in run | 14 | 0 | 7,126 | 14% |
| workflow-lean | later sibling | 170 | 4,609 | 2,472 | 99% |

So the problem is real for default-type workflow slots, and `workflow-lean` (now the default for read-only slots) already
removes most of it by carrying ~7k of setup instead of ~70k. **Agent-tool subagents behave differently:** in the base arm
below, `general-purpose` siblings with three different briefs each read the whole ~70.6k setup from cache (12 of 12
siblings, 0 first-request writes), so the workaround adds nothing for them.

## Experiment

`eval/harness/r2-exp.sh` (Agent-tool subagents) and `r2-exp-wf.sh` (a Workflow with three `agent()` slots), aggregated by
`r2-agg.py` and `cc-token-ledger --task --quick`. One scratch repo, headless Opus 5.5, auto mode, the live memory files
(global CLAUDE.md, mission board, rules essay) byte-identical in both arms; three read-only slots with different briefs.
Runs 1 of each arm are cold; later runs in an arm reuse what the earlier run cached, as sessions in one cwd within the
TTL would. Capacity-gate refusals (machine load ~29/core) contaminated the first Agent-tool reps; those are marked and
excluded, and later reps ran with `CC_ADMIT_GATE=off`.

| Workflow run | slot first requests (read / write) | tree cache writes | tree $ |
|---|---|---:|---:|
| base r1 (cold) | 0 / 69,681 · 5,458 / 64,223 · 5,458 / 64,222 | 274,412 | 1.674 |
| sys r1 (cold) | 0 / 69,769 · 54,437 / 15,332 · 54,437 / 15,331 | 127,873 | 0.824 |
| base r2 (warm) | 69,681 / 0 ×3 | 72,466 | 0.706 |
| sys r2 (warm) | 69,769 / 0 ×3 | 21,481 | 0.313 |

On a cold run a later sibling writes 15k instead of 64k (−76%); the main thread of a second session in the same cwd reads
61k of memory from cache instead of 12k (Agent-tool arm: main first-request write 20,400 vs 69,291 in every warm rep).

**Why hold, at 85%.** The saving that remains after `workflow-lean` sits in default-type workflow slots (code-writing,
judges, synthesis; $693 of worker spend on 2026-09-24 alone) and in same-cwd main-thread restarts. Capturing it means
changing where every session reads its instructions, plus a fleet settings change and launcher work, and the one quality
measurement that would license it (F1) was not run. Two further costs are unmeasured: instructions edited mid-session
would no longer be re-attached, and nested CLAUDE.md files would need the same treatment.
