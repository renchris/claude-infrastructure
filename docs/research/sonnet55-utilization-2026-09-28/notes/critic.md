# Completeness critic: Sonnet 5.5 adoption + CC 2.1.280 -> 2.1.284 notes

Scope: every file in this `notes/` directory was read in full (card-p001..p148, vendor-docs, cc284-{workflows,hooks,teams,adversary},
harness-hazards-{a,b}, census, skills-consolidation). Spot checks used `/tmp/s55/*`, `claude-infrastructure` @ `9eb533126`
(read-only) and the four account `.claude.json` flag caches (read-only). Nothing outside this file was written.

## Verdict

**INCOMPLETE for (a) the routing/effort table and (b) HOLD/ADVANCE. Close to complete for (c) harness changes. Adequate for (d) skills.**

- The card and vendor facts are complete. All 148 pages have a note, and every figure caption has an extracted raster that some note read. That was measured with a python map of `[Figure|Table N]` captions in `card.txt` against `/tmp/s55/figs/*`: every Figure page has a raster, and the pages without one are text tables that the notes transcribed.
- What is missing is the join between those facts and **this fleet**, in three places:
  1. The currency the fleet actually pays in (weekly plan points, not USD).
  2. Any Sonnet 5.5 measurement in our own harness.
  3. Proof that the chosen effort level actually binds on a Sonnet 5.5 subagent or Workflow agent.
- (b) is written off an adversary note that predates a GREEN gate run which no note cites.

---

## Ranked gaps (most decision-relevant first)

### 1. Cost comparisons use USD, but the fleet pays in weekly plan points (changes rows a1-a14)
- `model-config.yaml:762-770` says the fleet has **zero dollar exposure**: "The scarce resource is 4×100 weekly points ... Before citing ANY cost comparison for a routing decision, state which currency it is in."
- Every Sonnet-vs-Opus cost claim in the notes is list USD:
  - vendor-docs.md §4: the CSV $/task figures, and the claim "Sonnet 5.5 High costs less than Opus 5.5 Medium".
  - card-p109-128.md: the matched-cost frontiers on CursorBench, HLE, DRACO and WANDR.
  - card-p129-148.md: AutomationBench (Sonnet "about half the cost").
