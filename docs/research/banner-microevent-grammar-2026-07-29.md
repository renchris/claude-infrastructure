# Ambient micro-event grammar for a looping decorative scene — derived

Derivation + numeric checklist for `assets/banner/v5a-long-walk.svg` (1920x600, P=240s,
Chrome-dino idiom). Companion to `docs/plans/BANNER_NARRATIVE_SPEC.md` (branch
`docs/banner-narrative-spec`), which holds the qualitative cause/behaviour/exit ruling.
This file is the NUMERIC half: thresholds, class taxonomy, measurements off the artifact,
and a lint spec. Produced by a research subagent 2026-07-29. Not committed by its author.

## 0. Three mechanism facts that invert the usual derivation

| Fact | Evidence | Consequence |
|---|---|---|
| A CSS-animated SVG has NO seam. Nothing restarts at t=P. | `scripts/banner-build.py:20-34` R3 | "P=240s" is the ensemble recurrence period = LCM of element periods, not a seam. A period must divide 240 only if that element joins the story's return. |
| The viewer's clock is anchored at t=0, not a random phase. SVG-in-`<img>` starts its CSS timeline when the image renders; the hero is first on the page; Chrome does not throttle SVG-in-img animation offscreen. | readme-typing-svg's mechanism; chromium/CSSWG thread | THE FIRST 30 SECONDS IS THE PRODUCT. v5a's `shoot` enters at t=231.4s => seen by ~0% of readers. |
| Shipped size is 900 CSS px, not 1920. | `scripts/banner-apply-header.sh:38` emits `width="900"`; mobile ~360px | Scale 0.469x desktop, ~0.19x mobile. A 26px hop = 12 CSS px desktop, 5 CSS px mobile. Check every threshold at DISPLAYED size. |

MUST-VERIFY (2 min): publish to a scratch gist, hard-reload, confirm the first beat fires ~3s
after paint rather than at an arbitrary phase. If GitHub lazy-loads or re-encodes the hero,
placement reverts to random phase: P(overlap) = (d + D)/P.

## 1. The taxonomy — highest-leverage move

v5a's failure is a MISSING TYPE SYSTEM: five things on independent timers, so simultaneity is
the only relationship the composition can express, and it expresses it by accident.

| Class | What | Duration | Entry/exit law | Duty budget | Period law |
|---|---|---|---|---|---|
| TEXTURE | continuous, transition-free | 100% | never appears/disappears | 100% (see 1a) | periods COPRIME to P and each other; phase baked PER ELEMENT |
| STATE | slow world/creature condition | unbounded | posture/level change over 2-6s, never a crossfade | <=40% each; <=2 concurrent, mutual-exclusion matrix | must divide P |
| VISITOR | object that arrives and leaves | **<=10s, target 3-8s** | <=0.3s transient, or motion, or occlusion — NEVER opacity | <=4% each, <=15% aggregate | must divide P |
| BEAT | the creature's reaction | 0.3-1.5s | begins 150-400ms after its cause; ends on baseline | <=5% aggregate | slaved to a VISITOR/STATE, never a free oscillator |

The 46% problem in one line: **the balloon is a VISITOR with a STATE's duration** (57.6s per
instance, twice per loop). `peek` at 24.0s is the same error. Class is the knob; duration follows.

### 1a. TEXTURE law: de-phase or it becomes one giant event

v5a's 91 stars carry three animations `sA`/`sB`/`sC` at 60/30/10s with NO per-element phase and
`animation-delay` appearing 0 times. 46 stars pulse in unison, then 30, then 15 — the whole sky
swells every 10s, a full-field luminance transient more salient than any 7px meteor, on a period
inside the dwell window so the metronome is detectable.

This REGRESSES the repo's own builder: `banner-build.py:227-250` gives each star its own
`@keyframes` with baked random phase via `hold_cycle(holds, ph)` and one of four periods
`(7, 9, 11, 13)` — coprime, so the field never repeats. The fix mechanism already exists.

Threshold (defensible): any periodic ambient element with period < 1/3 median dwell (< ~10s) and
N > 3 synchronized instances reads as a beat. De-phase per element or lengthen the period.

