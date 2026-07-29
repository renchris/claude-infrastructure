# Hero-banner event set — independent design

## 0 · Disk-verified ground truth (my numbers below are built on these, not on the brief's prose)

| Fact | Value | Source |
|---|---|---|
| Canvas / master period | `viewBox 0 0 1920 600`, P=240 s | `assets/banner/v5a-long-walk.svg:1` |
| Ground rule | `y=506`, `dasharray 3 9` (12 px pitch), `#6f7b8a` @.7, **static — does not scroll** | v5a `line.rl` |
| Type block (real, not the keep-out) | wordmark `x=960 y=158 size=62` ⇒ ≈(559,112)–(1361,158); subtitle `y=194 size=19 ls=6` ⇒ ≈(760,181)–(1160,194) | v5a `text.wm`, `text.sub` |
| Creature | `translate(852 391) scale(.72)`, sprite 220×160 ⇒ occupies **x 852–1010, y 391–506**; **cell = 14.4 px** (floor is 12); footfall x ≈ **888** | v5a, `docs/plans/README_HERO_BANNER.md` §v5 S6 |
| Existing scroll rates | `.gN` 1960px/60s = **32.7 px/s**, `.gF` 16.3, `.cm` 16.3, `.cf` 8.2 | v5a `@keyframes dF` |
| Reduced motion | `*{animation:none!important}` + **explicit `opacity:0` for every rare item** | v5a `@media` block |

