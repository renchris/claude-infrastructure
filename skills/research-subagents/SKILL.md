---
name: research-subagents
description: Full anti-under-spawn discipline for fanning out RESEARCH SUBAGENTS — parallel fire-and-forget Agent calls with no team_name, for exploration/decomposition/discovery. Load this BEFORE spawning any research/exploration subagent wave, and the MOMENT you consider how many subagents to spawn. Provides the mandatory pre-spawn decomposition artifact, default N=10 (anchor band 8-12), question-type classification + named-entity audit, the 6-field canonical brief, adversarial-sampling floor (15-20%), per-subagent depth/cost calibration, OASIS stop criterion, synthesis-bottleneck + partial-failure protocols, and the banned-phrase / trigger-phrase tables. Triggers: "research X", "explore the design space of Y", "all angles on Z", "investigate/audit broadly", "fan out subagents", /research, deep-research, or ANY decision about research-subagent count. NOT for spawning code-writing teammates (use agent-teams) or depth-first single-subsystem root-cause debugging (single agent wins).
---

# Research Subagent Fan-Out — Anti-Budgeting Discipline

*Last revised: 2026-05-24 — V2 validation (Category C gate; depth caps split by task class; NF-1 diversity finding; R2/R3/E1 routing refinements). Forensic case studies, recursion-regression tracking, and validation evidence live in `~/.claude/memory/research-subagents-*.md` and are pointed-to where load-bearing.*

**Scope**: Research subagents — `Agent` calls with no `team_name`, fire-and-forget,
return-and-die, exploration/decomposition/discovery only. **Not** teammates or
assignee agents for plan implementation (those live in `agent-teams.md`, have
worktrees, write code, persist until shutdown).

The downward bias on research-subagent count is a **cognition** problem, not an
**output** problem. Existing anti-cap rules ("if proposing ≤5, cite file:line")
constrain stated counts; they do not constrain the count-first thinking that
produces them. Lead's pre-articulation cognition is the surface that escapes
those rules. This file closes that gap.

## Pre-Spawn Artifact (Mandatory)

Before *any* research-subagent spawn, render inline:

| Axis | Sub-questions |
|------|---------------|
| (one row per distinct angle the answer must address) | (each cell = one subagent) |

Then emit verbatim:

> `Decomposition: <N> axes → <M> sub-questions → <K> parallel subagents. Axes: [...]`

**Default N = 10** for typical complex (multi-axis, ambiguous, cross-domain)
research. Anchor band 8–12. Specific drift triggers:

| Question profile | N |
|---|---|
| Single-fact lookup | 1 |
| 2-3 entity comparison | 3 |
| Targeted single-axis | 5–7 |
| **Typical complex multi-axis (THE DEFAULT)** | **10** |
| Cross-domain w/ adversarial dimensions | 12–15 |
| Open literature survey | 18–22 |
| Saturation-test / atypical | 25–30 |

**Derailment-adjusted lower bound**: under high shared-blindspot risk (all
subagents reading the same ≤5 source documents) OR high-stakes irreversibility
(security, data integrity, alignment), default downshifts to N=6–8 with stronger
adversarial coverage (25-33%). Per-subagent garbage rate compounds: at 5%
per-sub failure, P(≥1 contaminated synthesis input) = 40% at N=10, 64% at N=20.

If the next sentence contains a number under 8 before this artifact exists, you
have not decomposed enough. If it contains a number above 22 without a
documented axis-count ≥ 6, you have over-spawned. Empty cells are conspicuous;
the table cannot be faked. This is the load-bearing forcing function — every
other rule below depends on it.

**Citations**: arxiv 2511.07112 verbatim "diminishing returns beyond n≈10"
across 6 LLMs × 4 benchmarks; arxiv 2402.05120 plateau at N≈10; Anthropic
cookbook tier "10+ for complex" puts 10 as the floor not midpoint.

## Question-Type Discipline (User-Intent Fidelity)

**Methodology gap**: lead translating a feature-port question into a wave brief naming operators as targets causes workers to drift into BD/legal/compliance content. The existing OASIS/decomposition rules grade axis-orthogonality, not user-intent-fidelity. **This section is the gate that catches type-drift BEFORE the decomposition table is rendered — upstream of the Pre-Spawn Artifact step.**

### Question-Type Classification (mandatory before decomposition)

Before composing the decomposition table, lead classifies the user's question
as exactly one of (or an explicit combination, with each named):

| Type | Asks | Output looks like |
|---|---|---|
| **Product** | What should we build? | Feature spec / schema delta / UX pattern / effort |
| **Architectural** | How should we build it? | System design / data flow / migration plan |
| **Market** | What do customers want? | Demand signals / segment sizing / use-case archetypes |
| **Competitive** | Who else is in this space? | Vendor feature matrix / pricing tier / positioning |
| **BD/Sales** | How do we sell to whom? | Decision-maker map / outreach sequencing / contract terms |
| **Legal/Compliance** | What regulations apply? | Jurisdiction matrix / risk register / certification needs |
| **Operational** | How do we run X at scale? | Runbook / monitoring / failure modes |

Lead states verbatim before composing wave brief:

> *"Question type: <Product | Architectural | Market | Competitive | BD/Sales |
> Legal/Compliance | Operational>. Out of scope: <explicit list of types NOT
> to research>."*

**Default is single-type.** A mixed-type brief is more often ambiguous than
genuinely multi-type. When ambiguous, surface to user BEFORE spawning rather
than guessing. Guessing wrong is the failure mode this section addresses.

### Named-Entity Audit (mandatory when user names specific companies, people, or regulations)

When the user's brief names ≥1 specific operator/vendor/regulation/individual:

1. **Classify the named entity**: research subject OR use-case context?
2. **Default = use-case context.** Operator names are archetypes for validating
   product fit, NOT subjects of company-profile research.