## 2. What makes "caused" — mechanisms with windows

| Mechanism | Window | Source | Use here |
|---|---|---|---|
| Launching / contact causality | effect <=70ms after contact; ~50ms discrimination threshold; >150-200ms reads as two independent events | Michotte, registered replication (R.Soc.Open Sci. 2025); Hubbard 2004 | meteor->impact flash. At 24fps: <=2 frames. |
| Kinematic consistency | cause moves FIRST; effect direction matches; velocity ratio in a narrow band | Michotte's 3 conditions | ejecta must fly along the meteor's vector, not radially |
| Gaze cueing | orients at SOA 100-700ms, peak 300-700ms | Frontiers Psychol. 2017/2021; PLOS ONE 2016 | THE load-bearing device: head turn 150-400ms after onset |
| Animacy from kinematics | driven by magnitude of speed change + angular magnitude of direction change | Tremoulet & Feldman 2000, Perception 29:943-951 | the entire recipe for "exit with agency" |
| Motion-onset capture | motion onset captures where abrupt onset/offset does not | JOV; Atten.Percept.Psychophys. 2013 | banner sits in parafovea while reading text below => motion, not opacity, is the only cue that reaches them |
| Gradual-change blindness | gradual changes missed 69% of the time with NO disruption (vs 59% across one) | Simons, Franconeri & Reimer 2000, Perception 29:1143-1154 | v5a's fades are 4.8s — below threshold. A slow crossfade is not an entrance. |
| Kuleshov / reaction shot | meaning from juxtaposition; neutral face + context reads as caused | Kuleshov; fMRI replication 2024 | the creature's reaction makes the cause legible — cheaper than elaborating the event |

### 2a. Both "events" move at scenery speed (measured)

Parallax speeds from `@dF` (`translateX(-1960px)`) over each class's period:
cf 240s = 8.2 px/s · cm 120s = 16.3 · gF 120s = 16.3 · gN 60s = 32.7 · grun 20s = 98.0

- `balloon` (`@bo`: 1980,0 -> -160,-60 over 120s) = **17.8 px/s**, vertical component 0.5 px/s
  => within **9%** of the mid-cloud/far-ground layer. Kinematically world-fixed = scenery.
- `shoot` (`@sh`: 0,0 -> -660,310 over 7.2s) = **101 px/s** => within **3%** of `grun`.
  A meteor moving at ground-scroll speed.

An object drifting at a parallax layer's rate IS that layer, whatever it depicts. 46% duty made
the balloon ambient; the velocity match made it scenery even at 4%.

Thresholds (defensible): peak speed >= 3x the fastest layer => **>=300 viewBox px/s** (~140 CSS
px/s at 900). A 729px meteor path in **<=2.2s, target 1.0-1.5s**. OR use the unoccupied channel:
ALL parallax is pure translateX, zero vertical => any vertical motion >=40 viewBox px separates
figure from ground at any speed.

### 2b. Fade vs exit-with-agency

A fade is the OBSERVER's loss of information; the object does not act, it stops existing.
Agency requires, in preference order:
1. Self-propelled acceleration — speed change >=2x within <=0.5s, or direction change >=30°, then exit through a boundary.
2. Occlusion — behind a mound, below the horizon. "Gone" without "ceased to exist". Cheapest correct exit here (mounds exist).
3. Transformation — it pops, or lands and becomes something persistent (the ember).

Opacity->0 is not on the list. If used at all: **<=0.3s**, plus motion.

## 3. Duration and duty cycle — where the boundaries are

Dwell model (NN/g): users often leave in 10-20s; still likely to leave through the next 20s;
curve flattens ~30s; average visit a little under a minute; survive 30s and 2min+ is common.
Working survival: S(10)~0.7, S(20)~0.5, S(30)~0.4, S(60)~0.25, S(120)~0.15.

- t=0 anchored (this case): P(see event entering at t) = S(t). Duty is nearly irrelevant; ENTRY TIME is everything.
- Random phase (fallback): P(overlap) = (d+D)/P; P(witness an entry) = min(1, n*D/P).

