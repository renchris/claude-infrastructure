# Harness hazards B: Sonnet 5.5 hazards 4 to 8 mapped to claude-infrastructure

Scope: hazards (4) effort defaults, (5) thinking off and breaking API params, (6) JSON output
parsing, (7) reasoning_extraction refusals, (8) tolerant tool-call handling. The harness is
`/Users/chrisren/Development/claude-infrastructure` (main @ 9eb533126, clean). This pass was
read-only: nothing in the harness was edited. Every file:line below was read with grep, sed or
Read. Findings are **measured**, meaning read directly off the file, unless tagged
**inferred**.

## Source claims used (the guides)

- The Claude Code default for Sonnet 5.5 is medium effort: "In Claude Code and our apps, the default effort is set to Medium, while the
  Claude Platform defaults to High" (/tmp/s55/announce.txt:370). The API default is high (/tmp/s55/effort.txt:163).
- CC 2.1.284 adds `claude-sonnet-5-5` as "now the default Sonnet model on the Anthropic API"
  (/tmp/s55/cl.md:5). So the `sonnet` alias flips to 5.5 when the launcher bumps to 2.1.284.
- CC 2.1.280 changes behaviour so that "an effort level saved before `/effort` became per-model [no longer applies] to newly released models ...
  they start at their default until you pick a level" (/tmp/s55/cl.md:552).
- The five settings that return a 400 error on Sonnet 5.5 are thinking budgets (`type:enabled`+`budget_tokens`), non-default
  temperature/top_p/top_k, assistant prefill, forced `tool_choice` any/tool, and
  `thinking:{type:"disabled"}` (/tmp/s55/migration-guide.txt:35, :99-101, :226-228, :362-364, :429, :443-445).
  `between_tools` is also rejected at xhigh/max effort (:105).
- JSON: "Parse the last JSON value in the response ... Don't take everything from the first { to the
  last }. The model occasionally writes a draft before its final JSON" (/tmp/s55/prompting.txt:110).
- Refusals: "If your prompts ask the model to include its reasoning in the response, remove those
  instructions, because they invite reasoning_extraction declines" (/tmp/s55/prompting.txt:187).
  Fallback does not retry that category (migration-guide.txt:341).
- Tool-name case: the guide says to accept an unambiguous wrong-case call, or to return is_error naming the
  exact expected name (/tmp/s55/prompting.txt:164-167).
- Preserved thinking: "Nothing changes for you if Claude Code ... builds your requests"
  (/tmp/s55/preserved-thinking.txt:26).

Live state (measured):
- The launcher binary is 2.1.280 (`bin/cc-claude-bin` resolves to `~/.claude-280/node_modules/.bin/claude`).
  The `sonnet` alias therefore still means Sonnet 5 today and becomes Sonnet 5.5 on the 2.1.284 bump.
- The SSOT still says `sonnet_latest: claude-sonnet-5` (model-config.yaml:127). No code reads it:
  its only consumers are a test fixture (tests/lr-fire-resume-model-ssot.bats:52,84,98).
- `effort_defaults` has no Sonnet key (model-config.yaml:1095-1200: default, verify_judge, mundane,
  frontier, settings_floor, fable_*, fable51_*, opus55_*).

---

## (4) EFFORT DEFAULTS: every place Sonnet is spawned or fired

