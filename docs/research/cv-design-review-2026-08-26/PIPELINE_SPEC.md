# PIPELINE_SPEC — the one executable design-review pipeline

**Status:** ratified reconciliation of the thirteen stage designs in `pipeline/P1..P13-*.md`,
**survived two adversarial reviews on 2026-08-26 and was cut by them from thirteen stages to five.**
**Date:** 2026-08-26 · **Substrate:** `README.md` (the measured bench) + `agents/A1..A15`.
**Supersedes** the thirteen stage specs *wherever this document rules against them*, and only there.
Each stage spec remains the authority on its own internals; this document owns the **seams**, the
**contradictions**, and the **ceiling**.

🚨 **Read §2A before trusting any number in a `P*` stage spec.** Two reviewers attacked this document
against the machine rather than against its prose. Most of what they found was true: the
false-positive bound was computed on the wrong denominator (**3/8 = 37.5 %**, not 3/13 = 23.1 %), one
promotion path silently pierced the isolation §0.1 calls mechanical, and **seven of thirteen stages
could not name the number they improve.** §2A records every ruling — conceded, partially conceded,
and refuted — so no objection here returns without new evidence.

**Reading order for a builder:** §0 (what the stages are) → §1 (the contracts between them) → **§6
(build this first — and note the `spec` column: nothing may be built from a `PROSE` row)** → §10 (the
close) → §2 and §2A only when a stage spec disagrees with a sibling or with a measurement.

---

## 0. The pipeline

### 0.1 The sequence, one line each

`dr` is one binary. Every stage is a subcommand over one run directory. Stages 1–3 share **one
browser process and one CDP session** — that boundary is fixed by the CDP handle, not by taste
(P3 §1.1 exits `4` on a closed session; a `CDPSession` cannot cross an OS process).

| # | Stage | Subcommand | Runs where | One-line job |
|---|---|---|---|---|
| **S0** | **SURFACE** | `dr surface` | repo, no browser | Enumerate the `(route × auth × data-state × viewport × theme)` universe from the filesystem, and the named states nobody built. This is the **denominator**; without it no coverage claim means anything. |
| **S1** | **CAPTURE** | `dr capture` | browser (proc A) | Pin the instrument, drive readiness, freeze motion, write archival masters + a manifest that states — as computed fields — exactly which derived image is safe to send and what it costs. |
| **S1b** | **INK-PROBE** | (phase of `dr capture`) | browser (proc A) | Differential-render the ranked ≤40 candidates (`visibility:hidden` + re-clip) → `inkmask.json`. **Moved here from P4** (§2 C24): it needs a live page, and P4 must stay file-in/file-out. |
| **S2** | **EXTRACT** | `dr extract` | browser (proc A) | One `DOMSnapshot.captureSnapshot` (32.7 ms) + one AX tree (26.7 ms) → an ~854-token fact-pack of **values** and an on-disk per-node layout table. Emits **abstentions**, which are the vision layer's job queue. |
| **S3** | **SCREEN** | `dr screen` | files only, parallel | Every question with a number in the answer: G/T/K/A/O rule families + the NumPy cross-check arms. Emits a **closed census** and three-valued verdicts. Its most valuable output is `INDETERMINATE`. |
| **S4** | **ROUTE** | `dr route` | files only | Decide which of the residue earns a model call, collapse abstentions **by class**, mint crop requests, and write the block ledger. Never opens a browser. |
| **S5** | **DECOMPOSE** | `dr decompose` | browser (proc A, re-clip) | Cut the crops S4 asked for, from the *same pass*, inside the lossless envelope, each carrying a caption with its own prohibition and a **region label**. Bounded, not exhaustive (§2 C2). |
| **S6** | **JUDGE** | `dr judge` | network only | Compose and issue the model requests. Owns **blindness**, because blindness is a property of a request. Pass 1 gestalt is blind of facts *and* verdicts; pass 2 reconciles against values; crop and adjudicate calls carry the fact-pack. |
| **S7** | **STATES/MOTION** | `dr states` | browser (proc B) | Enumerate the interaction/stress/theme state space from the page's own vocabulary; assert motion from the animation model rather than watching it; hand S1 a small list of named cells. |
| **S8** | **ARBITRATE** | `dr arbitrate` | files only | Dedup by a key that spans the *claim*, subtract the control, promote a model finding to `asserted` only via an **executed falsifiable predicate**, compute severity, order by actionability. Never deletes. |
| **S9** | **ATTRIBUTE** | `dr attribute` | dev server | Resolve a finding to a `file:line` write target through the fiber owner stack + Next's own source-map resolver. **The only stage whose output is a write target.** Never guesses a path. |
| **S10** | **LABEL** | `dr label` | files only | Render the `UNREVIEWED` block from `surface.json` + the run's coverage, and veto any report carrying a numeric aesthetic score. Detects nothing. |
| **S11** | **EVAL** | `dr eval` | offline | Grade the *instrument* against a known-answer corpus. The only writer of `.pipeline-pin`. |
| **S12** | **REDTEAM** | `dr redteam` | files only | Execute the seven cross-stage assertions over a completed run. Advisory; never gates. |
| **RT** | **RUNTIME** | `dr` itself | the top frame | Not a stage — the **composition**: the cell key, the journal, the lanes, the budget, the exit code, and the `coverage` field. It owns *scheduling* and asserts only about its own completeness. |

`dr review <app>` is exactly the composition S0→S10. There is no code path reachable only through
`review`. **A stage that cannot run alone against stored inputs cannot be debugged.**

🚨 **The table above is the full DESIGN inventory. It is no longer the BUILD inventory.** After the
2026-08-26 value attack (§2A.2), the **core pipeline is five stages — S0 · S1 · S2 · S3 · S6-blind** —
and everything else is an optional tier that must beat that spine on a stated number before it is
built. **S5 DECOMPOSE and S4's five-trigger machinery are cut; S7 and S1b are deferred**, each with
a revival condition in §6 Tier 3. The design of each remains correct and is left in place, because a
stage that is cut for want of *evidence* is a different thing from one that is cut for being *wrong*,
and the evidence may arrive. **Read §6 before building anything from §1.**

**RT is the only thing that computes the exit code, and it never reads `judge/` or the `advisory`
rung.** That isolation is the mechanical enforcement of the June 2026 ruling: a future edit wiring a
judgement finding into an exit code has to *delete* it, which is a reviewable diff rather than a
drift.

🚨 **That sentence was FALSE when written, and the diff that broke it was in this same document**
(attack ruling A1.U5, CONCEDED). §1.9's Route C let a model finding reach S8's `asserted` set, and
C17 gates on that set — so the gate did read judgement output, laundered through arbitration. **An
isolation a sibling section quietly pierces is worse than no isolation, because it is defended.**
Route C is deleted (D18); `advisory` is now terminal with no promotion path by any route, and the
paragraph above is true of the design rather than of its intention. **The general lesson, which
applies to every "mechanically enforced" claim in this document: an isolation is only real if you can
name the code path that would have to change to break it — and then check that no other path already
does.**

### 0.2 Numbering reconciliation — read this before any cross-reference

Every stage spec invented its own numbers for its neighbours, and none of them agree. This table is
the only valid map. A reference inside a `Pn` file means what its **role** says, never its number.

