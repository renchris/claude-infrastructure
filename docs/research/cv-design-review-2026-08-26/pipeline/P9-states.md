# P9 — STATES AND MOTION

**Stage:** enumeration and temporal assertion. Everything a single still frame cannot contain —
the interaction state space, the breakpoint/theme/direction space, content stress, and motion.

**Substrate:** `agents/A10-motion-interaction.md` (every WAAPI/CDP/PerformanceObserver number),
`pipeline/P1-capture.md` §2.1, §3.3, §4.2, §4.3 (the freeze levers, `--states` contract, theme
probe), `agents/A7-deterministic-layer.md` (CDP extraction costs), `pipeline/P5-route.md` §3.1
(image-block ledger), `pipeline/P7-arbitrate.md` §1.1 (findings schema), plus a live census of the
three consumer repos taken 2026-08-26 (§1.3, §6.2 — both carry findings no agent report predicted).

**One-sentence thesis.** P9 does not photograph states; it *enumerates* them from the page's own
state vocabulary, collapses that enumeration into proof-carrying equivalence classes, settles almost
all of it with numbers, and hands P1 a small list of named cells plus — for the one defect class no
timing instrument can reach — a ≤9-frame strip selected by elapsed milliseconds.

---

## 0. Contract

### 0.1 Invocation

Two subcommands. The first is a *planner* (no capture, no findings); the second is an *asserter*
(runs a browser, emits findings). They are separate because the plan is an input to P1 and the
assertions are an output of a pass that P1 has already made.

```
design-states plan   <url> --out <dir>
                     [--interactive-cap 400] [--class-cap 120] [--crop-cap 8]
                     [--stress 1,3,12] [--rtl auto|on|off]
                     [--budget-ms 20000]

design-states assert <url> --out <dir> --plan <dir>/state-plan.json
                     [--tokens auto|<file>] [--throttle 1,4]
                     [--interactions <dir>/interactions/*.js]
                     [--frames auto|off] [--budget-ms 120000]
```

`plan` runs first, its `cells[]` feed `design-capture --states` (P1 §4.2 — capture photographs the
state it is given and never invents one), and `assert` runs after, in its own browser pass, because
its instruments (`page.clock`, `Emulation.setCPUThrottlingRate`, real `locator.click()`) mutate the
page in ways that would void P1's byte-stability gate (P1 §6.2).

### 0.2 Inputs

| Input | Type | Required | Notes |
|---|---|---|---|
| target | URL or `file://` | yes | Same target string P1 was given. A mismatch is exit 4. |
| `--out` | dir | yes | Shared with the P1 perceive dir; P9 writes only under `states/`, `interactions/`, `frames/`, `findings/`. |
| `--plan` | path | `assert` only | The `plan` output. Refuses to assert without one — assertions are scoped to enumerated classes, never to whatever the page happened to contain at that moment. |
| `--tokens` | `auto` \| path | no (default `auto`) | Duration/easing allowlist. `auto` **extracts from the app's own token source** (§4.2); it never carries a hardcoded scale. |
| `--interactions` | dir of `.js` | no | One file per named interaction to review for motion (`open-nav.js` = `await page.getByRole('button',{name:'Menu'}).click()`). Absent ⇒ §4 runs page-load-only and says so. |
| `--stress` | int list | no (default `1,3,12`) | Text-length multipliers for the truncation axis (§1.6). |

### 0.3 Outputs

Every path is absolute in `state-plan.json` / `motion.json`. Nothing else is written.

| Artifact | Class | Read by |
|---|---|---|
| `state-plan.json` | plan | **P1** (`--states`), P5, P7 |
| `states/<cell>.js` | driver | P1 only — the exact file P1 executes between R7 and R8 |
| `findings/states.json` | `layer:dom` | P7 |
| `findings/motion.json` | `layer:dom` | P7 |
| `findings/motion-frames.json` | `layer:judgement`, **advisory-only** | P7 (capped, §7.4) |
| `frames/<interaction>.t<NNNN>ms@2x.png` | `lossless` (asserted) | the judge, via P5's ledger |
| `coverage.json` | — | **P7 and the report** — the population this stage could not reach (§6) |

`stdout` is one line of JSON:
`{"ok":true,"plan":"<abs>","cells":N,"classes":M,"uncovered":["raf-library:motion@12"],"warnings":[…]}`.

### 0.4 Failure modes

| Exit | Name | Meaning | Recovery |
|---|---|---|---|
| 0 | OK | plan or assertions produced; **zero findings is a normal outcome** | — |
| 1 | USAGE | bad args; `assert` without `--plan` | fix the call |
| 4 | INPUT | plan target ≠ assert target, or plan `dom_sha` ≠ the live DOM's | re-run `plan` |
| 11 | FREEZE_UNPROVEN | the freeze canary did not freeze (§5.3) — **no frame in this run is evidence** | the page has a motion source neither clock reaches; see `coverage.json` |
| 12 | STATE_FORCE_FAILED | `CSS.forcePseudoState` returned but the computed style did not change on a class whose CSSOM candidate said it must (chromium 343757697) | the class is emitted as `abstained`, not as a pass — a state-forcing failure is a loud skip (A10 §8) |
| 13 | CLASS_EXPLOSION | equivalence classes > `--class-cap` after collapse | the route is a component gallery; re-run per section with `--section <selector>` |

🚨 **`ok:true` with `coverage.raf_uncovered` non-empty is NOT a clean bill.** A harness that reports
"0 animations found" on a rAF-driven page is the exact false green this stage exists to prevent
(A10 §4.1). §6 makes that a *rendered sentence in the report*, not a field nobody reads.

### 0.5 What P9 does not own

| Not P9's | Owner | Why |
|---|---|---|
| taking any screenshot of a state cell | **P1** | P9 emits `states/<cell>.js`; P1 owns DPR pinning, clamp-safety and the byte-stability gate. Two stages rastering means two rasterisers to keep honest. |
| deciding whether a frame strip earns a model call | **P5** | P5 holds the session-wide image-block ledger (ceiling 12). P9 states a cost; it never spends. |
| dedup, control subtraction, promotion/demotion | **P7** | P9 emits findings with `layer` and `severity` and stops. |
| mapping a state finding to the source line | **P8** | "this button has no `:focus-visible` rule" resolves to a JSX call site + declaring rule by P8's ladder, not here. |
| contrast of a focus ring against its backdrop | **P4** (xcheck) | Ring *presence* is a computed-style delta (deterministic, here). Ring *contrast* over a gradient or image is the DOM-vs-pixels comparator's job — the same abstention discipline as §2 of the README. |