| # | Site | Model | Effort explicit? | Exposed? |
|---|------|-------|------------------|----------|
| 4a | agents/research-decomposition-critic.md:3 | `model: sonnet` | **NO**: frontmatter has no `effort:` (lines 1-8) | **YES on 2.1.284.** It runs Sonnet 5.5 at whatever it inherits. |
| 4b | agents/deep-research-sonnet.md:4 | `model: sonnet` | **NO** (lines 1-9). Its description limits use to a "probe-certified low- or medium-effort Workflow", which is a per-call effort, but an Agent-tool spawn has none. | **YES on 2.1.284** for any Agent-tool spawn. Body line 12 still says "at Sonnet 5 tier". |
| 4c | skills/frontier-campaign/SKILL.md:28-30, the red-team gate: "one `workflow-lean` Sonnet agent (`model: sonnet`), ≤500-token verdict" | sonnet alias | **NO**: no effort named | **YES on 2.1.284** |
| 4d | skills/research-subagents/SKILL.md:426: `agent(brief, {model: 'claude-sonnet-5', effort: 'max'})` | pinned id `claude-sonnet-5` | yes (max) | **No.** It is a retired recipe (marked "Retired 2026-09-22" at :424) and pinned to Sonnet 5, not the alias. Stale if copied. |
| 4e | bin/cc-recover-safeguard:116 `FALLBACK_MODELS="opus sonnet haiku"`, re-fire at :160 `--model "$TARGET"`, with no `--effort` | sonnet alias | **Indirectly yes.** handoff-fire appends no `--effort` (scripts/handoff-fire.sh:10855), so the pane's `claude()` injects `--effort ${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-high}}` (~/.zshrc:495). The typed `--model sonnet` wins last (zshrc:502). | **Low.** The fire lands at high: explicit, and inside the guide's "medium→high for agentic" band. |
| 4f | scripts/handoff-fire.sh:57-62, `--model <other>` passed verbatim plus the caller's `--effort`, else the launcher's HIGH | caller | yes (high floor) | Low. The comment "claude=HIGH" is **correct** for `claude()` (zshrc:495). The stable-track `claude-prev` still injects `max` (zshrc:80,175); a Sonnet fire through it would run Sonnet 5.5 at **max**, which the guide reserves for measured gains. |
| 4g | bin/cc-route, bin/cc-wave-plan | Opus/Fable only (cc-route:16-23, 178-214; cc-wave-plan:604-646, 760) | yes (ssot_effort) | **Not exposed.** No Sonnet slot exists. |
| 4h | lib/cc-upgrade-gate/check04_effort.sh:15,31: `gate_headless ... --effort "$2"` | `$GATE_MODEL` | yes | Not exposed. It probes every rung explicitly. |
| 4i | Research judges: docs/research/opus55-effort-sweep-2026-09-22/judge.py:43-44 (`JUDGE_MODEL` claude-opus-5, `JUDGE_EFFORT` xhigh); fable51-effort-sweep judge.py:29-30; review-judge-followup judge.py:84; token-efficiency judge-workflow.js:54 (effort xhigh); settle-rejudge.js:9-11,98-101 | Opus/Fable judges; Sonnet appears only as an **arm** (`claude-sonnet-5` @max) | yes | Not exposed as a judge. A Sonnet 5.5 sweep that copies these must pick its effort afresh, since the levels are recalibrated. |
| 4j | commands/evolve-skill.md:33-37 scorer `claude-latest -p --bare ... --json-schema` | **none passed** (binary default) | **NO** effort, **NO** model | Not Sonnet today, because the default model on this plan is Opus. **Inferred:** after 2.1.284 it is still not Sonnet unless the plan default changes. The missing effort and model make the scores non-reproducible across bumps. |
| 4k | Live `~/.claude/settings.json:1263` `"effortLevel": "high"`, :1326 `"model": "claude-fable-5-1[1m]"`; settings-templates/settings.example.json:12 | n/a | settings floor | **Inferred hazard:** 2.1.280 (cl.md:552) stops a pre-per-model saved level from applying to a newly released model. Non-wrapped surfaces (IDE, bare binary) that switch to Sonnet 5.5 would then start at CC's Sonnet 5.5 default (**medium**), not the `high` floor. scripts/effort-parity-assert.sh checks this key, not the per-model value. |
| 4l | Health/probe callers: handoff-fire.sh:10480-10482 (`-p 'Reply with exactly: ok' --model "$probe_model" --max-turns 1`, no effort) | probe_model | no | Not a hazard. Success is `"is_error":false`, so effort is irrelevant. |

