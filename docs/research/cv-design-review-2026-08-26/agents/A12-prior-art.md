# A12 — Prior Art: how agentic visual design-review systems actually work (as of 2026-08-26)

Scope: shipped products, OSS projects, and published research on agentic/automated **visual design review**.
Method: 29 web calls, primary sources preferred (vendor docs > vendor marketing > SEO comparison sites).
Every claim carries a URL. Vendor claims are labelled; user reports are labelled.

**Source-quality warning, stated up front.** A large fraction of 2026 search results for this topic are
SEO comparison farms (`qaskills.sh`, `crosscheck.cloud`, `bug0.com`, `testdino.com`, `mcp.directory`,
`benchlm.ai`) that paraphrase each other. Where a number below comes only from those, it is marked
**[secondary]** and should not be treated as measured. The load-bearing claims are all from primary
docs, GitHub repos, or peer-reviewed/arXiv papers.

---

## (i) System table

| System | What it reviews | Perception approach | Judging approach | Loop closure to code | Open/commercial | Maturity evidence |
|---|---|---|---|---|---|---|
| **Playwright MCP** (Microsoft) | Not a review system — the *substrate* most review agents run on | **Accessibility tree by default**; screenshots opt-in; `--caps=vision` adds coordinate mouse tools | None (no judge) | Agent-driven; `browser_take_screenshot` is annotated *"You can't perform actions based on the screenshot"* | Open (Apache), `@playwright/mcp` | 36.5k stars, 573 commits ([repo](https://github.com/microsoft/playwright-mcp)); official docs at [playwright.dev/mcp](https://playwright.dev/mcp/introduction) |
| **chrome-devtools-mcp** (Google Chrome DevTools team) | Runtime + perf + console, incl. **CLS/LCP/INP** — the only *deterministic visual-quality* metric in the field | CDP: perf traces, network, console w/ source-mapped stacks, screenshots, a11y | None (no judge) | Agent reads trace → edits code → re-traces | Open ([repo](https://github.com/ChromeDevTools/chrome-devtools-mcp)) | Official Google; [Chrome for Developers blog](https://developer.chrome.com/blog/chrome-devtools-mcp) |
| **OneRedOak `design-review`** | Front-end PR diffs, live | Playwright MCP; **screenshots at 1440 / 768 / 375** as evidence | 7-phase rubric, 4-level triage `[Blocker]/[High-Priority]/[Medium-Priority]/[Nitpick]` | **Report only** — PR comment; a human or a second agent applies fixes | Open | 3.9k stars / 565 forks ([dir](https://github.com/OneRedOak/claude-code-workflows/tree/main/design-review)) |
| **Anthropic `design-critique` skill** | Figma links, screenshots, or *written descriptions* | Screenshot/image, single pass | 5-part framework + severity table + 3 prioritised recs | None — critique artifact only | Open ([SKILL.md](https://github.com/anthropics/knowledge-work-plugins/blob/main/design/skills/design-critique/SKILL.md)) | ~3.7k installs [secondary] |
| **Anthropic Code Review** (not visual, but the best-evidenced review loop) | PR diffs | Text/code only | **Parallel specialist agents + a verification agent that tries to DISPROVE each finding before posting** | Ranked GitHub PR comments | Commercial (Team/Enterprise) | Launched **2026-03-09**; Anthropic internal: substantive findings on 16%→**54%** of PRs, **<1%** marked incorrect ([InfoQ](https://www.infoq.com/news/2026/04/claude-code-review/), [The New Stack](https://thenewstack.io/anthropic-launches-a-multi-agent-code-review-tool-for-claude-code/)) |
| **Claude Design** (Anthropic Labs) | Generates *live HTML*, not mockups | Live canvas; inline element comments; reads codebase for real tokens/components | Human-in-loop refinement (knobs, inline comments) | Hand-off to Claude Code | Commercial (Pro+) | Launched **2026-04-17**, research preview; practitioner notes instability + no pixel-precision ([review](https://justinmckelvey.com/blog/claude-design-review)) |
| **Figma Dev Mode MCP** | Design→code fidelity | **Structured design metadata**, explicitly *replacing* screenshots: *"Traditionally, AI tools relied on screenshots or API dumps — often resulting in imprecise code output… The MCP server eliminates this ambiguity"* | Not a judge — supplies ground truth (variables, component→file mapping via Code Connect) | Agent writes code against real tokens/components | Commercial (Figma seat) | Public beta **2025-06-04** ([Figma blog](https://www.figma.com/blog/introducing-figma-mcp-server/)) |
| **Applitools Eyes / Autonomous** | Rendered app states | Screenshot + DOM capture; **"Visual AI", not pixel diff** | Baseline diff w/ **match levels** (Strict / Layout / Ignore Colors / Dynamic); baseline keyed on app+test+browser+OS+viewport+branch | **Human approves; accept propagates** across tests/devices/browsers ("automated test maintenance") | Commercial | *Vendor-reported customer measurements*: Peloton 78% maintenance-time cut (130 h/mo), EVERSANA INTOUCH 65% regression-time cut ([blog, 2025-10-24](https://applitools.com/blog/test-maintenance-at-scale-visual-ai/)); *user reports*: "false failures on very little pixel deviations", "not cheap and generates unwanted noise sometimes" (G2/Capterra) |
| **Percy Visual Review Agent** (BrowserStack) | Rendered pages | Screenshot diff + AI classifier | Classifies each change **Irregular vs Valid**, smart bounding boxes, natural-language change summary | **Explicitly advisory**: *"This classification advises you. It does not approve or reject changes for you, so review every change before approving."* ([docs](https://www.browserstack.com/docs/percy/ai-agents/visual-review-agent/overview)) | Commercial (paid plans) | Launched **Oct 2025**; *marketing claim* 3× faster review, filters ~40% of changes ([SD Times](https://sdtimes.com/test/browserstack-adds-visual-review-agent-for-web-testing/)) — **absent from the product docs**. Docs state real limits: no AI diff >13,500px tall, unavailable on very large change sets, disabled when regions/sensitivity are set |
| **Chromatic** | Storybook stories (component-level) | Cross-browser pixel snapshots | Baseline diff + anti-flake layer (latency, animation, resource load, minor DOM churn) | **Human approves baseline in the PR**; TurboSnap uses the *bundler dependency graph* to snapshot only affected stories | Commercial | Free 5k snaps/mo, $149/mo for 35k; realistic $300–700/mo for 500 stories × 30 PRs/day; 90%+ snapshot reduction on 1000+-story Storybooks [secondary] |
| **Storybook 9 (`addon-a11y` + Vitest addon)** | Component stories | DOM, via **axe-core** | Deterministic WCAG rule set; `parameters.a11y.test` per story | Fails the test run; deep-links to the violating node | Open | [docs](https://storybook.js.org/docs/writing-tests/accessibility-testing); ceiling is measured — see §(iii) |
| **Stagehand / Browserbase** | Not review — control | **Chrome accessibility tree** with "hybrid trimming"; caching of `act/observe/extract` | None | n/a | Open SDK + commercial cloud | [repo](https://github.com/browserbase/stagehand); v4 claims 2× faster than Playwright, ~80% more token-efficient (vendor) |
| **Google Antigravity** | Agent's own UI work | Built-in Chrome; **screenshots + browser video recordings** as first-class "Artifacts" | Human reads the artifacts | Agent edits, then re-verifies; artifacts attach to the task | Commercial (free tier) | 2.0 launched **2026-05-19** at I/O; [Artifacts docs](https://antigravity.google/docs/artifacts/) |
| **v0 / v0.app (Vercel)** | Generated UI | Live preview + element-select | Human judgement, conversational | Direct code edit / PR / deploy | Commercial | Rebranded v0.app Jan 2026; 6M+ devs [secondary]. Structural flaw noted by reviewers: **each refinement iteration grows the context window, so cost penalises exactly the iterative loop the product exists for** |
| **designagent.dev** (Claude Code plugins) | Three *separate* commands | `/design-review` = **intent, not pixels** (PRD + research + Figma + analytics); `/design-qa` = screenshots running UI and **diffs vs the Figma frame / DESIGN.md**; `/tokens` = deterministic clustering + hardcoded-value drift | Severity-ranked drift report; DESIGN.md lints code rules (borders vs shadows, off-grid spacing, extra typefaces, over-cap weights); hardcode linter flags raw hex/px/ms, raw Tailwind palette utilities, literal font-family | Report + lint failures | Commercial plugins | All marked "New"; no adoption data ([site](https://designagent.dev/)) |
| **uisentinel** | Running web UI, for coding agents | **Deterministic**: contrast ratios, overflow px, touch targets, alignment, keyboard nav; **plus** model-based hierarchy/spec matching | JSON with exact measurements — *"3.1:1 needs 4.5:1"*, *"overflows by 45px on mobile"* | Explicit **validate → fix → re-validate → confirm** loop | Open | **8 stars** — immature, cited as a design pattern not as proven ([repo](https://github.com/mhjabreel/uisentinel)) |
| **proofshot** | Agent's UI work | `session.webm` video + screenshots + action timeline + server/browser console logs | **Human is the judge** — explicitly | Bundles proof onto the PR | Open | 853 stars ([repo](https://github.com/AmElmo/proofshot)) |
| **AgenticDRS** (Adobe Research) | Graphic designs | Multi-agent under a **meta-agent orchestrator** | Graph-matching-based in-context exemplar selection + prompt expansion; DRS-BENCH | Research only | Paper | arXiv 2508.10745, subm. 2025-08-14, rev **2026-03-12** |
| **PerceptUI** (Woven by Toyota) | UI screenshots, **persona-conditioned** | Screenshots (+ optional reference image) | Contrastive Reflection Fine-Tuning + reflective prompt evolution (symbolic gradients from failure analysis) | Research only | Paper | arXiv 2606.05697, **2026-06-04**; 74.25% avg / **44.30% order-consistent** on WiserUI-Bench; ρ=0.658 on LabintheWild |
| **Nighthawk / OwlEyes** (Monash et al.) | Rendered GUI screenshots | Purpose-trained CV, not an LLM | Detect + **localise** text overlap, component occlusion, missing image | Bug report w/ region | Open research | arXiv 2205.13945: **0.84 precision / 0.84 recall** detection, 0.59 AP / 0.60 AR localisation; found **151** previously-undetected issues in shipped Play/F-Droid apps, **75 confirmed or fixed** |

---

## (ii) Techniques that recur across the best systems

1. **Split the judgment by evidence type — countable vs perceptual — and never let one substrate do both.**
   The single most repeated architecture. Applitools: pixel/DOM diff + match levels for the countable,
   human for the rest. designagent: three separate commands (`/tokens` lint, `/design-qa` pixel diff,
   `/design-review` intent). uisentinel: deterministic contrast/overflow/touch-target numbers *plus* a
   model pass for hierarchy. The `mllm-ui-judge` experiment states it as a conclusion:
   **"count what is countable, look at what is visual, let humans decide taste."**

2. **Deterministic *localisation* under model *judgment*.** Every mature system turns a perceptual
   finding into a coordinate/DOM node before it reaches a human: Applitools traces a diff to a DOM
   element; Percy draws bounding boxes only around meaningful changes; Nighthawk localises the region
   (0.59 AP); UICrit's dataset is critiques **paired with bounding boxes**; Duan et al.'s pipeline
   spends half its stages just refining bounding boxes. A critique without a location is not
   actionable and does not survive triage.

3. **Ground the rubric in an on-disk artifact the repo owns.** OneRedOak puts design principles in
   `CLAUDE.md` + `design-principles-example.md`; designagent lints against `DESIGN.md`; Figma MCP
   supplies real variables and component→file mappings; Claude Design reads the codebase for actual
   brand tokens. Nobody who ships lets the model supply the standard from its own priors.

4. **A separate verification stage that tries to falsify each finding before it is surfaced.**
   Anthropic Code Review's verification agent is the best-evidenced instance (<1% incorrect findings
   at 54% PR coverage). Duan et al. built the same shape (a Validation module between generation and
   output). **Caveat with teeth:** Duan et al. report the validation step *"sometimes eliminated valid
   comments"* — the FP filter has its own FN rate, and nobody publishes it.

5. **Multi-viewport sweep as a fixed protocol, not a judgement call.** 1440 / 768 / 375 in OneRedOak;
   Chromatic snapshots per viewport; Applitools' Ultrafast Grid renders one capture across the matrix.
   The viewport set is part of the contract, so the agent cannot decide it "looked fine".

6. **Human owns the baseline/approval gate; the AI owns the triage.** Percy's docs are explicit that
   the classifier *advises* and never approves. Chromatic requires a human accept. proofshot's whole
   thesis is bundling evidence *for a human*. No shipped commercial system auto-accepts a visual change.

7. **Cost control by change-scoping, not by sampling.** TurboSnap uses the bundler dependency graph so
   only affected stories are snapshotted (90%+ reduction on large Storybooks). This is the pattern to
   copy for agentic review: derive the review set from the dependency graph of the diff, not from a
   heuristic or a token budget.

8. **Video/interaction artifacts, because static frames cannot see motion.** Antigravity records
   browser sessions as Artifacts; proofshot ships `session.webm` + a timeline. PerceptUI names this as
   its own limitation: *"screenshot-only evaluation cannot capture interactive, temporal usability issues."*

9. **Order-swap consistency as the *reported* metric, not an internal detail.** WiserUI-Bench reports
   "Consistent Accuracy" (correct under both orderings) as a headline alongside average accuracy,
   because the gap between them *is* the finding.

10. **"Problems over prescriptions."** OneRedOak states it verbatim: *"Instead of 'Change margin to
    16px', say 'The spacing feels inconsistent with adjacent elements.'"* Anthropic's design-critique
    skill mandates the same shape (explain why it matters, propose alternatives, acknowledge what works).
    Rationale: a prescription that is wrong is a false positive; a described problem that is wrong is
    still a conversation.

---

## (iii) Techniques tried and abandoned — with the reason

| Technique | Status | Why it was dropped / demoted |
|---|---|---|
| **Raw pixel diffing** | Abandoned by all three commercial vendors | Anti-aliasing, font rendering, sub-pixel shifts, dynamic content flood the queue. Replaced by perceptual matching + explicit match levels (Applitools), anti-flake layers (Chromatic), AI classification (Percy). |
| **Pixel-highlight overlays for review** | Replaced (Percy, Oct 2025) | Red-pixel noise made reviewers scan everything. Replaced by bounding boxes around *meaningful* changes + a natural-language summary of what changed. |
| **Coordinate/vision-based agent *control*** | Demoted to opt-in (`--caps=vision`) in Playwright MCP | *"Deterministic tool application. Avoids ambiguity common with screenshot-based approaches."* Docs: *"For most web applications, the default snapshot-based approach is more reliable and token-efficient."* Vision is now reserved for canvas, maps, image editors, charts, and custom widgets without ARIA. |
| **Screenshots as the design→code channel** | Explicitly replaced by Figma | *"Traditionally, AI tools relied on screenshots or API dumps — often resulting in imprecise code output, requiring developers to 'correct' token mismatches… The MCP server eliminates this ambiguity by providing explicit design metadata."* |
| **Absolute 1–5 MLLM scoring of UIs** | Failed in the one published end-to-end trial | `mllm-ui-judge`: ten screenshots rated 1–5 **clustered between 3.5 and 4.0** — no discriminative power. Range compression is the failure mode, and it is invisible if you only look at mean-vs-human (judge 3.65 vs human 3.82). |
| **Rubric/pointwise scoring generally** | Known-broken without permutation | Rubric evaluation is structurally a multiple-choice task and inherits its position bias: **top-1 ranking reversals in 16–39% of cases** purely from reordering the rubric; some judges are first-biased and some last-biased, so a fixed order cannot be corrected for. Mitigation that works: random permutation over 3–5 orderings (≈⅔ of the K=10 benefit); *exact* score–position balancing "buys essentially nothing". |
| **Naked pairwise comparison (no order swap)** | Insufficient — this is the correction most relevant to us | WiserUI-Bench: frontier MLLMs sit **barely above the 50% chance line** on average accuracy for picking the real A/B-test winner, and **order-invariant Consistent Accuracy is ~30–37% against a 25% chance baseline**, with a strong bias toward the *second* image. `mllm-ui-judge` saw the verdict flip on **2 of 3** order-swapped pairs of *identical* screenshots. Pairwise beats pointwise on calibration, but only the swap-surviving verdict is a verdict. |
| **Intrinsic iterative self-refinement (critique your own output, repeat)** | Abandoned in the literature | Huang et al. (ICLR 2024) and Kamoi et al. (TACL 2024): intrinsic self-correction without an external signal often fails to improve and *degrades* performance. The field moved to generator/verifier separation and tool-grounded critique. |
| **A single MLLM judge as the fitness signal in a closed improvement loop** | Failed in trial | `mllm-ui-judge` ran closed-loop mutation against two named defects (generic CTA labels, card-wall layouts). **The judge failed to register code-level improvements that deterministic parsing detected**; structural layout fixes stayed hard; the loop did not converge. |
| **Automated a11y as the accessibility answer** | Bounded, not abandoned | Deque's own study (2,000+ audits, 13,000+ pages, ~300,000 issues, 2021-03-10) puts automated coverage at **57%** — better than the 20–30% folklore, and still a hard ceiling. axe-core deliberately trades recall for near-zero false positives. |
| **Full-page snapshotting as the default unit** | Superseded | Component-level stories (Chromatic/Storybook) plus dependency-graph scoping (TurboSnap) — full-page diffs are expensive and attribute badly. |
| **Iteration-as-product without iteration-priced cost** | Structural failure in v0 | Reviewers note every refinement grows the context window and pushes usage into higher tiers — "the platform can end up financially penalising the iterative visual exploration that's supposed to be the whole point". |

---

## (b) The load-bearing question: does Playwright MCP's a11y-tree rationale transfer to design *review*?

**The stated rationale, verbatim, from primary sources:**

- README/docs: *"Deterministic tool application. Avoids ambiguity common with screenshot-based approaches."*
- *"Uses Playwright's accessibility tree, not pixel-based input."* / *"LLM-friendly. No vision models needed, operates purely on structured data."*
- *"~200-400 tokens per snapshot vs thousands for DOM/screenshots"* ([playwright.dev/mcp](https://playwright.dev/mcp/introduction))
- Vision-mode page: *"For most web applications, the default snapshot-based approach is more reliable and token-efficient. Use vision mode only when the accessibility tree doesn't cover your use case."*

**Assessment: the rationale does NOT transfer, and it was never claimed to.** Three independent
observations, all from primary sources:

1. **Every clause of the rationale is about *actuation*, not *perception*.** "Deterministic tool
   application", "unique ref for deterministic interaction", "no coordinate guessing" — these answer
   the question *which element do I click*. Design review asks *does this look right*, and has no
   actuation step at all. `browser_take_screenshot`'s own tool annotation makes the boundary explicit:
   *"You can't perform actions based on the screenshot"* — a statement about actions, silent about
   judgment.

2. **The Playwright team never extended the claim to visual verification.** The `/mcp/vision-mode`
   page contains **no** guidance on visual verification, design checking, or visual regression; its
   worked examples are canvas drawing and clicking unlabeled icons. The decision table it ships is
   "which mode do I use to *interact* with X", not "which mode do I use to *evaluate* X". Reading the
   a11y-tree preference as a claim about design review is an extrapolation the source does not make.

3. **The token argument inverts once the pixels are the subject.** The 200–400-token snapshot is cheap
   *because it discards* exactly the information design review is about. An accessibility tree cannot
   express: contrast, spacing rhythm, alignment, optical weight, crowding, overflow, z-order occlusion,
   or motion. Nighthawk exists precisely because these defects are invisible to structural
   representations — text overlap and component occlusion produce a perfectly valid a11y tree.

**But the sharp version of the answer is not "use screenshots instead" — it is a role split:**

| Question the review asks | Right substrate | Evidence |
|---|---|---|
| Is the *semantic structure* right (heading order, roles, labels, focus order, landmarks)? | a11y tree / axe-core | Deterministic, 57% automated a11y coverage, near-zero FP by design |
| Is a *measurable geometric* property violated (contrast ratio, overflow px, touch-target size, off-grid spacing, hardcoded token)? | **DOM + computed styles**, not pixels and not the a11y tree | uisentinel emits `3.1:1 needs 4.5:1`, `overflows by 45px on mobile`; designagent's `/tokens` + hardcode linter; Becker's practitioner account solved CSS bugs by *querying computed styles*, not by looking |
| Did the rendered result *shift/jank* over time? | CDP performance trace (CLS/INP) | chrome-devtools-mcp — a deterministic number for a purely visual defect |
| Does it *look* right — hierarchy, rhythm, balance, crowding, taste? | **Pixels. There is no substitute.** | WiserUI-Bench: layout/container structure is the hardest category *even for vision models*; a11y tree cannot represent it at all |
| *Where* is the defect, so a fix can be written? | Map pixels → DOM node → source file | Applitools DOM attribution; UICrit's bbox-paired critiques; Figma Code Connect's component→file path |

**The transferable design rule:** the a11y tree is the right substrate for *navigation, actuation,
attribution, and specification-conformance*; the screenshot is the only substrate for *perceptual
judgment*; and computed styles are a third substrate that beats both for anything with a number.
A design-review agent that uses only one of the three has a structural blind spot, and the blind
spot is silent — it produces a confident clean bill of health.

---

## (c) Loop structures, and what converges

| Loop | Who runs it | Evidence on convergence |
|---|---|---|
| **Single-pass critique** | Anthropic `design-critique` skill; OneRedOak (7 phases, one pass) | The dominant shipped shape. No published convergence claim — because there is no second pass. |
| **Single-pass + adversarial verification of findings** | Anthropic Code Review (2026-03-09) | **Best-evidenced loop in the field**: <1% of findings marked incorrect while raising coverage 16%→54% of PRs. Cost: Duan et al. observed the same-shaped validation stage "sometimes eliminated valid comments" — an unmeasured FN rate. |
| **Iterative refine-until-converged (intrinsic)** | Self-Refine-style | **Does not converge; degrades.** Huang et al. ICLR 2024; Kamoi et al. TACL 2024. `mllm-ui-judge`'s closed mutation loop failed to converge because the judge could not perceive its own improvements. |
| **Iterative refine with an *external/structural* signal** | Duan et al. 2412.16829 (bbox refinement until the LLM confirms or max-iters); uisentinel's validate→fix→re-validate | **Converges on the grounded sub-problem.** Bounding-box IoU 0.120→0.357 for Gemini-1.5-pro (~3×) and 0.233→0.345 for GPT-4o (+48%). Closed **22%** of the gap to human experts on comment quality — i.e. iteration bought real ground on *localisation*, not on *taste*. |
| **Pairwise tournament / Bradley-Terry** | Design Arena, WebDev Arena (human voters, Elo from Bradley-Terry, blind + anonymised to kill brand bias); WiserUI-Bench as the automated analogue | Converges *statistically* with enough votes, and is the industry standard for ranking design quality — but with **model** judges the order-invariant accuracy is near chance (§iii). Pairwise is the right *frame*; the judge is the weak link, not the frame. |
| **Human-in-the-loop gate** | Chromatic, Percy, Applitools, proofshot, Antigravity | The only structure with production evidence at scale. Percy's docs: the AI classification *"does not approve or reject changes for you"*. Every commercial vendor puts a human at the accept. |

**Practitioner data point on iteration count** (first-hand, Luca Becker, 2025-10-20): giving the agent
live DOM + computed-style access took UI-fix tasks from *"10-15 frustrating iterations"* to *"2-3"*,
raising success from ~50% to ~75%. That is external-signal iteration, and it is the only first-hand
convergence number found.

---

## (d) Reported failure modes in production

1. **Reviewer habituation / accept-fatigue is the #1 killer, and it is a *rate* threshold, not a vibe.**
   *"Once engineers routinely click 'accept' because a visual suite cries wolf on every pull request,
   the nominal amount of visual coverage stops mattering."* The AI-code-review literature puts the
   habituation point near **~20% false positives** — above that the tool loses credibility regardless
   of its catch rate. Concrete comparison [secondary]: one benchmark run found ~2 FPs for CodeRabbit
   vs ~11 for Greptile; Greptile users on large repos report **30–50%** of findings need manual triage.
   CR-Bench (2026) documents low signal-to-noise → fatigue → abandonment as a chain.

2. **False positives cluster in specific file/element classes.** Across three AI reviewers, config,
   test infra and IaC files produced **30–42%** of all false positives — agents tuned for app code
   misfire on everything else. The visual analogue is dynamic content: dates, emails, carousels,
   animations, third-party embeds. This is why every vendor ships a suppression mechanism (Applitools
   Dynamic/Regions-Only, Percy Intelli-ignore, Chromatic Flake Filter).

3. **Vendor AI still emits pixel-level false failures.** User reports (G2/Capterra) on Applitools:
   *"at times we have false failures on very little pixel deviations"*, *"not cheap and generates
   unwanted noise sometimes"*, plus cloud dependency and setup learning curve. Note the shape: the
   vendor's *own* published customer wins (78% maintenance-time cut at Peloton) and these user
   complaints are both true — Visual AI moved the FP rate a lot and did not zero it.

4. **Silent blindness — the agent reports success without ever perceiving.** proofshot's framing:
   *"AI coding agents build UI features blind. They write code but can't verify the result looks right."*
   The broader pattern reported by practitioners: agents that "monitor" by HTTP status, "QA" by parsing
   DOM attributes, "analyse competitors" from meta descriptions — technically functional, practically
   blind. This is the most dangerous failure mode for us because its output is a **clean report**.

5. **Judge instability under reordering.** Documented three independent times: 16–39% top-1 reversals
   from rubric reordering; 2-of-3 verdict flips on order-swapped identical screenshots; WiserUI-Bench's
   average-vs-consistent accuracy gap and second-image bias.

6. **Cost, and cost that scales the wrong way.** Chromatic realistically $300–700/mo for a 500-story
   design system at 30 PRs/day even with TurboSnap [secondary]; Percy's AI diff simply switches off
   above 13,500px vertical or on very large change sets; v0's iteration cost grows with the context
   window. For an agentic loop, screenshots are the expensive token: vision tokens are materially
   pricier than text, and a 3-viewport × N-state sweep multiplies fast.

7. **Human ground truth is itself noisy — which caps the achievable agreement.** Duan et al. report
   human inter-rater Fleiss κ of **0.22** (comment quality) and **0.29** (ranking). `mllm-ui-judge`'s
   five human raters spanned **2.4–5.0** on the same components. Any target like "match human
   reviewers" is aiming at a distribution ~as wide as the effect being measured.

---

## Adversarial pass: the strongest published account of an agentic visual-review system failing

**The account:** `github.com/CAPTH69/mllm-ui-judge` — *"Testing whether multimodal LLMs can judge and
improve AI-generated UI components."* It is the only published end-to-end attempt found that ran the
full architecture we are building (MLLM judge → fitness signal → closed improvement loop) and reported
the result honestly. Generator GPT-5.4, judge Claude-4.5-Sonnet, 10 component instances, 5 human raters.

**The four measured failures, in order of how badly they hit our design:**

| Arm tried | Result |
|---|---|
| Absolute 1–5 scoring | Scores **clustered 3.5–4.0** — no discrimination between good and bad UIs |
| Pairwise with order swap | **Position bias flipped the verdict in 2 of 3 pairs** on *identical* screenshots |
| Yes/no design checklist | Better feedback, but **"remained unstable on perceptual checks"** |
| Deterministic code audit | **Beat the vision model** on countable facts (imports, button presence, generic-CTA phrase counts); could not perceive layout |
| Closed-loop mutation on two named defects | **The judge failed to register code-level improvements that deterministic parsing detected.** Structural layout fixes stayed hard. The loop did not converge. |

**Mechanism of failure — the generalisable part.** The judge was used as the *fitness function* of an
optimisation loop while being (a) low-variance, (b) order-dependent, and (c) partially blind to the
axis being optimised. Each property alone is survivable; together they are fatal, because a fitness
function that cannot see the improvement gradient turns iteration into a random walk that *reports
progress*. Note the trap in the aggregate statistic: judge mean 3.65 vs human mean 3.82 — a 0.17 gap
that reads like near-human agreement and completely conceals a judge with no discriminative range.
**Never validate a design judge on mean agreement; validate on discrimination and on swap-consistency.**

The project's own conclusion is the one-line design rule:
> **"count what is countable, look at what is visual, let humans decide taste."**

**Honest limits of this account:** n=10 components, 5 raters, no publication date, no peer review, a
small personal repo. It is *directional*, not statistically powerful. It is the strongest account
available because it is corroborated on every axis by better-powered sources — WiserUI-Bench's
near-chance order-invariant accuracy (300 real A/B pairs, ACL 2026), the 16–39% rubric-reversal
finding (6 models, 3 families), and the ICLR/TACL self-correction results.

**Corroborating adversarial finding I did not expect.** WiserUI-Bench's ground truth is *behavioural*
(real A/B-test winners), not aesthetic — and that is where models are worst: average accuracy barely
above chance, container/layout-structure changes hardest, interpretation recall ~67–68% even for
GPT-5.1 and Claude 4.5 Sonnet. Meanwhile a separate 2026 study found models reach **almost perfect
agreement (κ ≥ 0.81)** with experts on *Aesthetics* and *Design Quality*, but **systematically
overestimate** Usability, Learnability and Efficiency by +1.00 to +3.00 points. Read together:
**an MLLM design judge is credible on "is it pretty" and not credible on "does it work better for a
user."** A constitution written in behavioural language ("reduces friction", "improves discoverability")
is asking the judge the question it is worst at; a constitution written in perceptual language
("contrast, rhythm, alignment, crowding") is asking the one it is best at.

---

## What this axis did NOT find (blockers / honest gaps)

- **No public postmortem of a named company abandoning an *agentic* visual design-review system.**
  Searched four ways. What exists is the *component* evidence: teams abandoning visual regression over
  false positives (generic, well-attested), and one published failed research loop. Treat "nobody has
  published a big abandonment" as absence-of-evidence, not evidence-of-absence — the tooling is <18
  months old.
- **No published cost figure for an agentic design review run** (tokens or dollars per PR). Vendor
  snapshot pricing exists; agent-loop cost does not.
- **No system found that runs a pairwise *tournament* between generated design variants with an
  automated judge in production.** Design Arena and WebDev Arena do pairwise Bradley-Terry with
  *human* voters. Our V2's pairwise-with-parallel-variants shape has no shipped precedent — the
  closest published analogue is WiserUI-Bench, which is a benchmark, and it says the automated judge
  is the weak link.
- **Applitools' root-cause-analysis (visual diff → DOM/CSS attribution) is referenced but not
  technically documented** in the pages reachable without an account. The mechanism we most want to
  copy is the one they publish least about.
- **`--image-responses auto`** in Playwright MCP is undocumented as to what "auto" decides. If we run
  on Playwright MCP this silently controls whether the reviewer sees pixels at all.

---

## Sources

Primary — tooling
- https://github.com/microsoft/playwright-mcp
- https://playwright.dev/mcp/introduction · https://playwright.dev/mcp/vision-mode · https://playwright.dev/mcp/capabilities
- https://github.com/ChromeDevTools/chrome-devtools-mcp · https://developer.chrome.com/blog/chrome-devtools-mcp
- https://github.com/OneRedOak/claude-code-workflows/tree/main/design-review
- https://github.com/anthropics/knowledge-work-plugins/blob/main/design/skills/design-critique/SKILL.md
- https://www.figma.com/blog/introducing-figma-mcp-server/ (public beta 2025-06-04)
- https://applitools.com/docs/eyes/sdks/storybook/core-concepts
- https://www.browserstack.com/docs/percy/ai-agents/visual-review-agent/overview
- https://storybook.js.org/docs/writing-tests/accessibility-testing
- https://github.com/browserbase/stagehand
- https://antigravity.google/docs/artifacts/
- https://designagent.dev/
- https://github.com/mhjabreel/uisentinel · https://github.com/AmElmo/proofshot

Vendor marketing / press (claims, not measurements)
- https://applitools.com/blog/test-maintenance-at-scale-visual-ai/ (2025-10-24)
- https://sdtimes.com/test/browserstack-adds-visual-review-agent-for-web-testing/ (Oct 2025)
- https://www.deque.com/blog/automated-testing-study-identifies-57-percent-of-digital-accessibility-issues/ (2021-03-10)

Research
- https://github.com/CAPTH69/mllm-ui-judge — the failed closed-loop judge experiment
- https://arxiv.org/html/2505.05026v5 — WiserUI-Bench (ACL 2026) · https://github.com/jeochris/wiserui-bench
- https://arxiv.org/html/2606.05697 — PerceptUI (Woven by Toyota, 2026-06-04)
- https://arxiv.org/abs/2508.10745 — AgenticDRS (Adobe Research, rev 2026-03-12)
- https://arxiv.org/html/2602.02219v2 — position bias in rubric-based LLM-as-a-judge (2026-06-24)
- https://arxiv.org/html/2412.16829v1 — visual prompting + iterative refinement for design critique (Berkeley + Google DeepMind, 2024-12-22)
- https://dl.acm.org/doi/10.1145/3654777.3676381 — UICrit (UIST '24)
- https://arxiv.org/abs/2205.13945 — Nighthawk (0.84 P / 0.84 R)
- https://arxiv.org/pdf/2310.01798 — LLMs Cannot Self-Correct Reasoning Yet (ICLR 2024)
- https://link.springer.com/chapter/10.1007/978-3-032-30549-7_12 — MLLMs vs expert ratings in mobile UI usability

Practitioner (first-hand)
- https://luca-becker.me/blog/level-up-agentic-coding-mcp-2-playwright/ (2025-10-20)
- https://justinmckelvey.com/blog/claude-design-review (Claude Design, launched 2026-04-17)

Press / analyst on Anthropic Code Review
- https://www.infoq.com/news/2026/04/claude-code-review/ · https://thenewstack.io/anthropic-launches-a-multi-agent-code-review-tool-for-claude-code/

Secondary (SEO comparison sites — treat numbers as unverified)
- https://bug0.com/knowledge-base/visual-regression-testing-tools · https://qaskills.sh/blog/chromatic-turbosnap-storybook-guide · https://crosscheck.cloud/blogs/best-visual-regression-testing-tools-2026/ · https://notes.designarena.ai/methodology/ (403 on fetch; content via search summary only)
