---
status: complete
owner: banner-v2
created: 2026-07-29
closed: 2026-07-31
supersedes: none
---

# Banner v2 — validate the SUBJECT before building any variant

The v1 bake-off compared three **mediums** of one idea and never tested the **subject**. That is
the one check that failed. So this doc is the check: *what is the header about?* — decided before
a single SVG is written.

> **RESOLVED 2026-07-31 — the check ran, in the intended order, and the work it gated shipped.**
> The subject went to the operator before any SVG was written; the ruling was *build all three
> subjects, and variants of each* rather than a single pick. Full record in **[§ Resolution](#resolution)**
> at the foot of this doc. The **R1–R4 bindings below remain the ruling source-of-record** and are
> still enforced in code — this doc is closed, not retired, and nothing here should be deleted.

Binding: **R1** whole-system (not a handoff/subsystem infographic) · **R2** title legible at t=0
and every t, motion supplements it · **R3** seamless indefinite loop, ambient not narrative ·
**R4** the clawd pixel creature (`#D77757`, 11×8 grid), not the asterisk mark.

## The axis the options are drawn on

The README asks its own question in the third paragraph:

> **So how do you run many at once, safely, unattended?**

Three words — **many · safely · unattended** — and each is a different honest answer to "what does
this repo stand for". The three subjects below are those three answers. They are not three styles
of one idea; they make different claims, so picking one is a real decision.

All three inherit the same aesthetic, and it is **quoted, not invented** — it is the aesthetic of
the session-start scene that ships inside the Claude Code binary
(`docs/research/CLAWD_SPRITE_EXTRACTION_2026-07-29.md`): *one saturated orange subject, everything
else dim monochrome texture, a hard dotted horizon, and a lot of empty space.*

All three also inherit the same motion vocabulary, and it too is quoted: clawd's real idle pose
table — **default · look-left · look-right · arms-up** — which is an idle animation, so it loops
by construction. R3 is satisfied by the source material rather than by a contrivance.

---

## S1 · The world it lives in — *safely*

**The claim:** this repo is the *environment* a Claude session inhabits. `~/.claude` stopped being
machine state and became a place that is deployed.

One clawd, standing in the extracted landscape stretched to 1920×600: soft `░` hills, `▒`
vegetation, the hard dotted ground line running the full width. The wordmark sits on that ground
line as permanent typographic furniture — it is the horizon's label, present at t=0.

**The loop:** the creature idles through its four real poses on a slow, uneven cadence; the dim
hill texture drifts a few pixels over ~20 s. Nothing enters, nothing leaves, nothing resolves.

**Strongest at:** restraint, and honesty — it is the shipped art, extended. Lowest risk of reading
as demo-ware.
**Weakest at:** it is the least *claim-making* of the three. A mascot standing in a landscape is
handsome; it does not by itself say what the system does.

---

## S2 · The fleet — *many* — **my recommendation**

**The claim:** many sessions run at once on one machine and cannot collide. That is the property
this repo has and a dotfiles repo does not.

Three or four clawds spread along one continuous horizon, each in its own lane, each idling **out
of phase** with the others. The wordmark is centred and constant; the creatures are periphery.

**The load-bearing detail: nothing connects them.** No threads, no pulses, no exchange — drawing a
line between two of them would rebuild the handoff infographic R1 just rejected. The composition
asserts isolation: same ground, separate lanes, no contact. The absence *is* the argument.

**The loop:** each creature runs the idle pose cycle on its own period, so the composition never
repeats visibly even though every element loops; a slow ground-line shimmer travels left→right
across the full 1920 and wraps. Seamless by construction — no restart seam because there is no
narrative to restart.

**Strongest at:** it answers R1 head-on — it is *about* the whole system's defining property, and
it cannot be mistaken for a subsystem diagram.
**Weakest at:** four mascots risks twee if the density is wrong. Mitigated by lane spacing and by
keeping every creature the same size and the same orange — a population, not characters.

---

## S3 · The night shift — *unattended*

**The claim:** it runs while you are asleep, and pages you only when a human must decide.

The **night** variant of the scene — which also ships in the binary: `*` stars, a `░▓▓███▓▓░` tree
canopy over a `███▓░` trunk. One clawd awake and working under the starfield; the horizon and the
wordmark hold the baseline.

**The loop:** the starfield twinkles on long uncorrelated periods; the creature idles. Optionally
one star at the far edge pulses at a distinctly slower beat — the page that is not coming.

**Strongest at:** it is the most *evocative*, and "unattended" is the README's actual differentiator.
Also the most naturally infinite loop of the three — a night sky is the canonical ambient texture.
**Weakest at:** a dark scene under a dark plate is a narrow tonal range; and a twinkling starfield
is one step from the decorative-field failure mode. Needs the most discipline to not become
wallpaper.

---

## What I need from you

Pick one (or name a fourth). Then three **variants of that subject** get built and screenshot-
compared through `scripts/banner-shots.sh` exactly as before — the medium question is already
settled (vector), so the variants will differ in composition and density, not in encoding.

While this is open I am authoring the clawd vector geometry from the extracted 11×8 grid and the
four pose cells, which every one of the three needs.

---

## Resolution

*Answered 2026-07-29; recorded here 2026-07-31. The ask above is kept verbatim as the historical
record — this section answers it. The doc is closed against evidence rather than deleted, because
the R1–R4 bindings it fixes are still cited in code.*

**The pick: none — the operator ruled all three.** `README_HERO_BANNER.md` § Log:

> **2026-07-29 (v2)** — subject validated with the operator BEFORE any SVG was written, which is the
> check whose absence sank v1. Ruling: build all three subjects and variants of each. Nine
> candidates shipped to `assets/banner/v2/`, gate still closed.

So S2's "my recommendation" above was **not** taken as a decision, and the "pick one" framing was
overtaken by the ruling itself. The check this doc exists to run — *validate the subject before
building any variant* — did run, and it ran before a single SVG was written.

**What got built** — `e063e5d9`, nine candidates, three per subject, all present at HEAD:

| Subject | Variants |
|---|---|
| **S1** the world it lives in — *safely* | `s1a-horizon` · `s1b-close` · `s1c-scene` |
| **S2** the fleet — *many* | `s2a-lanes` · `s2b-depth` · `s2c-row` |
| **S3** the night shift — *unattended* | `s3a-starfield` · `s3b-tree` · `s3c-longwatch` |

Screenshot-compared through `assets/banner/v2/comparison.html` exactly as this doc promised, each
with a frozen near-lossless WebP still. Three defects were caught by the checks rather than by eye —
a fleet that placed three creatures and rendered two, a title collision visible only on the
arms-up pose, and night scenery sitting behind the type — all recorded in `e063e5d9`.

**"Gate still closed"** in that entry means the README header edit was deliberately withheld:
*"The README header is NOT touched — that gate is the operator's."* (`e063e5d9`)

**Where the track went next.** The v2 nine did not become the header. Work continued through v3–v6,
and the README now ships `assets/banner/v6c-dusk-line.svg`, picked in `3ff7a361`. **No lineage from
S1/S2/S3 to v6c is recorded anywhere on disk** — v6 is described as "four art directions on the
settled v5 constraint set", not as a descendant of one of these three subjects. That is left
unstated here rather than inferred from the fact that v6c happens to be a night scene.

**Nothing is stranded by closing this.** The clawd vector geometry promised in the line above was
authored and now lives in `tools/banner/gen.py`. Still-live banner work has its own docs and its own
backlog items — `README_HERO_BANNER.md` and `BANNER_NARRATIVE_SPEC.md`. R1–R4 remain enforced in
code, which carries its own copies of the rules and does not read this file at runtime:
`scripts/banner-build.py:18-25` restates all four as the build contract, `scripts/banner-collide.py`
enforces R2 at every timestamp, and `tools/banner/gen.py` cites R1 and R4.

**Why the front-matter changed.** `status: open` is what kept re-emitting this finished doc into the
autonomous dispatch wave. `bin/cc-discover`'s C2 critic (`cc-discover:167,183`) turns every row of
`find-plan.sh --list-open` into an "advance \<plan\>" backlog item, and `find-plan.sh:97` treats
**only** `complete` and `superseded` as terminal — every other value, *including an unrecognised
one*, is listed and re-dispatched. So `closed` or `decided` would have parsed to `unknown` and
changed nothing. `complete` is the value the repo's own test pins
(`tests/find-plan-list-open.bats:43`, "complete and superseded plans are EXCLUDED").
