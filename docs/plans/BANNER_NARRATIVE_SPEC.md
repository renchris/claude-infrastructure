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

**Sequence them, do not stack them.** One event visible at a time, with clear empty air between.
Phase must live in **keyframe percentages**, never authored `animation-delay` — the freeze in
`banner-shots.sh` overrides delay on `*`, so an authored delay is discarded and every frozen frame
shows the wrong phase (and the t=0 vs t=P hash test cannot fail on the phase question).
`scripts/banner-build.py hold_cycle()` already rotates events inside a period; reuse it.

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
2. **Stride and scroll are not locked.** 32.7 px/s ÷ 2 strides/s = 16.3 px per stride = 1.13 cells,
   while the legs are two cells apart — **the creature has been sliding the whole time.** Fixing this
   is what makes the footprint lock possible, so it is a prerequisite, not a polish item.

### Open for the operator, not for us

**R3 of the binding ruleset says "seamless indefinite loop, ambient not narrative."** Everything
above is ambient-with-mechanism rather than plot, which is compatible — but the earlier chain was
not, and nobody adjudicated the conflict. If R3 stands as written, narrative-as-experienced is out
and the state/gauge reading is the only legal design. That is a ruling, not a craft call.

## Acceptance

An event passes only if a viewer can answer all three of *why did it appear*, *what did it do*, and
*how did it leave* — from the animation alone, without reading this file. **And it must pass in both
colour schemes**, since a reader gets whichever one their OS is set to and never sees the other.
**And it must be placed where a reader will actually meet it** — before t≈30 s, or it is not a rare
event, only a late one.
