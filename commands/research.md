---
description: Breadth-first multi-axis research via parallel subagents. Renders decomposition table, classifies question-type, audits named entities, fires wave with adversarial sampling. Default N=10. Invokes + applies the research-subagents skill verbatim. Use for "how to improve X", "research the design space of Y", "all angles on Z". For depth-first root-cause debugging, use /investigate instead.
argument-hint: <topic to research>
---

# /research — Breadth-first parallel subagent fan-out

**Topic**: $ARGUMENTS

First invoke the **research-subagents** skill (via the Skill tool) to load the full discipline, then apply it verbatim. Render each of the five mandatory pre-spawn artifacts below BEFORE spawning anything. If the topic resolves as Task-Category B (depth-first multi-hop reasoning over a single subsystem), stop and surface to user — single-agent wins there; this command is wrong.

---

## 1 · Question-Type Classification (verbatim emission)

Classify the topic as exactly one of (or explicit combination, with each named):

| Type | Asks |
|---|---|
| **Product** | What should we build? |
| **Architectural** | How should we build it? |
| **Market** | What do customers want? |
| **Competitive** | Who else is in this space? |
| **BD/Sales** | How do we sell to whom? |
| **Legal/Compliance** | What regulations apply? |
| **Operational** | How do we run X at scale? |

Emit verbatim before composing the wave brief:

> *Question type: \<type\>. Out of scope: \<explicit list of types NOT to research\>.*

Default is single-type. When ambiguous, surface to user BEFORE spawning rather than guessing.

## 2 · Named-Entity Audit (mandatory if topic names operators/vendors/regulations)

Default: named entities are **use-case archetypes**, not research subjects. State verbatim per `research-subagents.md § Named-Entity Audit`. Workers research the PATTERNS those entities exemplify, NOT the specific entities. Opt-out only if user intake explicitly says "research these companies" / "this IS a BD wave."

## 3 · Fidelity Restatement

Reproduce the user's ask in the user's own nouns and verbs:

> *Restatement: "\<user's ask in user's vocabulary; identify the specific product/feature/quality the user wants extracted\>."*

Audit the wave brief against this restatement — every worker's Objective field must derive from it without introducing scope-targets the restatement doesn't name.

## 4 · Pre-Deliverable Sample-Row Spec

Write ONE sample row of the deliverable's output table or section structure. The sample row's STRUCTURE constrains what workers can return and stay in-spec.

## 5 · Decomposition Table (load-bearing forcing function)

Render BEFORE composing any count:

| Axis | Sub-questions |
|------|---------------|
| (one row per distinguishable angle the answer must address) | (each cell = one subagent) |

Then emit verbatim:

> `Decomposition: <N> axes → <M> sub-questions → <K> parallel subagents. Axes: [...]`

**Default N = 10** for typical complex research. Anchor band 8–12. Empty cells are conspicuous; the table cannot be faked.

Drift triggers downshift to N = 6–8 under high shared-blindspot risk (all subagents reading the same ≤5 sources) OR high-stakes irreversibility (security, data integrity, alignment) — pair with raised adversarial coverage (25–33%).

## 6 · Wave Manifest (cost transparency)

State projected cost band + wall-clock band so the human decides on cost not plan quality:

> `Spawning N across <buckets>. ~$X-Y cost band, ~Z min wall clock. Reply 'abort' within 15s, else proceed.`

---

## Operational constants (apply during brief authoring)

**Type-mix pin** (`§ Per-Subagent Depth`):

| Tier | Allocation | Use |
|---|---|---|
| `deep-research` (Opus 4.8)² | 60% | Multi-axis breadth-first worker (default) |
| `Explore` (Haiku 4.5) | 25% | Codebase / file:line lookups |
| `deep-research` (frontier¹) | 10% | Adversarial / red-team briefs |
| `deep-research` (frontier¹) | 5% | Rare multi-hop depth-coordination |

¹ Frontier = Fable 5 (`claude-fable-5`, $10/$50) via call-time Agent `model: "fable"` override while `~/.claude/model-config.yaml` → `frontier_access.active` is true AND the session is on the claude-next eval track (window 2026-06-09 → 2026-06-23); otherwise Opus 4.8. Agent frontmatter stays `model: opus` — the override is always call-time.

² Quality-first (2026-06-30): the 60% worker slot defaults to **Opus 4.8** (`deep-research`), not Sonnet. Sonnet 5 @ max is ≤ Opus 4.8 quality AND ~15% pricier/task (Artificial Analysis), so its old "cheaper-at-iso-quality" free win broke. Sonnet 5 re-enters only via a probe-certified low/med-effort Workflow — spec: `~/.claude/model-routing-freewin-probe.md`.

Highly-canonical retrieval exception: route to `deep-research` (Opus 4.8), not `Explore` (Haiku lacks reasoning to disambiguate version-drift in canonical sources). Allocation shifts 25% → 20% Explore, 65% Opus 4.8 worker.

**Adversarial coverage**: 15–20% floor (1 brief of 4 types — hostile reviewer · devil's advocate · red-team · negative space). Raise to 25–33% under high-stakes irreversibility OR shared-source workers.

**Per-brief synthesis contract**: inline verbatim from `§ Cost Asymmetry` into every brief's Boundaries field. Banned content: narration, step-by-step reasoning chains, raw tool output, full file contents, brief restatement, filler, hedging.

**Per-brief budget**: 150–400 tokens (≈80–250 words). Stop-line MUST be the brief's FINAL line (serial-position adherence per arxiv 2406.15981, 2-4× over middle).

**Productive diversity** (mandatory at N ≥ 6): vary source subset / framing polarity / tool-access pattern across productive workers. Target ≤30% entangled pairs.

**Falsifiability stop**: before declining to spawn one more subagent, predict its finding in one sentence — would the opposite flip your conclusion? If yes, spawn. If no, stop is justified.

---

**Anchor-low guard (final line, load-bearing for adherence)**: render the decomposition table BEFORE committing to any number. If your inner monologue contains "I'll start with N and add more" — you've anchored. Restart from the axis list; count = length of that list.