- No note gives Sonnet 5.5's points-per-token rate, or whether Max meters Sonnet separately. (`tests/*` still carry a "You've hit your Sonnet limit" message shape: census.md:100.)
- `bin/cc-quota-price` fits rates per model from transcripts. The corpus has only **55 main + 8 subagent Sonnet 5.5 records** (harness-hazards-a.md:9), so no fit exists.
- **Why it matters:** the whole case for Sonnet 5.5 in the scoped-coding, mechanical-edit, breadth-research, Explore and cheap-bulk rows is "cheaper at matched quality". In points, the sign could flip either way.
- **Close by:** after a controlled Sonnet 5.5 burn on one account, run `bin/cc-quota-price` and state the per-token points ratio against Opus 5.5. The two gate runs already burned Sonnet 5.5 on next..next4 (gate-sonnet55.json, checks #1-#9).

### 2. No Sonnet 5.5 measurement in our own harness at any effort (changes a5-a10, a13)
- The incumbent routing was **settled by our own measurement**:
  - research-subagents SKILL.md:438-449 slot table;
  - model-config.yaml:901 and :910-913 ("Opus 5.5 @xhigh beat Sonnet 5 @max 5-1");
  - `docs/research/opus55-{effort-sweep,synth-reprobe}-2026-09-22`.
- No note ran Sonnet 5.5 on that corpus. All Sonnet 5.5 evidence comes from vendor harnesses (Cognition, Cursor, Proximal, AA, Zapier).
- Several card charts show Opus 5.5 dominating at matched cost, which argues against assuming a Sonnet win:
  - HLE, every cost point (p.119-120);
  - CursorBench above about $2 (p.115);
  - DRACO above about $1 (p.121);
  - WANDR (p.122);
  - OSWorld (p.131).
- The code-review row has **no review or bug-finding benchmark at all**. The only evidence is the FrontierCode footnote (the max-effort code-review skill fan-out), p.85 rubric speculation in a code-review task, and a CodeRabbit testimonial ("simple and moderate reviews"). The testimonial is cited only partly, at vendor-docs.md:141.
- **Close by:** re-run the synth-reprobe / effort-sweep harness with Sonnet 5.5 arms at medium, high and xhigh against the Opus 5.5 @xhigh incumbent, for the synthesis, review and judge slots.

### 3. Effort binding for Sonnet 5.5 subagents is unverified; the gate skips low/medium; the thinking-off rung is unreachable (changes the effort column everywhere)
- `lib/cc-upgrade-gate/check04_effort.sh:30-40` tests only high, xhigh and max. Measured in gate-sonnet55.json #4: "high(default,+model) xhigh max". **low and medium, the rungs vendor guidance recommends for agentic coding (vendor-docs.md:192), were never probed on 2.1.284.**
- Measured on 2026-09-28 with a python mmap regex over `/tmp/s55/cc284.strings`: the 2.1.284 model catalog sets `claude-sonnet-5-5 ... default_effort:"medium"`, and **also `claude-opus-5-5 ... default_effort:"medium"`**. That corrects vendor-docs.md:278 ("No vendor source here states Opus 5.5's Claude Code default").
- Four sources, taken together, leave the effective effort of an unpinned or frontmatter-pinned Sonnet 5.5 subagent unknown:
  - 2.1.280 cl.md:552: a pre-per-model saved effort level does not apply to new models;
  - #97829: frontmatter `effort` is ignored on the `--agent` path (cc284-adversary.md:34);
  - #97634: `/tasks` hides effort;
  - SSOT model-config.yaml:210-211: inheritance comes from the lead.
- Affected sites: research-decomposition-critic.md, deep-research-sonnet.md, frontier-campaign/SKILL.md:29, and Workflow `agent({effort})`.
- `type:"between_tools"` occurs **0 times** in cc284.strings. The 6 `"between_tools"` hits are dir-sync code, and the Sonnet 5.5 capability list has no thinking-off entry (measured, same scan). So vendor-docs §10's lowest setting is not reachable in CC, and **the table's floor is `low`**. The vendor also says Sonnet 5.5 low collapses on wide search (WANDR low 10.0 vs Sonnet 5 low 22.8, card-p109-128.md:90).
- **Close by:**
  - add low and medium to check04 for non-Opus families;
  - run one probe that spawns `model: sonnet` (no effort), `effort: low` in frontmatter, and `agent({model:'claude-sonnet-5-5', effort:'low'})`;
  - read the effort actually sent (`--debug` request log, or thinking-token deltas).

### 4. HOLD/ADVANCE: two GREEN gate runs exist but no note cites them, and the age rule is unresolved (changes b)
- Measured: `/tmp/s55/gate-sonnet55.json` and `/tmp/s55/gate-opus55.json` are both **GREEN, 14 pass / 0 fail / 1 skip** (#14 authstore) on 2.1.284, run across next..next4 (`/tmp/s55/run-gates.sh`, `gate.done` rc=0 twice). This satisfies skills-consolidation.md §4.3.1's run-set rule. **No note references either file.**
- The notes disagree on the verdict:
  - cc284-adversary.md:8-12 says YELLOW: 2.1.284 was 1.8 h old against a 7-day bar, and it predicts a #03 flake. Gate #03 passed on both models.
  - cc284-hooks.md:8 says ADVANCE.
- The "<1 week field exposure" rule is a churn *heuristic* in cc-version-audit/SKILL.md:116-117. The operator mandate is "upgrade immediately ... IF all our ways of working continue to work" (cc-upgrade-gate/SKILL.md:15-16), and the Opus 5.5 precedent advanced the fleet pin while the MANIFEST row said `skip` (skills-consolidation.md:332-334). No note says which rule governs the **fleet pin**.
- Also unprobed:
  - Whether 2.1.280 can run `--model claude-sonnet-5-5` by passthrough. "Cannot be reached any other way" (cc284-adversary.md:10) rests on string counts only, with no 280 x sonnet-5-5 check #1.
  - The Ultracode keyword on 284. cc284-teams.md:16,25 says it drives orchestration only; cc284-adversary.md:37 cites #97442, where the keyword pinned xhigh through 2.1.283. They conflict, and no live probe was run.
  - The "gave no verdict" count was not re-measured after the gate.

### 5. Haiku 4.5 retirement floor (2026-10-15, 17 days out): consumers not censused, and no Sonnet-vs-Haiku comparator (changes a11 Explore and a14 cheap bulk)
- vendor-docs.md:24 gives Haiku 4.5 as "Not sooner than October 15, 2026". That is a floor, not a scheduled date. Haiku 5.5 is due "in the coming weeks" (vendor-docs.md:40).
- census.md covers only Sonnet literals. Haiku consumers, measured by `grep` over skills, commands, agents, bin, hooks, scripts and lib:
  - skills/research-subagents/SKILL.md:449, :611-613, :680 (`roles.research_retrieval`, Explore `model:"haiku"`);
  - commands/research.md:81;
  - bin/claude-accounts:966;
  - bin/cc-memory-extract:54;
  - hooks/model-permission-decider.py:129;
  - scripts/handoff-fire.sh:10444, :13352;
  - scripts/headless-precondition-probe.sh:26.
- The card has no Haiku comparator on any capability benchmark. The only Haiku data is the p.96 affect chart.
- Estimated from list price × the vendor token-inflation figure, vendor-docs.md:28,34: Sonnet 5.5 costs about 2.6x Haiku 4.5 per unit of text ($2/$10 vs $1/$5, times about 1.3x tokens). That is USD; see gap 1.
- The Explore default model on 284 was not extracted either. cc284-workflows.md:34 asserts "unchanged" from 280 without measuring it.

### 6. Safeguard refusal and fallback exposure in our own workload is unmeasured (changes a2 long unattended, a13 adversarial)
- The card says cyber classifiers reroute requests to **Sonnet 5**:
  - p.29 and p.51;
  - p.52: in the destructive-injection eval, 25% of coding requests were served by Sonnet 5;
  - p.113: 1.2% of TB 4.0 requests were flagged.
- Sonnet 5 is far weaker: TB 4.0 10.3% vs 70.6% (vendor-docs.md:63).
- A fallback also drops Sonnet 5.5 thinking (vendor-docs.md:163). The 284 catalog gives Sonnet 5.5 `refusal_fallback` (measured, cc284.strings).
- No note measures, for our workload (rm-rf and credential hooks, security-worded hazard docs):
  - the rate of `stop_reason:"refusal"` or fallback;
  - whether the CC fallback is sticky for the session;
  - whether `switchModelsOnFlag:false` suppresses it.
- harness-hazards-b.md:174 flags that `bin/cc-classify` SAFEGUARD_SIGNATURES may miss the new wording, but does not test it. Tracker #97946 (CVP member blocked on 284) is noted only in passing.

### 7. Structured-output Workflow agents at low/medium are untested (changes a10 Workflow bulk synthesis, a7 bounded verifier)
- harness-hazards-b.md:124 rates `agent(..., {schema})` "Safe" by inference.
- The vendor gives two warnings:
  - forced `tool_choice` returns 400 on Sonnet 5.5 (vendor-docs.md:174);
  - structured outputs at low/medium sometimes think until `max_tokens` (vendor-docs.md:135).
- `lib/cc-upgrade-gate/check08_workflow.sh:12-19` runs only an **untyped** one-agent workflow, with the lead's own model. It never runs an Opus lead that pins `agent(brief,{model:'claude-sonnet-5-5', effort:'low'|'medium', schema})`.
- **Close by:** run 20 schema'd Sonnet 5.5 agents at low and medium, and count null or `max_tokens` results.

### 8. Teammate eligibility: the notes contradict each other and the gate (changes a3 scoped coding wave, a5 mechanical)
- cc284-workflows.md:32: the alias `sonnet` **passes** `hooks/agent-teams-enforce.sh`, and the full id is denied.
- cc284-teams.md:24 and census.md:34,86: a bare `sonnet` teammate is **denied**, because `non_firstParty_max` lists no `claude-sonnet-*`.
- Gate #7 teams-spawn **PASSED** on Sonnet 5.5, but its modelUsage shows both `claude-sonnet-5-5` (414 output tokens) and `claude-opus-5-5` (161 output tokens) (measured, gate-sonnet55.json). Which process ran which model is not established. Neither is whether `gate_headless` loads the enforce hook.
- `classifier_model: claude-sonnet-4-6` (model-config.yaml:805-808) is marked VERIFY and was not re-checked on 284 (census.md:35).

### 9. Comparators exist elsewhere but were not joined, and the Fable-Mythos mapping is wrong-footed (changes a1 lead, a8 judge, a13 adversarial)
- Multi-Agent ProgramBench (card p.123-124) defers its harness to the Opus 5.5 card §8.12 and gives **no Opus 5.5 multi-agent numbers**. The repo already has them: `docs/research/opus55-utilization-2026-09-22/notes/{c2-agentic-multiagent,g3}.md`, README.md:134-142 (a different metric, time-to-0.6). No note joins them.
- Fable 5.1 (roles `research_adversarial` and `frontier_discovery`) is absent from HLE, DRACO, WANDR, ProgramBench, OSWorld and Multi-Agent.
- card-p001-018.md:4 infers "Fable 5.1 = Mythos 5.1". The vendor docs treat them as **distinct models**: effort.txt lists both, and preserved-thinking.txt says "Claude Mythos 5.1 and models before Claude Fable 5.1 don't run the prefix check". So the pp.55-90 Mythos 5.1 alignment values (sycophancy, input hallucination, SHADE and so on) must not be read as Fable 5.1's.
- No evidence on whether Sonnet 5.5 and Opus 5.5 errors are decorrelated, which is the whole premise of the adversarial slot ("a DIFFERENT model on purpose", research-subagents SKILL.md:447).

### 10. Long-horizon and multi-file coding evidence is max-only or unlabelled (changes a2 long unattended, a4 ambiguous multi-file)
- Max-only or unlabelled:
  - SWE-Bench Pro, Multilingual and Multimodal, DeepSWE (p.110; DeepSWE has no comparators);
  - FrontierSWE v2 (p.114);
  - ProgramBench (p.117-118, Opus +11.5);
  - Toolathlon (p.134-135);
  - OSWorld (points unlabelled, p.131-132);
  - Multi-Agent ProgramBench (effort not stated, p.123).
- Per-effort coding data exists only for FrontierCode (peaks at xhigh), CursorBench and TB 4.0 (announce CSV).
- So the high and xhigh cells for long or ambiguous coding have **no Sonnet 5.5 evidence**, and the vendor says to reserve xhigh/max for measured gains (vendor-docs.md:193).
- The reliability signals the table must weigh are Pass³ 68.5, the lowest of the frontier set (p.135), and the 62% fault-copying rate (p.98). No note converts either into an unattended-run risk.

---

## Lower-ranked gaps (recorded, not in the top 10)

- **Prompt audit not run.** `/doctor prompt-audit` (2.1.283 L112) is recommended in four notes but was never run.
- **Vendor snippets not mapped to consumers.** None of carry-through, scope-limit, no-extra-review, verification or think-first (vendor-docs.md §12) is mapped to the agent defs, CLAUDE.global.md or the `workflow-lean` system prompt. Measured: a `grep` for the vendor-named anti-patterns ("minimize tool calls", "strictly necessary", "hold all findings", "don't think" and similar) over CLAUDE.global.md, agents, skills, commands, templates and hooks found none. The only hits were "no preamble" wording, which is not a vendor anti-pattern.
- **Visual/chart row: no brief tells the model to crop.** Chartography "tools" means a container plus an image-crop tool, worth +28.6 points (card p.125-126), and Opus leads without tools. The host has cropping available (measured: PIL 12.2.0, `magick`, `sips`), but no skill or brief tells a visual slot to crop and re-Read.
- **`lean_prompt` capability not examined.** The 284 catalog gives Sonnet 5.5 `lean_prompt`, and gives Opus 5.5 `opus_5_5_prompt_bundle` too (measured, cc284.strings). So CC sends the two models different system prompts, and some in-CC behaviour differences may be prompt-driven. No note covers this.
- **Catalog vs vendor-doc differences.** The Sonnet 5.5 catalog entry lacks `mid_conv_tool_change`, although the vendor docs list mid-conversation tool changes as supported (vendor-docs.md:42). It also has no `effort_cost_index`, which Sonnet 5 has: `low:0.47 ... max:5.59` (measured).
- **Write-without-read shim does not cover Sonnet 5.5.** The guard's skip logic is structurally the same in 280 and 284 (measured: `tengu_write_tool_not_read_hypothetical` context in both strings dumps). But none of the four account flag caches has a `tengu_velvet_mallet_sonnet_5_5` or `_opus_5_5` key: only `sonnet_5`, `sonnet_4_6` and `opus_5` (measured, python read of `~/.claude-{next,secondary,tertiary,quaternary}/.claude.json`). So `hooks/lib/read-before-write-parity.sh` no-ops for both 5.5 models. This predates Sonnet 5.5, but it has never been live-tested for Sonnet 5.5.
- **Account-linking exemption unexplored.** The vendor exempts linked accounts from thinking binding (vendor-docs.md:246). harness-hazards-a.md:110 finds nothing linked, but no note asks whether the four orgs *can* be linked. That would remove the transplant hazard.
- **Skills (d): lane frequency not counted.** The model-vs-harness-only mix was not counted from MANIFEST history. It decides whether the harness-only lane's higher load (skills-consolidation.md:441) matters. The six-phrasing auto-load probe and the "Sonnet 5.5 skips reference files" risk are both unmeasured (skills-consolidation.md:419-437).
- **Card §1.1 not summarised.** The training data and process section (p.9) has no summary. Low routing impact.

## What is adequately covered (no action)

- Card coverage is complete:
  - effort-labelled points are transcribed wherever the card labels them;
  - the announce CSV gives exact TB 4.0, FrontierCode, CursorBench and AA-Briefcase per-effort data, and it agrees with the chart read-offs.
- Harness hazards 1-8 are mapped to file:line with measured exposure.
- The prefix and anchor behaviour of `claude-bump-models`/`claude-lint-models` was measured in a simulation.
- Binary pins are censused, including the new `bin/cc-memory-extract:55`.
- The CHANGELOG 281-284 was read in full on three axes plus the adversary.

## Measurement labels

- **Measured:**
  - caption-to-raster map: python over `/tmp/s55/card.txt` form-feed pages and `/tmp/s55/figs`;
  - gate verdicts: `python3 json.load` of `/tmp/s55/gate-{sonnet55,opus55}.json`;
  - catalog fields and `between_tools`/`velvet_mallet`/`write_tool_not_read` counts: python `mmap` + `re` over `/tmp/s55/cc28{0,4}.strings`;
  - flag caches: python read of the four `.claude.json` files;
  - Haiku, Opus-literal and anti-pattern greps: `grep -rn` in `claude-infrastructure`;
  - crop tooling: `python3 -c "import PIL"`, `which magick convert sips`.
- **Estimated:**
  - Sonnet 5.5 vs Haiku 4.5 per-text cost of about 2.6x: list price ratio × the vendor's ~30% token-inflation figure;
  - the "17 days" to the Haiku floor: date arithmetic from 2026-09-28.
