---
status: in-progress
owner: pool-2 (feat/banner-showoff) implements; lead specifies
---

# Banner narrative spec — cause / behaviour / exit for every event

Operator ruling, 2026-07-29 (binding, supersedes the timing half of S9). Two critiques:

- **(a) Volume dilutes significance.** So much content — the starfield above all — that no single
  element carries weight. Awwwards-grade means restraint: every element earns its place or goes.
- **(b) Every rare occasion needs a CAUSE, a BEHAVIOUR, and an EXIT.** Named non-sequiturs in the
  current v5a: the orange asterisk that passes clawd; the "horns" that appear and vanish; clawd
  becoming sleepy with no reason, doing nothing distinct while `Zzz`, and waking for no reason; a
  shooting star that lands and does nothing; a second smaller mascot that appears and leaves
  unexplained.

## Why it reads as random — measured, not guessed

Duty cycles over the P=240 s master period, read off the keyframe percentages in
`assets/banner/v5a-long-walk.svg`:

| event (class) | window | duty | verdict |
|---|---|---|---|
| `balloon` (`bo`, 120 s) | 4.8–60.0 s, **twice per loop** | **46.0%** | not rare — nearly ambient |
| `rCheer` (`rc`, 120 s) — the "horns" | 34.8–42.0 s | 6.0% | fires **inside** the balloon pass |
| `peek` (`pk`, 240 s) | 98.4–122.4 s | 10.0% | 24 s is long for a "peek" |
| `rSleep` (`rs`, 240 s) | 148.8–175.2 s | 11.0% | overlaps the balloon's 2nd pass |
| `shoot` (`sh`, 240 s) | 231.4–238.8 s | 3.1% | the only genuinely rare one |

Three structural faults:

1. **The rare events are not rare.** S1 sells a 1.7% duty cycle. The balloon is on screen 46% of
   the time, so it is scenery that happens to move — it cannot read as an event.
2. **Events stack instead of sequencing.** `rCheer` lands mid-balloon; `rSleep` lands inside the
   balloon's second pass. Two unrelated things at once, so neither reads as caused by anything.
3. **Nothing causes anything.** Five independent timers on one shared period. Simultaneity is the
   only relationship the composition can express, and it expresses it by accident.

## The fix: one causal chain, sequenced across the loop

The conceit that makes every element explicable: **clawd is a session; the sky is the work that
arrives.** Events do not fire on timers — each is *triggered by the previous one*, so the 240 s
loop is a story that closes rather than a reset.

The shooting star is the **prime mover** — the only uncaused arrival, and the thing that both opens
and closes the cycle.

| # | beat | CAUSE | BEHAVIOUR (what it does while present) | EXIT |
|---|---|---|---|---|
| 1 | **Shooting star** | uncaused — the one external arrival | streaks down across the sky, behind the clouds, never crossing the type | **lands**: does not vanish. It becomes a small ember on the ground at the impact point, which persists |
| 2 | **Ember** | the landing | sits on the ground, faint slow pulse — the only warm light in the frame | consumed by beat 5 |
| 3 | **Visitor peeks** | *something landed* — curiosity | emerges from behind the mound **nearest the ember**, edges toward it, looks at it, looks at clawd | retreats behind **the same mound it came from** — a symmetric exit reads as intent, not a despawn |
| 4 | **clawd cheers** | it saw the visitor | whole-body gesture — a hop with a body tilt, **not two pixels above the head** | settles back to stride |
| 5 | **clawd sleeps** | the sky has gone quiet: star landed, visitor gone, nothing overhead | sits, `Zzz` drifts up; a 1 px body rise/fall for breathing; **the ground keeps scrolling** — the world moves while the session rests | woken by beat 1 of the next cycle: the next streak. Stands, stride resumes |

That last row is what closes the loop causally: the event that starts the story is the event that
ends the sleep, so t=P is both the seam and the narrative return.

**Sequence unrelated beats; STACK beats that cause each other.** ⚠️ This started life as the
unqualified "sequence them, do not stack them", and that form is *wrong* — it forbids the very thing
this redesign exists for. The resident's cheer is caused by the visitor arriving, so a strict
pairwise-disjointness rule rejects causality itself. Causally-linked beats **must** overlap, declared
as one beat in two elements (`COMPOSITE_OF`) — the same precedent as Zzz-during-sleep. The corrected
rule: **stack when one beat causes the other; sequence when they are unrelated, with clear empty air
between.**

A subtlety the gate surfaced and that a hand-written rule would have missed: naming a single parent
for the cheer is not enough. Declaring only `peer` as its cause made the gate correctly reject v6a,
where the cheer is caused by the `peek` it overlaps. **The parent is whichever visitor beat that
variant carries**, so the relationship is per-variant, not global.

**Phase lives in the element, and the freeze is additive.** ⚠️ This section previously read "phase
must live in keyframe percentages, never authored `animation-delay`", on the grounds that the freeze
overrode delay on `*` and discarded it. That was true of the old freeze and is now **superseded** —
it solved the clobbering by removing the feature. The freeze is now additive: an element keeps its
phase in `--d`, the harness supplies only the seek in `--fz`, and the delay is their `calc()` sum, so
custom-property inheritance carries it into SVG children and assets with no `--d` are byte-unaffected.
Verified against a three-rect control that renders one step apart under the new freeze and identically
under the old one. Consequence: the seam test now genuinely exercises phase (staggered vs
stripped-stagger produce different renders), where before it could not fail on that question.