| This spec | Stage file | Called elsewhere |
|---|---|---|
| S0 SURFACE | P13 | "phase A", `cv-gap enumerate` |
| S1 CAPTURE | P1 | P2's "P1", P3's "P2-CAPTURE", P4's "P2", P7's "P1", P9's "P1" |
| S2 EXTRACT | P3 | P2's "P0 FACTS", P4's "P2 snapshot", P7's "P2 extract" |
| S3 SCREEN | P4 (+ P3's rules) | P2's "findings_dom/xcheck", P5's "P3/P4 SCREEN", P3's "P5-XCHECK" |
| S4 ROUTE | P5 | P2's "P4 ADJUDICATE" partly, P4's "judge_queue" |
| S5 DECOMPOSE | P2 | P4's "crops", P5's "clip_request", P3's "P4-CROP" |
| S6 JUDGE | P6 | P2's "P3 JUDGE", P3's "P6-JUDGE", P5's "the model call", P7's "P5" |
| S7 STATES | P9 | P1's "P5 motion", P4's "a motion stage" |
| S8 ARBITRATE | P7 | P2's "P4 ADJUDICATE", P4's "P7" |
| S9 ATTRIBUTE | P8 | P4's "P7 ATTRIBUTE", P6's "UNOWNED", P7's "P2 extract" ← **all stale, see §2 C15** |
| S10 LABEL | P13 | "phase B", `cv-gap label` |
| S11 EVAL | P10 | P5's "P7 EVAL", P4's "P7" in its FP table |
| S12 REDTEAM | P12 | — |
| **RT RUNTIME** | **P11** | *unnamed by every sibling* — P2's "the caller", P5's "the agent", P9's "P5 holds the ledger" |

### 0.3 The three substrates, and the line nothing may cross

| Substrate | Answers | Never ask it |
|---|---|---|
| Computed styles / CDP box model | every question with a number in the answer | whether it looks good |
| Accessibility tree | semantic conformance, element **identity**, the name a human would use | anything perceptual, and anything about source structure |
| Pixels (frontier VLM) | hierarchy, grouping, "does this make sense", whether a render betrays correct styles | **any number** |

> **The judge is forbidden to opine below the perceptual threshold, and SCREEN is forbidden to opine
> above it.** A pipeline that lets either cross re-creates the failure the other was hired to prevent.

Governing rule, from A4 and confirmed by the bench: **the grounder supplies identity, the DOM
supplies geometry.** No distance is ever computed from a box a model drew.

---

## 1. The contract chain

One run directory is the API. Nothing is written outside it, including temp files.

```
.dr/runs/<runid>/
  run.json  profiles.json  surface.json  journal.jsonl  blocks.json  degradation.json
  cells/<route-slug>/<w>x<h>.<theme>[.<state>]/
      manifest.json  masters/  read/  crops/                  # S1
      facts/{domsnapshot,layout,inkmask}.json  facts.json     # S1b, S2
      screen.json                                             # S3
      route-plan.json  clip/                                  # S4
      plan.json  crops/cNN.png                                # S5
      judge/{gestalt.blind.json,<call>.request.json,<call>.response.json}   # S6
      states/  frames/  findings/{states,motion,motion-frames}.json         # S7
      arbitrated/{report.json,report.md,arbitration.jsonl,control.diff.json} # S8
      attribution.json                                         # S9
  report.json  report.md  coverage.json  cost.json  control/
```

### 1.0 → S0 · repo → `surface.json` + `profiles.json`

**In:** repo root, app name. No browser, no network.
**Out (a) `surface.json`** — the coverage denominator: `routes[] {path, file, dynamic, auth,
states_declared, states_absent, inherits_from, task}` · `axes {viewport[], theme[], data[]}` ·
`tuples_total` · `tuples_capturable_without_a_human`. The two totals are separate on purpose; their
**ratio** is the number that tells the operator how much of the product has never been looked at.
**Out (b) `profiles.json`** — *new, and mandatory* (§2 C11). Per app:

```jsonc
{ "app": "reso-management-app",
  "engines": [ {"name":"panda","source":"styled-system/tokens/index.mjs","sha":"…","coverage":0.94},
               {"name":"tailwind4","source":null,"sha":null,"coverage":0.0,
                "token_map":"ABSENT",             // ← measured, see the ruling below
                "reason":"no @theme block in the app-shell CSS entry"} ],
  "precedence": ["panda","tailwind4"],       // REQUIRED when engines.length > 1, else refuse
  "class_inverter": "panda+tailwind-literal",
  "react":  {"declared":"19.2.4", "installed":"19.2.8", "resolved_from":"node_modules"},
  "next":   {"declared":"16.2.6", "installed":"16.3.0", "resolved_from":"node_modules"},
  "frame_api_fields": ["line1","column1"],
  "intent": {"source":["docs/design-system/CONSTRAINTS.md","docs/design-system/VOICE_AND_CONTENT.md"],
             "sha256":"…"} }
```

🚨 **`profiles.json` reads `node_modules`, never `package.json`, and it records both.** Measured
2026-08-26: `reso-management-app` declares `next 16.2.6` / `react 19.2.4` and has **16.3.0 / 19.2.8**
installed; `reso-landing-app` declares `react ^18` and has 18.3.1. A range specifier is not a
version, and every mechanism this pipeline keys on — `_debugSource`'s existence, the frame API's
field names, `jsxDEV`'s arity — is a property of the **bytes that execute**. The declared string is
recorded only so a mismatch is visible; no stage may branch on it. *(Attack ruling A1.7 — the spec's
own example carried the declared version and the two disagree today.)*

🚨 **A `token_map: "ABSENT"` engine is a first-class state, and the spec previously could not express
it.** Measured 2026-08-26 on `reso-management-app`: `grep -c '@theme' src/app/globals.css` = **0**,
and the only `@theme` blocks in the tree sit in `src/app/(vt-reference)/globals.css` and two
component files — a reference surface, not the app shell. So the second engine in the two-engine
precedence problem **has no extractable token map at all**, and C11's headline consequence ("a colour
legal under Panda and absent from the Tailwind `@theme` layer") **cannot occur as described**: there
is no Tailwind layer to be absent from. The real state is worse and simpler — Tailwind 4 is in the
PostCSS chain (`postcss.config.cjs`: `@tailwindcss/postcss` then `@pandacss/dev/postcss`, confirmed)
emitting utilities from **no declared token source**, so every Tailwind-authored colour is
unattributable to a token by construction. **Ruling: `token_map: ABSENT` forces the K-family to
`INDETERMINATE` with reason `engine-has-no-token-source` for every subject whose winning declaration
came from that engine** — not `FAIL`, and not a silent pass. The `coverage: 0.61` in the original
example was a number for a file that does not contain the construct it was measured over, and is
withdrawn.

**No stage takes a per-app premise from prose** — *and after this attack, not from a hand-written
JSON example either.* A profile with >1 engine and no `precedence` is a refusal, not a default; a
profile naming a `source` path is invalid until `dr surface` has **opened that path and found the
construct**, which is now an assertion at profile-generation time rather than a comment.

**Absent-state ledger** is part of `surface.json` and it is a `find`, not a vision task. **It carries
its denominator's scope in the same sentence, always** (attack ruling A1.5): measured
2026-08-26, `reso-management-app` has **0 `loading.tsx`** against **16 `page.tsx` under
`src/app/(app)`** and **0 against 105 `page.tsx` across all of `src/`**. The numerator is zero at
both scopes — the finding is *stronger* than the spec claimed, not weaker — but §5.1's *"recall 1.00,
0 FP by construction"* was written over the `(app)` denominator covering **15 %** of the app's
routes, and never said so. A recall figure whose denominator is unnamed is a rate over an
unfalsifiable population, which is the exact defect §4.2 item 2 exists to kill. **Every count this
stage emits names its glob.** Zero false positives by construction, and **no stage that begins at a
URL can produce it.**

**One more `find` lives here, moved in from S7** (attack ruling A2.10): `prefers-reduced-motion`
occurrences per app. Measured — `reso-management-app` **338**, `reso-web-app` **0**,
`reso-landing-app` **0**, and the landing app is the `framer-motion` one. That is a blocker-grade
finding produced by a grep, and it does not need the S7 stage that was going to carry it.

### 1.1 → S1 · `surface.json` (+ `states/<cell>.js` from S7) → `manifest.json` + masters

**In:** target URL/`file://`, viewport set (`auto` = the page's own occupied `@media (width)`
branches, floored at 3, capped at 5), theme set (`auto` = the 3-step probe including the
`next-themes` class route), `--states` files, DPR.
**Out:** `masters/<cell>.doc@Nx.png` (`read_class:"forbidden"`), `read/<cell>.{index,fNN}@Nx.png`,
`facts/*.domsnapshot.json`, `facts/*.layout.json`, `manifest.json`, one JSON line on stdout.

The manifest carries, **per image, as computed fields**:

| Field | Meaning | Why it is a field and not a rule downstream |
|---|---|---|
| `read_class` | `forbidden` \| `degraded` \| `lossless` | a **prohibition**; `forbidden` may never reach `Read`. Stops each later stage re-deriving the clamp rule. |
| `read_colour_class` | `intact` \| `quantised-256` \| `jpeg-<q>` | **new — attack ruling A1.4.** The clamp is not one axis, and one bit cannot describe two. |
| `eff_read` | model px / CSS px **through Claude Code's `Read`** (2000-px client clamp) | the path an *agent* uses — **geometry only** |
| `eff_api` | model px / CSS px **through a direct API request** (no client clamp; 4,784-token tier binds) | the path `dr judge` uses — **§2 C6: these differ and both are right** |
| `visual_tokens` | `⌈w/28⌉·⌈h/28⌉` after the applicable clamp | the cost, exactly |
| `tier_safe` | `⌈w/28⌉·⌈h/28⌉ ≤ 4784` | the predicate `clamp_safe` does **not** imply (§2 C5) |
| `chrome` | `live` \| `neutralized` | `position:fixed` was rewritten to `absolute` in the doc master |

🚨 **The `Read` clamp is a FOUR-ARM LADDER and the spec modelled only its last arm** (attack ruling
A1.4, CONCEDED). Read out of the shipped client (`cli.js`, fn `DJ1`: `xC=3932160, $J1=2000,
_J1=2000`), the order is: **passthrough → palette-PNG quantise to 256 colours → JPEG 80/60/40/20 →
`resize(fit:'inside')` → palette/JPEG again.** The consequence is the state the old one-bit
`clamp: safe|degraded` field **could not express**: a ≤2000 px master that merely exceeds 3.75 MiB is
**palette-quantised to 256 colours at full geometric resolution.** `eff_read` computes **1.0** — every
geometric claim about that image is sound — while every colour claim about it is a lie, because a
5/255 drift and a 256-colour palette do not survive each other.

That is not a footnote on `reso-management-app`: it ships a **generated P3 accent layer**
(`src/app/mc-p3.generated.css`, confirmed on disk), so its accent colours are exactly the population
a palette pass destroys. Combined with §4.1(h) — Chromium clips P3 to untagged sRGB before the file
exists — **colour findings on that app's accents are blind on two independent axes**, and the manifest
must say which one fired. Hence `read_colour_class`: geometry and colour degrade independently, are
consumed by different rule families, and a stage weighting a colour claim reads `read_colour_class`,
never `read_class`. **A rule family whose subject is colour refuses on any image whose
`read_colour_class != "intact"`** — an abstention, per C8, not a run failure.

Plus per cell: `coverage.{virtualized, raf_libraries, content_visibility_auto_nodes,
cross_origin_iframes}`, `fonts_resolved[]`, `fixed_elements[]`, `scrollbar_px`, and eight
assertions. **`replay.comparable_with` states the diff-legality rule as data**, so no stage
reconstructs it from prose: same `spec_sha256` + same `env_sha256` ⇒ byte equality; same spec only
⇒ NVIDIA FLIP mean ≤ 0.020 (measured noise floor 0.0099–0.0130; weakest true regression 0.0753;
**pixelmatch at its default inverts here and must not be the gate**).

Three flags are load-bearing and each for a different reason: `--force-device-scale-factor=<dpr>`
(headless vs headed Retina drift ~1.5 px over four paragraphs), context `deviceScaleFactor` equal to
it, and `screenshot({scale:'device'})` (without it `deviceScaleFactor` is silently discarded at
encode). The only detector for a mismatch is `raster_w / css_w` on the written file —
`window.devicePixelRatio` reads `1` in both cases.

`reducedMotion` is **`no-preference`** on the default arm (§2 C4) and `reduce` is an *additional*
cell. Reviewing the reduce branch as "the design" produces a perfectly deterministic photograph of
a page most users never see.

### 1.2 → S1b · live page → `facts/<cell>.inkmask.json`

Runs **inside S1's process**, after the master is written and stability has been asserted, before
the context closes (§2 C24). Ranked ≤40 candidates only; a full-page differential sweep is ~2,000
captures and is not the job.

```
before = clip-capture(union box)                     # box ∪ shadow/outline spread
hide    = element.style.visibility = 'hidden'        # NEVER display:none — that reflows
after  = clip-capture(same rect)
ink_mask = |before - after|.sum(axis=2) > 12         # 3 levels/channel
```

Out: per candidate `{backendNodeId, union_rect, ink_frac, mask_rle, glyph_mask_rle}`. This is the
painted shape **by construction** — including `border-radius`, `box-shadow`, pseudo-elements — which
is what kills the modal-colour swamping that made the shipped X1/X2 arms wrong. Seven zero-ink
causes are deliberately conflated (opacity 0, colour==background, occlusion, `overflow:hidden`
clip, `clip-path` empty, font never loaded, `content-visibility:hidden`): all seven are the same
finding — *the DOM reports a healthy box and the user sees nothing* — and all seven are invisible to
a DOM-only reviewer.

### 1.3 → S2 · the same CDP session → `facts.json` (~854 tok) + `layout.json`

**One** `DOMSnapshot.captureSnapshot` with the 39-property whitelist and **all four** `include*`
flags (32.7 ms; the flags cost +0 ms; the alternatives are 881 ms in-page and 5,788 ms per-node).
Separately `Accessibility.getFullAXTree` (26.7 ms) — a *different substrate*, joined on
`backendDOMNodeId`, never merged into one table.

**The split rule:** per-node facts live in `layout.json` **on disk, so they are not in context**;
per-page facts live in `facts.json`, which is the only thing a model reads.

**The reduction rule, one sentence:** *a node is named only when it is an outlier against the page's
own dominant convention, or when it carries an abstention; everything else becomes a distribution,
emitted as its head (which establishes the convention) plus its violators (which break it).* The
tail is **promoted, never dropped** — in a token-built page the tail *is* the defect.

**Rarity indicts an IDENTITY; off-scale indicts a MAGNITUDE.** One frequency threshold across all
axes is the obvious design and it is wrong: 0.5 % rarity correctly flags `font-family: Inter`
(4 nodes vs GeistSans's 1,978 — a real leak) and *also* flags `font-size: 72px` (the hero, 5 nodes),
which is not a defect. Families/colours by rarity; sizes/radii/spacing by off-scale/off-grid only.

**The abstention rule — colour from the compositor, KIND from the cascade.**
`blendedBackgroundColors` is adopted for the *value* and gated by an independent 12-deep ancestor
walk that only classifies the backdrop. Five whitelist properties (`mix-blend-mode`,
`backdrop-filter`, `filter`, `background-clip`, `-webkit-text-fill-color`) exist **solely to prevent
a false pass** and produce no finding. Every abstention carries `routeTo`, a bbox, and
`blendedWouldGive` — *the number this stage refused to publish*. Pinned by the invariant
`measured + indeterminate === textRuns`, asserted every run.

`cannotAnswer` is a **contract clause, not a diagnostic**: it counts the nodes whose interiors are
structurally unreachable (`canvas:1, background-image:6, svg:41, video:0`), so silence in this pack
can never be read as absence of defect.

**Budget: hard ceiling 1,100 tokens.** The entire justification for handing the judge this pack is
that it costs less than the image it accompanies. On breach, truncate histograms first, then capped
violator lists, and **never abstentions** — a dropped abstention silently becomes a pass.

### 1.4 → S3 · `{domsnapshot, layout, inkmask}.json` + the PNG + `profiles.json` → `screen.json`

Pure file-in/file-out. No browser (§2 C24). Sha- and timestamp-matched to the capture, else refuse.

**Three-valued, and the third value is the point.** `PASS` (precondition held, measurement ran,
inside band) · `FAIL` (held, ran, outside band) · `INDETERMINATE` (**precondition did not hold, so
no measurement exists**), carrying the reason in machine-readable form plus `routeTo`.

**Bands are derived from the capture manifest, never constants:** `band = J1(0.5/dpr) + J2(0.25
fractional layout) + J3(0.5/line-box)`. A constant tolerance is wrong at both DPRs and silently
wrong at 1.5. **A profile may reweight severity and disable a rule; it may never loosen a band —
bands are physics, not policy.** And an *unpinned* capture does not get a looser band: the whole
geometric family voids to `INDETERMINATE`.

**Rule admission test, binding on every rule added later.** A rule enters only if it declares
`subjects(page)` (the enumerable population — no rule may iterate an implicit set), `precondition()`,
**at least one reachable INDETERMINATE branch** (a rule claiming it can measure every subject on
every page is lying), one mutant fixture, and a clean-control run.

Families: **G1–G4** geometry · **T1–T3** type · **K1–K4** token conformance · **A1–A3** correctness
floors (the only family permitted to gate) · **O1–O2** containment · cross-checks **X1** (zero-ink,
over S1b's mask) · **X3** (contrast sampled across a run — *the arm that works*) · **X2, X4–X6 ship
OFF** (§3).

**Output header is a closed census, asserted at exit:**
`pass + fail + indeterminate + out_of_scope == subjects`, plus — new, and it is the fix for §2 C7 —
`indeterminate_classes`, the abstentions collapsed by `(rule, backdrop_signature)`.

**Fingerprint spans the CLAIM, not the location:**
`fp = blake2s-128(rule_id ‖ subject.path ‖ claim)` where `claim` is a rule-defined discriminator.
Measured: deduplicating by `(rule, target)` **silently swallowed a real colour-token drift** because
an unrelated `token-drift` already sat on that element. 0/1 until the key was widened, then 1/1.

### 1.5 → S4 · `screen.json` + `facts.json` + `manifest.json` → `route-plan.json` + `blocks.json`

**Five triggers, and only five.** Anything else is settled and forwarded as a *fact*, never a question.

| | Trigger | Volume |
|---|---|---|
| **T1** | `INDETERMINATE` **minus** what the cross-check closed, **then collapsed by class** | on the corpus today: **0**. On a real page: expect 2–4 classes from ~95 subjects (U3) |
| **T2** | the six unscreenable classes — hierarchy · gestalt · content-fit · semantic-coherence · optical-alignment · readability | **once per page, unconditional, never cut for budget** |
| **T3** | explicit operator request | budget-exempt, recorded as `kind:"explicit"` |
| **T4** | arbitration: the judge contradicts a `layer:dom` finding | ≤1 per page; a second is a *rule* defect to file, not a third image |
| **T5** | no-DOM subjects (canvas, WebGL, PDF comp, video frame) | model-primary, because nothing was lost |

🚨 **The T1 subtraction is CODE, not discipline, and it is gated on the xcheck file EXISTING.** If
the cross-check is down, an empty file resolves nothing *and looks like nothing needed resolving* —
so the subtraction must test for the file, and T1 *grows* under a cross-check outage. This is the one
case where a larger model queue is the correct response to a layer failure.

**The NEVER list:** if the answer has a number in it, the model does not get the question. Distances,
gaps, sizes, ratios, contrast (solid *or* gradient), token membership, animation timing, bounding
boxes for anything, and any score/grade/ranking.

**Out:** `route-plan.json` (the decision record, with a per-layer `coverage` field and
`unadjudicated_by_budget`), crop *requests* (S4 never rasterises — a crop from a second browser pass
is a different frame), and `blocks.json`, the **single image ledger** (§2 C1).

### 1.6 → S5 · crop requests → `plan.json` + `crops/cNN.png`

Re-clips inside S1's original pass. `Page.captureScreenshot({clip:{x, y, width, height, scale}})` —
`clip.scale` renders **truly** at 1.388×, not a Lanczos downsample of a 2× render. *(Field names
corrected per attack ruling A1.6: `Page.Viewport` is `{x, y, width, height, scale}`. The spec wrote
`{w, h}`, which is not a protocol shape — CDP would have thrown `Failed to deserialize` on the first
call, so this was a build-stopper hiding in a one-line code fence.)*

**Ceiling is 2.0 on a design argument, not physics.** The review target is what a human sees at
DPR 2. A defect visible only at 4× is manufactured false-positive supply. The consequence is what
terminates the recursion: a child crop buys *isolation* and at most a move from eff 1.39 → 2.00; it
never buys magnification.

**Envelope (§2 C5):** both predicates must hold —
`w ≤ 2000 ∧ h ≤ 2000 ∧ bytes ≤ 3,932,160` **and** `⌈w/28⌉·⌈h/28⌉ ≤ 4784`.
Square maximum is **966×966 CSS @2**, not 1000×1000. Non-square gets more room; the token predicate
is the general rule.

Every crop carries, in its caption, **verbatim**: its band role and page fraction · its neighbours ·
`eff` · a **region label** (`region c07 — "the KPI row, second card"`) · and its own prohibition —
at `eff < 2.00`, *"do not assert any 1–2 px alignment, hairline-width or colour-drift finding from
this image; if you suspect one, name the region."* A crop that cannot support a verdict must say so
**in the same image's caption**, because a judge that is not told will answer anyway.

**Region labels replace coordinates entirely** (§2 C19). A crop finding names a label; attribution
becomes a lookup in `plan.json`, which holds the rect and the dominant element's `backendNodeId`.
Three multiplications owned by three stages are replaced by a join.

### 1.7 → S6 · images + `factpack.json` (+ verdicts, only where legal) → `judge/*.json`

**S6 owns the REQUEST, and that is what makes blindness real** (§2 C10). The blind gestalt pass is a
separate API request with its own message list — *not* a turn in an agent's append-only conversation,
because an agent that read `screen.json` at turn 3 and looked at the screenshot at turn 5 has run the
anchored arm while every contract believes it ran the blind one.

| Call | Image | May receive | May NOT receive |
|---|---|---|---|
| **gestalt (pass 1, BLIND)** | one viewport frame, `eff_api` 1.68× | nothing but the image + the app's `intent` block | `factpack.json`, `screen.json`, any finding |
| **reconcile (pass 2, same conversation)** | — | `factpack.json` **and** `screen.json` | — |
| **crop** | one crop ≤966×966 @2 | `factpack.json` (values, filtered to the crop + page-level distributions) | `screen.json` verdicts |
| **adjudicate** | one region crop | everything, including the cross-check row | more than one INDETERMINATE **class** per call |

🚨 **`adjudicate` takes a CLASS, and the class→call converter is a named step, not an assumption**
(attack ruling A1.U2, CONCEDED — this was a real type break). C7 rules that *"S4 routes classes, never
subjects"*, and that collapse is the entire affordability argument: 95 → ~3. This table previously
said *"no more than one INDETERMINATE per call"*, and **a class is a set of INDETERMINATEs** — so
either C7's ruling was void and the budget was fiction, or this constraint was void, and no stage
converted one to the other. The converter:

> S4 emits one `adjudication_request` **per class**, carrying `{class_key: (rule,
> backdrop_signature), exemplar: <the single highest-consequence subject>, member_count: N,
> member_node_ids: [...]}`. S6 crops **the exemplar** and asks the question **about the exemplar
> only**. S8 then **fans the verdict back over the class**, and the fan-out is recorded as
> `generalised_from_exemplar: {class_key, member_count}` on every derived finding.

The fan-out is the honest cost of affordability and it is stamped on the output rather than hidden:
a class-generalised finding **may never reach `asserted`** (its predicate was executed against one
member, not N), and the report header counts it separately. If a class is not homogeneous enough to
generalise, that is a *rule* defect — the class key is wrong — and it is filed against S3, not paid
for with N images.

🚨 **The facts/verdicts split is the ruling that reconciles P6, P5 and the README** (§2 C3).
`factpack.json` carries **values**; `screen.json` carries **verdicts**. A value tells the model what
is true and stops it computing what it cannot compute; a verdict tells it what counts as reportable,
and that is the anchor. A `gestalt` or `crop` call receiving verdicts is a schema violation rejected
before the API call.

**Output is schema-validated before the acting agent ever sees it.** `evidence` is a tagged union
with **no numeric member** — the only legal move for a number is `needs_measurement{question,
region, what_would_change}`, which routes back to S3. An exhortation is violable in fluent prose; a
schema with no slot is not.

⚠️ **And that is exactly why Route C cannot exist in v1** (attack ruling A1.U1 + A1.U5, CONCEDED —
see §1.9). §1.9 asked a model to emit *"a predicate in an AST-allowlisted DSL"* over browser
geometry — `gap < 8` — through a schema **built to forbid numbers**. There is no member of this union
for it and none may be added: adding one re-opens sub-perceptual fabrication, which D8 and §4.1(c)
both close. The two constraints are not reconcilable by writing more specification, and the resolution
is to delete the demand, not the guard. `needs_measurement` remains the *only* numeric exit, and it
routes to S3, which owns numbers.

Three cap rules, and the third is new:
- `findings: maxItems 7` (page) / `4` (crop) — a reviewer flagging 40 to catch 8 is net negative.
- `clean_assertion` **required and non-empty**, so an empty `findings` array is a *result*.
- **`unprompted: maxItems 3`, non-fungible, schema-forbidden from citing any fact-pack path.**
  Reason (§2 C3): `maxItems 7` under a prior of 14 FAILs arithmetically guarantees the discretionary
  tail is cut first, and the discretionary tail is the only thing here nothing else can produce.

`gestalt.blind.json` is written and **hashed into `run.json` before any fact is shown**, so no later
stage can retroactively edit it and S12 can assert it.

Branch order is permuted per call from `tree_seed` and the seed is **echoed**; without the echo you
cannot distinguish "permuted, stable" from "never permuted". Swap-recheck fires only on
`impact_claim == task-blocked` — the reversal harm is real, 2× cost on every call is not.

### 1.8 → S7 · the page's own state vocabulary → `state-plan.json` + motion findings

Runs in its **own** browser pass (proc B): its instruments (`page.clock`,
`Emulation.setCPUThrottlingRate`, real `locator.click()`) mutate the page in ways that void S1's
byte-stability gate.

**The state axis has two halves and the cheap mechanism reaches only one.** Measured in
`reso-management-app`: **207 `[data-hover]`** rules set by Ark/Base UI *JS pointer handlers*, against
305 CSS `:hover` rules. `CSS.forcePseudoState` changes style computation only and fires no events, so
a forced sweep reports healthy hover coverage while the 207-rule population was never exercised —
and it fails *silently in the safe direction*. So the attribute axis is first-class, driven by **real
input only**, counted separately, and a `state-missing` finding requires **both** axes exercised or
it is `abstained: axis-unreached`.

**Interaction states are CROPS, not PAGES.** A hover changes one component; the S1/S2 axes never
become capture cells. The state axis costs O(1) images, not O(states × elements).

**Motion is asserted, not watched.** Every property a motion review asserts is already an exact
number in the animation model. Frames are needed for exactly one class: *a mid-interpolation
rendering artifact whose timing model is entirely correct and whose composited pixels are wrong.*
≤9 frames, indexed by **elapsed ms**, endpoints declared known-good, and the prompt fenced to the
artifact question — timing estimates from a frame strip are forbidden.

**A freeze nobody tested is not a freeze.** A two-armed canary (a 10 s linear WAAPI animation + a rAF
tick counter, read twice 250 ms apart) must show both frozen, or **no frame in that run is
evidence**. `waapi_animations_seen: 0` beside `raf_canary_ticks_per_250ms: 17` is the GSAP false
green, and `coverage.verdict` reads `PARTIAL`, never `CLEAN`.

### 1.9 → S8 · every findings file → `arbitrated/report.{json,md}`

**Deduplication LINKS, never DELETES.** Key is `sha1(defect_class ‖ target_key ‖ observable_bucket)`
over a closed class vocabulary (so a rule and a model can meet at all), a **`target_key`** (below),
and a per-type quantised observable (**colour exact and unquantised** — quantising colour re-creates
the swallowed-drift bug one level up).

🚨 **`target_key` is a DURABLE SELECTOR, not a `backendNodeId`, and three stages were keyed on the
wrong one** (attack ruling A1.U3, CONCEDED). The protocol defines `BackendNodeId` as *"a unique DOM
node identifier used to reference a node that **may not have been pushed to the front-end**"* — a
renderer-side handle. It does not survive a navigation, so it certainly does not survive S7's proc B
or S9's separate dev-server run, and **run-to-run `new` / `known` / `regressed` partitioning cannot
be built on it.** The same defect reaches further than the dedup key: §4.3's `.design-exceptions.jsonl`
falsifier is `selector_absent`, which presupposes a stable selector **no stage in the contract chain
was producing.**

**Ruling — S2 mints `target_key` once, at extract time, and everything downstream joins on it:**

```jsonc
{ "target_key": "sha1(dom_path ‖ stable_attrs)",   // THE cross-process, cross-run identity
  "dom_path":   "main>div:nth-of-type(2)>section[data-testid=kpi]>div:nth-child(3)",
  "stable_attrs": {"data-testid":"kpi","id":null,"role":"group"},
  "backendNodeId": 4127 }                          // in-process handle ONLY, never a key
```

`backendNodeId` stays on the record — it is the correct and only handle for an in-process CDP call
within S1/S1b/S2 — but it is **demoted to a transient field that no key, no join and no falsifier may
read.** Precedence for `stable_attrs`: `data-testid` > `id` > `role` + ordinal path. The honest
limit, stated rather than discovered later: a `dom_path` through a list whose length changes between
runs will re-key, so a re-keyed finding surfaces as `new` rather than silently vanishing — **the
failure direction is a duplicate, never a swallowed defect**, which is the same asymmetry D5 bought
by widening the key in the first place.

The arithmetic that makes never-delete correct: blind Opus 5 gave **0 FP** and **3 novel TPs** over
**8 pages**. Rule of Three puts the FP upper bound at **3/8 = 37.5 %** and the novel-TP rate at
**3/8 = 0.375 per page**. *The two are still the same arithmetic on the same denominator*, which is
the property this ruling rests on: a finding you are about to discard is exactly as likely to be a
defect nobody was looking for as it is to be noise. **Never-delete survives the correction; the
safety margin does not** — see the rewritten §2 C18.

🚨 **n = 8, not 13 — corrected 2026-08-26 under attack ruling A2.3, and this number was wrong in six
places.** `bench/corpus/out/blind_key.json` contains exactly **8** entries (`page-A`…`page-H`, H the
clean control), and `README.md:30` says so in its own results table: *"Claude vision, blind (8 pages,
no ground truth)"*. The corpus **builds** 13 variants; the blind judge **saw 8** of them. Every
`3/13 = 23.1 %` in this document was a rate computed over the corpus's build count instead of the
run's trial count — the `count-the-population-the-remedy-acts-on` failure, committed against our own
substrate.

Same class + same node + **different** observable bucket does not collapse; it mints a
`substrate-disagreement` at `major`, unconditionally, above whatever the underlying class earns. An
instrument that lies is worse than the defect it lied about.

**Promotion:** `asserted` requires *a falsifiable predicate over browser-supplied facts that was
actually executed and did not fail.* Not high confidence, not two models agreeing. Route A (DOM
arithmetic) auto-asserts. Route B (cross-check) asserts iff it carries **both operands and the
tolerance**.

🚨 **Route C is DELETED. A model finding is `advisory`, terminal, with no promotion path at all**
(attack rulings A1.U1 + A1.U5, both CONCEDED — this is the single largest design change from the
review). The old Route C read, in full: *"requires the verifier to return a TEST, not a verdict — a
predicate in an AST-allowlisted DSL, plus a `falsifiable_by` that is checked for vacuity."* That was
the whole specification. Nothing defined the allowlist, the fact namespace it binds to, the vacuity
test, or the arity of `falsifiable_by`. It is **a compiler for a language with no programs**, and it
had two independent fatal defects:

1. **It cannot be expressed.** §1.7 mandates that S6's `evidence` union has **no numeric member**, and
   a predicate over browser geometry is inherently numeric. The judge would have had to emit numbers
   through a schema built to forbid them.
2. **It silently breaks the one isolation this pipeline calls load-bearing.** §0.1 states that RT
   *"never reads `judge/` or the `advisory` rung"* and calls that *"the mechanical enforcement of the
   June 2026 ruling."* C17 gates on S8's `asserted` set. Route C let **a model finding enter that
   set.** The gate therefore read judgement output, laundered through arbitration — *the diff that
   would break the isolation had already been written, inside the section that praised it.* An
   isolation a sibling section quietly pierces is nominal, and nominal is worse than absent because it
   is defended.

**Ruling: no model finding is promotable by any route.** `advisory` is terminal — which is what the
June 2026 ruling always said, and what §0.1 already claimed was mechanically true. If a model finding
deserves promotion, the correct move is the one already in the contract: it emits
`needs_measurement`, **S3 grows a rule**, and the rule's own Route A asserts it on the next run. That
path is buildable today, it produces a reusable detector instead of a one-shot verdict, and it keeps
every number inside the layer that owns numbers. The cost is honest and small: on the measured run,
**3 novel findings per 8 pages stay advisory** — and they were never gating anything, because the
gate has never been allowed to read them.

**Rejection is asymmetric:** promotion takes 1 sample; rejection takes 3 independent predicates that
all evaluate false. The stage must be harder to talk *out* of a finding than into one.

**Severity is computed, never asked for** (§2 C13); **confidence is a band from the evidence route,
never a probability a model produced** (§2 C14). A declared-but-unmeasured band renders with `†` and
the header counts them.

The report header **can never render "clean"**: it renders counts including `UNVERIFIED`, so a page
on which every instrument abstained reads as *three axes unchecked*. Abstentions sit **above**
advisories — an abstention is a known hole, an advisory is an opinion.

### 1.10 → S9 · a finding + a dev server → `attribution.json`

Per finding: `verdict ∈ {RESOLVED, AMBIGUOUS, UNATTRIBUTABLE, VENDOR, STALE}`, `confidence ∈ {HIGH,
MEDIUM, LOW}`, ordered `targets[] {kind, file, line, column, evidence, excerpt, shared_with,
edit_hazard}`, `component_path[]`, `declaring_rule`, `why_not_better`, and — when nothing resolves —
a runnable `next_probe` **command**, never a path.

🚨 **This stage never emits a guessed path.** An agent given `targets: []` plus a grep command runs
the grep and reads the result; an agent given a wrong `file:line` **edits it**.

**Rung 1 is `fiber._debugStack` + `_debugOwner` → `POST /__nextjs_original-stack-frames`.**
`__source` / `_debugSource` is **dead on React 19** — measured 0 occurrences in 19.2.8's dev bundle,
and `jsxDEV`'s args 5/6 are now `debugStack`/`debugTask`. It is *alive* on React 18, which **one of
three apps** still runs — so it is coded as a **fast path under** the owner-stack resolver, never as
the primary. A resolver written against `_debugSource` has a scheduled expiry date, and the upgrade
that kills it will look like an unrelated regression.

🚨 **"two of three apps" was FALSE and it was the rationale for the fast path** (attack ruling A1.2,
CONCEDED). Measured 2026-08-26 from `node_modules`, not from prose: `reso-management-app` **19.2.8**,
`reso-web-app` **19.2.8** (declares `^19.2.8`), `reso-landing-app` **18.3.1**. **Only the landing app
— a purchased template — is React 18.** §2 C11's table row said `reso-web-app` = React 18.2.0, and
§1.10 then built a design decision on top of that row. The correction *strengthens* D6 and *weakens*
the fast path: the owner-stack resolver is not merely the primary, it is the **only** path that runs
on the two apps anyone is reviewing, and `_debugSource` is a one-app legacy branch whose test corpus
is a template nobody edits. It stays — it costs ~20 LOC and the landing app is real — but it is now
explicitly a **single-app** branch, and §5.1's attribution row may not average it in. *This is the
sharpest single lesson of the review: C11's own heading is "**the measured stack wins, and prose is
banned as a source**", and the table under that heading carried an unmeasured row that eleven
downstream sentences inherited.*

`HIGH` requires rung-1 resolution **and** class-inversion agreement **and** `shared_with == 0` **and**
a clean tree. On the management app **337 files under `src/` import `styled-system/css`** (352 across
all tracked files) and **`fg.muted` appears 221 times under `src/`** — 223 including `styled-system/`,
427 across the tracked repo. **`MEDIUM` is the honest modal verdict and the consumer prompt is
designed for `MEDIUM`**, and the conclusion is unchanged at every one of those scopes.

⚠️ **`fg.muted` × 263 reproduced at NO scope and was quoted twice as load-bearing** (attack ruling
A1.4, CONCEDED). Neither did the bare `337` — it is right, but only under `src/`, which the spec never
said. **Every count in this document now carries its glob**, because a count whose scope is unstated
cannot be re-measured, and an un-re-measurable number is prose wearing a measurement's clothes — the
thing C11 exists to ban.

### 1.11 → S10 · `surface.json` + the run → the `UNREVIEWED` block

Prepended verbatim, generated with no prose authored at report time. §4 gives its shape. S10 detects
nothing and vetoes two things: a report that scores taste, and a report that does not say what it
never looked at.

### 1.12 The driver, and the protocol surface it stands on

*New section — attack ruling A1.U6, CONCEDED. The spec used two automation vocabularies across nine
sections and never named the library, which is the sort of omission that reads as a choice.*

**The driver is Playwright, and every raw-protocol call goes through `browserContext.newCDPSession(page)`.**
§1.1 and §1.8 use the Playwright surface (`screenshot({scale:'device'})`, `page.clock`,
`locator.click()`, `animations:'disabled'`); §1.2 and §1.6 use raw CDP (`Page.captureScreenshot`,
`DOMSnapshot.captureSnapshot`, `Runtime.callFunctionOn`). These are reconcilable — one `CDPSession`
over one Playwright page — but the reconciliation is **load-bearing in one specific place** and must
be stated as a rule rather than left to a builder:

🚨 **A `Page.captureScreenshot({clip:{…scale}})` issued through the CDP session BYPASSES Playwright's
`scale:'device'` handling.** §1.1 calls that flag load-bearing precisely because without it
`deviceScaleFactor` is silently discarded at encode — so S5's re-clip, which is a raw-CDP call by
necessity (`clip.scale` has no Playwright equivalent), is on the *unprotected* path. **Rule: every
raw-CDP capture asserts `raster_w / css_w == dpr` on the written file before the bytes are accepted**,
which is the same detector §1.1 already names as the only one that works (`window.devicePixelRatio`
reads `1` in both the healthy and the broken case). One assertion, both paths, no trust.

**The protocol surface is EXPERIMENTAL, and §4 must say so** (attack ruling A1.6, CONCEDED). Read out
of `browser_protocol.json`: the `DOMSnapshot` **domain** is `experimental: true`; the `Accessibility`
domain and `getFullAXTree` are `experimental: true`; and of `captureSnapshot`'s four `include*` flags,
**`includeBlendedBackgroundColors` and `includeTextColorOpacities` are themselves `experimental: true`.**
So the *entire* contrast-and-abstention substrate — §1.3's D4 ruling, X3, and every `INDETERMINATE`
that makes the three-valued design honest — sits on protocol fields Chromium may rename or remove in
a point release, and §4's blind-spot list never said so. This does not change a design decision: there
is no non-experimental alternative, the measured alternatives are 881 ms and 5,788 ms, and the whole
pipeline is already Chromium-only by §4.1(g). It changes what the pipeline must **detect**: `dr
extract` asserts each flag's presence in the *response* — not its acceptance in the request, which
Chromium silently ignores for unknown params — and a missing field is a `degradation.json` entry
(`substrate: reduced`) that abstains the dependent classes, never a wrong number and never a pass.
Added to §4.1 as blind spot **(n)**.

---

## 2. Contradictions, named and ruled

Twenty-three places where two stage specs cannot both be built. Each ruling names the loser and why.
*(The working numbering skipped C12, C21 and C25 — three apparent conflicts that dissolved on a
closer read. The gaps are kept rather than renumbered, because every cross-reference in §1 and §3
already points at these ids.)*

| | Contradiction | Ruling in one line |
|---|---|---|
| C1 | Four image budgets (16/12/19/8) against one cliff | Two *different* resources, one ledger each |
| C2 | P2's 12-crop cover vs P5's 2 vs P12's "crops destroy the finding" | ≤2 crops default; the sweep is gated on a probe |
| C3 | Fact-pack blind (P6) vs with-the-question (P5) vs "no reason to withhold" (README) | **Values may enter; verdicts may not** |
| C4 | `reducedMotion: no-preference` (P1) vs `reduce` (P3, P4) | P1 wins; the precondition is *pinned*, not *pinned to reduce* |
| C5 | 1000×1000 vs 966×966 vs 2000×1800 CSS crop | 966×966 square; the token predicate is the general rule |
| C6 | Frame at eff 1.389 (P1) vs 1.68 (P6) | Both right — different delivery paths; manifest carries both |
| C7 | 95 abstentions (P4) vs a budget of 2 (P5) | Collapse by class before routing; print the deficit |
| C8 | Every stage fails closed ⇒ the composition fails never | Degradation vector; an exit needs to invalidate *everything* |
| C9 | Three different "global image" | Three images, three questions, three names |
| C10 | Can an agent's conversation run a blind pass? | No. S6 owns the request or the run is stamped `blind:false` |
| C11 | Per-app stacks: brief vs P3/P5 vs P4/P8/P12 | The measured stack wins; `profiles.json` is generated |
| C13 | Model sets severity (P6) vs computed (P7) | P7 wins; P6 emits an impact *claim* |
| C14 | Model confidence 0–1 (P6) vs evidence-route band (P7) | P7 wins on output; P6's number is routing-internal |
| C15 | Attribution owner: "unowned"/"P2"/P8 | **P8 owns it**; the other two tables are stale |
| C16 | Gradient contrast: settled (README/P5/P6) vs a duty crop (P2) | Settled; P2 must subtract `resolved_by(xcheck)` |
| C17 | Three `--gate` flags in three stages | One gate, `dr review --gate`, over S8's `asserted` set |
| C18 | "Zero FP" as the defended baseline vs a bound — **and the bound was computed on the wrong n** | Absolute-zero is the ship gate; **no *rate* below n=16**; the real bound is **3/8 = 37.5 %**, not 23.1 % |
| C19 | Crop findings carrying page-space coordinates | Region labels; coordinates from a crop are rejected |
| C20 | Budget breach: wave 2 / subagent / drop cells | Drop **whole cells**, never truncate a cell mid-chain |
| C22 | P1 names the motion owner "P5" | S7; see the §0.2 map |
| C23 | `--frames=strict` | `merge` is the only production mode |
| C24 | P4 needs a live browser; P11 says P4 has none | The differential probes move into S1b |
| C26 | P13 exit 3 vs P11's `coverage` field | One exit table; P13's floor becomes a marker on exit 2 |

### C1 — Four budgets, one cliff. **They are two resources, and conflating them is the bug.**

P2 sets 16, P5 sets 12, P4 sets 12/19, P6 sets 8, P9 reserves 4 of P5's 12. P11 then declares the
cliff can never fire "because `--call-concurrency` bounds requests in flight and P5 caps a single
request at 12 blocks." P12 accepts that for the API path and refutes it for the other one.

**Ruling.** There are two resources with different owners and different failure modes:

| | **The request** (API path) | **The conversation** (agent path) |
|---|---|---|
| Owner | `dr judge`, in code | the agent, reading `report.md` |
| Bound | **≤8 image blocks per request** (P6's number — the most conservative, and the request is what the cliff is about) | **`blocks.json`: `{ceiling, spent, entries[]}`**, decremented by every stage that writes a model-facing image |
| Enforcement | mechanical — the request is built here | `read_order` ≤6 paths, each carrying `deliverable: true\|false` and the running `spent/ceiling` pair |
| On exhaustion | refuse the call, exit 70, name the image | write the image anyway, mark `deliverable:false` |

P11 is **correct and superseded on its own path**; P5's 12 governs the *conversation*, not the
request. The agent-path bound is today an *instruction* — "read them in order and stop when you have
enough" — and an instruction is a request a model can decline, and it cannot see the images already
in the conversation before the run began. Converting it to a ledger costs one field.

**Refusing to write destroys evidence; refusing to *deliver* costs nothing.** That asymmetry is why
the over-budget image is still written.

⚠️ **Whether the cliff counts per request or per conversation is UNVERIFIED** and it is the cheapest
probe in the programme (§7 U1, ~4 min). If per-request, the conversation ledger can rise to ~18 and
S6's cap is the only real one. If per-conversation, this section is load-bearing exactly as written.

### C2 — Crop decomposition. **Bounded, and its expansion is gated on a probe.**

P2 builds an exhaustive 12-crop MECE cover driven by the abstention set. P5 says 1 global + ≤1
region and observes T1 is **empty** on the corpus today. P12 R2 attacks the justification itself.

**The attack, and it holds.** The 18.9 % → 48.1 % lever is measured on a benchmark with **zero web
screenshots**, scoring **point-in-box not IoU**, on the **inverse task** (find a *named* widget vs
name an *unnamed* defect). And the logical form of our own unique findings settles it:

| Blind finding | Logical form | Minimum sufficient frame |
|---|---|---|
| orphan legend | `∃ caption ∧ ¬∃ referent` | the caption **and** the whole table |
| unlabelled **smallest** hit target | `argmin` over every interactive target | **every** interactive element |
| numeric columns not aligned | within- and across-column comparison | the column plus a neighbour |
| inverted action hierarchy | a relation between primary and secondary | both actions, so not a tight crop on either |

**Four of the five defects only this judge produces are structurally unreachable from a crop.** The
fifth (washed-out text on a gradient) is now settled deterministically at zero model cost.

**Ruling.** S5 survives, bounded:
1. The **global pass is mandatory, first, blind, and unbudgeted** — its block is *not fungible* with
   the crop budget.
2. A crop may answer only a question the **global pass raised**, or a *collapsed abstention class*
   the cross-check could not close. Never speculative, never a per-finding duty crop.
3. **Superlatives and existentials are banned in crop output** — S6's crop schema rejects any
   `problem` matching `/\b(smallest|largest|only|most|least|no other|missing|absent|nowhere)\b/`
   with *"this claim quantifies over the page; ask it at global scope."* Mechanical, and it closes
   the hole rather than warning about it.
4. No crop finding reaches `asserted` without a global re-ask (S8 gains `scope_mismatch`).
5. **P2's exhaustive cover ships only if U4 shows a 6-crop arm strictly dominating full-page on our
   own corpus.** Until then it is `dr decompose --sweep`, off by default. If U4 comes back negative,
   S5 shrinks to a re-clip utility and the stage's planning half is deleted.

*What survives from P2 regardless, because it is right and cheap:* the `uncovered == []` checked
post-condition, the projection-profile band cutter, the cut-never-straddles-an-element rule, the
per-cut overlap derived from the straddler distribution, and the caption-with-its-own-prohibition.

🚨 **The 2026-08-26 value attack finished this ruling** (A2.7, CONCEDED). C2 bounded S5 and gated its
expansion on U4; the attack observed that **U4 is unrun, and 706 lines of P2 spec therefore rest on a
probe** — which by §5.2's governing rule makes the stage an argument, not a number. **S5 is cut from
the core pipeline. What ships is a ~40-LOC re-clip utility**, with no planning half. The five clauses
above survive as the *design* to build **if** U4 revives it. See §6 B17.

### C3 — The fact-pack. **Values may enter any call; verdicts may enter only adjudication.**

Three positions: the README ("no context-budget argument for withholding"), P6 ("blind on pass 1 —
my reason is contamination, not budget"), P5 ("facts arrive *with* the question, after the pixels").

**They are not actually about the same object, and P12 named the distinction nobody else drew.** A
*value* ("this text is 14 px, its neighbour 16") tells the model what is true and is the thing that
stops it computing a number it measurably cannot compute. A *verdict* (`token-drift FAIL on
.btn-primary`) tells it what counts as reportable. **The first is a legitimate aid. The second is
the anchor.**

Two mechanisms make the anchoring risk concrete rather than psychological:
- **Crowding-out is arithmetic.** `maxItems: 7` under a prior of 14 `FAIL`s cuts the discretionary
  tail *first*, and the output is well-formed with every finding in it real. Nothing notices.
- **This judge class is measurably sensitive to framing alone** — 16–39 % top-1 reversals from
  *reordering* identical content. "Inserting 854 tokens of pre-verdicted claims is inert on the
  output distribution" is not a tenable null.

**Ruling.** Split the artifacts at the contract level (§1.7's table), add the non-fungible
`unprompted` array so the tail cannot be crowded out arithmetically, and freeze + hash the blind
pass. **The fact-pack ships** — deleting it re-opens sub-perceptual fabrication, which is worse.

⚠️ **U5 (§7) settles the direction and it is the highest-value experiment in the whole wave**: three
arms over 13 pages, 39 calls, <100 k tokens. Decision rule stated *before* the data: if arm C's
unprompted count is below arm A's by more than one finding across the corpus, verdicts never enter a
gestalt call under any circumstances.

### C4 — `reducedMotion`. **P1 wins; the others' precondition was over-specified.**

P3 §3.1 sets `prefers-reduced-motion: reduce`; P4 lists `reduced_motion=reduce` as one of six pinned
knobs. P1 sets `no-preference` and flags the departure explicitly.

**Ruling for P1.** A9's own measurement already discharges the determinism argument —
`animations:'disabled'` + `fonts.ready` + rAF converged byte-identical *without* the flag. What
`reduce` costs is real: a shipped marketing page drops parallax, swaps hero video for a still, hides
an animated section. Under `reduce`, S1 produces a perfectly deterministic photograph of **the wrong
page**, and hides the motion defects the review exists to find.

P4's band derivation does not depend on *which* value, only on it being **fixed**. So the
precondition is restated: *`reduced_motion` is pinned to a value and that value is recorded in the
manifest.* P3's `setEmulatedMedia` line is deleted. `reduce` becomes an additional cell, which S7
needs anyway for its paired reduced-motion test — and that test is a **blocker waiting to fire**:
measured, `reso-landing-app` and `reso-web-app` have **zero** occurrences of `prefers-reduced-motion`
in their sources, and the landing app is the one built on `framer-motion`.

### C5 — The lossless crop. **966×966 CSS @2, and `clamp_safe` is necessary but not sufficient.**

P2/P3/P4/P7 all say ≤1000×1000 CSS @2 = 2000×2000 raster, "the exact pass-through condition". P5 and
P6 say 966×966. P11 shows 2000×2000 = 72·72 = **5,184 visual tokens, over the 4,784 tier**.

**Ruling for P5/P6/P11.** `⌈n/28⌉² ≤ 4784 ⇒ ⌈n/28⌉ ≤ 69 ⇒ n ≤ 1932 px = 966 CSS @2.` A 1000×1000
CSS @2 crop passes `clamp_safe`, passes every entry check, is accepted by `Read`, and is then
**resampled by the API**. Every geometric claim about it is a claim about a frame that was resized
after the pipeline certified it — the phantom-offset defect arriving through the request layer.

The predicate `assert ceil(w/28)*ceil(h/28) <= 4784` is enforced in **two** places, not one: in S5's
crop writer (so bytes are not wasted) and in S6's request assembly (P11's point — only the layer
assembling the request can see how many images it carries). Largest clamp-safe *and* tier-safe
rectangle: **2000×1800 = 4,680 tokens = 1000×900 CSS @2.**

### C6 — `eff` 1.389 or 1.68? **Both. It is a function of the delivery path, and nobody said so.**

P1 computes 1.389 for a 1440×900 @2 frame (2880×1800 raster → the 2000-px client clamp → 2000×1250).
P6 computes 1.68 (2419×1512, the largest 16:10 inside the 4,784-token tier).

**Ruling: neither is wrong and the manifest must carry both.**

| Path | What binds first | Delivered | `eff` |
|---|---|---|---|
| Agent `Read`s the PNG | Claude Code's 2000-px / 3.75 MiB **client** clamp | 2000×1250, 3,240 tok | **1.389** |
| `dr judge` posts to the API | no client clamp; the 4,784-token **tier** | 2419×1512, 4,698 tok | **1.68** |

So `manifest.images[].eff_read` and `.eff_api` are separate fields, and a stage weighting a claim by
`eff` must name which path delivered it. The corollary is a real capability difference: **the API
path sees 21 % more detail per CSS pixel on the whole-frame gestalt call than the agent path ever
can** — one more reason S6 owns the request (C10).

Also settled here: **1440×900 @2 cannot be delivered at full DPR 2 inside the tier** (104×65 = 6,760).
The honest desktop maximum is 1.68×, which independently re-derives, from our own token physics, why
detail above that has to come from clipping rather than from raising DPR.

### C7 — 95 abstentions against a budget of 2. **Collapse by class, then print the deficit.**

P4's own worked census reports `indeterminate: 95` on one page. P5 grants **2** image blocks per
page. The README's governing sentence is *"an abstention routes to the vision layer; a pass routes
nowhere."* **A dropped abstention routes nowhere.** As specified, the budget converts 87 % of the
honest abstentions back into silent passes — the exact failure the abstention was invented to
prevent, re-entering through the routing layer.

**Ruling, three parts:**
1. **Type them before routing.** 95 abstentions are not 95 questions. `(rule, backdrop_signature)`
   collapse turns "a gradient behind the hero" into **one** class no matter how many text runs sit
   on it, and one crop answers a class. S3 emits `indeterminate_classes` alongside `indeterminate`;
   S4 routes classes, never subjects.
2. **Print the deficit.** Every report header carries
   `coverage: {subjects, adjudicated, unadjudicated_by_budget}`. An unanswered question must be
   visible as unanswered, not absent.
3. **Rank by consequence**, not document order — an abstention on a 12-px legend and one on the
   primary CTA are not interchangeable.

⚠️ **U3 decides whether the affordability argument survives at all** (~20 min): histogram
`INDETERMINATE` by `(rule, backdrop_signature)` over 10 real routes. If 95 collapses to ~3, the
architecture holds. If it collapses to ~40, S4's budget is fiction and the whole abstention-routing
premise needs re-sizing.

🚨 **Until U3 answers, none of this machinery is built** (attack ruling A2.8, CONCEDED). **T1 on the
corpus today is 0.** Five triggers, a block ledger, a class collapse and a routing deficit exist to
manage *an empty queue of unknown real size* — which is the definition of an argument rather than a
number. **S4 v1 is ~20 lines: route T2 unconditionally, forward everything else as a fact.** The
ruling above is not withdrawn — it is the correct design *if U3 shows the queue is real and
collapsible*, and it is exactly what gets built then. §6 B19 holds the revival condition. *(The
exemplar→class converter in §1.7 is part of that same deferred machinery, and it is specified now so
that the deferral is a scheduling decision rather than an unsolved contract.)*

### C8 — Fail-closed everywhere composes into fail-never.

Every stage is individually right to refuse rather than guess. Composed, the preconditions multiply
— and every one of them correlates with **liveness**, which correlates with the pages that matter.
The corpus dashboard converges; a production dashboard with a revenue counter and an Intercom iframe
returns `exit 11` and `exit 5` forever. A pipeline whose dominant output on real apps is a refusal
has 100 % precision over an empty set: *sees fine, critiques plausibly, changes nothing* — with a
fail-closed alibi.

**Ruling: no stage may exit non-zero for a reason that invalidates only a SUBSET of findings.** S8
already built the right primitive for one field (`device_scale_factor_pinned:false` forces the
geometric classes to `abstained` with reason `instrument-unpinned` rather than failing the run).
Generalise it to a run-level `degradation.json`:

```jsonc
{ "stability":  "converged" | "drifting",     // was P1 exit 11
  "instrument": "pinned" | "unpinned",        // was P1 exit 20
  "frames":     "single" | "multi",           // was P3 exit 5
  "clamp":      "safe" | "degraded",          // client clamp fired
  "blind":      true | false }                // was the blind pass request-isolated? (C10)
```

| Former exit | Becomes | Which classes abstain | Which stand |
|---|---|---|---|
| P1 `11 UNSTABLE` | `stability: drifting` | every pixel-derived class (X1, X3, ink centroid, diff) | all DOM classes |
| P1 `20 ENV_DRIFT` | `instrument: unpinned` | every geometric + pixel class | token, contrast-solid, AX, containment |
| P3 `5` cross-origin frame | `frames: multi` | findings whose subject is inside the frame subtree | the top document |
| P4 `2` sha mismatch | *stays fatal* | — | — the frame and the facts are not the same render |
| P3 `4` dead CDP session | *stays fatal* | — | — nothing was measured |
| P1 `10 NAVIGATION` | *stays fatal* | — | — the page never loaded |

**Only three exits survive as run failures, and each invalidates everything.** The rest become
per-class abstentions, which is what the ledger was always for.

⚠️ **U2 measures how bad this is** (~30 min): run S1 unchanged over 20 sampled `reso-management-app`
routes against a real dev server with seeded data. P12's stated prediction is **fewer than 12 of 20
converge.** The gate has never been run on any of the 105 real routes.

### C9 — Three images have been called "the global image".

| Image | Geometry | Cost | Question it answers | Caption's prohibition |
|---|---|---|---|---|
| **Gestalt frame** | viewport height, first fold, 2419×1512 (API) | 4,698 tok | *does this page make sense* | none — this is the unbudgeted call |
| **Index frame** | whole page, long edge ≤2000, `eff` ~0.57–0.66 | ~2,200 tok | section order, rhythm, balance — a **table of contents** | `MEASURE NOTHING ON THIS IMAGE` |
| **Squint frame** | 512 px long edge; 14 px text renders at ~5 px, illegible **by construction** | **608 tok** | what does the eye land on first, second, third | *"any finding naming a number, colour value or piece of text is invalid here"* |

**Ruling.** The **gestalt frame is the mandatory one**, and it is the one the measured result came
from — the 2/2 + 3-unasked blind run used a viewport shot, not a full-page stitch. Below-the-fold
content is **its own gestalt call at its own scroll offset**, never a taller image: a 2500 px-tall
shot delivers **0.80× effective detail, worse than a plain DPR-1 viewport shot at any DPR.** The
index frame is optional and its caption is what converts a silent failure into a declared one. The
squint frame is gated on its own probe (§7 U6) and, if it survives, is the only mechanism available
for the pre-analytical glance while the UMSI++ licence is unresolved.

### C10 — Can an agent's conversation run a blind pass? **No, and this is the composition hole.**

P5 builds an elaborate ordering hack (image → image → `Bash --ask` text) because an agent cannot
build a message array — an image arrives only as a `Read` tool_result and the instruction that caused
it necessarily precedes it. The hack is clever and it does not solve the actual problem.

**Blindness is a property of the request.** An agent whose append-only conversation already holds
`plan.json`, `route-plan.json`, and — at turn 3 — `screen.json`, and which looks at the screenshot at
turn 5, **has run the anchored arm while every contract in the pipeline believes it ran the blind
one.** No amount of tool-call ordering fixes that, because the earlier turns are still in the
request.

**Ruling.** S6 issues the blind gestalt pass as its **own API request with its own message list**,
and writes `gestalt.blind.json` + its sha into `run.json` before any fact is shown. P5's `--ask`
ordering remains only for an interactive mode with no API key, and **in that mode the run is stamped
`degradation.blind: false`** and every judgement finding is labelled *unblinded* in the report. That
label is the difference between a limitation and a lie.

### C11 — Per-app stacks. **The measured stack wins, and prose is banned as a source.**

The wave brief said `reso-management-app` = "Next 16 / React 19 / Tailwind 4" and `reso-web-app` =
"Next 13, between the two". P8, P4 and P12 independently read the checkouts and agree the brief is
false in two of three rows; P3 §10 and P5 §7 were written from the brief and are stale.

| App | Measured 2026-08-26 **from `node_modules`** | Consequence this changes |
|---|---|---|
| `reso-landing-app` | Next 14.2.11, React **18.3.1**, Tailwind 3.4.7, purchased template | `_debugSource` **present**; frame API needs the **legacy** `lineNumber`/**`colNumber`** fields |
| `reso-management-app` | Next **16.3.0** installed (16.2.6 declared), React **19.2.8** installed (19.2.4 declared), **Panda CSS 1.9 *and* Tailwind 4.2.4** in one PostCSS chain (`postcss.config.cjs`) | there is **no single token map** — and the Tailwind half has **no token map at all** (`@theme` count = 0 in the app-shell CSS) |
| `reso-web-app` | Next **15.5.24**, React **19.2.8** ← *corrected*, **Chakra 2 + Emotion 11**, no Tailwind, no Panda | class names are runtime `css-<hash>`, **not invertible**; conformance surface is currently 100 % `INDETERMINATE` |

🚨 **This table was itself wrong in three cells, and it is the table whose heading bans prose as a
source** (attack rulings A1.2 / A1.3 / A1.7, all CONCEDED). Corrections, each re-measured above:
**(a)** `reso-web-app` is React **19.2.8**, not 18.2.0 — so **one** of three apps is React 18, not
two, and §1.10's `_debugSource` fast-path rationale rested on this cell. **(b)** The Next 14 frame API
takes `lineNumber`/**`colNumber`**; `column` is not a field it reads. Measured in the shipped bundles:
Next 14.2.11 has 321 `lineNumber` / 29 `colNumber` / 0 `column1`; Next 16.3.0 has 716 `line1` / 672
`column1`. **(c)** `16.2.6` was the *declared* range's floor while `16.3.0` is installed — hence the
`declared`/`installed` split now mandatory in `profiles.json` (§1.0).

**The generalisable lesson, and it is the reason this whole review was worth running:** C11 was
written to stop the pipeline inheriting a false premise from the wave brief, it correctly caught the
brief in two of three rows, and it then **published its own unmeasured row in the fix**. A table that
bans prose must be *generated*, not written — `profiles.json` is now the artifact and this table is
its illustration, not its source. Any cell here that disagrees with a live `dr surface` read loses,
automatically, with no ruling required.

**Ruling.** `profiles.json` (§1.0) is a generated P0 artifact and every stage asserts against it.
Two consequences worth stating separately because they are actionable today:
- **A two-engine app needs an explicit `precedence` or the K-family refuses.** Emitting a confident
  `FAIL` whose truth value depends on which resolver ran is worse than abstaining.
- **`reso-web-app` needs one line of app-side config** — `compiler: { emotion: { autoLabel:
  'dev-only', labelFormat: '[local]' } }` — which costs nothing in production and turns opaque
  hashes into component names, moving that app's modal attribution verdict from `LOW` to `MEDIUM`.
  **This is the single highest-leverage app-side change the whole programme wants.**

### C13 / C14 — Severity and confidence. **The model sets neither.**

P6's finding schema carries `severity: blocker|worth-fixing|nitpick` and `confidence: 0.0–1.0`, both
model-emitted. P7 says severity is a computed two-axis lookup the model never sets, and that a
probability a model produced is never emitted.

**Ruling for P7 on both, with one repair to P6 so it stays buildable.** P6 emits
`impact_claim ∈ {task-blocked, reads-unfinished, cosmetic}` — a *factual claim about user impact*,
which is a legitimate thing to ask an eye. S8's table maps `(impact class × rung) → severity`, and
`blocker` requires `asserted`: **a model alone can never mint one.** That unreachable cell is the
June ruling in code. The swap-recheck gate, which P6 needed severity for, fires on
`impact_claim == task-blocked`.

P6's numeric confidence survives as a **routing-internal** value only: the 0.6 surfacing floor and
the 0.75 adjudicate-close floor. It is never rendered and never appears in `report.json`'s
`confidence` field, which carries S8's evidence-route band. *(Both floors are policy wearing a
measurement's clothes and are marked so — §7 U8.)*

### C15 — Attribution ownership. **P8, and two other tables are stale.**

P6 §8 calls it *"UNOWNED — the biggest hole in the pipeline"*; P7 §8 assigns it to *"P2 extract"*;
P7 §7.4's rendered finding says `source` is *"populated by P2"*. All three predate P8, which owns it,
measured the mechanism out of the actual bundles, and found that the mechanism most attribution
tooling is built on is **dead on React 19**. Correct every reference to **S9**.

### C16 — Contrast over a gradient. **Settled deterministically; it must leave the vision queue.**

P2's duty generator lists `findings_dom INDETERMINATE` at priority 100 and gives the gradient as its
example. But the cross-check settles that case at zero model cost (4.81:1 left third, 1.57:1 right),
and P5 and P6 both say so. As written, P2 spends a 3,200-token crop re-asking a closed question.

**Ruling.** The duty source is `INDETERMINATE − resolved_by(xcheck)`, **gated on the xcheck file
existing** (C8's third row). P5 states the failure mode exactly and it is worth repeating as the
rule: *the subtraction is code, not discipline* — new rules will add new abstentions and nobody
re-runs the subtraction by hand.

### C17 — Three gate flags. **One gate.**

P3 claims it "may block CI", P4 ships `--gate`, P7 ships `--exit-on-blocker`, P11 ships
`dr review --gate` mutually exclusive with `--judge on`.

**Ruling: P11's is the sanctioned CI wiring and the only one.** It computes the exit code in a frame
that **never reads `judge/` or the `advisory` rung** — so a future edit wiring a judgement finding
into an exit code has to *delete that isolation*, which is a reviewable diff rather than a drift.
P3's and P4's flags survive as debugging affordances and are documented as not-for-CI. CI gates on
exactly what scored **9/9 with zero control false positives**, gates on nothing marked
`INDETERMINATE` (an abstention in CI is a PR comment, never a red), and needs no API key.

### C18 — The false-positive claim. **We have not measured zero. We have measured "below 37.5 %".**

🚨 **REWRITTEN 2026-08-26 under attack ruling A2.3 — the denominator was wrong, in six places, and it
is the number the entire ship-gate argument rests on.** This section previously computed from
**n = 13** and reported a **23.1 %** bound. The blind judge run was over **8 pages**, not 13:
`bench/corpus/out/blind_key.json` holds exactly eight entries (`page-A`…`page-H`, H clean), and
`README.md:30` labels that row *"Claude vision, blind (8 pages, no ground truth)"*. The corpus
**builds** 13 variants; the judge **saw 8**. Corrected arithmetic:

| | Was (n = 13) | **Is (n = 8)** |
|---|---|---|
| 95 % FP upper bound, rule of three | 3/13 = **23.1 %** | **3/8 = 37.5 %** |
| Novel-TP rate | 0.231 / page | **0.375 / page** |
| Position vs the ~20 % credibility cliff | 1.16× over | **1.9× over** |

**Nothing about the design changes. Everything about its urgency does.** 23.1 % was *marginally* over
the abandonment line — close enough that a reader could treat it as a rounding argument. **37.5 % is
nearly twice the line**, and every sentence in this document of the form *"bounds the rate below
23 %"* was false when written. The remedy was already correct and is unchanged — it is now the
gating item rather than a Tier-1 one:

**Ruling, three separable claims that must stop being one:**
1. **Absolute zero on the control is the ship gate** and it is enforceable at n = 1. A rule that
   fires on a page with no defect will fire on every page. Keep it, no exceptions, no baseline-diff
   suppression.
2. **No false-positive *rate* may appear in any report or README below n = 16 clean pages.**
   3/16 = 18.75 % is the first n strictly under the cliff. *(P7 derived n ≥ 16 independently, from
   the correct reasoning, before anyone had checked which n we actually had — the one place in this
   programme where the discipline outran the measurement.)*
3. **State the budget per 1,000 subject-checks, never per run.** P4's census is 1,841 subjects on
   *one page*; across 105 routes that is ~193,000 subject-checks per audit. A per-subject FP rate of
   1×10⁻⁴ — twenty times better than anything measured anywhere in this substrate — still yields
   **~19 false findings per audit**, delivered to an agent that acts on them by editing source.

⚠️ **And the corpus those eight pages came from is 35× smaller than the target, per page.** Every
number in this substrate — 9/9, 0 FP, 2/2, 3 unprompted — was measured on **thirteen 106-line,
52-element HTML files generated from one template** (`bench/corpus/build_corpus.py`), against a
real-page census of **1,841 subjects on one page**. *Zero false positives was measured at 1/35th the
subject density of the target*, and FP supply grows with subject count, not with page count. This
risk applies to the one-screenshot null exactly as much as to the pipeline — but **the pipeline
multiplies exposure by rule count** (G/T/K/A/O families plus six cross-checks, against the spine's
one file), which is the strongest argument in this document for shipping the spine and making every
later family buy its way in.

**Ruling, three separable claims that must stop being one:**
1. **Absolute zero on the control is the ship gate** and it is enforceable at n = 1. A rule that
   fires on a page with no defect will fire on every page. Keep it, no exceptions, no baseline-diff
   suppression.
2. **No false-positive *rate* may appear in any report or README below n = 16 clean pages.**
   3/16 = 18.75 % is the first n strictly under the cliff.
3. **State the budget per 1,000 subject-checks, never per run.** P4's census is 1,841 subjects on
   *one page*; across 105 routes that is ~193,000 subject-checks per audit. A per-subject FP rate of
   1×10⁻⁴ — twenty times better than anything measured anywhere in this substrate — still yields
   **~19 false findings per audit**, delivered to an agent that acts on them by editing source.

And the instrument that fixes it is nearly free: **mine ~315 clean screens from the three apps' own
git history** — pages that shipped and were never subsequently touched by a visual-bug fix. Every
finding on that set is a false positive **by construction, at zero labelling cost.** This is the
cheapest decisive experiment in the wave and no stage owns it. **§6 assigns it as `B0` — the FIRST
item built, ahead of the spine's own stages, and the spine is not "shipped" until it has run clean
over B0.** *(It was Tier 1 `B7` before the 2026-08-26 attack; the corrected denominator is what
promoted it — a 37.5 % bound is not a thing to schedule behind eight other builds.)*

### C19 / C20 / C22 / C23 / C24 / C26 — the short rulings

- **C19 coordinate frames.** A crop finding's coordinates are in crop space; page space needs the
  crop rect × DPR × scroll offset, three multiplications owned by three stages, none carried on the
  finding record. An off-by-one returns a node one row up in a table — real element, real file,
  wrong answer, and `DOM.getNodeForLocation` reports no error. **Forbid the model from emitting
  coordinates at all**; it names a region label, and attribution is a join. S8 gains
  `coordinate-frame-unproven`.
- **C20 budget breach.** RT's scheduler drops **whole cells**, lowest-priority first, and never
  truncates a cell mid-chain: a cell with a global call and no crop pass is the
  18.9 %-not-48.1 % configuration. P2's "wave 2 in a fresh context" and P5's "split to a subagent"
  are agent-path affordances, not the scheduler.
- **C22 naming.** P1 calls the motion owner "P5". It is **S7**. See §0.2.
- **C23 frames.** `--frames=merge` is the only production mode; frame nodes are extracted with
  translated bounds but **excluded from the page histograms**, because a third-party embed's spacing
  scale is not this app's. `strict` (exit 5) never runs in production.
- **C24 the live-browser conflict — an architectural correction, not a preference.** P4's X1/X2 arms
  call `Page.captureScreenshot` and `Runtime.callFunctionOn`; P11 declares `dr screen` "separate;
  reads files only, no browser". Both cannot be true. **Ruling: the differential probes move into
  S1b, inside the capture process.** This preserves S2's same-frame invariant *and* keeps S3
  embarrassingly parallel, and it is the only placement in which the ink mask describes the frame
  that was photographed.
- **C26 coverage floors.** P13's exit 3 ("a declared axis has 0 captures") folds into RT's exit 2
  `PARTIAL` with the specific marker in `coverage.json`. One exit table for the whole binary.

---

## 2A. The adversarial review of 2026-08-26 — every ruling

Two reviewers attacked this document independently: **A1 on buildability** ("can a competent engineer
build this?") and **A2 on value** ("is this ceremony against a one-screenshot null?"). Both ran their
claims against the machine rather than against the prose, and **most of what they found was true.**
This section is the permanent record: a spec that survived an attack has to say *which* attack and
*why it survived*, or the objection returns next quarter carrying the same evidence.

**The rule for re-raising anything below: a `REFUTED` row may be re-opened only with evidence that did
not exist on 2026-08-26.** Re-asserting the original argument is not new evidence.

### 2A.1 Buildability (A1)

| | Claim | Ruling | Where it landed |
|---|---|---|---|
| **A1.1** | Read clamp is 2000×2000 / 3,932,160 B, and the ladder is palette→JPEG→resize | **CORROBORATED**, then extended against us | §1.1 — the constant was right, the *model* of it was one-dimensional → A1.4 |
| **A1.2** | `reso-web-app` is React **19.2.8**, not 18.2.0 — so **one** of three apps is React 18, not two | **CONCEDED** | §1.10, §2 C11 — the fast-path rationale was built on a false cell |
| **A1.3** | `src/app/globals.css` contains **0** `@theme`; the Tailwind engine has no token map | **CONCEDED** | §1.0 — new `token_map: ABSENT` state; C11's headline consequence cannot occur as described |
| **A1.4** | `fg.muted` × 263 reproduces at **no** scope (221 / 223 / 427); `337` is right only under `src/` | **CONCEDED** | §1.10 — every count now carries its glob |
| **A1.5** | The state ledger's denominator is 16 `page.tsx` under `(app)`, but the app has **105** | **CONCEDED** | §1.0 — *the numerator is 0 at both scopes, so the finding got stronger*; the unnamed denominator was still the defect |
| **A1.6** | `Page.Viewport` is `{x,y,width,height,scale}`, not `{w,h}`; `DOMSnapshot`, `getFullAXTree` and two `include*` flags are `experimental` | **CONCEDED** | §1.6 (a build-stopper in a code fence), §1.12, §4.1(n) |
| **A1.7** | Next 14 uses `lineNumber`/**`colNumber`**; installed 16.3.0 ≠ declared 16.2.6 | **CONCEDED** | §1.0 `declared`/`installed` split, §2 C11 |
| **A1.8** | §8's cost row is off ~4× against §8's own constants | **CONCEDED** | §8 — the row is now derived, and the derivation is shown |
| **A1.U1** | The Route C predicate DSL has no grammar, no evaluator, no bindings — and demands numbers through a schema built to forbid them | **CONCEDED — Route C DELETED** | §1.9, §1.7 |
| **A1.U2** | C7 routes *classes*; §1.7 forbids >1 INDETERMINATE per call. A class **is** a set of them | **CONCEDED** | §1.7 — explicit exemplar→class converter, and class-generalised findings may never be `asserted` |
| **A1.U3** | `backendNodeId` is a renderer-side handle; three stages keyed run-to-run identity on it | **CONCEDED** | §1.9 — `target_key` is now the identity; `backendNodeId` demoted to a transient field |
| **A1.U4** | `read_class`/`eff_read` model only the resize arm; "geometry intact, colour destroyed" was inexpressible | **CONCEDED** | §1.1 — `read_colour_class` |
| **A1.U5** | RT's exit-code isolation is already violated by §1.9's Route C | **CONCEDED** | dissolved by deleting Route C; §0.1's claim is now true rather than aspirational |
| **A1.U6** | The driver is never named; Playwright and raw CDP are mixed across nine sections | **CONCEDED** | §1.12 |
| **A1.0** | *"Buildable spine, unbuildable adjudicator"* — everything from S4 on is prose naming artifacts without typing them | **PARTIALLY CONCEDED** | The diagnosis is right and the prescription was already this document's §6: the spine is Tier 0, S8 is Tier 2. What was missing is that a reader could not *tell* — so §6 now carries a **specification-completeness** column, and no stage may be built from a `PROSE` row |

### 2A.2 Value, against the one-screenshot-one-prompt null (A2)

| | Claim | Ruling | Where it landed |
|---|---|---|---|
| **A2.1** | "Full-page screenshot" is the wrong image — full-page `eff` = 0.80, worse than a DPR-1 viewport shot | **REFUTED as an attack — the spec already ruled this** | §2 C9 and §8 both say it, and the measured run used a viewport frame. Kept as written; the attack corroborates C9 against the null |
| **A2.2** | "Plus the fact-pack" is an untested arm, not the baseline; ship blind until U5 answers | **REFUTED as an attack — this is already the design** | §2 C3 calls U5 *"the pipeline's central bet"*, and Tier 0's B5 is blind-only. Tightened, not changed: B5 now says **blind-only, no fact-pack, until U5** in the build row itself |
| **A2.3** | The FP bound is computed on the wrong denominator — n = 8, not 13 → **37.5 %**, not 23.1 % | **CONCEDED — the most consequential fix in the review** | §1.9, §2 C18, §5.1, §5.2 |
| **A2.4** | The corpus is 35× too small in subject density; **B7 should outrank Tier 0** | **PARTIALLY CONCEDED** | The density argument is CONCEDED into C18. The ranking is **refuted on sequencing**: a corpus with no detector produces nothing, so B7 becomes **B0 — first item inside Tier 0**, and the spine's ship gate is a run *over* B0. Ordering, not tier |
| **A2.5** | S1: ship the pinning flags; make the stability **gate** an advisory abstention | **CONCEDED** | §6 B1 — and it was already C8's own logic, applied inconsistently to its own capture stage |
| **A2.6** | S3, X3, S6-blind, S0+S10, `.design-exceptions.jsonl` all earn outright | **AGREED** | Unchanged; each is Tier 0 or Tier 1 already |
| **A2.7** | S5 DECOMPOSE is ceremony — do not build | **CONCEDED** | §6 — S5's *planning* half is cut from the core pipeline; what remains is a re-clip utility. §2 C2 already killed the transfer argument; this finishes the job |
| **A2.8** | S4 ROUTE is ceremony at current volume — replace with ~20 lines, "route T2 unconditionally" | **CONCEDED** | §6 — S4 v1 **is** the 20-line form; the five-trigger machinery is Tier 3, gated on U3 |
| **A2.9** | S1b INK-PROBE: defer — it exists to fix a swamping bug in X1, and X1 has **zero** true positives | **CONCEDED** | §6 Tier 3 — build it when X1 finds one |
| **A2.10** | S7: defer, but extract the one grep that is its real finding | **CONCEDED** | §1.0 — `prefers-reduced-motion` (management 338, web **0**, landing **0**) is now a SURFACE `find` |
| **A2.11** | S8 is half-earned: the dedup key is measured, the predicate DSL is a compiler with no programs | **CONCEDED** | Converges with A1.U1 — the key survives, Route C is deleted |
| **A2.12** | S9 ATTRIBUTE is the weakest "earns" — mechanism measured, value not | **PARTIALLY CONCEDED** | Stays in Tier 1 (it is the only answer to *"changes nothing"*), but §6 now states **the number it must produce**, and its own facts are corrected per A1.2/A1.4 |
| **A2.0** | Seven of thirteen stages name an argument rather than a number, and by §5.2's own rule that is ceremony | **CONCEDED — and it is this document's own governing rule turned on itself** | §6 is restructured so the core pipeline contains only stages that name a measured number. See §6.0 |

### 2A.3 What the attacks did NOT touch, and why that matters

Neither reviewer challenged: the three-substrate separation (§0.3), the **judge-may-not-emit-numbers**
rule, the `INDETERMINATE`-is-the-product design, never-delete deduplication, the D4 abstention ruling
(a confident false PASS at 10.36:1 where the text sits at 1.22:1), the `UNREVIEWED` block, or the cut
of local VLMs and learned detectors. A2 independently re-derived §2 C18's *"~19 false findings per
audit"* and §2 C9's full-page-`eff` ruling from the same evidence and reached the same conclusions.
**The architecture survived; the arithmetic and the stage inventory did not.**

---

## 3. Designs changed by refutation or by the substrate

Distinct from §2: these are not stage-vs-stage disagreements, they are places where a stage's own
design does not survive contact with a measurement.

| | Was | Is now | What refuted it |
|---|---|---|---|
| **D1** | S5 plans an exhaustive 12-crop cover as the default | ≤2 crops, global-pass-driven only; the cover is `--sweep`, gated on U4 | ScreenSeekeR transfer invalid (0 web screenshots, point-in-box, inverse task) **+** 4 of 5 unique findings are page-global quantifications |
| **D2** | X1 ink mask from the crop's **modal colour** | from S1b's **differential render** | on a round button the square crop's corners count as ink and swamp a 16 px glyph |
| **D3** | X2 centroid measured against the element's **own** post-transform box | against the **container's content box**, and **still ships OFF** | a `translate` moves box and ink together, so the number is *invariant under the compensation it claims to verify* |
| **D4** | Adopt `blendedBackgroundColors` as the contrast operand | adopt the **value**, gate the **kind** on an independent 12-deep ancestor walk, abstain on any varying backdrop | measured 10.36:1 reported where the text sits at **1.22:1** — a confident false PASS, strictly worse than an abstention |
| **D5** | Dedup key `(rule, target)` | `(defect_class, backendNodeId, observable_bucket)`, and dedup **links** rather than deletes | the key swallowed a real colour-token drift; 0/1 → 1/1 once widened |
| **D6** | Attribution via `__source` / `_debugSource` | owner-stack → `__nextjs_original-stack-frames`, with `_debugSource` as a **fast path under** it | React 19.2.8: `_debugSource` 0 occurrences; `jsxDEV` args 5/6 are now `debugStack`/`debugTask` |
| **D7** | `<=1000×1000 CSS @2` is the lossless crop | `966×966`, and both the clamp *and* the token predicate are asserted | 2000×2000 = 5,184 tok, over the 4,784 tier — the API resamples a "clamp-safe" image |
| **D8** | Verdicts enter the judge because they are cheap | values enter; verdicts enter adjudication only; `unprompted` is non-fungible | crowding-out is *arithmetic* under `maxItems 7`, and 16–39 % reversals from reordering refute the inert-prior null |
| **D9** | Every precondition failure exits non-zero | a degradation vector; three exits survive | fail-closed at every stage composes into fail-never on exactly the live pages that matter |
| **D10** | The abstention set is small, so vision is affordable | abstentions are **collapsed by class**, and the routing deficit is printed | 95 abstentions on one page against a budget of 2 |
| **D11** | "Our zero-FP baseline" | absolute-zero is the ship gate; no *rate* below n=16; budget per 1,000 subject-checks | rule of three: **3/8 = 37.5 %** (corrected from 3/13 = 23.1 % — see D21), nearly 2× the 20 % abandonment line |
| **D12** | Per-app behaviour keyed on a profile **string** | `profiles.json`, generated by reading the repo, with per-engine maps + explicit precedence | the wave brief was false in two of three rows and eleven specs inherited it |
| **D13** | The blind pass is "pass 1" in a conversation | the blind pass is a **request** S6 owns; otherwise the run is stamped `blind:false` | an append-only conversation that read the findings has already run the anchored arm |
| **D14** | `reducedMotion: reduce` for determinism | `no-preference` default, `reduce` as an additional cell | determinism was already achieved without it; `reduce` photographs a page most users never see |
| **D15** | S3 runs the differential probes | S1b runs them, inside the capture process | S3 must be file-in/file-out to stay parallel, and the probe needs a live page |
| **D16** | Model emits severity and confidence | model emits an `impact_claim`; S8 computes both | the reliability numbers apply to graded judgement *more* than to binary judgement |
| **D17** | Rubric scoring / any design score | rubric **tree** for coverage; **no** score, rank, grade or rating anywhere | 16–39 % top-1 reversals from reordering alone; α = 0.248 among designers on preference; V1 plateaued at 78/100 on a self-assigned scale with no external referent |
| **D18** | A model finding can reach `asserted` via **Route C**, an AST-allowlisted predicate DSL | **no model finding is promotable by any route**; `advisory` is terminal, and a model that wants a number emits `needs_measurement` so **S3 grows a rule** | the DSL had no grammar, no evaluator and no bindings, demanded numbers through a union built to forbid them (§1.7), and silently pierced the RT exit-code isolation §0.1 calls mechanical |
| **D19** | Run-to-run identity is the `backendNodeId` the browser issued | `target_key = sha1(dom_path ‖ stable_attrs)`, minted once by S2; `backendNodeId` is a transient in-process handle no key may read | CDP defines it as a renderer-side id for a node *"that may not have been pushed to the front-end"* — it survives neither S7's proc B nor S9's dev-server run, and §4.3's `selector_absent` falsifier presupposed a selector no stage produced |
| **D20** | The `Read` clamp is one axis: `clamp: safe \| degraded` | **two** axes — `read_class` (geometry) and `read_colour_class` (`intact \| quantised-256 \| jpeg-<q>`) | the client ladder quantises a ≤2000 px master to **256 colours at full resolution** when it merely exceeds 3.75 MiB, so `eff_read` reads 1.0 while every colour claim is void — and the management app ships a generated P3 accent layer |
| **D21** | FP bound = 3/13 = 23.1 %, *marginally* over the ~20 % cliff | **3/8 = 37.5 %**, nearly **2×** the cliff; the mined clean corpus is promoted to **B0**, the first thing built | `blind_key.json` holds 8 entries and `README.md:30` says "8 pages" — the rate was computed over the corpus's *build* count, not the run's *trial* count |
| **D22** | Thirteen stages, each adding capability | **five** stages in the core pipeline; the rest are optional tiers that must buy in with a measured number | seven of thirteen stages named an argument rather than a number, which §5.2's own governing rule defines as *"overhead wearing a contract"* |

**Two things that were proposed and are cut outright**, because the evidence forbids them rather
than merely disfavouring them:

- **Any local VLM in the detection path.** Measured on this Mac: correct at 1 of 3 resolutions,
  **invented a misalignment at the other two**, 21–66 s per screenshot, accuracy non-monotonic in
  resolution. A detector that invents defects is worse than no detector, because an agent acts on
  them. (A local model earns a place only in bulk *screening* where a 50 % hit rate is acceptable
  because a second pass adjudicates. We do not have that workload.)
- **Any learned GUI element detector.** Best measured F1 **0.438 at IoU > 0.9** — on a 200×48 button
  that still permits ~5 px of boundary error — against `getBoundingClientRect`, which is exact and
  free. The failure *shapes* decide it: classical CV fails by returning an obviously wrong number, a
  learned model by returning a plausible one, and the consumer is an agent that will act.

---

## 4. What this pipeline does not see — and how it says so

A pipeline that cannot state what it did not look at is not advisory, it is misleading. The June
2026 ruling makes **coverage** a correctness claim, so this section is inside the gate: S10 may fail
a run for *lying about coverage*, and may never fail one for taste.

### 4.1 The blind spots, by why they are blind

**(a) Never photographed.** The largest and least visible class. P13's worked example on the
management app: **18 of 288 tuples captured (6.3 %)** — `theme=light` 0/144, `data=empty` 0/96,
`viewport=390x844` 0/96. And of 288 tuples, only **96 are reachable without a human** writing auth
and seed fixtures. *A review of the logged-out homepage at 1440 px reviews the marketing screenshot,
not the product.*

**(b) Absence with no denominator.** Named states (`loading` / `error` / `not-found`) are a `find`,
so they have a denominator and are reported as a percentage. **Unnameable absence — "there is no way
to undo this", a caption whose referent does not exist — has no denominator, so no coverage number
over it is admissible and the pipeline must never print one.** Opus 5 produces this class unprompted
at roughly **3 per 8 blind pages** with zero false positives *(corrected from "1 per 13" — A2.3; the
blind run was 8 pages, and three of its unprompted findings were of exactly this class)*; it is real,
it is valuable, and it is unmeasurable.

**(c) Below the perceptual threshold, from the judge.** Measured 0/2 (a 1 px misalignment, a 5/255
colour drift). This is not a gap to close; the gate here is **precision, not recall** — the claim
must land in `needs_measurement` or not exist.

**(d) Interiors.** `<canvas>`, WebGL, `<video>`, raster and SVG contribute a width and a height.
`@react-three/fiber` in the management app is invisible to *every* DOM instrument and additionally
defeats the byte-stability gate.

**(e) rAF-driven motion.** `document.getAnimations()` returns WAAPI only. Measured rAF-capable
sources in **all three apps** (`framer-motion` 7 and 11, `motion` 12, `@react-three/fiber` 9,
`react-slick`). "0 animations found" on such a page is the canonical false green.

**(f) Virtualised rows below the fold.** `captureBeyondViewport` renders one pass at scroll 0;
recycled rows do not exist to be rendered.

**(g) Everything Chromium-only.** No cross-engine divergence is measured or approximated.

**(h) Colour gamut — and this is systematic on one app, not a footnote.** Chromium rasterises to an
untagged sRGB buffer and clips P3 before the file exists — `color(display-p3 1 0 0)` and `#ff0000`
both encode to `(255,0,0)`. A screenshot cannot testify about gamut. **`reso-management-app` ships a
generated P3 accent layer** (`src/app/mc-p3.generated.css`), so its accent colours are exactly the
population this blindness covers, and they are *also* the population the `Read` client's 256-colour
palette arm destroys (§1.1, `read_colour_class`). **Two independent colour blindnesses stack on one
app's brand colours**, and the report must name which one fired rather than reporting a colour result.

**(i) Production builds.** `_debugOwner` / `_debugStack` are stripped, so attribution degrades to
CSS-side evidence and caps at `LOW`.

**(j) Second-order consequences with no detector.** A clean `regress.json` means *no change on the
rules we run*, **never** *no harm done*.

**(k) Whether the declared task is the WRONG task.** Product judgement, in no artifact on disk.

**(l) False negatives, structurally.** The FP budget cannot see them; the corpus is a closed world
by construction. The only instrument pointed at this is the *novel-finding rate* (§7 U7).

**(m) Taste.** By ratified decision, and because the construct's own inter-rater reliability among
designers is **α = 0.248** — a threshold on it would be a threshold on noise.

**(n) The measurement substrate is EXPERIMENTAL protocol surface.** *(New — attack ruling A1.6.)* The
`DOMSnapshot` domain, the `Accessibility` domain, `getFullAXTree`, and the
`includeBlendedBackgroundColors` / `includeTextColorOpacities` flags are all declared
`experimental: true` in `browser_protocol.json`. Everything §1.3 calls the abstention substrate — D4's
contrast ruling, X3, and the `measured + indeterminate === textRuns` invariant that makes the
three-valued design honest — depends on fields Chromium may rename or drop in a point release. There
is no non-experimental alternative (the measured ones are 881 ms and 5,788 ms), so this is a
**dependency risk to detect, not a design to change**: `dr extract` asserts each flag's presence in
the *response*, because Chromium silently ignores unknown request params rather than erroring — the
canonical false-green shape. A missing field writes `degradation.substrate: reduced` and abstains the
dependent classes. **The failure this prevents: a protocol rename turning every contrast question into
a silent pass, with no error anywhere in the run.**

**(o) The corpus this pipeline was graded on is 35× less dense than its target.** *(New — attack
ruling A2.4.)* Thirteen 106-line, 52-element generated HTML files against 1,841 subjects on one real
page. Every recall and FP number in §5.1 inherits that, and FP supply scales with **subjects**, not
pages. This is not closed by any stage; it is closed by **B0** (§6), which is why B0 is the first
thing built.

### 4.2 The labelling mechanism — five surfaces, all generated, none prose

1. **`coverage` on `report.json`**: `full | affected | sampled | full-fallback`. **No default.**
   A sampled run opens `report.md` with `⚠️ SAMPLED — 12 of 84 affected routes reviewed. This run
   cannot support a "no regressions" claim.`
2. **The closed census**, asserted at exit: `pass + fail + indeterminate + out_of_scope == subjects`,
   plus `unadjudicated_by_budget`. A coverage claim is arithmetic over a population the stage
   *enumerates*. The March corpus's *"60 % of visual checks are fully automated"* had 15 items over
   one 25-item checklist for a page that no longer exists — an unfalsifiable denominator.
3. **`degradation.json`** (§2 C8), consulted per finding class, so a partial instrument produces
   *named abstentions* rather than either a refusal or a silent pass.
4. **The report header, which can never render "clean."** It renders
   `ASSERTED n · UNVERIFIED n · ADVISORY n† · baseline/merged/rejected n`, and **abstentions sit
   above advisories** — a known hole outranks an opinion. Each abstention names *why* it could not be
   settled and *which stage owns the retry*.
5. **The `UNREVIEWED` block**, prepended verbatim, every line a count over an enumerated set or a
   named absent capability:

```text
UNREVIEWED — what this report did not look at
  surface     18 of 288 tuples captured (6.3%). Not captured: theme=light (0/144),
              data=empty (0/96), viewport=390x844 (0/96).
  instrument  pinned ✓ · clamp safe ✓ · stability CONVERGED · blind pass REQUEST-ISOLATED ✓
  intent      anchored — docs/design-system/CONSTRAINTS.md @ 4f1c…, VOICE_AND_CONTENT.md @ 9ab2…
  task-fit    asked on 3 of 12 routes; 9 routes have no declared task and were not asked.
  absence     named states checked deterministically (16 routes x 3 states).
              Unnamed absences are NOT measurable — no recall figure exists for this class.
  abstentions 95 subjects in 3 classes; 3 adjudicated, 0 unadjudicated_by_budget.
  motion      WAAPI set covered. 2 rAF sources uncovered (motion@12, @react-three/fiber@9) —
              a clean motion result is not evidence of correctness for them.
  glance      squint pass RAN. Saliency NOT RUN (UMSI++ licence unresolved) — no attention-mass
              claim in this report is measured.
  precision   sub-perceptual defects (<2px, <8/255) are outside the judge's measured ability
              (0 of 2) and outside the DOM layer's (INDETERMINATE, not PASS).
  suppressed  4 known-and-accepted findings hidden; 0 falsifiers fired. --all to see them.
  taste       NOT ADJUDICATED. No score is produced, by ruling (June 2026).
```

**Anything the pipeline cannot verify says `NOT RUN` or `NOT MEASURABLE`, never nothing.** That is
the whole defence against the failure this block exists to defeat: a fail-safe default whose output
is indistinguishable from the healthy state. And it is **prepended**, not appended — a verdict placed
last is read after the decision has already been made.

### 4.3 The exception channel, which does not exist today and must

Measured: a grep for `design-ok|@design-allow|design-lint-disable|design-exempt` across **all three
apps returns nothing.** So every intentional violation this pipeline finds will be re-reported
forever, starting on run two — and against a ~20 % credibility budget, **a re-reported
known-and-accepted finding spends exactly the same credibility as a wrong one, even though it is
true.** This is the mechanism the previous generation of this tool died for lack of: built in a
two-day burst, then zero substantive change in five months.

`.design-exceptions.jsonl` lives **in the repo, beside the code**, one appended object per line,
with a **required prose `why`** (an exception with no stated reason is indistinguishable from a
finding someone got tired of) and a **`falsifier`** — `selector_absent | rule_span_changed |
intent_sha_changed` — so it **expires by event, not by date**. The default report shows only `new`
and `regressed`; `known`, `suppressed` and `fixed` render as counts.

---

## 5. The honest ceiling

"100th percentile" is unfalsifiable as written. The operational restatement, which is what this
pipeline is actually built to satisfy:

> On every defect class where a human designer is the reference, find what the best human finds; on
> every class where humans are structurally blind (1 px, 5/255), find what no human finds; and on
> every class where it can do neither, **say so** rather than passing.

Two different bars, and a third obligation. A single score over them would be meaningless.

### 5.1 What to expect, per class

| Class | Recall to expect | FP | Evidence for that number |
|---|---|---|---|
| DOM-determined: spacing, alignment ≥1 px, token drift, type scale, grid, contrast-solid, overflow, target size | **~1.00** | **0** | measured 9/9, 0 control FP, 80 ms/page. It is arithmetic over `getBoundingClientRect` and computed styles. |
| Contrast over gradient / image / composited backdrop | **~1.00**, deterministic, no model | **0** | measured: 4.81:1 left third vs 1.57:1 right, zero findings on the control |
| Named-state absence (`loading`/`error`/`not-found`) | **1.00** | **0 by construction** | it is a `find`. Measured: **0 `loading.tsx` against 16 `page.tsx` under `src/app/(app)`, and 0 against 105 across all of `src/`** — the glob is part of the claim (A1.5) |
| Motion timing over the **WAAPI** set | **~1.00** | low | every asserted property is already an exact number in the animation model |
| Judgement / gestalt: hierarchy, grouping, content-fit, affordance, readability | **0.50 – 0.66** | 0 measured, **bounded only at 37.5 %** | our 2/2 is **n = 2**. The nearest published ceilings are WebDevJudge best model **66.06 %** (humans 84.82 %) and DiffSpot best-of-13 **47.2 %**. Gate at ≥0.50 — above the best published result on the closest task, well under the human ceiling. |
| Novel / unprompted findings (no rule was looking) | **~0.375 per page** | 0 measured, **bounded only at 37.5 %** | 3 real defects across **8** blind pages (not 13 — A2.3). **This is the capability nothing else here has, and it is also the most fragile** — anchoring, cropping and `maxItems` each threaten it independently. |
| Sub-perceptual (≤2 px, ≤8/255) **from the judge** | **0.00 — expected, and not gated** | **gate is precision = 1.00** | measured 0/2 blind; the local model's failure was *inventing* one at 2 of 3 resolutions. Below the threshold the gate is on **abstention, not detection**. |
| Sub-perceptual **from the DOM layer** | **1.00** | 0 | this is the half humans cannot do; a 5/255 drift is ΔE ≈ 0.6, below the JND |
| Unnameable absence (orphan legend class) | **no figure is admissible** | 0 measured | there is no denominator for the set of things that do not exist |
| rAF-driven motion | **0.00**, named | — | invisible to `getAnimations()`; present in all three apps |
| Second-order consequence **prediction** | **out of reach** | — | DiffSpot 47.2 % is the ceiling on the *easier* direction (the change is shown, not hypothesised); hard-tier recall <23 % for every model; `line-height` median recall **4.0 %** |
| Second-order consequence **verification** | reachable | — | re-run and diff — measurement, not prediction |
| Attribution to `file:line` | `HIGH` requires 100 % exact-line; **`MEDIUM` is the modal verdict** | ≤20 % over-abstention budget | **337 files under `src/` import `styled-system/css`; `fg.muted` appears 221 times under `src/`** (223 with `styled-system/`, 427 tracked-repo-wide — the old "263" reproduced at no scope, A1.4). A stage reporting `HIGH` there would be lying by construction, at every one of those scopes. |
| Taste / preference | **not attempted** | — | ratified June 2026; α = 0.248 among designers |

### 5.2 The three sentences someone should actually take away

**1. On our own corpus the ceiling is 11/11, and ~430 lines of Python plus one prompt already reach
it.** `detect_dom` (9/9) + `detect_xcheck` (the gradient) + one blind judge call (2/2 plus 3 nobody
injected), all at zero false positives. **Expected marginal recall from the other nine stages on
this corpus: 0.0.** Everything above the spine buys things the corpus does not contain — states,
motion, absence, real-app scale — and **actionability**, which is a different axis from recall and
is the one A15 predicted we would fail on. *The 2026-08-26 value attack accepted this sentence and
then pointed out we had not acted on it: seven of thirteen stages named an argument rather than a
number. §6 now enforces it.*

**2. The false-positive claim is a bound, not a measurement — and the bound is nearly 2× the
abandonment line, not marginally over it.** 0 FP over **8** blind pages gives a 95 % upper bound of
**37.5 %**, against the ~20 % at which an AI reviewer loses credibility regardless of catch rate.
Until the mined clean corpus exists, the honest sentence is *"we have measured no false positives on
8 pages and one control, which bounds the rate below 37.5 %"* — never *"zero false positives"*, and
never the **23.1 %** this document carried in six places until the denominator was checked. **The
number came from the corpus's build count (13) instead of the run's trial count (8), and no reader
could have caught it without opening `blind_key.json`** — which is precisely why B0 is now the first
thing built and why no rate may be quoted below n = 16.

**3. The dominant risk is not missing a defect; it is a confident clean report over a page nobody
photographed.** 6.3 % of one app's tuple universe was captured in P13's worked example, and
fail-closed preconditions correlate with liveness, which correlates with the pages that matter. That
is why §4's labelling is not documentation — it is the deliverable that makes the rest safe to act
on.

### 5.3 The single assumption most likely to be wrong

**That the composition is additive.** Every stage spec is written as though its stage adds
capability to a growing total. Measured, the total is already 11/11, and from there a stage can only
*subtract*: by consuming the image blocks the global pass needs, by refusing on the pages that
matter, by dropping honest abstentions into silent passes, by cropping away four of the five findings
only this judge produces, by anchoring the fifth out of the output, or by minting the nineteenth
false positive in an audit and losing the operator. **Each of those is a good stage doing its job.**

Therefore the governing build rule in §6: **no stage ships until it beats the spine on a stated
number**, and a stage that cannot name the number it improves is overhead wearing a contract.

🚨 **On 2026-08-26 a reviewer applied that rule to this document's own stage list and found seven of
thirteen stages fail it.** This section named the assumption, §6 stated the rule, and the inventory
above them both still carried thirteen stages — *the rule was written and then not run*. §6.0 now
runs it: the core pipeline is **five** stages, every optional tier carries the number that revives
it, and §6 gained a `number` column so a future stage cannot enter without one. **The assumption most
likely to be wrong turned out to be wrong in the document that identified it**, which is the strongest
available argument for keeping §6.0's column rather than trusting the discipline.

---

## 6. Build order, ranked by measured leverage

Ranked by *evidence per unit of build*, not by pipeline order. Anything whose leverage is an
argument rather than a measurement is below anything whose leverage is a measurement.

### 6.0 The admission rule, and the two columns that enforce it

*Restructured 2026-08-26 under attack ruling A2.0, CONCEDED.* §5.2 already stated the governing rule
— **"a stage that cannot name the number it improves is overhead wearing a contract"** — and the
value attack applied it to the stage inventory and found **seven of thirteen stages name an argument,
not a number.** Scored by this document's own rule, those seven are ceremony. So the inventory is
now split by that rule rather than by pipeline order, and two columns make the split checkable:

- **`number`** — the measured quantity this build improves, or **`ARGUMENT`**. A row reading
  `ARGUMENT` may not enter the core pipeline, no matter how good the argument is.
- **`spec`** — how completely *this document* specifies it: **`BUILDABLE`** (a competent engineer can
  build it from §1 without inventing a contract), **`PARTIAL`**, or **`PROSE`**. *(Attack ruling
  A1.0: the buildability reviewer's verdict was "buildable spine, unbuildable adjudicator", and they
  were right that a reader could not tell which was which.)* 🚨 **Nothing may be built from a `PROSE`
  row.** Its next step is a design pass, not an implementation task.

**THE CORE PIPELINE IS FIVE STAGES: S0 · S1 · S2 · S3 · S6-blind.** Everything else is an optional
tier that must buy its way in by beating the spine on a stated number. That is a cut from thirteen,
and it is the honest reading of our own measurement: on this corpus the ceiling is 11/11 and the
spine already reaches it.

### Tier 0 — THE SPINE. Build this first; it is already 11/11 on the corpus.

| | Build | `number` — measured leverage | `spec` | ~Size |
|---|---|---|---|---|
| **B0** | **The mined clean corpus** (~315 pages from the three apps' git history that shipped and were never touched by a visual-bug fix) — **promoted from Tier 1, and it is now the FIRST thing built** | Every finding on it is a **false positive by construction, at zero labelling cost.** It is the denominator every FP claim in this document needs and none has. Without it the safety argument is a **37.5 %** bound (§2 C18) against a ~20 % cliff | `BUILDABLE` | ~200 LOC |
| **B1** | **CAPTURE, pinned** — the three DPR flags, the 9-step readiness ladder, `manifest.json` with `eff_read`/`eff_api`/`read_colour_class`/`tier_safe` computed. **The stability gate ships as an ADVISORY abstention flag, not a gate** | without the scale flag every geometric finding inherits a **1.5 px phantom offset**; without the scroll prime **7 of 8** sections photograph at `opacity:0` (47,991 B → 58,960 B once primed) | `BUILDABLE` | ~350 LOC |
| **B2** | **EXTRACT** — one `captureSnapshot` + one AX tree → the 854-token fact-pack + `target_key` | **32.7 ms** vs 881 ms in-page vs 5,788 ms per-node — 29× and 177×. The pack is **cheaper than the screenshot it rides beside** | `BUILDABLE` | ~500 LOC |
| **B3** | **`detect_dom`** — the rule file **with its explicit `INDETERMINATE`** | **9/9 DOM-determined, 0 control FP, 80 ms/page.** Exists and runs today at 353 LOC | `BUILDABLE` | ~250 LOC |
| **B4** | **`detect_xcheck`, X3 arm only** — contrast sampled in thirds | resolves the gradient deterministically (**4.81 / 1.57**), **0 control FP**, removes a whole class from the model queue. Exists today at 233 LOC | `BUILDABLE` | ~180 LOC |
| **B5** | **One blind gestalt call** — request-isolated, viewport frame, `unprompted` array. 🚨 **BLIND-ONLY: no fact-pack, no verdicts, until U5 answers** | **2/2 judgement + 3 real defects nobody injected + 0 FP.** This is the arm that was *measured*; adding the fact-pack changes the arm (§2 C3) | `BUILDABLE` | one prompt |
| **B9** | **S0 SURFACE + the `UNREVIEWED` block** — *promoted into the spine from Tier 1* | It is a `find`: **0 `loading.tsx` against 16 `page.tsx` under `(app)`, 0 against 105 across `src/`**; **18 of 288 tuples = 6.3 %**; `prefers-reduced-motion` **0** in two of three apps. Zero FP by construction, and **no stage that begins at a URL can produce any of it** | `BUILDABLE` | ~300 LOC |

🚨 **B1's stability gate is demoted to advisory, and it is C8's own logic finally applied to C8's own
capture stage** (attack ruling A2.5). U2's *stated prediction is that fewer than 12 of 20 live routes
converge* — so shipping convergence as a **gate** means the pipeline's dominant output on real pages
is a refusal, which is exactly the fail-closed-composes-into-fail-never failure §2 C8 exists to
prevent. It writes `degradation.stability: drifting`, abstains the pixel-derived classes, and lets
every DOM class stand. The capture stage was the one place the degradation vector had not reached.

**Order matters and is not negotiable: B0 before B1.** The value attack argued B7-the-corpus
*outranks* Tier 0; that is **partially refuted on sequencing** — a corpus with no detector produces
nothing, so it cannot precede the detectors that run on it. But it precedes everything *else*, and it
is the ship gate: **the spine is not "shipped" until it has run over B0 and produced zero asserted
findings.** That converts the programme's central safety claim from a bound into a measurement, which
is the single largest available reduction in risk anywhere in this document.

**That is the entire measured value of the programme, at ~1,800 LOC and one model call per page.**
Ship it, run it on the corpus, on B0, and on 20 real routes — and make every later stage beat it.

### Tier 1 — the highest-leverage things that are NOT stages

These outrank every remaining line of specification, and three of them require no model call at all.
*(B7 and B9 have moved up into Tier 0 as B0 and the SURFACE row — see 2A.2 A2.4 and A2.6. The ids are
kept rather than renumbered, because §2, §4 and §7 already cross-reference them.)*

| | Build | `number` — why it outranks a stage | `spec` |
|---|---|---|---|
| **B6** | **Run the gating probes** — U5 first, then U1, U3, U2, U4 (§7) | **U5 decides whether the judge in the pipeline is still the judge we measured**; U4 decides whether S5 exists at all. A specification of a measurement is not a measurement. Total: ~3 h and <150 k tokens for decisions that currently gate four stages. **U5 should now run over all 13 corpus variants, not 8** — the blind arm's n is the binding constraint on every rate this document may quote | `BUILDABLE` |
| **B7** | → **promoted to B0, Tier 0.** The FP denominator is the ship gate, not a follow-on | see B0 | — |
| **B8** | **S9 ATTRIBUTE** (rung 1 + the CSS side + `shared_with`) | The only stage whose output is a **write target**. A15's predicted failure is *"sees fine, critiques plausibly, changes nothing"*, and this is the only thing pointed at it. Mechanism measured and exists today. 🚨 **The number it must produce, stated so it can fail** (attack ruling A2.12): **≥60 % of spine findings resolve to a `file:line` a human confirms is the right edit site, at ≤20 % over-abstention.** Below that it is a `LOW`-verdict generator and does not ship. Its *value* has never been measured — only its mechanism | `BUILDABLE` |
| **B9** | → **promoted into Tier 0.** It is the coverage denominator; nothing downstream means anything without it | see Tier 0 | — |
| **B10** | **`.design-exceptions.jsonl`** + the new/known/suppressed/regressed partition | Measured: **no exception channel exists in any of the three apps.** Without it, run 2 reprints every intentional violation forever, and a re-reported true finding spends the same credibility as a wrong one. This is the mechanism the previous tool died for lack of. ~60 LOC. **Depends on `target_key` (§1.9 / D19)** — its `selector_absent` falsifier was unbuildable before that ruling | `BUILDABLE` |
| **B11** | **One line in `reso-web-app/next.config`**: `compiler: { emotion: { autoLabel: 'dev-only', labelFormat: '[local]' } }` | Free in production, and it moves an entire app's modal attribution verdict from `LOW` to `MEDIUM`. Highest ratio of value to diff in the whole document | `BUILDABLE` |

### Tier 2 — OPTIONAL. Build after the probes have answered, each on its stated number.

*These are no longer "the pipeline". They are candidates that must beat the spine.*

| | Build | `number` — gated on / justified by | `spec` |
|---|---|---|---|
| **B12** | **S8 ARBITRATE — the DEDUP HALF ONLY** | the dedup bug is *measured*: **0/1 → 1/1** once the key spanned the claim. 🚨 **The predicate-DSL half is DELETED, not deferred** (D18) — it was a compiler for a language with no programs. At ≤7 findings/page from one call, what remains is a link-never-delete dedup over ~10 items, and it is worth ~150 LOC, not a stage | `BUILDABLE` (dedup) |
| **B13** | **RT run composition** — cell key folding the render env, journal-based resume, `--gate` isolation, the one-line tier predicate | a resume across a `git pull` otherwise mixes two instruments; the tier predicate prevents a silent API resample of a "clamp-safe" image. **The `--gate` isolation is now genuinely enforceable** — with Route C deleted there is no path from `judge/` to the exit code at all | `BUILDABLE` |
| **B14** | **S3's remaining rule families** (K, T, O) + the closed census + `indeterminate_classes` | K is the *whole job* on the management app — **and K must abstain, not FAIL, wherever the winning declaration came from the token-map-less Tailwind engine** (§1.0). 🚨 **No family ships without a clean run over B0**; each new family multiplies FP exposure over ~193,000 subject-checks (§2 C18) | `BUILDABLE` |
| **B15** | **S11 EVAL**, specifically `abstention_recall = 1.00` and `false_abstention_rate ≤ 0.05` | the **only** gate that catches a change which improves every other number while destroying the pipeline (the naive `blendedBackgroundColors` adoption) | `BUILDABLE` |
| **B16** | **The affected-set index** (`nft.json ∘ SSR chunk source maps`) | measured p50 = **2 routes**, 44.3 % singletons ⇒ the median PR reviews 2 routes for **$0.24**. ⚠️ `nft.json` **alone indexes 0 modules** and reports every commit as affecting nothing — a total silent false negative that looks like a clean incremental run | `PARTIAL` |

### Tier 3 — DEFERRED or CUT, each with the number that would revive it

*Four of these were core stages in the ratified thirteen. The value attack scored them against the
one-screenshot null and they did not clear it. Every one is recorded here rather than deleted,
because each carries a real observation — the observation is just not worth a stage.*

| | Build | Ruling and the number that revives it | `spec` |
|---|---|---|---|
| **B17** | **S5 DECOMPOSE — CUT from the core pipeline** | **CONCEDED (A2.7).** §2 C2 already killed the ScreenSeekeR transfer (zero web screenshots, point-in-box not IoU, inverse task) and found **4 of 5 unique findings are page-global quantifications structurally unreachable from a crop**. Its survival was conditional on U4, which is unrun, and 706 lines of P2 spec rested on that probe. **What ships instead: a ~40-LOC re-clip utility** (`Page.captureScreenshot` with a rect), no planning half, no MECE cover, no duty crops. Revived only if **U4 shows a 6-crop arm strictly dominating full-page on our own corpus** | `PARTIAL` |
| **B18** | **S7 STATES/MOTION — DEFERRED; its one real finding has been extracted** | **CONCEDED (A2.10).** Its blocker is genuine but it is a **`grep`, not a stage**: `prefers-reduced-motion` = **0** in `reso-web-app` and `reso-landing-app`, and the landing app is the `framer-motion` one (338 in management). **That line now lives in S0 SURFACE** (§1.0) and costs nothing. The rest of S7 stays deferred for the reason its own spec gives: **no acceptance corpus exists for it.** Revived when one does | `PROSE` |
| **B19** | **S4 ROUTE — CUT to ~20 lines** | **CONCEDED (A2.8).** T1 on the corpus today is **0**. Five triggers, a block ledger and collapse-by-class exist to manage an empty queue of unknown real size. **S4 v1 is: "route T2 unconditionally; forward everything else as a fact."** The five-trigger machinery, the class collapse and the session ledger are revived by **U3** (if 95 abstentions collapse to ~3, the machinery is affordable and worth building) and **U1** (if the cliff is per-conversation) | `BUILDABLE` (the 20-line form) |
| **B19b** | **S1b INK-PROBE — DEFERRED** | **CONCEDED (A2.9).** It costs ≤40 differential captures per cell to fix a swamping bug in X1 — **and X1 has produced zero true positives to date.** Build it the first time X1 finds one. *(The C24 ruling that it belongs inside S1's process stands and is unaffected — it is a placement ruling, not a build order.)* | `BUILDABLE` |
| **B20** | Saliency (UMSI++) | **the UEyes licence is the gate**, not a nice-to-have. CC 0.833 vs the best VLM at 0.408 is mechanistic and will not be closed by a better prompt | `PROSE` |
| **B21** | The 512 px squint pass | its own probe (U6) shows the gestalt defects survive and the sub-perceptual ones still miss | `PARTIAL` |
| **B22** | `dr redteam` as a standing job | after B12–B15 give it artifacts to assert over | `PARTIAL` |

### Cut — do not build

Local VLM in the detection path · any learned GUI detector · annotated overlays as a standing input
(a full second image at ~3,240 tok against ~840 for the same findings as JSON) · any score, grade,
rank or 1–5 rating · X2 centroid **on** by default · X4/X5/X6 until each has its own control run ·
a per-finding duty crop · negative caching of "this cell had no findings" (it makes the clean result
and the not-run result the same bytes) · **Route C and its AST-allowlisted predicate DSL** (D18 —
no model finding is promotable by any route) · **S5's planning half** (B17) · **S4's five-trigger
machinery at current volume** (B19).

### 6.0b AS BUILT — 2026-09-04, and the three numbers above that moved

Built against the corpus, all in `bench/`, none of it a model call: **B3** and **B4** already
existed; **B19**'s 20-line S4 is `route.py`; the per-app half of **C11** is `profiles.py`; the ship
gate of **C18** is `score.py`, which exits non-zero. `README.md` § 8.1 holds the full delta. Three
rows of this document are now false as written and are corrected here rather than in place, because
each was a *ruling* and its reasoning still stands:

- **"X2 centroid ON by default" is off the Cut list.** It was cut for want of a control run, which is
  the correct reason, and it has now had one: 0 findings on the control against the old arm's 2, the
  injected defect at −2.00 px against a derived 1.25 px band, both DPRs agreeing. Its two documented
  defects are fixed (container-relative measurement; a painted-shape mask). The Cut list's sibling
  entry — *"X4/X5/X6 until each has its own control run"* — is untouched and is the rule that
  admitted this one.
- **"T1 on the corpus today is 0" (C7, B19) is now 12 crops over 13 pages.** X2's honest vertical
  abstention — a text glyph's ink sits where its font's baseline puts it, and no artifact here
  carries that — created a real queue where there was none. **The cut still stands**: twelve
  questions of one class collapse and fold to one image each, and nothing is dropped. But the
  premise it rested on is gone, and U3 now has something to histogram.
- **X1's swamping bug (B19b) is fixed offline, and B19b is not thereby closed.** `inkmask.py` gets
  the painted-shape mask from a flood fill over the stored PNG rather than from S1b's differential
  re-render. The differential probe is strictly better — it assumes nothing about shape or backdrop —
  and B19b's revival condition (*build it the first time X1 finds a true positive*) is unchanged,
  because X1 still has no fixture and has never caught anything. `score.py` reports it NOT ADMITTED.

One thing this build did NOT do, and it is the one that matters: **B0**. The false-positive claim is
still a bound, not a measurement. `score.py --clean-set` is the socket, and the rate is withheld in
code until n ≥ 16.

### 6.1 The scorecard this restructure produces

| | Before the attack | After |
|---|---|---|
| Stages in the core pipeline | **13** | **5** — S0 · S1 · S2 · S3 · S6-blind |
| Core-pipeline LOC | ~1,500 (spine) inside a 13-stage frame | **~1,800**, and the frame is gone |
| Stages naming a measured number | 6 of 13 | **5 of 5** |
| Model calls per page | 3.6 | **1** |
| Promotion paths from a model finding to `asserted` | 1 (Route C) | **0** |
| FP denominator | 8 pages, 52 elements each | **B0 is the ship gate** |

**Nothing measured was lost in the cut.** The 11/11 was always the spine's; the eight stages removed
from the core contributed **0.0 expected marginal recall on the corpus that measured them** (§5.2
sentence 1), and each keeps a revival condition stated as a number above.

---

## 7. The probe queue — every deferred decision, with the experiment that settles it

| | Question | Probe | Cost | Decides |
|---|---|---|---|---|
| **U5** | Does the fact-pack suppress unprompted findings? | 3 arms over **all 13 corpus variants** (not the 8 the original blind run used — A2.3) — A blind, B facts-only, C facts+verdicts; count unprompted findings, control FPs (5×), injected recall. **Decision rule stated before the data:** if C is below A by more than one finding across the corpus, verdicts never enter a gestalt call | 39 calls, <100 k tok | **the pipeline's central bet** — §2 C3. **It also re-runs arm A at n=13, which is the cheapest available improvement to every rate this document may quote** |
| **U1** | Does the >20-block cliff count per **request** or per **conversation**? | Read 21 small PNGs in one turn; then 21 across 21 turns; compare the errors | ~4 min | whether the ledger is per-run or per-turn — §2 C1 |
| **U3** | Are 95 abstentions ~95 questions or ~3 classes? | histogram `INDETERMINATE` by `(rule, backdrop_signature)` over 10 real routes | ~20 min | whether the affordability argument survives — §2 C7 |
| **U2** | Does the stability gate converge on **live** pages? | run S1 unchanged over 20 sampled management routes against a real dev server with seeded data. **Stated prediction: fewer than 12 of 20** | ~30 min | how much of §2 C8's degradation vector is load-bearing |
| **U4** | Does crop refinement improve **anything** on our corpus? | blind prompt on the full page vs the same page as 6 crops, 13 pages, count finds + FPs | ~2 h | **whether S5 exists** — §2 C2 |
| **U6** | Do gestalt findings survive a 512 px squint frame? | re-run the 13-page blind pass at 512 px; real iff the 2 judgement defects still land **and** the 2 sub-perceptual ones still miss | ~1 h | whether the glance is reachable without a saliency licence |
| **U7** | Has the judge collapsed onto the corpus? | novel-finding rate on **previously unreviewed** pages; alarm at **zero across three consecutive runs** | continuous | the anti-overfit alarm, with the right polarity |
| **U8** | Are the 0.6 surfacing / 0.75 close floors right? | log every finding with its confidence over one three-app run, adjudicate, plot precision against threshold, take the knee | one run | today both are policy wearing a measurement's clothes |
| **U9** | Does the Read clamp still read 2000 px / 3.75 MiB? | render a 1,999 px and a 2,001 px PNG each carrying a 256-step grey ramp and a 5/255 patch pair; Read both; ask which pair differs | minutes | **every `eff` and every batch size is downstream of this constant**, read from a bundle that ships weekly. Either result is news |
| **U10** | Do server-component fibers source-map to server modules? | render one obviously-attributable Server Component; read `fiber._debugStack.stack`; POST with `isServer:true` | ~15 min | if no, **most of a Next 16 App Router page** falls to `LOW` and the `data-component` convention becomes a dependency, not a recommendation |

**Run U5 first.** Every other stage's design is downstream of whether handing the judge 854 tokens of
verdicts costs us the capability that is the only reason a judge is in the pipeline at all.

---

## 8. Constants — every number, and what derives it

| Constant | Value | Derived from |
|---|---|---|
| Read client clamp | 2000 × 2000 px, 3,932,160 B | read from the 2.1.183 bundle — **re-probe per release (U9)** |
| Visual-token formula | `⌈w/28⌉ · ⌈h/28⌉` | patch grid, vision docs — **not** bytes/750 |
| High-res tier | 2,576 px long edge **and** 4,784 visual tokens | both bind; for wide frames the **token count binds first** |
| Lossless square crop | **966 × 966 CSS @2** (1,932 px) | `⌈n/28⌉² ≤ 4784 ⇒ ⌈n/28⌉ ≤ 69` |
| Largest clamp-safe **and** tier-safe rect | 2000 × 1800 = 4,680 tok | both predicates |
| Whole-frame `eff` | **1.389** via `Read`; **1.68** via the API | §2 C6 |
| Full-page `eff` | **0.80** at any DPR | height binds; worse than a plain DPR-1 viewport shot |
| Image blocks / API request | **≤8** | most conservative of the four; the request is what the cliff is about |
| Image blocks / conversation | ledger, ceiling **12** (→ ~18 if U1 says per-request) | rejection, not degradation, so the margin must be real |
| DPR | **2** | the largest DPR at which a ≤966 CSS crop is lossless end-to-end; DPR 3 buys nothing on desktop |
| Geometric band | `J1(0.5/dpr) + J2(0.25) + J3(0.5/line-box)` | physics, not policy — a profile may never loosen it |
| `INK_DELTA` | 12 (Σ over 3 channels) | 3 levels/channel; grayscale AA at a glyph edge is ≤2 |
| ΔE₂₀₀₀ token bands | <1.0 drift · 1.0–3.0 near-miss · >3.0 undeclared | 1.0 is the JND floor; our 5/255 drift lands at ΔE ≈ 0.6 |
| Contrast | WCAG 2.1 `4.5:1` / `3.0:1` large | **APCA rides along as a scalar and gates nothing** — as a gate it flagged 66 of 99 runs against WCAG's 13 |
| Target size | `44 − band` | WCAG 2.5.5; the band exists because our control flipped clean→defective at 44 → 43 px |
| Occlusion | `IoU_of_smaller > 0.5` + paint order + not a declared overlay | raw overlap is noise: **4,795 intersecting pairs** among the first 600 boxes on a correct page |
| FLIP regression gate | mean ≤ 0.020 | noise floor 0.0099–0.0130, weakest true positive 0.0753 — **5.8× separation**; pixelmatch inverts here |
| Fact-pack ceiling | 1,100 tokens | it must cost less than the screenshot it accompanies |
| Findings cap | 7 page / 4 crop / **3 unprompted (non-fungible)** | ranking is the work; the third is what stops arithmetic crowding-out |
| FP budget | **0 asserted on any control, absolutely**; no *rate* below n=16; stated per 1,000 subject-checks | rule of three; ~20 % is the credibility cliff |
| **Blind-run trials** | **n = 8** (`page-A`…`page-H`) | `bench/corpus/out/blind_key.json`; the corpus *builds* 13 variants, the judge *saw* 8 — **never quote the build count as the trial count** |
| **FP 95 % upper bound today** | **3/8 = 37.5 %** | rule of three at the real n — **1.9× the ~20 % cliff**, not 1.16× |
| Judgement recall gate | **≥ 0.50**, ≥8 items/class | above the best published result on the closest task, under the human ceiling |
| Abstention gates | `abstention_recall = 1.00` **and** `false_abstention_rate ≤ 0.05` | a layer can score 1.00 on the first by abstaining on everything |
| Branch-order permutation | 3–5 seeds, echoed | recovers ≈⅔ of the benefit of ten; exact balancing buys essentially nothing |
| **Cost — the SPINE, which is what ships** | **≈$0.04 and ~5.4 k input tokens per page**, **1 model call** | derived below |
| **Cost — full optional pipeline** (if every tier is built) | **≈$0.20 and ~25 k input tokens per cell**, 3.6–4 model calls; **images are ~90 % of input**, not 24 % | derived below |

🚨 **The old cost row was internally contradictory against §8's own constants, by ~4×** (attack
ruling A1.8, CONCEDED). It read *"≈$0.12 and ~15.5 k tokens per cell, 3.6 model calls; the image is
24 % of input tokens"* — i.e. ~3,720 image tokens, **smaller than the single mandatory gestalt frame
this same table prices at 4,698.** No arrangement of this table's own numbers produces it. The
derivation, shown so the next reader can check it rather than trust it:

```
gestalt frame   2419×1512  →  ⌈2419/28⌉ · ⌈1512/28⌉ = 87 · 54 = 4,698 tok   (§2 C6)
966×966 CSS @2  1932×1932  →  ⌈1932/28⌉²            = 69²     = 4,761 tok   (§2 C5)

SPINE (1 blind call, no crops, no fact-pack):
  in  = 4,698 image + ~700 prompt/schema                       ≈  5,400
  out = ~600
  $   = 5,400/1e6·$5 + 600/1e6·$25                             ≈  $0.042

FULL (gestalt + reconcile + ≤2 crops = 3.6–4 calls):
  gestalt    4,698 + 700                                       =  5,398
  reconcile  4,698 (image re-sent in-conversation) + 854 + ~1,900 =  7,452
  crops ×2   (4,761 + 854 + 500) × 2                           = 12,230
  in ≈ 25,080 · out ≈ 2,800
  $   = 25,080/1e6·$5 + 2,800/1e6·$25                          ≈  $0.195
  images = 4,698 + 4,698 + 9,522 = 18,918  →  75–90 % of input, depending on crop count
```

⚠️ **Both rows are DERIVED, not measured, and the reconcile row assumes the in-conversation image is
re-billed** — true without prompt caching, and the one assumption most likely to be wrong. **A
measured cost per page over B0 supersedes this table on sight.** The load-bearing fact is not the
dollar figure, it is the shape: **the image dominates**, so cost control is image control (fewer
calls, never a taller frame), which is the same conclusion §2 C9 and §2 C20 reach from geometry.

---

## 9. The two sentences this whole document exists to make true

**A finding is asserted only when a predicate that could have failed was executed and did not.**
Everything else is advisory, abstained, or in the appendix — and the appendix is never empty, because
nothing is ever deleted. *(After the 2026-08-26 review this is true of the code and not merely of the
prose: Route C was the one path by which a model finding could reach `asserted` without a predicate,
and it is deleted — D18.)*

**A report may claim "clean" only on the one row of the degradation ladder that earns it**, and every
other row must name, in generated text and not in prose, the population it did not look at. The
pipeline's most dangerous available output is not a wrong finding. It is a confident clean report
over a page nobody photographed.

---

## 10. Close — the three things to leave with

*If you read nothing else, read this section. Each part points at the section that holds the detail.*

### 10.1 The honest recall ceiling

> On every defect class where a human designer is the reference, find what the best human finds; on
> every class where humans are structurally blind (1 px, 5/255), find what no human finds; and on
> every class where it can do neither, **say so** rather than passing.

**Per class, and the full table with its evidence is §5.1:**

| Class | Recall | FP |
|---|---|---|
| DOM-determined (spacing, alignment ≥1 px, token drift, type scale, grid, contrast-solid, overflow, target size) | **~1.00** | **0** measured (9/9, 0 control FP, 80 ms) |
| Contrast over gradient / composited backdrop | **~1.00**, deterministic, no model | **0** |
| Named-state absence — with its glob named | **1.00** | **0 by construction** |
| Judgement / gestalt (hierarchy, grouping, content-fit, readability) | **0.50 – 0.66** | 0 measured, **bounded only at 37.5 %** |
| Novel / unprompted findings | **~0.375 / page** | 0 measured, **bounded only at 37.5 %** |
| Sub-perceptual from the **judge** | **0.00 — expected, gate is precision** | gate = abstention, not detection |
| Sub-perceptual from the **DOM layer** | **1.00** | 0 |
| rAF motion · unnameable absence · taste · second-order prediction | **0.00 / no figure admissible / not attempted** | — |

🚨 **The three sentences that qualify all of it.** (1) On our own corpus **the ceiling is 11/11 and
the five-stage spine already reaches it** — expected marginal recall from every cut stage: **0.0**.
(2) **The false-positive claim is a bound, not a measurement, and the bound is 37.5 % — nearly 2× the
~20 % credibility cliff.** Never write "zero false positives"; write *"no false positives on 8 pages
and one control, which bounds the rate below 37.5 %"*, until **B0** replaces the bound with a
measurement. (3) **The dominant risk is not a missed defect. It is a confident clean report over a
page nobody photographed** — 6.3 % of one app's tuple universe was captured in the worked example.

### 10.2 The build order, ranked by measured leverage — §6 holds the tables

**THE CORE PIPELINE IS FIVE STAGES: S0 SURFACE · S1 CAPTURE · S2 EXTRACT · S3 SCREEN · S6 JUDGE
(blind).** ~1,800 LOC, **one model call per page**, ≈$0.04/page. Cut from thirteen, on this
document's own rule that a stage which cannot name the number it improves is overhead.

1. **Tier 0 — the spine.** `B0` mined clean corpus (**first, and it is the ship gate**) → `B1` pinned
   capture, stability **advisory** → `B2` extract + `target_key` → `B3` `detect_dom` → `B4` `detect_xcheck` X3
   → `B5` **one blind gestalt call, no fact-pack until U5** → `B9` SURFACE + `UNREVIEWED`.
2. **Tier 1 — not stages, and they outrank every remaining line of spec.** `B6` run the probes ·
   `B8` ATTRIBUTE (must hit **≥60 % confirmed write targets** or it does not ship) ·
   `B10` `.design-exceptions.jsonl` · `B11` the one-line Emotion config.
3. **Tier 2 — optional, each on its number.** `B12` dedup-only arbitration · `B13` RT composition ·
   `B14` remaining rule families (**none ships without a clean B0 run**) · `B15` EVAL · `B16` affected-set index.
4. **Tier 3 — deferred or cut, each with a revival number.** `B17` S5 DECOMPOSE **cut** (revived by
   U4) · `B18` S7 **deferred**, its one real finding extracted into SURFACE · `B19` S4 **cut to ~20
   lines** (revived by U3/U1) · `B19b` S1b **deferred** until X1 finds a true positive · `B20`–`B22`.
5. **Cut outright:** local VLM in detection · learned GUI detectors · any score/grade/rank ·
   **Route C and its predicate DSL** · annotated overlays · negative caching.

**Run U5 first** — every stage's design is downstream of whether handing the judge 854 tokens of
verdicts costs the capability that is the only reason a judge is in the pipeline at all.

### 10.3 What this does not see — §4 holds the mechanism

**Fifteen named blind spots**, each reported as `NOT RUN` or `NOT MEASURABLE`, never as silence:
**(a)** never photographed — the largest class, 18 of 288 tuples (6.3 %), and only 96 of 288 reachable
without a human · **(b)** absence with no denominator · **(c)** below the perceptual threshold from
the judge (0/2 measured) · **(d)** interiors: canvas, WebGL, video, SVG · **(e)** rAF-driven motion,
present in **all three** apps · **(f)** virtualised rows below the fold · **(g)** Chromium only ·
**(h)** colour gamut — **two stacked blindnesses on the management app's P3 accents** · **(i)**
production builds · **(j)** second-order consequences · **(k)** whether the declared task is the
wrong task · **(l)** false negatives, structurally · **(m)** taste, by ruling (α = 0.248) · **(n)**
the measurement substrate is **experimental CDP surface** that can vanish in a point release ·
**(o)** the grading corpus is **35× less dense** than the target, so every number above inherits that.

**The mechanism, not the list, is the deliverable.** Five generated surfaces carry it — the
`coverage` field, the closed census (`pass + fail + indeterminate + out_of_scope == subjects`),
`degradation.json`, a report header that **can never render "clean"**, and the `UNREVIEWED` block,
**prepended, never appended** — because a verdict placed last is read after the decision has been
made. **Anything the pipeline cannot verify says `NOT RUN` or `NOT MEASURABLE`, never nothing.**
