# D6 skeptic review: switch off the per-agent token budget

Reviewed: `/tmp/haiku55-decisions/D6-agent-budget-switch.md`, its 49 rows, the 49 raw streams in
`/tmp/haiku55-decisions/d6/raw/`, `d6/cell.sh`, `d6/score.py`, `d6/key.json`, the three background
notes, and the 2.1.293 binary text. No model calls were made.

## Verdict

**The recommendation survives: add `CLAUDE_CODE_RIPPLING_TULIP=0` to the settings `env` block, and do
not use `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=infinite`. My conviction is 88%, against the worker's 91%.**

Every headline number reproduces. What does not hold up is part of the story around the numbers:

- The write-up says the sub-agent cut its own work short because it saw a countdown. The raw streams
  show a second cause that is perfectly mixed in with the first: the lead wrote a different prompt
  for the sub-agent whenever the budget was on.
- "Silently returning partial work" is not what happened. The partial result was stated in 9 of 9.
- The budget was only tested against real work at 3% and 22% of what the task needed, so the
  "every time" rate says nothing about a realistic value.
- "For good" is not supported. The switch is an undocumented, code-named variable shown to work on
  one binary.

None of these reverses the action, because the action rests on a different pair of facts that did
hold: the switch restores control behavior, and it costs nothing while the server flag is off.

## What I recomputed

All figures below are measured with my own python3 over the raw streams and rows unless marked.

| Claim in the write-up | My result | Match |
|---|---|---|
| 49 rows; 0 of 49 `is_error`; every `stop_reason` `end_turn` | 49 raw files rescored independently, 0 field mismatches against the 49 rows; 0 of 49 errors; 49 of 49 `end_turn`; 49 of 49 `terminal_reason` `completed` | yes |
| 39 valid, 10 dropped (fallback to `claude-opus-4-8`) | 39 and 10; 10 of 29 long-prompt calls dropped | yes |
| Long task: 0 of 9 budget-on finished, 6 of 6 budget-off | codes 4, 2, 2, 3, 1, 0, 0, 0, 0 against 8, 8, 8, 8, 8, 8 | yes |
| Fisher exact p = 0.0002; `=0` alone p = 0.0014 | 1/5005 = 0.0002; 1/715 = 0.0014 | yes |
| Short prompt, 2 of 2 in each of six arms | 12 of 12 show the stated value | yes |
| Parent sentence: `NONE`, sentence, `NONE`, `NONE` (2 of 2 each) | same, 8 of 8 | yes |
| Median output tokens 1843, 1719, 1669, 920; wall 24, 38, 22, 16 s | true medians are 1780.5, 1700, 1512.5, 920 and 22, 31, 20.5, 16 s; the write-up reports the upper-middle value for the even-sized arms | no, minor |
| "stopped ... with about 17,300 tokens left still showing" (20000 arm) | true for 3 of 4; the fourth (rep 7) was shown `0 tokens left` after its third file | partly |
| Settings: 11 env keys, variable absent, four symlinks | `jq '.env | length'` = 11; 0 of 3 budget variables present; `totalTokensReminder` null; 4 of 4 account `settings.json` are symlinks to `~/.claude/settings.json` (`ls -la`) | yes |
| Resolver text has 1 hit in the 2.1.293 binary | `mmap.find`: 1 hit; the variable name has 4 whole-file hits, of which 2 are reads and both sit inside the budget resolver; 0 hits in 2.1.284 | yes |

Extra robustness checks (measured):

- 20000 arm alone against budget-off: 0 of 4 against 6 of 6, p = 0.0048.
- Dropping the one `=0` run whose lead did not ask for budget text: 0 of 9 against 5 of 5, p = 0.0005.
- Across every launch run including the dropped ones, the starting countdown equaled the value
  predicted from the environment in 40 of 41 (the one miss did not ask the question). The `=0` runs
  showed `15000000` in 7 of 7 that reported and never showed a budget value.

## The checks the brief asked for

**Ground truth fixed by a program before the models ran?** Yes for completion. `key.json` and the
corpus carry a modification time of 23:57:01; the first call finished at 23:57:48 and the first long
call at 23:58:06 (`stat`). Each of the 8 codes occurs exactly once in its file (8 of 8). "Finished"
is a substring count, no judgment. Two caveats: the generator script is not in `d6/`, so "seeded" is
unverified, and `score.py` was last written at 00:04:13, after the last run, so "regexes fixed first"
cannot be shown from timestamps. My independent rescoring removes the practical risk.
"What the sub-agent saw" is the sub-agent's own report, not a capture of its context. The 40-of-41
agreement with the environment makes that report trustworthy here.

**Identical tools, prompts and inputs?** Tools and the top-level prompt were identical within each
prompt family, and the corpus was a fresh copy per run. The sub-agent's input was not identical,
because the lead writes it:

| Arm (long task) | Lead model | n | Sub-agent prompts with a "say so if you can't finish" clause |
|---|---|---|---|
| budget on (3000, 20000) | Opus 5.5 (valid) | 9 | 9 |
| budget off (control, `=0`) | Opus 5.5 (valid) | 6 | 0 |
| budget on | Opus 4.8 (dropped) | 5 | 0 |
| control | Opus 4.8 (dropped) | 4 | 0 |