## Specific rulings

- **Cut the balloon.** It is the single largest volume offender at 46% duty and it explains nothing.
  If it must survive, re-cause it: the visitor *releases* it as it leaves, so it has an origin and a
  direction. Cutting is preferred — restraint over addition.
- **Fix the cheer's legibility.** Arms-up currently reads as horns/antennae because the arms clear
  the head silhouette as two loose pixels. `clawd-sprite.py` measured the cliff (rise −3; −4 reads
  as antennae). Either scale clawd up so arms read as arms, or make the cheer a whole-body gesture.
  A gesture nobody can name is not an emote.
- **Sleep needs a distinct state, not a badge.** Today `Zzz` is the only difference. Asleep must
  differ in posture (sitting/lower silhouette), in breathing, and in *absence* of the walk stride.
- **Thin the starfield hard.** Cut the count substantially. Make the three depth tiers genuinely
  different in size and opacity so depth reads as depth. Prefer 1 px dots for the far tier and
  reserve the asterisk glyph for only the few nearest stars: an asterisk is six strokes of ink, so
  forty of them is forty competing marks, and it also stops the sky from being a field of Claude
  marks competing with the wordmark.
- **Thin the sky furniture.** Three cloud bands + ground mounds + ground rule + moon is a lot of
  simultaneous texture. Every band that is not carrying the parallax should go.
- **Unchanged and still binding:** clawd present and alive; side-scrolling ground like dino-run;
  wordmark legible at every t with nothing behind it; 100% seamless loop; stars never touch the
  type; moon subtle, behind the clouds, no solid-white cell; vector only; reduced-motion freezes
  legibly. Do **not** run `scripts/banner-apply-header.sh` — the README edit is the operator's call.

## Per-event reconsideration (operator directive, second pass)

Reconsider **each micro-event individually** so it has a story of how it enters, exists and leaves,
rather than being zero-context random. One at a time.

### The balloon — the orange asterisk on a stem

The deeper fault is not the timing: it is **the Claude asterisk floating with no owner**, which
reads as a stray mark rather than an object.

Give it an owner rather than deleting it: **it is the visitor's balloon.** The visitor enters
holding it — the string is what makes the asterisk legible as *held* instead of *floating*. On
leaving it **lets go**, and the release *is* the exit: the asterisk rises out of frame under its own
logic. One story now explains two events that were both orphans, and nothing has to fade out
unexplained. If that cannot be built cleanly, **cut it** — a fade-in with no origin is not an event.

### The horns — the arms-up cheer

Two independent faults. It is **illegible**: the arms clear the head silhouette as two loose pixels,
so it reads as horns or antennae (`clawd-sprite.py` measured the cliff at rise −3, with −4 reading
as antennae). And it is **uncaused**: it fires mid-balloon-pass, so even read correctly it would
mean nothing.

- **Enters** because clawd sees the visitor arrive — aimed at something actually in frame.
- **Exists** as a *whole-body* gesture: a hop with a body tilt and arms held wide. The silhouette
  must change shape, not sprout.
- **Leaves** by settling back into the stride.

If it cannot be made legible at this scale, **cut it**. A gesture that reads as horns is worse than
no gesture: the viewer is left with a question instead of a beat.

### The mini pet — the visitor

It peeks from behind a mound and then lingers 24 s with nothing to do. That mismatch is most of why
it feels arbitrary: the motion says *glance*, the duration says *visit*. Pick one. The stronger
choice is a **visit with an errand**:

- **Enters** because something arrived — walks in from behind the mound nearest it, never popping
  into existence.
- **Exists** doing exactly one legible thing: hands over the balloon, or studies the ember, or falls
  into step with clawd for a few strides — the last states *sessions run each other* as behaviour
  instead of as a diagram.
- **Leaves** back behind **the same mound**. A symmetric exit reads as intent; a fade reads as a
  despawn.

## Should clawd move between right, middle and left?

**Not as a free traverse — as motivated excursions from one fixed anchor.**

The scene is a dino-run side-scroller, and that idiom works *because* the character's x is fixed
while the world moves; that is what sells walking. A clawd that also translates across x introduces
a second horizontal motion competing with the ground scroll, and the eye reads it as sliding rather
than walking. A full left-to-right traverse also drags clawd through the wordmark keep-out, against
a binding requirement.

So: **choose one resting anchor** and let clawd leave it only for a reason — stepping toward the
ember, following the visitor a few paces — and always **return to it** before the loop closes, or
the composition does not return to its start even though the timing does. Excursion speed must read
as clearly slower than the ground scroll, otherwise the two motions fight.

Worth knowing when picking a candidate: the four v6 files already differ in anchor (v6a/v6b hold
clawd left, v6c right of centre, v6d centre), and a composition balanced for one anchor will not be
balanced at another — so this is a per-candidate decision, not a global one.

