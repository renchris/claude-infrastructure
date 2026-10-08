# D6: switch off the per-agent token budget (Claude Code 2.1.293)

## Recommendation

**Apply the edit: add `"CLAUDE_CODE_RIPPLING_TULIP": "0"` to the `env` block of
`~/.claude/settings.json`.** Conviction 91%. Do not use `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=infinite`.

- The setting is not present today (`jq '.env' ~/.claude/settings.json`: 11 keys, none of
  `CLAUDE_CODE_RIPPLING_TULIP`, `CLAUDE_CODE_TOTAL_TOKENS_REMINDER`; top-level `totalTokensReminder`
  is null). The four account dirs (`.claude-next`, `-secondary`, `-tertiary`, `-quaternary`) symlink
  their `settings.json` to that one file (`ls -la`), so one edit covers all four.
- **"Advisory" is true of the client and false of the model.** No run stopped or errored
  (0 of 49 `is_error`, every `stop_reason` `end_turn`), but an Opus 5.5 sub-agent that was shown
  a small budget cut its own work short every time: 0 of 9 finished the eight-file task with the
  budget on, against 6 of 6 with it off.
- **What is lost by not applying it:** nothing today (the server flag is off; the control arm and
  the `=0` arm are indistinguishable). The loss is conditional: if the vendor turns the flag on
  with a value that a sub-agent task exceeds, Opus 5.5 sub-agents return partial work with no error
  to catch, and the lead is told a budget sentence that makes it plan around the limit.
- **What is lost by applying it:** the budget could not save us quota we wanted saved. It is one
  undocumented env line; if a later binary renames it the line becomes inert, not harmful.

## Results

All calls: 2.1.293, main model `claude-opus-5-5` at `--effort low`, tools `Agent,Read`, account
`~/.claude-quaternary`. "Valid" means `modelUsage` named only `claude-opus-5-5`. All numbers below
are measured by `d6/score.py` over the raw streams (regex on the sub-agent's returned text and the
final reply; planted-code count against `d6/key.json`).

### Short prompt (the brief's prompt, verbatim): what the sub-agent saw

| Arm | Env | n valid | Countdown the sub-agent quoted | Work cut short |
|---|---|---|---|---|
| 1 control | none | 2 of 2 | `15000000 tokens left` (2 of 2) | no |
| 2 forced on | `RIPPLING_TULIP=100000 STREAMED_BUMBLEBEE=true` | 2 of 2 | `100000 tokens left` (2 of 2) | no |
| 3a switch `RIPPLING_TULIP=0` | `RIPPLING_TULIP=0 STREAMED_BUMBLEBEE=true` | 2 of 2 | `15000000 tokens left` (2 of 2) | no |
| 3b switch `TOTAL_TOKENS_REMINDER=infinite` | forced on + `=infinite` | 2 of 2 | `Infinite tokens left` (2 of 2) | no |
| S+ settings-env positive control | `--settings` file with env `RIPPLING_TULIP=100000`, `STREAMED_BUMBLEBEE=true`; nothing in the shell | 2 of 2 | `100000 tokens left` (2 of 2) | no |
| S0 forced on in the shell, `=0` in settings env | shell `RIPPLING_TULIP=100000 STREAMED_BUMBLEBEE=true`; `--settings` file with env `RIPPLING_TULIP=0` | 2 of 2 | `15000000 tokens left` (2 of 2) | no |

Arm 3a cannot hold both `100000` and `0` in the same variable, so S0 is the real "forced on plus
switch" test, and it is the form of the proposed edit: the settings `env` value replaced the shell
value and the budget vanished.

### Parent side: the budget sentence in the Agent tool description

Prompt: "Do not launch anything. Quote verbatim every sentence in your Agent tool description that
mentions a budget of tokens for agents you launch. If there is no such sentence, reply exactly NONE."

| Arm | n valid | Reply |
|---|---|---|
| control | 2 of 2 | `NONE` (2 of 2) |
| forced on 100000 | 2 of 2 | "Each fresh agent you launch has a budget of 100,000 tokens, counting the context it starts with." (2 of 2) |
| `RIPPLING_TULIP=0` (+ `STREAMED_BUMBLEBEE=true`) | 2 of 2 | `NONE` (2 of 2; one rep added a few words around it) |
| forced on + `TOTAL_TOKENS_REMINDER=infinite` | 2 of 2 | `NONE` (2 of 2) |

### Long task: is the budget only advisory? (arm 4)

Sub-agent task: read eight planted files in the working directory (190,229 bytes in total, one
`CODE:` line each, key fixed before any run) and report all eight codes plus any budget text.

| Arm | Calls | Valid (Opus 5.5 served) | Codes returned per valid call (of 8) | Finished 8 of 8 | Countdown quoted | Error or forced stop |
|---|---|---|---|---|---|---|
| control | 6 | 2 | 8, 8 | 2 of 2 | 15000000, then about 14996900 | none |
| `RIPPLING_TULIP=0` (+ bumblebee) | 4 | 4 | 8, 8, 8, 8 | 4 of 4 | 15000000, then about 14996900 (3 of 4 quoted it) | none |
| forced on 20000 | 7 | 4 | 4, 2, 2, 3 | 0 of 4 | 20000, then about 17300 | none |
| forced on 3000 | 7 | 5 | 1, 0, 0, 0, 0 | 0 of 5 | 3000 (one rep: then 358) | none |