---

## 1. Enumeration — where the list comes from

A hand-written state list restates a perishable fact (which states this app ships) inside a spec
with no way to learn it changed. Every axis below is *derived from the running page*, and each
records **which source answered**, so a later stage can tell a measured empty set from a blind one.

### 1.1 The five sources, in priority order

| | Source | Yields | Cost | Availability, measured 2026-08-26 |
|---|---|---|---|---|
| **S1** | CSSOM pseudo-class sweep | `:hover :focus :focus-visible :active :disabled :checked :open :target :invalid` | one in-page pass | all three apps |
| **S2** | CSSOM **attribute** sweep | `[data-hover] [data-focus-visible] [data-disabled] [data-state=…] [data-selected] [data-press] [aria-expanded] [aria-busy]` | same pass | **reso-management-app: 207 `[data-hover]` rules** |
| **S3** | Route + prop states | loading · empty · error · populated | one nav per state | **no Storybook in any of the three apps** |
| **S4** | Viewport · theme · direction | breakpoints, light/dark, LTR/RTL | delegated to P1 §4.1/§4.3 | Tailwind 3/4 + `next-themes` |
| **S5** | Content stress | truncation, wrap, overflow | in-page text mutation | all three |

### 1.2 S1 — the pseudo-class axis

A10 §3.4's sweep, with the CORS accounting it demands, run once in-page:

```js
const WANTED = /:(hover|focus-visible|focus|active|disabled|checked|open|target|invalid)\b/;
let blind = 0, rules = [];
for (const sheet of document.styleSheets) {
  try { rules.push(...sheet.cssRules); } catch { blind++; }        // cross-origin throws
}
const flat = [];                                                    // walk @media/@supports/@layer
(function walk(rs){ for (const r of rs) { if (r.cssRules) walk(r.cssRules); else if (r.selectorText) flat.push(r); } })(rules);
const stateful = flat.filter(r => WANTED.test(r.selectorText));
```

`blind` is written to `coverage.cssom_blind_sheets`. **Report the blind fraction; never read it as
zero** (A10 §4.3). A candidate is `(rule, state, elements)` where `elements` =
`document.querySelectorAll(selectorText.replace(stateRe,''))` — the rule's element set with the
state pseudo-class stripped. That is a *candidate generator only*: `@layer`, `:where()` and
unopened `@container` blocks all mean a matching rule may never win the cascade. Confirmation is
§3's computed-style delta, on one representative per class.

### 1.3 S2 — the attribute axis, and why S1 alone reads a confident false green

**Measured, `reso-management-app/src`, 2026-08-26:**

| Selector | Occurrences | Set by |
|---|---|---|
| `[data-hover]` | **207** | Ark UI / Base UI JS pointer handlers |
| `[data-disabled]` | 39 | library prop |
| `[data-focus-visible]` | 24 | library focus-visible heuristic |
| `[data-press]` | 27 (across 4 values) | app's own press machinery |
| `[data-state="open"\|"closed"]` | 8 | Ark popover/dialog |
| `:hover` (source text) | 305 | CSS |

Two consequences, and both invert a naive design:

1. **`CSS.forcePseudoState(node, ['hover'])` cannot reach any of the 207.** Ark sets `data-hover`
   from a `pointerenter` handler; forced pseudo-state changes *style computation only* and fires no
   events (A10 §3.2). A sweep that forces `:hover` and finds 305 rules responding will report
   healthy hover coverage while the 207-rule attribute population was never exercised.
2. **The failure is silent in the safe direction.** The elements carrying `[data-hover]` styling
   usually *also* match a `:hover` rule from a base layer, so the "does this element have any hover
   affordance" test passes on the wrong evidence. This is the fail-safe-mimics-healthy shape; it
   would not have shown up as a red anywhere.

So the attribute axis is a **first-class axis with its own driving mechanism** (§3, mechanism M2 —
real input only), and `coverage.attribute_states_driven` counts it separately from
`coverage.pseudo_states_forced`. A finding of class `state-missing` may only be emitted for an
element whose *both* axes were exercised; otherwise it is `abstained: axis-unreached`.

### 1.4 S3 — prop states, and the honest gap

A10 §3.3 makes Storybook the systematic enumerator for loading/empty/error/disabled, because those
are *props*, not pseudo-classes, and no state-forcing API reaches them. **Measured: none of
`reso-landing-app`, `reso-management-app`, `reso-web-app` has a `.storybook/` directory or a
`stories/` tree.** The recommendation is therefore inapplicable as written, and pretending otherwise
would produce a plan whose cells never render.

What exists instead, and what P9 uses:

| Signal | How it is enumerated | Confidence |
|---|---|---|
| `aria-busy="true"`, `[data-loading]`, a `Skeleton*` component in the owner chain | render-time DOM predicate; the loading cell is produced by `page.route()` delaying the matching XHR by 3000 ms | high — the app genuinely renders it |
| empty | route with a request stubbed to `[]` / `{items:[]}` | high, but **needs the route table**, so it is `--interactions`-supplied, not derived |
| error | route stubbed to HTTP 500 | high, same caveat |
| `:disabled` / `[data-disabled]` | S1/S2 | high |

**The bound and the admission:** P9 derives *which* states exist (36 files in `reso-management-app`
match `Skeleton|isLoading|isPending|EmptyState|aria-busy`) but it cannot derive *which network call*
produces each one. Route-stub fixtures are caller-supplied. Where they are absent, `coverage.prop_states`
reads `"declared: 4, driven: 0, source: none"` — a measured hole, not a clean sheet.

### 1.5 S4 — viewport, theme, direction

Viewport and theme are P1's (§4.1 `--viewports auto` from occupied `@media (width)` branches;
§4.3's three-step theme probe, which exists precisely because `next-themes` — present in
`reso-management-app` — writes a class on `<html>` and defeats a `prefers-color-scheme` probe).
P9 adds exactly one thing: **direction**. `--rtl auto` emits an RTL cell iff the page contains a
logical-property or direction signal (`dir=`, `[dir=rtl]` in any selector, `next-intl`, or any
`margin-inline`/`padding-inline`/`inset-inline` declaration). Measured: **zero RTL/i18n signals in
all three apps**, so `auto` emits no RTL cell and records `rtl: "no-signal"`. Forcing `dir=rtl` on
an app with no RTL intent generates a page of true-but-useless findings.