## Making the sky read as craft rather than as basic vector art

Measured on the committed `v6c`: **zero filters** — no `feGaussianBlur`, no `feTurbulence`, no
`filter=` anywhere; 8 radial and 8 linear gradients, 4 masks. Stars are already shapes rather than
text glyphs, and the moon is a properly masked crescent, so the geometry is not the problem. **The
flatness is the absence of any optical treatment**, and that is the highest-leverage fix available.

Ordered by effect per unit of effort:

1. **Bloom, not a single radial gradient.** One radial gradient behind the moon is the tell of
   vector art. Real glow is two or three stacked passes — a tight bright halo plus a much wider,
   very faint bloom — with a slight outward colour shift (warm core, cooler edge). Add a small
   `feGaussianBlur` on the halo so its falloff is optical rather than a gradient stop.
2. **A single grain layer over the sky.** One tiled `feTurbulence` at very low opacity destroys the
   plastic flatness of a large gradient more than any other single change. Inline, so it stays
   self-contained and legal in SVG-as-image mode — but it must be render-verified and perf-checked,
   because filters over a full-width rect are the one genuinely expensive thing here.
3. **Never pure white.** `#ffffff` reads as a hole punched in the page; moonlight is a warm
   off-white (≈`#f4ead8`). The light-mode block currently sets `.ct0{fill:#ffffff}` on cloud tops —
   worth revisiting for the same reason.
4. **Colour-temperature variance in the stars.** All-white stars look cheap. Give them 3–5%
   saturation spread — a few cool (`#cfe0ff`), a few warm (`#fff0dd`). This is the single biggest
   cheap-to-refined lever in the starfield and it costs nothing.
5. **A terminator and maria on the moon.** A flat crescent is a shape; a subtle gradient across the
   lit limb plus two or three very low-contrast darker patches make it an object.
6. **Atmospheric perspective.** A single linear sky gradient is not how a sky looks. Lighten
   subtly toward the horizon and add a faint vignette; even 2–3% separates "painted" from
   "gradient".
7. **Occlude the glow.** The moon sits behind the clouds by requirement, so its *glow* must be
   occluded by them too — otherwise the halo reads as pasted on top of the scene.

## Stars: scatter, and the constellation idea

**Scatter.** Uniform random placement reads as wallpaper, and clumping reads as spam. Use
**Poisson-disc / blue-noise placement with a minimum separation**, so stars never pile up in one
spot but never form a grid either. Vary density deliberately: sparser near the horizon (atmosphere
washes low stars out), denser high, with genuine voids — empty sky is what makes the occupied sky
read as composed. Keep the keep-out box around the type.

**Dynamism.** Most stars should *not* twinkle; a minority should, on uncorrelated periods, easing
rather than linear, and varying **opacity and scale together**. Reserve a 4-point diffraction cross
for only the two or three brightest — that one detail is what makes a field read as photographic
instead of sprinkled.

**Constellation line-mapping as a rare event: yes — and it is the best event idea on the table.**
It is thematically exact: separate points revealed to be one figure is *sessions run each other*
stated in the sky. Enter by drawing on (stroke-dashoffset, star to star, in order, quickly but not
instantly), exist as a brief hold, leave by fading the lines while the stars remain. Three hard
constraints:

- **It must not read as a network diagram.** R1 rejected the handoff infographic, and lines joining
  things is exactly that grammar. The rule that keeps it safe: constellation lines join **stars to
  stars in the sky**, and never join clawd to the visitor. If a line ever touches a creature, R1 is
  back.
- **It must respect the type keep-out** — lines, not just stars.
- **It is night-only.** There are no stars in the light scheme, so this cannot be the only rare
  event; the day scene still needs its own arrival (see below).

## Both schemes must carry the story (measured 2026-07-29)

Rendering the committed v6 set under a real `prefers-color-scheme: light` shows light mode is a true
daytime scene — moon becomes a warm sun, stars hidden, white clouds on blue, warm tan ground. Two
consequences:

1. **The shooting star cannot be the prime mover for daytime readers.** The light block sets
   `.sh{opacity:.20}` and hides the starfield, so the one uncaused arrival the whole chain hangs
   from is nearly invisible in light mode. Either give day its own legible arrival (a drifting seed,
   a paper plane, a bird) or **re-root the chain on the ground**, which survives both schemes.
2. **The art directions converge in daylight.** v6a, v6b and v6d become nearly the same picture
   because what distinguishes them is night-only. Only v6c keeps an identity (sun left, warm horizon
   band). Choose a candidate on **both** looks, never on the dark one alone.

## SYNTHESIS — five-agent research panel, 2026-07-29

Reports on disk (144 KB): `repo-semantics`, `event-grammar`, `prior-art`, `event-generator`,
`event-adversary`. **This section supersedes the causal chain proposed above.** The chain was
internally consistent and about nothing; what follows is grounded in named mechanisms and survives
the adversarial pass.

### The finding that reorders everything: the viewer's clock starts at t=0

