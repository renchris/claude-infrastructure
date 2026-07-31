# What makes a good clawd micro-event — the criteria, before the candidates

Written 2026-07-30, ahead of building the candidate preview page. The operator's ask, verbatim:

> create an HTML preview page of 20+ Clawd mascot micro-events / emotes before we go into
> high-fidelity integrating it into our banner. Please first research what makes sense to have an
> event/emote that is a) fun, cute, and showcases your Opus 5 beautiful design b) representative of
> our claude-infrastructure features c) has a clear and intuitive making sense beginning middle and
> end, like a story, for the entry, existing showcase and happening, and exit scene. representative
> of our claude-infrastructure is a bonus, we just want fun events/emotes over something confusing
> and abstract that users wont get that feels forced, if we can have all.

The last sentence is the ranking rule and it is a **change of priority** from where this track has
been. Every prior document in this repo optimised for *emblematic* — how much of claude-infrastructure
a beat encodes. This one says: **fun first, legible always, emblematic where it comes for free.** A
beat that is deeply representative and cryptic now LOSES to a beat that is charming and says nothing.
That inversion is recorded here because it silently invalidates the ranking in
`docs/research/repo-semantics.md`, which is otherwise still the best source list we have.

---

## 0. What was already settled, and where — do not re-derive this

Three documents already on disk carry most of the grammar. This file does not repeat them.

| Source | What it already settles |
|---|---|
| `docs/research/event-grammar.md` and `banner-microevent-grammar-2026-07-29.md` (near-duplicates) | The class taxonomy (TEXTURE / STATE / VISITOR / BEAT), the causality windows, the duty budget, the placement maths. The numeric half. |
| `docs/research/repo-semantics.md` | 14 ranked claude-infrastructure behaviours with file-level evidence and a per-candidate visual grammar. The source list. |
| `docs/research/event-adversary.md` | The adversarial pass. Its central finding is load-bearing here and quoted below. |
| `tools/banner/gen.py` — `RARE_EVENTS`, `DELETED_EVENTS` | What ships, and what was cut WITH REASONS. |

**The adversary's finding that governs this whole task:**

> semantic content and R1-safety are anti-correlated in this design space — everything that would
> make the scene mean "sessions run each other" (two agents interacting, connections, one waking
> another) is what R1 forbids. The chain is about nothing because it is only allowed to be about
> nothing.

The operator's "representative is a bonus" resolves that deadlock rather than fighting it. We stop
trying to make the beats *mean* the repo and let most of them just be a creature being alive.

---

## 1. The expressive envelope — what this sprite can and cannot do

Everything below is forced by the artwork, which is quoted from the shipping binary
(`docs/research/CLAWD_SPRITE_EXTRACTION_2026-07-29.md`), not invented:

```
x:     0 1 2 3 4 5 6 7 8 9 10
y=0      # # # # # # # # #
y=1      # # # # # # # # #
y=2    # # . # # # # # . # #     . = eye hole
y=3    # # # # # # # # # # #
y=4      # # # # # # # # #
y=5      # # # # # # # # #
y=6      #   #       #   #
y=7      #   #       #   #
```

11x8 cells, ONE flat `#D77757`, rendered **115 x 84 CSS px** at the 838 px README column.

**Three hard constraints, each of which has already caused a shipped defect:**

1. **No mouth, no brows.** Two eye holes are the entire face. Every "expression" must therefore be
   posture, or a glyph, or nothing.
2. **Bilaterally symmetric.** `scaleX(-1)` maps the sprite onto itself, so *turning to face* is
   invisible **by construction** — the adversary pass found a shipped "turn-to-face beat" that
   existed only in the code. It also means a **sideways lean carries no direction**: there is no
   front to lean toward, so a lateral shift reads as the whole image sliding. Anticipation must be
   vertical (a crouch), not lateral. (This one bit us during this session and was caught by looking
   at a render.)
3. **Fine acting does not survive the size.** The measured rule from the legibility audit: only
   **(i) a whole-body posture change of ≳30% of the silhouette**, or **(ii) a standardized glyph at
   ≥16 rendered px**, reads reliably. Limb-level and gaze-level acting does not. A prior cheer was
   authored as two arm nubs and read as **horns**.

### The channels that DO work, in order of reliability

| Channel | Why it works | Cost |
|---|---|---|
| **Arresting the walk** | The stride is a perfect 0.5 s metronome. A violated rhythm IS a transient — it needs zero new artwork. The cheapest reliable cue available. | free |
| **Whole-body squash & stretch** | Changes the silhouette, which is the only thing that survives. Keep within ~±15%: a hard-edged pixel body has no interior deformation to sell a bigger distortion, so beyond that it reads as a scaling bug. | cheap |
| **A standardized glyph above the head** | `!` `?` spark, sweat, note, heart. Decoded instantly *because* they are conventional — an invented glyph has to be learned, and there is no budget for learning at 17 px. | cheap |
| **Vertical motion** | The entire parallax world is pure horizontal translate, so the vertical channel is completely unoccupied. Any vertical move separates figure from ground instantly. | cheap |
| **Occlusion** (a mound, below the ground line, a frame edge) | Gives "gone" without "ceased to exist". The correct exit. | cheap |
| **Synchrony between two creatures** | Two bodies doing the same thing on the SAME FRAME reads as relationship with no ink drawn between them. Precedent already in the generator. | moderate |