### 1.6 S5 — content stress

Truncation and overflow are the state most often shipped broken, and they need no fixture: mutate
the rendered text. The driver P9 writes into `states/stress-3x.js`:

```js
const CAP = 4000;
for (const el of document.querySelectorAll('h1,h2,h3,p,td,th,li,button,label,[data-text]')) {
  for (const n of el.childNodes) if (n.nodeType === 3 && n.data.trim())
    n.data = n.data.trim().slice(0, CAP / 3).repeat(3);
}
```

Multipliers `1,3,12` and their reasons: **1×** is the control (the cell must exist so P7 can
subtract it); **3×** is the smallest multiplier that reliably crosses a one-line box into wrap or
`text-overflow: ellipsis` for typical label lengths; **12×** crosses the *container*, which is where
`overflow: hidden` clipping, a flex child refusing to shrink (`min-width: auto`), and a table column
blowing its grid actually surface. Two rungs conflate wrap-failure with overflow-failure; four adds
no new regime. `CAP` bounds a pathological node at 4000 chars so a 12× pass on a long article
cannot produce a 200 MB DOM.

---

## 2. Bounding — a proof-carrying equivalence class, not a sample

The naive product is 9 pseudo-states × 8 attribute states × 3 viewports × 2 themes × 3 stress rungs
× every interactive element. On `reso-management-app`'s densest route that is five figures. Three
collapses, applied in this order, and each is *exact* rather than a heuristic sample.

### 2.1 Collapse A — identical matched-rule set ⇒ identical state response

**Key:** `sha1( sorted(rule_ids that match this element) ‖ sorted(resolved values of the custom
properties those rules reference) )`.

This is not a similarity heuristic. State styling can only come from a rule that matches the
element, so two elements matching the *same rule set* respond identically to the same forced state —
by construction. The custom-property term is load-bearing for these apps specifically: Tailwind 4
and Panda both express theme and state colour through `var(--…)`, so two elements can share a rule
set and still differ once `--color-accent` resolves differently under a `[data-tier]` ancestor.
Including the resolved values makes the key exact instead of nearly-exact.

**Why not `CSS.getMatchedStylesForNode`,** which returns the same information authoritatively: A7
measured the per-node CDP walk at **5788 ms** for an 83-layout-node page — ~70 ms/node. At the
400-node interactive cap that is 28 s, most of a P1 budget, for a key. The in-page CSSOM index
(§1.2) computes the same partition with one `querySelectorAll` per stateful rule and no round trip.
P8 still uses `getMatchedStylesForNode`, correctly — it needs the *cascade*, on a handful of nodes,
after a finding exists.

### 2.2 Collapse B — a state exists only if it changes something visible

A class is promoted to a *cell* only if driving the state changes at least one property in the
watched set:

```
background-color · color · border-*-color · border-*-width · outline-color · outline-width
outline-style · outline-offset · box-shadow · opacity · transform · filter
text-decoration-line · text-decoration-color · cursor · visibility
```

Sixteen properties, enumerated rather than "diff everything", because a full computed-style diff
fires on `-webkit-*` internals, on `transition-property` itself, and on `perspective-origin`
recomputing from a box change — noise with a 100% false-positive rate against a design question.
`cursor` and `visibility` are in the set although they are not paint properties: `cursor:pointer`
appearing only on `:hover` is a real (weak) affordance signal, and `visibility` is how several
tooltip patterns in these apps enter.

### 2.3 Collapse C — caps, with the reason each number is that number

| Cap | Value | Reason |
|---|---|---|
| `--interactive-cap` | **400** nodes | Above 400 interactive nodes on one route, the page is a list of N identical rows; Collapse A has already reduced them to one class, so the 401st node adds a key computation and no class. Above the cap P9 keeps every node whose class is not yet represented and drops the rest — never a random sample. |
| `--class-cap` | **120** classes | Exceeding 120 *distinct* rule-set partitions on a single route means the route is a component gallery (`/ui-sh-demo` in `reso-management-app` is exactly this). Exit 13 tells the caller to run per-section rather than silently truncating a gallery's tail. |
| `--crop-cap` | **8** crops routed to vision | P5's session image-block ledger has ceiling 12 (P5 §3.1). Reserving 4 leaves the judge's own on-demand crops and P6's saliency second-image intact. Almost all state findings are computed-style deltas needing zero images; a crop is minted only for `focus-ring-adequacy` and `state-indistinguishable` (§3.4). |
| P1 state cells | **≤ 6** per route | Each named cell multiplies P1's own 6-cell viewport×theme product. Six state cells (`base`, `stress-3x`, `stress-12x`, `loading`, `empty`, `error`) is the full S3+S5 set; the S1/S2 axes are *not* cells at all — see §2.4. |

### 2.4 The decision that makes the arithmetic work: interaction states are CROPS, not PAGES

A hover state changes one component. Photographing the whole page for it costs a full-page raster to
carry ~1/40th of a page's worth of new information, and P1 §4.4 already shows a single page in two
themes producing ~32 Read-safe images. So the S1/S2 axes never become P1 cells. They are driven
inside `design-states assert`'s own browser pass, settled by computed-style delta, and produce an
image **only** when the delta exists and its *adequacy* is the open question. The crop is cut from
the element's `getBoundingClientRect()` + 16 px padding, at DPR 2, and asserted ≤ 1000×1000 CSS px
so it is lossless under the Read clamp (P1 §1.1). The state axis therefore costs O(1) images, not
O(states × elements).

---

## 3. Driving a state — three mechanisms and one confirmation rule

| | Mechanism | Reaches | Cost | Blind to |
|---|---|---|---|---|
| **M1** | `CSS.forcePseudoState(nodeId, [...])` via `context.newCDPSession(page)` → `DOM.getDocument` → `DOM.querySelector` | `:active :focus :focus-within :focus-visible :hover :target`, plus `:disabled :checked :open` and validity states on element types that support them | ~2–5 ms/node, no layout thrash | anything a JS handler sets — **all 207 `[data-hover]` rules** |
| **M2** | real input: `locator.hover()`, `.focus()`, `.click()`, `mouse.down()` | everything M1 reaches **plus** `pointerenter` handlers, `:has(:hover)` parents, library `data-*` state | ~50–150 ms/element (must await `transitionend` or seek) | nothing, but it is 20–50× slower and only one element can be hovered at a time |
| **M3** | script driver (`states/<cell>.js`, executed by P1 between R7 and R8) | prop states, route stubs, content stress | one nav | pseudo-classes |