An SVG in `<img>` starts its CSS timeline when the image begins rendering, the hero is the first
element on the page, and Chrome does not throttle SVG-in-`<img>` animation. So there is **no random
phase**: every reader starts at t≈0. **The first ~30 seconds of the loop is the product.** An event
at t=231 s is seen by essentially nobody — not because it is rare, but because it is *late*.

This reframes the adversary's strongest attack rather than refuting it. Its "no viewer ever witnesses
cause and effect" holds under random phase; under t=0 anchoring the defect is **placement**, and the
fix is front-loading, not abandoning events. Two agents converged here independently, and one adds
the sharpest single move available: **fire the distinctive beat ONCE, ~2–4 s after load, and never
repeat it** (`begin="2.5s" repeatCount="1"`). A repeating distinctive event is a *beacon of
repetition* — the 40-second reader watches it fire twice and the illusion dies. One-shot gives every
reader exactly one beat while they are still looking, and nobody ever sees it recur.

✅ **CONFIRMED by measurement, 2026-07-29 — front-loading is justified.** Probe committed as
`scripts/banner-timeline-anchor.sh` (landed `83638b1f`) so it can be re-run rather than believed. A
raw render taken immediately best-matches frozen t=0 at RMSE 0.000%; a raw render taken 25 s later
*still* best-matches t=0 at 0.189%; and the control — frozen t=0 vs frozen t=25 — differs, so 25 s of
motion is detectable and the null is not vacuous. Re-run independently at a 20 s gap: t=0 and t=0,
against a 3.50% control.

**The failure mode that nearly produced a false refutation, recorded because it will bite anyone
repeating this.** The naive probe renders the unfrozen file twice, 25 s apart, observes that the two
differ, and concludes the timeline is *not* load-anchored. That test cannot decide anything: a
load-anchored timeline also differs between two such renders, because the screenshot fires at a
variable delay after load and the 0.5 s stepped stride flips the legs on ~250 ms of jitter.
**"Differs" cannot separate jitter from drift.** The decisive form asks *which phase* each render
sits at, by matching it against frozen references — a question the naive form never asks. The first
run of the naive probe returned REFUTED.

Side result worth keeping: the immediate raw render matching frozen t=0 at **RMSE 0.000%**
independently validates the freeze harness itself — pixel-exact against a live render of the
unmodified file, which no prior check had established.

### The reframe that dissolves R1 at no cost

**A session is never co-present with its peers.** Peers live in other panes, other worktrees, other
accounts. Co-presence is not merely risky under R1 — it is *the wrong picture of the system*. So
peers are always **off-canvas, and their existence arrives as world state**: mail is a file, a
predecessor is a record. R1 becomes free rather than endured, and every event can have exactly one
creature in frame because the repo has exactly one session per pane.

Corollary: **v6b's "a second session walks in and both cheer" is not just R1-exposed, it is
semantically wrong** — and as shipped its peer interpenetrates clawd for ~7.2 s in the same flat
orange, reading as a render error or as one session absorbing another.

### The spine: the scroll rate is the only gauge

| Reading | Means | Event |
|---|---|---|
| nominal | working | ambient |
| **negative** | a turn was returned | THE REFUSAL |
| **zero** | blocked on a human | THE ASK |

Events share one vocabulary instead of each inventing its own. **Significance comes from a shared
scale, not from novelty per beat** — the direct answer to critique (a). Second structural rule:
nothing is ever authored above y=340, so the sky stays purely ambient and the wordmark cannot be
crossed *by construction* rather than by a keep-out check.

### The thesis belongs in a STATE, not an event

Bake a footprint into the scrolling strip at **exactly one stride pitch**, for the whole strip. The
foot then lands in an existing print every stride *by construction* — no second animation. The
reading: **the record is continuous and the walker is not.** You cannot tell where one session's
prints end and the next's begin. That is "SESSIONS RUN EACH OTHER" rendered as the ground itself,
with no second creature and nothing joining anything, and it makes "nothing a session did dies with
it" a permanent property rather than a 4-second event. Independently, the prior-art census ranks
persistent footprints a top-tier *fresh* beat that also hides the loop seam.

### The recommended set — three events, MECE, shippable alone

- **THE OVERLAP** — `handoff-fire.sh self-close --successor` refuses to retire a predecessor until
  the successor is *verified engaged*, so succession **overlaps rather than touches**. The print
  pitch halves for ~12 prints: two walkers' worth of record. The foot lands on every *second* print
  and the mismatch is the tell. Exit by resolution — pitch halves back, foot re-registers.
- **THE REFUSAL** — `completion-assert.sh` refuses a false "done"; the README's own diagram draws it
  as an arrow *back*. A post arrives, the creature settles (it is trying to end the turn), the bar
  drops across, and **the world scrolls back exactly one print pitch**. So the creature steps into
  the same print twice: *a returned turn is redoing a step.* The best detail in the set, and free.
- **THE ASK** — the system pages you only when a human must decide (`cc-decide` class C waits with no
  default; `cc-blockers`; STOP-ASK). Nothing arrives: it stops, ears up, gaze parks straight out,
  world rate zero for 6 s, then resumes. **In a loop made of motion, the only cessation is the most
  salient thing in it** — and it needs no new art, since the sprite already faces front. Prior-art
  independently ranks "creature stops, looks off-frame, resumes" top-tier fresh.

