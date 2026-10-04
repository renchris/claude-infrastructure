# Headless model-call audit (shard: headless)

## Assumptions
- Scope: every place the repo calls a Claude model outside an interactive session (headless `claude -p` / `claude-latest -p`, direct `/v1/messages`). docs/research one-off scripts excluded. Read-only; nothing in the repo was edited.
- Platform and cost unit: Max-subscription OAuth via `claude -p`, so cost is weekly quota, not dollars. The Batch API is not reachable from `claude -p` on OAuth; the one API-key path (`/evolve-skill`, `--bare`) is rare and small. Batch is skipped everywhere for that reason.
- Target models: Opus 5.5, Fable 5.1, Sonnet 5.5, and Haiku 4.5 where a site pins it.
- Measured fact this audit leans on (model-config.yaml:267, :1419): with no `--effort`, Claude Code sends `medium` for the 5.5 models, and top-level `effortLevel` does not reach them. The repo's own isolation recipe (skills/cc-upgrade/utilize.md:54; tests/fixtures/codex-probe/runs/README.md:31-42, verified there) is `--tools "" --setting-sources "" --strict-mcp-config --no-session-persistence` plus a scratch cwd. Without `--setting-sources ""`, `claude -p` loads CLAUDE.md, rules, hooks (Stop hooks included) and plugins. Without `--strict-mcp-config`, it loads the user-scope MCP servers (ms365, motion and motion-plus are configured on 4 of 5 config dirs).
- Quality bar: no eval covers any of these call sites except the dl-sweep and router bats (stubbed models). Every change below is either a free win (input hygiene, correctness) or marked as a tradeoff.

## Inventory (call sites)
| Site | Model / effort | Hygiene | Verdict |
|---|---|---|---|
| scripts/handoff-fire.sh:13024-13027 `probe_account` | Haiku 4.5, or the Fable id being fired; no effort | only `--strict-mcp-config`; loads user settings, CLAUDE.md, rules, hooks, plugins and tools | **finding 01** |
| scripts/dl-sweep.sh:155-157 (launchd, nightly) | Sonnet 5.5, unpinned (so medium) | `--tools "" --strict-mcp-config --no-session-persistence`, mktemp cwd; **loads user settings** | **findings 02, 03, 09** |
| scripts/research-kit/router.py:233 (UserPromptSubmit classifier, 6 s timeout) | haiku_latest | `--setting-sources local` only | **finding 05 (+ test, 05b)** |
| hooks/model-permission-decider.py:411-428 (PreToolUse; not wired live, migration 0022 pending) | Haiku 4.5 | setting-sources "", strict-mcp; enumerated disallow list; persists sessions | **finding 06** |
| scripts/research-kit/lib/courier.py:130-135 (certification reviewers, ANTHROPIC lane) | reviewer_pins model; **no effort** | `--setting-sources local` only | **findings 07, 08** |
| commands/evolve-skill.md:32-38 (API key, `--bare`) | Opus 5.5 @high | `--bare` | **finding 04** |
| bin/cc-memory-extract:371-386 | Haiku 4.5 | full isolation recipe | clean (see notes) |
| bin/claude-accounts:1272 wire probe (direct API) | Haiku 4.5, max_tokens 1, "." | n/a | clean |
| scripts/limit-recover/lr-probe.sh | none: unauthenticated HEAD, zero tokens | n/a | clean |
| lib/cc-upgrade-gate, scripts/automode-land-probe.sh, scripts/headless-precondition-probe.sh | probes | load settings **on purpose** (they measure the real harness) | not flagged |
| scripts/research-kit/workflows/round.workflow.js:40-43 | workflow-lean @low per shell command | in-session Workflow | **finding 10** (low) |
| scripts/jev/* | non-Anthropic model (`typesafe-ai/jev`) | n/a | out of scope |

## Summary
The three biggest items:
1. **The handoff-fire probe** loads the full user layer to answer "can this account reach this model?". Its own comment records the cost: about $1 of cache creation per Fable 5.1 probe, and a user Stop hook forced a second turn that made healthy accounts read as failed. Adding `--setting-sources "" --tools ""` removes both.
2. **dl-sweep**, the nightly unattended Sonnet 5.5 job, has the same exposure: about 60 KB of CLAUDE.md and rules, plus Stop hooks, inside a JSON extractor. On top of that, its parser uses the first-`[`-to-last-`]` span, which the repo's own Sonnet 5.5 hazard census forbids, and a parse miss reports a silent `ok candidates=0`.
3. **/evolve-skill**'s scoring command merges "run the variant" with "judge the output". The skill body under test grades its own answer, and the judge never sees the case's `expected_behavior` rubric. The fixtures README describes two steps; the command has one.

