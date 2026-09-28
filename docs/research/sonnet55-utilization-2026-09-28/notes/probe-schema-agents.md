# Probe: schema'd Workflow agents on claude-sonnet-5-5 at low/medium (2.1.284)

Probe name: schema-agents. Date: 2026-09-28. This closes critic.md §7 ("Structured-output Workflow agents at
low/medium are untested"). Scratch and raw files are in `/tmp/s55/probe-schema-agents/`.

## Question

The vendor gives two warnings for Sonnet 5.5 (vendor-docs.md:135, :174):
- with structured outputs at low or medium effort, the model sometimes thinks until `max_tokens`;
- a forced `tool_choice` returns a 400.

Do Workflow `agent(brief, {model:'claude-sonnet-5-5', effort:'low'|'medium', schema})` calls under 2.1.284 fail
because of either warning, as a null result, a schema failure, a `max_tokens` stop or a wrong answer?

## Answer

No. Across 49 schema'd Sonnet 5.5 agents, 40 of them at low or medium, there were 0 null results, 0 schema
failures, 0 wrong answers, 0 `max_tokens` stops, 0 API errors and 0 StructuredOutput nudges. The effort each
agent recorded matched the effort requested in 49 of 49 cases.

Conviction: 85% that the pattern is safe for short, bounded reasoning briefs like these. This does not cover long
synthesis briefs, which were not tested.

Why the warnings do not bite (MEASURED, below):
- CC implements `schema` as a `StructuredOutput` tool that the model calls with auto tool choice. When the model
  skips the call, CC sends an in-conversation nudge. There is no API-level forced tool choice.
- The 2.1.284 binary also carries the string `tool_choice {type:'tool', name:...} demoted to auto: extended
  thinking is active` (strings over `~/.claude-284/.../bin/claude.exe`).
- The subagent output cap is 128,000 tokens (`modelUsage.claude-sonnet-5-5.maxOutputTokens` in both lead JSONs).
  Hitting `max_tokens` would take about 128k tokens of thinking. The observed mean was about 526 thinking tokens
  per agent on the hard set.

## Method

Lead: `CLAUDE_CONFIG_DIR=<acct> ~/.claude-284/node_modules/.bin/claude -p --model claude-opus-5-5 --effort high
--permission-mode auto --output-format json < prompt.txt`, run from cwd `/tmp/s55/probe-schema-agents/runN`.
The prompt told the lead to call the Workflow tool once, with the script inline and verbatim, and to return the
raw array. MEASURED: the lead's `Workflow` tool_use input `script` equals the file byte for byte in both runs
(python comparison against the lead transcript). Every agent used `agentType:'workflow-lean'`,
`model:'claude-sonnet-5-5'` and a JSON schema with `additionalProperties:false`. The brief told the agent to
reason only and to call no tool except StructuredOutput. Ground truth came from `answers.py` / `gen.py` (Python)
and was checked by exact match, with a numeric tolerance of 0.005.

| run | account | tasks | agents |
|---|---|---|---|
| run1 | next | set 1 (see below) | 0. The Workflow tool rejected the script (see Hazard 1) |
| run2 | next | set 1: A invoice (discount then tax), B weighted rank + disqualify, C critical path (7 tasks), D shipping tiers + surcharge + zone, E filter/count/sum over 12 rows | low 5x2 = 10, medium 5x2 = 10, high 5x1 = 5 |
| run3 | next4 | set 2 (harder): Z 5-house logic puzzle with 13 clues and a unique solution (brute-force verified); G 22-row ledger with tier rules, per-category totals, top customer, returned count | low 2x5 = 10, medium 2x5 = 10, high 2x2 = 4 |

## Results (all MEASURED)

Counts come from `analyze.py <wf dir> <out.json>`, which joins `journal.jsonl` started/result rows to each
`agent-<id>.jsonl` and scores against truth. The effort and thinking tallies come from `effort.py <wf dir>`.

| run | effort | n | null result | schema fail / error | wrong | `max_tokens` stop | agents with a thinking block | recorded effort = requested |
|---|---|---|---|---|---|---|---|---|
| run2 | low | 10 | 0 | 0 | 0 | 0 | 0/10 | 10/10 |
| run2 | medium | 10 | 0 | 0 | 0 | 0 | 0/10 | 10/10 |
| run2 | high | 5 | 0 | 0 | 0 | 0 | 4/5 | 5/5 |
| run3 | low | 10 | 0 | 0 | 0 | 0 | 10/10 | 10/10 |
| run3 | medium | 10 | 0 | 0 | 0 | 0 | 10/10 | 10/10 |
| run3 | high | 4 | 0 | 0 | 0 | 0 | 4/4 | 4/4 |
| **total** | low+medium | **40** | **0** | **0** | **0** | **0** | 20/40 | 40/40 |

Other measurements:
- **Journal.** `journal.jsonl` holds `launched`, 25 `started` and 25 `result` rows for run2, and 24/24 for run3.
  It records no stop reasons at all. Stop reasons are only in the per-agent `agent-<id>.jsonl`.
- **Stop reasons.** `grep -o '"stop_reason":"[a-z_]*"'` over the agent transcripts found only `tool_use`: 27
  entries in run2 and 22 in run3. `grep -l max_tokens` found 0 files in both runs.
- **Missing stop reasons.** 3 of 25 (run2) and 2 of 24 (run3) agents have no non-null stop_reason recorded
  anywhere in their transcript. For those agents the transcript cannot show whether the stop was `max_tokens`.
  Two things rule that out: each of them made exactly one StructuredOutput call that validated, and no nudge was
  sent.
- **Nudges and API errors.** `grep -l -E 'You MUST call the|has not been delivered|StructuredOutput validation'`
  found 0 of 25 and 0 of 24 files. `grep -l -E '"isApiErrorMessage":true|invalid_request_error|"status":400'`
  found 0 of 25 and 0 of 24.
- **Tool calls.** Every agent made exactly 1 StructuredOutput call and no other tool call (0 Bash or Read), from
  `analyze.py`.
- **Token use.** From `modelUsage` in `runN/out.json`:
  - run2: Sonnet 5.5 output 8,900 tokens, thinking 853, $0.2205.
  - run3: Sonnet 5.5 output 17,103 tokens, thinking 12,627, $0.2578.
  - Lead totals: $0.7196 (run2) and $0.7937 (run3).
  - The per-entry `usage.output_tokens` in agent transcripts is **not** a usable instrument. It holds a streaming
    snapshot, for example 2 tokens on a message whose text is about 60 tokens.
  - Thinking text is omitted from the transcripts, which record `"thinking":""`, so thinking length per agent is
    not observable there. Only the aggregate `thinkingTokens` is.
- **Wall time.** The lead's wall time was 48 s for run2 and 61 s for run3 (MEASURED, `date +%s` before and after).

## Side findings

1. **Hazard: workflow scripts reject `Date.now()`, `Math.random()` and `new Date()`.** Run1 failed before any
   agent started. The tool_use_error was: "Workflow scripts must be deterministic: Date.now()/Math.random()/new
   Date() are unavailable (breaks resume). Stamp results after the workflow returns, or pass timestamps via args."
   Any repo workflow script that times its agents inline breaks on this. It was not checked whether 2.1.280 enforces
   the same rule.
2. **The low/medium thinking decision is task-dependent.** On the easy set (run2), Sonnet 5.5 skipped thinking
   entirely at low and medium: 0 of 20 agents had a thinking block, and 853 thinking tokens came from the 5 high
   agents. It wrote its working as visible text before the StructuredOutput call, and every answer was still
   right. On the harder set (run3), all 20 low/medium agents thought. This matches the vendor's other caveat, that
   the model may skip thinking at low/medium with structured outputs. Here that cost no accuracy, but the brief
   said "work this out by careful reasoning". Whether it did the work in visible text *because* of that wording is
   not established.
3. **Effort binds on Workflow agents.** Every assistant entry in a workflow agent transcript carries top-level
   `"effort"` and `"perTurnEffort"` fields, and they matched the `agent({effort})` value in 49 of 49 agents. This
   partly closes critic.md item 3 for Workflow agents, not for Agent-tool spawns. `agent-<id>.meta.json` does
   **not** record effort; it holds only agentType, model, description, spawnDepth and similar fields.
4. **The lead can refuse to retry.** When told "call exactly once", the run1 Opus 5.5 lead refused to edit and
   retry after the tool error, and returned prose instead of the array. Any harness that parses the lead's result
   must handle a non-JSON reply.

## Limits

- **Sample size.** 0 failures in 40 low/medium agents bounds the per-agent failure rate below about 7.5% at 95%
  confidence (ESTIMATED, rule of three: 3/40). The vendor says "occasionally", which could be below that. Rare
  failures are not excluded.
- **Task size.** The briefs are short: at most about 900 visible output tokens per agent, and about 526 thinking
  tokens per agent on the hard set (ESTIMATED, 12,627 / 24). Long synthesis or file-reading briefs, where agents
  use tools and run many turns, were not tested.
- **High control.** The high-effort control could not separate the arms, because nothing failed in any arm.
- **Unexercised failure paths.** No failure occurred, so the nudge path, `error_max_structured_output_retries` and
  the throw-versus-null behaviour of `agent()` on failure (strings: "agent({schema}): subagent completed without
  calling StructuredOutput (after in-conversation nudge)") were never exercised. The scripts caught throws, and
  none occurred.

## Files

- Scripts: `/tmp/s55/probe-schema-agents/wf.js`, `wf2.js`.
- Truth: `truth.json`, `truth2.json`. Generators: `answers.py`, `gen.py`.
- Scorers: `analyze.py`, `effort.py`.
- Per-run files: `runN/{prompt.txt,out.json,analysis.txt}`.
- Journals:
  - `~/.claude-next/projects/-private-tmp-s55-probe-schema-agents-run2/62a2570c-4d35-4cf0-9ebb-8e055e704642/subagents/workflows/wf_bb04abf9-d55/`
  - `~/.claude-quaternary/projects/-private-tmp-s55-probe-schema-agents-run3/87390602-94d3-406d-923f-2153543f5960/subagents/workflows/wf_7ae584de-8cf/`

## Skeptic

Skeptic pass, 2026-09-28. Scratch is in `/tmp/s55/probe-skeptic-schema-agents/`. I re-read every cited artifact and
re-scored all 49 agents with my own scorer (`indep.py`), using my own recursive comparison against truth. I also ran
one live request capture, because three mechanism claims were labelled MEASURED but rested on static strings or on
labels that CC writes itself.

**Decisive check.** I ran one Workflow on 2.1.284 (account next, Sonnet 5.5 lead at medium) with two schema'd
`workflow-lean` Sonnet 5.5 agents on task G, one at low and one at medium. It ran under
`ANTHROPIC_LOG=debug BUN_OPTIONS=--console-depth=10`, which makes the SDK log every request body with the auth headers
redacted (`live2/out.json`, $0.2777 MEASURED from `total_cost_usd`). The two requests tagged
`x-claude-code-request-class: workflow` carried the following (MEASURED, regex parse of `live2/out.json`):
- `tool_choice: undefined`, `max_tokens: 128000` and `thinking: {type:"adaptive", display:"omitted"}`;
- `output_config: {effort:"low"}` on one request and `{effort:"medium"}` on the other;
- a `StructuredOutput` tool whose `input_schema` is the agent's schema, with no `strict` field. `strict: true` appears
  nowhere in either request, and neither request carries an output format.

Both agents answered G correctly. An earlier run at default inspect depth (`live/`, $0.2781) showed the same
`tool_choice` and `max_tokens` values.

Verdict per claim:

1. **Headline: 0 null, 0 schema failures, 0 wrong, 0 `max_tokens`, 0 API errors, 0 nudges in 49 agents (40 at
   low/medium). UPHELD.** `indep.py` reproduces every count. All 49 are fresh API responses: 49 distinct message ids
   and 49 distinct journal keys, so no result was replayed from a resume. Every transcript entry is version 2.1.284 and
   model `claude-sonnet-5-5`. Each agent's StructuredOutput input equals its journal result. I re-derived the truth
   independently: a brute force (`puzzle_check.py`) finds exactly one solution to puzzle Z, and it equals `truth2.json`.
   G recomputed in Python equals `truth2.json`, and A to E recomputed by hand equal `truth.json`.
2. **Scope: the note leaves out the main reason the warnings do not bite. QUALIFIED.** CC does not use API structured
   outputs for `schema` today. The tool is sent without `strict` and there is no output format (live capture). The
   binary adds `strict` only when the GrowthBook flag `tengu_structured_output_strict` is on
   (`e.strictInputJSONSchema&&x("tengu_structured_output_strict",!1)` in `strings284.txt`). The cached value of that
   flag is `false` on all four accounts (MEASURED, `cachedGrowthBookFeatures` in each `.claude.json`). The vendor
   warning is about structured outputs, which the vendor says include strict tool use (vendor-docs.md:135, :175). This
   probe therefore tested CC's non-strict pattern, not the vendor's condition. The result holds for the fleet as it is
   configured today. If the flag were flipped on the server side, every schema'd agent would fall under the warning
   with no CC version change, and this probe says nothing about that state.
3. **"No API-level forced tool choice". UPHELD, now MEASURED live** (`tool_choice: undefined`). The note's evidence
   was static. The demotion string is real in 2.1.284, and it is also in 2.1.280. It covers only `{type:'tool'}` with
   thinking on, and the only hard-coded forced `toolChoice` in the binary is the web_search helper. So the string is
   not evidence about StructuredOutput. The nudge exists as described (`requiresStructuredOutput` adds a meta user
   message "... You MUST call the StructuredOutput tool ..."), but it was never exercised.
4. **"Subagent output cap is 128,000 (MEASURED, `modelUsage...maxOutputTokens`)". The conclusion is UPHELD and the
   instrument is REFUTED.** `modelUsage.maxOutputTokens` is filled from `A5(model).default`, a static per-model table
   (`maxOutputTokens:A5(s).default` in `strings284.txt`), not from the request. It would read 128000 even if the request
   sent less. The live capture shows `max_tokens: 128000` on both workflow-agent requests, so the figure itself is
   right. `CLAUDE_CODE_MAX_OUTPUT_TOKENS` is not set in the environment or in the settings.json `env` of next or next4
   (MEASURED, `env` and a settings read).
5. **"Mean about 526 thinking tokens per agent" in the "(MEASURED, below)" list. MISLABELLED.** The arithmetic is right
   (12,627 / 24), but it is a derived mean that includes the 4 high agents. It is ESTIMATED, as the Limits section
   already says.
6. **The script matches the file byte for byte in both runs. PARTLY REFUTED.** It matches exactly in run2. In run3 the
   lead dropped the trailing newline (4,936 bytes against 4,937), and the two match after `rstrip`. This does not
   affect any result.
7. **The results table and the journal, stop-reason, nudge and API-error greps. UPHELD.** Reproduced: 25/25 and 24/24
   started/result rows; 27 and 22 non-null `stop_reason` entries, all `tool_use`. The stop reason is missing on 3/25
   agents (low:C:1, low:E:1, medium:E:1) and 2/24 (low:Z:5, high:G:2). The nudge grep patterns match the real 2.1.284
   nudge text. No positive control was run for those greps. A stronger independent check covers the gap: every agent
   transcript holds exactly one API message id, so no agent made a second API call, and a nudge or a retry after a
   `max_tokens` stop would need one. This also settles the missing-stop-reason question more firmly than the note's
   own argument.
8. **Exactly 1 StructuredOutput call and no other tool call per agent. UPHELD** (`indep.py`).
9. **Token and cost figures. UPHELD** (`out.json`). "Lead totals $0.7196 / $0.7937" are session totals that include
   the Sonnet agents. The Opus lead's own share was $0.4992 and $0.5359 (MEASURED,
   `modelUsage.claude-opus-5-5.costUSD`).
10. **"Per-entry `usage.output_tokens` is not a usable instrument". REFUTED as stated.** Only the first streamed entry
    of a message holds a snapshot. The entry that carries the non-null `stop_reason` holds the final count. Summing
    those gives 15,483 over 22/24 agents against modelUsage's 17,103 (run3), and 7,964 over 22/25 agents against 8,900
    (run2). The gaps fit the agents that have no final entry (MEASURED, `outtok.py`). Per-agent output (thinking plus
    visible text) is therefore observable for 44 of 49 agents. The maximum was 870 tokens at low or medium
    (medium:Z) and 945 at high. For the same reason, "thinking length per agent is not observable" is too strong.
11. **Wall time 48 s and 61 s. UPHELD** (`runN/start.txt`, `end.txt`).
12. **Side finding 1, the determinism hazard. UPHELD on 2.1.284.** The run1 lead transcript holds the exact
    tool_result text, and that entry is version 2.1.284. On the open 2.1.280 question: the same error string is in the
    2.1.280 binary (MEASURED, `grep -a -c` returns 2 on both binaries). Enforcement on 2.1.280 was not run.
13. **Side finding 2, thinking depends on the task. UPHELD** (0 of 20 agents with a thinking block on the easy set, 20
    of 20 on the hard set; `indep.py`).
14. **Side finding 3, effort binds on Workflow agents. UPHELD, now at the API level.** The note's instrument, the
    transcript `effort` / `perTurnEffort` fields, is written by CC and does not prove the API received that value. The
    live capture shows `output_config.effort` of `"low"` and `"medium"` on the workflow-agent requests. Run3 agrees:
    task G's final output tokens were 539 to 559 at low and 560 to 603 at medium (n=5 each, no overlap), with the same
    114-character visible output, so the difference is thinking (MEASURED, `outtok.py`). The claim that
    `meta.json` has no effort key is UPHELD.
15. **Side finding 4, the lead refuses to retry. UPHELD** as a single observation (run1 `out.json` result text).
16. **Limits.** The rule-of-three arithmetic (3/40 = 7.5%) is UPHELD. "At most about 900 visible output tokens per
    agent" is REFUTED as stated. The largest visible output (text plus tool input) was 906 characters (medium:A:2),
    which is about 230 to 300 tokens (ESTIMATED at 3 to 4 characters per token). The ~900 figure is either a character
    count or the per-agent total including thinking (maximum 945, see item 10).

**Overall.** The headline holds for today's configuration. It needs one scope qualification, and the note should give
that as the main reason: `schema` goes out as a non-strict tool, and strictness is gated by a server-side flag. Two
instruments were labelled MEASURED but did not measure what was sent (`maxOutputTokens` and the transcript `effort`
field). The live capture confirms both conclusions anyway. There are two minor numeric or wording errors. The 85%
conviction stands for the current flag state. With `tengu_structured_output_strict` on, the pattern is untested.

Skeptic files: `/tmp/s55/probe-skeptic-schema-agents/{indep.py,outtok.py,sig.py,puzzle_check.py,run2.indep.txt,run3.indep.txt}`,
`live/` and `live2/` (`prompt.txt`, `wf-live.js`, `out.json` with the SDK request log).