**Routing rule.** M1 for the sweep over every class on the `:`-axis; **M2 for every class on the
attribute axis, unconditionally** (§1.3); M2 also for confirming any M1 class that comes back
*negative*, because chromium issue 343757697 reports `forcePseudoState` "does not always" apply, and
a state-forcing failure must be a loud skip rather than a silent "this element has no hover style".

**The confirmation rule, stated so it cannot be softened:** a `state-missing` finding requires
`(a)` the CSSOM candidate generator found no rule for that state on the element's class, **and**
`(b)` M2 real input produced zero delta across the sixteen watched properties. One arm alone is a
candidate, never a finding. `(a)` alone over-fires on `@layer`-shadowed rules; `(b)` alone over-fires
whenever a transition had not settled.

### 3.4 The two state findings that earn an image

| Rule | Deterministic part | Why a pixel is still needed |
|---|---|---|
| `focus-ring-adequacy` | `outline-width`, `outline-style`, `outline-offset`, `box-shadow` under forced `:focus-visible` — presence is a number | Ring *contrast against what it sits on* is P4's comparator when the backdrop is solid, and genuinely a pixel question over a gradient or image. The crop goes to P4 first; only P4's `INDETERMINATE` reaches the judge. |
| `state-indistinguishable` | the delta exists but is below a perceptual floor: ΔE < 2.0 in CIELAB **and** no geometry change | ΔE 2.0 is the standard just-noticeable-difference floor for large areas; below it the state technically changed and a user cannot tell. Whether that is a defect is a judgement, and judgement is the judge's. **Advisory-only** — Opus 5 scored 0/2 on sub-perceptual precision (a 5/255 drift), so this rule computes the number itself and asks the model only whether the *design intent* survives it. |

---

## 4. Motion, asserted rather than watched

On timing, **vision is strictly the worse instrument** (A10 §6): every property a motion review
asserts is already a number in the animation model, exact and CI-stable, while a frame strip adds
sampling error, instrument error and model nondeterminism to answer a question a perfect instrument
answered for free. §4 is therefore the whole of motion review except one defect class (§7).

### 4.1 The assertion table — what `motion.json` contains

Collected by arming `Animation.animationStarted` **before** the interaction, then reading
`animation.effect.getComputedTiming()` (which resolves `"auto"`) plus `effect.getKeyframes()`.

| Rule | Predicate | Severity | Source |
|---|---|---|---|
| `motion-duration-off-token` | `duration ∉ tokens.durations` (§4.2) | minor | A10 D1 |
| `motion-easing-off-token` | `easing ∉ tokens.easings`; **`linear` on an entrance/exit is always flagged** | minor | A10 D2 |
| `motion-non-composited` | any keyframe property ∉ `{transform, opacity, filter}` | major | A10 D3 |
| `motion-compositor-rejected` | trace `animation` event `failureReasonsMask != 0`; the report names the bit (`1<<11` box-size-dependent transform, `1<<13` + `unsupportedProperties`) | major | A10 §2.4 |
| `motion-iterations-unbounded` | `iterations === Infinity` on a non-decorative element (has an accessible name or is in the tab order) | major | A10 D1 |
| `motion-reduced-ignored` | §4.3 | **blocker** | A10 D12 |
| `layout-shift` | `Σ value where !hadRecentInput`; report `sources[].{node,previousRect,currentRect}` | major > 0.1, minor > 0.01 | A10 D7 |
| `interaction-latency` | `duration` > 200 ms, split into input delay / handler / presentation | major | A10 D5 |
| `main-thread-block` | LoAF `blockingDuration > 0`; names `scripts[].sourceURL` + `sourceFunctionName` | major | A10 D6 |
| `scroll-snap-broken` | after a programmatic scroll + `scrollend`, `scrollTop` ≠ any snap point | major | A10 D13 |
| `sticky-detached` | `rect.top` fails to clamp at the stick offset across sampled scroll offsets | major | A10 D13 |
| `scroll-timeline-misranged` | `a.timeline instanceof ScrollTimeline/ViewTimeline` and `progress` ∉ [0,1] at the range endpoints | minor | A10 D14 |

Thresholds and their reasons: **CLS 0.1** and **INP 200 ms** are the Core Web Vitals "good"
boundaries — chosen because they are the numbers the app's own performance tooling already reports,
so P9 cannot disagree with the app's dashboard about the same event. **LoAF's 50 ms** is the API's
own emission threshold, not ours. **`durationThreshold: 16`** on the `event` observer, not the
default 104 ms, because 104 hides exactly the 120–200 ms responses a design review cares about
(A10 §2.3) — 16 ms is the API's documented minimum.

Every assertion runs twice: `Emulation.setCPUThrottlingRate(1)` and `(4)`. A duration that holds at
1× and blows the INP budget at 4× is a real defect caught deterministically (A10 §2.5), and the
finding carries which arm fired. `--throttle 1` disables the second arm for a fast local loop.

### 4.2 The token allowlist is EXTRACTED, never hardcoded

A duration allowlist written into this spec would be a perishable fact restated where it cannot
learn it changed. `--tokens auto` resolves in this order and records which rung answered:

| Rung | Mechanism | Applies to |
|---|---|---|
| T1 | `getComputedStyle(document.documentElement)` → every custom property matching `/^--(duration|ease|transition|animate|motion)/`, values parsed to ms / easing strings | **reso-management-app** (Tailwind 4 + Panda emit theme tokens as CSS vars on `:root`) |
| T2 | read `tailwind.config.js` → `theme.transitionDuration` + `theme.transitionTimingFunction`, merged with Tailwind's defaults when the key is `extend` | **reso-landing-app** (Tailwind 3.4) |
| T3 | read the app's theme module (`theme/**/transition*.ts`) for a duration/easing map | **reso-web-app** (Chakra 2) |
| T4 | **no token source found** → do not invent one | — |

