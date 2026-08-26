# A13 — Adversarial audit of the visual-design-review corpus (2026-08-26)

**Corpus:** 4 research docs (2026-03-20/21) + 2 plans (2026-06) in `reso-management-app`.
**Method:** every named artifact grepped/stat'd at HEAD; shas checked with `merge-base --is-ancestor`; external facts checked against live vendor docs (platform.claude.com vision page fetched 2026-08-26) and web search. Repo untouched (read-only).

**Headline verdict:** the four March docs describe an architecture whose *subject* (the
`/preview/luxury-menu` route), *instrument* (`scripts/visual-validate.ts`), and *central bet*
(autonomous VLM-judge quality gating to 85-90+) were all subsequently deleted or refuted by the
operator's own June 2026 evidence — yet none of the four carries a staleness banner. The June
hardening plan is the healthy layer: its claims verify by content at HEAD. New work should inherit
from the June layer and treat the March layer as historical research, not as premises.

---

## Findings table

Paths abbreviated: AVQ = `docs/research/AI_VISION_DESIGN_QA.md`, AVDA = `docs/research/AUTONOMOUS_VISUAL_DESIGN_ARCHITECTURE.md`, WF = `docs/research/VISUAL_DESIGN_ITERATION_WORKFLOW.md`, V2 = `docs/research/VISUAL_ITERATOR_V2_ARCHITECTURE.md`, HARD = `docs/plans/AUTONOMOUS_VISUAL_ITERATION_HARDENING.md`, CAMP = `docs/plans/DESIGN_PAGE_METHODOLOGY_100P_CAMPAIGN.md`.