3. **Lead must state verbatim in wave brief**:
   > *"Entities named in user brief (X, Y, Z) are use-case archetypes for
   > pattern-validation. Workers research the PATTERNS those entities exemplify,
   > NOT the specific entities. Do not return: decision-maker chains, contract
   > lock-in analyses, M&A timing, fundraising signals, named-individual
   > LinkedIn surveys, entity-specific tech-stack profiles, partnership
   > negotiation paths, or 'how to sell to <named entity>' framing."*
4. **Opt-out clause**: If the user's brief explicitly says "research these
   specific companies" or "this IS a BD wave," lead echoes the opt-out verbatim
   and skips the audit. Otherwise: defaults bind.

### Fidelity Restatement (mandatory before critic-gate)

Lead writes a one-paragraph restatement of the user's ask using the user's
own nouns and verbs. The restatement is the user-side contract:

> *Restatement: "<reproduce user's ask in user's vocabulary; identify the
> specific product/feature/quality the user wants extracted from the source>."*

Lead then audits the wave brief against the restatement. **Test**: can each
worker brief's "Objective" field be derived from the restatement WITHOUT
introducing scope-targets the restatement doesn't name? If not, the wave
brief has drifted — rewrite before critic-gate. The critic does not catch
restatement-vs-brief divergence; that audit is the lead's responsibility.

### Pre-Deliverable Sample-Row Spec (mandatory before worker spawn)

Lead writes ONE sample row of the deliverable's output table or section
structure. Example for a feature-port wave:

```
Feature: F&B Credit Wallet
Source pattern (Luna): pre-loaded balance, multi-outlet, end-of-day forfeit-to-takeaway
Target analog (Reso): deposit→credit→shortfall-bill (single-venue ledger pattern)
Schema delta: New entity `fbCreditWallet` at schema.ts:613+ (follows storedBottle pattern)
UX delta: Progress-toward-threshold bar (NOT remaining-balance; inversion vs Luna)
Effort: M (~800 LOC)
Out-of-scope content for this row: vendor partnerships, decision-makers, regulatory compliance
```

The sample row's STRUCTURE constrains what workers can return and stay
in-spec. If a worker returns content that doesn't map to any column in the
sample row, that's drift caught at return-time before synthesis pollution.

### Drift Recovery (synthesis-time filter)

If workers return type-drifted content despite the pre-spawn discipline:

1. Lead applies the classification filter to every finding at synthesis-time.
2. In-type findings → main synthesis sections.
3. Out-of-type findings → demoted to "Out-of-Scope Discovery" appendix OR
   dropped entirely if the user explicitly excluded the type.
4. **Never** silently incorporate out-of-type findings into recommendations.

### Banned Drift Triggers (cognition tells, lead-level)

If lead catches itself writing any of these into the wave brief, drift has
occurred. Rewrite before spawning.

| Drift symptom | What it signals |
|---|---|
| "How can we sell this to <named operator>?" | BD-drift from product question |
| "What's the decision-maker map at <named operator>?" | BD-drift; product-research doesn't need this |
| "What's <operator>'s contract lock-in with <incumbent vendor>?" | Competitive-drift; product question doesn't need contract analysis |
| "What state/federal regulations govern <feature>?" | Legal-drift; only research if user explicitly named legal as in-scope |
| "Which Fortune 500 company should we approach about <integration>?" | BD-drift; product question is feature-port not partnership |
| "How do we negotiate <partnership> with <vendor>?" | BD/integration-drift |
| Operator name appears as research-subject heading in worker brief | Named-entity-audit failure |
| Wave brief introduces decision-maker, M&A, contract, jurisdiction, lobby content | Drift confirmed; rewrite |
| "What's the fresh-RFP window at <named operator>?" | BD-drift; product feature transfer doesn't time RFPs |
| "How do we displace <incumbent> at <operator>?" | Competitive/BD-drift |

> **Case study**: V1 Luna→NA wave (2026-05-24/25). 12/13 workers BD-drifted because named operators flipped workers into operator-as-subject mode. ~$50+ total methodology overhead. Forensic detail: `~/.claude/memory/research-subagents-case-studies.md § V1 Luna→NA wave drift`.

## The Flip

Never start with *"how many subagents?"* Start with *"what are the distinguishable
sub-questions?"* Count = length of that list. Numbers anchor low; decomposition
does not (Springer 2025 / arxiv 2505.15392 establish anchoring exists in LLM
decisions; the same papers note reasoning offers partial mitigation, so the
decomposition step IS the mitigation, not its bypass).

## Brief Structure (6-Field Canonical)

Each subagent brief MUST contain these 6 fields, in this order (Anthropic
cookbook `research_lead_agent.md:107-114` canonical):

1. **Objective** — the sub-question, in one sentence
2. **Output format** — bullets, table, structured manifest, or freeform
3. **Context** — what lead already knows; sources lead has already consulted
4. **Key questions** — 2-4 specific angles the answer must address
5. **Tools / sources** — preferred starting points (files, URLs, paper anchors)
6. **Boundaries** — adversarial-pass requirement, banned content, depth budget
   (inlined per § Cost Asymmetry), stop condition

**Length**: 150-400 tokens (≈ 80-250 words). Briefs above 400 tokens suffer
lost-in-middle exposure (TACL 2024 Liu et al. — middle-position instructions
have 40-60% adherence vs 95% at primacy). Briefs below 150 tokens
under-specify; subagent satisfices on the first axis it finds.