**T4 is not a pass.** With no token source, membership is unanswerable, so P9 asserts the weaker
*consistency* property instead: **≤ 3 distinct durations across all animations in one interaction**,
and flags any duration that appears exactly once alongside ≥ 4 uses of a neighbouring value within
±40 ms as `motion-duration-outlier`. Reason for 3: an entrance, an exit and a micro-feedback tier is
the full vocabulary of every token scale we found; a fourth distinct value inside one interaction is
almost always a hand-typed number. Reason for ±40 ms: below that, two values are a typo of each
other (200 vs 220); above it they are plausibly different tiers. The finding says
`tokens: unavailable — asserted consistency only`, so nobody reads it as conformance.

### 4.3 Reduced motion — a relative test, because an absolute one is unfalsifiable

A10 D12 calls this "the cleanest binary test in the table" and states it as *any animation with
`duration > ~0` under `reduce` is a defect*. Taken literally that is wrong in both directions: an
app that collapses a 300 ms slide to a 100 ms cross-fade has honoured the preference and would be
convicted, and an app whose animations are all 0 ms anyway would be acquitted without ever having a
reduced-motion branch. P9 runs it as a **paired** measurement:

```
A. emulateMedia({reducedMotion:'no-preference'}) → run interaction → record {id: duration}ₙ
B. emulateMedia({reducedMotion:'reduce'})        → run interaction → record {id: duration}ᵣ
   for every id where durationₙ > 100 ms:
       durationᵣ == durationₙ                       ⇒ motion-reduced-ignored   (blocker)
       durationᵣ <= 100 ms or animation absent      ⇒ honoured
       0 < durationᵣ < durationₙ                    ⇒ honoured (partial), recorded not flagged
```

**100 ms** is the in-scope floor, not a pass mark: below 100 ms the reduce/no-reduce distinction is
not perceived as motion, so both answers are acceptable and the test carries no information. This
is also why P1 §2.1 deliberately captures the `no-preference` branch by default and makes `reduce`
an *additional* cell — reviewing the `reduce` branch as "the design" reviews a page most users never
see and hides the motion defects the review exists to find.

**Measured, and it is a real finding waiting to happen:** `reso-management-app` has a
reduced-motion branch (Panda `_motionReduce`, `@media (prefers-reduced-motion)` in `globals.css`,
plus per-component handling). **`reso-landing-app` and `reso-web-app` have zero occurrences of
`prefers-reduced-motion`, `motion-reduce` or `useReducedMotion` in their sources** — and the landing
app is the one built on `framer-motion`. On those two, arm B will return `durationᵣ == durationₙ`
for every animation, and `motion-reduced-ignored` is the correct blocker.

---

## 5. The two clocks, the two documented holes, and the canary that makes the freeze falsifiable

### 5.1 The holes, stated exactly

| Lever | Controls | **Blind to** |
|---|---|---|
| `Animation.setPlaybackRate(0)` + `Animation.seekAnimations({animations, currentTime})` — and Playwright's `animations:'disabled'`, which implements the same half | CSS transitions, CSS animations, Web Animations (the WAAPI set) | **`requestAnimationFrame`** — every rAF-driven library |
| `page.clock.install()` + `clock.runFor(16)` | `Date`, `setTimeout`, `setInterval`, **`requestAnimationFrame`**, `requestIdleCallback`, `performance`, `Event.timeStamp` | **CSS animations/transitions and the document timeline** — the docs make no such claim |

A harness using one has a silent hole. P9 installs **both**, in this order, and P1 §3.3 already
mirrors it for the still path: clock at R0 (before any page script), stepped in 16 ms increments
through readiness so timers and rAF callbacks the page *needs* still fire, then stopped; WAAPI
playback rate set to 0 and seeked explicitly at each sample point.

One further trap that neither table names: `animations:'disabled'` fast-forwards finite animations
to completion and cancels infinite ones (Playwright's own docs). It yields **the end state, never a
mid-transition frame** — it is a determinism tool for stills and must never be used to sample the
interior of a transition. §7 seeks explicitly instead.

### 5.2 UNVERIFIED, and it is load-bearing

A10 §8 flags that **`page.clock` composing safely with `page.screencast` is not verified** — virtual
time versus wall-clock frame timestamps could desynchronise, which would corrupt precisely the
elapsed-ms labels §7 depends on. P9's default (`--frames auto`) therefore uses the **seek ladder**,
not the screencast, whenever every animation in the interaction is WAAPI-visible, and only falls
back to screencast for rAF-driven motion where the clock is the *only* lever. Where both are needed
in one interaction, P9 refuses to interleave them: it runs two passes and labels the rAF pass
`timebase: "virtual"`.

**The one probe that settles it:** install the clock, start a screencast, `runFor(160)`, and check
whether the ten arriving frames' `metadata.timestamp` values advance by ~16 ms each (virtual time is
driving the compositor) or by wall-clock intervals (they are independent). One page, one minute.

### 5.3 The canary — a freeze nobody tested is not a freeze

Both levers can be *installed* and still not be *effective*: `page.clock.install()` must run before
any page script (a `beforeInteractive` Next.js script defeats it), and `setPlaybackRate(0)` applies
to animations that exist at the time it is sent. A harness that assumes the freeze took produces
frames whose labels are fiction, and nothing in the output looks wrong.

So P9 injects a two-armed canary at `addInitScript` time and reads it at every sample point:

```js
// arm 1 — WAAPI: a 10 s linear animation on an off-screen 1×1 element
const c = document.createElement('div');
c.id = '__p9_canary'; c.style.cssText = 'position:fixed;left:-9px;top:-9px;width:1px;height:1px';
document.documentElement.appendChild(c);
c.__anim = c.animate([{opacity:0},{opacity:1}], {duration:10000, easing:'linear'});
// arm 2 — rAF: a monotonic tick counter
window.__p9_raf = 0;
(function tick(){ window.__p9_raf++; requestAnimationFrame(tick); })();
```

**The assertion, run twice with a real 250 ms of wall time between reads, after the freeze:**

| Arm | Frozen means | Failure |
|---|---|---|
| WAAPI | `getComputedStyle(c).opacity` identical across the two reads | exit 11 `FREEZE_UNPROVEN`, `arm: "waapi"` |
| rAF | `window.__p9_raf` identical across the two reads | exit 11, `arm: "raf"` — **the clock did not install before page script** |

This is the one mechanism in P9 that exists purely to make a *silent* success falsifiable, and it is
cheap: two `evaluate` calls and 250 ms. A frame set from a run whose canary did not freeze is not
evidence, and exit 11 says so rather than emitting a plausible strip.

---

## 6. The rAF-library census — "0 animations found" is a coverage verdict, never a pass