The lead had been told "Each fresh agent you launch has a budget of N tokens" and reacted by
licensing a partial return. That split (9 of 9 against 0 of 6) is as clean as the outcome split, so
the data cannot say whether the sub-agent's countdown or the lead's clause did the work. The same
confound undercuts the side observation that Opus 4.8 sub-agents "ignored" the budget: those five
sessions also had an Opus 4.8 lead that wrote no such clause. Also, every sub-agent was asked to
quote budget text, which makes the countdown more salient than it is in normal work.

**Served model read from modelUsage on every row, substitutes dropped?** Yes. All 49 rows carry the
`modelUsage` key list; valid means it lists `claude-opus-5-5` alone, which covers the sub-agent
because the field is session-wide. In the raw streams, 39 of 39 valid rows have no message from any
other model. In all 10 dropped rows both the lead and the sub-agent ran on `claude-opus-4-8`. The
safety stop came on the lead's first request, before any sub-agent existed, so dropping those rows
does not select on the outcome. Drop rate by arm: control 4 of 6, `=0` 0 of 4, 20000 3 of 7,
3000 2 of 7 (control against `=0`, Fisher two-sided p = 0.076, not a real difference at this n).

**Is n large enough?** A sign test does not apply: the runs are unpaired, with no shared item or
seed across arms. Fisher's exact test is the right tool and gives 0.0002. Read it narrowly. All 15
valid runs are repeats of one task, one prompt, one account, inside about seven minutes, so the
p-value covers run-to-run noise on that task only. Clopper-Pearson one-sided 95% bounds: finish rate
with the budget on is below 28% (0 of 9), with it off above 61% (6 of 6). For the switch itself,
n = 2 per arm is thin for anything random, but the countdown text is produced by the client, and the
7-of-7 and 40-of-41 tallies above are the better support.

**Ceiling or floor?** Yes, by construction. A full run used about 89,000 sub-agent tokens (measured
from the usage line, 89,114 to 89,281, n = 6). Budgets of 3000 and 20000 are 3% and 22% of that.
At 3000 the budget is roughly the sub-agent's starting context (2,742 to 3,016 tokens in the four
runs that made no tool call), so declining is the only sensible move. Control sits at the ceiling,
budget-on near the floor. That answers "does the model obey the countdown" (yes) and "does the
client enforce anything" (no). It does not tell us where truncation starts. The one realistic value,
100000, was only run on the short prompt, where there was no work to cut.

**Does the recommendation follow from the numbers or from the worker's prior?** Split.
Measured: `=0` gives control behavior; a settings `env` value of 0 beat a shell value of 100000
(2 of 2); nothing is lost today. Prior: that the vendor will turn the flag on, at a value that binds
on fleet work, and that the fleet is better off without it. The action is still sound because the
measured cost is zero and the measured failure, when it happens, raises no error.

**Cheaper explanations for the data.** Three, and all fit: the lead told the sub-agent it may stop;
the sub-agent was primed by being asked about its budget; the budget was so far below the need that
any budget-aware agent would stop. All three are still effects of the feature being on, and `=0`
removed both the parent sentence (2 of 2) and the sub-agent budget, so none of them argues against
the edit. They argue against quoting "every time" as the expected rate in production.

## Claims in the write-up that should be corrected

1. "Silently returning partial work" (in the conclusion). In 9 of 9 valid budget-on runs the
   sub-agent's return said which files it had not read, and in 9 of 9 the lead's final reply said so
   too. The accurate statement is "no error or stop reason to catch; the shortfall is only in the
   text."
2. "The model chose to stop" is incomplete. See the 9-of-9 lead-written clause above.
3. "If a later binary renames it the line becomes inert, not harmful." That is an assumption. If a
   later build read 0 as a budget of zero, every sub-agent would be told it had nothing left, and
   this measurement shows what Opus 5.5 does then (4 of 5 made zero tool calls at 3000).
4. The medians are upper-middle values, and the 20000 arm table omits the `0` countdown on rep 7.

## One practical point about how to apply it

`~/.claude/settings.json` is a regular file and a hand edit would work. The fleet's own convention
(`claude-infrastructure/migrations/README.md`) is that settings changes land as a numbered migration
with a verify line; earlier env keys went in that way (`migrations/0055-cert-store-bundled.sh`).
A hand edit is a live-versus-repo drift by that document's definition. This is the operator's call.

## Not settled by this measurement

- Whether `=0` beats a real server-sent value. The flag is off (0 mentions of the three flag names
  in all four account state files, `grep -c`), so the budget was only ever forced through the same
  variable. The claim rests on the code read, which I confirmed in the binary text.
- Whether a realistic budget hurts real fleet work. No long-task arm above 22% of need.
- Which side causes the truncation, and what happens with the budget on but the parent sentence off.
- The user `settings.json` path itself, and accounts other than quaternary, were not run live.
- Durability. Nothing shows the variable survives the next binary, or keeps the same meaning.
- Other models and surfaces: Haiku 5.5 sub-agents, Fable 5.1 leads, resume, forks, sessions started
  without user settings.
- Effect on weekly quota. The prompt forced exactly one sub-agent, so respawn cost was not measured.