Two further candidates (**THE LANE**, a fork in the ground for worktree isolation; **THE ADVANCE**, a
deploy sweep whose payload is that nothing changes) are specified in the generator report but are the
recommended cut order — THE ADVANCE first (weakest exit, 1 px payload), THE LANE second (most
infographic-prone, widest footprint).

### Deleted, with reasons

| Beat | Why it goes |
|---|---|
| Shooting star | The most tired beat available — ships as a free asset marketed for "pop up randomly in night backgrounds" — **and structurally invisible by day**, so it cannot carry a story in both schemes |
| Drifting balloon | Filler: no cause for entering, no exit but drifting off, and it renders the brand asterisk as a stray object (against R4) |
| Floating Zzz | UI iconography, not observation — and it **contradicts the thesis**: idleness here is a `cc-reaper` classification and a closed pane, not sleep |
| Waving creature | Breaks the fourth wall, and collides with the 👋 that opens roughly every profile README |
| The 4 s hop | Voluntary motion implies a cause it does not have. **Involuntary → texture; voluntary → must map to a mechanism, or cut.** 60 unmotivated hops per loop is precisely the noise critique (a) named |

### Enforcement — a lint, not a doctrine

Per this repo's own chokepoint rule, every ruling above is worthless as prose. Extend the build lint
to expand every keyframe list to **absolute seconds on the 240 s master** and assert: pairwise event
disjointness with margin; at most one feature on canvas (`min pairwise strip gap ≥ 1920 +
feature_width`); per-type duty ≤4%; aggregate ≤25%; ≥65% empty air; no type recurring with a gap
<60 s; and every rate modulation spanning an exact multiple of the 0.5 s stride. Measured v5a fails
this at **88.1% aggregate duty, 64.8% union coverage, four concurrent events for 3.6 s**.

Also assert `strip_length = 28.8 × (strides_taken − strides_in_place)`, divisible by the dash pitch —
a hard stop cannot be paid back by a later catch-up without destroying the print lock.

### Two defects nobody had recorded

1. **The sprite is bilaterally symmetric, so the turn-around is a visual no-op.** Ears at 0/200, eyes
   at 40/160, body 20+180 all mirror about x=110, and `legA` maps onto `legB` under `scaleX(-1)`. Found
   independently by two agents. "Turn around" is unavailable as a beat without new art.
2. **Stride and scroll are not locked** — RESOLVED, and the original diagnosis here was too narrow.
   This section first read "32.7 px/s ÷ 2 strides/s = 16.3 px per stride = 1.13 cells while the legs
   are two cells apart", which implies one wrong rate to correct. Measured against the emitted files
   there were **four different ground-ish rates** — near tufts 1.51 cells/stride, foreground 2.26,
   mounds 0.75, far mounds 0.38. **"The ground" was never one layer**, so there was no single ground
   speed to lock to; that, not a bad constant, was the defect.

   **The condition, derived rather than tuned:** `(TILE / STRIP_PERIOD) × STRIDE == k × CELL × scale`,
   with both periods dividing P. Seven solutions exist in the usable scale band; the chosen one is
   `STRIP_PERIOD = 20 s, scale = 1.2, k = 2`, and a designated strip layer carries that rate.
   Independently verified off the emitted file: the strip translates −1920 px over 20 s = 96 px/s =
   **48.000 px per 0.5 s stride = exactly 2.0000 cells**, i.e. the ground advances one full
   leg-spacing per stride. Enforced by `assert_stride_locked`, which fails the build naming the
   offending cell count and the scales that would work — sabotage-proved by restoring 1.06, which
   reports "2.264 sprite cells at scale 1.06".

   🔒 **CONSEQUENCE: clawd's scale is no longer a free art-direction variable.** It is pinned by the
   lock, all four variants sit at 1.2, and the print pitch is now a design constant rather than a
   knob. Any future "make clawd bigger/smaller" must move `STRIP_PERIOD` or `STRIDE` with it, or
   re-solve the condition — a bare scale change silently breaks the footprint lock that the whole
   thesis rests on. Note the lock happens to scale clawd **up** from 1.06, which is independently
   what the gesture-legibility finding wanted, so the two constraints agree rather than compete.

### Open for the operator, not for us

**R3 of the binding ruleset says "seamless indefinite loop, ambient not narrative."** Everything
above is ambient-with-mechanism rather than plot, which is compatible — but the earlier chain was
not, and nobody adjudicated the conflict. If R3 stands as written, narrative-as-experienced is out
and the state/gauge reading is the only legal design. That is a ruling, not a craft call.

## THE PICK: v6c-dusk-line (operator, 2026-07-29)

All remaining work concentrates on that one file. **The operator's condition on the pick: every
surviving micro-event must make narrative and repo-relevance sense** — and, separately, *"heavily
improve the dynamicness and quality of the moon and stars"*.

### Three defects that invalidate current verification — fix before judging art