- Budget on versus off, valid calls: 0 of 9 against 6 of 6 finished. These are unpaired runs, so a
  sign test does not apply; Fisher's exact test (computed by hand, 1/C(15,6)) gives p = 0.0002.
  `=0` alone against budget on: 4 of 4 against 0 of 9, p = 0.0014.
- Control against `=0`: 2 of 2 against 4 of 4 finished, same countdown text. No test can separate
  them at this n; that is the expected result (the switch restores control behavior).
- 3000 against 20000 (median 0 against 2.5 codes): n = 5 and 4, not distinguishable with any
  confidence and not needed for the decision.
- At 3000, four of five sub-agents made zero tool calls and returned at once saying the budget was
  too small. At 20000 they stopped after two to four files with about 17,300 "tokens left" still
  showing. Nothing in the client stopped them; the model chose to stop.
- Median output tokens per valid call (all models in the session): control 1843, `=0` 1719,
  20000 1669, 3000 920. Median wall: 24 s, 38 s, 22 s, 16 s.

Dropped calls (10 of 49). In ten long-task calls (nine in the table above, one in the first version below) the first Opus 5.5 request was
stopped by the safety classifier and the session fell back to `claude-opus-4-8`
(`model_refusal_fallback`, category "cyber"); they are excluded from every count above. It happened
on control too (4 of 6), so it is the prompt, not the budget. As a side observation only: the five
dropped budget-on sessions (Opus 4.8 sub-agent, 3000 or 20000) all returned 8 of 8 codes, with the
countdown at 0 in the 3000 runs, and nothing stopped them. That is the direct evidence that the
client enforces nothing.

A first version of arm 4 (5 calls, files outside the working directory) hit Read permission denials
in every arm and scores 0 codes everywhere; its rows are kept (`A4_*`) but not used for completion.
They agree in direction: control sub-agents attempted 8 reads, 3000 sub-agents attempted 0 and 1.

## Method (five lines)

1. Binary `~/.claude-293/node_modules/.bin/claude` (2.1.293), `-p --model claude-opus-5-5 --effort low --output-format stream-json --verbose --setting-sources "" --strict-mcp-config --no-session-persistence --tools "Agent,Read"`, `CLAUDE_CONFIG_DIR=~/.claude-quaternary`, run under `env -i` from a fresh `mktemp -d` so no variable leaks in from the calling session (`d6/cell.sh`, modeled on `measure/retrieval/cell.sh`).
2. Arms differ only in the env vars (or the `--settings` env file) shown in the tables; 49 model calls in total, at most 4 in parallel.
3. Ground truth fixed first: the eight planted codes (`d6/key.json`, generated by a seeded script) and three regexes (`(\d+|Infinite) tokens left`, `has a budget of (\d+) tokens`, code substrings).
4. `d6/score.py` reads each raw stream, takes the sub-agent's returned text from the Agent tool result and the session's final reply, applies the regexes and the key, and marks a call valid only if `modelUsage` lists `claude-opus-5-5` alone.
5. `stream-json` was used instead of plain `json` so the sub-agent's own return and its tool calls are visible; the final `result` event carries the same fields as `--output-format json`.

Raw rows: `/tmp/haiku55-decisions/D6-agent-budget-switch.rows.jsonl` (49 rows). Raw streams:
`/tmp/haiku55-decisions/d6/raw/`.

## Why `RIPPLING_TULIP=0` and not `TOTAL_TOKENS_REMINDER=infinite`

Both removed the per-agent budget and the parent sentence (2 of 2 each). `=0` left the sub-agent
with exactly the control text (`15000000 tokens left`); `infinite` replaced it with
`Infinite tokens left` for the sub-agent, a change from 2.1.284 behavior that we have not
evaluated. `=0` is the narrower edit.

## Not settled

- **Override of a real server value: not measured live.** The flag is off on this account, so the
  budget could only be forced through the same env variable. S0 shows the settings value beats a
  shell value; that `=0` beats a server-sent value rests on the code read
  (`function SWt(e,n){return n??Qc()?.[e]??$r(e,null)}`, 1 hit in the 2.1.293 binary by `mmap.find`).
- **The user `settings.json` path itself was not exercised** (`--setting-sources ""` was required;
  the env block was delivered by a `--settings` file). The positive control shows a settings env
  block reaches the resolver; that the user file behaves the same is assumed.
- **What value the vendor would send.** A budget far above typical sub-agent use might never bind;
  only 3000, 20000 and 100000 were tried, and only the first two against a task that exceeds them.
- **Other sub-agent models.** Only Opus 5.5 sub-agents count here (plus 5 dropped Opus 4.8
  sessions that ignored the countdown). Haiku 5.5 Explore agents were not tested.
- **Other surfaces and resume.** Workflow `agent()`, teammates, forks, and resuming an agent that
  recorded a budget before the edit were not exercised; out-of-process workers need the env line
  in their own environment.
- **The countdown undercounts.** With the budget at 20000, a sub-agent that used about 89,000
  tokens (its own usage line) still showed about 16,800 left; what the countdown counts was not
  traced.
- **The refusal fallback.** 10 of 29 calls whose prompt asked for a multi-file read fell back to
  Opus 4.8 after a "cyber" classifier stop. Outside this decision, but it cost 10 calls here.
- n is 2 per arm on the short prompt; every arm was unanimous, but two reps cannot bound a rare
  failure.
