## 0. Three mechanism facts that invert the usual derivation — establish these before any timing work

| Fact | Evidence | Consequence |
|---|---|---|
| **A CSS-animated SVG has no seam.** Nothing restarts at t=P. Each element's animation loops on its own period; "seamlessness" is per-element (0% value == 100% value), already enforced by `scripts/banner-build.py:20-34` R3. | `banner-build.py:22` R3; v5a's `@sh`/`@bo` end on a *different* transform than 0% and are still seamless because opacity is 0 at both ends | "P=240s" is not a seam — it is the **ensemble recurrence period = LCM of all element periods**. You only need a period to divide 240 if that element must participate in the *story's* return. This licenses a deliberate split (§6). |
| **The viewer's clock is anchored at t=0, not at a random phase.** An SVG in `<img>` starts its CSS timeline when the image begins rendering; the hero is the first element on the page; Chrome does not throttle SVG-in-`<img>` animation even offscreen. | CSS-in-SVG-file is *required* for GitHub README rendering (readme-typing-svg's whole mechanism); Chrome "treats the image contents as relevant to the user regardless of whether the image is on screen" (chromium/CSSWG thread) | **The first 30 seconds of the loop is the product.** An event entering at t=231s (v5a's `shoot`) is seen by ~0% of README readers. Every "how rare" calculation below is a function of *placement*, not duty cycle. |
| **The shipped size is 900 CSS px, not 1920.** `scripts/banner-apply-header.sh:38` emits `<img … width="900">`; mobile renders ~360px. | viewBox is `0 0 1920 600` | Scale factors **0.469×** desktop, **~0.19×** mobile. Every salience threshold must be checked in *displayed* px. A 26px hop = 12 CSS px desktop, **5 CSS px mobile**. A 1px star is sub-pixel. |

**MUST-VERIFY before committing to the front-loading rule** (one test, 2 min): publish the SVG to a scratch gist/README, hard-reload, and confirm the meteor fires ~3s after paint rather than at an arbitrary phase. If GitHub applies `loading="lazy"` to the hero or serves through a re-encoder, phase anchoring is lost and §5's front-loading collapses to the random-phase formula `P(see) = (d + D)/P`. Both formulas are given below so the schedule can be re-derived either way.

---

## 1. The taxonomy — the single highest-leverage move

The v5a failure is not bad timing, it is a **missing type system**. Five things fire on independent timers and the composition has exactly one relationship available to express — simultaneity — which it therefore expresses by accident. Sort every animated element into one of four classes with *different laws*:

| Class | What it is | On-screen duration | Entry/exit law | Duty budget | Period law |
|---|---|---|---|---|---|
| **TEXTURE** | continuous, transition-free (parallax bands, starfield, grass) | 100% | none — never appears or disappears | 100%, but see §1a | periods **coprime** to P and to each other; phase baked **per element** |
| **STATE** | a slow condition of the world or the creature (light level, weather, asleep/awake) | unbounded | a *posture/level* change over 2-6s, never a crossfade | ≤40% each; **≤2 concurrent, mutual-exclusion matrix enforced** | must divide P (the story returns) |
| **VISITOR** | an object that arrives and leaves | **≤10s, target 3-8s** | ≤0.3s transient, or motion, or occlusion — **never opacity** | ≤4% each, ≤15% aggregate | must divide P |
| **BEAT** | the creature's own reaction | 0.3-1.5s | begins 150-400ms after its cause; ends on baseline pose | ≤5% aggregate | slaved to a VISITOR/STATE, **never an independent oscillator** |

The rule that kills the 46% problem in one line: **the balloon is a VISITOR with a STATE's duration.** 57.6s per instance, twice per loop. `peek` at 24.0s is the same error. Duration is not the knob — *class* is, and duration follows from class.

### 1a. TEXTURE has one law and v5a breaks it: de-phase or it becomes one giant event

v5a's 91 stars carry **three** animations, `sA`/`sB`/`sC` at 60/30/10s, with **no per-element phase and no `animation-delay`** (verified: `animation-delay` appears 0 times in the file). So 46 stars pulse in perfect unison, then 30, then 15. The sky does not twinkle — **the whole sky swells every 10 seconds**, a full-field luminance transient far more salient than any 7-px meteor, on a period well inside the dwell window so the viewer *can* detect the metronome (they see 2-3 cycles).

This is a **regression** from the repo's own builder: `banner-build.py:227-250` gives each star its own `@keyframes` with a random baked phase `ph` via `hold_cycle(holds, ph)` and one of four periods `(7, 9, 11, 13)` — coprime, so the field never repeats. The mechanism to fix it already exists and is already lint-compatible.

> **Threshold (defensible):** any periodic ambient element with period < ⅓ of the median dwell (**< ~10s**) and N > 3 synchronized instances will be read as a beat. De-phase per element, or push the period above the dwell.

---

## 2. What makes a viewer perceive "caused" — mechanisms with windows

Causality is not narrated, it is *timed*. The windows are narrow and measured:

| Mechanism | Window | Source | Use in this scene |
|---|---|---|---|
| **Launching / contact causality** | effect must start **≤70ms** after contact; ~50ms is the discrimination threshold; >150-200ms reads as two independent events | Michotte, registered replication (Royal Society Open Sci. 2025); Hubbard 2004 | meteor→impact flash; visitor→balloon handover. At 24fps this is **≤2 frames**. |
| **Kinematic consistency (priority + velocity ratio)** | cause must move *first*, effect's direction must match cause's, velocity ratio within a narrow band | Michotte's three conditions | ejecta must fly *down-left along the meteor's vector*, not radially |
| **Gaze cueing** | attention orients at SOA **100-700ms**, peak **300-700ms**; reverses past ~300ms in some paradigms via IOR | Frontiers Psychol. 2017/2021; PLOS ONE 2016 | **the creature's head turn is the load-bearing device.** Fire it 150-400ms after the visitor's onset. |
| **Animacy from kinematics** | animacy ratings driven by *magnitude of speed change* + *angular magnitude of direction change*; observers report goal-direction toward off-screen targets | Tremoulet & Feldman 2000, *Perception* 29:943-951 | this is the *entire* recipe for "exit with agency": a speed change and/or a direction change ≥~30° immediately before leaving |
| **Motion-onset capture** | motion onset captures attention where abrupt onset/offset does not, when motion is task-relevant; peripheral cue→target 100/200ms | JOV; *Atten. Percept. Psychophys.* 2013 | the banner sits in parafovea while the reader reads text below → **motion, not opacity, is the only cue that reaches them** |
| **Gradual-change blindness** | sufficiently gradual changes are missed **69%** of the time *with no visual disruption at all* — worse than across a disruption (59%) | Simons, Franconeri & Reimer 2000, *Perception* 29:1143-1154 | v5a's fades are **4.8s** (2% of 240s). They are below threshold. **A slow crossfade is not an entrance; it is a change nobody will see happen.** |
| **Kuleshov / reaction-shot attribution** | meaning comes from the *juxtaposition*; a neutral face + a context is read as caused | Kuleshov; fMRI replication 2024 | the creature's reaction is what *makes* the cause legible — cheaper and stronger than making the event itself more elaborate |

### 2a. The finding the qualitative spec missed: both "events" move at scenery speed

Parallax layer speeds, computed from `@dF` (`translateX(-1960px)`) over each class's period:

| layer | period | speed (viewBox px/s) |
|---|---|---|
| `cf` far clouds | 240s | 8.2 |
| `cm` mid clouds | 120s | 16.3 |
| `gF` far ground | 120s | 16.3 |
| `gN` near ground | 60s | 32.7 |
| `grun` ground rule | 20s | 98.0 |

| "event" | measured speed | verdict |
|---|---|---|
| `balloon` (`@bo`: 1980,0 → −160,−60 over 120s) | **17.8 px/s**, vertical component 0.5 px/s | within **9%** of the mid-cloud / far-ground layer. It is *kinematically world-fixed* — the definition of scenery. |
| `shoot` (`@sh`: 0,0 → −660,310 over 7.2s) | **101 px/s** | within **3%** of `grun`. A meteor moving at ground-scroll speed. |

An object drifting at a parallax layer's rate **is** a piece of that layer, no matter what it depicts. The 46% duty made the balloon ambient; the velocity match made it *scenery* even at 4%.

> **Thresholds (defensible):** an event's peak speed ≥ **3×** the fastest parallax layer → **≥300 viewBox px/s** (≈140 CSS px/s at 900). A 729-px meteor path must complete in **≤2.2s, target 1.0-1.5s**. *Or* use the completely unoccupied channel: **all parallax is pure `translateX`, zero vertical component** — so any vertical motion ≥40 viewBox px instantly separates figure from ground, at any speed.

### 2b. Fade vs exit-with-agency

A fade is perceived as the *observer's* loss of information, not the object's action — the object does not *do* anything, it stops existing. Agency requires one of three, in preference order:

1. **Self-propelled acceleration** — speed change ≥2× within ≤0.5s, or direction change ≥30° (Tremoulet & Feldman's two significant factors), *then* exit through a boundary.
2. **Occlusion** — behind a mound, below the horizon, into a burrow. Preserves object permanence: "gone" without "ceased to exist". Cheapest correct exit available in this scene (the mounds already exist).
3. **Transformation** — it pops, it lands and becomes something persistent (the ember).

Opacity→0 is not on the list. If opacity must be used, it must complete in **≤0.3s** (a transient) and be accompanied by motion.

---

## 3. Duration and duty cycle — where the boundaries actually are

**Dwell model** (NN/g: users often leave in **10-20s**; still likely to leave through the next **20s**; the curve flattens at **~30s**; average visit "a little less than a minute"; survive 30s and 2min+ is common). Working survival: S(10)≈0.7, S(20)≈0.5, S(30)≈0.4, S(60)≈0.25, S(120)≈0.15.

Two regimes, two formulas:

- **t=0 anchored (this case):** P(a viewer sees the event that enters at time t) = **S(t)**. Duty cycle is nearly irrelevant; **entry time is everything.**
- **Random phase (fallback):** P(overlap) = **(d + D)/P**; P(witnessing an entry) = **min(1, n·D/P)**.

### The three boundaries, derived

| Read | Boundary | Derivation |
|---|---|---|
| **SCENERY** | per-instance on-screen duration > median dwell (**>30s**) — *or* speed within ±25% of any parallax layer — *or* per-type aggregate duty >35% | If the instance outlives the visit, the viewer **arrives mid-event**: it has no beginning for them, therefore no cause, therefore it is furniture. P(a 20s window contains the balloon's *entry*) = 20/120 = **17%**; P(it contains balloon *presence*) = **48%**. Presence dominates transitions ~3:1 → furniture. |
| **RARE AND SPECIAL** | per-instance **2.5-10s** (target **3-8s**); per-type duty **≤4%**; ≥1 instance entering before t≈45s | Upper bound: duration ≤ ⅓ median dwell so entry + middle + exit all fit inside one visit *with air either side* (contrast requires witnessed absence). Lower bound in §7. Genre check: Cookie Clicker's golden cookie — the canonical "rare special catchable event" — is **13s on screen with a 300-900s spawn interval = 1.4-4.3% duty**. |
| **MISSABLE** | entry at t > 45s (seen by ≤30%) or t > 120s (≤15%); under random phase, per-instance duty <1% (≤2.4s/240s → 9% chance) | v5a's `shoot` enters at **t=231.4s** → seen by ~0-5% of README readers. It is the only event the spec calls "genuinely rare" and it is functionally **absent from the product**. |

**Aggregate bands (defensible in direction, ±5pp is taste):** total VISITOR duty **12-25%**; union event coverage **20-35%** of P; **≥65% of the loop must be empty air**, because "special" is a contrast effect and there is nothing to contrast against otherwise.

**Measured v5a:** aggregate duty **88.1%** (211.4s of 240s), union coverage **64.8%**, time with ≥2 concurrent events **40.7s**, with ≥3 **11.6s**, with **4 concurrent: 3.6s**.

---

## 4. Distribution across P — clustering, spacing, overlap

**Overlap: never between independent events; always inside a causal chain.** This is not taste. The attribution machinery binds whatever co-occurs, so two independent overlapping events produce either false causality or incoherence. v5a produces the pathological case:

```
t=148.8-175.2  sleep      ⎫
t=150.4-158.4  spin       ⎬ 8.0s where the creature is simultaneously
t=154.8-162.0  cheer      ⎭ ASLEEP, CHEERING, and FACING BACKWARD
t=122.4-180.0  balloon    …while a balloon that means nothing drifts past
```

Permitted overlaps, exhaustively: (a) the **reaction window** — a BEAT overlapping its cause by 0.15-1.5s; (b) a **chain hand-off** — A's exit overlapping B's entry by ≤1.5s where B is caused by A; (c) a **persistent token** (the ember) which is a STATE, not an event.

**Spacing: neither even nor random — decaying, because the audience decays.**
- Even spacing maximises P(witness) for a given n, but a strict metronome with gap < dwell is detectable (the viewer samples 2-3 gaps). Jitter gaps **±30-40%**: two samples differing by >30% cannot support a rhythm estimate.
- Under t=0 anchoring, expected events-seen-per-viewer is maximised by front-loading. Balanced against "don't open frantically" and "reward the lingerer":

| block | events | mean gap | rationale |
|---|---|---|---|
| t = 0-30s | **2** | 12-16s | ~50-60% of readers live here. Both identity-carrying events must land inside this block. |
| t = 30-60s | **2** | 15-20s | ~30-40% reach here |
| t = 60-120s | **2** | 25-35s | ~20% |
| t = 120-240s | **2-3** | 40-50s | the lingerer and the operator; the day-arc's payoff; cheap variants acceptable |

**Total 8-9 VISITOR/BEAT events per 240s.** Hard caps: **max gap ≤20s before t=60**, **≤45s after**. Measured v5a max gap: **50.4s (t=180→230.4)** — 21% of the loop is a dead zone, and it sits exactly where the day-arc's climax should be.

**Repetition and the memory window.** Because D ≪ P, an event recurring at ≥2× median dwell is effectively never seen twice. Therefore: (i) **no event type may recur with a gap <60s** — the ~25% who stay a minute see the repeat and the world stops feeling alive (v5a: `spin` recurs every 80s, `balloon` gap 62.4s — both marginal); (ii) **variety is cheap to skip** — do not author 12 unique events when 5 types with jittered variants are indistinguishable to 95% of viewers; (iii) spend the entire art budget on the two events before t=30s.

---

## 5. The loop as a day, not a reset

A cycle reads as a *day* rather than a *reset* when four things hold:

1. **One global slow variable, single-cycle over P, smooth at the wrap** (light level / colour temperature / shadow direction). A sinusoid over 240s is seamless by construction and changes at ~0.4%/s — *below the change-detection threshold*. This is **gradual-change blindness used as a feature**: the viewer never sees the sky change and always notices it has changed. The same mechanism that makes a 4.8s event-fade invisible (a bug) makes a 240s light arc feel like time passing (a feature).
   *v5a has no such variable.* `@mn` pulses the moon 0.78→0.97→0.78 on an **80s** period — 3 unrelated pulses per loop — and `rSleep` sits on 240s. Nothing is slaved to anything.
2. **Events keyed to phases of that variable**, so each event inherits its cause from world state: "the world became night, *therefore* the fireflies." This is the only way to get causality without contact, and it is what Chrome Dino does with one integer — `INVERT_DISTANCE: 700` flips day↔night, `INVERT_FADE_DURATION: 12000` (12s) crossfades it, and `PTERODACTYL.minSpeed: 8.5` gates the rare obstacle behind world state rather than a timer (`t-rex-runner/index.js:115-125, 1503-1505`). Genre scale for a full day: Minecraft **20 min**, Terraria **24 min** (15 day / 9 night), Stardew **~14 min**. A 4-minute day is 3-6× fast; acceptable for decoration only because the light change stays sub-threshold.
3. **The last beat sets up the first.** The narrative return must be a *causal* wrap: the spec's construction — the next cycle's streak is what wakes the sleeping creature — is correct, and under t=0 anchoring it also puts the prime mover exactly where every viewer arrives. The chain therefore *must* be re-laid-out: star at t≈3s, sleep at t≈150-200s. In v5a the order is inverted (sleep at 148.8, star at 231.4).
4. **The wrap sits at the loop's least-informative moment.** A reset is only detectable if the viewer was tracking something. v5a places its single most memorable beat (the meteor, ending 238.8s) **1.2s before the wrap** — the worst possible placement. Put the climax at **55-75% of P** and reserve the last **12-15% of P** for settling.

**The wrap has a second job that agrees with the first.** `@media (prefers-reduced-motion: reduce)` sets `*{animation:none!important}`, so the reduced-motion still renders **every animation's 0% value**. Therefore: **the joint 0% state of every animation must compose a publishable photograph** — and it must be calm, which is exactly what requirement 4 wants. One constraint, two payoffs. (v5a satisfies the mechanical part: every event is `opacity:0` at 0%.)

Conflict to resolve explicitly: t=0 is *also* the first impression, which wants to be arresting. Resolution — **t=0 is the calm-before, and the first event's onset is at t≈2.5-4s**: the still stays composed and the live viewer gets their first beat inside 4 seconds.

---

## 6. Period assignment — the fix for "independent timers"

The root cause of both the pile-up and the "reads as random" complaint is that **phase is expressed as a percentage of each event's own period**, and the periods differ (240 / 120 / 80). `29%` of 120s and `29%` of 240s are different absolute times, so nothing can be scheduled *relative to anything else*. The builder's own R-rule forbids the obvious fix — `banner-build.py:31-34`: phase must live in keyframe percentages because `banner-shots.sh` overrides `animation-delay` on `*` to seek a timestamp, and `--lint` fails the delay form.

**The compatible fix: every STATE/VISITOR/BEAT track gets `dur: 240s`. Multiple occurrences become multiple pulses inside one 240s keyframe list.** Percentages then *are* absolute seconds (1% = 2.4s), the whole loop becomes one readable score, `hold_cycle()` already rotates pulses inside a period, and the shots-seek freeze still works. This converts five independent timers into a composition.

**Then split the period space deliberately:**

- **STORY** (STATE, VISITOR, BEAT, global light) → **period exactly P**. The ensemble returns; the story closes.
- **TEXTURE** (starfield, twinkles, grass rustle) → **periods coprime to P and to each other** (`7, 9, 11, 13`, per `banner-build.py:236`), **per-element baked phase**. LCM is astronomical → the texture never visibly repeats and cannot form a beat.

You cannot get both properties from one period assignment. Assigning by *class* gets both.

---

## 7. The anticipation/resolution pair — minimum cue, minimum payoff

**Minimum cue** (cheapest first — the first is free and the strongest available here):

1. **Arrest an established rhythm.** The walk cycle is `0.5s steps(1,end)` — a perfect metronome (and a textbook 12-frame-per-step walk at 24fps). **Halting it for 0.6-1.2s is a 100%-reliable transient requiring zero new artwork**, because rhythm violation is itself a transient. Nothing else in the scene is this cheap.
2. **A directional gaze.** Works with a schematic/pixel face, orients attention at 100-700ms SOA. → head/ear turn toward the region the thing will enter, **300-700ms before it does**.
3. **A herald that precedes its object**: a shadow crossing the ground, a mound's shadow deepening, a glow growing. Lead time **1-3s**; beyond ~6s the link is lost unless the cue *persists* (grows, brightens) — persistence is what buys longer leads.
4. **Anticipation on the creature's own action**: 250-500ms (6-12 frames @24fps) for a small action, up to 1s for a large one; ≈⅓ of the action's duration, minimum ~100ms (Disney's anticipation/timing pair; the juice literature's floor).

**Minimum payoff** — derived from the oculomotor budget:

```
saccade latency ~200ms  +  flight 30-50ms  +  fixation/identify ~200-300ms
                    ≈ 400-500ms before the eye is on target
```

Therefore: **transient at t₀, payoff at t₀+0.5s to t₀+2.0s. Never put the payoff at t₀.** A 0.3s meteor whose whole existence *is* the transient cannot be seen — the eye arrives after it is gone. (This is why Animal Crossing pairs its shooting stars with an audio herald and sends them in pairs — a second chance for an eye that arrived late.)

**Minimum viable full-grammar event:**

```
0.15-0.30s  entry transient (motion onset, ≥300 px/s or vertical)
0.20-0.40s  eye-arrival slack — nothing important happens here
1.0 -2.0s   the one legible state change (the payoff)
0.3 -0.5s   exit: speed change ≥2× or direction change ≥30°
0.2 -0.5s   through an edge or an occluder
────────────
≈2.5s floor · 4-8s comfortable · 10s ceiling
```

Plus, in parallel: **BEAT** — the creature's reaction beginning **150-400ms** after the event's salient onset, directional, returning to baseline with 300-800ms of follow-through.

### 7a. The baseline motion budget — the reason no event can read as special

Reactions only read as reactions against stillness. v5a's baseline:

| baseline motion | period | instances per 240s |
|---|---|---|
| `hop` (a full 26px jump + 9px secondary bounce) | 4s | **60** |
| `look` (head −20px then +20px) | 8s | **30** |
| `ears` | 2s | **120** |
| `blink` | 4s | 60 |
| synchronized sky swell (`sC`, 15 stars) | 10s | 24 |

The creature hops 60 times and turns its head 30 times per loop. **The single strongest causal device available — a directional gaze — is spent on a free-running 8s oscillator that cannot correlate with events on 240/120/80s periods except by accident.** And a creature that is always doing something can never be seen to *react*.

> **Rule:** BEAT-class motion (gaze, gesture, posture) is **never** an independent oscillator. Budget: **≤1 spontaneous creature motion per 20s** outside a caused BEAT (12 per loop, not 270). `blink` and `ears` may stay as TEXTURE if de-phased and small; `look` and `hop` must become BEATs with causes.

---

## 8. THE CHECKLIST — hold a candidate event against these, in order

**Gate 0 — class.** Name the class: TEXTURE / STATE / VISITOR / BEAT. If it doesn't fit one, it isn't designed yet. *If you cannot name the class, stop.*

**Gate 1 — placement (t=0-anchored; strongest filter, apply first).**
1. Does at least one instance enter before **t=45s**? (t>45s ⇒ ≤30% of readers; t>120s ⇒ ≤15%.)
2. If this event carries the piece's *identity*, does it enter before **t=30s**? Identity content after t=40s is not shipped.
3. Is t=0 to t≈2.5s free of it, so the reduced-motion still stays calm?

**Gate 2 — duration (VISITOR).**
4. On-screen per instance in **[2.5s, 10s]**? (target 3-8s) — >30s ⇒ SCENERY by construction; <2.5s ⇒ unseeable.
5. Per-type duty ≤**4%**? Aggregate VISITOR duty ≤**15%**? Total event duty ≤**25%**? Union coverage ≤**35%**?

**Gate 3 — kinematic figure/ground.**
6. Peak speed ≥**3×** the fastest parallax layer (**≥300 viewBox px/s**) **or** a vertical component ≥**40 viewBox px**? Speed within ±25% of any layer ⇒ it *is* that layer.
7. Salient travel ≥**40 viewBox px** (survives 0.19× mobile ⇒ ≥7.6 CSS px) and key silhouette ≥**50 viewBox px** in its largest dimension (identifiable at mobile scale)?

**Gate 4 — cause.**
8. Name the cause in one clause. "A timer fired" fails. Legal causes: another event's product, a STATE threshold crossing, the creature's own action, or **exactly one** designated uncaused prime mover per loop.
9. Is the cause **on screen** (spatial contiguity) and does it move **first** (Michotte's priority)?
10. Contact-type causality: effect within **≤70ms** (≤2 frames @24fps)? Reaction-type: **150-400ms**? Herald→arrival: **1-3s** (≤6s only if the herald persists/grows)?
11. Is there a cue at all? Cheapest sufficient cue = **halt the walk cycle for 0.6-1.2s**.

**Gate 5 — behaviour (the middle).**
12. Exactly **one** legible state change while present, occupying **1.0-2.0s**, starting **0.5-2.0s after** the entry transient (never at it)?
13. Nameable in three words by someone who hasn't read the spec? (v5a's cheer fails: it reads as "horns" — `clawd-sprite.py` measured the cliff at rise −3.)
14. Does the creature's BEAT respond, directionally, within 150-400ms?

**Gate 6 — exit.**
15. Contains a **speed change ≥2×** or a **direction change ≥30°** in the final 0.5s (Tremoulet & Feldman's animacy factors)?
16. Leaves through an **edge**, an **occluder**, or a **transformation**? *If the exit is an opacity fade, it fails.*
17. If opacity is used at all, does it complete in **≤0.3s**? (A 4.8s fade is missed 69% of the time — v5a's fades are 4.8s.)
18. Symmetric with the entry where the fiction implies it (out of a mound ⇒ back into *the same* mound)?

**Gate 7 — composition.**
19. Does it overlap any other event? Legal only as (a) a BEAT reacting to its cause, (b) a ≤1.5s chain hand-off, (c) a persistent STATE token. **Independent overlap fails.**
20. Does it violate the **mutual-exclusion matrix**? (asleep ⊥ cheering ⊥ walking ⊥ facing-backward.)
21. Gap to the nearest neighbouring entry: ≥**8s** (air), ≤**20s** before t=60, ≤**45s** after?
22. Recurrence gap ≥**60s** for the same type?
23. Wordmark keep-out respected — including any strokes/lines, not just the sprite?

**Gate 8 — mechanism.**
24. Is its animation `dur: 240s` with phase in **keyframe percentages** (1% = 2.4s), never `animation-delay`? (`banner-build.py:31-34`; `--lint` fails the delay form.)
25. Does its 0% value participate in a publishable still?
26. Does it pass in **both** colour schemes? (`.sh{opacity:.20}` + hidden starfield in light mode ⇒ the prime mover is nearly invisible for daylight readers — an event that only works at night cannot be load-bearing.)
27. TEXTURE only: period coprime to P, phase baked per element, no synchronized cohort >3?

---

## 9. A worked schedule (numbers consistent with §1-8; the *fiction* is taste, the *timings* are not)

Uses the spec's chain, re-laid-out for t=0 anchoring. 9 events, aggregate VISITOR duty **10.4%**, union coverage **~19%**, max gap before t=60 = 12.5s, max gap after = 42s, zero independent overlap.

| t (s) | beat | class | dur | mechanism notes |
|---|---|---|---|---|
| 0.0 | at-rest tableau: creature mid-stride, empty sky | — | — | = the reduced-motion still; every animation at 0% |
| 2.5 | **herald**: walk-cycle halts, ears perk, head lifts up-right | BEAT | 0.8 | free transient; 0.8s lead ⇒ inside the 1-3s herald window |
| 3.3 | **streak** enters top-right, 729px path, 40° down-left | VISITOR | **1.3** | **560 px/s** = 5.7× `grun` ✓ |
| 4.6 | **impact**: 0.15s flash + 2 ejecta along the meteor vector | — | 0.5 | effect at **+60ms** ⇒ contact causality ✓ |
| 4.8 | creature flinch, then resumes stride with 0.5s settle | BEAT | 0.7 | reaction at **+200ms** ✓ |
| 5.1→ | **ember** persists: 1px warm pulse, period 11s (coprime) | STATE | — | the chain's memory; the only warm mark |
| 17.6 | mound shadow deepens (herald) → **visitor** walks out | VISITOR | **7.5** | translation exit/entry; occluder = the mound |
| 20.1 | creature notices: stride halts, head turns to visitor | BEAT | 0.6 | **+250ms** after the visitor clears the mound ✓ |
| 21.0 | **cheer**: 0.35s anticipation crouch → 0.5s whole-body hop with tilt → 0.4s settle | BEAT | 1.25 | anticipation ≈⅓ of action ✓; silhouette *changes shape*, does not sprout |
| 23.5 | visitor sets the balloon by the ember (its one errand) | — | 2.0 | payoff at +5.9s of a 7.5s visit |
| 27.0 | visitor retreats behind **the same** mound | — | 2.1 | symmetric ⇒ intent |
| 39.5 | **balloon release**: tugs, accelerates 0→250 px/s upward, exits top edge | VISITOR | **3.5** | vertical channel, unoccupied by parallax ✓; acceleration ⇒ agency ✓ |
| 58 | ambient A (counter-flow bird/seed, right-to-left at 340 px/s) | VISITOR | 3.0 | keeps the ≤20s pre-t=60 gap |
| 96 | ambient B (different silhouette) | VISITOR | 4.0 | |
| 138 | light has dimmed (global sinusoid at ~58% of arc): creature slows, 0.8s sit anticipation, posture drops, breathing 1px, stride **absent**, `Zzz` | STATE | ~55 | STATE ⇒ long duration is legal; posture change, not a badge |
| 168-238 | quiet: only TEXTURE + the ember + the light arc | — | — | last 13% of P = settling ⇒ the wrap is uninformative ⇒ no reset detectable |
| (P wrap) | next cycle's streak at t=3.3 wakes it | — | — | the opener is the closer; t=P is the narrative return |

Climax (the streak/impact) sits at **1.4% of P** rather than 55-75% — the one place this schedule *knowingly* violates §5.4, because t=0 anchoring dominates: a climax nobody sees is not a climax. The §5.4 rule survives in its operative half — **the wrap is calm** — which is what actually prevents the reset read.

---

## 10. Make it a lint, not a doctrine

Per this repo's own lesson — a rule enforced only by its own suite is detection, not a gate — extend `banner-build.py --lint` to parse the `<style>` block, expand every keyframe list to absolute seconds on the 240s master, and assert:

| # | assertion | current v5a |
|---|---|---|
| L1 | every STORY-class period divides P | ✓ (240/120/80/60) |
| L2 | no two VISITORs overlap | **FAIL** — 40.7s of ≥2 concurrency |
| L3 | no two mutually-exclusive STATEs overlap | **FAIL** — asleep+cheer+backward for 8.0s |
| L4 | every VISITOR entry has a BEAT within 150-400ms | **FAIL** — 0 of 5 |
| L5 | per-instance VISITOR duration ≤10s | **FAIL** — balloon 57.6s, peek 24.0s, sleep 26.4s (mis-classed) |
| L6 | aggregate event duty ≤25%, union coverage ≤35% | **FAIL** — 88.1% / 64.8% |
| L7 | max entry gap ≤20s (t<60) / ≤45s (t≥60) | **FAIL** — 50.4s gap at t=180 |
| L8 | no VISITOR opacity ramp >0.3s | **FAIL** — all ramps 1.2-4.8s |
| L9 | peak speed ≥3× fastest parallax, or vertical ≥40px | **FAIL** — balloon 1.09×, shoot 1.03× |
| L10 | ≥1 event entry before t=45s; identity event before t=30s | **FAIL** — first true event at t=34.8 |
| L11 | no TEXTURE cohort >3 elements sharing a phase | **FAIL** — cohorts of 46 / 30 / 15 |
| L12 | joint 0% state renders a legible still | ✓ |
| L13 | every assertion also evaluated under `prefers-color-scheme: light` | untested |

---

## 11. Defensible vs taste

**Defensible (mechanism or measurement backs the number):** the ≤70ms contact window; the 150-400ms reaction window; 100-700ms gaze SOA; ≤0.3s appearance transients and the 69% gradual-change miss rate; the 400-500ms eye-arrival budget and hence the 0.5-2.0s payoff offset; ≥3× parallax speed and the "vertical is unoccupied" observation (both computed from this file); ≥40px travel / ≥50px silhouette from the 0.469×/0.19× display scales; the ≤10s VISITOR ceiling from duration-vs-dwell; the t=0 anchoring consequence for placement; the class taxonomy and mutual exclusion; de-phasing TEXTURE; period-by-class.

**Taste (defensible in *direction*, arbitrary in magnitude):** 8-9 events per 240s (could be 6, could be 12); the 2/2/2/3 front-loading split; the specific 12-25% duty band and 65% empty-air floor; 240s as the day length (genre says 14-24 min; 4 min is a decoration-scale choice); ±30-40% gap jitter; the ≥60s recurrence floor; the climax at 55-75% of P.

**Pure taste (fiction, not grammar):** the star→ember→visitor→cheer→sleep chain; whether the balloon survives as the visitor's property or is cut; the "clawd is a session, the sky is the work" conceit; a day-cycle at all rather than weather or seasons.

---

## 12. Blockers and uncertainties, named

1. **t=0 anchoring is load-bearing and unverified in GitHub's actual pipeline.** If the hero `<img>` is lazy-loaded or re-encoded, placement reverts to random phase and §5's front-loading is wrong (the §1-4 and §7 thresholds are unaffected). One 2-minute scratch-gist test settles it. **Do this before scheduling anything.**
2. **Dwell figures are general-web (NN/g), not GitHub-README-specific.** README readers plausibly dwell longer and scroll past faster. The *ordering* of the thresholds is robust to ±2× on D; the specific 45s/120s cut-points are not.
3. **Overlap with existing work:** `docs/plans/BANNER_NARRATIVE_SPEC.md` (branch `docs/banner-narrative-spec`, commits `79cb8bee`, `56e21dd2`) already contains the qualitative cause/behaviour/exit ruling, the 46% measurement, and the causal chain. Everything above is additive — the numeric grammar, the class taxonomy, the kinematic-camouflage finding, the baseline-motion-budget finding, the synchronized-starfield regression, the t=0 placement inversion, and the lint. **Two places where I contradict it:** (a) it says "the shooting star is the prime mover that both opens and closes the cycle" while placing nothing at the loop's head — under t=0 anchoring the star must physically sit at t≈3s; (b) it never addresses `.look` (8s) and `.hop` (4s), which are the largest single obstacle to any event reading as caused.
4. **Untested cost:** the spec's `feTurbulence` grain + stacked bloom over a full-width rect is the one genuinely expensive item, and it interacts with 91 star elements. Not measured here.
5. **Light-mode parity is unmeasured against these thresholds.** With the starfield hidden and `.sh{opacity:.20}`, the daylight scene may fail L9/L10 even after the dark scene passes. Gate 8.26 exists for this reason.

---

**Sources:** [Michotte replication (R. Soc. Open Sci. 2025)](https://royalsocietypublishing.org/rsos/article/12/9/250244/235317/Michotte-s-research-on-perceptual-impressions-of) · [Hubbard, perception of causality](http://timothyhubbard.net/hubbard_FD2004.pdf) · [Space and time in perceptual causality (Frontiers 2010)](https://www.frontiersin.org/articles/10.3389/fnhum.2010.00028/full) · [Tremoulet & Feldman 2000, animacy from a single object](http://wexler.free.fr/library/files/tremoulet%20(2000)%20perception%20of%20animacy%20from%20the%20motion%20of%20a%20single%20object.pdf) · [Simons, Franconeri & Reimer 2000, change blindness without disruption](http://wexler.free.fr/library/files/simons%20(2000)%20change%20blindness%20in%20the%20absence%20of%20a%20visual%20disruption.pdf) · [Gaze-cueing time course (Frontiers 2017)](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2017.02343/full) · [Gaze cueing and task demands (Frontiers 2021)](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2021.618606/full) · [Attentional capture by motion onset/offset (JOV)](https://jov.arvojournals.org/article.aspx?articleid=2191962) · [Flicker and abrupt displacement in motion-onset capture](https://link.springer.com/article/10.3758/s13414-013-0587-x) · [Kuleshov effect fMRI replication](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC11299807/) · [NN/g, How long do users stay on web pages](https://www.nngroup.com/articles/how-long-do-users-stay-on-web-pages/) · [t-rex-runner source](https://github.com/wayou/t-rex-runner) · [Cookie Clicker golden cookie](https://cookieclicker.wiki.gg/wiki/Golden_Cookie) · [ACNH balloon spawn rate](https://www.nintendolife.com/guides/animal-crossing-new-horizons-balloons-spawn-rate-hunting-colour-guide) · [Minecraft day length](https://www.namehero.com/gaming-blog/how-long-is-a-minecraft-day-the-ultimate-guide/) · [Terraria day/night cycle](https://terraria.wiki.gg/wiki/Day_and_night_cycle) · [Stardew day cycle](https://stardewvalleywiki.com/Day_Cycle) · [After Dark — deliberate randomisation, "never put the toasters on a track"](https://lowendmac.com/2007/aggressively-stupid-the-story-behind-after-dark/) · [Juice it or lose it (Jonasson & Purho)](https://www.youtube.com/watch?v=Fy0aCDmgnxg) · [Disney's 12 principles](https://www.adobe.com/creativecloud/animation/discover/principles-of-animation.html) · [SMIL/CSS in SVG-as-img](https://css-tricks.com/guide-svg-animations-smil/) · [CSS-in-SVG required for GitHub README animation](https://blog.eamonncottrell.com/animate-svgs-for-github-readmes)