### Tempting and unavailable — do not spend time on these

- Facial expression of any kind. There is no face.
- Turning around, facing left/right, looking at another creature. Symmetric.
- Anything communicated by a **line, thread, arc, travelling pulse, or arrow** between two things.
  A standing operator ruling ("R1") rejected the banner being a handoff/subsystem infographic, and a
  drawn connector rebuilds exactly that. This is why relationship is restricted to co-location,
  synchrony, entering/leaving frame, and acting on world furniture.
- Numbers, gauges, bars, HUD elements. Quantities have no depiction here that is not a chart.
- An opacity cross-fade as an entrance or exit. A gradual change is missed **69%** of the time even
  with no visual disruption — a fade is not an exit, it is the observer losing information. Motion
  or occlusion, or it did not happen.

---

## 2. The story test — what "beginning, middle and end" has to mean mechanically

The operator asked for entry / showcase / exit. Translated into things that can be checked:

```
ENTRY      0.15-0.30s   a transient: motion onset, or the walk arresting
           0.20-0.40s   eye-arrival slack — NOTHING important happens here
SHOWCASE   1.0 -2.0s    exactly ONE legible state change
EXIT       0.3 -0.5s    a speed change >=2x or a direction change >=30 degrees
           0.2 -0.5s    out through an edge, an occluder, or a transformation
                        => ~2.5s floor, 4-8s comfortable, ~9s ceiling
...then AIR
```

**The 0.20-0.40 s of slack is the part that gets skipped and it is not optional.** The oculomotor
budget is saccade latency ~200 ms + flight 30-50 ms + fixation/identification ~200-300 ms, so the
eye is not on target for **400-500 ms** after the cue. A beat whose payoff lands on the same frame as
its cue cannot be seen. Put the cue first and the payoff 0.5-2.0 s later, always.

**Air is a requirement, not leftover space.** "Special" is a contrast effect; a beat with no silence
around it has nothing to be special against. Each preview loop is 12 s and no story may exceed 9 s.

---

## 3. The scoring rubric used to pick candidates

| # | Test | Fails if |
|---|---|---|
| S1 | **Nameable in three words** by someone who has read nothing | it needs the caption to parse |
| S2 | **Three acts present**, with the payoff ≥0.5 s after the cue | it is a movement, not a story |
| S3 | **Legible at 332 px** via posture or glyph | the delta is limb-level |
| S4 | **Exits with agency** — motion, occlusion, or transformation | it fades out |
| S5 | **Fun to a stranger** — would someone with no context enjoy it | it is a diagram of something |
| S6 | **No connector drawn** between two entities | it is an infographic (R1) |
| S7 | **Works in BOTH colour schemes** | it only exists at night |
| S8 | *(bonus)* evokes something the repo really does, without being told | — |

S8 is the only optional row. A candidate passing S1-S7 and failing S8 is a **keeper**; a candidate
passing S8 and failing S1 or S5 is **cut**, and that is the operator's ranking made mechanical.

---

## 4. Do not re-propose these

Cut previously, with reasons recorded in `gen.py`'s `DELETED_EVENTS` and the adversary pass:

| Cut | Why |
|---|---|
| balloon | filler with no cause for entering; renders the brand asterisk as a stray object |
| shooting star | the most tired beat available, AND absent in the day scheme, so it cannot carry anything in both |
| birds | never in anyone's inventory, never reviewed, 40% duty over three passes, no story |
| Zzz / sleep | UI iconography; and idleness here is a reaper classification, not sleep |
| constellation lines | terminal cliché *and* the R1-adjacent one — "dots joined by lines in a night sky" has been the default visual of AI for a decade |

Already shipping, so not candidates: **THE SUMMONING**, **THE REFUSAL**, **THE ASK**, plus
`rOverlap`, `peek`, `peer`, `rCheer`.

---

## 5. Where the candidates come from

Four categories, ordered so a reader meets the charming ones first:

- **Idle life** — the creature alone. Needs no explanation to anybody. Highest S5, zero S8.
- **Reactions** — something happens to it. Arrest + one posture change; the most reliable shape.
- **The world** — it meets a thing or another of its kind. Carries S6 risk; disciplined by the
  synchrony/occlusion rules.
- **What it does** — the S8 tier, drawn from `repo-semantics.md`. Kept **only** where the beat is
  still fun with S8 covered up.

## 6. Open — to be integrated when the research wave lands

A five-axis research wave (cute-craft, emote catalogues, repo→action mapping, sprite capability,
page engineering) is running against this same question. Its findings are **additive** to this file
and should be INTEGRATED into the sections above rather than appended as a second opinion. Expected
to sharpen: the amplitude numbers in §1, the glyph vocabulary, and the candidate list in §5.
