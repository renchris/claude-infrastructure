# A15 — Hostile Review of the Decomposition Itself

**Agent**: A15 (adversarial slot) · **Date**: 2026-08-26 · **Verdict up front**: the wave
spends 12 of 15 axes on *perception capability* for a problem whose last two deaths — both
in this operator's own repos, both in March 2026 — were caused by everything *except*
perception. The decomposition re-answers the answered question and leaves the killing
questions unassigned.

Grounding read for this review: `reso-management-app/docs/research/` (the March-2026
corpus: `AI_VISION_DESIGN_QA.md`, `VISUAL_ITERATOR_V2_ARCHITECTURE.md`,
`BREAKING_THE_78_CEILING.md`, `DESIGN_ITERATION_STOPPING_CRITERIA.md`), the V2 build
commits (`aa4c0ba81`, `07bf25f40`, `8be4f3425`, all 2026-03-21), and the three apps'
manifests.

---

## Ranked missing dimensions

### M1. There is no acceptance test — the wave optimizes an unmeasured objective

**Why dangerous.** Every model axis (A1–A4, A8) will return "X is better than Y on
benchmark Z", and A6 asks which benchmarks *predict* design-review skill — but nobody owns
building the thing a prediction would be validated against. "100th-percentile design
review" is not currently falsifiable: percentile of what population, scored by whom? The
operator has already paid for this lesson once: V1 plateaued at **78/100 on a
self-assigned scale with no external referent** (`BREAKING_THE_78_CEILING.md`), and the
operator's own corpus found absolute MLLM scoring hits only **38% accuracy vs 77% for
pairwise** (MLLM-as-UI-Judge, arXiv 2510.08783, cited in
`VISUAL_ITERATOR_V2_ARCHITECTURE.md` §1). A wave that picks models before it has a
measuring stick will pick them on vibes and benchmark folklore.

**The unasked question.** "On a frozen set of screens from these three apps containing K
*seeded* defects and N operator-adjudicated real ones, what recall at what false-positive
budget constitutes done — and what does a competent human reviewer score on the same set?"

**First-pass answer.** Build the eval from the apps themselves: inject 40–60 known
regressions across defect classes (spacing, contrast, token drift, overflow, broken
responsive states, z-index/occlusion), and mine real historical visual-bug fixes from git
history as labeled positives. Calibrate the judgment tier against
[UICrit](https://arxiv.org/abs/2407.08850) (UIST '24 — 3,059 designer critiques over 983
screens; few-shot prompting on it yielded ~55% quality gains) while noting its
distribution is mobile, not these apps. Acceptance sketch: ≥80% recall on seeded defects,
≤1 false "must-fix" per screen, ≥60% operator accept-rate on judgment findings. **No
result from A1–A4 is meaningful until this exists.**

### M2. Pixel-to-source attribution — nothing bridges "this region is wrong" to "this file:line"

**Why dangerous.** The stated consumer is a Claude Code agent. A critique the agent cannot
localize to a component is a report; the loop closes only when a finding lands as an edit.
VLMs are documented — in the operator's *own* corpus — as unable to do precise
localization ("cannot precisely measure pixel distances… spatial reasoning is limited",
`AI_VISION_DESIGN_QA.md` §1). A4's GUI parsers return screen-space boxes; A7 returns
computed styles; A11 wires "integration" — none of the fifteen returns a **repo path and
line number**. This is the single highest-leverage deterministic component and it was
never assigned.

**The unasked question.** "Given a finding at region (x,y,w,h) on route R, what mechanism
returns the owning React component and source location, and what fraction of findings
arrive actionable without a human interpreting them?"

**First-pass answer.** It is mostly free in dev builds: CDP `DOM.getNodeForLocation` maps
the pixel to a DOM node; React fiber debug metadata / component stacks (what Next.js's own
dev-overlay click-to-source uses) map the node to source. This demotes the VLM to
*finding* problems and hands *locating* them to a deterministic layer — precisely the
division of labor the corpus already recommends for measurement. Without it, "review by an
agent for an agent" degenerates into prose the same agent must re-ground by grepping.

### M3. The corpse of the last attempt goes un-autopsied — nobody asks what V1/V2 actually died of

