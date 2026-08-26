# A10 — Motion & Interaction Review: closing the "cannot evaluate from stills" blind spot

Research date **2026-08-26**. Consumer: Claude Code sessions driving Playwright/Chromium.
Scope: what a still screenshot cannot show — motion, transitions, hover/focus/active states,
scroll behaviour, layout instability — and how an agent reviews it as of August 2026.

**Headline.** The blind spot is largely *not* a vision problem. Most of what our corpus filed as
"animation/transition issues — cannot evaluate from stills" is exactly readable as a number from
`getAnimations()`, the CDP `Animation` domain, and three `PerformanceObserver` entry types, with
zero pixels and zero model nondeterminism. The genuinely vision-shaped residue is one narrow class
(§6). The correct architecture is **deterministic-first, vision-as-residue**, and the biggest
practical hazard is not the vision tier but a *silent* deterministic hole: rAF-driven animation
libraries are invisible to every WAAPI-based instrument (§4.1).

---

## 1. Defect table — dynamic design defects, evidence, judgement, tool

| # | Defect | How to capture evidence | How to judge it | Tool / model |
|---|---|---|---|---|
| D1 | Transition duration wrong (too slow / too fast vs token) | `el.getAnimations()` -> `a.effect.getComputedTiming().duration` | Numeric assert vs design-token allowlist (e.g. `{120,200,320}`) | **Deterministic** — WAAPI, no vision |
| D2 | Easing wrong (linear where `ease-out` specified; wrong cubic-bezier) | `getComputedTiming().easing` (string, e.g. `cubic-bezier(0.4,0,0.2,1)`); per-keyframe via `effect.getKeyframes()[i].easing` | String match vs token set; flag `linear` on entrance/exit | **Deterministic** |
| D3 | Wrong property animated (animating `height`/`top` not `transform`) | `effect.getKeyframes()` property keys; CDP `Animation.AnimationEffect.keyframesRule` | Any keyframe key outside `{transform,opacity,filter}` => will not composite | **Deterministic** |
| D4 | Animation janks / drops frames | Chrome trace event `animation` -> `failureReasonsMask` + `unsupportedProperties`; Lighthouse `non-composited-animations` | Nonzero mask => named, actionable reason (§2.4) | **Deterministic** — trace/Lighthouse |
| D5 | Interaction feels unresponsive | `PerformanceObserver({type:'event', durationThreshold:16})` -> `processingStart-startTime` (input delay), `processingEnd-processingStart` (handler), `duration` (to next paint) | INP budget: good <=200 ms; split the three components to attribute | **Deterministic** — Event Timing |
| D6 | Main-thread stall during the interaction | `PerformanceObserver({type:'long-animation-frame'})` -> `blockingDuration`, `scripts[].sourceURL/sourceFunctionName/forcedStyleAndLayoutDuration` | LoAF fires >50 ms; `blockingDuration>0` names the script | **Deterministic** — LoAF |
| D7 | Layout instability (content jumps) | `PerformanceObserver({type:'layout-shift', buffered:true})` -> `value`, `sources[].{node,previousRect,currentRect}` | Sum `value` where `!hadRecentInput`; `sources` names the culprit node and its two rects | **Deterministic** — Layout Instability API |
| D8 | Missing hover affordance on an interactive element | CSSOM sweep: enumerate `document.styleSheets` rules whose `selectorText` contains `:hover`; intersect with `querySelectorAll('a,button,[role=button],[tabindex]')` | Interactive element matched by **no** `:hover` rule => defect | **Deterministic** — CSSOM (caveat §4.3) |
| D9 | Missing / invisible `:focus-visible` ring | CDP `CSS.forcePseudoState(nodeId,['focus-visible'])`, then screenshot + `getComputedStyle` for `outline*`, `box-shadow` | `outline-width:0` / `outline-style:none` with no compensating `box-shadow` => defect; ring *contrast* is a pixel judgement | **Hybrid** — CDP forces state; contrast needs pixels |
| D10 | `:active` / pressed state absent or identical to rest | `CSS.forcePseudoState(...,['active'])` + computed-style diff vs base | Zero computed-style delta => no pressed feedback | **Deterministic** |
| D11 | Disabled / loading / empty / error states unstyled or unreachable | Storybook story per state + `play()`; or `CSS.forcePseudoState(['disabled'])`; or prop-driven render | Screenshot per state + computed-style delta; assert each state exists as a story | **Hybrid** — Storybook/Playwright drive, vision judges |
| D12 | `prefers-reduced-motion` ignored | `page.emulateMedia({reducedMotion:'reduce'})`, run the interaction, then `document.getAnimations()` | Any animation with `getComputedTiming().duration > ~0` under `reduce` => defect. Cleanest binary test in the table | **Deterministic** |
| D13 | Scroll behaviour wrong (no smooth scroll, broken snap, sticky detaches) | `getComputedStyle(el).scrollBehavior / scrollSnapType / position`; sample `el.scrollTop` + `getBoundingClientRect()` across scripted scroll offsets | Snap: after a scroll + `scrollend`, `scrollTop` must equal a snap point. Sticky: `rect.top` must clamp at the stick offset across offsets | **Deterministic** |
| D14 | Scroll-driven animation mis-ranged | `getAnimations()` -> `a.timeline instanceof ScrollTimeline/ViewTimeline`; CDP `Animation.viewOrScrollTimeline` | Assert range start/end; drive by setting scroll offset, read `getComputedTiming().progress` | **Deterministic** |
| D15 | View Transition broken (old/new snapshot mismatch, wrong group) | `document.getAnimations().filter(a => a.effect.pseudoElement?.startsWith('::view-transition'))`; `transition.ready` is the assertion point | Assert the expected `::view-transition-group(name)` set exists and its timings | **Deterministic** for structure; **vision** for the composite |
| D16 | **Mid-interpolation rendering artifact** — z-order flicker, text blur under scaled transform, `backdrop-filter` seam, clip-path reveal, shadow banding | Frame sequence at >=30 fps through the transition | Vision judge on the frames; **no timing instrument can see this** | **Vision only** — see §6 |
| D17 | Choreography reads wrong (motion doesn't originate from the trigger; stagger order wrong) | Frame sequence + the element's transform-origin / keyframe path | Partly deterministic (stagger delays are numbers); the "reads as" part is aesthetic | **Hybrid** |

---

## 2. What you can assert with **zero vision** — the deterministic core

### 2.1 Web Animations API — the primary instrument
`document.getAnimations()` returns every **CSS Animation, CSS Transition, and Web Animation** in
effect; `Element.getAnimations({subtree:true})` scopes it to a component.
<https://developer.mozilla.org/en-US/docs/Web/API/Document/getAnimations>

Per animation, `animation.effect.getComputedTiming()` yields — with `"auto"` already resolved —
`delay`, `endDelay`, `duration`, `iterations`, `iterationStart`, `direction`, `fill`, `easing`,
plus purely computed `activeDuration` (= `duration x iterations`), `endTime`
(= `activeDuration + delay + endDelay`), `localTime`, `progress`, `currentIteration`.
<https://developer.mozilla.org/en-US/docs/Web/API/AnimationEffect/getComputedTiming>

Subclass discriminators tell you *what kind* of motion it is without guessing:
`CSSTransition.transitionProperty`, `CSSAnimation.animationName`, and `effect.pseudoElement`
(which is how you pick out `::view-transition*`).

**This answers the brief's question directly:** "this transition is 400 ms and eases wrong" is
`a.effect.getComputedTiming().duration === 400 && a.effect.getComputedTiming().easing === 'linear'`.
Exact, cheap, CI-stable, no pixels.

### 2.2 Freezing time for a reproducible still
Two levers, **and neither alone is complete** (sharpest finding in §4.1):

| Lever | Controls | Does NOT control |
|---|---|---|
| `animation.currentTime = t` / CDP `Animation.setPlaybackRate(0)` + `Animation.seekAnimations({animations,currentTime})` | WAAPI: CSS transitions, CSS animations, Web Animations | rAF-driven JS animation |
| Playwright `page.clock.install()` + `clock.runFor(16)` | `Date`, `setTimeout`, `setInterval`, **`requestAnimationFrame`**, `requestIdleCallback`, `performance`, `Event.timeStamp` | CSS animations/transitions and the document timeline (docs make no such claim) |

CDP: <https://chromedevtools.github.io/devtools-protocol/tot/Animation/> ·
Clock: <https://playwright.dev/docs/clock> (Playwright >=1.45)

So: **WAAPI seek for CSS motion, clock-step for rAF motion.** A harness using only one has a silent hole.

Playwright's screenshot assertion implements the WAAPI half:
> `animations` — "When set to `"disabled"`, stops CSS animations, CSS transitions and Web Animations.
> Animations get different treatment depending on their duration: finite animations are
> fast-forwarded to completion, so they'll fire `transitionend` event. infinite animations are
> canceled to initial state, and then played over after the screenshot."
> — <https://playwright.dev/docs/api/class-pageassertions>

Consequence: `animations:'disabled'` gives the **end state**, never a mid-transition frame. It is a
determinism tool for stills, not a motion-review tool.

### 2.3 The three PerformanceObserver entry types

| Entry type | Reads | Key fields | Limit |
|---|---|---|---|
| `layout-shift` | visual instability | `value`, `hadRecentInput`, `lastInputTime`, `sources[].{node,previousRect,currentRect}`; score = impact fraction x distance fraction | **Excludes transform-driven movement by design** — see §6 |
| `event` / `first-input` | interaction latency | `startTime`, `processingStart`, `processingEnd`, `duration` (rounded to 8 ms); default `durationThreshold` 104 ms, **minimum 16 ms** | Baseline 2025; `duration` is capped at next paint |
| `long-animation-frame` | main-thread jank | `duration`, `blockingDuration`, `renderStart`, `styleAndLayoutStart`, `firstUIEventTimestamp`, `scripts[].{sourceURL,sourceFunctionName,invoker,invokerType,forcedStyleAndLayoutDuration,pauseDuration}`; threshold 50 ms | **Main thread only** — a composited animation janking on the raster/compositor thread produces no LoAF |

<https://developer.mozilla.org/en-US/docs/Web/API/LayoutShift> ·
<https://developer.mozilla.org/en-US/docs/Web/API/PerformanceEventTiming> ·
<https://developer.mozilla.org/en-US/docs/Web/API/PerformanceLongAnimationFrameTiming>

Set `durationThreshold: 16` on the `event` observer — the default 104 ms hides exactly the
120-200 ms responses a design review cares about.

### 2.4 Will-it-jank, without watching it
Chrome writes compositor-rejection reasons into the trace; Lighthouse's `non-composited-animations`
audit reads the `animation` trace event's `failureReasonsMask` + `unsupportedProperties`:

| Bit | Reason |
|---|---|
| `1 << 3` | Effect has unsupported timing parameters |
| `1 << 4` | Effect has composite mode other than `replace` |
| `1 << 6` | Target has another animation which is incompatible |
| `1 << 11` | Transform-related property depends on box size |
| `1 << 12` | Filter-related property may move pixels |
| `1 << 13` | Unsupported CSS property (names carried in `unsupportedProperties`) |

<https://github.com/GoogleChrome/lighthouse/blob/main/core/audits/non-composited-animations.js> ·
<https://developer.chrome.com/docs/lighthouse/performance/non-composited-animations>

For actual smoothness, `PercentDroppedFrames` from the trace's `PipelineReporter` events is the
metric; there is **no web-exposed API** for it, and web.dev explicitly names rAF polling an
anti-pattern — it "doesn't actually capture all types of animation updates" and misses variable
update frequency. <https://web.dev/articles/smoothness>

### 2.5 CPU pressure as a deterministic amplifier
`Emulation.setCPUThrottlingRate` (slowdown factor: 1 = none, 4 = 4x) turns a marginal animation into
a reproducibly failing one. Run every motion assertion at 1x **and** 4x; a duration that holds at 1x
and blows the INP budget at 4x is a real defect, deterministically caught.
<https://chromedevtools.github.io/devtools-protocol/tot/Emulation/>

---

## 3. Capturing the states that need input

### 3.1 Real interaction (highest fidelity) — the default
`locator.hover()`, `.focus()`, `.click()` dispatch real input events, so the browser's own
`:hover`/`:focus-visible` machinery, JS `pointerenter` handlers, and `:has(:hover)` parent rules all
behave exactly as in production. Cost: the state is transient — you must wait for `transitionend`
(or seek, §2.2) before a screenshot.

### 3.2 Forced pseudo-state (highest throughput)
CDP `CSS.forcePseudoState(nodeId, forcedPseudoClasses[])` — "ensures that the given node will have
specified pseudo-classes whenever its style is computed."
<https://chromedevtools.github.io/devtools-protocol/tot/CSS/>

DevTools exposes this set for all elements: **`:active`, `:focus`, `:focus-within`,
`:focus-visible`, `:hover`, `:target`**, plus element-specific ones under "Force specific element
state" (`:disabled`, `:checked`, `:open`, validity states).
<https://developer.chrome.com/docs/devtools/css/reference>

Playwright has no first-class API — go through `context.newCDPSession(page)` -> `DOM.getDocument` ->
`DOM.querySelector` -> `CSS.forcePseudoState`. Open feature request since 2020:
<https://github.com/microsoft/playwright/issues/3347>

WARNING: forced state changes **style computation only**. It does not fire `pointerenter`, does not
run a JS hover handler, and (chromium issue 343757697) does not always propagate reliably. Use it
for a batch sweep; confirm anything that fails with a real `hover()`.

### 3.3 Storybook
`play()` functions drive real interactions per story (`userEvent.hover/click/tab`) and are the
systematic way to enumerate **loading / empty / error / disabled** — states that are *props*, not
pseudo-classes, and therefore unreachable by any state-forcing API.
<https://storybook.js.org/docs/writing-tests/interaction-testing/>

`@storybook/addon-pseudo-states` is the weakest of the three mechanisms: it "rewrites all document
stylesheets to add a class name selector to any rules that target a pseudo-class" and toggles those
classes on the story container. Specificity, `:has()`, and `:focus-visible`'s heuristic all diverge
from the real thing. <https://storybook.js.org/addons/storybook-addon-pseudo-states>

### 3.4 State-coverage audit — the systematic part the brief asks for
Do not enumerate states by hand. Enumerate them from the CSS:

```js
// every selector in the page that targets an interactive pseudo-class
const wanted = /:hover|:focus-visible|:focus|:active|:disabled/;
const rules = [...document.styleSheets].flatMap(s => {
  try { return [...s.cssRules]; } catch { return []; }   // cross-origin sheets throw
});
const stateful = rules.filter(r => r.selectorText && wanted.test(r.selectorText));
```

Then (a) assert every interactive element matches at least one `:hover` and one `:focus-visible`
rule, and (b) generate the capture matrix from `stateful` rather than from a hand-written list.
WARNING: cross-origin stylesheets throw on `.cssRules` (CORS) — count them and report the blind
fraction rather than silently reading 0.

---

## 4. Adversarial pass — what a hostile reviewer would say I missed

### 4.1 "Your deterministic core is blind to the animation libraries people actually ship." — Correct, and this is the largest hole.
`document.getAnimations()` returns CSS Animations, CSS Transitions and Web Animations **only**.
GSAP drives everything through its own rAF ticker and is not part of the WAAPI spec, so GSAP tweens
do not appear at all. Same for react-spring, Lenis smooth-scroll, canvas/WebGL motion, and any
Motion / Framer-Motion animation that falls off its WAAPI fast path (non-`transform`/`opacity`
properties, layout animations, spring physics). Corroborated independently by the DevTools
Animations panel, which states that "`requestAnimationFrame` animations are not yet supported."
<https://developer.chrome.com/docs/devtools/css/animations>

**Mitigations, in order:** (1) detect the library at review time (`window.gsap`, `window.Motion`,
`__FRAMER_MOTION*`) and *report the coverage gap* rather than returning a clean bill;
(2) `page.clock.install()` + `runFor(16)` in a loop, sampling `getComputedStyle(el).transform` /
`.opacity` per virtual frame — this reconstructs the timing curve of a rAF animation
deterministically, because clock **does** patch rAF; (3) fall back to frames.
A harness that reports "0 animations found" on a GSAP page is the exact false-green this section
exists to prevent.

### 4.2 "LoAF and CLS make you think you've covered jank and instability." — Partly false on both.
LoAF is main-thread only; a composited transform animation that stutters from raster or GPU memory
pressure produces **no LoAF entry and no long task**. And the Layout Instability spec excludes
transform-driven movement from the shift score by design — which is exactly why a transform-based
motion bug scores CLS 0. Both blind spots route to §6.

### 4.3 "Your CSSOM sweep will lie." — Yes, in three ways.
Cross-origin sheets throw (report the count). Rules inside unopened `@media`/`@container` blocks are
present in the CSSOM but may never apply. And `@layer` / `:where()` change specificity such that a
matching `:hover` rule may be overridden — presence of a rule is not proof of a visible effect.
Confirm any D8 finding by forcing `:hover` and diffing computed style.

### 4.4 "You cited a claim you could not verify." — Flagged, not used.
A search result (`aidailyshot.com`, "Anthropic Releases Claude API for Real-Time Video", 2026) claims
a Claude real-time video API with "<500 ms per frame" latency and 4K / H.264 / VP9 support. This is
**contradicted by Anthropic's own current vision documentation**, which lists only JPEG/PNG/GIF/WebP
and states "Animations are unsupported, and only the first frame is used." The corresponding Claude
Code feature request (anthropics/claude-code#32130, opened 2026-03-08) was **closed as not planned**.
Treat the video-API claim as unsubstantiated; plan for frames.

### 4.5 "1 FPS." — The default that silently destroys the exercise.
Gemini samples video at **1 frame per second** by default. A 200 ms transition sampled at 1 FPS
appears in zero or one frame. Any motion review that uploads a video without setting `fps`
explicitly is measuring nothing — and will still produce a confident answer. This is the single most
dangerous default in the vision path.

---

## 5. Model comparison — who can actually ingest motion (Aug 2026)

### 5.1 Video-capable models

| Model | Video input | Sampling control | Cost per frame | Practical ceiling |
|---|---|---|---|---|
| **Gemini 3 Pro / 2.5 series** | **Yes**, native. MP4/MPEG/MOV/AVI/FLV/MPG/WebM/WMV/3GPP; inline <100 MB, File API 20 GB paid / 2 GB free; Cloud Storage 2 GB per file | **Yes** — `videoMetadata(fps=N)`, plus `start_offset`/`end_offset` clipping (e.g. `'40s'` -> `'80s'`). Quality "significantly higher from 2.5 series models" | 258 tok/frame default; **66 tok/frame** at `media_resolution` low. ~300 tok/s default, ~100 tok/s low at 1 FPS. Audio 32 tok/s @ 1 kbps | 1M context => 1 h video at default res, 3 h at low. Up to **10 videos/request** on 2.5+ (1 before). Free-tier YouTube cap 8 h/day |
| **Claude (Opus 5 / 4.7+)** | **No.** Images only; "Animations are unsupported, and only the first frame is used" — so an animated GIF is a still | n/a — you control sampling because you build the frame set | `ceil(w/28) x ceil(h/28)` visual tokens. High-res tier (4.7+): long edge <=2576 px, <=4784 visual tokens. Standard tier: 1568 px / 1568 tokens | **100 images/request** on 200k-context models, **600** otherwise; **>20 image blocks => every image must be <=2000 px per side**; 10 MB/image; 32 MB request |
| **GPT-5.x** | No native video-file input on the vision path; the documented pattern is an **array of frames** (and therefore no audio). Responses API adds audio-in / video-out modalities, not video-in for review | You control sampling | per-image tiling | — |
| **Open-weight, local (M1 Max 64 GB)** | **Qwen3-VL** is the live option — the 8B variant reaches Qwen2.5-VL-72B-class video performance with explicit temporal-grounding and long-video evaluation (arXiv 2511.21631). Runs on MLX (Metal, unified memory, M1+) or `vllm-mlx`; 30B-A3B fits comfortably in 64 GB | Full — you feed frames | free | Slower than M4 Max (~55-70 tok/s on 35B-A3B there); adequate for offline batch review, not an inline agent loop |

Vendor sources: <https://ai.google.dev/gemini-api/docs/video-understanding> ·
<https://ai.google.dev/gemini-api/docs/generate-content/video-understanding> ·
<https://ai.google.dev/gemini-api/docs/gemini-3> ·
<https://platform.claude.com/docs/en/docs/build-with-claude/vision> ·
<https://github.com/anthropics/claude-code/issues/32130> · <https://arxiv.org/pdf/2511.21631>

WARNING — doc inconsistency: the *current* `docs/video-understanding` page documents 1 FPS sampling
but **does not mention `videoMetadata` / `fps` at all**; the `generate-content/video-understanding`
page does. Probe that `fps` is honoured on your target model rather than trusting either page.

### 5.2 Contact sheet vs. separate frames vs. video — the actual arithmetic

**Evidence that grids work.** IG-VLM ("An Image Grid Can Be Worth a Video", arXiv:2403.18406, later
IEEE Access) samples **6 frames uniformly and tiles them 3x2**, feeding the single composite to an
off-the-shelf VLM with grid guidance + reasoning guidance in the prompt. It **beats specialised
video models on 9 of 10 zero-shot video-QA benchmarks** with no video-specific training. Grid
reading order is a strong, reliable temporal prior for a still-image model.
<https://arxiv.org/abs/2403.18406>

**Evidence that grids are not free.** Frame-selection-sensitivity work (TempCore, arXiv:2509.01167)
finds many video-QA benchmarks are solvable from a *single* frame, with single-frame and text-only
baselines staying competitive — i.e. grid wins on those benchmarks partly measure something other
than temporal reasoning. Do not generalise "grids beat video" into "grids resolve 16 ms
differences." <https://arxiv.org/html/2509.01167v2>

**The token math, for Claude, on a 1440x900 viewport** (patch cost `ceil(w/28) x ceil(h/28)`;
high-res tier caps 2576 px long edge / 4784 visual tokens):

| Input shape | Visual tokens | Per-frame fidelity |
|---|---|---|
| 1 frame, native 1440x900 | `52 x 33` = **1,716** | 100 % |
| 9 frames, sent separately | **15,444** | 100 % each |
| 3x3 contact sheet (4320x2700, downscaled to ~2410x1506 to fit BOTH caps) | **~4,700** | cell ~803x502 => **56 % linear, 31 % of the pixels** |

| Input shape (Gemini, 1 s of interaction) | Tokens |
|---|---|
| default 1 FPS, default res | 258 — **and only 1 frame; useless for a 200 ms transition** |
| `fps=30`, default res | 30 x 258 = **7,740** |
| `fps=30`, `media_resolution` low | 30 x 66 = **1,980** |

**Verdict.** For a *single interaction* (<=1 s, <=20 frames), **separate full-resolution frames on
Claude beat a contact sheet**: you stay under the 20-image threshold that would otherwise force
every image to <=2000 px, each frame keeps native fidelity, and D16-class artifacts (a 1 px seam, a
blurred glyph, a 4 px focus ring) survive. The contact sheet's 3.3x token saving costs 69 % of the
pixels — precisely the pixels those defects live in. Use a contact sheet when (a) you need >20
frames, (b) you want the model to reason about *ordering* rather than *detail*, or (c) budget binds.
**Best of both: contact sheet for triage -> full-resolution frames for the 3-frame window it flags.**
For dense temporal sampling (>30 frames), Gemini at `fps=30, media_resolution=low` is ~8x cheaper
per frame than Claude at native resolution and is the right tool.

WARNING: do **not** review motion from a Playwright `recordVideo` `.webm`. It is VP8, variable frame
rate, "visibly compressed ... with mosquito noise around glyph edges," and carries no guarantee of a
frame at any particular instant. It is a debugging receipt, not an instrument.
<https://playwright.dev/docs/videos>

---

## 6. The one defect class the deterministic argument cannot cover

**The strongest case for deterministic-only motion review is genuinely strong.** Every property a
design review of motion *asserts* — duration, delay, easing, animated property, iteration count,
fill mode, stagger offsets, compositability, reduced-motion compliance, layout-shift contribution,
interaction latency — is a number in the animation model. Reading it costs nothing, is exact, is
stable across CI runs, and produces a diff rather than a probability. A vision judge over a 6-frame
strip introduces sampling error (did a frame land inside the transition?), instrument error (VP8
compression, 1 FPS defaults), and model nondeterminism, then hands back false positives a human must
triage — to answer a question a perfect instrument had already answered for free. On timing, **vision
is strictly the worse instrument and should never be used.**

**The class it cannot cover: mid-interpolation rendering artifacts — a frame whose timing model is
entirely correct and whose composited pixels are wrong.**

Every instrument in §2 reads the animation *model* or the main-thread *timeline*. None of them
rasterizes. All of the following return a clean green from WAAPI, CDP, LoAF, Event Timing and the
compositor audit, while looking broken on screen:

- an element flickering to the wrong stacking order for two frames because an animated `transform`
  creates a new stacking context part-way through;
- text going blurry mid-transition because a scaled transform rasterizes on non-integer boundaries;
- a `backdrop-filter` panel showing a hard seam only while its parent is animating;
- a `clip-path` briefly revealing a background it should never expose;
- a shadow or gradient banding at intermediate opacity values;
- an image popping from placeholder to final inside what the model reports as one continuous 300 ms fade.

Ask WAAPI and you get `duration: 300, easing: 'ease-out', progress: 0.5` — a perfect green. Ask CLS
and you get **0**, because the Layout Instability spec excludes transform-driven movement from the
score by design. Ask LoAF and you get nothing, because the animation is composited and the main
thread was idle. The defect exists only in pixels no timing API ever touches.

That is why the vision tier is not optional — and also why its job is **exactly one question**, asked
of frames, never of timings: *"across these frames, does any intermediate frame contain a rendering
artifact absent from both endpoints?"*

(A weaker second candidate — *choreographic quality*, whether motion reads as originating from its
trigger — is partly deterministic, since stagger delays and transform-origins are numbers, and the
residue is aesthetic preference rather than a defect. D16 is the one that is unambiguously a defect
and unambiguously invisible to instrumentation.)

---

## 7. Recommended recipe — reviewing ONE interaction end-to-end

Target: "click the button, panel opens." Budget ~1 s of motion.

```
0.  SETUP
    page.emulateMedia({ reducedMotion: 'no-preference' })
    cdp = await context.newCDPSession(page); await cdp.send('Animation.enable')
    inject the observer bundle BEFORE the interaction:
      layout-shift (buffered:true) · event (durationThreshold:16) · long-animation-frame
    detect rAF libraries: window.gsap / window.Motion / __FRAMER_MOTION*  -> record coverage gap

1.  DETERMINISTIC PASS   (run first; most defects die here)
    a. arm Animation.animationStarted -> collects every WAAPI animation with its full
       AnimationEffect (delay, duration, easing, iterations, fill, keyframesRule)
    b. perform the REAL interaction (locator.click()), never a forced state
    c. assert: duration in token set · easing in token set · animated props subset of
       {transform,opacity,filter} · no unexpected iterations/fill
    d. drain the three observers: CLS sum over !hadRecentInput == 0 · INP components < 200 ms ·
       no LoAF with blockingDuration > 0
    e. repeat (b)-(d) under Emulation.setCPUThrottlingRate(4)
    f. reduced-motion arm: emulateMedia({reducedMotion:'reduce'}) -> re-run -> assert
       getAnimations() yields no animation with duration > 0

2.  FRAME CAPTURE   (only if step 1 is clean, or to explain a step-1 failure)
    Playwright >=1.59:
      const sc = await page.screencast.start({ onFrame: f => frames.push(f), quality: 90 })
      // f = { data: JPEG bytes, timestamp: ms since epoch, viewportWidth, viewportHeight }
      await interact(); await sc.stop()
    Timestamps are real and per-frame -> select frames by elapsed ms, never by index.
    Fallback (any Playwright): CDP Page.startScreencast({format:'jpeg', quality:90,
      everyNthFrame:1}) + Page.screencastFrame -> metadata.timestamp, then screencastFrameAck.
    Deterministic alternative when you need exact phases rather than a stream:
      Animation.setPlaybackRate(0), then Animation.seekAnimations({animations, currentTime:t})
      for t in {0, 25%, 50%, 75%, 100%} of the computed activeDuration; screenshot each.
      For rAF libraries use page.clock.install() + runFor(16) instead (§4.1).

3.  VISION JUDGE   (one question only)
    Send 5-9 frames as SEPARATE full-resolution images (stay <=20 image blocks so Claude does not
    impose the 2000 px cap), each preceded by a text label carrying its elapsed ms:
        "Frame 1 - t=0 ms:" <image>  "Frame 2 - t=83 ms:" <image>  ...
    Prompt intent, verbatim: "Frames 1 and N are the endpoints and are known-good. In frames
    2..N-1 only, identify any rendering artifact absent from both endpoints: z-order flicker,
    text blur, seams, clipping, banding, or content popping. Report NONE if there is none.
    Do not comment on timing, duration or easing - those are measured elsewhere."
    Budget: 9 x 1,716 = ~15.4k visual tokens, ~$0.08 at Opus 5 input pricing.
    If >20 frames are needed: tile a 3x3 contact sheet for triage, then re-send the flagged
    3-frame window at full resolution.

4.  REPORT
    Deterministic findings as assertions carrying the measured number and the expected token.
    Vision findings ONLY as "artifact at t~X ms, frames k..k+1" - never as a timing claim.
    ALWAYS state the rAF coverage gap from step 0: a clean deterministic pass on a GSAP page
    is not evidence of correctness.
```

**Why the vision judge is fenced to one question.** Given timings in the prompt, a vision model will
re-litigate them and emit confident, wrong duration estimates derived from an unknown sampling rate.
Restricting it to the artifact question is what makes its output additive rather than noise
competing with an exact measurement.

---

## 8. Blockers / uncertainties

- **`fps` on Gemini 3 is doc-inconsistent** (§5.1). Probe it on the target model before relying on
  it; a silently-ignored `fps` degrades to 1 FPS and still yields a confident answer about nothing.
- **`CSS.forcePseudoState` reliability** — chromium issue 343757697 reports it "does not always"
  apply. Any state-forcing failure must be a loud skip, never a silent pass.
- **`page.screencast` frame rate is not documented.** Frames arrive as the compositor produces them,
  so the interval is not guaranteed. The per-frame `timestamp` is what makes it usable — select by
  elapsed time, never assume a fixed cadence.
- **No web-exposed dropped-frame API.** `PercentDroppedFrames` needs a Chrome trace
  (`PipelineReporter` events) via CDP `Tracing`; there is no `PerformanceObserver` equivalent, and
  rAF-based FPS counters are explicitly an anti-pattern.
- **Not verified in this pass:** whether `page.clock` composes safely with `page.screencast`
  (virtual time vs. wall-clock frame timestamps could desynchronise); and whether Playwright's
  WebKit and Firefox backends expose enough of the WAAPI seek path for §7 step-2's deterministic
  alternative. Both are cheap empirical probes, not research questions.

---

## Sources

WAAPI: <https://developer.mozilla.org/en-US/docs/Web/API/Document/getAnimations> ·
<https://developer.mozilla.org/en-US/docs/Web/API/AnimationEffect/getComputedTiming>

Performance APIs: <https://developer.mozilla.org/en-US/docs/Web/API/LayoutShift> ·
<https://developer.mozilla.org/en-US/docs/Web/API/PerformanceEventTiming> ·
<https://developer.mozilla.org/en-US/docs/Web/API/PerformanceLongAnimationFrameTiming> ·
<https://web.dev/articles/smoothness>

CDP: <https://chromedevtools.github.io/devtools-protocol/tot/Animation/> ·
<https://chromedevtools.github.io/devtools-protocol/tot/CSS/> ·
<https://chromedevtools.github.io/devtools-protocol/tot/Page/> ·
<https://chromedevtools.github.io/devtools-protocol/tot/Emulation/>

DevTools / Lighthouse: <https://developer.chrome.com/docs/devtools/css/reference> ·
<https://developer.chrome.com/docs/devtools/css/animations> ·
<https://developer.chrome.com/docs/lighthouse/performance/non-composited-animations> ·
<https://github.com/GoogleChrome/lighthouse/blob/main/core/audits/non-composited-animations.js>

Playwright: <https://playwright.dev/docs/api/class-screencast> ·
<https://playwright.dev/docs/api/class-pageassertions> · <https://playwright.dev/docs/api/class-page> ·
<https://playwright.dev/docs/clock> · <https://playwright.dev/docs/videos> ·
<https://playwright.dev/docs/release-notes> · <https://github.com/microsoft/playwright/issues/3347>

Storybook: <https://storybook.js.org/docs/writing-tests/interaction-testing/> ·
<https://storybook.js.org/addons/storybook-addon-pseudo-states>

Models: <https://ai.google.dev/gemini-api/docs/video-understanding> ·
<https://ai.google.dev/gemini-api/docs/generate-content/video-understanding> ·
<https://ai.google.dev/gemini-api/docs/gemini-3> ·
<https://platform.claude.com/docs/en/docs/build-with-claude/vision> ·
<https://github.com/anthropics/claude-code/issues/32130>

Research: <https://arxiv.org/abs/2403.18406> (IG-VLM) · <https://arxiv.org/html/2509.01167v2>
(TempCore) · <https://arxiv.org/pdf/2511.21631> (Qwen3-VL)

View transitions: <https://developer.mozilla.org/en-US/docs/Web/API/View_Transition_API/Using> ·
<https://www.bram.us/2025/01/01/view-transitions-snippets-getting-all-animations-linked-to-a-view-transition/>