`document.getAnimations()` returns CSS Animations, CSS Transitions and Web Animations **only**.
GSAP drives its own rAF ticker and does not appear at all; nor do react-spring, Lenis, canvas/WebGL
motion, or any Motion/Framer-Motion animation that falls off its WAAPI fast path (non-`transform`/
`opacity` properties, layout animations, spring physics). Chrome's own DevTools Animations panel
states that "`requestAnimationFrame` animations are not yet supported."

### 6.1 The census, run before any assertion

```js
const probes = {
  gsap:          !!window.gsap || !!document.querySelector('[data-gsap]'),
  motion:        !!window.Motion || !!window.__FRAMER_MOTION__ || !!window.framerMotion,
  react_spring:  !!window.__REACT_SPRING__,
  lenis:         !!window.lenis || !!document.querySelector('[data-lenis]'),
  three:         !!window.__THREE__ || !!document.querySelector('canvas[data-engine]'),
  canvas2d:      [...document.querySelectorAll('canvas')].length,
  slick:         !!(window.jQuery && window.jQuery.fn && window.jQuery.fn.slick),
};
```

Bundler-mangled globals make every one of these a *false-negative-prone* probe, so the census has a
second, non-bypassable arm: **the rAF canary's own tick rate**. If `window.__p9_raf` advances by
more than 4 ticks during a 250 ms window in which `getAnimations()` returned an empty set, something
is animating that WAAPI cannot see, whatever the globals say. Reason for 4: idle React/Next apps
emit occasional rAF from scheduling and scroll handlers; a sustained animation runs at ~15 ticks per
250 ms at 60 Hz, so 4 separates "a couple of housekeeping callbacks" from "a ticker is running".

### 6.2 The population this actually applies to — measured, and it is all three apps

| App | rAF-capable motion source | Consequence for a WAAPI-only harness |
|---|---|---|
| `reso-landing-app` | `framer-motion@^11`, `@headlessui/react@^2` transitions | v11 uses WAAPI for accelerable values but falls back to rAF for layout/spring/non-accelerable properties — **partial coverage, and which half is invisible depends on the animation** |
| `reso-management-app` | `motion@^12.38`, **`@react-three/fiber@^9` + `@react-three/drei`** | r3f's render loop is pure rAF inside a WebGL canvas. Not merely invisible to `getAnimations()` — invisible to *every* DOM instrument, and it also defeats P1's byte-stability gate, which is why it must be named, not silently tolerated |
| `reso-web-app` | `framer-motion@^7`, **`react-slick@^0.29`** | slick's autoplay is an interval-driven infinite carousel; `getAnimations()` will report it as nothing |

**Consequence for the report.** `coverage.json` carries `raf_uncovered: ["motion@12", "r3f@9"]`, and
P7 renders it as a sentence in the report body, above the findings: *"Motion review covered the
WAAPI animation set. This page also runs <N> rAF-driven sources; a clean motion result is not
evidence of correctness for them."* A count in a JSON field that nobody prints is how this false
green survives.

**Recovery, in the order A10 gives:** (1) name the gap; (2) reconstruct the curve deterministically
— `page.clock.install()` + `runFor(16)` in a loop, sampling `getComputedStyle(el).transform` and
`.opacity` per virtual frame, which works precisely because the clock *does* patch rAF; (3) frames.
Rung 2 is a real deterministic motion review for a rAF library and it produces the same duration and
easing numbers §4.1 asserts — it is fitted from the sampled curve, and the finding carries
`method: "clock-sampled"` so it is never confused with a WAAPI-read value.

---

## 7. The frame residue — one defect class, one question, ≤9 images

### 7.1 What genuinely needs frames

Exactly one class: **a mid-interpolation rendering artifact — a frame whose timing model is entirely
correct and whose composited pixels are wrong.** Every instrument in §4 reads the animation *model*
or the main-thread *timeline*; none rasterises. All of these return a clean green from WAAPI, CDP,
LoAF, Event Timing and the compositor audit while looking broken on screen:

- an element flickering to the wrong stacking order because an animated `transform` creates a new
  stacking context part-way through;
- text going blurry mid-transition because a scaled transform rasterises on non-integer boundaries;
- a `backdrop-filter` panel showing a hard seam only while its parent animates;
- a `clip-path` briefly revealing a background it should never expose;
- a shadow or gradient banding at intermediate opacity;
- an image popping from placeholder to final inside what the model reports as one continuous fade.

Ask WAAPI: `duration: 300, easing: 'ease-out', progress: 0.5` — perfect green. Ask CLS: **0**,
because the Layout Instability spec excludes transform-driven movement from the score by design. Ask
LoAF: nothing, because the animation is composited and the main thread was idle. Two of these
(`backdrop-filter` seams, `clip-path` reveals) are live risks in `reso-management-app`, whose bottle-
service surfaces animate scrims and morph panels.

### 7.2 Sampling — a deterministic seek ladder, and elapsed ms is the only index

**Default (WAAPI-visible motion): the seek ladder.** `Animation.setPlaybackRate(0)`, then
`Animation.seekAnimations({animations, currentTime: t})` for `t ∈ {0, 12.5, 25, 37.5, 50, 62.5, 75,
87.5, 100}%` of the computed `activeDuration`, screenshotting each. Nine points, not five: five is
enough to *explain* a known failure, and the artifacts above occupy 1–2 frames, so a 25% stride at
300 ms samples every 75 ms and can step over a 33 ms flicker entirely. Nine at 37.5 ms stride is the
densest ladder that still fits §7.3's image ceiling. This path is fully deterministic — same shas on
re-run — which is what lets P7 subtract a control.

**Fallback (rAF-driven motion): screencast, selected by timestamp.**

```js
const frames = [];
const sc = await page.screencast.start({ onFrame: f => frames.push(f), quality: 90 });
await interact();
await sc.stop();
// f = { data: JPEG bytes, timestamp: ms since epoch, viewportWidth, viewportHeight }
```

Frame rate is **not documented** — frames arrive as the compositor produces them. So P9 selects by
elapsed ms against the interaction's `t0`, nearest-neighbour with a **±8 ms** tolerance, and never by
index. Reason for 8 ms: Event Timing rounds `duration` to 8 ms, so a tighter tolerance claims a
precision the surrounding measurements do not have. A requested point with no frame inside ±8 ms is
emitted as `missing`, not as its nearest neighbour — the strip must be able to say a frame is
absent. Fallback for any Playwright without `page.screencast`: CDP `Page.startScreencast({format:
'jpeg', quality: 90, everyNthFrame: 1})` + `Page.screencastFrame` → `metadata.timestamp`, then
`screencastFrameAck`.