**Why dangerous.** A13 audits the March corpus as *research* (are the claims sound?). The
sharper question is operational and unassigned: **V2 was built** — pairwise comparison,
parallel variants, design constitution, fresh-eyes agent, 11 checks (commits `07bf25f40`,
`8be4f3425`, 2026-03-21) — and the agent file
(`.claude/agents/visual-design-iterator.md`) shows **zero substantive change since**; its
only post-March touches are repo-wide doc sweeps (2026-08-21/24). A two-day build burst
followed by five months of silence is the strongest evidence available about the real
failure mode, and it points at adoption/cost/workflow, not eyesight. Note also the March
effort's actual target: **one greenfield artifact** (the bottle-service luxury menu — a
generate-and-polish loop), not *review of three living apps*. The wave inherits framing
from a different problem.

**The unasked question.** "Did V2 ever run end-to-end on a real page? What score, wall
time, and token cost? Why did usage stop — and does that cause survive into the new
design?" (Transcripts and tool logs on this machine can answer all four.)

**First-pass answer.** The plateau post-mortem the operator already wrote blames
hill-climbing in a local maximum and the self-evaluation ceiling
(`BREAKING_THE_78_CEILING.md` §1) — workflow and objective failures. A new system with
better perception and the same unexamined workflow dies the same death, at higher token
cost.

### M4. Review vs regression — the economically dominant job is "did this diff make it worse", and it got one bullet inside A7

**Why dangerous.** Three shipped apps change via agent-written PRs continuously. The
high-frequency need is a **visual regression gate**: baseline screenshot management,
flake control (fonts, animations, timestamps, live data), per-PR latency budgets — the
Playwright `toHaveScreenshot` / Chromatic / Percy discipline, where determinism dominates
and a VLM is optional garnish. Absolute critique is low-frequency, high-depth. A system
designed as a critic is too slow and too noisy to gate PRs; a gate is too shallow to be a
critic. Conflating them produces something used for neither — plausibly exactly what
happened in March.

**The unasked question.** "Of the reviews this system runs in a year, what fraction are
diff-gates vs absolute audits, and which architecture components do the two actually
share?"

**First-pass answer.** They share capture (A9) and little else. Build the deterministic
diff-gate first; run absolute critique as scheduled audits. Bonus: every visual regression
caught, reverted, or fixed becomes a free labeled example for M1's eval set.

### M5. Nobody owns *what gets photographed* — state-space enumeration is not capture fidelity

**Why dangerous.** A9 answers "how do we screenshot faithfully", not "what do we
screenshot". The defects that matter in these apps live in states a naive crawl never
reaches: authenticated multi-tenant dashboards (reso-management-app carries five regional
drizzle configs), empty/loading/error states, realistic seeded data, mobile breakpoints,
dark mode, long-content overflow. A review of the logged-out homepage at 1440px reviews
the marketing screenshot, not the product — and critique of placeholder dev data is
critique of states no user sees.

**The unasked question.** "Enumerate the review surface: how many (route × auth-state ×
data-state × viewport × theme) tuples exist per app, how are authenticated and seeded
states produced reproducibly, and what is the sampling policy under a cost budget?"

**First-pass answer.** Routes from the Next.js app manifest; states via the existing
`e2e/` + `reso-playwright` infrastructure (already in the tree); sampling triaged per app
— the admin surfaces need the data-state axis most, the landing page needs the full
viewport sweep.

### M6. Finding lifecycle and the trust budget — dedup, severity, suppression, and who eats a false positive

**Why dangerous.** When the consumer is an agent, a false positive is worse than noise:
the agent will *act* on it and spend a PR making the design worse (the operator's own
memory corpus: "prescribed remedy worse than the bug"). And a reviewer that reprints the
same 40 standing findings every run carries zero information (same corpus: alarm
polarity). No axis defines the finding schema, fingerprinting across runs
(new/known/regressed/fixed), suppression, or the FP rate at which auto-fix privileges are
revoked.

**The unasked question.** "What is the finding object — fingerprint, severity,
verifiability class, lifecycle state — and what per-class FP budget gates the right to
block a PR or trigger an auto-fix?"