| Read | Boundary | Derivation |
|---|---|---|
| SCENERY | per-instance duration > median dwell (>30s), OR speed within +-25% of any parallax layer, OR per-type duty >35% | If the instance outlives the visit the viewer ARRIVES MID-EVENT: no beginning, so no cause, so furniture. P(a 20s window contains the balloon's ENTRY) = 20/120 = 17%; P(contains its PRESENCE) = 48%. Presence dominates ~3:1. |
| RARE AND SPECIAL | per-instance **2.5-10s** (target 3-8s); per-type duty **<=4%**; >=1 instance entering before t~45s | Upper bound: <=1/3 median dwell so entry+middle+exit fit in one visit WITH air either side (contrast needs witnessed absence). Genre check: Cookie Clicker's golden cookie — the canonical rare catchable event — is 13s on screen, 300-900s spawn interval = 1.4-4.3% duty. |
| MISSABLE | entry at t>45s (<=30% of readers) or t>120s (<=15%); random-phase per-instance duty <1% (<=2.4s/240s => 9%) | v5a's `shoot` enters at t=231.4s => ~0-5%. The only event the spec calls genuinely rare is functionally absent from the product. |

Aggregate bands (defensible in direction, +-5pp taste): VISITOR duty **12-25%**; union event
coverage **20-35%**; **>=65% of the loop empty air** — "special" is a contrast effect.

Measured v5a: aggregate duty **88.1%** (211.4s/240s); union coverage **64.8%**; >=2 concurrent
**40.7s**; >=3 **11.6s**; 4 concurrent **3.6s**.

Per-event measured: balloon 115.2s/48.0% · sleep 26.4s/11.0% · spin 24.0s/10.0% ·
peek 24.0s/10.0% · cheer 14.4s/6.0% · shoot 7.4s/3.1%.

## 4. Distribution across P

**Overlap: never between independent events; always inside a causal chain.** Not taste — the
attribution machinery binds whatever co-occurs, so independent overlap yields false causality or
incoherence. v5a's pathological case:

```
t=148.8-175.2  sleep    }
t=150.4-158.4  spin     } 8.0s where the creature is simultaneously
t=154.8-162.0  cheer    } ASLEEP, CHEERING, and FACING BACKWARD
t=122.4-180.0  balloon  ...while a balloon that means nothing drifts past
```

Permitted overlaps, exhaustively: (a) the reaction window — a BEAT overlapping its cause by
0.15-1.5s; (b) a chain hand-off — A's exit overlapping B's entry by <=1.5s where B is caused by A;
(c) a persistent token (the ember), which is a STATE not an event.

**Spacing: neither even nor random — DECAYING, because the audience decays.** Even spacing
maximises P(witness) for a given n, but a metronome with gap < dwell is detectable (2-3 samples).
Jitter gaps +-30-40%: two samples differing >30% cannot support a rhythm estimate.

| block | events | mean gap | rationale |
|---|---|---|---|
| 0-30s | 2 | 12-16s | 50-60% of readers live here; both identity-carrying events land here |
| 30-60s | 2 | 15-20s | 30-40% reach here |
| 60-120s | 2 | 25-35s | ~20% |
| 120-240s | 2-3 | 40-50s | lingerer + operator; day-arc payoff; cheap variants OK |

Total **8-9 events per 240s**. Hard caps: max gap **<=20s before t=60**, **<=45s after**.
Measured v5a max gap **50.4s** (t=180->230.4) — 21% of the loop dead, exactly where the climax
should be.

Repetition: D << P, so an event recurring at >=2x median dwell is effectively never seen twice.
(i) No event type may recur with gap **<60s** (v5a: spin every 80s, balloon gap 62.4s — marginal).
(ii) Variety is cheap to skip — 5 types with jittered variants are indistinguishable to 95% of
viewers. (iii) Spend the whole art budget on the two events before t=30s.

## 5. The loop as a day, not a reset

1. **One global slow variable, single-cycle over P, smooth at the wrap** (light/colour temp/shadow
   angle). A 240s sinusoid changes ~0.4%/s — BELOW the change-detection threshold. This is
   gradual-change blindness USED AS A FEATURE: never seen changing, always noticed as changed.
   The same mechanism that makes a 4.8s event-fade invisible (bug) makes a 240s light arc feel
   like time passing (feature). v5a has no such variable: `@mn` pulses the moon on an 80s period
   (3 unrelated pulses/loop) while `rSleep` sits on 240s. Nothing is slaved to anything.
2. **Events keyed to phases of that variable**, so each inherits its cause from world state — the
   only way to get causality without contact. Chrome Dino does it with one integer:
   `INVERT_DISTANCE: 700` flips day<->night, `INVERT_FADE_DURATION: 12000` (12s) crossfades it,
   and `PTERODACTYL.minSpeed: 8.5` gates the rare obstacle behind world state, not a timer
   (`t-rex-runner/index.js:115-125, 1503-1505`). Genre scale for a full day: Minecraft 20 min,
   Terraria 24 min (15 day/9 night), Stardew ~14 min. A 4-min day is 3-6x fast; acceptable only
   because the light change stays sub-threshold.
3. **The last beat sets up the first.** The spec's wrap — the next cycle's streak wakes the
   sleeper — is correct, and under t=0 anchoring it also puts the prime mover where everyone
   arrives. The chain MUST be re-laid-out: star at t~3s, sleep at t~150-200s. v5a is inverted
   (sleep 148.8, star 231.4).
4. **The wrap sits at the loop's least-informative moment.** A reset is detectable only if the
   viewer was tracking something. v5a places its most memorable beat (meteor, ends 238.8s) **1.2s
   before the wrap** — worst possible. Climax at **55-75% of P**; last **12-15% of P** settles.

The wrap has a second job that AGREES: `@media (prefers-reduced-motion: reduce)` sets
`*{animation:none!important}`, so the still renders every animation's 0% value. Therefore the
JOINT 0% STATE MUST COMPOSE A PUBLISHABLE PHOTOGRAPH — and calm, which is what (4) wants. One
constraint, two payoffs. (v5a satisfies the mechanical part: every event is opacity:0 at 0%.)

Conflict: t=0 is also the first impression, which wants to be arresting. Resolution — t=0 is the
calm-before and the first event's onset is at **t~2.5-4s**: the still stays composed, the live
viewer gets a beat inside 4 seconds.

## 6. Period assignment — the fix for "independent timers"

Root cause of the pile-up AND the "reads as random" complaint: phase is a percentage of each
event's OWN period, and periods differ (240/120/80). 29% of 120s and 29% of 240s are different
absolute times, so nothing can be scheduled relative to anything. The builder forbids the obvious
fix — `banner-build.py:31-34`: phase must live in keyframe percentages because `banner-shots.sh`
overrides `animation-delay` on `*` to seek a timestamp, and `--lint` fails the delay form.

**Compatible fix: every STATE/VISITOR/BEAT track gets `dur: 240s`. Multiple occurrences become
multiple pulses inside one 240s keyframe list.** Percentages then ARE absolute seconds
(1% = 2.4s), the loop becomes one readable score, `hold_cycle()` already rotates pulses inside a
period, and the shots-seek freeze still works.

Then split the period space by class:
- STORY (STATE, VISITOR, BEAT, global light) -> period exactly P. The ensemble returns.
- TEXTURE -> periods coprime to P and each other (7, 9, 11, 13 per `banner-build.py:236`), phase
  baked per element. LCM astronomical => never visibly repeats, cannot form a beat.

One period assignment cannot give both properties. Assigning BY CLASS gives both.

## 7. The anticipation/resolution pair

Minimum cue, cheapest first:
1. **Arrest an established rhythm.** The walk is `0.5s steps(1,end)` — a perfect metronome (a
   textbook 12-frame-per-step walk at 24fps). **Halting it for 0.6-1.2s is a 100%-reliable
   transient needing zero new artwork**, because rhythm violation IS a transient.
2. **A directional gaze** — works with a pixel face; orients at 100-700ms SOA. Head/ear turn
   toward the entry region **300-700ms before** the thing arrives.
3. **A herald that precedes its object** — a shadow crossing the ground, a mound's shadow
   deepening, a growing glow. Lead **1-3s**; beyond ~6s the link is lost unless the cue PERSISTS
   (grows/brightens) — persistence buys longer leads.
4. **Anticipation on the creature's own action** — 250-500ms (6-12 frames @24fps) small, up to 1s
   large; ~1/3 of the action's duration, minimum ~100ms.

Minimum payoff, from the oculomotor budget:
saccade latency ~200ms + flight 30-50ms + fixation/identify ~200-300ms => **400-500ms before the
eye is on target**. Therefore: **transient at t0, payoff at t0+0.5s to t0+2.0s. NEVER put the
payoff at t0.** A 0.3s meteor whose whole existence IS the transient cannot be seen. (Animal
Crossing pairs shooting stars with an audio herald and sends them in pairs — a second chance for
a late eye.)

Minimum viable full-grammar event:
```
0.15-0.30s  entry transient (motion onset, >=300 px/s or vertical)
0.20-0.40s  eye-arrival slack — nothing important happens here
1.0 -2.0s   the ONE legible state change (the payoff)
0.3 -0.5s   exit: speed change >=2x or direction change >=30°
0.2 -0.5s   through an edge or an occluder
=> ~2.5s floor · 4-8s comfortable · 10s ceiling
```
Plus, in parallel: BEAT — the creature's reaction beginning 150-400ms after onset, directional,
returning to baseline with 300-800ms follow-through.

### 7a. The baseline motion budget — why no event can read as special

| baseline motion | period | instances per 240s |
|---|---|---|
| `hop` (26px jump + 9px secondary) | 4s | **60** |
| `look` (head -20px then +20px) | 8s | **30** |
| `ears` | 2s | **120** |
| `blink` | 4s | 60 |
| synchronized sky swell (`sC`, 15 stars) | 10s | 24 |

The creature hops 60x and turns its head 30x per loop. **The strongest causal device available —
a directional gaze — is spent on a free-running 8s oscillator that cannot correlate with events on
240/120/80s periods except by accident.** A creature always doing something can never be seen to
REACT.

Rule: BEAT-class motion (gaze, gesture, posture) is NEVER an independent oscillator. Budget
**<=1 spontaneous creature motion per 20s** outside a caused BEAT (12/loop, not 270). `blink` and
`ears` may remain TEXTURE if de-phased and small; `look` and `hop` must become BEATs with causes.

## 8. THE CHECKLIST — hold a candidate event against these, in order

Gate 0 — CLASS. Name it: TEXTURE / STATE / VISITOR / BEAT. If it fits none, it isn't designed. STOP.

Gate 1 — PLACEMENT (t=0-anchored; strongest filter, apply first)
1. Does an instance enter before **t=45s**? (>45s => <=30% of readers; >120s => <=15%.)
2. If it carries the piece's IDENTITY, does it enter before **t=30s**? Identity after t=40s is not shipped.
3. Is t=0..~2.5s free of it, so the reduced-motion still stays calm?

Gate 2 — DURATION (VISITOR)
4. On-screen per instance in **[2.5s, 10s]** (target 3-8s)? >30s => SCENERY; <2.5s => unseeable.
5. Per-type duty <=**4%**? Aggregate VISITOR <=**15%**? Total event duty <=**25%**? Union coverage <=**35%**?

Gate 3 — KINEMATIC FIGURE/GROUND
6. Peak speed >=**3x** the fastest parallax layer (**>=300 viewBox px/s**) OR vertical component >=**40 viewBox px**? Within +-25% of any layer => it IS that layer.
7. Salient travel >=**40 viewBox px** (>=7.6 CSS px at 0.19x mobile) and key silhouette >=**50 viewBox px** in its largest dimension?

Gate 4 — CAUSE
8. Name the cause in one clause. "A timer fired" fails. Legal: another event's product, a STATE threshold crossing, the creature's own action, or EXACTLY ONE designated uncaused prime mover per loop.
9. Is the cause ON SCREEN (spatial contiguity) and does it move FIRST (Michotte's priority)?
10. Contact-type: effect within **<=70ms** (<=2 frames @24fps)? Reaction-type: **150-400ms**? Herald->arrival: **1-3s** (<=6s only if the herald persists/grows)?
11. Is there a cue at all? Cheapest sufficient cue = **halt the walk cycle 0.6-1.2s**.

Gate 5 — BEHAVIOUR (the middle)
12. Exactly ONE legible state change, **1.0-2.0s**, starting **0.5-2.0s after** the entry transient (never at it)?
13. Nameable in three words by someone who hasn't read the spec? (v5a's cheer fails — reads as "horns"; `clawd-sprite.py` measured the cliff at rise -3.)
14. Does the creature's BEAT respond, directionally, within 150-400ms?

Gate 6 — EXIT
15. Contains a **speed change >=2x** or **direction change >=30°** in the final 0.5s?
16. Leaves through an EDGE, an OCCLUDER, or a TRANSFORMATION? An opacity fade FAILS.
17. If opacity is used at all, does it complete in **<=0.3s**? (4.8s fades are missed 69% of the time; v5a's are 4.8s.)
18. Symmetric with the entry where the fiction implies it (out of a mound => back into THE SAME mound)?

Gate 7 — COMPOSITION
19. Overlaps another event? Legal only as (a) a BEAT reacting to its cause, (b) a <=1.5s chain hand-off, (c) a persistent STATE token. Independent overlap FAILS.
20. Violates the MUTUAL-EXCLUSION MATRIX? (asleep _|_ cheering _|_ walking _|_ facing-backward.)
21. Gap to nearest neighbouring entry: >=**8s** (air), <=**20s** before t=60, <=**45s** after?
22. Recurrence gap >=**60s** for the same type?
23. Wordmark keep-out respected — including strokes/lines, not just the sprite?

Gate 8 — MECHANISM
24. `dur: 240s` with phase in KEYFRAME PERCENTAGES (1% = 2.4s), never `animation-delay`? (`banner-build.py:31-34`; `--lint` fails the delay form.)
25. Does its 0% value participate in a publishable still?
26. Passes in BOTH colour schemes? (`.sh{opacity:.20}` + hidden starfield in light mode => the prime mover is nearly invisible for daylight readers. An event that only works at night cannot be load-bearing.)
27. TEXTURE only: period coprime to P, phase baked per element, no synchronized cohort >3?

## 9. A worked schedule (timings derived; fiction is taste)

9 events · aggregate VISITOR duty **10.4%** · union coverage **~19%** · max gap before t=60
**12.5s** · after **42s** · zero independent overlap.

| t (s) | beat | class | dur | notes |
|---|---|---|---|---|
| 0.0 | at-rest tableau: creature mid-stride, empty sky | — | — | = the reduced-motion still (all 0%) |
| 2.5 | herald: walk halts, ears perk, head lifts up-right | BEAT | 0.8 | free transient; 0.8s lead |
| 3.3 | streak enters top-right, 729px path, 40° down-left | VISITOR | 1.3 | **560 px/s = 5.7x grun** |
| 4.6 | impact: 0.15s flash + 2 ejecta along the meteor vector | — | 0.5 | effect at **+60ms** => contact causality |
| 4.8 | creature flinch, resumes stride, 0.5s settle | BEAT | 0.7 | reaction at **+200ms** |
| 5.1-> | ember persists: 1px warm pulse, period 11s (coprime) | STATE | — | the chain's memory; only warm mark |
| 17.6 | mound shadow deepens (herald) -> visitor walks out | VISITOR | 7.5 | occluder = the mound |
| 20.1 | creature notices: stride halts, head turns to visitor | BEAT | 0.6 | **+250ms** after it clears the mound |
| 21.0 | cheer: 0.35s anticipation crouch -> 0.5s whole-body hop w/ tilt -> 0.4s settle | BEAT | 1.25 | anticipation ~1/3 of action; silhouette CHANGES SHAPE, does not sprout |
| 23.5 | visitor sets the balloon by the ember (its one errand) | — | 2.0 | payoff at +5.9s of a 7.5s visit |
| 27.0 | visitor retreats behind THE SAME mound | — | 2.1 | symmetric => intent |
| 39.5 | balloon release: tugs, accelerates 0->250 px/s up, exits top edge | VISITOR | 3.5 | vertical channel; acceleration => agency |
| 58 | ambient A (counter-flow bird/seed, R->L at 340 px/s) | VISITOR | 3.0 | holds the <=20s pre-t=60 gap |
| 96 | ambient B (different silhouette) | VISITOR | 4.0 | |
| 138 | light dims (~58% of arc): creature slows, 0.8s sit anticipation, posture drops, 1px breathing, stride ABSENT, Zzz | STATE | ~55 | STATE => long duration legal; posture, not a badge |
| 168-238 | quiet: TEXTURE + ember + light arc only | — | — | last 13% settles => no reset detectable |
| (wrap) | next cycle's streak at t=3.3 wakes it | — | — | opener is the closer; t=P is the narrative return |

The climax sits at 1.4% of P rather than 55-75% — a KNOWING violation of §5.4, because t=0
anchoring dominates: a climax nobody sees is not a climax. §5.4 survives in its operative half —
THE WRAP IS CALM — which is what actually prevents the reset read.

## 10. Make it a lint, not a doctrine

Extend `banner-build.py --lint` to parse `<style>`, expand every keyframe list to absolute seconds
on the 240s master, and assert:

| # | assertion | v5a |
|---|---|---|
| L1 | every STORY-class period divides P | PASS (240/120/80/60) |
| L2 | no two VISITORs overlap | **FAIL** — 40.7s of >=2 concurrency |
| L3 | no two mutually-exclusive STATEs overlap | **FAIL** — asleep+cheer+backward 8.0s |
| L4 | every VISITOR entry has a BEAT within 150-400ms | **FAIL** — 0 of 5 |
| L5 | per-instance VISITOR duration <=10s | **FAIL** — balloon 57.6s, peek 24.0s, sleep 26.4s (mis-classed) |
| L6 | aggregate event duty <=25%, union coverage <=35% | **FAIL** — 88.1% / 64.8% |
| L7 | max entry gap <=20s (t<60) / <=45s (t>=60) | **FAIL** — 50.4s at t=180 |
| L8 | no VISITOR opacity ramp >0.3s | **FAIL** — all ramps 1.2-4.8s |
| L9 | peak speed >=3x fastest parallax, or vertical >=40px | **FAIL** — balloon 1.09x, shoot 1.03x |
| L10 | >=1 entry before t=45s; identity event before t=30s | **FAIL** — first true event t=34.8 |
| L11 | no TEXTURE cohort >3 elements sharing a phase | **FAIL** — cohorts of 46/30/15 |
| L12 | joint 0% state renders a legible still | PASS |
| L13 | every assertion re-evaluated under `prefers-color-scheme: light` | UNTESTED |

## 11. Defensible vs taste

DEFENSIBLE (mechanism or measurement): the <=70ms contact window; 150-400ms reaction window;
100-700ms gaze SOA; <=0.3s appearance transients and the 69% gradual-change miss; the 400-500ms
eye-arrival budget and hence the 0.5-2.0s payoff offset; >=3x parallax speed and the
vertical-is-unoccupied observation (both computed from this file); >=40px travel / >=50px
silhouette from the 0.469x/0.19x display scales; the <=10s VISITOR ceiling from duration-vs-dwell;
the t=0 anchoring consequence for placement; the class taxonomy and mutual exclusion; de-phasing
TEXTURE; period-by-class.

TASTE (defensible in DIRECTION, arbitrary in magnitude): 8-9 events per 240s; the 2/2/2/3
front-loading split; the 12-25% duty band and 65% empty-air floor; 240s as the day length (genre
says 14-24 min); +-30-40% gap jitter; the >=60s recurrence floor; climax at 55-75% of P.

PURE TASTE (fiction, not grammar): the star->ember->visitor->cheer->sleep chain; whether the
balloon survives as the visitor's property or is cut; the "clawd is a session, the sky is the
work" conceit; a day-cycle at all rather than weather or seasons.

## 12. Blockers and uncertainties

1. **t=0 anchoring is load-bearing and unverified in GitHub's actual pipeline.** If the hero
   `<img>` is lazy-loaded or re-encoded, placement reverts to random phase and §5's front-loading
   is wrong (§1-4 and §7 thresholds are unaffected). One 2-minute scratch-gist test settles it.
   DO THIS BEFORE SCHEDULING ANYTHING.
2. Dwell figures are general-web (NN/g), not GitHub-README-specific. Threshold ORDERING is robust
   to +-2x on D; the 45s/120s cut-points are not.
3. Overlap with existing work: `docs/plans/BANNER_NARRATIVE_SPEC.md` (branch
   `docs/banner-narrative-spec`, commits 79cb8bee, 56e21dd2) already holds the qualitative ruling,
   the 46% measurement, and the causal chain. This file is additive. TWO CONTRADICTIONS: (a) it
   calls the shooting star the prime mover that opens and closes the cycle while placing nothing
   at the loop's head — under t=0 anchoring the star must physically sit at t~3s; (b) it never
   addresses `.look` (8s) and `.hop` (4s), the largest single obstacle to any event reading as
   caused.
4. Untested cost: the spec's `feTurbulence` grain + stacked bloom over a full-width rect is the one
   genuinely expensive item, and it interacts with 91 star elements.
5. Light-mode parity is unmeasured against these thresholds. Gate 8.26 exists for this reason.

## Sources

Michotte replication (R.Soc.Open Sci. 2025) https://royalsocietypublishing.org/rsos/article/12/9/250244/235317/Michotte-s-research-on-perceptual-impressions-of ·
Hubbard, perception of causality http://timothyhubbard.net/hubbard_FD2004.pdf ·
Space and time in perceptual causality (Frontiers 2010) https://www.frontiersin.org/articles/10.3389/fnhum.2010.00028/full ·
Tremoulet & Feldman 2000 http://wexler.free.fr/library/files/tremoulet%20(2000)%20perception%20of%20animacy%20from%20the%20motion%20of%20a%20single%20object.pdf ·
Simons, Franconeri & Reimer 2000 http://wexler.free.fr/library/files/simons%20(2000)%20change%20blindness%20in%20the%20absence%20of%20a%20visual%20disruption.pdf ·
Gaze-cueing time course (Frontiers 2017) https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2017.02343/full ·
Gaze cueing and task demands (Frontiers 2021) https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2021.618606/full ·
Attentional capture by motion onset/offset (JOV) https://jov.arvojournals.org/article.aspx?articleid=2191962 ·
Flicker and abrupt displacement in motion-onset capture https://link.springer.com/article/10.3758/s13414-013-0587-x ·
Kuleshov effect fMRI replication https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11299807/ ·
NN/g How long do users stay on web pages https://www.nngroup.com/articles/how-long-do-users-stay-on-web-pages/ ·
t-rex-runner source https://github.com/wayou/t-rex-runner ·
Cookie Clicker golden cookie https://cookieclicker.wiki.gg/wiki/Golden_Cookie ·
ACNH balloon spawn rate https://www.nintendolife.com/guides/animal-crossing-new-horizons-balloons-spawn-rate-hunting-colour-guide ·
Minecraft day length https://www.namehero.com/gaming-blog/how-long-is-a-minecraft-day-the-ultimate-guide/ ·
Terraria day/night cycle https://terraria.wiki.gg/wiki/Day_and_night_cycle ·
Stardew day cycle https://stardewvalleywiki.com/Day_Cycle ·
After Dark, "never put the toasters on a track" https://lowendmac.com/2007/aggressively-stupid-the-story-behind-after-dark/ ·
Juice it or lose it (Jonasson & Purho) https://www.youtube.com/watch?v=Fy0aCDmgnxg ·
Disney's 12 principles https://www.adobe.com/creativecloud/animation/discover/principles-of-animation.html ·
SMIL/CSS in SVG-as-img https://css-tricks.com/guide-svg-animations-smil/ ·
CSS-in-SVG required for GitHub README animation https://blog.eamonncottrell.com/animate-svgs-for-github-readmes