🚨 **Never review motion from a Playwright `recordVideo` `.webm`.** VP8, variable frame rate,
visibly compressed with mosquito noise around glyph edges, and no guarantee of a frame at any
instant. It is a debugging receipt, not an instrument — and mosquito noise around glyphs is
indistinguishable from the text-blur artifact this section exists to find.

### 7.3 Presentation — separate full-resolution frames, never a contact sheet at first pass

| Shape | Visual tokens | Per-frame fidelity |
|---|---|---|
| 9 frames sent separately, native 1440×900 | 9 × 1,716 = **15,444** | 100% each |
| 3×3 contact sheet (downscaled to fit both caps) | ~4,700 | cell ~803×502 ⇒ **56% linear, 31% of the pixels** |

The sheet's 3.3× saving costs 69% of the pixels — precisely the pixels a 1 px seam, a blurred glyph
or a 4 px ring live in. Nine separate frames also stay under the **20-image-block** threshold, above
which the per-image cap tightens and oversized images are **rejected rather than downscaled** — a
hard request failure. The sheet is correct only when >20 frames are genuinely needed, and then only
for triage: **contact sheet to locate the window → re-send that 3-frame window at full resolution.**

Frames are labelled in text immediately before each image, carrying elapsed ms — a still-image model
reads reading order as a temporal prior, and the label is what stops it inventing one:

```
Frame 1 — t=0 ms:      <image>
Frame 2 — t=37 ms:     <image>
…
Frame 9 — t=300 ms:    <image>
```

### 7.4 The prompt — verbatim, and fenced to one question

```text
These 9 frames are consecutive samples of a single UI transition, in order, with the elapsed
time from the start of the interaction given in each label.

Frames 1 and 9 are the ENDPOINTS and are known-good: they have already been reviewed as still
images and any defect in them has been reported elsewhere.

In frames 2 through 8 ONLY, identify any rendering artifact that is absent from BOTH endpoints:
  - an element drawn in front of or behind something it should not be (z-order flicker)
  - text that is blurry, doubled, or differently weighted than in the endpoints
  - a hard seam, edge, or band where the endpoints show a smooth surface
  - content clipped, or a background revealed, that neither endpoint exposes
  - an image, icon, or placeholder that pops or swaps

For each, report: the frame number(s), the region in words, and what is wrong.
If there is none, reply exactly: NONE.

Do NOT comment on timing, duration, easing, speed, or whether the motion feels right.
Those are measured exactly elsewhere and your estimate of them would be wrong.
```

**Why the fence is the whole design.** Given timings in the prompt a vision model will re-litigate
them and emit confident, wrong duration estimates derived from an unknown sampling rate. Restricting
it to the artifact question is what makes its output additive rather than noise competing with an
exact measurement. It also matches the measured shape of the model we have: Opus 5 scored 2/2 on
judgement/semantic/gestalt defects and 0/2 on sub-perceptual precision, with zero false positives —
"does any frame contain something the endpoints do not" is a gestalt comparison, which is the half
it wins.

**Every finding from this pass enters `findings/motion-frames.json` as `layer:"judgement"`,
`severity:"advisory"`, and P7 caps it there.** Per the June 2026 standing ruling, taste stays human
and gates adjudicate correctness and coverage only; a vision verdict on motion is triage, never a
CI gate. The finding text is written as *"artifact at t≈150 ms, frames 5–6"* and **never** as a
timing claim.

### 7.5 Why not video, and why not Gemini here

Claude ingests images only — "Animations are unsupported, and only the first frame is used" — so an
animated GIF is a still, and the frame set is ours to build either way. Gemini samples video at
**1 frame per second by default**: a 200 ms transition sampled at 1 FPS appears in zero or one frame,
and the model still returns a confident answer. That is the most dangerous default in the vision
path. Gemini at `fps=30, media_resolution=low` (66 tok/frame) is genuinely ~8× cheaper per frame and
is the right tool **above ~30 frames** — a long scroll-driven sequence, not a 300 ms transition. Even
then, `fps` is doc-inconsistent across Google's own two pages and must be probed on the target model
before it is relied on, because a silently-ignored `fps` degrades to 1 FPS and still answers.

---

## 8. The artifacts, in full

### 8.1 `state-plan.json` — the contract with P1

```json
{
  "schema": "design-states/1",
  "ok": true,
  "target": "http://localhost:3000/reservations",
  "dom_sha": "sha256:41c9…",
  "sources": {
    "pseudo":    { "rules": 419, "blind_sheets": 0 },
    "attribute": { "rules": 288, "distinct": ["data-hover","data-disabled","data-focus-visible","data-press","data-state","data-selected"] },
    "prop":      { "declared": 4, "driven": 0, "source": "none", "why": "no storybook, no route fixtures supplied" },
    "rtl":       "no-signal",
    "stress":    [1, 3, 12]
  },
  "classes": 63,
  "cells": [
    { "name": "base",       "driver": null },
    { "name": "stress-3x",  "driver": "/abs/states/stress-3x.js" },
    { "name": "stress-12x", "driver": "/abs/states/stress-12x.js" }
  ],
  "interaction_states": [
    { "class": "c07", "state": "hover", "axis": "attribute", "mechanism": "M2",
      "representative": "button.lt-rail[data-press=nav]", "members": 14,
      "css_box": [24, 96, 232, 44] }
  ],
  "warnings": []
}
```

`cells[]` maps 1:1 onto P1's `--states name=path.js`. `interaction_states[]` is **not** for P1 — it
is P9's own worklist for `assert`, and its `css_box` is what a crop would be cut from if §3.4 fires.

### 8.2 Findings — P7's schema, plus three fields P7 reads

```json
{ "rule": "motion-reduced-ignored",
  "target": { "backendNodeId": 8123, "selector": "[data-modal-skin] .scrim" },
  "detail": "scrim-out runs 240 ms under prefers-reduced-motion:reduce, identical to the no-preference arm",
  "severity": "blocker",
  "layer": "dom",
  "method": "waapi",
  "arm": "throttle-1x",
  "evidence": { "duration_normal": 240, "duration_reduce": 240, "easing": "ease", "animation_name": "scrim-out" } }
```