**Serial-position discipline** (arxiv 2406.15981): last-position instructions
have 2-4× adherence vs middle. The stop-line ("if you reach saturation
before 30 tool calls, return early; if you can predict the next call's
result, stop") MUST be the brief's final line.

**Positive-framing constraint (mandatory)** — Semantic Gravity Wells
(arxiv 2601.08070, n=40,000): negative instructions on rare actions
paradoxically prime them at 87.5% violation rate. **Every "do not" /
"don't" in a per-brief instruction must be rewritten as a positive
imperative**:

| Replace | With |
|---|---|
| "Do not cite the rule file" | "Cite primary sources only (arxiv, GitHub, vendor docs, blog posts)" |
| "Don't return uncited claims" | "Return every claim with file:line or URL" |
| "No filler / hedging" | "Lead with the finding; hedge inline only when uncertainty is part of the finding" |
| "Don't exceed 15K output" | "Aim for 3-15K dense signal; compress when filler appears" |

The synthesis contract's "Banned content" list (§ Cost Asymmetry) is the
ONE structural exception — it must remain verbatim quotable across briefs.
But every other negative-framed instruction in per-brief content must be
inverted.

## Adversarial Sampling (Mandatory at N > 5; ~17% floor)

Reserve **15–20% of the wave** (minimum 1 brief at N ≥ 5; minimum 2 at N ≥ 10)
across distinct adversarial brief types. **Do not collapse all adversarial
slots to a single "find issues" brief** — different framings attack different
blind spots:

| Brief type | Verbatim framing | Where in wave structure | Token budget |
|---|---|---|---|
| **Hostile reviewer** | "What dimension would a hostile reviewer say we missed?" | Same wave as productive subagents | Full (3-15K) |
| **Devil's advocate** | "Argue the strongest version of the position contrary to the current working hypothesis." | Wave 2 (against lead's synthesis) | ≤500 tokens |
| **Red-team** | "Find evidence this approach FAILS, not evidence it works." | Wave 2 (against lead's synthesis) | ≤500 tokens |
| **Negative space** | "What dimensions am I NOT exploring, and why not? List 3 with reasons." | Lead inline, not a subagent | Inline only |

Raise to 25-33% under high-stakes irreversibility (security, data integrity,
alignment) or when productive subagents are all reading the same source files
(strong shared-blindspot signal). The 15-20% floor calibrates to observed practice (PWA cold-start ran 1:3.4; Top-10 R2 ran 1:3.5 — both ≈ 25-30% adversarial).

Consensus at high-N is a measurement artifact of shared inputs, not evidence of correctness — see § Productive Diversity Budget for the empirical basis.

## Productive Diversity Budget (Architectural vs Methodological)

Adversarial sampling (15-20%) handles shared-blindspot risk in the
*adversarial* subagents. But the remaining 80-85% — the *productive* workers
— are implicitly assumed to produce independent signals. **That premise is
empirically false for same-family LLMs.**

**Evidence**: same-family models err on the same wrong answer ~60% of the time vs ~33% independence baseline (arxiv 2506.07962 "Correlated Errors"); cross-family entanglement documented at 18 LLM × 6 family scale, +4.5% accuracy gain from penalizing entangled models (arxiv 2604.07650); distributed-info multi-agent accuracy collapses to 30.1% vs 80.7% complete-info single-agent — Stasser & Titus 1985 "hidden profile" pathology replicated in LLM committees (arxiv 2505.11556 "HiddenBench"). Full 3-paper expansion: `~/.claude/memory/research-subagents-validation-log.md § V2 NF-1`.

**Two diversity axes** to budget at spawn time:

| Axis | What it means | When to spend it |
|---|---|---|
| **Architectural diversity** | Different model families (Anthropic + Google + OpenAI) or different model generations within family | High-stakes irreversibility; when productive workers cluster on same source pool; when "100p" matters more than cost discipline |
| **Methodological diversity** | Different source types / tool access / framing polarity / sub-question angles | DEFAULT — applies to every wave; ensure no two workers read the same 5-source subset (arxiv 2604.03809 representational collapse) |

**Pre-spawn entanglement audit** (mandatory at N ≥ 6):

1. List the productive subagent set (excluding adversarial slots).
2. For each pair, check: same model family? same primary source subset?
   same tool-access pattern? same framing polarity? If all four → entangled.
3. Target: ≤30% of productive-subagent pairs are entangled.

**When architectural diversity is unavailable** (single Anthropic family —
the typical case in Claude Code), **methodological diversity becomes the
only compensating mechanism**:

- Enforce source-disjoint stratification (assign disjoint paper/source
  subsets per worker; canonical anchors shared only as cross-reference).
- Vary framing polarity across worker briefs (some "argue for X", some
  "find evidence against X", some "compare X to Y").
- Vary tool-access patterns (some workers Read-only, some WebSearch-heavy,
  some Bash-heavy for empirical tests).

**Without methodological diversity at minimum, high-N waves are sub-linear
in coverage** — N=12 entangled workers ≈ N=4 independent workers per the
Behavioral Entanglement Index data.

## Quota-Aware Wave Sizing (Max plan — 2026-07-01)

On a Max plan the binding constraint on a 10–100-agent wave is the **5-hour + weekly
usage quota**, not dollars — and Opus draws it down ~5× faster than Sonnet/Haiku.
Objective = **maximal actionable yield within the weekly cap** (SSOT + full rationale:
`~/.claude/model-routing-freewin-probe.md` § Quota-constrained refinement). The reasoning
WORKER slot is floor-pinned on the **effort** axis (= max per probe T1 + the T2 effort grid —
low/med/high/xhigh all fall below the open-ended-grounding floor, for BOTH Opus and Sonnet).
On the **model** axis it is pinned to Opus 4.8 ONLY in-process/teammate surfaces; **in a
Workflow it is NOT** (see the free-win bullet below). Quota is managed at the WAVE level:

- **Decomposition discipline is the primary lever.** Spawn exactly the orthogonal axes; the
  OASIS stop kills the redundant tail. The "never under-spawn / default 10–30" rule guards
  against *lazy* under-spawning — it is NOT "more is always better." Under a quota, N is a
  cost knob: N = the count of genuinely distinct axes, not a target to fill. (The cheapest
  token is the un-spawned agent — this is the biggest zero-quality-cost saving.)
- **Workflow bulk synthesis-worker free win (T2 effort grid, CERTIFIED 2026-07-01).** In a
  Workflow, spawn breadth-first synthesis/inferential workers as
  `agent(brief, {model: 'claude-sonnet-5', effort: 'max'})` — **NOT** Opus-4.8@max. Sonnet-5@max
  ties Opus-4.8@max on quality across easy AND hard synthesis briefs (0 reliable Opus wins, blind
  4-judge default-to-refute) at **~2-3× lighter quota-draw** — so it frees the scarce Opus headroom
  for the decisive slots. HARD requirements: effort MUST be `max` (Sonnet@xhigh drops below the
  floor — wrong-file citations on hard grounding), AND the brief MUST carry a saturation bound
  (~15-25 tool calls; unbounded max-effort Sonnet overflowed context once). In-process `/research`
  can't pin effort → those workers stay Opus 4.8 (`workflow_synthesis_worker` role in
  `~/.claude/model-config.yaml`).
