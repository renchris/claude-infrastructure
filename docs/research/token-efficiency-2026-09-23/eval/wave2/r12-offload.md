# Rank 12: large non-read Bash output to a file (wave 2, item 6, 2026-09-24)

**Verdict: built, gated, staged for all accounts as migration 0039. Conviction 82% that registering it is net-positive.**
The pass filed rank 12 as "no user-space mechanism". There is one on Claude Code 2.1.280: a PostToolUse hook's
`hookSpecificOutput.updatedToolOutput` replaces the result before the model sees it. For Bash it has to be the
`tool_response` object with `stdout` replaced; a bare string is ignored. Both behaviours were probed headless the same day,
as was the `^Bash$` matcher the registration uses.

## The hook

`hooks/bash-output-offload.sh`. For a Bash result whose stdout is longer than 8,000 chars, from a command that names no
read verb (cat, sed, head, tail, awk, less, nl, bat, jq, grep, rg, diff, git show/diff/log/blame), not backgrounded and
not an image: it saves the full stdout under `${TMPDIR}/claude-bash-output/` and returns the first 40 lines, one pointer line
(total size, the hidden line range, the path, how to read it), up to 30 failure- or warning-looking lines from the hidden
middle with their line numbers, and the last 60 lines. Deliberate reads pass through untouched, because the agent asked
for that text. `CC_BASH_OFFLOAD=0` disables it, and any error fails open. Tests: `tests/bash-output-offload.bats` (5/5, with the
migration).

## Offline gate

`eval/harness/r12/` (`r12-run.sh`, `r12-agg.py`, four tasks). Same arm files and invocation as F1 (Opus 5.5, effort high,
auto mode); the arms differ only in whether `--settings` registers the hook. The tasks print 900-2,000 lines, with the
needed fact in a different place in each: a failing test in the middle (O1, then fix and commit), three warnings in the
middle (O2), the total on the last line (O3), and one stock line in the middle with no failure words (O4). 3 runs per arm
per task, ABBAAB, next4 and next. $15.78.

| task | arm | success | hook fired | $ / run | turns |
|---|---|---:|---:|---:|---:|
| O1 test failure mid-output | off / on | 3/3 / 3/3 | – / 1 | 0.780 / 0.750 | 8.7 / 7.7 |
| O2 warnings mid-output | off / on | 3/3 / 3/3 | – / 0 | 0.623 / 0.621 | 3.3 / 3.0 |
| O3 total on the last line | off / on | 3/3 / 3/3 | – / 0 | 0.620 / 0.620 | 3.0 / 3.0 |
| O4 one fact mid-output | off / on | 3/3 / 3/3 | – / 2 | 0.621 / 0.624 | 3.0 / 3.0 |
| **all** | off / on | **12/12 / 12/12** | 3 | 0.661 / 0.654 | 4.5 / 4.2 |

- **The hook rarely fires on well-behaved agents.** In most runs the agent already piped the script through grep, tail or
  a file itself. The hook targets the population that did not; production has it (rank 12's ≤$453 per 14.96 days is
  measured on real non-read results over 8k chars).
- **Where it fired, nothing was lost.** On both O4 runs the one needed line was in the hidden range with no failure
  words; the agent read the saved file by the path in the pointer and answered 42 correctly. The O1 run fixed and
  committed as usual.
- **Why 82%.** Correctness and turns are unchanged at this n, and the fired cases are the adversarial ones. The saving
  cannot be measured offline at this firing rate, and the pass's estimate rests on production traffic. The residual risk is a
  session that needs a hidden line and does not follow the pointer, which the fired runs did not show.

## Operator step

It needs a settings entry, so it is staged as c10 migration 0039 for every account (the one shared `settings.json`,
refused unless every account is linked, backed up, verified by content):

`bash ~/Development/claude-infrastructure/migrations/0039-bash-output-offload.sh --confirm settings.json`

The entry is its own `"^Bash$"` matcher, outside the collapsible `"Bash"` audit chain that
`config/hook-chains.d/posttooluse-bash` mirrors. The hook rewrites the result, and rewriting hooks run in parallel with
last-write-wins semantics.