`method` ∈ `waapi | clock-sampled | forced-pseudo | real-input | trace | observer | frames`. It
exists so P7 never merges a WAAPI-read duration with a curve-fitted one under a single
`(rule, target)` key — the *span must equal the subject*, and a fitted number and a read number are
different subjects even when they agree.

### 8.3 `coverage.json` — the population this stage could not reach

```json
{ "raf_uncovered": ["motion@12.38", "@react-three/fiber@9"],
  "raf_canary_ticks_per_250ms": 17,
  "waapi_animations_seen": 0,
  "cssom_blind_sheets": 0,
  "attribute_states_driven": 6,
  "pseudo_states_forced": 9,
  "prop_states_driven": 0,
  "classes_abstained": [{ "class": "c31", "why": "state-force-failed", "state": "focus-visible" }],
  "verdict": "PARTIAL" }
```

`waapi_animations_seen: 0` beside `raf_canary_ticks_per_250ms: 17` is the exact false-green shape
§6 exists to catch, and `verdict` is `PARTIAL`, never `CLEAN`, whenever `raf_uncovered` is non-empty.

---

## 9. What this stage cannot do

| Cannot | Who owns it |
|---|---|
| Say whether a transition *feels* right, or whether choreography reads as originating from its trigger | Nobody, deliberately. Stagger delays and transform-origins are numbers (§4.1); the residue is aesthetic preference, and taste stays human (June 2026 ruling). |
| See motion inside a `<canvas>` / WebGL surface (`@react-three/fiber`) | Nobody. It is invisible to every DOM instrument and to the frame path's determinism. §6 names it; a future stage would need a canvas-pixel differ. |
| Measure dropped frames / `PercentDroppedFrames` | A Chrome trace (`PipelineReporter` events) via CDP `Tracing`. There is no `PerformanceObserver` equivalent, and rAF-based FPS counters are explicitly an anti-pattern. P9 asserts *will-it-jank* (`failureReasonsMask`) instead of *did-it-jank*. |
| Detect a composited animation stuttering from raster or GPU-memory pressure | Nothing here. LoAF is main-thread only; the animation produces no LoAF and no long task. It routes to §7's frame residue or to nothing. |
| Enumerate which network call produces a loading/empty/error state | The caller, via `--interactions` route fixtures (§1.4). |
| Turn any of this into a source-line fix | **P8** |
| Decide whether a frame strip is worth its image blocks | **P5** |

---

## 10. UNVERIFIED register — each with the one probe that settles it

| # | Claim | Probe |
|---|---|---|
| U1 | `page.clock` composes safely with `page.screencast` (virtual time vs wall-clock frame timestamps) | §5.2 — install clock, start screencast, `runFor(160)`, check whether 10 frames' `metadata.timestamp` advance by ~16 ms each. One page, one minute. |
| U2 | `framer-motion@7` (reso-web-app) has **no** WAAPI path at all, so 100% of its animations are rAF-invisible; `@11` (reso-landing-app) has a partial one | On each app: animate one `opacity` and one `width`, read `document.getAnimations().length` after each. 0 vs 1 settles the version's fast path per property. |
| U3 | The in-page CSSOM index (§2.1) partitions elements identically to `CSS.getMatchedStylesForNode` | Run both on 20 sampled nodes of `/ui-sh-demo` and diff the partitions. A disagreement means `@layer`/`:where()` ordering is doing something the index cannot model. |
| U4 | `CSS.forcePseudoState` failure rate on Ark UI / Base UI components (chromium 343757697) | Force `:hover` on 50 classes, then repeat with real `hover()`, and count classes where the deltas differ. If it is >0, M1 is a *pre-filter* only and M2 must run everywhere. |
| U5 | 9 seek-ladder points is dense enough for the artifacts in §7.1 | Inject a known 2-frame z-order flicker at a known `t`, and check the 9-point ladder catches it at 200/300/500 ms durations. This is also the acceptance corpus this stage needs and does not have. |
| U6 | Sub-100 ms reduced-motion animations are genuinely not perceived as motion (the §4.3 in-scope floor) | Not settleable by a probe here — it is a perceptual claim. If it matters, lower the floor to 0 and accept the partial-honour rows as informational. |

---

## 11. Threshold summary

| Threshold | Value | Reason |
|---|---|---|
| interactive-node cap | 400 | above it, nodes add key computations and no classes (Collapse A) |
| equivalence-class cap | 120 | above it the route is a component gallery ⇒ exit 13, run per section |
| state crops to vision | 8 | P5 ledger ceiling 12, minus 4 reserved for the judge's own crops + saliency |
| P1 state cells | ≤6 | the full S3+S5 set; S1/S2 never become cells (§2.4) |
| watched properties | 16 | enumerated; a full computed-style diff is 100% noise on this question |
| stress multipliers | 1, 3, 12 | control · wrap/ellipsis regime · container-overflow regime |
| text node cap | 4000 chars | a 12× pass on an article must not build a 200 MB DOM |
| `event` durationThreshold | 16 ms | the API minimum; the 104 ms default hides 120–200 ms responses |
| INP budget | 200 ms | Core Web Vitals "good" — the number the app's own tooling reports |
| CLS budget | 0.1 major / 0.01 minor | same |
| CPU throttle arms | 1× and 4× | a marginal animation becomes reproducibly failing at 4× |
| reduced-motion in-scope floor | 100 ms | below it the reduce/no-reduce distinction carries no information |
| duration-outlier window | ±40 ms | below, two values are a typo of each other; above, plausibly different tiers |
| distinct durations per interaction (T4) | ≤3 | entrance · exit · micro-feedback is the full vocabulary of every token scale found |
| ΔE floor for `state-indistinguishable` | 2.0 CIELAB | standard large-area just-noticeable-difference |
| seek-ladder points | 9 | 5 steps over a 33 ms artifact at 300 ms; 9 is the densest that fits the image ceiling |
| frame-selection tolerance | ±8 ms | Event Timing rounds `duration` to 8 ms; tighter claims precision we do not have |
| frames to the judge | ≤9 separate | 15,444 visual tokens, under the 20-image-block cliff, 100% per-frame fidelity |
| canary freeze window | 250 ms | long enough that a 60 Hz ticker advances ~15 ticks; short enough to run at every sample |
| rAF idle tick threshold | 4 per 250 ms | separates housekeeping callbacks from a running ticker |