- **Tier-mix down.** Route every genuinely-retrieval axis to Haiku; reserve Fable for the
  sharp 10–15%; the inferential axes take Sonnet-5@max in Workflows / Opus-4.8@max in-process.
- **Prefer Workflows for waves >~10 agents** — the only surface where per-slot model+effort is
  pinnable (in-process subagents inherit lead effort, GH #25591), AND the only surface where the
  Sonnet-5@max worker free win above is realizable.

**Do NOT put a projected quota/$ number in the 15-second abort manifest** (decided via item-3
probe wf_b0f4b091-172, 2026-07-01): the manifest can compute *draw* but not *remaining* cap
(machine-readable only via the undocumented `claude.ai/api/oauth/usage` endpoint), so any figure
is un-anchored false precision that duplicates the existing $/ETA proxies and rots. The manifest's
N + tier ("Spawning 20 across …, all Opus-max") is the honest scale signal; real headroom belongs
on the statusline (true denominator via oauth/usage). Read the manifest's "$ at Opus rates" as a
rough scale proxy only — on a plan, marginal $ ≈ 0.

## Cost Asymmetry (The Economic Foundation — Calibrated)

Lead context is precious; subagent context is **mostly** free *except for
what the subagent surfaces in its report* AND *except for cache-TTL effects
on lead synthesis*. The classic asymmetry holds within a single wave: a
subagent burning 200K tokens internally and returning 8K of dense findings
has spent 25× more context than lead carries.

**Cache-TTL caveat**: Anthropic dropped prompt-cache default
TTL from 1h → 5min around Mar 2026 (GitHub claude-code #46829). Parallel
subagent waves achieve ~4.2% cache hit rate empirically (arxiv 2601.06007
"Don't Break the Cache") because each parallel call pays its own cache write
that siblings can't share. If a wave takes >5 minutes, lead's pre-wave
context exits cache before results return — synthesis pays full
cache_creation rate on the whole session context. Practical impact: 4-7×
cost inflation on long-running waves vs the naive calculation.

**Calibrated cost (Opus 4.8 $5/$25 pricing, ~600K input per subagent at
80% input / 20% output split; Fable 5 slots — `claude-fable-5`, $10/$50 —
cost 2× the corresponding row)**:

| N subagents | No-cache | 70% cache hit | Batch | Cache + batch |
|---|---|---|---|---|
| 10 | $54 | $37 | $27 | $19 |
| 20 | $108 | $74 | $54 | $37 |
| 30 | $162 | $112 | $81 | $56 |

At pinned depth (~180K per subagent, not 600K), divide above by ~3 — a
20-subagent wave is ~$36 no-cache, ~$12 with cache+batch.

Marginal value approaches zero around **$100-150 per question** for typical
complex research; $250 is the practical ceiling. The "rounding error vs
engineer-hours" framing holds when research substitutes for >3 engineer-hours
of investigation (≈ $500); breaks down for trivial questions (15-min
investigations ≠ rounding error against $50 wave).

**Synthesis contract** (mandatory in every research-subagent brief, inlined
verbatim per brief):

> "You have ~1M tokens of nominal context. Effective working ceiling is
> ~400K before reasoning quality degrades (LongSWE-Bench, MRCR v2, Opus 4.6
> self-degradation curve). Target 150-250K on exploration; hard cap 500K.
> Make tool calls until next-call falsifiability check fails — predict the
> next call's result; if you can predict it AND wouldn't change your answer,
> stop. Typically 20-40 tool calls for non-trivial questions. Run an
> adversarial self-pass before composing.
>
> Return signal-dense findings, **no fixed token cap on returns** — typical
> 3-15K for depth research, ≤500 for trivial lookups, ≤500 hard cap for
> adversarial / red-team briefs where the deliverable IS a sharp verdict.
>
> **Banned content**: narration ('I will now investigate'), step-by-step
> reasoning chains, raw tool output, full file contents, re-explanation of
> the brief, filler ('it's worth noting'), hedging ('one could argue').
>
> **Required content**: findings as bullets or tables, every claim with
> file:line or URL citation, alternatives considered (with brief reason
> ruled out), blockers/uncertainties named explicitly, adversarial-pass
> output integrated into the body. Distinguish empirical (cited) from
> theoretical (reasoning) for non-trivial claims.
>
> If you can't fill 3K tokens of pure signal on a non-trivial question, you
> under-explored — but go deeper by making more *informative* tool calls,
> not by padding text."

> Why inlined not tagged: GH claude-code #46829 (cache TTL broke shared-prefix dedup). Restore tag pattern only if sibling-prefix dedup ships. Full rationale: `~/.claude/memory/research-subagents-validation-log.md § cache-TTL`.

The legacy ≤500-token cap was an artifact of 200K-context-window thinking; at 1M context, signal density is the constraint. **Narrow exception**: adversarial / red-team subagents where the deliverable IS a sharp verdict keep a ≤500-token cap — bloat dilutes a crisp conclusion.

## Per-Subagent Depth (Calibrated to Empirical Degradation Curves)

Breadth without depth is shallow research, but **depth past the model's
reasoning cliff is paying full price for degraded synthesis**. The 1M context
window is nominal, not effective — empirical measurements:

- LongSWE-Bench: Claude 3.5 Sonnet drops **29% → 3%** going 32K → 256K
  (arxiv 2505.07897 — 90% relative reasoning collapse).
- Opus 4.6 self-flags degradation at ~40% utilization, recommends fresh
  session at ~48% ≈ 480K (GH anthropics/claude-code #34685).
- Anthropic's own production cap: 20 tool calls / 100 sources per subagent
  (~50-200K context spent) — an order of magnitude less than 500-800K.
- Anthropic architects around 200K as the working ceiling.

**Per-subagent depth target (task-class-conditional)**:

- **Synthesis / reasoning workers** (multi-hop inference, citation-and-bullet
  synthesis — the typical `deep-research` (Opus 4.8) worker): **150K modal,
  256K ceiling, 30K floor.** 180K is the modal sweet spot — well below the
  256K reasoning cliff. Hard ceiling: 500K.
- **Retrieval workers** (pure lookup + extraction, no inferential synthesis —
  Explore Haiku, or rare retrieval-only Sonnet slot): **350-500K modal, up
  to 1M for genuinely retrieval-only briefs**, with explicit caveat on
  lost-in-middle (TACL 2024: 40-60% middle adherence even on retrieval).
  Above 500K expect ~15-25% degradation on multi-needle retrieval per MRCR v2.

> Depth-cliff evidence: LongSWE-Bench 29%→3% (32K→256K) is reasoning-specific; retrieval is robust (MRCR v2 Opus 4.6 76% at 1M; Gemini 2.5 Pro 91.5%→83.1% across 128K→1M). Full benchmarks: `~/.claude/memory/research-subagents-validation-log.md § V2 R2`.

**Routing implication**: a `deep-research` (Opus 4.8) worker brief that includes any
inferential synthesis falls under "synthesis" budget (cap at 256K). The
`Explore` Haiku tier is retrieval by definition. If a brief sits ambiguously
between — *"extract these claims from this source set AND reason about
their convergence"* — treat as synthesis (use lower cap). The previous "500–800K" prescription landed inside the degradation zone for synthesis workers.

**Tool-call density**: 1 tool call per 5–8K of accumulated context.

- 180K context ↔ ~25-35 tool calls (matches the ≥30 contract)
- 250K context ↔ ~35-50 tool calls
- Below 1 call per 10K = hoarding, not exploring
- Above 1 call per 2K = not distilling between calls

**Saturation at subagent level**: stop tool calls when next call would surface refinement of evidence already gathered, not a new dimension — use the test in § Pre-Commitment Falsification. **Anti-satisficing trigger**: if composing a return without having predicted the next call, that's satisficing — keep going. Quality of decomposition > raw call count.

**`Explore` vs `deep-research` vs `general-purpose`**:

- `Explore`: built-in, fast, read-only. **Cost is track-conditional — verify
  the running track before pricing a fan-out:** stable `claude`/`cc` (2.1.114)
  → Haiku-tier (~70× cheaper); eval `claude-next` (**≥2.1.198**) → Explore
  inherits the **LEAD model, capped at opus** (2.1.198 change), so a heavy
  Explore fan-out draws opus/lead-tier quota — the ~70× discount does NOT hold
  on the eval track. Use for terminal codebase lookups, file:line discovery,
  doc URL fetches.
- `deep-research` (custom, frontier-tier — frontmatter `opus`; lead passes
  `model: "fable"` at call time during the access window): use for
  multi-axis depth research. ⚠️ See § Recursion Regression — the `Agent`
  tool declaration is currently NOT honored by stock Claude Code; the
  subagent runs as flat (non-recursive) deep research.
- `general-purpose`: built-in, Sonnet, all-tools. Use for adversarial briefs
  (≤500 token verdict) and as `deep-research` substitute when custom-agent
  registration is unavailable (new session before first restart).

**Frontier tier (window-conditional)**: Fable 5 (`claude-fable-5`, $10/$50 —
2× Opus 4.8, the most intelligent tier, ABOVE Opus) is available from plan
usage 2026-06-09 → 2026-06-23, ONLY on the claude-next eval track (CC
2.1.170+). SSOT: `~/.claude/model-config.yaml` → `frontier_access`. While
`active: true` AND the session is on the eval track, route the
adversarial/judge/depth-coordination slots to Fable 5 via the call-time
Agent `model: "fable"` override — and the same for Dynamic Workflow
judge/synthesis slots via `agent(prompt, {model: "fable"})`. On the stable
2.1.114 track or after the window, those slots use the fallback (Opus 4.8).
Agent-definition frontmatter stays `model: opus` so the definitions remain
valid on both tracks — the override is always call-time. Agent TEAMS run on
both tracks too; teammate models are gated by the auto-mode allowlist in
the SSOT, not by the track — default Opus 4.8; `claude-fable-5` verified
in auto mode 2026-06-09 and allowlisted, so eval-track teams may pin
`teammate_frontier` (Fable 5) per-member where judgment density warrants
the 2× cost. **Lead/default sessions do NOT ride the frontier tier**
(`lead_default` reverted to Opus 4.8 on 2026-06-09 — Fable-by-default burned
5-hour plan windows). Panel frontier work runs AGENT-INITIATED
under the bounded-autonomy policy (global CLAUDE.md § Frontier Tier Routing +
SSOT `frontier_discovery_budget`, hook-enforced cap): `/frontier-run` over the
per-project `docs/research/FRONTIER_HOLES.md` ledger — blocking walls escalate
inline, queued holes batch at wrap-up; capture via `/frontier-hole`. The
`claude-fable` launcher is an optional human surface, not the pipeline. Panel workers use the `frontier-derivation` agent definition
(baseline-blind; frontmatter `opus`, call-time `model: "fable"`).

> **⚠️ QUALITY-FIRST ROUTING OVERRIDE (2026-06-30) — READ FIRST; governs this whole
> tier-selection section.** The breadth-first **worker slot defaults to Opus 4.8**
> (`deep-research`), NOT Sonnet. The Sonnet-worker default + the "$/insight" cost-win math
> below (MALBO ~47%, "pure Opus overpays") were a COST-first optimization valid when Sonnet
> was cheaper at iso-quality. **Sonnet 5 broke that**: ≤ Opus 4.8 quality AND ~15% MORE
> $/task at max effort (Artificial Analysis 2026-06-30) — neither a quality nor (at
> inherited-max) a cost win. Under the operator's quality-first objective (100th percentile;
> cost only breaks ties among equal-quality configs), every reasoning-sensitive worker takes
> the GA ceiling (Opus 4.8); Fable 5 is the availability-gated tier above. Reinterpret the
> section below: "Sonnet worker" / "deep-research-sonnet" = the **Opus 4.8** worker slot; the
> "re-spawn on Opus" escalation becomes **re-spawn on the frontier (Fable 5, window-gated)**;
> the cost-win math is retained (historical) but SUPERSEDED for worker selection. Sonnet 5
> re-enters the worker slot ONLY via a probe-certified free win (iso-quality AND cheaper/task
> at pinned low/med effort in a Workflow) — spec: `~/.claude/model-routing-freewin-probe.md`.

**Type-mix pin for typical complex research wave (model-tier-aware)**:

- 60% `deep-research` (Opus 4.8) — multi-axis breadth-first worker  [worker slot; was `deep-research-sonnet`/Sonnet — see override]
- 25% `Explore` (Haiku 4.5 on stable-114; **inherits lead model, capped opus,
  on eval ≥2.1.198 — re-price this slice, it is no longer the cheap tier there**)
  — codebase lookups, file:line discovery
- 10% `deep-research` (frontier: Fable 5 via `model: "fable"` during the
  access window on the eval track; otherwise Opus 4.8) — adversarial /
  red-team briefs only
- 5% `deep-research` (frontier, same routing) — rare multi-hop
  depth-coordination (>5 inferential steps, non-decomposable); usually
  indicates question should have been re-decomposed instead

**Cost win**: at N=15 typical wave, mixed-tier ≈ $8.80 vs homogeneous Opus
≈ $16.50 — ~47% reduction at iso-performance (Anthropic prod pattern; MALBO
arxiv 2511.11788; X-MAS arxiv 2505.16997).

**When the lead picks tier per subagent**: default to `deep-research` (Opus 4.8)
for the worker slot (quality-first — see override). Escalate to the frontier
(Fable 5 via call-time `model: "fable"` during the access window) only on explicit trigger:

1. Brief is adversarial / red-team / devil's advocate (sharpness > cost)
2. Sub-question requires multi-hop reasoning chain >5 steps AND lead is
   confident the question CAN'T be re-decomposed into more independent axes
3. User explicit "highest quality, cost no object"

**Failure-mode signal (automatic re-spawn triggers)** — two distinct signals
trigger automatic re-routing:

1. **Sonnet worker return <3K on non-trivial question** → lead inspects at
   synthesis time; if not a satisficing-failure (worker did try) → re-spawn
   on Opus OR re-decompose into smaller independent axes.
2. **Sonnet worker's predict-next-call falsifiability check fails on an
   inferential gap** (worker explicitly flags: *"I couldn't determine X
   without multi-hop inference Y"*) → **automatic re-spawn on Opus**, no
   re-decomposition first. The inferential gap is itself the signal that the
   sub-question required multi-hop reasoning Sonnet couldn't complete;
   further decomposition doesn't help.

Pure Opus for a typical wave overpays ~47%; pure Sonnet underperforms on adversarial briefs; pure Explore misses synthesis. The mix wins on $/insight when ≥20% of sub-questions are pure retrieval — almost always true for codebase-adjacent research. Full V2 R3 routing rationale: `~/.claude/memory/research-subagents-validation-log.md § V2 R3`.

**Highly-canonical retrieval exception**: for retrieval briefs targeting specific line ranges of *highly-canonical* sources (Anthropic cookbook, published research papers with file:line citations, vendor docs at named anchors), route to `deep-research` (Opus 4.8), NOT `Explore`. Haiku's retrieval lacks the reasoning to disambiguate version-drift / line-shift in canonical sources. The 25% Explore allocation contracts to ~20% when canonical retrieval briefs surface; the freed slot goes to the Opus 4.8 worker. Full V2 E1 derivation: `~/.claude/memory/research-subagents-validation-log.md § V2 E1`.

## Banned Phrases (Cognition Tells)

| Banned (under-spawn cognition) | Replace with |
|---|---|
| "Let me think about this myself first AND decide a count now" | "Let me decompose the question space first; count = decomposition length" |
| "I'll start with N and add more if needed" | "What are the axes? Each gets ≥3 sub-questions" |
| "Let me try a few approaches" | "Let me enumerate every distinguishable approach" |
| "Batch into rounds of N" / "wave 1 / wave 2" | "Fire all independent sub-questions in one wave" |
| "N subagents should be enough" | "What's the full question space?" |
| "Consider whether to spawn more" | "What am I NOT exploring yet?" |
| "Let me start narrow and widen" | "Let me start wide and prune" |
| "A focused investigation should reveal..." | "Parallel investigations across [list] will reveal..." |
| "That seems like overkill" | "What's the cost of under-sampling here?" |
| "Let me match agents to buckets" | "Each bucket gets 3–10 sub-questions; fan each" |

**The single most subtle ban**: thinking that *commits to a count* before
producing the decomposition table. Bare meta-reasoning is fine and is the
cited mitigation for anchoring per arxiv 2505.15392 — but it must precede
externalizing a number. The failure mode is "I think 5 is right" → render
decomposition table → fill to match the 5. The fix is to render the table
first, then read the count off it.

## Pre-Commitment Falsification (Per-Spawn Calibration)

Before deciding NOT to spawn the next subagent, write the predicted finding in
one sentence. Then ask: *"If this subagent returned the opposite, would my
final answer change?"*

- Can't predict → spawn.
- Can predict + would flip conclusion → spawn (it's load-bearing).
- Can predict + wouldn't flip conclusion → stop is justified.

This is the only calibration signal that's both adversarial (resists motivated
reasoning) and cheap (one sentence, no extra inference).

## Stop Condition (OASIS — Orthogonal Axes + Sublinear Saturation)

The "two consecutive waves of agreement" criterion is structurally insufficient
for same-model subagents: homogeneous LLM committees converge to >0.95 cosine
similarity in 1-2 rounds regardless of whether they share a true answer
(arxiv 2502.19559 "Stay Focused"; arxiv 2604.03809 "Representational Collapse").
Two waves of agreement is the textbook signature of false consensus, NOT
saturation. The replacement criterion is structural diversity at spawn time
plus four checks at synthesis time:

**OASIS criterion** — stop spawning when ALL of:

1. **Orthogonal axes**: every spawned axis has pairwise brief-cosine ≤ τ to
   every other (default τ = 0.6). Diversity enforced at brief-write time, not
   detected post-hoc.
2. **Adversarial null**: the mandatory adversarial-pass subagent's "what am I
   missing" returns refinements only, no new axis.
3. **Sublinear tail**: cumulative-discovery curve fits `c·N^α` (α<1); next
   subagent's expected gain < ε (default 0.5 unique findings).
4. **Falsifiability check**: write the predicted next finding in one sentence;
   ask *"would the opposite flip my conclusion?"* — if no, stop is justified.

If any one fails, name the failing dimension and spawn ONE more subagent on
it (not a fresh wave). Iterate, do not re-wave.

**Never stop on count.** But also: never accept consensus as evidence of
correctness; it may be evidence of collapse.

## Failure Mode to Guard Against: Obvious-Axis Saturation

Covering predictable dimensions (perf, security, UX, cost) thoroughly while
missing non-obvious ones (regulatory, second-order, adversarial users,
time-of-day behavior, accessibility-of-the-edge-case, supply-chain, hydration
race conditions). Tells:

- All subagents share framing vocabulary
- No subagent disagrees with another
- Findings cluster on the lead's first-principles tree
- No "found something we weren't looking for" results

**Before declaring saturation**, run the negative-space trigger verbatim:

> "What dimensions am I NOT exploring, and why not? List 3 with reasons."

If any reason is *"I forgot"* or *"not obviously relevant"* → promote into
scope, spawn the missing subagent(s). If the reason is *"explicitly out of scope
per user intake"* → cite the user's words. Cap at 3 dimensions per invocation;
each must cite either a concrete file/symbol or a named technique.

## Wave Structure (1 wave default; conditional gap-fill follow-up)

**Default**: single wave. All N subagents fired in one Agent-tool-batch.
This is the maximum-parallelism case and what the rest of this rule assumes.

**Exception 1 — API burst splitting**: if N > 15, split into 2-3 sub-batches
within the same logical wave (10-15 per batch, fired sequentially within
the same lead turn). This is API-throughput accommodation, NOT phased
research strategy. Manifest before the first sub-batch:

> `Spawning 22 across 4 buckets in 2 sub-batches: data 6 + UI 8 (batch 1),
> auth 4 + perf 4 (batch 2 immediately following) — reply 'abort' within
> 15s, else proceed.`

**Exception 2 — Conditional gap-fill (the only legitimate sequential
pattern)**: after Wave 1 returns and lead synthesizes, run the negative-space
trigger:

> "What dimensions am I NOT exploring, and why not? List 3."

If any reason is *"I forgot"* or *"not obviously relevant"* with a citable
file:line or named technique → spawn Wave 2 of 3-8 narrow gap-fill subagents
on the NAMED dimensions (each at 200-400K narrow context, not full depth).
If all reasons are *"explicitly out of scope"* → wave 1 stands; no wave 2.

**Banned**: scheduled multi-wave ("wave 1 of 3, then wave 2 of 3"). Scheduled
waves are batched under-spawning disguised as discipline. The discriminating
test: *is the next wave's brief determined by the previous wave's findings,
with a named gap?* If yes → legitimate sequential. If no → fire all at once.

The 15-second abort window lets the human decide on cost (manifest names projected $$ + wall-clock band), not on plan quality.

## Task-Category Gate (When Multi-Agent Actually Applies)

Anthropic's multi-agent research system reports a 90.2% gain (Opus orchestrator
+ Sonnet subagents vs solo Opus) — but the same engineering blog explicitly
caveats: *"domains that require all agents to share the same context or involve
many dependencies between agents are not a good fit for multi-agent systems
today"*. Coding tasks are named as a poor fit. Production config: 3–5 default,
max 20, NO recursion, ≤20 tool calls / 100 sources per subagent. Stanford's
arxiv 2604.02460 (Apr 2026) shows single-agent matches or beats multi-agent on
multi-hop reasoning under matched token budgets.

**Four task categories**:

| Category | Verdict | When |
|---|---|---|
| **A. Breadth-first independent retrieval** | MAS wins | Multiple venues / SKUs / regions; regulatory + perf + security + UX coverage; each axis answerable independently |
| **B. Depth-first multi-hop reasoning** | SAS wins at matched compute | Single-file refactor, proof, single-subsystem bug; long inferential chains; Stanford arxiv 2604.02460 |
| **C. Degraded-context tasks** | MAS wins via factorization | Long source + many tools + noisy distractors (>20 files in scope, >10 tools, codebase audits at scale); single-agent reasoning falls off sharply; Stanford 2604.02460 §3 + LangChain benchmark |
| **D. Verification-heavy / role-structured** | MAS only if extra compute is OK | Test-time compute scaling rebadged; redundant agents verifying each other |

Apply this rule's fan-out discipline for Category A and Category C. Default
to single-agent for Category B. Category D is optional — MAS is fine if cost
permits, single-agent is fine if not.

**When unsure**, ask in order: (1) *can each axis answer correctly without
seeing other axes' answers?* If yes → A. (2) *does the lead context have to
juggle >20 files or >10 tools simultaneously?* If yes → C, fan out even if
the question feels depth-coordinated. (3) *is this a verification problem
masquerading as research?* If yes → D, escalate cost decision. Otherwise →
B, single-agent.

## Synthesis Bottleneck Threshold

Lead's effective working context (frontier lead — Fable 5 / Opus 4.8 — 1M nominal, ~400K usable post-rot)
accommodates subagent returns up to a ceiling that the rule must respect.

**Lead-context budget at synthesis time**:

```
Lead_effective                              ≈ 400K
- System prompt + CLAUDE.md + rules         ≈ 30K
- Tool schemas                              ≈ 20K
- Decomposition + pre-spawn artifact        ≈ 10K
- Plan / tool calls / prior turns           ≈ 30K
- Output budget reserved                    ≈ 32K
- Safety buffer                             ≈ 20K
─────────────────────────────────────────────────
Available for subagent returns              ≈ 258K
```

**N_max single-tier** at varying return densities:

| Per-return density | N_max |
|---|---|
| 3K (terse) | ~86 |
| 8K (mid) | ~32 |
| 15K (max) | ~17 |

**Operational rule**: at N > 25, switch to **artifact-reference pattern** —
subagents write full findings to `~/.claude/research-artifacts/<session>/<agent>.md`
and return a 500-token manifest with section anchors. Lead reads sections
on demand during synthesis. Decouples N from lead-context. Mirrors
Anthropic's production system per their multi-agent blog.

At N > 50, additionally introduce **mid-tier synthesizer subagents** (3-5
mid-synths, each handling 5-10 leaves). Cost: ~10-15% information loss per
hierarchical layer; one extra LLM hop per leaf (~3× supervisor pattern cost).
Justified only for genuinely large research questions (>50 distinguishable
axes). Mid-synth brief MUST include: *"preserve dissenting findings verbatim;
never smooth to consensus"* to prevent coordination drift.

**Per-wave context audit (mandatory before spawning N > 20)**:

```
available_context = 400K - (current_used) - 32K_output_reserve - 50K_safety
if N × expected_return_density > available_context:
  → split into waves
  → OR escalate to artifact-reference pattern
  → OR escalate to mid-tier synthesizers
```

## Partial-Wave Failure Protocol

If K of N subagents return with errors (rate-limit, context-overflow,
tool-unavailability, recursion-attempted-on-broken-Agent-tool), the synthesis
contract's "banned: hedging" clause does NOT apply to partial-coverage
findings. Lead's synthesis under partial coverage MUST:

1. Name the missing axes explicitly in the synthesis output: *"3 of 12
   subagents failed (axes: X, Y, Z). Findings below cover the remaining
   9 axes."*
2. Decide between:
   - **Resynthesize from partial**: if the failed axes are non-critical or
     redundant with adjacent successful axes
   - **Respawn the failed axes**: cheaper than respawning the full wave; pass
     the lead's pre-wave context as the brief context for the respawn
3. Never present partial coverage as complete coverage. The banned-content
   rule against hedging applies to *successful* returns; partial coverage
   demands explicit acknowledgment.

## Trigger Phrases That Elicit Under-Spawning

Empirically (case studies in `feedback-no-parallelism-cap.md`), these framings
trigger smaller initial decompositions than warranted:

- *"investigate X"* → narrow, spawns ~3–5
- *"audit Y"* → check-list mode, spawns ~5–8
- *"re-check / re-investigate Z"* → assumes prior work covered the axes
- *"deep dive into W"* → singular-investigation framing

When the user uses any of these, apply this rule **more aggressively**, not
less. The framing is the trigger; the actual question space is what counts.

## Recursion Regression

> Recursion status (May 2026 — SUPERSEDED on CC 2.1.183; see Update below): depth-2 fan-out NOT operational in stock Claude Code. The `Agent` tool is not exposed to subagents regardless of frontmatter declaration (GH #46424 primary blocker; also #4182, #19077, #31977, #30703). Default to depth-1 flat fan-out and re-spawn from lead context when sub-axes emerge. Workarounds + re-evaluation trigger: `~/.claude/memory/research-subagents-recursion-regression.md`.
>
> **Update 2026-06-19 — RESOLVED on CC 2.1.183 (claude-next), empirically verified.** A controlled headless probe against the 2.1.183 binary (`--safe-mode --permission-mode auto`, Opus parent) returned `{"fanout4_completed": true, "depth2_DEPTH2OK": true}`: a worker subagent spawned its own leaf sub-subagent via the `Agent` tool and relayed the result up (depth-2 works → #46424 cleared), and four parallel workers under an Opus parent all completed with no session termination (→ GH #61258 does not reproduce on 2.1.183). So on the **2.1.183 runtime** hierarchical fan-out (lead → mid-tier synthesizers → leaf workers — the § Synthesis Bottleneck N>50 pattern) is available; prefer it over re-spawn-from-lead when sub-axes emerge. **Scope:** verified depth-2 (the operationally relevant tier; the 2.1.172 changelog claims up to 5, untested past 2). The **stable `claude` track (still 2.1.114 until bumped) keeps the old non-recursive behavior** — hold depth-1 discipline there. Probe provenance: claude-next 2.1.170→2.1.183 upgrade session, 2026-06-19.

## Relationship to Other Rules

| File | Scope | Relationship |
|---|---|---|
| `agent-teams.md` | Teammates / assignees with `team_name`, worktrees, code work | Disjoint — that file governs implementation agents; this governs research subagents |
| Critical Rule #6 in project `CLAUDE.md` files | Forbids STATING low caps in proposals | Complementary — that rule constrains output, this constrains cognition |
| `feedback-no-parallelism-cap.md` (memory) | Past case studies of under-spawning | Empirical backing for this rule |

The two files (`agent-teams.md` and this one) cover the two distinct agent
patterns Claude uses. Neither should be confused with the other; the discipline
required is different in each case.