| # | file:line | Claim (verbatim, trimmed) | Defect class | Convicting evidence | Should now say |
|---|---|---|---|---|---|
| 1 | AVDA:106, :126, :522 | "scripts/visual-validate.ts — 15 computed-style checks … Run: `npx tsx scripts/visual-validate.ts`" · status "Created (1,123 lines)" | **stale → deleted** | File ABSENT at HEAD. Deleted 2026-05-01 in `af27ca827` ("70KB validator hard-coded to deleted route (26 references)"); it was 1,974 lines at deletion, not 1,123. | Layer 1 as described no longer exists; the living Layer-1 equivalents are `tests/visual/*` invariant specs + `pnpm design:gate`. |
| 2 | AVDA:522, V2:1-5, WF:141-159 | The whole loop targets `/preview/luxury-menu`; agent "First Action" curls `http://localhost:3000/preview/luxury-menu` (`.claude/agents/visual-design-iterator.md:26-37`) | **stale → subject deleted** | Route created `73c21305a` (03-20), nuked `50aeffea8` 2026-04-25 ("abandoned scratch work — luxury-menu, luxury-menu-v2…"). `src/app/preview/` gone; preview lives at `src/app/(preview)/preview/` with different pages. | The V1/V2 iterator program was abandoned; the agent file is an orphan whose first action fails by design (curl → exit). |
| 3 | AVDA:528 (§16) | `.claude/agents/visual-design-iterator.md` — "**TO BUILD**"; `docs/reference-images/` — "**TO CAPTURE**"; `~/.claude/hooks/visual-preview.sh` — "**TO BUILD**" | **never-implemented / wrong status both ways** | Agent WAS built (568 lines, on disk, `aa4c0ba81` 03-20 — the status row was stale within a day) but is dead (row 2). `docs/reference-images/` has NO add-commit in `git log --all` — the 5-image reference set (AVDA:398-406) was never captured, so the "comparative anchoring" and "calibration pass" mitigations (AVDA:272-278) were never executable. The hook was never built. | Mark agent BUILT-then-ORPHANED; reference set and hook NEVER BUILT. |
| 4 | AVDA:3-4 vs AVDA:49 | "Opus 4.6 — ranked #1 on Design Arena" (problem statement, repeated §1) | **false + internally contradicted** | Its own §2 says "Claude Opus 4.1 (Thinking) holds #1 … Opus 4.6 was added Feb 5, 2026 and is still accumulating votes" — the headline attached the #1 to a model that never held it. As of Aug 2026 the leader is **Kimi K3** (~1368-1372 Elo), with Claude Opus 5 ~3rd (~1327) per BenchLM/modelgrep trackers. | The capability-transfer argument can no longer lean on "our model is #1"; if the premise matters, re-derive it for the current model. |
| 5 | AVDA:35, :55, :539 | "generation-evaluation correlation is 60-80% (Microsoft Research AesCoder validation)… Validated AI aesthetic scoring against Design Arena's human-voted rankings" | **citation does not support claim** | arXiv 2510.23272 is "Code Aesthetics with Agentic Reward Feedback" — an instruction-tuning/RL paper (AesCode-358K, GRPO-AR, OpenDesign benchmark, AesCoder-4B model). Its public abstract/page contain no judge-vs-Design-Arena 60-80% agreement result. This number is the load-bearing support for §1's "Answer: Yes". | Treat the 60-80% figure as UNVERIFIED; the cited paper is about training generators, not validating judges. |
| 6 | V2:13-16 vs AVDA:58 | "absolute scoring achieves only 38% accuracy, while pairwise comparison reaches 77%" (V2, citing arXiv 2510.08783) | **contradicted-by-sibling + unverified as stated** | AVDA cites the SAME paper as "accuracy within ±1 point on a 7-point Likert scale >75%" — i.e., absolute scoring looks fine under the sibling's reading. The paper (n=30 interfaces) reports pairwise performance *rising with the human score gap* and explicitly warns MLLMs are "not … replacements for real-life human evaluation". The bare 38%/77% dichotomy that justified V2's entire pairwise pivot is not recoverable from the paper's public summaries. | If pairwise-vs-absolute matters for new work, re-read the paper directly; do not inherit either sibling's number. |
| 7 | V2:83-86 | "C3AI (ACM WWW 2025) demonstrated that negative framing (prohibitions) works for constitutional AI, while positive aspirational framing doesn't" | **misread citation** | C3AI's headline finding is the near-opposite: *positively framed, behavior-based principles align better with human preferences*; the negative-framing advantage is a narrower result about fine-tuned CAI model adherence. The doc quotes the secondary result as the paper's conclusion. | "C3AI found fine-tuned models adhere better to negatively framed principles, though positively framed ones align better with human preference — we chose prohibitions for machine-checkability." |
| 8 | AVQ:559 (+table :553-557) | "Formula: `tokens = (width * height) / 750`" · "200x200 ~54 · 1000x1000 ~1,334 · 1092x1092 ~1,590" | **false (superseded)** | Live vision docs (fetched 2026-08-26): cost is patch-based — `⌈w/28⌉ × ⌈h/28⌉` visual tokens. 200×200 = **64**, 1000×1000 = **1,296**, 1092×1092 = **1,521**; high-res tier caps at 4,784. The /750 formula is gone from the docs. | Recompute every token/cost budget (AVQ §8, AVDA §10, V2 §9) on the patch formula. |
| 9 | AVQ:545-549 | "Keep longest edge at or below 1568 px. Images above this are auto-downscaled" · "Maximum 8000x8000 … <5 MB (API), <10 MB (claude.ai)" | **stale on two of three** | Live docs: **Claude 4.7+ models have a high-resolution tier — 2576 px long edge / 4,784 visual tokens** (automatic, no opt-in); 1568 is now only the "standard" tier. File size: **10 MB on the Claude API direct** (5 MB only on Bedrock/Google Cloud). 8000×8000 still correct. Also unmentioned: requests with >20 images impose a stricter ~2000 px per-image cap. | 2576 px capture target on current models (≈3× image tokens — a real cost trade); 10 MB API; note the >20-image dimension cap. |
| 10 | AVQ:12-13 | "up to 600 images per API request" | survives, with caveat | Live docs confirm 600 (100 for 200k-window models) — but the 20+-image stricter dimension limit and the 32 MB request cap are the binding constraints in practice. | Keep, add the two caveats. |
| 11 | AVQ:30, :33, :165-183, :496-498 | "Spatial reasoning is limited… Cannot say 'padding is 16px'" · crop-tool with "normalized coordinates (0-1 range)" · "vision encoder processes images at roughly 1092x1092 to 1568x1568" | **stale (capability moved)** | Anthropic now ships a first-class "Coordinates and bounding boxes" workflow: current Claude models **return absolute pixel coordinates** (documented as approximate but supported); the encoder claim is wrong for the 2576-px high-res tier. The §7B sub-pixel arithmetic ("1px on 1440px is sub-pixel") changes at 2576. | Re-benchmark the "cannot localize" claims on the current model before designing around them; prefer absolute-pixel coordinate prompting over the 0-1 crop-tool pattern. |
| 12 | AVQ:292 vs AVQ:332 | "Applitools Eyes … 99.9999% accuracy, 0.001% false positives" vs "False positive rate 5-10% (Applitools Visual AI)" | **unfalsifiable + self-contradictory** | Two figures for the same product, four orders of magnitude apart, both traceable only to vendor marketing; presented in a section titled "What the Research Shows". | Drop both, or label as vendor marketing. |
| 13 | AVDA:38-39, WF:10, WF:97-135 | "60% of visual checks are fully automated… 28%… 12%" / "80% of visual validation is automatable today" | **unfalsifiable denominator + refuted in spirit** | The percentages are 15/7/3 over ONE 25-item checklist for the now-deleted luxury-menu (gold #E5C048, Bodoni, receipt, 90-min timeout — WF:99-135). Never a population. And HARD's Phase-1 measurement (06-27, `wf_27c57ec7-877`) showed the pixel-VRT lane that "automation" actually shipped caught **0/6** real deck bugs prospectively — "regression-lock ≠ prospective detection" (HARD:130-141). | Automation coverage must be restated per-mechanism (invariant / regression-lock / device-only) as HARD does, not as one scalar. |
| 14 | AVDA:41, :547, V2:5, :236 | "targets a score of ≥ 85/100 … Total cost per full design pass: ~$0.70" · "V2 targets 90+ autonomous quality … Expected ceiling 90+" | **never-validated aspiration** | The program was nuked 2026-04-25 before V2 ever ran to convergence; no recorded run reached 85 or 90. The 78/100 V1 plateau (V2:5) is itself a self-scored number from the very rubric-judge later found biased. Cost figure computed on the dead /750 formula and March pricing. | These are hypotheses the program abandoned, not results. |
| 15 | V2:88-98 + agent §4 (`.claude/agents/visual-design-iterator.md:293`) | Constitution gates "gold accents <8% surface", "info density 20-30%" — binary pass/fail | **unfalsifiable as instrumented** | The agent's own "How to Check" column reads "Visual estimation from screenshot" — a *binary gate* adjudicated by the estimator the constitution exists to constrain. No instrument ever computed a surface-area %; the claimed determinism is fictional for ~⅓ of the 24 rules. | A gate is binary only if a measurement exists; route %-area rules through computed styles/pixel counting or demote to advisory. |
| 16 | AVDA:64-67 vs WF:213 | "1M Context Window Eliminates the Constraint … ~2,000 screenshots … Context is NOT a constraint" vs "Context fills after ~15-20 screenshots" | **contradicted-by-sibling** | Two March docs, same corpus, 100× apart. Neither is right unconditionally: the fleet later measured the same model id running at BOTH 200K and 1M windows (claude-infrastructure `CONTEXT_ECONOMY_V2`), and effective reasoning degrades well before nominal limits. V2:216 "382K — well within the 1M window" silently assumes the 1M case; under a 200K session the plan exceeds the window ~2×. | Budget against the *measured* session window, never the nominal max. WF's 15-20 figure is closer to observed Claude Code practice. |
| 17 | AVDA:296-307 vs V2:108-120 | Stop conditions: hard cap **12**, phases 1-3/4-6/7-12, scored-rubric convergence vs hard cap **15**, phases 1-6/7-9/10-15, pairwise convergence | **contradicted-by-sibling, unmarked** | V2 (03-21) explicitly supersedes AVDA (03-20) — "V1 plateaued… V2 replaces the core evaluation and iteration architecture" — but AVDA carries no superseded banner and still reads as current. Which is right: V2, trivially, and then neither (row 2). | Banner AVDA §§5-9 as superseded by V2, and both as retired by `50aeffea8`. |
| 18 | AVDA:548, WF:156 | "Hard iteration cap (safety) | 50 (maxTurns)" | **contradicted by the built artifact** | Shipped agent has `maxTurns: 200` (`.claude/agents/visual-design-iterator.md:6`) and adds `Agent` to the tool list the docs specify as "Read, Edit, Bash, Glob, Grep". The safety story documented is not the one built. | If the agent is ever revived, reconcile; otherwise moot. |
| 19 | WF:245 | "Percy alone is $399/month" | **stale price** | Current published Percy tiers: free 5K screenshots; ~$199/mo (Professional, 25K); ~$249 Desktop&Mobile; enterprise bundles $449-599. No $399 tier. Direction ("cloud, $$$") survives; the number doesn't. | "Percy is a paid cloud tier (free 5K, then ~$199+/mo as of 2026-08)". |
| 20 | WF:42, :279 | "Playwright … 143 devices" | **stale count** | Installed Playwright ships **207** device descriptors (`Object.keys(devices).length` = 207, measured 2026-08-26). | Version-bound fact; say "~200 presets" or drop the number. |
| 21 | WF:43, :272 | "BrowserMCP … **AVOID** — dies on /compact (GH #3426)" | **moot (subject retired)** | BrowserMCP was retired fleet-wide 2026-08-11 (0 invocations / 3,504 transcripts / 30 d; wrapper `git rm`'d — per claude-infrastructure CLAUDE.md). The AVOID verdict was right and is now vacuous. | The live decision is agent-browser CLI primary / chrome-devtools-mcp for rich surfaces. |
| 22 | WF:186 | "PostToolUse hooks **cannot inject images back into context** … confirmed working for text but not images" | **unverified today** | Measured on a March-era binary; hook semantics have demonstrably changed since (e.g., Stop-hook `additionalContext` became model-reaching on 2.1.220 — claude-infrastructure `docs/research/final-response-shaping-2026-08-08.md`). No re-measurement of the PostToolUse-image claim exists. | Re-probe on the current binary before designing around the two-step relay. |
| 23 | AVQ:343 | "Claude 3 Sonnet scored 70.31% accuracy vs GPT-4V's 65.10%" | **stale (two model generations)** | Accurate as a citation of the screenshot-to-code blog, but both models are 2+ generations old; useless as guidance for an Opus-5-era build. | Historical footnote only. |
| 24 | HARD:203, :601, :694 | "#12 … BUILT report-mode (`55e854d91`)" · "Commit `22a64ac25`" | **sha-citation rot (content fine)** | Neither sha is an ancestor of `origin/main` (rebase-land rewrote them; both were "NOT pushed" at write time). Content-verify PASSES: `occludedTargets` live in `tests/visual/layout-matchers.ts` + `layout-invariants.deck.spec.ts`; `waitForStableGeometry` live in `scripts/ios-sim-verify/verify.mjs` (3 hits); `scripts/visual/bless-rubric.mjs` exists. | Cite trunk shas or paths; the mechanisms themselves are real and live. |
| 25 | CAMP:58 | Phase 1B output "`…_PHASE1B_NORTHSTAR.md` (the yardstick)" | **never-implemented** | `docs/plans/DESIGN_PAGE_METHODOLOGY_PHASE1B_NORTHSTAR.md` ABSENT; no add-commit in `git log --all`. Phase 1B was ratified as "disqualifying" to skip (decision :135), then the campaign closed via re-integration (:138) without ever producing the north-star doc. The "100p bar" the campaign said you cannot design without was never written down. | Any new campaign judging "is it great" still lacks the ratified taste yardstick; that gap is open, not closed. |
| 26 | corpus-wide | (absence) | **missing staleness banners** | `af27ca827` (05-01) added OBSOLETE banners to four `docs/specs/*` siblings when the luxury-menu infra was retired — but none of AVQ/AVDA/WF/V2 got one, and AVDA §16's status table still asserts artifacts exist. Anyone loading these four today reads a live-looking architecture. | Banner all four: "subject + instrument deleted 2026-04/05; superseded on evidence by AUTONOMOUS_VISUAL_ITERATION_HARDENING.md + DESIGN_PAGE decisions 2026-06-20/28." |

**Claims checked that SURVIVE (for balance):** NN/g parallel-vs-iterative 70%/18% (verified against Nielsen/Faber, IEEE Computer Feb 1996); 600-images-per-API-request (current docs, non-200k models); 8000×8000 max; images-before-text prompting; no-EXIF/metadata parsing; JPEG-artifact caution; sub-200px degradation; the $99/yr Apple Dev fee (HARD:239); the HARD plan's 0/6-prospective-catch finding, the regression-lock≠detection insight, and its entire built inventory (#1-#10, #12, #13 + Tier-1 sim), all content-verified at HEAD.

---

## Load-bearing claims, ranked by blast radius

**LB-1. "60% fully automated at 99% confidence / 80% automatable today" (AVDA:36-39, WF:10).**
The single most inheritable-looking number in the corpus, and the most rotten: its instrument is
deleted (row 1), its denominator is one 25-item checklist for a deleted page (row 13), and the
operator's own June measurement showed the automated lane catching 0/6 real bugs prospectively.
If new work sizes its human-review budget off this split, it will under-review by design. What
actually holds at HEAD: the HARD plan's per-mechanism taxonomy (invariants = prospective;
goldens = regression-lock only; device-only residue enumerated).

**LB-2. The autonomous VLM-judge quality gate (V2 entire; AVDA §§5,7,9 — "pairwise to 90+", "≥85 rubric pass").**
Never validated (program nuked pre-convergence, row 14), resting on an over-read citation (row 6)
and a misread one (row 7) — and then *actively ruled against* by the June campaign: "Do NOT run
the heavy RE-DERIVE path (VLM 'is-it-great' gate / tournament … correlate with regression-to-
the-mean; taste stays human, gates adjudicate correctness/coverage only)" (CAMP:138). A new
visual-review architecture that re-adopts VLM scoring as a *gate* contradicts the operator's own
ratified decision; the sanctioned role is advisory triage (HARD #10, "advisory, never CI-blocking").

**LB-3. Model-capability premise (AVDA §§1-2: Design Arena #1, generation→evaluation 60-80%).**
Both legs defective (rows 4, 5). Everything in AVDA's "Why This Works Now" is downstream of these
two. The honest current framing: Claude Opus 5 is top-3-ish on Design Arena, the transfer
correlation is unestablished, and the June evidence says judge-mode taste is mean-reverting.

**LB-4. Token/cost arithmetic (AVQ §8, AVDA §10/§13/§17, V2 §9).**
Every budget in the corpus — 440/screenshot, ~$0.05/eval, ~$0.70/pass, 226-iteration headroom —
is computed on a formula Anthropic has replaced (row 8) and a resolution tier that no longer
binds (row 9). Directionally the budgets still clear, but the high-res tier's ~3× image tokens is
a real new cost axis the corpus cannot see, and any new capture pipeline should target 2576 px,
not 1568.

**LB-5. "Context is NOT a constraint" (AVDA:64-67).**
Contradicted by its own sibling and by later fleet measurement (row 16). A new long-horizon
review loop that plans 90+ screenshot iterations on this premise dies mid-session in a 200K
window.

**LB-6. The June layer's sha citations (row 24).**
Low blast radius but insidious: the *healthy* documents cite pre-rebase shas that resolve locally
and exist on no branch — the exact "cited sha may not survive the land" trap. Verify by content
when inheriting from HARD.

---

## What the new work should inherit

- **Inherit:** the HARD plan's verified mechanism taxonomy + flake discipline + accepted-residual
  list (all live at HEAD: `tests/visual/layout-invariants.deck.spec.ts`, `layout-matchers.ts`,
  `header-geometry.spec.ts`, `focus-invariant.deck.spec.ts`, `cls.deck.spec.ts`,
  `safe-area-cdp.deck.spec.ts`, `scripts/visual/bless-rubric.mjs`, `scripts/ios-sim-verify/`);
  the CAMP decisions (taste stays human; gates adjudicate correctness/coverage; explicit-stance
  assignment for divergence); AVQ's prompt-engineering templates (the one part of the March layer
  with no rotten premise — but recompute its numbers per rows 8-11).
- **Do not inherit:** any percentage from LB-1, any threshold from LB-2, any capability claim from
  LB-3, any token/dollar figure from LB-4, and no path in AVDA §16's artifact table without an
  `ls` first.
- **Open items the corpus leaves:** the never-written Reso north-star taste yardstick (row 25);
  Tier-2 physical-device lane (hardware-gated, HARD:629); the never-recaptured reference-image
  set if comparative anchoring is wanted again (row 3).