**Two defects in the v5a reference that shape my design** (neither is in the doc's settled-findings list):

1. **The sprite is bilaterally symmetric, so `rSpin` (turn-around) is a visual no-op.** Ears `x=0/200`, eyes `x=40/160`, body `x=20 w=180` — all mirror about x=110; and `legA{20,140}` maps under `scaleX(-1)` exactly onto `legB{60,180}`. A horizontal flip is therefore *a half-stride phase hiccup plus an inverted gaze*, nothing more. "Turn around" is unavailable as a beat without new art. This is why my human-facing event is a **cessation**, not a turn.
2. **Stride and scroll are not locked.** 32.7 px/s ÷ 2 strides/s = 16.3 px per stride = 1.13 cells, while the legs are 2 cells apart. The creature is sliding. Every event below depends on fixing this, and fixing it is what buys the design its best detail.

---

## 1 · The governing rule (why constraint 1 costs nothing)

**A session is never co-present with its peers.** Peers are in other panes, other worktrees, other accounts. Co-presence is not merely *risky under constraint 1* — it is the wrong picture of the system. So: **peers are always off-canvas; their existence arrives as world state.** Mail arrives as a file, not a keystroke. A predecessor arrives as a record. Constraint 1 is then free, not endured — every event below has exactly one creature in frame because the repo has exactly one session per pane.

**Second rule, doing constraint 2 structurally:** the type block lives at y 112–194; the ground at y 506. **All events are terrestrial or on-creature.** The sky stays purely ambient (clouds, moon, stars). Nothing can cross the wordmark because nothing is ever authored above y=340. This also means **no event depends on stars** — which is the same reason a shooting star is disqualified rather than merely tired (constraint 4: it does not exist by day).

**Third rule — the design's spine.** The scroll rate *is* the session's throughput, and it is the banner's only gauge. Three of five events are readings of it:

| Reading | Means | Event |
|---|---|---|
| nominal | working | ambient |
| **negative** | a turn was returned | THE REFUSAL |
| **zero** | blocked on a human | THE ASK |

Events share one vocabulary instead of each inventing its own. That is the direct answer to *"volume destroyed the significance of each piece"* — significance comes from a shared scale, not from novelty per beat.

---

## 2 · The ambient layer (not events — no cause, no exit)

**Recommendation: the ambient layer is involuntary motion only.** Blink 4 s · ear-flick 2 s · gaze 8 s · stride 0.5 s. **Cut the 4 s hop** (v5 S9 lists it): a hop is *voluntary*, so it implies a cause it does not have — 60 unmotivated hops per loop is precisely the noise the operator objected to. Line: **involuntary → texture; voluntary → must be an event with a mapping, or cut.**

**The trail is ambient, and it is the whole thesis.** Bake a footprint into the scrolling strip at **exactly one stride pitch**, for the entire strip. Then:

- Print pitch = 2 cells = **28.8 px**; rate = 28.8 px ÷ 0.5 s = **57.6 px/s** (1.76× v5a's, still a walk).
- The creature's foot lands in an existing print **every stride, by construction** — no second animation, no phase trickery.
- Read: *the record is continuous and the walker is not.* You cannot tell where one session's prints end and the next's begin. **That is "SESSIONS RUN EACH OTHER" rendered as the ground itself**, with no second creature and nothing joining anything. It also makes README property 4 ("nothing a session did dies with it") a *permanent state* rather than a 4-second event — which is what a property is.
- Invariant to assert at build: `strip_length = 28.8 × (strides_taken − strides_spent_in_place)`; **480 strides per 240 s**, minus the two events that spend strides without gaining ground (below) ⇒ **strip = 28.8 × 466 = 13,420.8 px**. Divisible by the 12 px dash pitch (13,420.8/12 = 1118.4 — so set the dash to 9.6 px pitch, or the strip to 13,478.4; pick in the build so *both* divide exactly).
- Legibility risk, named: one print = 14.4 px authored = **6.75 px at the README's 900 px width**. Must be one full cell, and needs per-scheme alpha (≈.38 on the dark plate, ≈.55 on `#f6f8fa`) — one line in the existing `@media (prefers-color-scheme: light)` block. **Verify at 900 px, not at 1920.**

---

## 3 · The five events

I argue for **five, and the count is derived, not chosen**: the README makes exactly five claims (its own five badges/rows). Four of them get one event each; the fifth (property 4, permanence) is deliberately *not* an event because permanence is a state — it is the trail. The vacated slot goes to the one thing a header may address that the system does not claim about itself: **the reader**. So: 4 claims + 1 reader = 5. A sixth event would have to invent a claim the README does not make. Every event owns a property no other event owns — that is the test, and it is checkable.

---

### E1 · THE OVERLAP — *property 1, sessions run each other*

**Honest mapping.** `handoff-fire.sh self-close --successor <uuid>` refuses to retire the predecessor until the successor is **verified engaged** — resolvable, `claude` on its tty, *and* a real assistant turn in its transcript (README §1). Succession therefore **overlaps rather than touches**: for a moment both sessions exist. The mail cursor is dup-biased for the same reason (`.acked` only at the Stop after a turn provably carried the mail). The event is a *density* in the record, which is what the mechanism literally produces — not a relationship between two figures.

- **CAUSE** — the strip scrolls in a stretch where the print pitch is **halved** (prints at 14.4 px for ~12 prints ≈ 173 px). You see it coming for 17.9 s: two walkers' worth of record approaching.
- **BEHAVIOUR** — 3.0 s. The creature's footfall now lands on every *second* print. The pitch is wrong for one walker and that mismatch is the tell. Its gaze parks down (the 8 s `look` cycle is *phase-aligned* so its down-beat coincides — keyframe percentages, never `animation-delay`).
- **EXIT** — the pitch halves back to one-per-stride and the foot **re-registers exactly**. The overlap resolved; one walker continues. Exit by resolution, with the creature's own footfall as the resolving act.
- **Position** — interaction t=34 s; on canvas 16.1–52.4 s.
- **Day scheme** — identical. Pure ground geometry; alpha re-tuned per scheme.
- **Constraint 1** — the second party exists only as a doubling in the record. There is no node to connect to.

### E2 · THE REFUSAL — *property 3, autonomy is bounded*

**Honest mapping.** `completion-assert.sh` is a `Stop` hook that **refuses a false "done"** against the live git and gate ledger; the README's own guardrail diagram draws it as an arrow *back*: `Stop -->|"the live git ledger disagrees"| M`. This is the single most literal mapping available in the repo: the animation of an arrow that points backward is the world moving backward.

- **CAUSE** — a low post (40 px, 3 cells tall, a bar in its head) reaches the creature. The creature **stops striding and settles one cell** — it is trying to end the turn. Cause is the creature's own attempt, not the scenery.
- **BEHAVIOUR** — 5.5 s total: 1.5 s settled (ears and blink keep going, clouds keep drifting — so it reads as *held*, never as a stalled file) → 0.5 s the post's bar **drops across** (shape first, colour second, so it survives both schemes) → **the world scrolls back exactly one print pitch over one 0.5 s stride** → 3 s of walking on, unopposed, and it passes the post.
- The world's back-step means **the creature steps into the same print twice.** A returned turn *is* redoing a step. This is the design's best detail and it is free.
- **EXIT** — it passes the post on the second attempt, and the post scrolls out behind it. Agency in both directions: refused, then allowed.
- **Position** — interaction t=84–89.5 s; on canvas 66.1–105.6 s.
- **Day scheme** — identical; the bar is geometry.
- **Constraint 1** — one creature; the refuser is a fixture, not a peer.

### E3 · THE LANE — *property 2, parallel work cannot collide*

**Honest mapping.** Every writer gets its **own worktree**, handed out warm in ~3 s; landing rejoins trunk through one machine-wide lock (README §2). The ground the creature walks *is* the trunk, so a fork in the ground is not a diagram of isolation — it is isolation.

- **CAUSE** — the ground rule splits ahead: trunk continues at y=506, a branch rises 3 cells to y≈463. It arrives **already drawn** (the worktree is warm, not built on demand).
- **BEHAVIOUR** — 13 s: 2 s step up (a nested `lift` group on the creature carrying one 240 s translateY, keyframe-aligned to the strip — S8 preserved) · 6.9 s walking the branch, silhouette raised and clearly off-trunk · 2 s step down at the merge. Top of creature reaches y≈348 worst-case with ears — **154 px clear of the subtitle**.
- **EXIT** — it steps back down onto trunk at the merge and the fork scrolls out. It landed.
- **Position** — interaction t≈138 s (the loop's far point — deliberately: the creature is off-trunk at the moment furthest from the seam); on canvas 120.1–165.7 s.
- **Day scheme** — identical.
- **Constraint 1** — the fork is terrain. There is no second creature, so there is nothing for a line to join. *(This is the event closest to infographic drift — see §6.)*

### E4 · THE ADVANCE — *property 5, the whole system deploys from git*

**Honest mapping.** The live `~/.claude` layer only ever advances to the background verifier's green stamp (`deploy-live.sh` on a launchd tick), and row 5's guarantee is *"an update that can't break a running session."* **A good deploy's signature is that nothing afterward is different.** That is the event's payload — and it is why this event is the one whose success looks like nothing.

- **CAUSE** — a launchd tick: a one-cell-wide vertical column enters from the right on its own group at **4× scroll (230 px/s)**, crossing in 8.3 s. Its off-canvas start must be a **presentation attribute**, not only a `0%` keyframe, or reduced-motion renders it mid-frame (this is the exact failure class the v5 log records twice).
- **BEHAVIOUR** — ~3 s salient. As the column passes each ground dot, that dot **re-seats** (drops 1 px, returns). The creature's ears flick and its eyes track the column right-to-left. **Its stride does not break** — deliberately, and that is the whole meaning.
- **EXIT** — it exits left having converted every dot it passed. Exit by *completion of its sweep*, not dissipation. (Weakest exit in the set — see §6.)
- **Position** — reaches the creature t=188 s; on canvas 183.5–191.9 s.
- **Day scheme** — identical (ground dots + an ear flick). Critically, **the payload is not in the starfield**, which is why it works where a shooting star cannot.
- **Constraint 1** — no second figure at all.

### E5 · THE ASK — *the reader*

**Honest mapping.** The system pages you **only when a human must decide**: `operator-readout.sh` renders `▶ <exact command>` at every turn close, `cc-blockers` is the board of everything blocking on you, `cc-decide` writes decision packets that survive a recycle, and the global protocol's STOP-ASK overrides auto-continue. This is the most operator-visible mechanism in the repo, and a header should have exactly one event whose subject is the person reading it.

- **CAUSE** — nothing arrives. It reaches an unmarked point in the walk and **stops**: legs halt, world halts (rate = 0), ears prick and hold up, the 8 s gaze cycle parks centred.
- **BEHAVIOUR** — 6.0 s (an exact multiple of the 0.5 s stride — see §5). It is still and looking straight out. Clouds keep drifting and it keeps blinking, so it is unmistakably *waiting*, not frozen. **In a loop made of motion, the only cessation is the most salient thing in it.** No new art: the sprite already faces the viewer (which is also why a turn-around is unavailable, per §0).
- **EXIT** — ears drop, gaze resumes its cycle, world resumes, it walks on. It parked the decision and carried on — which is the repo's actual rule: name it and backlog it, never block.
- **Position** — t=208–214 s.
- **Day scheme** — identical; creature-only.
- **Constraint 1** — one creature, and the second party is you.

---

## 4 · The 240 s timeline

```
 0 ────────────────── 16.1   EMPTY  (16.1 s)  ← loop seam sits mid-emptiness
16.1 ══ E1 approach ══ 34.0   overlap crosses the foot (3.0 s)  ══ 52.4
52.4 ────────────────── 66.1  EMPTY  (13.7 s)
66.1 ══ E2 approach ══ 84.0   settle · bar drops · WORLD REVERSES · pass (5.5 s) ══ 105.6
105.6 ───────────────── 120.1 EMPTY  (14.5 s)
120.1 ═ E3 approach ══ 138.0  step up · 6.9 s on the branch · step down (13 s) ══ 165.7
165.7 ───────────────── 183.5 EMPTY  (17.8 s)
183.5 ═ E4 sweep ═════ 188.0  column crosses, stride unbroken (≈3 s) ═══════════ 191.9
191.9 ───────────────── 208.0 EMPTY  (16.1 s)
208.0 ═ E5 ══════════ 214.0  WORLD STOPS · looks at you (6.0 s)
214.0 ───────────────── 240.0 EMPTY  (26.0 s)  → wraps into the 16.1 s at t=0
```

- **Empty canvas: 104.2 s = 43%.** Contiguous empty across the seam: **42.1 s** (26.0 + 16.1). The seam is therefore trivially exact — nothing is mid-gesture at t=0.
- **Salient event time: ≈28.5 s = 11.9% duty cycle.** Presence (a feature anywhere on canvas) is 52%, but for most of that a feature is a 3-cell object at the frame edge — approach *is* the composition's dominant motion, and it is free.
- **At most one feature on canvas at any t.** Enforceable as a spacing assertion in `banner-build.py`: `min pairwise strip gap ≥ 1920 + feature_width`. This is the mechanism that keeps restraint from being a matter of taste.
- **Reduced motion needs zero special-casing.** Every event is either terrain-positional (off-canvas at `translateX(0)`) or a keyframe window whose base style is its inactive state. So the `@media (prefers-reduced-motion)` block collapses to one line — no `opacity:0` exception list, unlike v5a's four. The frozen frame is t=0: the emptiest frame in the loop, which is also the best static banner. *Same artwork, provably, rather than by policy.*

---

## 5 · How the loop closes as a story

It walks. It crosses a stretch where the record says two of them were here at once, and the record resolves to one. It tries to stop; the ledger disagrees and it loses a step; it does the step again and passes. It takes a lane of its own, walks it clear of the trunk, and comes back down onto the trunk. The floor is re-laid under it mid-stride and it does not stumble. Then it stops, and looks at you, and waits — and goes back to work. Twenty-six seconds of nothing, and it begins again.

**The close is the claim.** Over 240 s you never see the walker change, and *that is the point*: nothing in the frame tells you which session you are watching. The trail runs continuously through it in both directions — prints ahead it did not make, prints behind it did. The repetition is not a video looping; it is the fact that the walk outlives any one walker. That delivers the subtitle without ever drawing two creatures, and it is the opposite of an infographic: no reading of this composition is "A connects to B", because there is no B on screen — only B's record.

---

## 6 · What I did not use, and the cut order

| Tired beat | Not used because | Replaced by |
|---|---|---|
| Shooting star | **Invisible by day** (constraint 4) — so it is structurally, not just aesthetically, wrong; and it has no cause and no exit but a fade | E4, whose rarity lives at ground level and survives both schemes |
| Drifting balloon | An object with no cause for entering and no exit but drifting off; means nothing here | E3 — a terrain arrival with a cause, a transaction and a landing |
| Floating Zzz | **Contradicts the thesis.** Idleness in this repo is not sleep, it is a `cc-reaper` classification and a closed pane. The honest render of idle is the creature ceasing to exist, which breaks the loop. "Sessions run each other" means the walk never stops | nothing — the beat is deleted, not substituted |
| Waving creature | A wave has no referent | E5 — stillness and a direct gaze, carrying `cc-blockers`/STOP-ASK. Same social beat, a real mechanism, and *available* because the sprite already faces front (§0) |

**Cut order if forced to three.**

1. **Cut E4 (THE ADVANCE) first.** Its exit is the weakest in the set (a sweep completing, not an act), its payload is a 1 px dot re-seat that I cannot promise at 6.75 px/cell, and its meaning — "a deploy that changes nothing" — is the one an audience is most likely to read as a rendering glitch. It is also the event whose property (deploys-from-git) is genuinely the least visual, i.e. the one I most had to reach for.
2. **Cut E3 (THE LANE) second.** It is the most infographic-prone thing here — a branching diagram of the landing pipeline is R1's error committed against a different subsystem — and it is the widest footprint (45.6 s of presence), so it is also the most expensive in the empty air that restraint depends on.

**The surviving three are MECE and I would ship them alone:** the walk (E1 — continuity of the record), the wall (E2 — bounded autonomy), the ask (E5 — the human). One is texture, two are readings of the single gauge, and together they need no new art beyond a footprint and a post.

---

## 7 · Build constraints my design adds (assert these, do not assume them)

1. **Every rate modulation must span an exact multiple of the 0.5 s stride** — otherwise the stride phase (`steps(1,end)`) breaks and the foot stops landing in prints. E2 = 0.5 s reverse; E5 = 6.0 s stop. ✅
2. **`strip_length = 28.8 × (strides_taken − strides_in_place)`**, and it must also divide by the ground dash pitch. A hard stop *cannot* be paid back by a later catch-up without destroying the print lock — the displacement must come out of the strip length instead. This is the non-obvious one.
3. **Phase in keyframe percentages only.** Never `animation-delay` — the freeze harness overrides it on `*`. Note v5a's starfield **currently ships authored `animation-delay` on every star** (`style="animation-delay:-1.30s"` ×N), which the v5 log says the freeze silently discards: those stars screenshot in lockstep today.
4. **Inactive state must be the base style**, not a `0%` keyframe — or reduced motion renders the event mid-gesture.
5. **Verify at 900 px, both schemes, at every event's interaction timestamp** — not `t=0` (`banner-collide.py`'s per-creature boxes caught `s3c` colliding for half a second in nineteen).
6. `scripts/banner-shots.sh <f> --times 0,240 --bg dark` → the two PNG hashes must be identical, with a guard against the empty-string false pass the doc records.