Counts: Group 1 (prompt text): 0 cruft findings; the prompts are clean and carry their reasons. Group 4 (request config / architecture): 10. Caching: no material lever. The only repeated prefix is cc-memory-extract's template, about 1K tokens on Haiku, too small to be worth it.

## Findings (ordered by confidence, then impact)

### 01 scripts/handoff-fire.sh:13027 (high, free win)
`probe_account` runs `"$BIN" -p 'Reply with exactly: ok' --strict-mcp-config --model "$probe_model" --max-turns 1 --output-format json` under the account's CLAUDE_CONFIG_DIR, so it loads user settings (hooks, plugins), CLAUDE.md and rules (~60 KB), and every built-in tool schema. Evidence in the file (13000-13004): four Fable 5.1 probes each showed "~1 USD of cache creation", and a Stop hook (session-continue.sh wake-floor) blocked the headless stop, forcing a second turn past `--max-turns 1`. The verdict logic was then rewritten to tolerate it. With `--setting-sources "" --tools ""` the probe sends almost nothing but the one-line prompt, and no hook can run. Neither flag changes reachability: auth comes from the config dir's credentials, and the settings `env` holds no base-URL or model override.
- old: `      --model "$probe_model" --max-turns 1 --output-format json 2>&1 </dev/null)" || rc=$?`
- new: `      --setting-sources "" --tools "" \` + newline + the old line.

### 02 scripts/dl-sweep.sh:155 (high, free win)
Nightly launchd job, Sonnet 5.5, `CLAUDE_CONFIG_DIR=<ranked account>`, no `--setting-sources`. It loads the operator's resident instructions (Session Close Protocol, mission board: about 15K tokens), plugins and hooks into a no-tool deadline extractor. The Stop-hook problem from finding 01 applies here too: a forced extra turn makes the final printed message something other than the JSON array, and the parser (finding 03) then reports zero candidates as `ok`.
- old: `"$CBIN" -p --tools "" \`
- new: `"$CBIN" -p --tools "" --setting-sources "" \`

### 03 scripts/dl-sweep.sh:169-174 (high, correctness)
`s, e = raw.find("["), raw.rfind("]")` is the first-to-last span that docs/research/sonnet55-utilization-2026-09-28/notes/harness-hazards-b.md:22-23 quotes the Sonnet 5.5 prompting guide as forbidding: "Parse the last JSON value… The model occasionally writes a draft before its final JSON". It also breaks on any `[` in prose before the array (the redaction tokens `[email]`, `[link]`, `[number]` appear in the input). On a parse failure, `got = []` and the job writes `ok … candidates=0`. dl-sweep postdates that census (2026-09-29 versus 2026-09-28), so the census never saw it. The replacement scans for the last top-level array and keeps the existing empty-list fallback. The better long-term fix is `--output-format json --json-schema` with an object wrapper, which needs new code.

### 04 commands/evolve-skill.md:32-38 (high, eval design)
The scoring command passes the variant body via `--append-system-prompt`, the case input as the prompt, and a `{score, feedback}` schema in the same call. So the model running under the variant scores its own (never produced) answer, without the `## expected_behavior` rubric. evolve-fixtures/pyramid-principle/cases/README.md:9-10 describes the intended two steps (run, then score against expected_behavior). eval-audit.md:171-179 (judge design) and 163 (atomic checks) apply. The replacement splits the command into a run call and a judge call.

### 05 scripts/research-kit/router.py:233 (+05b tests/research-router.bats:318) (high, free win)
The per-prompt Haiku classifier has a 6 s timeout (router.py:73) but runs without `--tools ""`, `--strict-mcp-config` or `--no-session-persistence`. It therefore starts the user-scope MCP servers (ms365, motion, motion-plus) inside a 6 s budget, ships every built-in tool schema with a one-label question, and writes a transcript per prompt. A timeout reads as `unavailable`, which blocks the research verbs for that turn. The bats test pins the exact argv and must change with the code (note the double space that `$*` gives an empty argument).

### 06 hooks/model-permission-decider.py:425-427 (medium-high, free win; applies once migration 0022 wires it)
`--disallowedTools` lists 15 names. The repo's own lesson ("Denylist = examples") and the codex-probe note ("`--tools ""` removes the tools rather than forbidding them") both apply: tools added since (Monitor, TaskCreate/TaskUpdate, CronCreate, RemoteTrigger, PushNotification, …) are not in the list, and the remaining schemas ride in every consult. There is also no `--no-session-persistence`, and the child inherits the consulting session's cwd, so each consult (up to 400 a day) writes a transcript into that project's dir. The tests stub the model (MITL_MODEL_CMD), so no test asserts this argv.

### 07 scripts/research-kit/lib/courier.py:132 (medium, free win)
Certification reviewers on the ANTHROPIC lane run with `--setting-sources local` but no `--strict-mcp-config`. Each one starts ms365 (about 200 deferred tools, mail included), motion and motion-plus. That is startup latency and tool-name context in every reviewer, plus a personal-mail tool surface inside a "blind" reviewer. The reviewers read the bundle with built-in Read/Grep/Glob, which `--strict-mcp-config` does not touch.

### 08 scripts/research-kit/lib/courier.py:133-134 (medium, TRADEOFF, operator decision)
No `--effort` on the reviewer call. The ANTHROPIC lane loads no user settings (so no `modelSettings` pin applies), and Claude Code's measured default for 5.5 is `medium`. Certification reviewers therefore run at medium, while the SSOT puts capability-sensitive review at `opus55_capability_sensitive: xhigh` / `fable51_capability_sensitive: high` (model-config.yaml:1295-1358). Effort is also not recorded in the panel, so two rounds at different effort cannot be told apart. Raising it costs quota and needs the operator's call. Proposed: pin `high` through `CC_RESEARCH_REVIEWER_EFFORT` as the floor, record it in the panel JSON, and have check-round void a mismatch the way it voids a model-pin breach.

### 09 scripts/dl-sweep.sh:156 (medium, free: pins today's measured behavior)
Sonnet 5.5 with no `--effort` runs at the binary's `medium` (measured, model-config.yaml:1419: "Always pass effort explicitly"). Pinning `medium` changes nothing today and keeps a binary bump from silently moving the nightly job. Raising it to the SSOT `sonnet55_default: high` would be a tradeoff for the operator; this hunk does not do that.

### 10 scripts/research-kit/workflows/round.workflow.js:40-43 (low, flag)
Each step is an LLM agent told to "Run exactly this one command… Do not edit, retry or interpret it": an LLM executor for a deterministic plan (prompt-audit Group 4). The cost is small (workflow-lean @low) and rounds are rare. It is flagged only. A Python fan-out in lib/round.py would drop those calls if the Workflow's visibility is not what is being bought.

## Levers skipped and why
- Batch API: unreachable from `claude -p` on OAuth. evolve-skill (API key) is about $2-10 per run and rare.
- Prompt caching: no site has a large repeated prefix. Probes cross accounts (separate orgs, no shared cache), the router and decider prompts are under the Haiku minimum, dl-sweep runs once a night, and cc-memory-extract's ~1K-token template is too small.
- Model step-down: every site is already on the cheapest tier that fits (Haiku for classifiers and probes), or is a judgment role where the SSOT already chose.
- Group 1 prompt cruft: the decider, router, dl-sweep and memory-extract prompts are tight, state their reasons, and carry real safety constraints (injection fencing, fail-to-ASK). Nothing to remove.