**First-pass answer.** Partition by verifiability: deterministic claims (contrast,
overflow, token drift — A7's layer) may gate, near-zero FP; judgment claims (VLM) never
gate, arrive batched and pairwise-framed (the corpus's own 77%-vs-38% result). Fingerprint
on (route, selector, rule).

### M7. Three apps, three *different* reference oracles — and for two of them "review" is mostly conformance, not aesthetics

**Why dangerous.** Measured from the manifests: reso-management-app is Next 16 + Panda 1.9
+ Park UI **with a real semantic-token system** in `panda.config.ts`; reso-landing-app is
"radiant" — a **purchased Tailwind Plus template** on Tailwind 3, i.e. professionally
designed already, the template *is* the oracle; the staff/admin app is a Panda 0.3
boilerplate on Next 13. There is no shared token source across the three. Where a token
system exists, most desirable critique is a deterministic conformance check (computed
styles vs tokens — pure A7, no model at all); where a template is the oracle, review is
drift-detection; only the residual is aesthetic judgment. A8's aesthetic/saliency models
are close to irrelevant for the admin tool, where density and clarity dominate.

**The unasked question.** "Per app: what is the reference artifact (tokens / template /
Figma / nothing), and what fraction of desired critique is conformance against it vs
judgment beyond it?"

**First-pass answer.** Management app → token-conformance checker first; landing → visual
drift vs template baseline; staff app → heuristic UX review where an
accessibility-tree/text-first pass may beat pixels entirely.

### M8. Non-page surfaces — the operator demonstrably ships emails and reviews TUIs, and every axis assumes a browser DOM

**Why dangerous.** The tree holds `mjml-reso-app` (×2) and a drafts-only Outlook pipeline
— email design is live, and email clients ignore modern CSS, so A7's browser-measurement
oracle is *wrong* there, not merely incomplete. The operator's feedback memory shows
repeated TUI design review (truecolor grays, pane geometry, "a render table measured at
120 cols inverts at 40") — terminal surfaces need capture and geometry-aware oracles, not
DOM. If the promise is "visual design review for this operator", these are
in-distribution and unowned.

**The unasked question.** "Which non-browser surfaces are in scope, and which need a
different capture+oracle stack rather than a smaller copy of the web one?"

**First-pass answer.** Scope v1 to web + email (email via multi-client renders — at
minimum Gmail/Outlook screenshots); keep TUI review on the existing screenshot-verify
discipline rather than pretending the web pipeline covers it.

---

## The single assumption most likely to be wrong

**That perception capability is the binding constraint — that a better eye yields a
better-designed product.** Twelve of fifteen axes bet on it. The operator's own record
refutes it twice in one month: V1 and V2 had adequate eyes (the corpus documents Claude
vision's limits *and* workable mitigations), and what actually failed was the objective
(self-assigned 78/100, no external referent), the search strategy (hill-climbing), the
framing (one greenfield page, not three living apps), and adoption (five months of
silence after a two-day build). The most probable failure of the system this wave
produces: **it sees fine, critiques plausibly, and nothing improves** — because the
objective was never defined (M1), the finding never reached a file (M2), and the loop was
never wired into the daily diff path (M4). If only three axes could be added, they are the
eval harness, pixel-to-source attribution, and the V2 autopsy. None of them is a vision
model.

---

**Sources**
- [UICrit: Enhancing Automated Design Evaluation with a UI Critique Dataset (arXiv 2407.08850)](https://arxiv.org/abs/2407.08850) · [UIST '24 version](https://dl.acm.org/doi/10.1145/3654777.3676381)
- Local: `reso-management-app/docs/research/AI_VISION_DESIGN_QA.md` · `VISUAL_ITERATOR_V2_ARCHITECTURE.md` (cites arXiv 2510.08783, arXiv 2410.21819) · `BREAKING_THE_78_CEILING.md` · `DESIGN_ITERATION_STOPPING_CRITERIA.md`
- Local commits: `aa4c0ba81`, `07bf25f40`, `8be4f3425` (2026-03-21, reso-management-app)
- App manifests: `reso-management-app/package.json` + `panda.config.ts` (semanticTokens) · `reso-landing-app/package.json` ("radiant", Tailwind 3) · `reso-staff-app/package.json` (panda-boilerplate)