**1. The wordmark's footprint is platform-dependent, so every keep-out check is unvalidated.**
SVG-as-image cannot load external fonts, so `<text font-family="ui-monospace,SFMono-Regular,Menlo,
monospace">` falls back to a system face. It *does* render — "the font fails to load" is the wrong
framing. The real defect is measured: substituting the stack moves the type's ink width by **−9.9%
(`sans-serif`) and −12.1% (`serif`)**. Every keep-out and collision check in this track was computed
against *this machine's* metrics; a platform with a wider fallback pushes the wordmark past what the
check cleared and the check still reports green, because it was computed here. **Draw the wordmark as
pixel geometry or outlined paths** — that makes the footprint invariant, which is the only thing that
makes the gate's central guarantee true rather than locally true.

**2. S3 is falsified in practice — the day scheme does not reach readers.** S3 concluded "one
self-theming file — no `<picture>`, no second asset", measured with a scheme-**emulation** probe. The
operator switched their OS to light and got no day version. The reliable mechanism is already in this
repo: **`README.md` ships four `<picture>` blocks with `media="(prefers-color-scheme: dark)"` on the
`<source>`** (lines 68/135/183/301), which resolves in the *host* document where the query definitely
works. Emit **two files behind `<picture>`**, same as every diagram already in that README. (A
contributing cause was local and is fixed: the comparison page declared `color-scheme: dark`, and an
SVG-as-image resolves the query against the embedding document, so that page could never show day.)

**3. Rendered size is 830 px, and 1920→830 is a NON-INTEGER ~2.3× downscale.** Judge everything at
rendered size, never at 1:1 of the art grid. This directly bounds the star work below: a 1 px star
lands on a fractional device pixel and shimmers.

**Not a defect — refuted:** CSS `@keyframes` inside an `<img>`-loaded SVG **does** animate in Firefox
144 (Marionette, one document, two screenshots straddling a hard flip, SMIL positive control also
advancing so the harness is sound). Mozilla bug 1190881 does not bite this build. **Do not re-express
anything in SMIL.** Note the two tests that gave *wrong* answers first: a single screenshot only
proves t=0 is composited, and two screenshots from two page *loads* both land at t≈0 because the
timeline anchors at load.

### Moon, stars and clouds — craft brief

Source: `docs/research/prior-art.md` §D. ⚠️ **This supersedes earlier optics guidance in this track
that was wrong for pixel art:** a smooth radial gradient behind a pixel moon reads as a Photoshop
layer sitting on top of the art and **will band**, so stacked `feGaussianBlur` bloom is the wrong
mental model.

**Moon glow** — 2–4 concentric **bands** stepping down the sky ramp, one step each, radii growing
non-linearly to fake inverse-square falloff. Hue-shift toward the moon's own hue and desaturate
outward so the glow resolves into the *sky*, not into grey. Dither **only** the outermost boundary;
interior boundaries stay hard. **The glow is not concentric on a crescent** — it centres on the lit
portion, offset toward the horns' outer edge; centring on the disc is a tell. Keep the radius under
~2.5× the moon's, or it reads as fog.

**Moon geometry, which is where amateurs die** — a crescent is bounded by a half-**circle** and a
half-**ellipse**: the terminator is an elliptical arc whose major axis is a diameter of the disc. Two
overlapping circles of different radii gives the *logo* moon, not the *sky* moon. The horns point
**away from the sun**, so at night they angle down toward the horizon, never up (xkcd 1738 flags
horns-up-at-night as impossible), and the line joining the horns must be a **diameter**, not a chord.
Add **earthshine**: the unlit disc filled one ramp step above sky, bounded by the same circle — the
cheapest single detail that separates "drew a moon" from "looked at the moon".

**Stars** — **desaturate almost everything.** Faint point sources are genuinely colourless to human
vision (small-field tritanopia), so a multicoloured starfield is *factually wrong*, not merely gaudy.
Give hue to **3–6 stars in the entire field**, in real temperature order, warm ones for contrast
against a cool sky; everything else near-white or one step off the sky colour. **At least three
brightness tiers** — a handful at palette-white, a middle band one step down, the majority two steps
down. Placement **clustered-random**, never even and never a grid: delete accidental lines and
triangles, and **carve a deliberate void** behind the wordmark and above the creature. **Twinkle a
minority**, at incommensurate periods (2.3 / 3.1 / 4.7 / 5.9 s, ±1 ramp step), and only the **low**
stars — scintillation is atmospheric and strongest near the horizon, so high stars stay steady.
**No diffraction spikes**: they are a camera artifact, and at this scale a 4-point spike reads as a
sparkle emoji. **Never pure `#ffffff`** — it blows out against a dark sky and destroys the magnitude
hierarchy.