In-process inheritance (**inferred**, from the SSOT's own note at model-config.yaml:210-211): "An
agent definition's `effort:` pins an in-process subagent's rung, so the 'subagents inherit lead
effort' rule applies only to unpinned definitions." Sites 4a-4c therefore run at the **lead's**
effort. With a lead at `/effort max` or xhigh, a ≤500-token Sonnet critic runs at max. The
guide warns that max adds self-started review rounds and reviewer subagents
(prompting.txt:65-71), and the announcement notes Sonnet 5.5 scores lower at Max than at Xhigh
on FrontierCode (announce.txt:400). The SSOT's own Opus 5.5 flip note already names this class
("any subagent/teammate that inherits a default silently drops a rung ... grep the agent
frontmatter", model-config.yaml:113-116). That audit covered Opus, not the two Sonnet agents.

**Smallest fixes (4):**
1. Add `effort: medium` to agents/research-decomposition-critic.md. It is a bounded, ≤500-token,
   <60 s critic, the guide's "well-specified" case. Add `effort: medium` (or `low`) to
   agents/deep-research-sonnet.md, matching its own description. Update its line 12 "Sonnet 5 tier".
2. skills/frontier-campaign/SKILL.md:29: name the rung,
   `agent(brief, {agentType:'workflow-lean', model:'sonnet', effort:'medium'})`.
3. model-config.yaml: add `effort_defaults.sonnet55_*` keys, the same shape as `opus55_*` and
   ADVISORY, before bumping `sonnet_latest`. Record that CC's Sonnet 5.5 default is medium versus
   API high.
4. commands/evolve-skill.md:34: pass `--model` and `--effort` on the scorer so scores stay
   comparable across bumps.
5. cc-recover-safeguard: pass `--effort high` explicitly on the re-fire (line 160). This removes
   the reliance on which launcher function the pane has, since `claude-prev` injects max.

---

## (5) THINKING OFF, between_tools, budget_tokens: the five 400s

**Measured: no harness code sets any of them.** A grep over repo code, excluding docs,
tests, node_modules and vendor, for `budget_tokens|MAX_THINKING_TOKENS|"thinking"|type.*disabled|
between_tools|alwaysThinkingEnabled|tool_choice|temperature|top_p|top_k|interleaved-thinking|
output_format|output-128k|token-efficient-tools|fine-grained-tool-streaming` hits only
model-config.yaml comments (:306-314, :397-398, :996) and unrelated identifiers (`top_path`,
`top_kind`, `top_pad`). The live `~/.claude/settings.json` `env` has no THINK/EFFORT/OUTPUT_TOKENS/MODEL
keys and no `alwaysThinkingEnabled`. ~/.zshrc sets no MAX_THINKING/THINKING env.

The direct Messages API callers are:

| Site | Body | Sonnet 5.5-safe? |
|------|------|------------------|
| bin/claude-accounts:966, 1001-1011 `fetch_wire_limits` | `{"model": WIRE_MODEL, "max_tokens": 1, "messages":[...]}`, WIRE_MODEL defaults to `claude-haiku-4-5-20251001` | **Yes.** No thinking, prefill, tool_choice or sampling fields, and only the rate-limit headers are read (:1024-1026). **Inferred:** with `CC_ACCOUNTS_WIRE_MODEL=claude-sonnet-5-5`, adaptive thinking plus max_tokens 1 gives a `max_tokens` stop, which is harmless here. |
| scripts/limit-recover/lr-probe.sh:61-74 | a connectivity probe; any 3-digit code at curl rc 0 counts as green (:29-35) | Yes. No model semantics. |
| scripts/cloud-create-api.py:101 | cloud sessions API, not Messages | n/a |

Every other model call goes through the `claude` CLI (`-p`), and CC owns the request body there.
The SSOT already records that the binary demotes forced tool_choice to auto and contains zero
`"type":"any"` constructions (model-config.yaml:306-314). Preserved-thinking and append-only
rules therefore do not apply: CC builds the requests (preserved-thinking.txt:26), and the
harness has no hand-built multi-turn API loop.

**Exposed: no. Fix: none needed.** One latent note: the zshrc comment at :69-77 says the settings
enum caps at xhigh. If an effort above high ever combines with a thinking-off surface on Sonnet
5.5, the result is a 400. CC already guards this for Opus 5 (cl.md:1700, 1970).

---

## (6) JSON OUTPUT: scripts that parse model-authored JSON

| Site | Parse | Model | Exposed? | Smallest fix |
|------|-------|-------|----------|--------------|
| **bin/cc-memory-extract:290-311** `parse_reply` | Tries a greedy fenced block `r"```(?:json)?\s*(\{.*\})\s*```"` (:293). Otherwise `text.find("{")` … `text.rfind("}")` (:296-300). This is **exactly the first-{-to-last-} pattern the guide forbids** (prompting.txt:110). | pinned `MODEL = "claude-haiku-4-5-20251001"` (:54), called via `claude -p --setting-sources "" --model` (:314-321) | **Latent.** Safe on Haiku. It breaks the day MODEL moves to Sonnet 5.5: a draft JSON before the final one makes one span that fails `json.loads`, or merges two objects. The greedy fence regex has the same flaw when two fenced blocks exist. | Replace with a last-value scan (`json.JSONDecoder().raw_decode` from each `{`, skipping past parsed values, keeping the last value that has `candidates`). Better: use `--json-schema`, as evolve-skill does. |
| **docs/research/opus55-effort-sweep-2026-09-22/judge.py:122**, fable51-effort-sweep judge.py:109, review-judge-followup judge.py:104 | `re.search(r"```json\s*(\{.*?\})\s*```", ...)` takes the **FIRST** fenced json block. The prompt says "Reply with ONLY one fenced ```json block" (:56). | Opus 5 / Fable judges @xhigh | **Latent, but the likeliest to bite.** This file is the house template: it has been copied twice already (review-judge-followup judge.py:2 says "COPY of ..."). A Sonnet 5.5 effort sweep that copies it, or sets `JUDGE_MODEL=claude-sonnet-5-5`, will score a draft block whenever the model writes one. | Use `re.findall(...)[-1]`, or move to `--json-schema` (structured outputs), which the guide prefers. Also treat `stop_reason=max_tokens` as a failure (prompting.txt:106). |
| lib/cc-upgrade-gate/common.sh:42-48,73-88 (`--output-format json`, `json_get`, `json_has_model`) | Parses **CC's result envelope**, not model text | any | **Not exposed** | none |
| scripts/handoff-fire.sh:10480-10489 | glob on the envelope `"is_error":false` | any | Not exposed | none |
| commands/evolve-skill.md:33-37; evolve-fixtures/pyramid-principle/cases/README.md:10 | `--json-schema` (structured outputs) | default | **Safe for parsing.** Guide caveat: with structured outputs at low/medium effort, the model can skip thinking or run to max_tokens (prompting.txt:92-106). The scorer passes no effort. | Pass `--effort high`, and optionally append "Think the problem through before you answer." to the scorer system prompt (prompting.txt:96). |
| token-efficiency judge-workflow.js:11,54; settle-rejudge.js:28,101 | Workflow `agent(..., {schema})`, i.e. structured | Opus/Fable | Safe | none |
| hooks/model-permission-decider.py:447-454 | first-line `ALLOW`/`ASK`, not JSON | pinned `claude-haiku-4-5-20251001` (:129); **not registered** in live settings.json (grep 0 hits) | Latent and **fail-safe**: an unparseable reply becomes ERROR, then `ask`. Under Sonnet 5.5, a preamble line would turn every consult into ASK, a silent loss of the decider's value. | If it is ever moved to Sonnet 5.5, scan all lines for the verdict token, or use `--json-schema` with an enum. |

---

## (7) REASONING_EXTRACTION: prompts that ask for reasoning in the response

**Measured: no active prompt asks the model to reproduce its reasoning.** A grep across agents,
commands, skills, hooks, scripts, bin, lib, templates, CLAUDE.global*.md, evolve-fixtures and
bench for `chain of thought | step by step | show your work/reasoning | explain your reasoning |
include your reasoning | reasoning trace | think out loud | <thinking> | scratchpad` finds only:

- agents/frontier-derivation.md:84-89: a **guard comment** saying the file is "INTENTIONALLY free of
  'explain/echo/transcribe your reasoning · show your thinking · step by step · chain of thought'"
  (written for Fable 5). The body asks for provenance **tags**, "not as a transcript of your
  thinking" (:80-81). This is already correct for Sonnet 5.5.
- agents/deep-research.md:258, commands/research.md:95, skills/research-subagents/SKILL.md:540: these
  **ban** "step-by-step reasoning chains" from returns. This is protective.
- Other hits are "step-by-step" as plan-doc wording (plan-update, plan-conventions,
  hooks/backup-before-write.sh:204) and filesystem "scratchpad". Neither is a model instruction.

Borderline wording (short justifications, not internal reasoning; low risk, noted for completeness):
- hooks/model-permission-decider.py:364 "On the second line give one short clause of reasoning." It is on
  Haiku and not registered. If moved to Sonnet 5.5, reword to "one short clause naming the risk".
- The sweep judges ask for `"why": "<=40 words"` (opus55-effort-sweep judge.py:57), and settle-rejudge.js:44
  `pair_reasons` asks for "verified differences". Both ask for a justification of the output, not
  a transcript of thinking. Keep them as they are.

**Exposed: no. Fix: none required.** Add the frontier-derivation guard comment to any new
Sonnet 5.5 judge or bench prompt, because fallback does not retry reasoning_extraction
(migration-guide.txt:341).

---

## (8) Tolerant tool-call handling (tool-name case)

**Measured: the harness has no custom tool dispatcher.** No repo code implements
`call_tool`/`CallToolRequest`/`FastMCP`/`McpServer(`. mcp-servers.json:19-33 lists only
third-party servers (motion, motion-plus, ms365). Every tool call is dispatched by CC itself.

Hook exposure: the live `~/.claude/settings.json` matchers are case-sensitive canonical names
(`Bash` ×10 PreToolUse, `^Bash$`, `Write|Edit|MultiEdit`, `Agent`, `WebFetch|WebSearch`,
`mcp__ms365__...`). A wrong-case `bash` call that **reached** hooks would bypass every Bash guard.
**Inferred, from reading the minified 2.1.284 binary, not a live test:** it cannot. CC resolves
a tool by exact `name` or declared `aliases` only (`Ut(e,n){return e.name===n||e.aliases?.includes(n)}`,
and the dispatcher `_n(s.options.tools,b,s.options.toolAliases)`). An unresolved name falls to the
`JEr(...)` error builder and yields a `No such tool available: <name>` tool_result before any
PreToolUse hook. That is the guide's option 2, return is_error. Case-insensitive matching exists
only in ToolSearch's `select:` path (`nWn`, `name.toLowerCase()===b`), which returns the
**canonical** name. Hook scripts therefore always see canonical `tool_name`.

**Exposed: no (inferred).** Smallest fix, optional: an upgrade-gate check. Fire one headless
turn on 2.1.284 × claude-sonnet-5-5 and grep transcripts for `No such tool available: [a-z]` to
measure how often Sonnet 5.5 miscases tools under this harness. A non-trivial rate costs turns,
not safety.

---

## Summary verdict

Nothing in hazards 5, 7 or 8 is exposed. Hazard 4 is **exposed on the 2.1.284 bump** at three alias
sites with no pinned effort (two agent frontmatters and the frontier-campaign red-team slot). The
SSOT also has no Sonnet 5.5 effort policy and a stale `sonnet_latest`. Hazard 6 is **latent** at two
first-JSON parsers: bin/cc-memory-extract (Haiku-pinned) and the reusable sweep judge.py template.
Both break only when pointed at Sonnet 5.5, and the judge template is the likeliest to be.