**Clouds** (v6c's signature) — dither the **interior** transition and keep the **silhouette hard**:
the silhouette is the design, the dither is the material. And the decisive animation trap: a moving
region's dither **crawls** unless it translates as a **rigid group** in whole art-pixel steps. These
clouds drift, so this binds.

## LEGIBILITY AUDIT — will a first-time viewer understand any of this? (2026-07-29)

Operator asked directly whether the beats are too abstract. Honest answer: **no first-time viewer
will decode any of them, and two have a worse failure mode than abstraction — they read as broken.**
Recorded here because the implementation was mid-build with two beats placed where nobody will see
them, and because the conclusion changes what to build, not just how to describe it.

### Reach — measured against the windows in the generator, not estimated

A reader arrives at t=0 (confirmed anchoring) and stays 5–15 s, once.

| beat | window | dwell needed | reach |
|---|---|---|---|
| THE REFUSAL | 3.0–8.0 s | ≥3 s | **essentially every viewer** |
| THE ASK | 13.0–22.0 s | ≥13 s | a minority |
| THE OVERLAP | 36.0–44.25 s | ≥36 s | **almost nobody** |
| visitor glance | 48.5–54.5 s | ≥48.5 s | **nobody** |

Front-loading was applied to the *first* beat only. Two of four sit outside any realistic dwell —
the same defect as the old set's t=231 s star, merely less extreme. **A beat worth building belongs
inside ~20 s.**

### The code problem, and why the subtitle is load-bearing

Every beat requires a code the viewer does not have: *ground = progress*, *reversal = work undone*,
*print density = two sessions*. None is inferable from the image. **And the one element that could
hand over the code is itself illegible** — the subtitle renders at ~7.3 CSS px desktop and ~3.4 px
mobile. Coded events plus an unreadable key compounds: making the subtitle legible is the cheapest
change with the largest effect on comprehension, and it is a prerequisite for the beats meaning
anything at all.

### Two misread risks — worse than "too abstract"

1. **THE REFUSAL may read as a rendering glitch.** A ground layer scrolling backward is what a broken
   animation looks like. Same failure class as v6b's interpenetrating sprites. *Looks broken* is a far
   worse outcome than *looks abstract*. Mitigation: an anticipation cue before the reversal so it
   reads as caused rather than as a stutter.
2. **THE ASK's 6 s of dead world may read as "the image finished loading."** A frozen banner caught
   mid-stop is indistinguishable from a stalled asset. Mitigation: keep something unmistakably alive
   through the stop — a blink, a breath — so cessation never reads as failure.

### What works, and what to sacrifice

**THE ASK lands** — not because the mechanism is legible but because **stillness plus direct outward
gaze is a human-universal signal**. Nobody reads "class C decision packet"; everybody reads "it
stopped and looked at me." That is the right note reached without a code, and it is why this beat
survives the audit intact.

**THE OVERLAP is the inverse: the most conceptually beautiful and the least perceptible.** Its mark is
a pitch change in ~6 px footprints; even an attentive viewer must be studying the ground. It is the
designated sacrifice if something must go — purest idea, lowest visibility.

### The honest posture, which should be stated rather than quietly assumed

**The ambient layer carries the banner for everyone; the beats reward the second look.** That is a
coherent design and it matches where viewer value actually lives — but it must be claimed openly.
Do not assert legibility the artifact does not have. Three consequences follow: make the subtitle
legible; pull THE ASK into ~8–14 s and THE OVERLAP inside 20 s or cut it; de-risk both misreads.

## OPERATOR MICRO-EVENT IDEAS (2026-07-29) — the live design input, and they beat mine

Given verbatim, with the note *"I think you should be able to research and come up with better
ones"* — so these are a **starting point to improve on, not a finished set**. Two of them overturn
rulings this document has been enforcing, and the operator authored those rulings, so their direction
governs. Recorded before improving on them so the originals are not lost to paraphrase.

### O1 · Handoff with two-way communication

> clawd puts on a magician hat and wand and spells up a teammate clawd. main clawd passes a mail
> letter for new clawd to read, then do a task, then hands back the task result such as building a
> cake, then waves good bye and poofs away by itself

**This is the most complete beat anyone has proposed in this track.** It has an unforced
beginning/middle/end with agency at every step: summon → hand over → work → hand back → farewell →
self-removal. The exit is *self*-removal, which is the strongest form — the departing party ends
itself rather than being faded out.

**It is also more literally accurate about the mechanism than my abstraction was.** `cc-notify`
enqueues a message as a **file the other session reads at a safe boundary** — a letter handed over IS
the mechanism, not a metaphor for it. And `handoff-fire.sh self-close` has the predecessor retire
*itself* once the successor is verified engaged, which is exactly "waves goodbye and poofs away by
itself".

**⚠️ It reverses two things this document argued.** (a) The "peers are never co-present" principle —
which I used to *dissolve* R1 — is contradicted: two clawds share the frame and interact. (b) An
object passing between two creatures is close to the picture R1 rejected. **The operator authored R1,
so this supersedes my derivation, and it is not to be re-litigated** — noted here only so a successor
does not "restore" the co-presence rule and quietly delete the operator's best idea. The trade is
explicit and favourable: it costs the architectural purity of one-creature-in-frame and buys a beat a
stranger can actually follow, which is precisely what the legibility audit above says the set lacks.

### O2 · Fireworks with clawd celebrating/dancing — on a commit succeeding

Repo-real (a land is the system's genuine success event) and **universally legible without a code** —
the one thing the audited set was short of. Cautions, not objections: fireworks are a heavily-used
beat, so the execution has to earn it; and celebration must be **whole-body posture** (the arms-up
cliff already measured — limb-level acting is illegible at this render size).

### O3 · Shooting star across the sky, with clawd's eyes following it

**This rehabilitates the beat I deleted, and the operator's version fixes what was wrong with it.**
My objection was that a shooting star refers to nothing and has no cause or exit. Adding *clawd
watching it* supplies the missing half: the event is not the star, it is **the noticing**. Gaze is
causality expressed for free, and reaction is what a bare star lacked.

Two constraints carry over unchanged: the star is inside `nOnly`, so it is **absent in the day
scheme** and needs a daylight counterpart (something crossing a bright sky — a bird, a paper plane);
and per the legibility audit the star must not read as a glitch, so the gaze should *lead* slightly,
selling the star as caused rather than as a stray pixel.

### Where this leaves the built set

The three specified beats (THE OVERLAP / THE REFUSAL / THE ASK) are **not cancelled** — THE REFUSAL
and THE ASK survived the audit on their own merits, and THE ASK is the only one that works on a
stranger. But O1–O3 are more legible than all three, and **O1 subsumes THE OVERLAP's meaning**
(succession) while being visible rather than a 6 px pitch change. If a beat is to be sacrificed,
THE OVERLAP was already named the candidate, and O1 replacing it is a strict improvement.

**Next, and explicitly invited: research better versions of these three** rather than implementing
them literally. The operator expects improvement on the sketch, not transcription of it.

## Acceptance

An event passes only if a viewer can answer all three of *why did it appear*, *what did it do*, and
*how did it leave* — from the animation alone, without reading this file. **And it must pass in both
colour schemes**, since a reader gets whichever one their OS is set to and never sees the other.
**And it must be placed where a reader will actually meet it** — before t≈30 s, or it is not a rare
event, only a late one.

---

## IMPLEMENTED — the recommended three (2026-07-29, pool-2). Implementer's note to the spec owner.

The recommended set is built on `feat/banner-showoff`. Verification and the full findings are in
`README_HERO_BANNER.md` § v7 (S17-S21); this section records only what the *spec* should know,
because two of its own rulings turn out to be incomplete rather than wrong.

| Beat | Window | As specified? |
|---|---|---|
| THE REFUSAL | 3.0-8.0 s | Yes. Post arrives with the ground, bar drops across the path, world pulls back exactly one print pitch, creature re-steps into the print it already made. |
| THE ASK | 13.0-22.0 s | Yes, plus a forced tail. 6 s of dead world, ears up, gaze parked front — then 3 s at treble, which the loop demands (below). |
| THE OVERLAP | 36.0-44.25 s | Yes. 12 extra prints at the half-pitch; the foot lands on every second print; exits by re-registration. |

**§ Enforcement's rule "every rate modulation spanning an exact multiple of the 0.5 s stride" is
necessary but NOT sufficient.** It does not cover *repayment*, and repayment is not optional:

1. Every scrolling layer must travel a whole number of its own wrap distances per master period or
   the loop seams, so a permanent world-time deficit would have to be a common multiple of every
   layer's period — and the slowest layer's period **is** P. **Every stop and rewind must be repaid
   inside the loop, above nominal rate.** THE ASK's 6 s cessation is therefore inseparable from a
   catch-up; it cannot be specified without one.
2. The repayment rate must be an **integer** multiple of nominal, because the print lock requires a
   whole number of pitches per stride. So the world's entire rate vocabulary is `{−1, 0, 1, 2, 3}` and
   **there is no gentle catch-up.** 6 s of stillness costs either 6 s at 2× or 3 s at 3×.

Both are now build-time assertions, so a future re-timing cannot quietly violate them. The
consequence for the spec: a beat that stops or reverses the world must budget its repayment as part
of its own declared window, or the duty budget is measuring a fiction.

**§ "at most one feature on canvas" needed a spatial form, not a temporal one.** A beat riding the
scrolling strip is on canvas for `(1920 + width) / 96` ≈ 20-26 s however brief its declared window is,
so THE REFUSAL and THE OVERLAP can be a comfortable 4 s apart in the event table and still put two
objects on screen together for twenty seconds. Their spacing is set by geometry, and
`assert_one_strip_feature` sweeps the real world clock to check it — the clock matters because THE
ASK's stop compresses the wall-clock gap between two strip features without changing either's window.

**One deliberate addition, for legibility rather than story:** THE REFUSAL's post is still on canvas
through THE ASK. That is not leftover scenery. A stopped strip of *uniform* ground texture is
ambiguous — nothing in it says whether it is moving — so one distinct object standing dead still is
what makes the next beat's cessation readable at all. It does nothing during it; it just holds.

**Open for the spec owner, unchanged by this session:** the visitor beats (`peek`/`peer`/`rCheer`) are
**demoted to t≈48-57 s, not deleted.** The synthesis' co-presence reframe indicts them — a session is
never co-present with its peers — but acting on it deletes v6b's entire identity, which is a spec
ruling and not an implementation call. They keep their machinery; one line in `RARE_EVENTS` reverses
the demotion, and removing them from `ALWAYS_EMITTED` completes the deletion.
